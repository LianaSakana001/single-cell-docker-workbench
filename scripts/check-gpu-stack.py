#!/usr/bin/env python3
"""Check CUDA Python metadata without importing CUDA or using a GPU."""

import argparse
import importlib.metadata as metadata
import json
import os
from pathlib import Path
import re
import sys


def compatibility_errors(bindings_version, core_build, recorded_bindings):
    errors = []
    match = re.search(r"cuda(\d+)(?:_|$)", core_build)
    if not match:
        errors.append(f"Cannot identify the CUDA family of cuda-core build {core_build!r}")
    elif bindings_version.split(".", 1)[0] != match.group(1):
        errors.append(
            f"cuda-core is a CUDA {match.group(1)} build, but Python sees "
            f"cuda-bindings {bindings_version}"
        )
    if bindings_version != recorded_bindings:
        errors.append(
            f"Conda records cuda-bindings {recorded_bindings}, but Python sees "
            f"{bindings_version}; a pip install may have replaced the base package"
        )
    return errors


def conda_record(prefix, name):
    records = []
    for path in (prefix / "conda-meta").glob(f"{name}-*.json"):
        record = json.loads(path.read_text())
        if record.get("name") == name:
            records.append(record)
    if len(records) != 1:
        raise ValueError(f"Expected one Conda record for {name}, found {len(records)}")
    return records[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-cuda-path", action="store_true")
    args = parser.parse_args()
    try:
        prefix = Path(sys.prefix)
        bindings = metadata.version("cuda-bindings")
        core = conda_record(prefix, "cuda-core")
        recorded = conda_record(prefix, "cuda-bindings")["version"]
        print(f"cuda-core={metadata.version('cuda-core')} build={core['build']}", flush=True)
        print(f"cuda-bindings={bindings} conda-record={recorded}", flush=True)
        errors = compatibility_errors(bindings, core["build"], recorded)
        if args.check_cuda_path:
            cuda_path = os.environ.get("CUDA_PATH", "")
            print(f"CUDA_PATH={cuda_path or 'UNSET'}", flush=True)
            if not cuda_path or not (Path(cuda_path) / "include" / "cuda.h").is_file():
                errors.append("CUDA_PATH must point to the Conda CUDA toolkit containing include/cuda.h")
        if errors:
            raise ValueError("; ".join(errors))
    except (ValueError, OSError, KeyError, metadata.PackageNotFoundError) as error:
        print(f"ERROR: incompatible GPU environment: {error}", file=sys.stderr)
        print("Rebuild with the matching CUDA constraints; do not change data permissions or the host driver.", file=sys.stderr)
        return 1
    print("GPU package metadata checks passed (no GPU computation performed).", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
