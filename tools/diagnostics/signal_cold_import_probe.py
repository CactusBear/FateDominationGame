"""Round37 cold-import probe for the signaling GDExtension.

This diagnostic owns only its explicit E: scratch root. It never edits the source
project, the release tools, or the native DLL. Each candidate is created once in
a fresh directory and imported once; a warm re-entry is intentionally absent.
"""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

GODOT_APP_ERROR_PROVIDER = "Application Error"
APP_ERROR_NS = {"e": "http://schemas.microsoft.com/win/2004/08/events/event"}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def ensure_physical_e(path: Path) -> Path:
    path = path.resolve()
    if path.drive.upper() != "E:":
        raise ValueError(f"diagnostic root must be on physical E:, got {path}")
    return path


def windows_creation_filetime(pid: int) -> int | None:
    """Read the process creation FILETIME and close the process handle."""
    if os.name != "nt":
        return None
    PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.OpenProcess.argtypes = [ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong]
    kernel32.OpenProcess.restype = ctypes.c_void_p
    kernel32.GetProcessTimes.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
    kernel32.GetProcessTimes.restype = ctypes.c_int
    kernel32.CloseHandle.argtypes = [ctypes.c_void_p]
    kernel32.CloseHandle.restype = ctypes.c_int
    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid)
    if not handle:
        return None
    try:
        class FILETIME(ctypes.Structure):
            _fields_ = [("dwLowDateTime", ctypes.c_uint32), ("dwHighDateTime", ctypes.c_uint32)]
        created = FILETIME()
        exit_time = FILETIME()
        kernel_time = FILETIME()
        user_time = FILETIME()
        if not kernel32.GetProcessTimes(handle, ctypes.byref(created), ctypes.byref(exit_time), ctypes.byref(kernel_time), ctypes.byref(user_time)):
            return None
        return (created.dwHighDateTime << 32) | created.dwLowDateTime
    finally:
        kernel32.CloseHandle(handle)


