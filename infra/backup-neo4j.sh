#!/usr/bin/env bash
set -euo pipefail
: "${NEO4J_IMAGE:?required}"
: "${SPACES_BUCKET:?required}"
: "${SPACES_ENDPOINT:?required}"
: "${AWS_CLI_IMAGE:=amazon/aws-cli:2.15.0}"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
docker stop atlas-neo4j
trap 'docker start atlas-neo4j >/dev/null' EXIT
docker run --rm --volume=/mnt/neo4j/data:/data --volume=/mnt/neo4j/backups:/backups \
  "${NEO4J_IMAGE}" neo4j-admin database dump system --to-path=/backups --overwrite-destination=true
docker run --rm --volume=/mnt/neo4j/data:/data --volume=/mnt/neo4j/backups:/backups \
  "${NEO4J_IMAGE}" neo4j-admin database dump neo4j --to-path=/backups --overwrite-destination=true
sha256sum /mnt/neo4j/backups/*.dump > "/mnt/neo4j/backups/${stamp}.sha256"
docker run --rm \
  --env AWS_ACCESS_KEY_ID --env AWS_SECRET_ACCESS_KEY \
  --volume /mnt/neo4j/backups:/backups:ro \
  "${AWS_CLI_IMAGE}" s3 cp /backups "s3://${SPACES_BUCKET}/neo4j/${stamp}/" \
  --recursive --endpoint-url "${SPACES_ENDPOINT}" --only-show-errors
