# Round47：退休 presenter 本人威力资源渲染闭包

## 结论与实际边界

本轮只修改 `scripts/net/ui/v2_view_presenter.gd`、新增纯组件 `scripts/game_scene/battle_io/shared_view_sections.gd` 和自有专项/执行器。board、场景、Session、source、规则、引擎均未写入。选择依据是本轮重读的真实调用，不是历史报告行号：

- board `_bind_self()` 已从 `_source.read_view()` 的 observer 玩家绘制 `Self/Stats/PowerRow/Power`、`BreakScroll/Break`。
- presenter `refresh()` 既调用 `board._bind_self()`，又在刷新开头及末尾调用 `_refresh_selection_feedback()`，重复覆写同一威力节点；开头还可能使用前一轮 `_mine` / `_sequence`。
- 阶段/残留已有共享入口，故没有扩删它们。本轮职责是**本人威力合计、短构成与 tooltip 的纯显示**，不是资源规则、魔力法阵、全部资源栏或全部 UI 解耦。

**已接生产 presenter，不是孤立 helper。** 新序号、同序号、observer 缺席、空 view 的每次刷新分别只执行一次反馈；不再在绑定当前 view 之前渲染旧本人缓存。缺席/空 view 清空合计、构成与 tooltip。选牌预览仍只在 `cards 非空 / 非 waiting / 非 submitted / preview.ok / 同 view_seq` 时采用，其他状态恢复当前本人基础构成。

**board 尚待唯一 owner 接线。** 当前 `board._bind_self()` 的基础威力段仍会绘制一次，然后 presenter 显示私有预览。不能宣称当前正式整屏已经只有一次威力绘制；本次 GREEN 的计数是 presenter 的生产 refresh 反馈次数，并截获非本职责绘制。接线契约见下一节。

## 给唯一 board owner 的精确接线契约

目标仅 `scripts/game_scene/battle_board_v2.gd::_bind_self()`。按符号/代码匹配，禁止按下面的旧行号硬删。

原威力段从 `var brk: Dictionary = player.get("power_breakdown", {})` 开始，经过本地 `GetPlayerTotalPower.breakdown(...)`、`power_label`、`_set_text(stats, "PowerRow/Power", ...)`、`_bind_power_hover(...)`、`parts` 循环，直到 `stats.get_node("PowerRow/BreakScroll").visible = not parts.is_empty()`。其后的 `_bind_spell_box(...)` 和本人头像/名字必须保留。魔力 `MagicSigil.set_value`、战果/名次也必须保留。

把上述段替换为：

```gdscript
var power_label := stats.get_node("PowerRow/Power") as Control
_bind_power_hover(power_label, _local_player_id, true)
if network_session == null:
	var brk: Dictionary = player.get("power_breakdown", {})
	if not _selected_cards.is_empty():
		brk = GetPlayerTotalPower.breakdown(_local_player_id, _selected_cards_power(), _selected_cards.duplicate(), _selected_cards_hidden())
	preload("res://scripts/game_scene/battle_io/shared_view_sections.gd").render_self_power(stats, player, brk, false)
```

- 本地规则计算保留原入口，不把 UI helper 当规则；`tooltip_enabled=false` 保留本地原 hover 绑定和既有 tooltip 行为。
- 网络 `_bind_self()` 继续处理本人面板、从者、魔力、战果/名次、令咒、头像与 hover，但**不再绘制基础威力**；唯一威力绘制在 presenter 已设置本轮 `_mine` / `_sequence` 之后。
- 本地模式用同一组件，网络模式在 presenter 用同一组件，文本/构成不存在第二份实现；不要在 network 分支再调用一次组件。
- `power_lines(player)` 留作薄兼容入口，因为 board 的 `_on_power_hover_enter()` 仍直接调用 `_network_presenter.power_lines(_network_presenter.player_view(pid))`。不要删除此真实消费者。
- 若 owner 更偏好 board 公共门面，可新增 `render_self_power_view(player: Dictionary, breakdown: Dictionary)`，内部仅转调组件；然后由主代理把 presenter 的那**一行**组件调用换成该公开方法。现在没有这个公开入口，因此生产 presenter 直接调用纯组件；不得 `call()` 私有方法、反射探测或增加 fallback 双绘制。
- observer 缺席清空已经在 presenter 生效；本地 `_bind_self()` 的无 player 早退若要额外清文字，可在早退前调用组件传 `{},{},false`，不要显示 Self 或借其他 player 填数。

