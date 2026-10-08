"""只读生产文件的导出前静态检查；不运行 Godot、不导出、不读取用户凭证。"""
from pathlib import Path
import argparse
import datetime
import fnmatch
import hashlib
import json
import re
import struct
import subprocess


def sections(text):
    """仅提取单行键值；不是 Godot Variant/多行 CFG 解析器。"""
    result = {}
    current = ""
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
            result.setdefault(current, {})
        elif "=" in line and not line.startswith(";"):
            key, value = line.split("=", 1)
            result.setdefault(current, {})[key.strip()] = value.strip()
    return result


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def native_kind(path):
    """检查 PE/ELF 魔数与 x86_64 机器号，不证明 ABI 或加载成功。"""
    with path.open("rb") as stream:
        header = stream.read(64)
        if header[:2] == b"MZ" and len(header) == 64:
            stream.seek(struct.unpack_from("<I", header, 60)[0])
            pe = stream.read(6)
            return "PE-x86_64" if pe[:4] == b"PE\0\0" and pe[4:] == b"\x64\x86" else "PE-other"
        if header[:4] == b"\x7fELF" and len(header) >= 20:
            return "ELF-x86_64" if header[4:6] == b"\x02\x01" and struct.unpack_from("<H", header, 18)[0] == 62 else "ELF-other"
    return "unknown"


