#!/usr/bin/env bash
set -euo pipefail

: "${NEO4J_IMAGE:?pinned image required}"
input=/tmp/neo4j-backup-input
test -f "$input"
mapfile -t values < "$input"
if [[ ${#values[@]} -ne 4 ]] || [[ -z "${values[0]}" || -z "${values[1]}" || -z "${values[2]}" || -z "${values[3]}" ]]; then
  echo "Neo4j backup input is incomplete" >&2
  exit 1
fi
export SPACES_BUCKET="${values[0]}"
export SPACES_ENDPOINT="${values[1]}"
export SPACES_ACCESS_KEY_ID="${values[2]}"
export SPACES_SECRET_ACCESS_KEY="${values[3]}"
exec /tmp/install-neo4j-backup.sh
