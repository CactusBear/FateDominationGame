"""Same-engine, four-case cold project/GDExtension caller comparison.

Diagnostic only: no production edits, DLL builds, process-memory writes, sleeps,
recovery mode, arbitrary PID attachment, or warm-cache reruns. Existing release
inventory/transform and the owned-child debugger are read-only dependencies.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import urllib.request

sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from tools.diagnostics.native_cold_import_debug import DEBUGGER_CPP, digest, parse_debug_log
sys.path.insert(0, str(REPO / "tools/release"))
import freeze_prepare

EXT = Path("addons/fate_server_signals/fate_server_signals.gdextension")
DLL = EXT.parent / "bin/libfate_server_signals.windows.template_release.x86_64.dll"
ENV_KEYS = ("APPDATA", "LOCALAPPDATA", "TEMP", "TMP", "TMPDIR")
CASES = ("C-formal-cold-freeze", "A-empty", "B-original-extension", "D-extension-import-only")
MINIMAL = ('config_version=5\n[application]\nconfig/name="R45 cold causal control"\n'
           'config/features=PackedStringArray("4.7")\n[rendering]\nrenderer/rendering_method="mobile"\n')


def save(path, value):
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def physical_e(path, fresh=False):
    path = path.absolute()
    if path.drive.upper() != "E:":
        raise ValueError("physical E: required")
    for parent in (path, *path.parents):
        if parent.exists() and (parent.is_symlink() or parent.is_junction()):
            raise ValueError(f"link/junction refused: {parent}")
    if fresh and path.exists():
        raise ValueError("exclusive nonexisting root required")
    return path.resolve()


def child_env(root):
    env = os.environ.copy()
    env["_NO_DEBUG_HEAP"] = "1"
    for key in ENV_KEYS:
        directory = root / "user" / key
        directory.mkdir(parents=True, exist_ok=False)
        env[key] = str(directory)
    return env


def bounded(command, cwd, env, log, timeout):
    # Popen handle is owned; no PID lookup/attach/taskkill by basename.
    started = time.monotonic()
    with log.open("xb") as stream:
        proc = subprocess.Popen(command, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT)
        timedout = False
        try:
            code = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timedout = True
            proc.kill()
            code = proc.wait(timeout=10)
    return {"pid": proc.pid, "exit": code, "timeout": timedout,
            "elapsed_s": time.monotonic() - started, "argv": command, "log": str(log)}


def debugger_source():
    old = 'std::wstring cmd=L"\\\""+std::wstring(argv[1])+L"\\\" --headless --editor --path \\\""+argv[2]+L"\\\" --import";'
    # Pass the complete, already validated tail. No implicit --editor/import.
    new = 'std::wstring cmd=L"\\\""+std::wstring(argv[1])+L"\\\" "+argv[4];'
    if DEBUGGER_CPP.count(old) != 1:
        raise RuntimeError("owned debugger command seam changed")
    source = DEBUGGER_CPP.replace(old, new)
    begin = source.index("    if(argc<4 || argc>6)")
    end = source.index("    std::wstring cmd=", begin)
    source = source[:begin] + '    if(argc!=5)return 2;\n' + source[end:]
    # No breakpoint parameters are accepted; original exception/handle logic stays.
    return source


def collect_official(root, revision):
    files = {
        "main.cpp": f"https://raw.githubusercontent.com/godotengine/godot/{revision}/main/main.cpp",
        "gdextension.cpp": f"https://raw.githubusercontent.com/godotengine/godot/{revision}/core/extension/gdextension.cpp",
        "gdextension_library_loader.cpp": f"https://raw.githubusercontent.com/godotengine/godot/{revision}/core/extension/gdextension_library_loader.cpp",
        "editor_help.cpp": f"https://raw.githubusercontent.com/godotengine/godot/{revision}/editor/doc/editor_help.cpp",
        "doc_tools.cpp": f"https://raw.githubusercontent.com/godotengine/godot/{revision}/editor/doc/doc_tools.cpp",
        "gdextension_file.rst": "https://raw.githubusercontent.com/godotengine/godot-docs/master/engine_details/engine_api/gdextension/gdextension_file.rst",
    }
    directory = root / "official"
    directory.mkdir()
    def fetch(item):
        name, url = item
        try:
            payload = urllib.request.urlopen(url, timeout=25).read()
            (directory / name).write_bytes(payload)
            return {"url": url, "file": str(directory / name), "sha256": hashlib.sha256(payload).hexdigest()}
        except Exception as exc:
            return {"url": url, "error": str(exc)}
    result = list(concurrent.futures.ThreadPoolExecutor(max_workers=6).map(fetch, files.items()))
    save(root / "official-fetch.json", result)
    return result


def prepare_project(case, directory, source):
    project = directory / "project"
    project.mkdir()
    manifest = {"case": case, "cache_before": False, "source_files": {}, "files": {}}
    if case == "C-formal-cold-freeze":
        # Exact existing release selection/transform, but deliberately do NOT
        # inherit generated .godot imported blobs: this is a cold diagnostic
        # derivative, not a release_prepare/verify READY claim.
        rels = freeze_prepare.inventory(source)
        cold_rels = [rel for rel in rels if not rel.startswith(".godot/")]
        transformed = freeze_prepare.transform(source, "FateDomination_demo_v1", cold_rels)
        manifest["excluded_inherited_cache"] = [rel for rel in rels if rel.startswith(".godot/")]
        manifest["classification"] = "COLD_DIAGNOSTIC_RELEASE_TRANSFORM_NOT_RELEASE_GATE"
        for rel in cold_rels:
            src, dst = source / rel, project / rel
            if src.resolve() != src or src.is_symlink() or src.is_junction():
                raise ValueError(f"source link refused: {src}")
            before = digest(src)
            dst.parent.mkdir(parents=True, exist_ok=True)
            if rel in transformed:
                dst.write_text(transformed[rel], encoding="utf-8", newline="\n")
            else:
                shutil.copyfile(src, dst)
            if digest(src) != before:
                raise RuntimeError(f"source changed during freeze: {rel}")
            manifest["source_files"][rel] = before
            manifest["files"][rel] = digest(dst)
        if any(digest(source / rel) != sha for rel, sha in manifest["source_files"].items()):
            raise RuntimeError("source changed after freeze")
    else:
        (project / "project.godot").write_text(MINIMAL, encoding="utf-8", newline="\n")
        if case != "A-empty":
            for rel in (EXT, DLL):
                dst = project / rel
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source / rel, dst)
                manifest["source_files"][rel.as_posix()] = digest(source / rel)
        manifest["files"] = {p.relative_to(project).as_posix(): digest(p) for p in project.rglob("*") if p.is_file()}
    if (project / ".godot").exists():
        raise RuntimeError("not a cold project")
    save(directory / "input-manifest.json", manifest)
    return project, manifest


def validate_flags(tail, help_text):
    flags = [s for s in tail if s.startswith("--")]
    if len(flags) != len(set(flags)):
        raise ValueError("duplicate CLI option")
    supported = set(re.findall(r"--[a-z][a-z0-9-]*", help_text))
    for flag in flags:
        if flag not in supported:
            raise ValueError(f"not in actual binary --help: {flag}")
    if any(x in flags for x in ("--quit", "--quit-after", "--export-release", "--recovery-mode")):
        raise ValueError("conflicting/coverage-removing lifecycle control")
    if flags.count("--import") != 1:
        raise ValueError("exactly one import required")
    return {"flags": flags, "duplicate": False, "quit_or_export_override": False,
            "editor_implied_by_import": True, "explicit_editor_redundant": "--editor" in flags}


def reclaim_generated(directory, manifest):
    """Delete only own recognized generated outputs, never frozen inputs/logs."""
    project = physical_e(directory / "project")
    removed = []
    for path in sorted(project.rglob("*")):
        rel = path.relative_to(project).as_posix()
        if rel in manifest["files"] or rel.startswith(".godot/"):
            continue
        if path.is_file() and (path.name.startswith("~lib") and path.suffix.lower() == ".dll"):
            physical_e(path)
            removed.append({"path": str(path), "sha256": digest(path), "bytes": path.stat().st_size})
            path.unlink()
    generated = project / ".godot"
    if generated.exists():
        physical_e(generated)
        removed.append({"path": str(generated), "kind": "generated_project_cache"})
        shutil.rmtree(generated)
    for key in ENV_KEYS:
        cache = directory / "user" / key
        if cache.exists():
            physical_e(cache)
            removed.append({"path": str(cache), "kind": "owned_disposable_user_cache"})
            shutil.rmtree(cache)
    return removed


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--source", type=Path, default=REPO)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--templates", type=Path, required=True)
    parser.add_argument("--vs-dev", type=Path, default=Path("D:/VS2022/Common7/Tools/VsDevCmd.bat"))
    parser.add_argument("--timeout", type=int, default=30)
    args = parser.parse_args(argv)
    if os.name != "nt" or not 1 <= args.timeout <= 180:
        raise ValueError("Windows only, owned lifecycle budget 1..180 seconds")
    root = physical_e(args.root, fresh=True)
    source = physical_e(args.source)
    if source in root.parents or root in source.parents:
        raise ValueError("diagnostics must be outside source")
    root.mkdir(parents=True)
    env = child_env(root)
    godot = args.godot.resolve()
    templates = args.templates.resolve()
    if "console" in godot.name.lower():
        raise ValueError("use actual engine, not console wrapper")
    meta = {"source": str(source), "godot": str(godot), "godot_sha256": digest(godot),
            "descriptor_sha256": digest(source / EXT), "dll_sha256": digest(source / DLL),
            "environment": {key: env[key] for key in ENV_KEYS}, "timeout_s": args.timeout}
    meta["version_run"] = bounded([str(godot), "--version"], root, env, root / "version.log", 20)
    meta["help_run"] = bounded([str(godot), "--help"], root, env, root / "help.log", 20)
    version = (root / "version.log").read_text(encoding="utf-8", errors="replace").strip()
    help_text = (root / "help.log").read_text(encoding="utf-8", errors="replace")
    if "this build = editor" not in help_text or meta["help_run"]["exit"]:
        raise ValueError("actual binary is not supported editor build")
    revision = re.search(r"official\.([0-9a-f]+)", version)
    if not revision:
        raise ValueError("no actual official revision")
    meta["actual_version"] = version
    meta["templates"] = []
    for path in sorted(templates.glob("windows*.exe")):
        item = {"path": str(path), "sha256": digest(path), "role": "export_template_not_editor"}
        if "console" not in path.name:
            log = root / (path.stem + "-version.log")
            item["version_run"] = bounded([str(path), "--version"], root, env, log, 20)
            item["version"] = log.read_text(encoding="utf-8", errors="replace").strip()
            item["matches_editor_version"] = item["version"] == version
        meta["templates"].append(item)
    wrapper = godot.with_name(godot.stem + "_console.exe")
    meta["console_wrapper"] = {"path": str(wrapper), "sha256": digest(wrapper), "used_for_lifecycle": False}
    meta["release_builder_sha256"] = digest(REPO / "tools/release/release_prepare.py")
    meta["freeze_builder_sha256"] = digest(REPO / "tools/release/freeze_prepare.py")
    meta["debugger_dependency_sha256"] = digest(REPO / "tools/diagnostics/native_cold_import_debug.py")
    save(root / "metadata.json", meta)
    collect_official(root, revision[1])
    cpp = root / "debugger.cpp"
    cpp.write_text(debugger_source(), encoding="utf-8", newline="\n")
    build = root / "build.cmd"
    build.write_text(f'@call "{args.vs_dev}" -arch=x64 -host_arch=x64\n@cl /nologo /EHsc /std:c++17 /W4 "{cpp}" /Fe:"{root / "debugger.exe"}" /Fo:"{root / "debugger.obj"}" /link dbghelp.lib\n', encoding="utf-8")
    build_result = bounded(["cmd.exe", "/d", "/c", str(build)], root, env, root / "build.log", 90)
    save(root / "build-result.json", build_result)
    if build_result["exit"]:
        raise RuntimeError("owned debugger build failed; see build.log")
    results = []
    for case in CASES:
        directory = root / case
        directory.mkdir()
        project, manifest = prepare_project(case, directory, source)
        case_env = child_env(directory)
        tail = ["--headless", "--verbose", "--rendering-method", "gl_compatibility"]
        if case != "D-extension-import-only":
            tail.append("--editor")
        tail.extend(["--path", str(project), "--import"])
        flags = validate_flags(tail, help_text)
        command = [str(root / "debugger.exe"), str(godot), str(project), str(args.timeout * 1000), subprocess.list2cmdline(tail)]
        # Debugger kills only its CreateProcess-owned engine handle at timeout.
        # Outer limit includes bounded post-kill handle cleanup, never a retry.
        run = bounded(command, directory, case_env, directory / "debug.log", args.timeout + 25)
        text = (directory / "debug.log").read_text(encoding="utf-8", errors="replace")
        events = parse_debug_log(text)
        owned = re.search(r"OWNED pid=(\d+) creation_filetime=(\d+) command=(.*)", text)
        result = {"case": case, "run": run, "engine_pid": int(owned[1]) if owned else None,
                  "engine_creation_filetime": owned[2] if owned else None,
                  "engine_command": owned[3] if owned else None, "flag_check": flags,
                  "events": events, "cold_project": True,
                  "cold_user_dirs": True, "native_os_disk_cache_cold_proven": False,
                  "input_manifest": str(directory / "input-manifest.json"),
                  "errors": [line for line in text.splitlines() if "ERROR:" in line],
                  "status": "NATIVE_FAILURE" if events["second_chance"] else
                      "CLEAN_EXIT" if events["child_exit_hex"] == "0x00000000" and "ERROR:" not in text else "INCOMPLETE_OR_ERROR"}
        save(directory / "result.json", result)
        results.append(result)
        print(json.dumps({key: result[key] for key in ("case", "engine_pid", "status", "events")}), flush=True)
        # Preserve first real failed cold project and every raw log. Reclaim only
        # own generated .godot from non-first-failing cases; never source files.
        first_failed = next((r["case"] for r in results if r["status"] == "NATIVE_FAILURE"), None)
        if case != first_failed:
            save(directory / "cleanup.json", reclaim_generated(directory, manifest))
    save(root / "results.json", {"metadata": str(root / "metadata.json"), "cases": results,
                                "lifecycle_attempts": len(results), "no_release_ready_claim": True})
    if digest(source / DLL) != meta["dll_sha256"] or digest(source / EXT) != meta["descriptor_sha256"]:
        raise RuntimeError("production native source changed during comparison")
    print(f"EVIDENCE={root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
