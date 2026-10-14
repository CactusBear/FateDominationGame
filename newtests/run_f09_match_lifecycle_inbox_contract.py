"""Run only the stateless match lifecycle inbox contract in an owned Windows Job."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
ENGINE = Path("E:/scratch/round51-engine/Godot_v4.7.2-stable_win64_console.exe")
FILES = (
    "scripts/net/session/host_match_request_inbox.gd",
    "newtests/f09_match_lifecycle_inbox_contract_test.gd",
    "newtests/f09_match_lifecycle_inbox_contract_test.tscn",
)
SESSION = ROOT / "scripts/net/session/lobby_session.gd"
SCENE = "res://newtests/f09_match_lifecycle_inbox_contract_test.tscn"
EXPECTED_CHECKS = 16


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if len(sys.argv) != 2 or not sys.argv[1].replace("-", "").isalnum():
        raise ValueError("Provide one evidence label")
    spec = importlib.util.spec_from_file_location("owned_runner", ROOT / "tools/run_isolated_godot_test.py")
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    engine = runner.physical_e(ENGINE)
    if not engine.is_file():
        raise FileNotFoundError(engine)
    token = uuid.uuid4().hex
    owner = runner.physical_e(Path("E:/scratch")) / ("isolated-" + token)
    generated = owner / "generated"
    project = generated / "project"
    evidence = owner / "evidence"
    project.mkdir(parents=True)
    evidence.mkdir()
    session_before = digest(SESSION)
    report = {"run_id":token,"generated":str(generated),"label":sys.argv[1],"processes":[],
              "source_sha256":{},"session_sha256_before":session_before,"passed":False}
    for name in FILES:
        source = ROOT / name
        destination = project / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        report["source_sha256"][name] = digest(source)
        if digest(destination) != digest(source):
            raise RuntimeError("Freeze mismatch: " + name)
    (project / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="MatchLifecycleInboxContract"\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
    env = os.environ.copy()
    for key in ("APPDATA", "LOCALAPPDATA", "TEMP", "TMP", "TMPDIR"):
        directory = generated / key.lower()
        directory.mkdir()
        env[key] = str(directory)
    command = [str(engine),"--headless","--fixed-fps","60","--path",str(project),
               "--scene",SCENE]
    report["watchdog_seconds"] = 300
    report["status"] = "failed"
    try:
        stdout, stderr, code = runner.execute(command, env, generated, evidence, "contract",
            {"seconds":300,"bytes":1500000000,"min_free":2000000000},report["processes"])
        report["analysis"] = runner.analyze(stdout,stderr,code)
        report["CHECK"] = sum(line.startswith("CHECK ") for line in stdout.splitlines())
        report["expected_CHECK"] = EXPECTED_CHECKS
        user_paths = [line.removeprefix("USER_DATA_PATH ") for line in stdout.splitlines()
                      if line.startswith("USER_DATA_PATH ")]
        if len(user_paths) != 1:
            raise ValueError("Missing unique actual Godot user directory")
        user_path = runner.physical_e(Path(user_paths[0]))
        runner.contained(user_path, generated)
        report["actual_user_data_path"] = str(user_path)
        report["physical_E_user_data_verified"] = True
        report["ERROR"] = [line for line in (stdout+stderr).splitlines() if "ERROR" in line]
        report["exit"] = code
        report["Job0"] = bool(report["processes"]) and all(row.get("exited") is True and row.get("active_owned_processes") == 0
            and row.get("log_handles_released") is True for row in report["processes"])
        report["session_sha256_after"] = digest(SESSION)
        report["session_unchanged_during_run"] = session_before == digest(SESSION)
        report["source_unchanged_during_run"] = all(digest(ROOT/name) == value for name,value in report["source_sha256"].items())
        report["passed"] = (report["analysis"]["passed"] and report["CHECK"] == EXPECTED_CHECKS
                            and not report["ERROR"] and report["Job0"]
                            and report["source_unchanged_during_run"]
                            and report["session_unchanged_during_run"])
        report["status"] = "passed" if report["passed"] else "failed"
        print(stdout, end="")
        print(stderr, end="", file=sys.stderr)
    except Exception as exc:
        report["error"] = repr(exc)
        if any(row.get("budget_failure") == "timeout" for row in report["processes"]):
            report["status"] = "inconclusive"
        report["Job0"] = bool(report["processes"]) and all(
            row.get("exited") is True and row.get("active_owned_processes") == 0
            and row.get("log_handles_released") is True for row in report["processes"])
    finally:
        report["evidence"] = str(evidence)
        (owner / "manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2),encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    if report.get("Job0"):
        runner.delete_owned(generated, owner)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
