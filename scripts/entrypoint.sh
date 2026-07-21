#!/usr/bin/env bash
set -euo pipefail

umask "${WORKBENCH_UMASK:-027}"

if [[ ! -d /workspace || ! -w /workspace ]]; then
  echo "ERROR: /workspace is missing or not writable by $(id -u):$(id -g)." >&2
  exit 1
fi

# Maintain only workbench-level infrastructure. Project directories are created
# explicitly with ./workbench init-project and are never rewritten at startup.
mkdir -p \
  /workspace/projects \
  /workspace/tmp \
  /workspace/.cache/numba \
  /workspace/.cache/matplotlib \
  /workspace/.conda/envs \
  /workspace/.conda/pkgs \
  /workspace/.jupyter \
  /workspace/.R/library

exec "$@"
