from __future__ import annotations
import hashlib, json, re, struct, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent


def parse_sections(path: Path):
    result, section = {}, ""
    for raw in path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
        line = raw.strip()
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            result.setdefault(section, {})
        elif "=" in line and not line.startswith(";"):
            k, v = line.split("=", 1)
            result.setdefault(section, {})[k.strip()] = v.strip()
    return result


def kind(path: Path):
    b = path.read_bytes()[:64]
    if b[:2] == b"MZ" and len(b) == 64:
        off = struct.unpack_from("<I", b, 60)[0]
        pe = path.read_bytes()[off:off+6]
        return "PE-x86_64" if pe[:4] == b"PE\0\0" and pe[4:] == b"\x64\x86" else "PE-other"
    if b[:4] == b"\x7fELF" and len(b) >= 20:
        return "ELF-x86_64" if b[4:6] == b"\x02\x01" and struct.unpack_from("<H", b, 18)[0] == 62 else "ELF-other"
    return "unknown"


def sha(path: Path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    checks = []
    def check(key, status, evidence):
        checks.append({"id": key, "status": status, "evidence": evidence})

    project = parse_sections(ROOT / "project.godot")
    presets = parse_sections(ROOT / "export_presets.cfg")
    app = project.get("application", {})
    check("bootstrap-entry", "PASS" if app.get("run/main_scene.fate_server") == '"res://assets/scenes/main_menu/server_bootstrap.tscn"' else "BLOCK", app.get("run/main_scene.fate_server"))
    check("stdout-flush", "PASS" if app.get("run/flush_stdout_on_print.fate_server") == "true" else "BLOCK", app.get("run/flush_stdout_on_print.fate_server"))

    # New net layout and literal references.
    expected_dirs = ["authority", "content", "identity", "p2p", "server", "session", "transport", "ui", "validation"]
    missing_dirs = [f"scripts/net/{x}" for x in expected_dirs if not (ROOT / "scripts/net" / x).is_dir()]
    check("newnet-layout", "PASS" if not missing_dirs else "BLOCK", {"missing": missing_dirs, "legacy_root_files": sorted(p.name for p in (ROOT / "scripts/net").glob("*.gd"))})
    legacy_refs = []
    for p in list((ROOT / "scripts").rglob("*.gd")) + list((ROOT / "assets").rglob("*.tscn")) + [ROOT / "project.godot"]:
        text = p.read_text(encoding="utf-8-sig", errors="replace")
        if re.search(r"res://scripts/net/[^/]+\.gd", text):
            legacy_refs.append(p.relative_to(ROOT).as_posix())
    check("legacy-net-references", "PASS" if not legacy_refs else "BLOCK", legacy_refs)

    server_presets = []
    for sec, vals in presets.items():
        if not re.fullmatch(r"preset\.\d+", sec):
            continue
        name = vals.get("name", "").strip('"')
        if vals.get("dedicated_server") != "true":
            continue
        filters = [x.strip() for x in vals.get("exclude_filter", "").strip('"').split(",") if x.strip()]
        required = ["data/*", "tests/*", "reports/*", "docs/*", "scratch/*", "addons/godot-git-plugin/*"]
        absent = [x for x in required if x not in filters]
        status = "BLOCK" if absent else "PASS"
        check(f"{name}-dedicated-exclusions", status, {"exclude_filter": filters, "missing_required": absent})
        check(f"{name}-feature", "PASS" if "fate_server" in vals.get("custom_features", "") else "BLOCK", vals.get("custom_features"))
        check(f"{name}-config-template", "PASS" if "assets/config/*.cfg" in vals.get("include_filter", "") else "BLOCK", vals.get("include_filter"))
        server_presets.append({"name": name, "platform": vals.get("platform"), "exclude_filter": filters, "include_filter": vals.get("include_filter"), "export_path": vals.get("export_path")})
    check("server-platform-pair", "PASS" if {x["platform"] for x in server_presets} >= {'"Linux"', '"Windows Desktop"'} else "BLOCK", server_presets)

    ext = ROOT / "addons/fate_server_signals/fate_server_signals.gdextension"
    ext_text = ext.read_text(encoding="utf-8-sig")
    libs = re.findall(r'^(windows\.x86_64|linux\.x86_64)\s*=\s*"([^"]+)"', ext_text, re.M)
    native = []
    for platform, ref in libs:
        p = ROOT / ref.removeprefix("res://")
        native.append({"platform": platform, "path": ref, "exists": p.is_file(), "kind": kind(p) if p.is_file() else "missing", "sha256": sha(p) if p.is_file() else None})
    check("signal-extension-platforms", "PASS" if {x["platform"] for x in native} == {"windows.x86_64", "linux.x86_64"} and all(x["exists"] and x["kind"] == ("PE-x86_64" if x["platform"].startswith("windows") else "ELF-x86_64") for x in native) else "BLOCK", native)
    extras = []
    for p in sorted((ROOT / "addons/fate_server_signals/bin").iterdir()):
        if p.is_file() and p.name not in {"libfate_server_signals.windows.x86_64.dll", "libfate_server_signals.linux.x86_64.so"}:
            extras.append(p.name)
    check("signal-bin-extras", "REVIEW" if extras else "PASS", extras)

    cfg = parse_sections(ROOT / "assets/config/server.cfg")
    server = cfg.get("server", {})
    required_cfg = {"authority_host_mode": '"dedicated"', "transaction_log": "true", "recovery_key_mismatch": '"reject"', "recovery_inheritance": '"host_select"', "roles": '["game"]'}
    cfg_bad = {k: server.get(k) for k, v in required_cfg.items() if server.get(k) != v}
    check("config-template-policy", "PASS" if not cfg_bad else "BLOCK", cfg_bad or {k: server.get(k) for k in required_cfg})
    data_cfg = cfg.get("data", {})
    check("config-simulation-fields", "PASS" if {"random_sim_enabled", "random_sim_budget_sec"} <= data_cfg.keys() else "BLOCK", data_cfg)

    # Static bootstrap argument and signaling-isolation contracts.
    boot = (ROOT / "scripts/net/server/server_bootstrap.gd").read_text(encoding="utf-8")
    contracts = {
        "bootstrap-routes": all(x in boot for x in ["--server-signaling", "--server-console", "--server-room-worker", "--room-data-validation-worker", "--server-gateway"]),
        "bootstrap-conflict-reject": "只能声明一种职责" in boot,
        "signaling-autoload-guard": "has_project_autoloads()" in boot and "纯信令必须运行于无 autoload" in boot,
        "signaling-relay-only": "roles 必须仅 relay" in boot and "configuration_error(configuration,true)" in boot,
        "arg-strip": '"--path","--scene"' in boot,
    }
    for k, ok in contracts.items():
        check(k, "PASS" if ok else "BLOCK", ok)

    # Static resource exclusion scan: any real scratch scene is a known all_resources leak risk.
    scratch_scenes = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "scratch").rglob("*.tscn"))
    check("scratch-resource-risk", "BLOCK" if scratch_scenes and any("scratch/*" not in x["exclude_filter"] for x in server_presets) else "PASS", scratch_scenes)

    report = {
        "schema": "export-audit-v6",
        "scope": "第二轮发行包静态审计；只读源码/配置；未启动Godot、未导出、未运行服务端",
        "repo": str(ROOT),
        "checks": checks,
        "counts": {s: sum(x["status"] == s for x in checks) for s in ["PASS", "BLOCK", "REVIEW"]},
        "native_libraries": native,
        "server_presets": server_presets,
        "scratch_scenes": scratch_scenes,
        "limitations": [
            "静态检查不能证明Godot导出解析、PCK内容、GDExtension ABI/依赖、真实启动、信号、网络或完整对局。",
            "all_resources下是否实际带入未排除资源须在导出后索引PCK确认；本轮按静态泄漏风险阻断。",
            "工作树含其他未提交改动；本报告不是冻结版本哈希或实际发行包证明。",
        ],
    }
    (OUT / "static-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    lines = ["# 第二轮发行包静态审计（export-audit-v6）", "", "范围：只读审计；未启动 Godot、未导出、未运行服务端。", "", f"结论：BLOCK={report['counts']['BLOCK']}，REVIEW={report['counts']['REVIEW']}，PASS={report['counts']['PASS']}", "", "## 阻断项"]
    for x in checks:
        if x["status"] == "BLOCK": lines.append(f"- **{x['id']}**：{json.dumps(x['evidence'], ensure_ascii=False)}")
    lines += ["", "## REVIEW"]
    for x in checks:
        if x["status"] == "REVIEW": lines.append(f"- **{x['id']}**：{json.dumps(x['evidence'], ensure_ascii=False)}")
    lines += ["", "## PASS 重点"]
    for x in checks:
        if x["status"] == "PASS": lines.append(f"- {x['id']}")
    lines += ["", "## 未覆盖", *[f"- {x}" for x in report["limitations"]]]
    (OUT / "REPORT.zh-CN.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"counts": report["counts"], "report": str(OUT / "static-report.json")}, ensure_ascii=False))
    return 2 if report["counts"]["BLOCK"] else 1 if report["counts"]["REVIEW"] else 0

if __name__ == "__main__":
    raise SystemExit(main())
