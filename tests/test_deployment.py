import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("gpu_stack", ROOT / "scripts/check-gpu-stack.py")
GPU_STACK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GPU_STACK)


class CudaCompatibilityTests(unittest.TestCase):
    def test_matching_base_is_accepted(self):
        self.assertEqual(GPU_STACK.compatibility_errors("12.9.7", "cuda12_py314_build", "12.9.7"), [])

    def test_pip_cuda13_over_cuda12_base_is_rejected(self):
        errors = GPU_STACK.compatibility_errors("13.4.4", "cuda12_py314_build", "12.9.7")
        self.assertTrue(any("CUDA 12 build" in error for error in errors))
        self.assertTrue(any("Conda records" in error for error in errors))

    def test_same_family_replacement_is_reported(self):
        self.assertTrue(GPU_STACK.compatibility_errors("12.9.8", "cuda12_py314_build", "12.9.7"))

    def test_unknown_core_build_is_rejected(self):
        self.assertTrue(GPU_STACK.compatibility_errors("12.9.7", "unidentified", "12.9.7"))


class NoninteractiveWrapperTests(unittest.TestCase):
    def run_wrapper(self, arguments):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            docker = folder / "docker"
            docker.write_text("#!/usr/bin/env python3\nimport json, sys\nprint(json.dumps(sys.argv[1:]))\n")
            docker.chmod(0o755)
            registry = folder / "registry.env"
            registry.touch()
            env = os.environ.copy()
            env["PATH"] = str(folder) + os.pathsep + env["PATH"]
            env["WORKBENCH_ENV_FILE"] = str(registry)
            result = subprocess.run(
                ["bash", str(ROOT / "workbench"), *arguments],
                input="", capture_output=True, text=True, check=True, env=env,
            )
            return json.loads(result.stdout)

    def test_smoke_runs_without_a_tty(self):
        args = self.run_wrapper(["smoke"])
        self.assertEqual(args[args.index("exec"):], ["exec", "-T", "--interactive=false", "workbench", "single-cell-workbench-smoke-test"])

    def test_exec_preserves_command_arguments_without_a_tty(self):
        args = self.run_wrapper(["exec", "python", "-c", "print('a b')"])
        self.assertEqual(args[args.index("exec"):], ["exec", "-T", "--interactive=false", "workbench", "python", "-c", "print('a b')"])


if __name__ == "__main__":
    unittest.main()