def run_event_query() -> list[dict]:
    query = "*[System[(Provider[@Name='Application Error']) and (EventID=1000)]]"
    completed = subprocess.run(
        ["wevtutil.exe", "qe", "Application", f"/q:{query}", "/f:xml", "/c:1000"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    events: list[dict] = []
    for block in re.findall(r"<Event xmlns=.*?</Event>", completed.stdout, re.S):
        try:
            root = ET.fromstring(block)
        except ET.ParseError:
            continue
        provider = root.find("e:System/e:Provider", APP_ERROR_NS)
        if provider is None or provider.attrib.get("Name") != GODOT_APP_ERROR_PROVIDER:
            continue
        system = root.find("e:System", APP_ERROR_NS)
        data = {
            node.attrib.get("Name", ""): node.text or ""
            for node in root.findall("e:EventData/e:Data", APP_ERROR_NS)
        }
        events.append({
            "event_record_id": system.findtext("e:EventRecordID", "", APP_ERROR_NS) if system is not None else "",
            "time_created_utc": (
                system.find("e:TimeCreated", APP_ERROR_NS).attrib.get("SystemTime", "")
                if system is not None and system.find("e:TimeCreated", APP_ERROR_NS) is not None else ""
            ),
            "app_name": data.get("AppName", ""),
            "process_id_hex": data.get("ProcessId", ""),
            "process_creation_filetime_hex": data.get("ProcessCreationTime", ""),
            "exception_code": data.get("ExceptionCode", ""),
            "faulting_module": data.get("ModuleName", ""),
            "faulting_module_path": data.get("ModulePath", ""),
            "faulting_offset": data.get("FaultingOffset", ""),
            "app_path": data.get("AppPath", ""),
            "integrator_report_id": data.get("IntegratorReportId", ""),
        })
    return events


def event_matches_pid(event: dict, pid: int, creation_filetime: int | None) -> bool:
    try:
        event_pid = int(event["process_id_hex"], 16)
    except (TypeError, ValueError):
        return False
    if event_pid != pid:
        return False
    if creation_filetime is None:
        return True
    try:
        return int(event["process_creation_filetime_hex"], 16) == creation_filetime
    except (TypeError, ValueError):
        return False


def copy_tree(src: Path, dst: Path) -> None:
    if dst.exists():
        raise FileExistsError(dst)
    shutil.copytree(src, dst)


def remove_thread_setting(project: Path) -> None:
    path = project / "project.godot"
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"(?m)^\[threading\]\n\nworker_pool/max_threads=20\n?", "", text)
    path.write_text(text, encoding="utf-8", newline="\n")


def write_empty_project(path: Path, threads: int | None) -> None:
    path.mkdir(parents=True, exist_ok=False)
    text = """config_version=5

[application]
config/name="Round37 Empty Cold Import"
config/features=PackedStringArray("4.7")

[rendering]
renderer/rendering_method="mobile"
"""
    if threads is not None:
        text += f"\n[threading]\n\nworker_pool/max_threads={threads}\n"
    (path / "project.godot").write_text(text, encoding="utf-8", newline="\n")


def source_hashes(root: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for path in sorted(root.rglob("*")):
        if path.is_file() and ".godot" not in path.parts:
            result[path.relative_to(root).as_posix()] = sha256(path)
    return result


def stage_variant(base: Path, variant: Path, *, extension: bool, threads: int | None) -> None:
    copy_tree(base, variant)
    if not extension:
        for rel in (
            "addons/fate_server_signals/fate_server_signals.gdextension",
            "addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll",
        ):
            target = variant / rel
            if target.exists():
                target.unlink()
    if threads is None:
        remove_thread_setting(variant)


def run_candidate(
    name: str,
    project: Path,
    godot: Path,
    root: Path,
    *,
    renderer: str | None,
    source_variant: str,
    timeout_s: int,
) -> dict:
    evidence = root / "evidence"
    evidence.mkdir(parents=True, exist_ok=True)
    stdout_path = evidence / f"{name}.stdout.log"
    stderr_path = evidence / f"{name}.stderr.log"
    user_root = root / "user" / name
    for child in (user_root,):
        child.mkdir(parents=True, exist_ok=False)
    env = os.environ.copy()
    for key, value in {
        "APPDATA": str(user_root / "APPDATA"),
        "LOCALAPPDATA": str(user_root / "LOCALAPPDATA"),
        "TEMP": str(user_root / "TEMP"),
        "TMP": str(user_root / "TMP"),
        "TMPDIR": str(user_root / "TMPDIR"),
    }.items():
        Path(value).mkdir(parents=True, exist_ok=True)
        env[key] = value
    command = [str(godot), "--headless"]
    if renderer is not None:
        command += ["--rendering-method", renderer]
    command += ["--editor", "--path", str(project), "--import"]
    started_utc = utc_now()
    with stdout_path.open("wb") as stdout, stderr_path.open("wb") as stderr:
        proc = subprocess.Popen(
            command,
            cwd=str(project),
            env=env,
            stdout=stdout,
            stderr=stderr,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        pid = proc.pid
        creation_filetime = windows_creation_filetime(pid)
        try:
            exit_code = proc.wait(timeout=timeout_s)
        except subprocess.TimeoutExpired:
            # The only process we are allowed to terminate is this exact Popen child.
            proc.terminate()
            exit_code = proc.wait(timeout=10)
            raise RuntimeError(f"candidate {name} timed out; owned pid={pid} exit={exit_code}")
    finished_utc = utc_now()
    # Event 1000 is read once after the owned child has exited; this is not a warm retry.
    events = [event for event in run_event_query() if event_matches_pid(event, pid, creation_filetime)]
    result = {
        "name": name,
        "source_variant": source_variant,
        "command": command,
        "pid": pid,
        "creation_filetime": creation_filetime,
        "started_utc": started_utc,
        "finished_utc": finished_utc,
        "exit_code_decimal": exit_code,
        "exit_code_hex": f"0x{(exit_code & 0xFFFFFFFF):08X}",
        "stdout": str(stdout_path),
        "stderr": str(stderr_path),
        "stdout_sha256": sha256(stdout_path),
        "stderr_sha256": sha256(stderr_path),
        "project_file_count_before_import": len(source_hashes(project)),
        "project_sha256_before_import": source_hashes(project),
        "application_error_events_for_exact_pid": events,
        "application_error_match": bool(events),
    }
    (evidence / f"{name}.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--freeze-python", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args(argv)

    source = args.source.resolve()
    godot = args.godot.resolve()
    root = ensure_physical_e(args.root)
    if root.exists():
        raise FileExistsError(f"refusing to reuse diagnostic root: {root}")
    root.mkdir(parents=True, exist_ok=False)
    base = root / "base-14-files"
    base_manifest = root / "base-14-files.json"
    freeze_command = [
        sys.executable, "-B", str(args.freeze_python.resolve()),
        "--source", str(source), "--target", str(base), "--manifest", str(base_manifest),
        "--prepare", "--preset", "FateServer Windows", "--role", "signaling",
        "--executable", "FateSignaling.exe",
        "--runtime-files", json.dumps([{
            "source": "addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll",
            "target": "libfate_server_signals.windows.template_release.x86_64.dll",
        }]),
        "--allowed-root", str(root),
    ]
    freeze = subprocess.run(freeze_command, cwd=str(source), capture_output=True, text=True, encoding="utf-8", errors="replace", check=False)
    (root / "freeze.stdout.log").write_text(freeze.stdout, encoding="utf-8", newline="\n")
    (root / "freeze.stderr.log").write_text(freeze.stderr, encoding="utf-8", newline="\n")
    if freeze.returncode != 0:
        raise RuntimeError(f"freeze failed once, exit={freeze.returncode}; see {root / 'freeze.stderr.log'}")
    manifest = json.loads(base_manifest.read_text(encoding="utf-8"))
    if len(manifest.get("source_files", {})) != 14:
        raise RuntimeError(f"expected 14 source files, got {len(manifest.get('source_files', {}))}")

    # The variants are staged from the same 14-file freeze, changing one variable at a time.
    stage_variant(base, root / "script-no-extension-default", extension=False, threads=None)
    stage_variant(base, root / "extension-default", extension=True, threads=None)
    stage_variant(base, root / "extension-thread20", extension=True, threads=20)
    stage_variant(base, root / "extension-gl-compatibility", extension=True, threads=None)
    write_empty_project(root / "empty-default", threads=None)

    godot_version = subprocess.run([str(godot), "--version"], capture_output=True, text=True, encoding="utf-8", errors="replace", check=False)
    results = []
    results.append(run_candidate("empty-default", root / "empty-default", godot, root, renderer=None, source_variant="empty", timeout_s=args.timeout))
    results.append(run_candidate("script-no-extension-default", root / "script-no-extension-default", godot, root, renderer=None, source_variant="14-file freeze minus extension", timeout_s=args.timeout))
    results.append(run_candidate("extension-default", root / "extension-default", godot, root, renderer=None, source_variant="14-file freeze, default worker setting", timeout_s=args.timeout))
    results.append(run_candidate("extension-thread20", root / "extension-thread20", godot, root, renderer=None, source_variant="14-file freeze, worker_pool/max_threads=20", timeout_s=args.timeout))
    results.append(run_candidate("extension-gl-compatibility", root / "extension-gl-compatibility", godot, root, renderer="gl_compatibility", source_variant="same 14-file extension project, command-only renderer", timeout_s=args.timeout))

    report = {
        "created_utc": utc_now(),
        "root": str(root),
        "source": str(source),
        "godot": str(godot),
        "godot_version_stdout": godot_version.stdout,
        "godot_version_stderr": godot_version.stderr,
        "godot_version_exit_code": godot_version.returncode,
        "freeze_command": freeze_command,
        "freeze_exit_code": freeze.returncode,
        "source_file_count": len(manifest["source_files"]),
        "source_file_hashes": manifest["source_files"],
        "native_dll_sha256": sha256(source / "addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll"),
        "gdextension_sha256": sha256(source / "addons/fate_server_signals/fate_server_signals.gdextension"),
        "results": results,
        "warm_reentry_attempted": False,
        "source_or_native_modified": False,
    }
    (root / "manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({
        "root": str(root),
        "source_file_count": len(manifest["source_files"]),
        "results": [
            {"name": item["name"], "pid": item["pid"], "exit": item["exit_code_decimal"], "hex": item["exit_code_hex"], "app_error": item["application_error_match"], "events": item["application_error_events_for_exact_pid"]}
            for item in results
        ],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
