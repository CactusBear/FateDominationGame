"""Targeted closure completion contract; reuse the existing owned Job/E-drive runner."""
import importlib.util
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "match_lifecycle_owned_runner", ROOT / "newtests/run_f09_match_lifecycle_inbox_contract.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
runner.FILES = (
    "scripts/net/session/host_match_request_inbox.gd",
    "newtests/f09_match_closure_completion_contract_test.gd",
    "newtests/f09_match_closure_completion_contract_test.tscn",
)
runner.SCENE = "res://newtests/f09_match_closure_completion_contract_test.tscn"
runner.EXPECTED_CHECKS = 53

if __name__ == "__main__":
    sys.exit(runner.main())
