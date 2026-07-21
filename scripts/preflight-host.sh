#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "$script_dir/.." && pwd)
env_file=${1:-"$project_dir/workbench.env"}

if [[ "$env_file" != /* ]]; then
  env_file="$project_dir/$env_file"
fi
if [[ ! -r "$env_file" ]]; then
  echo "ERROR: cannot read $env_file" >&2
  echo "Copy workbench.env.example to workbench.env and fill it first." >&2
  exit 1
fi

set -a
# The registry is a trusted, local shell-compatible env file.
# shellcheck disable=SC1090
source "$env_file"
set +a

required_vars=(
  COMPOSE_PROJECT_NAME CONTAINER_NAME IMAGE_NAME IMAGE_TAG BASE_IMAGE
  HOST_UID HOST_GID HOST_EXTRA_GID CONTAINER_USER
  WORKSPACE_HOST INPUT_A_HOST INPUT_B_HOST INPUT_FILE_HOST INPUT_FILE_NAME
  MEM_LIMIT MEMSWAP_LIMIT SHM_SIZE CPU_LIMIT THREAD_LIMIT
)

for name in "${required_vars[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: $name is empty in $env_file" >&2
    exit 1
  fi
done

for name in HOST_UID HOST_GID HOST_EXTRA_GID; do
  if [[ ! "${!name}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: $name must be a numeric ID" >&2
    exit 1
  fi
done

if [[ ! "$CONTAINER_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "ERROR: CONTAINER_USER is not a safe Linux username" >&2
  exit 1
fi
if [[ "$INPUT_FILE_NAME" == */* || "$INPUT_FILE_NAME" != *.h5ad ]]; then
  echo "ERROR: INPUT_FILE_NAME must be a basename ending in .h5ad" >&2
  exit 1
fi

reject_broad_path() {
  local name=$1 path=${2%/}
  case "$path" in
    ""|/|/home|/data|/srv|/mnt|/media|/Users)
      echo "ERROR: $name points to an unsafe broad root: $2" >&2
      exit 1
      ;;
  esac
}

check_dir() {
  local path=$1 mode=$2
  [[ -d "$path" ]] || { echo "ERROR: missing directory: $path" >&2; exit 1; }
  [[ -r "$path" ]] || { echo "ERROR: unreadable directory: $path" >&2; exit 1; }
  if [[ "$mode" == rw && ! -w "$path" ]]; then
    echo "ERROR: directory is not writable: $path" >&2
    exit 1
  fi
  printf 'OK   %-2s directory %s\n' "$mode" "$path"
}

check_file() {
  local path=$1
  [[ -f "$path" && -r "$path" ]] || {
    echo "ERROR: missing or unreadable file: $path" >&2
    exit 1
  }
  printf 'OK   ro file      %s\n' "$path"
}

echo "== Identity =="
printf 'host user=%s uid=%s gid=%s groups=%s\n' \
  "$(id -un)" "$(id -u)" "$(id -g)" "$(id -Gn)"
[[ "$(id -un)" == "$CONTAINER_USER" ]] || {
  echo "ERROR: CONTAINER_USER does not match the current host account" >&2
  exit 1
}
[[ "$(id -u)" == "$HOST_UID" ]] || {
  echo "ERROR: HOST_UID does not match the current host account" >&2
  exit 1
}
[[ "$(id -g)" == "$HOST_GID" ]] || {
  echo "ERROR: HOST_GID does not match the current host account" >&2
  exit 1
}
case " $(id -G) " in
  *" $HOST_EXTRA_GID "*) ;;
  *)
    echo "ERROR: current account is not a member of HOST_EXTRA_GID=$HOST_EXTRA_GID" >&2
    exit 1
    ;;
esac

echo "== Host paths =="
reject_broad_path WORKSPACE_HOST "$WORKSPACE_HOST"
reject_broad_path INPUT_A_HOST "$INPUT_A_HOST"
reject_broad_path INPUT_B_HOST "$INPUT_B_HOST"
reject_broad_path INPUT_FILE_HOST "$INPUT_FILE_HOST"
check_dir "$WORKSPACE_HOST" rw
check_dir "$INPUT_A_HOST" ro
check_dir "$INPUT_B_HOST" ro
check_file "$INPUT_FILE_HOST"

workspace_real=$(realpath -e "$WORKSPACE_HOST")
for input_path in "$INPUT_A_HOST" "$INPUT_B_HOST" "$INPUT_FILE_HOST"; do
  input_real=$(realpath -e "$input_path")
  if [[ "$input_real" == "$workspace_real" ||
        "$input_real" == "$workspace_real/"* ||
        "$workspace_real" == "$input_real/"* ]]; then
    echo "ERROR: writable workspace overlaps a read-only input: $input_path" >&2
    exit 1
  fi
done

echo "== Docker and GPU =="
printf 'Docker context=%s\n' "$(docker context show)"
docker version --format 'Docker client={{.Client.Version}} server={{.Server.Version}}'
docker compose version
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader

echo "== Compose syntax =="
docker compose --env-file "$env_file" -f "$project_dir/compose.yaml" config --quiet
echo "OK   compose configuration is valid"

echo "Preflight passed. No image was pulled, built, started, or modified."
