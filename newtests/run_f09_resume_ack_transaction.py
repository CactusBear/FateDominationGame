"""Run only the synthetic resume-ack transaction scene in an owned E-drive project."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import uuid

REPO = Path(__file__).resolve().parents[1]
ENGINE = Path("E:/scratch/round51-engine/Godot_v4.7.2-stable_win64_console.exe")
OWNED = (
    "scripts/net/identity/resume_ack_transaction.gd",
    "newtests/f09_resume_ack_transaction_test.gd",
    "newtests/f09_resume_ack_transaction_test.tscn",
)


def main():
    scratch = Path("C:/Users/Administrator/AppData/Local/hermes/cache/scratch").resolve()
    if scratch.drive.lower() != "e:":
        raise RuntimeError("Scratch must physically resolve to E drive")
    owner = scratch / ("resume-ack-" + uuid.uuid4().hex)
    project = owner / "project"
    project.mkdir(parents=True)
    for relative in OWNED:
        source = REPO / relative
        if source.exists():
            destination = project / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
    if sys.argv[1:] not in ([], ["--red-missing-rollback"]):
        raise RuntimeError("Only --red-missing-rollback is supported")
    mutation = bool(sys.argv[1:])
    if mutation:
        script = project / OWNED[0]
        source = script.read_text(encoding="utf-8")
        anchor = "\t\tprevious_hashes[member] = previous\n"
        if source.count(anchor) != 1:
            raise RuntimeError("Owned rollback mutation anchor changed")
        script.write_text(source.replace(anchor, "\t\tpass # Owned RED mutation only\n"), encoding="utf-8")
    (project / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="ResumeAckSynthetic"\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8"
    )
    env = os.environ.copy()
    for name in ("APPDATA", "LOCALAPPDATA", "TEMP", "TMP", "TMPDIR"):
        folder = owner / "runtime" / name.lower()
        folder.mkdir(parents=True)
        env[name] = str(folder)
    command = [str(ENGINE), "--headless", "--fixed-fps", "60", "--path", str(project),
               "--scene", "res://newtests/f09_resume_ack_transaction_test.tscn"]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, encoding="utf-8", errors="replace", env=env)
    try:
        stdout, stderr = process.communicate(timeout=180)
    except subprocess.TimeoutExpired:
        subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
        stdout, stderr = process.communicate()
        (owner / "stdout.log").write_text(stdout, encoding="utf-8")
        (owner / "stderr.log").write_text(stderr, encoding="utf-8")
        print("Owned resume-ack test timed out; evidence=" + str(owner))
        return 124
    (owner / "stdout.log").write_text(stdout, encoding="utf-8")
    (owner / "stderr.log").write_text(stderr, encoding="utf-8")
    results = [json.loads(line[7:]) for line in stdout.splitlines() if line.startswith("RESULT ")]
    passed = (process.returncode == 0 and len(results) == 1 and
              isinstance(results[0].get("checks"), int) and results[0]["checks"] > 0 and
              results[0].get("failures") == [] and
              not any(marker in stdout + stderr for marker in ("SCRIPT ERROR", "ERROR:")))
    report = {"command":command,"pid":process.pid,"exit_code":process.returncode,
              "passed":passed,"results":results,"evidence":str(owner),"mutation":mutation,
              "scope":"synthetic primitive only; no Session/network/native DLL test"}
    (owner / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(stdout, end="")
    print(stderr, end="", file=sys.stderr)
    print(json.dumps(report, ensure_ascii=False))
    shutil.rmtree(project)
    shutil.rmtree(owner / "runtime")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
