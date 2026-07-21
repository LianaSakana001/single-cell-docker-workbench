#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 PROJECT_NAME [ENV_FILE]" >&2
  exit 2
fi

project_name=$1
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$script_dir/.." && pwd)
env_file=${2:-"$repo_dir/workbench.env"}

if [[ ! "$project_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "ERROR: project name may contain only letters, digits, dot, underscore, and hyphen" >&2
  exit 1
fi
if [[ ! -r "$env_file" ]]; then
  echo "ERROR: cannot read $env_file" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

: "${WORKSPACE_HOST:?Set WORKSPACE_HOST in workbench.env}"
target="$WORKSPACE_HOST/projects/$project_name"
if [[ -e "$target" ]]; then
  echo "ERROR: project already exists: $target" >&2
  exit 1
fi

umask 027
mkdir -p \
  "$target/notebooks" \
  "$target/scripts" \
  "$target/config" \
  "$target/data/interim" \
  "$target/data/processed" \
  "$target/results/h5ad" \
  "$target/results/figures" \
  "$target/results/tables" \
  "$target/logs" \
  "$target/tmp"
cp "$repo_dir/templates/example-project-README.md" "$target/README.md"

printf 'Created project: %s\n' "$target"
