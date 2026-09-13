#!/usr/bin/env bash
set -euo pipefail

: "${ATLAS_ENV:?dev or prod required}"
: "${PRIVATE_IP:?VPC address required}"
: "${NEO4J_IMAGE:?pinned image required}"

input=/tmp/neo4j-runtime-input
test -f "$input"
IFS= read -r NEO4J_RUNTIME_PASSWORD < "$input" || true
test -n "$NEO4J_RUNTIME_PASSWORD"
NEO4J_ADMIN_PASSWORD="$(sed -n '2p' "$input")"
if [[ -z "$NEO4J_ADMIN_PASSWORD" ]]; then
  test -f /etc/neo4j-atlas/runtime.env
  NEO4J_AUTH="$(sed -n 's/^NEO4J_AUTH=//p' /etc/neo4j-atlas/runtime.env)"
  NEO4J_ADMIN_PASSWORD="${NEO4J_AUTH#neo4j/}"
fi
export NEO4J_ADMIN_PASSWORD NEO4J_RUNTIME_PASSWORD
exec /tmp/configure-neo4j.sh
