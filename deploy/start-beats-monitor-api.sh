#!/usr/bin/env bash
set -Eeuo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE="$DIR/node/bin/node"

if [ ! -x "$NODE" ]; then
  echo "Missing Node runtime: $NODE" >&2
  exit 1
fi

exec "$NODE" "$DIR/beats-monitor-api.js"