def run(root, out):
    root, out = root.resolve(), out.resolve()
    # 将所有输出严格限定在本任务目录，不能误写到生产目录。
    allowed = root / "scratch" / "package-preflight-v5"
    if out != allowed and allowed not in out.parents:
        raise ValueError("输出必须位于 scratch/package-preflight-v5 内")
    checks = []
    def check(name, ok, detail, severity="BLOCK"):
        checks.append({"name": name, "status": "PASS" if ok else severity, "detail": detail})
    read = lambda p: (root / p).read_text(encoding="utf-8-sig")
    project = sections(read("project.godot"))
    presets = sections(read("export_presets.cfg"))
    app = project.get("application", {})
    check("服务端 feature 入口", app.get("run/main_scene.fate_server") == '"res://assets/scenes/main_menu/server_bootstrap.tscn"', app.get("run/main_scene.fate_server"))
    check("服务端即时 stdout", app.get("run/flush_stdout_on_print.fate_server") == "true", app.get("run/flush_stdout_on_print.fate_server"))
    production = [root / "project.godot", root / "export_presets.cfg", root / "icon.svg"]
    for folder in ["scripts", "assets", "addons", "data", "json_maker"]:
        production.extend(p for p in (root / folder).rglob("*") if p.is_file() and ".git" not in p.parts and "__pycache__" not in p.parts)
    production = sorted({p for p in production if not any((parent / ".gdignore").exists() for parent in p.parents if parent != root and root in parent.parents)}, key=lambda p: p.relative_to(root).as_posix())
    references, missing, legacy = [], [], []
    for path in production:
        if path.suffix not in {".gd", ".tscn", ".tres", ".godot", ".gdextension"}:
            continue
        text = path.read_text(encoding="utf-8-sig", errors="replace")
        # 字面量引用扫描（包括注释）；不解析 uid://、动态拼接或条件分支。
        for match in re.finditer(r'res://[^"\s\)\],;]+', text):
            target = match.group(0)
            rel = target[6:]
            if Path(rel).suffix not in {".gd", ".tscn", ".tres", ".gdextension", ".cfg", ".dll", ".so"}:
                continue
            item = {"source": path.relative_to(root).as_posix(), "line": text[:match.start()].count("\n") + 1, "target": target}
            references.append(item)
            if not (root / rel).is_file():
                missing.append(item)
            if re.match(r"scripts/net/[^/]+\.gd$", rel):
                legacy.append(item)
    check("新 net 目录引用无旧平铺路径", not legacy, legacy)
    check("生产字面量资源引用可定位", not missing, missing, "REVIEW")
    for folder in ["authority", "content", "identity", "p2p", "server", "session", "transport", "ui", "validation"]:
        check("net 目录 " + folder, (root / "scripts/net" / folder).is_dir(), folder)
    server_presets = []
    for section, values in presets.items():
        if not re.fullmatch(r"preset\.\d+", section):
            continue
        name = values.get("name", "").strip('"')
        options = presets.get(section + ".options", {})
        filters = values.get("exclude_filter", "").strip('"').split(",")
        check(name + " 外置 data 排除", "data/*" in filters, filters)
        if values.get("dedicated_server") != "true":
            continue
        server_presets.append({"name": name, "platform": values.get("platform"), "path": values.get("export_path"), "options": options})
        check(name + " feature", "fate_server" in values.get("custom_features", ""), values.get("custom_features"))
        check(name + " 配置模板包含", "assets/config/*.cfg" in values.get("include_filter", ""), values.get("include_filter"))
        check(name + " editor Git 插件排除", "addons/godot-git-plugin/*" in filters, filters)
        scratch_resources = [p.relative_to(root).as_posix() for p in (root / "scratch").rglob("*.tscn") if not any((parent / ".gdignore").exists() for parent in p.parents if parent != root and root in parent.parents)]
        leaked_scratch = [p for p in scratch_resources if not any(fnmatch.fnmatch(p, f) for f in filters)]
        check(name + " scratch 资源排除", not leaked_scratch, leaked_scratch)
        if values.get("platform") == '"Windows Desktop"':
            check(name + " release console wrapper", options.get("debug/export_console_wrapper") == "2", options.get("debug/export_console_wrapper"))
    platforms = {p["platform"] for p in server_presets}
    check("双平台服务端预设", {'"Linux"', '"Windows Desktop"'} <= platforms, sorted(platforms))
    extensions = []
    for path in sorted((root / "addons").rglob("*.gdextension")):
        libraries = sections(path.read_text(encoding="utf-8-sig")).get("libraries", {})
        for feature, value in libraries.items():
            if not feature.startswith(("windows", "linux")):
                continue
            library_path = value.strip('"')
            target = root / library_path[6:] if library_path.startswith("res://") else path.parent / library_path
            target = target.resolve()
            extensions.append({"extension": path.relative_to(root).as_posix(), "feature": feature, "path": target.relative_to(root).as_posix(), "exists": target.is_file()})
            if "webrtc_native" in path.as_posix() and feature in {"windows.release.x86_64", "linux.release.x86_64"}:
                expected = "PE-x86_64" if feature.startswith("windows") else "ELF-x86_64"
                check("WebRTC release " + feature, target.is_file() and native_kind(target) == expected, target.relative_to(root).as_posix())
            if "fate_server_signals" in path.as_posix():
                expected = "PE-x86_64" if feature.startswith("windows") else "ELF-x86_64"
                kind = native_kind(target) if target.is_file() else "missing"
                check("信号扩展 " + feature, kind == expected, {"binary": target.relative_to(root).as_posix(), "kind": kind, "sha256": sha(target) if target.is_file() else None})
    signal_features = {e["feature"] for e in extensions if "fate_server_signals" in e["extension"]}
    check("信号扩展双平台声明", {"windows.x86_64", "linux.x86_64"} <= signal_features, sorted(signal_features))
    template = sections(read("assets/config/server.cfg"))
    policy = template.get("server", {})
    for key, expected in {"authority_host_mode": '"dedicated"', "transaction_log": "true", "recovery_key_mismatch": '"reject"', "recovery_inheritance": '"host_select"', "roles": '["game"]'}.items():
        check("模板策略 " + key, policy.get(key) == expected, policy.get(key))
    data_cfg = template.get("data", {})
    check("模拟开关与预算分开声明", {"random_sim_enabled", "random_sim_budget_sec"} <= data_cfg.keys(), data_cfg)
    plugin = read("addons/godot_ai/export/mcp_export_plugin.gd")
    check("外置 data 复制入口静态存在", "_copy_external_data(path)" in plugin, "静态存在不证明插件实际被调用；目标目录不会清理源中已删除的旧文件，必须用新空目录")
    check("导出插件启用", "res://addons/godot_ai/plugin.cfg" in project.get("editor_plugins", {}).get("enabled", ""), project.get("editor_plugins"))
    manifest = []
    for path in production:
        rel = path.relative_to(root).as_posix()
        # 不读取 user:// 或仓库外配置，只记录受检生产树与公开配置模板。
        manifest.append({"path": rel, "bytes": path.stat().st_size, "sha256": sha(path)})
    canonical = json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    git = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, capture_output=True, text=True, check=False)
    status = subprocess.run(["git", "status", "--porcelain"], cwd=root, capture_output=True, text=True, check=False)
    report = {"schema": 1, "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(), "root": str(root), "scope": "静态快照；未导出、未启动 Godot、未验证 ABI/协议/完整对局", "version": app.get("config/version", "").strip('"'), "git_head": git.stdout.strip(), "dirty": bool(status.stdout.strip()), "source_tree_sha256": hashlib.sha256(canonical).hexdigest(), "manifest_files": len(manifest), "resource_reference_count": len(references), "checks": checks, "extensions": extensions, "server_presets": server_presets, "counts": {state: sum(c["status"] == state for c in checks) for state in ["PASS", "BLOCK", "REVIEW"]}, "limitations": ["CFG 仅单行静态提取，不是 Godot 语法解析", "字面量扫描含注释；动态路径、uid:// 和 PCK 内容须另验", "并行写入时哈希不是冻结快照；全部写入者结束后必须复跑", "E 盘测试数据与 user:// 日志位置仅文档约定，未创建/迁移/读取用户数据"]}
    out.mkdir(parents=True, exist_ok=True)
    for name, content in [("static-report.json", report), ("source-manifest.json", manifest), ("resource-references.json", references)]:
        (out / name).write_text(json.dumps(content, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"report": str(out / "static-report.json"), "counts": report["counts"], "source_tree_sha256": report["source_tree_sha256"]}, ensure_ascii=False))
    return 2 if report["counts"]["BLOCK"] else 1 if report["counts"]["REVIEW"] else 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    raise SystemExit(run(args.root, args.out or args.root / "scratch/package-preflight-v5"))
