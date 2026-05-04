#!/usr/bin/env bash
set -euo pipefail

workspace_root="${WORKSPACE_ROOT:-/workspace}"
mkdir -p "${workspace_root}"
cd "${workspace_root}"

if [ "$#" -eq 0 ]; then
  exec bash
fi

exec "$@"
