#!/usr/bin/env bash
set -euo pipefail

echo "== Identity and mounts =="
id
test -w /workspace
test -r /inputs/input-a
test -r /inputs/input-b
test -r "${SMOKE_H5AD_PATH:?SMOKE_H5AD_PATH is unset}"
test ! -w /inputs/input-a
test ! -w /inputs/input-b
test ! -w "$SMOKE_H5AD_PATH"

probe=$(mktemp /workspace/tmp/.write-test.XXXXXX)
trap 'rm -f "$probe"' EXIT
printf 'workspace write test\n' > "$probe"

echo "== Cgroup memory limit =="
if [[ -r /sys/fs/cgroup/memory.max ]]; then
  memory_limit=$(< /sys/fs/cgroup/memory.max)
elif [[ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]]; then
  memory_limit=$(< /sys/fs/cgroup/memory/memory.limit_in_bytes)
else
  echo "ERROR: cgroup memory limit file is unavailable" >&2
  exit 1
fi
printf 'memory limit bytes=%s expected=%s\n' "$memory_limit" "$EXPECTED_MEM_LIMIT"

/opt/conda/bin/python - "$memory_limit" "$EXPECTED_MEM_LIMIT" <<'PY'
import re
import sys

actual = sys.argv[1]
expected = sys.argv[2].strip().lower()
if actual == "max":
    raise SystemExit("container memory is unlimited")

match = re.fullmatch(r"([0-9]+)([kmgt]?)b?", expected)
if not match:
    raise SystemExit(f"cannot parse EXPECTED_MEM_LIMIT={expected!r}")
value = int(match.group(1))
scale = {"": 1, "k": 1024, "m": 1024**2, "g": 1024**3, "t": 1024**4}
expected_bytes = value * scale[match.group(2)]
if int(actual) != expected_bytes:
    raise SystemExit(
        f"memory limit mismatch: actual={actual}, expected={expected_bytes}"
    )
PY

echo "== GPU =="
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader

echo "== Python =="
/opt/conda/bin/python - <<'PY'
import importlib.metadata as md
import os

import anndata
import cupy
import rapids_singlecell
import scanpy

print("python packages:")
for name in ("anndata", "scanpy", "rapids-singlecell", "cupy", "notebook", "harmonypy"):
    try:
        print(f"  {name}={md.version(name)}")
    except md.PackageNotFoundError:
        print(f"  {name}=MISSING")

print("cupy devices:", cupy.cuda.runtime.getDeviceCount())
gpu_probe = cupy.arange(10, dtype=cupy.float32).sum()
print("cupy kernel probe:", float(gpu_probe.get()))

h5ad_path = os.environ["SMOKE_H5AD_PATH"]
adata = anndata.read_h5ad(h5ad_path, backed="r")
try:
    print("backed h5ad shape:", adata.shape)
finally:
    adata.file.close()
PY

echo "== R =="
/opt/conda/bin/conda run -n r-sc Rscript -e \
  'pkgs <- c("Seurat", "SingleCellExperiment", "edgeR", "limma", "harmony"); missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]; if (length(missing)) stop("Missing R packages: ", paste(missing, collapse = ", ")); cat("R=", R.version.string, "\n", sep = ""); for (pkg in pkgs) cat(pkg, "=", as.character(packageVersion(pkg)), "\n", sep = "")'

echo "Smoke test passed."
