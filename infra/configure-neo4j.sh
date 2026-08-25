#!/usr/bin/env bash
set -euo pipefail
: "${ATLAS_ENV:?dev or prod required}"
: "${PRIVATE_IP:?VPC address required}"
: "${NEO4J_PASSWORD:?initial admin password required}"
: "${NEO4J_IMAGE:?pinned image required}"
if [[ "${ATLAS_ENV}" == "prod" ]]; then heap="3g"; pagecache="3g"; else heap="1500m"; pagecache="1500m"; fi
install -d -m 0700 /etc/neo4j-atlas
umask 077
printf 'NEO4J_AUTH=neo4j/%s\n' "${NEO4J_PASSWORD}" > /etc/neo4j-atlas/runtime.env
docker pull "${NEO4J_IMAGE}"
docker rm -f atlas-neo4j >/dev/null 2>&1 || true
docker run -d --name atlas-neo4j --restart unless-stopped \
  --env-file /etc/neo4j-atlas/runtime.env \
  --env NEO4J_server_memory_heap_initial__size="${heap}" \
  --env NEO4J_server_memory_heap_max__size="${heap}" \
  --env NEO4J_server_memory_pagecache_size="${pagecache}" \
  --env NEO4J_server_default__listen__address=0.0.0.0 \
  --publish "${PRIVATE_IP}:7687:7687" \
  --volume /mnt/neo4j/data:/data --volume /mnt/neo4j/logs:/logs \
  "${NEO4J_IMAGE}"
unset NEO4J_PASSWORD
