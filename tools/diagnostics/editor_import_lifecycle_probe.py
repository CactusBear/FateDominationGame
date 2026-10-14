"""Observe pinned Godot editor teardown, not a production import workaround.

Every run uses a new physical E: project and the real GUI executable. Reuses
round39's owned-child debugger; never attaches to existing processes or changes
engine/plugin files. Fixed frames and filesystem completion are NOT doc barriers.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.diagnostics.native_cold_import_debug import (
    DEBUGGER_CPP, digest, parse_debug_log, require_fresh_e,
)

ENGINE_SHA = "ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424"
DOC_RVA = 0x66DCC10
CLEANUP_RVA = 0x17ABA60
CALLBACK_RVA = 0x1792840

FS_PLUGIN = '''@tool
extends EditorPlugin
var requested := false
func _enter_tree() -> void:
    var fs := EditorInterface.get_resource_filesystem()
    fs.sources_changed.connect(_sources_changed)
    print("[R40] ENTER scanning=", fs.is_scanning())
func _sources_changed(_changed: bool) -> void:
    var fs := EditorInterface.get_resource_filesystem()
    print("[R40] SOURCES_CHANGED scanning=", fs.is_scanning())
    if not fs.is_scanning() and not requested:
        requested = true
        _after_fs.call_deferred()
func _after_fs() -> void:
    if EditorInterface.get_resource_filesystem().is_scanning():
        requested = false
        return
    print("[R40] FS_COMPLETE doc_ready=UNKNOWN")
    print("[R40] NORMAL_QUIT_REQUEST")
    get_tree().quit(0)
'''


def mode_arguments(mode: str, iterations: int) -> str:
    if mode == "import":
        return "--import"
    if mode == "iterations" and iterations > 0:
        return f"--quit-after {iterations}"
    if mode in ("fs-quit", "editor-close"):
        return ""
    raise ValueError("unknown mode or nonpositive iteration count")


def assess_observation(text: str) -> dict:
    events = parse_debug_log(text)
    traces = []
    for line in events["traces"]:
        match = re.search(r"rva=(0x[0-9a-f]+).*value=(0x[0-9a-f]+)", line)
        if match:
            traces.append({"rva": int(match[1], 16), "doc": int(match[2], 16)})
    callbacks = [i for i, x in enumerate(traces) if x["rva"] == CALLBACK_RVA]
    cleanup = [i for i, x in enumerate(traces) if x["rva"] == CLEANUP_RVA]
    before = bool(callbacks and cleanup and callbacks[0] < cleanup[0])
    return {
        "status": "BLOCKED_NO_PUBLIC_DOC_COMPLETION_CONTRACT",
        "completion_contract_proven": False,
        "callback_entry_before_cleanup_observed": before,
        "callback_entry_doc_nonnull": bool(callbacks and traces[callbacks[0]]["doc"]),
        "filesystem_completion_observed": "[R40] FS_COMPLETE" in text,
        "normal_quit_requested": "[R40] NORMAL_QUIT_REQUEST" in text,
        "trace_values": traces,
        "events": events,
    }


def debugger_source() -> str:
    source = DEBUGGER_CPP
    source = source.replace("argc>6", "argc>7").replace("if(argc==6)", "if(argc>=6)")
    old = 'std::wstring cmd=L"\\\""+std::wstring(argv[1])+L"\\\" --headless --editor --path \\\""+argv[2]+L"\\\" --import";'
    new = 'std::wstring cmd=L"\\\""+std::wstring(argv[1])+L"\\\" --headless --editor --verbose --path \\\""+argv[2]+L"\\\" "+(argc==7 ? argv[6] : L"--import");'
    if source.count(old) != 1:
        raise RuntimeError("round39 debugger command seam changed")
    return source.replace(old, new)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--mode", choices=("import", "iterations", "fs-quit", "editor-close"), required=True)
    parser.add_argument("--iterations", type=int, default=2)
    parser.add_argument("--timeout", type=int, default=60)
    parser.add_argument("--vs-dev", type=Path, default=Path("D:/VS2022/Common7/Tools/VsDevCmd.bat"))
    args = parser.parse_args(argv)
    tail = mode_arguments(args.mode, args.iterations)
    if os.name != "nt" or args.timeout <= 0:
        raise RuntimeError("Windows only, positive timeout required")
    godot = args.godot.resolve()
    if digest(godot) != ENGINE_SHA:
        raise RuntimeError("RVA trace requires exact round39 GUI engine hash")
    root = require_fresh_e(args.root)
    root.mkdir(parents=True)
    if root.is_junction() or root.is_symlink():
        raise RuntimeError("owned physical root required")
    cpp = root / "debugger.cpp"
    cpp.write_text(debugger_source(), encoding="utf-8")
    build = root / "build.cmd"
    build.write_text(f'@call "{args.vs_dev}" -arch=x64 -host_arch=x64\n@cl /nologo /EHsc /std:c++17 /W4 "{cpp}" /Fe:"{root / "debugger.exe"}" /Fo:"{root / "debugger.obj"}" /link dbghelp.lib\n', encoding="utf-8")
    compiled = subprocess.run(["cmd.exe", "/d", "/c", str(build)], cwd=root, capture_output=True)
    (root / "build.log").write_bytes(compiled.stdout + compiled.stderr)
    if compiled.returncode:
        print(f"build blocked: {root / 'build.log'}")
        return 2
    project = root / "project"
    project.mkdir()
    descriptor = args.source.resolve() / "addons/fate_server_signals/fate_server_signals.gdextension"
    dll = descriptor.parent / "bin/libfate_server_signals.windows.template_release.x86_64.dll"
    addon = project / "addons/fate_server_signals"
    (addon / "bin").mkdir(parents=True)
    shutil.copy2(descriptor, addon / descriptor.name)
    shutil.copy2(dll, addon / "bin" / dll.name)
    config = 'config_version=5\n[application]\nconfig/name="Round40 editor lifecycle diagnostic"\nconfig/features=PackedStringArray("4.7")\n[rendering]\nrenderer/rendering_method="mobile"\n'
    if args.mode in ("fs-quit", "editor-close"):
        plugin = project / "addons/round40_lifecycle"
        plugin.mkdir()
        (plugin / "plugin.cfg").write_text('[plugin]\nname="Round40 observer"\ndescription="filesystem-only counterexample; not a document completion contract"\nauthor="diagnostic"\nversion="1"\nscript="plugin.gd"\n', encoding="utf-8")
        plugin_source = FS_PLUGIN
        if args.mode == "editor-close":
            plugin_source = plugin_source.replace(
                "    get_tree().quit(0)",
                "    print(\"[R40] OFFICIAL_EDITOR_CLOSE_NOTIFICATION\")\n"
                "    var editor_node := EditorInterface.get_base_control().get_parent()\n"
                "    print(\"[R40] CLOSE_TARGET class=\", editor_node.get_class())\n"
                "    editor_node.notification.call_deferred(NOTIFICATION_WM_CLOSE_REQUEST)",
            )
        (plugin / "plugin.gd").write_text(plugin_source, encoding="utf-8")
        config += '[editor_plugins]\nenabled=PackedStringArray("res://addons/round40_lifecycle/plugin.cfg")\n'
    (project / "project.godot").write_text(config, encoding="utf-8")
    env = os.environ.copy()
    env["_NO_DEBUG_HEAP"] = "1"
    for key in ("APPDATA", "LOCALAPPDATA", "TEMP", "TMP", "TMPDIR"):
        directory = root / "user" / key
        directory.mkdir(parents=True)
        env[key] = str(directory)
    command = [str(root / "debugger.exe"), str(godot), str(project), str(args.timeout * 1000), hex(DOC_RVA), f"{hex(CLEANUP_RVA)},{hex(CALLBACK_RVA)}", tail]
    with (root / "debug.log").open("wb") as log:
        result = subprocess.run(command, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=args.timeout + 30)
    text = (root / "debug.log").read_text(encoding="utf-8", errors="replace")
    report = {
        "mode": args.mode, "command": command, "debugger_exit": result.returncode,
        "project_cache_existed_before": False,
        "user_env_redirected_not_proof_of_native_doc_cache_isolation": True,
        "godot_sha256": digest(godot), "dll_sha256": digest(dll),
        "descriptor_sha256": digest(descriptor), "observation": assess_observation(text),
    }
    (root / "result.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
