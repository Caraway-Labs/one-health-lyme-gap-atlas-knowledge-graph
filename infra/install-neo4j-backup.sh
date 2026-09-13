#!/usr/bin/env bash
set -euo pipefail

: "${NEO4J_IMAGE:?pinned image required}"
: "${SPACES_BUCKET:?private backup bucket required}"
: "${SPACES_ENDPOINT:?Spaces endpoint required}"
: "${SPACES_ACCESS_KEY_ID:?Spaces access key required}"
: "${SPACES_SECRET_ACCESS_KEY:?Spaces secret key required}"

install -d -m 0700 /etc/neo4j-atlas
install -d -o 7474 -g 7474 -m 0700 /mnt/neo4j/backups
umask 077
cat > /etc/neo4j-atlas/backup.env <<EOF
NEO4J_IMAGE=${NEO4J_IMAGE}
AWS_CLI_IMAGE=amazon/aws-cli:2.15.0
SPACES_BUCKET=${SPACES_BUCKET}
SPACES_ENDPOINT=${SPACES_ENDPOINT}
AWS_ACCESS_KEY_ID=${SPACES_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${SPACES_SECRET_ACCESS_KEY}
EOF
install -m 0750 "$(dirname "$0")/backup-neo4j.sh" /usr/local/sbin/backup-neo4j

cat > /etc/systemd/system/neo4j-atlas-backup.service <<'EOF'
[Unit]
Description=One Health Lyme Atlas Neo4j logical backup
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
EnvironmentFile=/etc/neo4j-atlas/backup.env
ExecStart=/usr/local/sbin/backup-neo4j
EOF

cat > /etc/systemd/system/neo4j-atlas-backup.timer <<'EOF'
[Unit]
Description=Daily One Health Lyme Atlas Neo4j backup

[Timer]
OnCalendar=*-*-* 10:30:00 UTC
Persistent=true
Unit=neo4j-atlas-backup.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now neo4j-atlas-backup.timer
unset SPACES_ACCESS_KEY_ID SPACES_SECRET_ACCESS_KEY
