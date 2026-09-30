#!/usr/bin/env bash
set -euo pipefail
: "${ATLAS_ENV:?dev or prod required}"
: "${PRIVATE_IP:?VPC address required}"
: "${NEO4J_ADMIN_PASSWORD:?initial admin password required}"
: "${NEO4J_RUNTIME_PASSWORD:?shared graph runtime password required}"
: "${NEO4J_IMAGE:?pinned image required}"
if [[ "$NEO4J_ADMIN_PASSWORD" == *"/"* || "$NEO4J_ADMIN_PASSWORD" == *$'\r'* || "$NEO4J_ADMIN_PASSWORD" == *$'\n'* ]]; then
  echo "NEO4J_ADMIN_PASSWORD contains a character that cannot be represented in NEO4J_AUTH" >&2
  exit 1
fi
if [[ "$NEO4J_RUNTIME_PASSWORD" == *"'"* || "$NEO4J_RUNTIME_PASSWORD" == *"\\"* || "$NEO4J_RUNTIME_PASSWORD" == *$'\r'* || "$NEO4J_RUNTIME_PASSWORD" == *$'\n'* ]]; then
  echo "NEO4J_RUNTIME_PASSWORD contains a character that cannot be represented in the bootstrap query" >&2
  exit 1
fi
if [[ "${ATLAS_ENV}" == "prod" ]]; then heap="3g"; pagecache="3g"; else heap="1500m"; pagecache="1500m"; fi
install -d -m 0700 /etc/neo4j-atlas
umask 077
printf 'NEO4J_AUTH=neo4j/%s\n' "${NEO4J_ADMIN_PASSWORD}" > /etc/neo4j-atlas/runtime.env
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

for _ in $(seq 1 30); do
  if docker exec --env NEO4J_PASSWORD="${NEO4J_ADMIN_PASSWORD}" atlas-neo4j \
    cypher-shell -u neo4j 'RETURN 1' >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
docker exec --env NEO4J_PASSWORD="${NEO4J_ADMIN_PASSWORD}" atlas-neo4j \
  cypher-shell -u neo4j 'RETURN 1' >/dev/null
runtime_user_file="$(mktemp)"
trap 'rm -f "$runtime_user_file"; docker exec atlas-neo4j rm -f /tmp/runtime-user.cypher >/dev/null 2>&1 || true' EXIT
umask 077
printf "CREATE USER graph_runtime IF NOT EXISTS SET PASSWORD '%s' CHANGE NOT REQUIRED;\n" \
  "${NEO4J_RUNTIME_PASSWORD}" > "$runtime_user_file"
docker cp "$runtime_user_file" atlas-neo4j:/tmp/runtime-user.cypher
docker exec --env NEO4J_PASSWORD="${NEO4J_ADMIN_PASSWORD}" atlas-neo4j \
  cypher-shell -u neo4j --file /tmp/runtime-user.cypher
if ! docker exec --env NEO4J_PASSWORD="${NEO4J_RUNTIME_PASSWORD}" atlas-neo4j \
  cypher-shell -u graph_runtime 'RETURN 1' >/dev/null 2>&1; then
  printf "ALTER USER graph_runtime SET PASSWORD '%s' CHANGE NOT REQUIRED;\n" \
    "${NEO4J_RUNTIME_PASSWORD}" > "$runtime_user_file"
  docker cp "$runtime_user_file" atlas-neo4j:/tmp/runtime-user.cypher
  docker exec --env NEO4J_PASSWORD="${NEO4J_ADMIN_PASSWORD}" atlas-neo4j \
    cypher-shell -u neo4j --file /tmp/runtime-user.cypher
fi
unset NEO4J_ADMIN_PASSWORD NEO4J_RUNTIME_PASSWORD
