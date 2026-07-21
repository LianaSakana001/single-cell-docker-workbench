#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$script_dir/.." && pwd)
cd "$repo_dir"

git rev-parse --is-inside-work-tree >/dev/null

bad_env=$(git ls-files | grep -E '(^|/)(workbench\.env|[^/]+\.env)$' || true)
if [[ -n "$bad_env" ]]; then
  echo "ERROR: tracked private env file(s):" >&2
  printf '%s\n' "$bad_env" >&2
  exit 1
fi

secret_pattern='(gh[pousr]_[A-Za-z0-9]{20,}|github[_]pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY)'
if git grep -nE "$secret_pattern" -- . ':(exclude)scripts/release-audit.sh'; then
  echo "ERROR: possible credential or private key found" >&2
  exit 1
fi

private_path_pattern='(^|[[:space:]="(])/(home|Users|data)/[A-Za-z0-9._-]+'
if git grep -nE "$private_path_pattern" -- . ':(exclude)scripts/release-audit.sh'; then
  echo "ERROR: possible user-specific absolute path found" >&2
  exit 1
fi

if git grep -nE 'FILL[_]ME' -- . ':(exclude)scripts/release-audit.sh'; then
  echo "ERROR: unresolved placeholder found" >&2
  exit 1
fi

echo "Release audit passed."
