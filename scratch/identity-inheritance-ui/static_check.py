"""仅源码契约与场景引用检查，不启动 Godot、不读取凭证。"""
import json
import re
import subprocess
from pathlib import Path

from gdtoolkit.parser import parser

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "scratch/identity-inheritance-ui/static-results.json"
checks = []


def check(name, result):
    checks.append({"name": name, "passed": bool(result)})


scripts = ["scripts/net/identity_inheritance_panel.gd", "scripts/net/lobby_screen.gd",
           "scratch/identity-inheritance-ui/identity_inheritance_ui_window_test.gd"]
for path in scripts:
    parser.parse((ROOT / path).read_text(encoding="utf-8"))
    check("gdtoolkit 文法解析 " + path, True)

scenes = ["assets/scenes/main_menu/multiplayer_lobby.tscn",
          "assets/scenes/main_menu/identity_inheritance_panel.tscn",
          "scratch/identity-inheritance-ui/identity_inheritance_ui_window_test.tscn"]
scene_nodes = {}
for scene in scenes:
    source = (ROOT / scene).read_text(encoding="utf-8")
    nodes = set()
    for line in source.splitlines():
        if line.startswith("[node "):
            name = re.search(r'name="([^"]+)"', line).group(1)
            parent = re.search(r'parent="([^"]+)"', line)
            if parent is None:
                path = "."
            else:
                parent = parent.group(1)
                check(f"{scene} 父节点 {parent}/{name}", parent in nodes)
                path = name if parent == "." else parent + "/" + name
            check(f"{scene} 无重名路径 {path}", path not in nodes)
            nodes.add(path)
    for path in re.findall(r'path="res://([^"]+)"', source):
        check(f"{scene} 外部资源 {path}", (ROOT / path).is_file())
    declared = int(re.search(r"load_steps=(\d+)", source).group(1))
    check(f"{scene} load_steps", declared == len(re.findall(r"\[(?:ext_resource|sub_resource) ", source)) + 1)
    scene_nodes[scene] = nodes

panel = (ROOT / scripts[0]).read_text(encoding="utf-8")
lobby = (ROOT / scripts[1]).read_text(encoding="utf-8")
for path in set(re.findall(r"\$([A-Za-z0-9_/]+)", panel)):
    check("子窗口绑定路径 " + path, path in scene_nodes[scenes[1]])
check("正式大厅按钮与窗口实例存在", {"IdentityInheritancePanel", "Margin/Content/Actions/InheritIdentity"}.issubset(scene_nodes[scenes[0]]))
check("正式按钮真实接线", "$Margin/Content/Actions/InheritIdentity.pressed.connect(_show_identity_inheritance)" in lobby)
check("断线每帧检查", "$IdentityInheritancePanel.refresh_context()" in lobby[lobby.index("func _process"):lobby.index("func _sync_data")])
check("候选显示仅权威 label", "candidates.add_item(row.label)" in panel)
check("候选 metadata 使用 member_id", "candidates.set_item_metadata(candidates.item_count - 1, row.member_id)" in panel)
check("选择读取 metadata", "candidates.get_item_metadata(selected[0])" in panel)
check("复用既有输入模型与 revision 请求", "identity_inheritance_input.gd" in panel and "_input.request_args(_target_member)" in panel)
check("空参数候选查询及真实提交", '_session.request("identity_candidates", {})' in panel and '_session.request("identity_inherit", args)' in panel)
check("不用密钥指纹或票据作显示/选择", re.search(r"fingerprint|token|public_key|private_key|_inheritance_ticket|identity_profile|JSON.stringify", panel) is None)
check("目标在线/观战与房主权限闸", 'member.get("connected") == false and member.get("spectator") == false' in panel and 'view.get("owner") != active_session.peer_id()' in panel)
check("失败回调清理窗口", "$IdentityInheritancePanel.request_failed()" in lobby)
check("切房清理窗口", "$IdentityInheritancePanel.close_panel()" in lobby[lobby.index("func _reset_data_sync"):])
result = subprocess.run(["git", "diff", "--check", "--", scripts[1], scenes[0]], cwd=ROOT, capture_output=True, text=True)
check("受影响既有文件 git diff --check", result.returncode == 0)
for path in [scripts[0], scripts[2], scenes[1], scenes[2]]:
    text = (ROOT / path).read_text(encoding="utf-8")
    check("新增源码无行尾空白 " + path, all(line == line.rstrip() for line in text.splitlines()))
report = {"mode": "static_only", "godot_executed": False, "checks": len(checks),
          "passed": sum(c["passed"] for c in checks), "failures": [c for c in checks if not c["passed"]],
          "details": checks,
          "limitations": ["gdtoolkit 不检查 Godot 静态类型/实际 API", "未执行 Godot 加载、窗口点击、网络与持久化验收", "专项测试仅是窗口夹具源码"]}
OUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({k: v for k, v in report.items() if k != "details"}, ensure_ascii=False, indent=2))
raise SystemExit(0 if not report["failures"] else 1)
