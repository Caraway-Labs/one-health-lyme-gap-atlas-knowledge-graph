#!/usr/bin/env bash
set -euo pipefail
: "${NEO4J_IMAGE:?required}"
: "${SPACES_BUCKET:?required}"
: "${SPACES_ENDPOINT:?required}"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
docker stop atlas-neo4j
trap 'docker start atlas-neo4j >/dev/null' EXIT
docker run --rm --volume=/mnt/neo4j/data:/data --volume=/mnt/neo4j/backups:/backups \
  "${NEO4J_IMAGE}" neo4j-admin database dump system --to-path=/backups --overwrite-destination=true
docker run --rm --volume=/mnt/neo4j/data:/data --volume=/mnt/neo4j/backups:/backups \
  "${NEO4J_IMAGE}" neo4j-admin database dump neo4j --to-path=/backups --overwrite-destination=true
sha256sum /mnt/neo4j/backups/*.dump > "/mnt/neo4j/backups/${stamp}.sha256"
aws s3 cp /mnt/neo4j/backups "s3://${SPACES_BUCKET}/neo4j/${stamp}/" \
  --recursive --endpoint-url "${SPACES_ENDPOINT}" --only-show-errors
