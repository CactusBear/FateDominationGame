#!/usr/bin/env python
"""C02: inventory direct presenter -> board private accesses (stdlib only).

Semantic categories are reviewed declarations, NOT naming heuristics.
No production/plan writes. --check compares existing reports without writing.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import sys

PRESENTER = "scripts/net/ui/v2_view_presenter.gd"
BOARD = "scripts/game_scene/battle_board_v2.gd"
JSON_REPORT = "reports/refactoring/presenter-private-access.json"
MD_REPORT = "reports/refactoring/presenter-private-access.md"
CATEGORIES = {
    "render_primitive": "①纯渲染原语",
    "render_entry": "②渲染入口",
    "presentation_state": "③展示状态读写",
    "modal_lifecycle": "④模态与生命周期",
}
# Explicit, manually reviewed semantic decisions; each reason describes real code.
REVIEW = {
    "render_primitive": {
        "_area_image": "按显式 AREA_IMAGES 索引返回背景路径，不查规则。",
        "_back": "调用 LoadHelper.resolve_card_back 解析声明的牌背资源。",
        "_bind_avatar": "对传入头像节点填图并设置主题变体。",
        "_bind_badge": "对传入徽章填文字、主题并显示。",
        "_bind_card": "对传入卡位填图并按参数压暗。",
        "_bind_flow_border": "按节点尺寸绑定流动边框材质，复制共享材质并接 resized。",
        "_bind_hand_availability": "消费已给定 effects/actionable/locked，写元数据、压暗、呼吸与锁遮罩。",
        "_bind_hand_face": "消费牌面和未公开标记，更新局部卡面或触发翻面动画。",
        "_bind_pile": "按给定牌背与数量绘制两个背面及计数。",
        "_clear": "清除传入容器的非保留子节点，先摘下再 queue_free。",
        "_phase_cn": "按 PHASE_NAMES 显式表格式化阶段名称。",
        "_play_avatar_entrance": "只对给定头像和徽章启动进场动画，Tween 绑定节点生命周期。",
        "_set_img": "给指定 TextureRect 加载已提供路径的纹理。",
        "_set_text": "给指定 Label 设置文本。",
        "_set_variation": "设置传入 Control 的主题变体。",
        "_spawn": "复制 _tpl 内命名模板，显示并添加到指定父节点。",
        "_sync_items": "按目标数量增删指定模板实例，不重新计算领域数据。",
        "_wheel_direction": "从鼠标滚轮事件提取方向，static func。",
        "_wheel_scroll": "根据滚动条范围滚动传入容器并缓存横向位置。",
    },
    "render_entry": {
        "_bind_area_event_cards": "事件牌模块：同步卡位、排序、明暗绘制及放大绑定。",
        "_bind_drawer_row_remeasure": "抽屉模块：接行尺寸变化信号，触发后续重排。",
        "_bind_effect_button": "手牌模块：创建能力按钮及 PopupMenu 并接能力输入回调。",
        "_bind_phase_timeline": "阶段模块：刷新顶栏回合、阶段与夜晚圆点。",
        "_bind_played_cards_row": "出牌行模块：复用卡位、面向授权数据渲染、绑定放大与起飞登记。",
        "_bind_power_hover": "威力浮窗模块：安装悬浮回调、读取构成并定位显示 tooltip。",
        "_bind_residue_entries": "残留模块：按玩家挂载牌堆、刷新卡行并布局。",
        "_bind_rival_order": "顺位模块：复用玩家节点、排序、高亮并维护交接动画状态。",
        "_fill_buff_rows": "BUFF 模块：分别消费 Dictionary 与 BaseBuff，生成行与说明绑定。",
        "_fill_card_row_from_list": "抽屉卡行模块：重建卡位、合并重复牌、绘制牌面与数量。",
        "_layout_held_group": "手牌模块：分组与扇形布局、复用卡位并调用卡面绑定。",
        "_layout_mana_cost_preview": "预览模块：按手牌和相邻区域边界定位魔力浮窗。",
        "_layout_scroll": "战区模块：布局卷轴、席位、事件、特效与出牌区域。",
        "_play_phase_banner": "阶段模块：创建/更新横幅并替换阶段 Tween。",
        "_queue_drawer_remeasure": "抽屉模块：检测布局就绪、防重入并延迟刷新抽屉。",
        "_update_held_cards": "手牌模块：逐帧处理布局、悬浮、选择、可用性与确认按钮。",
    },
    "presentation_state": {
        "_drawer_card_size": "读取抽屉行共享空间，计算卡位尺寸。",
        "_drawer_row_cards": "查询抽屉行内部卡位容器。",
        "_drawer_row_share": "读取抽屉节点可见性和尺寸计算各行空间份额。",
        "_drawer_rows": "按显式 DRAWER_ROWS 收集当前抽屉行引用。",
        "_fly_armed": "presenter 刷新后写 true，启用后续牌飞行动效。",
        "_hover_desc": "读取悬浮说明节点引用用于输入命中判断。",
        "_hover_zoom": "读取悬浮放大节点引用用于输入命中判断。",
        "_local_player_id": "写观察者座位；setter 还同步 _seat_controller.set_single_local。",
        "_main": "读取主战区模板节点并 duplicate 创建战区内容。",
        "_main_area_index": "读取当前主战区索引用于展开完成判断。",
        "_opponent_drawer": "读取抽屉节点引用，查询可见性并取得按钮、布局和内容。",
        "_pending_tactical_action": "写待确认部署/移动请求字典，包含权威 view_seq。",
        "_phase_banner": "读取阶段横幅句柄，判空后执行 hide。",
        "_phase_tween": "读取阶段动画句柄，判空后执行 kill。",
        "_play_group_nodes": "查询当前出牌组；函数内部按帧更新缓存。",
        "_rivals": "读取顺位容器遍历子节点，隐藏各玩家残留牌堆。",
        "_scroll_is_animating": "查询当前卷轴 Tween 是否运行。",
        "_scroll_target": "按视图/本地路径及主战区索引查询卷轴目标矩形。",
        "_seats": "读取席位模板节点并 duplicate 创建战区席位。",
        "_selected_opponent_id": "读取当前抽屉选中玩家 ID。",
        "_strip_by_index": "从当前卷轴容器按索引查询节点。",
        "_strip_open": "查询卷轴视觉稳定与透明度；内部更新逐帧 meta 缓存。",
        "_strips": "读取当前卷轴容器供 presenter 填充战区。",
    },
    "modal_lifecycle": {
        "_close_card_browser": "关闭浏览器并关闭悬浮卡图。",
        "_confirm_held_cards": "绑定 PlayButton 的提交入口；网络转 selection.confirm，本地提交命令。",
        "_disable_card_zoom": "清理卡位放大元数据，必要时关闭当前悬浮与说明窗。",
        "_hide_event_zoom": "关闭悬浮放大、清理悬浮状态并按参数关闭说明窗。",
        "_is_paused": "查询暂停菜单是否可见，控制输入是否被阻挡。",
        "_is_progress_blocked": "汇总调试、动画、播报和暂停阻塞条件。",
        "_on_close_opponent_drawer_pressed": "清除选中对手状态并关闭抽屉。",
        "_on_drawer_out_of_game_pressed": "本地除外区浏览器回调，presenter 初始化时解除这条接线。",
        "_on_held_effect_pressed": "能力输入入口：单项提交或打开多项 PopupMenu。",
        "_on_hscroll_wheel": "滚轮输入接线入口：调用滚动原语并消费事件。",
        "_on_local_special_spell_input": "令咒输入接线入口：检查阻塞后转能力输入。",
        "_on_play_group_toggle": "出牌组输入接线入口：切换展开状态并消费事件。",
        "_on_strip_gui_input": "战区输入接线入口：网络转 presenter，本地走部署/移动选择。",
        "_raise_modal": "改变同父节点兄弟顺序，提升模态 GUI 输入优先级。",
        "_say": "展示临时 toast 并创建定时隐藏 Tween。",
        "_show_card_browser": "打开并填充只读浏览器，重置滚动并提升浏览器/悬浮层。",
        "_show_tactical_confirm": "设置确认描述与按钮状态，并进入确认面板生命周期。",
    },
}
BOUNDARIES = {
    "_back": "只属展示资源解析，但依赖 LoadHelper 内容环境；不等于纯字符串函数。",
    "_bind_flow_border": "原语会接信号、复制材质；纯渲染不等于无副作用。",
    "_bind_hand_face": "局部动画会写元数据并回调；按单卡视觉职责归原语。",
    "_bind_effect_button": "兼有输入接线；主归手牌模块入口，命令执行不在本函数。",
    "_bind_power_hover": "回调含本地规则读取及网络 presenter 反向调用，非纯参数渲染。",
    "_bind_rival_order": "接 opponent 输入信号并维护动画状态，不能当无状态填值函数迁移。",
    "_fill_buff_rows": "有 Dictionary/BaseBuff 双数据源；分类不表示本地分支已经迁移。",
    "_fill_card_row_from_list": "间接调用 _render_card_face；数据类型、隐私和放大职责须跟随迁移。",
    "_layout_held_group": "包含 network_session 分支，依赖 presenter.card_unpublished。",
    "_layout_scroll": "包含 network_session/MapData 双路径，不是纯几何函数。",
    "_update_held_cards": "同时查询合法性与维护输入状态；共同展示入口仍有规则耦合。",
    "_local_player_id": "赋值有 setter 副作用；不能当作普通字段赋值删除。",
    "_pending_tactical_action": "三类是字典存储归属；内容是四类确认/命令生命周期的一部分。",
    "_phase_banner": "三类是句柄归属；hide 操作同时涉及阶段展示生命周期。",
    "_phase_tween": "三类是句柄归属；kill 操作同时涉及阶段动画生命周期。",
    "_opponent_drawer": "三类是节点引用归属；读取出的对象会被展示/输入代码进一步使用。",
    "_play_group_nodes": "查询会更新帧缓存，并非无副作用 getter。",
    "_strip_open": "查询会写节点 meta 并可打印诊断，不是纯布尔计算。",
    "_scroll_target": "查询包含 network_session/MapData 分支，后续统一应移除双路径。",
    "_disable_card_zoom": "也可视为单卡绑定原语；因会关闭当前悬浮窗，主归模态生命周期。",
    "_confirm_held_cards": "四类未单列命令适配：按输入提交生命周期暂归四类，明确不是纯渲染。",
    "_on_held_effect_pressed": "混合命令提交/菜单展示；四类不足以表达未来完整组件归属。",
    "_on_strip_gui_input": "混合输入路由与规则/命令入口；不以回调名称推定为纯展示。",
    "_on_hscroll_wheel": "按对外输入回调归四类；内部滚动实现 _wheel_scroll 归一类。",
    "_on_play_group_toggle": "按输入回调归四类；只改视觉展开，不提交游戏命令。",
    "_on_drawer_out_of_game_pressed": "presenter 只持有/解除 Callable，不代表网络会执行该本地查询。",
    "_say": "toast 非严格模态；归第四类临时提示生命周期，不表示阻塞输入。",
    "_is_progress_blocked": "展示阻塞查询不等于客户端暂停了权威规则进程。",
}


def mask_noncode(text: str) -> str:
    """Mask strings/comments while preserving offsets/newlines (including triple quotes)."""
    out = list(text)
    i = 0
    while i < len(text):
        if text[i] == '#':
            end = text.find('\n', i)
            if end < 0:
                end = len(text)
        elif text[i] in ('"', "'"):
            quote = text[i]
            delimiter = quote * 3 if text.startswith(quote * 3, i) else quote
            end = i + len(delimiter)
            while end < len(text):
                if text[end] == '\\':
                    end += 2
                elif text.startswith(delimiter, end):
                    end += len(delimiter)
                    break
                else:
                    end += 1
            else:
                raise ValueError("字符串未闭合，拒绝产生不可靠统计")
        else:
            i += 1
            continue
        for j in range(i, min(end, len(text))):
            if text[j] not in '\r\n':
                out[j] = ' '
        i = end
    return ''.join(out)


ACCESS = re.compile(r'\bboard\s*\.\s*(_[A-Za-z0-9_]*)\b')
DECL = re.compile(r'^(?:@onready\s+)?(?:(?:static\s+)?func|var)\s+([A-Za-z0-9_]+)\b')
FUNC = re.compile(r'^(?:static\s+)?func\s+(\w+)\b')


def scan(text: str) -> list[dict]:
    masked = mask_noncode(text)
    source_lines = text.splitlines()
    functions = {}
    context = "<top-level>"
    for n, line in enumerate(masked.splitlines(), 1):
        match = FUNC.match(line)
        if match:
            context = match[1]
        functions[n] = context
    result = []
    for match in ACCESS.finditer(masked):
        line = masked.count('\n', 0, match.start()) + 1
        column = match.start() - masked.rfind('\n', 0, match.start())
        suffix = masked[match.end():]
        stripped = suffix.lstrip()
        if stripped.startswith('('):
            kind = 'call'
        elif re.match(r'(?:=(?!=)|\+=|-=|\*=|/=|:=)', stripped):
            kind = 'write'
        elif stripped.startswith('.bind('):
            kind = 'callable_reference'
        else:
            kind = 'read'
        result.append({"member": match[1], "path": PRESENTER, "line": line,
                       "column": column, "function": functions[line], "kind": kind,
                       "source": source_lines[line - 1].strip(),
                       "chained_operation": re.match(r'\s*\.\s*(\w+)\s*\(', suffix)[1]
                       if re.match(r'\s*\.\s*(\w+)\s*\(', suffix) else None})
    return result


def definitions(text: str) -> dict:
    masked = mask_noncode(text).splitlines()
    original = text.splitlines()
    starts = [(i, DECL.match(line)) for i, line in enumerate(masked) if DECL.match(line)]
    result = {}
    for index, (start, match) in enumerate(starts):
        end = starts[index + 1][0] if index + 1 < len(starts) else len(masked)
        # Stop at another top-level construct/comment; include indented setters/bodies.
        for i in range(start + 1, end):
            if original[i] and not original[i][0].isspace():
                end = i
                break
        while end > start + 1 and not original[end - 1].strip():
            end -= 1
        result[match[1]] = {"path": BOARD, "line": start + 1, "end_line": end,
                           "kind": "method" if 'func ' in masked[start] else "field",
                           "source": '\n'.join(original[start:end])}
    return result


def self_test() -> None:
    fixture = '''# board._comment()
var quoted = "board._string() # escaped \\\""
var multiline = """board._triple()
board._also_string()"""
func example():
\tboard._set_text(x, "board._ignored", "值") # board._other()
\tboard._local_player_id = 4
\tsignal_name.connect(board._on_strip_gui_input.bind(x))
\tboard._phase_tween.kill()
\tboard._opponent_drawer.visible
'''
    found = scan(fixture)
    assert [v['member'] for v in found] == ['_set_text', '_local_player_id', '_on_strip_gui_input', '_phase_tween', '_opponent_drawer']
    assert [v['kind'] for v in found] == ['call', 'write', 'callable_reference', 'read', 'read']
    assert found[3]['chained_operation'] == 'kill'
    assert found[0]['line'] == 6 and found[0]['column'] == 2 and found[0]['function'] == 'example'
    d = definitions('var _id: int = -1:\n\tset(v):\n\t\t_id = v\nstatic func _query():\n\treturn 1\n')
    assert d['_id']['end_line'] == 3 and d['_query']['kind'] == 'method'
    assert len([name for values in REVIEW.values() for name in values]) == len(set(name for values in REVIEW.values() for name in values))
    print('SELF-TEST PASS: comments/strings/triple quotes, coordinates, access kinds, chained effects, setters/static definitions, unique classification')


def build(root: Path) -> dict:
    pbytes = (root / PRESENTER).read_bytes()
    bbytes = (root / BOARD).read_bytes()
    accesses = scan(pbytes.decode('utf-8-sig'))
    defs = definitions(bbytes.decode('utf-8-sig'))
    decisions = {member: (category, reason) for category, values in REVIEW.items() for member, reason in values.items()}
    member_names = sorted(set(a['member'] for a in accesses))
    issues = []
    members = []
    for name in member_names:
        refs = [a for a in accesses if a['member'] == name]
        category, reason = decisions.get(name, (None, '未经过人工语义审查，不猜分类。'))
        definition = defs.get(name)
        if category is None or definition is None:
            issues.append('未分类或定义未解析：' + name)
        # Resolve all method-valued reads as Callable references using real declarations.
        if definition and definition['kind'] == 'method':
            for ref in refs:
                if ref['kind'] == 'read' and ref['chained_operation'] is None:
                    ref['kind'] = 'callable_reference'
        members.append({"name": name, "category": category, "category_label": CATEGORIES.get(category),
                        "reason": reason, "boundary_note": BOUNDARIES.get(name),
                        "definition": definition, "reference_count": len(refs),
                        "access_kinds": dict(sorted(Counter(a['kind'] for a in refs).items())), "references": refs})
    missing = sorted(set(decisions) - set(member_names))
    if missing:
        issues.append('已审查成员不再被访问，请人工删除决策：' + ', '.join(missing))
    counts = {category: {"members": sum(m['category'] == category for m in members),
                         "references": sum(m['reference_count'] for m in members if m['category'] == category)}
              for category in CATEGORIES}
    assert sum(m['reference_count'] for m in members) == len(accesses)
    return {"schema_version": 1, "task": "C02", "sources": {
                PRESENTER: {"sha256": hashlib.sha256(pbytes).hexdigest()},
                BOARD: {"sha256": hashlib.sha256(bbytes).hexdigest()}},
            "scope": "直接 board._成员；不递归计算 board.get_node、公开 API、节点别名、字符串动态调用及 board 内部间接访问。",
            "methodology": "词法屏蔽注释/字符串后扫描直接引用；四类由真实函数体与引用现场人工审查，非名字启发式。每个成员唯一主类，跨界另标。",
            "caveats": [
                "纯渲染指展示职责，不代表函数式纯函数或无信号/节点/动画副作用。",
                "field read 只表示读取句柄；chained_operation 的 hide/kill 等仍会改变被引用对象。",
                "callable_reference 包含 connect/is_connected/disconnect/bind，不能视为实际执行次数。",
                "访问次数按源码引用出现次数，而非运行时次数；同一行多引用分别保留列号。",
                "不追踪对象别名、动态字符串 API、完整 GDScript AST 与跨文件继承；当前 75 个成员均可在 board 直接解析定义。",
                "分类为本次源码的人工审查结果；源码 hash 变化必须重新审查语义，不能只重跑工具就认可旧决策。",
                "四类没有独立命令入口类别；混合输入/命令成员暂归四类并显式说明，不决定后续组件设计。",
                "未执行 Godot 场景/窗口验收；此任务只验证静态分析工具与报告一致性。"],
            "baseline_comparison": {"plan_path": "docs/refactoring-plan.md", "evidence_lines": [81, 83, 178],
                "expected_members": 75, "expected_references": 177,
                "matches_plan": len(members) == 75 and len(accesses) == 177},
            "summary": {"distinct_members": len(members), "references": len(accesses),
                        "access_kinds": dict(sorted(Counter(a['kind'] for a in accesses).items())),
                        "categories": counts, "boundary_members": sum(bool(m['boundary_note']) for m in members)},
            "issues": issues, "members": members}


def markdown(report: dict) -> str:
    s = report['summary']
    lines = ['# C02：presenter 对 board 私有成员访问', '',
             f"- 实测：**{s['distinct_members']} 个成员 / {s['references']} 次源码引用**；计划基线一致：{report['baseline_comparison']['matches_plan']}。",
             '- 本报告可供主代理合并附录 A；工具不修改计划或生产源码。',
             '- 定义范围与完整源码、逐处行列、访问类型和链式操作保存在同名 JSON。', '',
             '## 范围、口径与疑问', '', report['scope'], '', report['methodology'], '']
    lines += ['- ' + note for note in report['caveats']]
    lines += ['', '### 扫描问题', ''] + (['- ' + v for v in report['issues']] or ['- 无未知成员、缺失定义或过期分类项。'])
    lines += ['', '### 源码指纹', ''] + [f"- `{path}`：`{meta['sha256']}`" for path, meta in report['sources'].items()]
    lines += ['', '## 四类统计', '', '| 类别 | 成员数 | 引用数 |', '|---|---:|---:|']
    for category, label in CATEGORIES.items():
        c = s['categories'][category]
        lines.append(f"| {label} | {c['members']} | {c['references']} |")
    lines += ['', '访问类型：`' + json.dumps(s['access_kinds'], ensure_ascii=False) + '`。', '']
    for category, label in CATEGORIES.items():
        lines += ['## ' + label, '', '| 成员 | 引用数 | board 定义 | presenter 引用行 | 实际职责与边界 |', '|---|---:|---|---|---|']
        for m in report['members']:
            if m['category'] != category:
                continue
            d = m['definition']
            definition = f"`{d['path']}:{d['line']}–{d['end_line']}`" if d else '未解析'
            refs = ', '.join(str(v['line']) + ':' + str(v['column']) for v in m['references'])
            reason = m['reason'] + (' **跨界：**' + m['boundary_note'] if m['boundary_note'] else '')
            lines.append(f"| `{m['name']}` | {m['reference_count']} | {definition} | `{PRESENTER}`：{refs} | {reason.replace('|', '/')} |")
        lines.append('')
    lines += ['## 验证与未决边界', '',
              '- `python tools/list_presenter_private_access.py --self-test`：词法与坐标、调用/赋值/Callable/句柄、setter/static 定义专项自测。',
              '- `python tools/list_presenter_private_access.py`：从当前源码重新生成指定两份报告并校验计数守恒。',
              '- `python tools/list_presenter_private_access.py --check`：只读重算并逐字比对已落盘 JSON/Markdown，验证来源未漂移、输出可复现。',
              '- 计划附录由主代理合并；输入/命令混合职责与各跨界条目由后续任务决策，不在本任务修改生产代码。', '']
    return '\n'.join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--check', action='store_true', help='只读比对现存报告')
    parser.add_argument('--self-test', action='store_true', help='执行内置合成词法夹具，不写报告')
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    root = args.root.resolve()
    report = build(root)
    payloads = {JSON_REPORT: json.dumps(report, ensure_ascii=False, indent=2) + '\n', MD_REPORT: markdown(report)}
    if args.check:
        for relative, text in payloads.items():
            path = root / relative
            if not path.exists() or path.read_text(encoding='utf-8') != text:
                print('CHECK FAIL: 报告不存在或源码/报告已变化：' + relative, file=sys.stderr)
                return 1
    else:
        for relative, text in payloads.items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding='utf-8', newline='\n')
    print(json.dumps(report['summary'], ensure_ascii=False, indent=2))
    for issue in report['issues']:
        print(issue, file=sys.stderr)
    print('CHECK PASS' if args.check else 'REPORTS GENERATED')
    return 1 if report['issues'] else 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as exc:
        print('ERROR: ' + str(exc), file=sys.stderr)
        raise SystemExit(1)