## 新组件契约与耦合退休

`SharedViewSections.render_self_power(stats, player, breakdown, tooltip_enabled=true)`：调用者传当前 observer 的过滤 player、已经选定的构成以及稳定场景节点。只改三个既存节点的 text/tooltip/visible，不读 Session/source/GameData，不查规则，不遍历对手，不增删节点，不创建 Tween，不触碰 modal/zoom。

`SharedViewSections.power_lines(player)`：保留原 tooltip 顺序、正号、零值省略和 `BaseNumber.display_text` 数值格式。presenter 的 `power_lines()` 已转调它，原实现循环退休。

presenter `_refresh_selection_feedback()` 内本人合计/短构成原循环以及两次 `board._set_text(...)` 私有调用退休。费用仍调用 `board._render_group_cost_preview(board._read_group_preview(), input_available())`，未假称该费用入口公开化。本人 `_mine` 是 presenter 自有传输缓存，本轮没有跨到 board 私有规则状态。

## RED → GREEN 与真实命令

执行命令（仅 headless，E 独占副本）：

```bash
python tests/round47_presenter_runner.py
python tests/round47_presenter_runner.py res://tests/refactor_held_actions_test.tscn
```

执行器先构造显式依赖白名单的 E 源码副本，记录每个原文件 SHA256，再在该副本运行。底层 runner 的 `freeze=false` 表示它消费**已经冻结的 source 副本**，不是在正式仓库运行；底层 manifest 的 `source_files=[]` 由外层 `ownership.json.source_files` 补足。没有复制整棵 tests、旧 report 或 .godot。

| 阶段 | E 证据根 | 实际结果 |
|---|---|---|
| 有效业务 RED | `E:/scratch/round47-presenter-fdc42dd28660497ca1e559f450b377b1` | scene 退出 1；16 checks；3 个 failures：新序号两次反馈、缺席 observer 未清空、空 view 未清空；scene.stderr 空；源码无漂移 |
| 初次 GREEN | `E:/scratch/round47-presenter-38c1f3e768f146b69bb690c78093c286` | scene 退出 0；16 checks；failures=[]；stderr 空；源码无漂移 |
| 最终闭包 GREEN | `E:/scratch/round47-presenter-fbd484e693af475f826abe2851ba7075` | scene 退出 0；23 checks；failures=[]；stderr 空；源码无漂移 |
| 原持有卡回归 | `E:/scratch/round47-presenter-476a35dd69d14f15bcbe0e69b475e7f4` | scene 退出 0；43 checks；failures=[]；stderr 空；源码无漂移 |

最终闭包与持有卡回归的共同源码 SHA256 集合逐项比较，无不一致。前一次 23-check GREEN 根 `...98bb128fb4534cff96834059eb1950fa` 运行期间 Session 被其他 owner 修改，保留其漂移记录但不作为最终冻结结论，随后已重新冻结通过。

23 项覆盖真实 `MatchAuthority.view_for/preview_group` 的非空视图/私有预览、真实 board 原 `_bind_self()` 威力文字与新反馈等价、waiting/submitted/stale/rejected 回退、同 seq 反馈、observer 缺席/空 view/同 seq 恢复、三个节点 instance_id、负小数/零值/tooltip。`ProbeBoard` 只为隔离其他职责截获绘制和输入，基础等价测试实际调用 `super._bind_self()`，魔力/令咒/hover 等无关入口截获。phase key 不变和关闭 zoom/modal 不复活只证明这个纯闭包未改它们，不是完整动画或实际鼠标验收。

最终生产文件摘要：

- presenter：`7b6dfe7d484a3eb5a6482df9f25fcc0b9df50d21bce3c5d5dc65370fd36bf966`
- shared component：`c720b26ea254b585e4d1415698738194474c3a5254a171f6bc45be7ddecc602b`

### 隔离、失败与回收

所有实际 Godot 均为未改字节的 4.7.2 主程序独占 E 副本，复制前后摘要相等。main/真实 OS.create_process child 都落入本轮独占 E user 目录，随机 token 与 JSON 回执读回通过；最终 main PID 19636、child PID 38476、scene PID 29044。Job Object 挂起加入后恢复，根/child 退出、ActiveProcesses=0、日志句柄释放后回收；每进程外层预算 180 秒。这里只把 child 探针称为落盘/退出证明，不替代正式对局 worker 验收。

首轮冷导入 `...8ba4ed8a144648ea90131a981716953e` 缺扩展 DLL 且 Cursor 图片 preload 先于 import，保留失败证据。随后补全扩展/资源依赖，在隔离配置临时移除 Cursor autoload 做资源导入，再恢复完整 autoload 严格导入/运行。只在副本关闭 VCS 自动启用与 editor plugin；不改正式 project.godot。此流程不代表正式冷导入发行门通过。

夹具首轮 Control/Node override 签名错误造成 180 秒超时根 `...654e4a7068d5409e8e255a09bd7efffe`；已按真实父签名修复。后续 `--check-only --script` 缺 autoload 全局名的失败根 `...9e64d6dee16d4b29989a708e89590dd0` 已保留，不算业务 RED。改用真实场景加载入口和 fail-fast watchdog。ModalLayer 下真实抽屉路径已按现 scene 修正，不改生产场景。所有本轮生成 source/engine 和底层 generated 已回收，保留小型日志/manifest/ownership；不按名称清扫其他 Godot 进程。

## 窗口 owner 最小接线后命令（本代理未开窗口）

由 `sa-0-2a9d86fa` 在其批准的 E 冻结工程与 E 引擎上执行；先落实上面的 board 威力段退休：

```bash
"<OWNED_E_GODOT>" --fixed-fps 60 --path "<OWNED_E_FREEZE>" --scene res://tests/net_v2_ui_input_parity_window_test.tscn -- window
```

该现存套件显式拒绝 headless，包含实际客机认证、真实鼠标选牌、`ManaCostPreview` 的 4/6、本人预览总威力及“出牌 6”的断言，并测试原手牌 instance_id。不可用本轮 headless 场景改成非 headless 冒充输入验收。另用实际输入确认打开/关闭 card browser 后 zoom 不复活；继承身份/空视图/同序号恢复需要完整 Session/ENet 专项，本轮这里只验闭包生命周期，没有声称已复验整条网络恢复链。

## 具体剩余耦合引用（当前源码扫描）

presenter 仍有 **86 次 board 私有符号引用 / 57 个不同私有符号**，不是“已全解耦”。明确仍保留：

- `refresh()` → `_bind_shared_phase_view`、`_bind_rivals`、`_bind_residue_piles`、`_bind_self`、`_bind_strips`、`_fill_buff_rows`；写 `_local_player_id`、`_fly_armed`，读取 `_opponent_drawer`。
- `_refresh_group_reveal()` → `_scroll_is_animating/_strip_open/_strip_by_index/_main_area_index/_play_group_nodes/_play_avatar_entrance`，仍直接参与 reveal 元数据生命周期。
- `_bind_action_hint()` → `_phase_cn` 与两次 `_set_text`，及 location choice 的原 renderer/Panel cancel 回调。
- `_bind_hand()` → `_layout_held_group` 三次与 `_update_held_cards`；`bind_hand_card()` → `_bind_hand_face/_held_card_playable/_bind_hand_availability`。
- `browse_input()` → `_hover_zoom/_hover_desc/_hide_event_zoom/_drawer_rows/_wheel_scroll/_on_close_opponent_drawer_pressed` 等 modal/输入状态。
- `area_input/_invalidate_area_confirmation()` → `_pending_tactical_action/_pending_confirm_desc/_confirm_alert_mode/_tactical_confirm`，仍是部署/移动确认适配。
- `power_lines()` 现为无 board 访问的组件转调；`_refresh_selection_feedback()` 仅残留费用的 `_render_group_cost_preview/_read_group_preview`，本人威力没有私有原语访问。

## 文件交付

- 改：`scripts/net/ui/v2_view_presenter.gd`
- 新：`scripts/game_scene/battle_io/shared_view_sections.gd`
- 新：`tests/round47_presenter_power_test.gd`、`.tscn`、`tests/round47_presenter_entry.gd`、`tests/round47_presenter_runner.py`
- 新：本报告。

`git diff --check` 在本次范围通过。`git check-ignore` 确认自有 tests 被仓库规则忽略，主代理打包/接线时须显式包含这些真实文件，不要只看 git status。没有 commit/add。复用技能 `godot-presenter-preview-handoff` 已补充“反馈在本轮 view 绑定后 / 计数真实 refresh / 未接 board 只算局部 GREEN”的迁移规则。
