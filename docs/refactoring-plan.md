# 单机与联机 UI 统一及项目高耦合重构方案（v2：任务级）

> **最新停止交接见 §7（2026-10-12）**：按用户最后选择，本轮不启动 Godot；已验证成果、未验候选、剩余字母/编号、阻断及接手路径均已记录。不自动续跑。

> v1 原文备份在 `backups/refactoring-plan/refactoring-plan.v1.md`。v2 沿用 v1 的结论、优先级和各耦合点的验收口径（v1 §4 C01–C12 的「验收」段依然有效，本文不重复），补上 v1 漏掉的耦合点，修正部分描述，并把每个批次拆成**原子任务**：每项只改一处、只跑一条命令、可以单独回退。
> 本文已进入实施，逐轮状态及实际验收证据见 `docs/refactoring-execution.md`。原行号对应重构前工作树；A01 首次核对 383 个脚本无漂移，此后迁移须按符号重新定位，不覆盖原 inventory 以掩盖变化。原 6/16 白名单数字不是完整词法访问计数；A04/A05 实测基线为跨层 13 次、私有访问 116 次，按精确锚点逐项退休。

## 0. 使用方式

- 任务编号形如 `B07`。每项都写明 **改动 → 验证 → 完成判据**。回退默认用 `git checkout -- <本任务涉及的文件>`；如果不提交，每项完成后执行 `git diff > backups/refactoring-plan/<编号>.patch`。
- 决策 D1–D6 已于 2026-10-09 由用户拍板（D5 选 B，其余选 A），结论见 §6，相关任务已按结论改写，不再等待。
- 命令约定（bash，仓库根目录）：

```bash
GODOT="D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
t()  { timeout 180 "$GODOT" --headless --fixed-fps 60 --path . --scene res://tests/$1.tscn 2>&1 | grep -E 'RESULT|SCRIPT ERROR|SHADER ERROR'; }
tw() { timeout 240 "$GODOT" --fixed-fps 60 --path . --scene res://tests/$1.tscn -- window 2>&1 | grep -E 'RESULT|SCRIPT ERROR'; }   # 窗口段必须带 -- window
gate() { python tools/check_layer_deps.py; }   # 由 A04 创建
```

- 「专项」指 `t <套件>`：`RESULT` 全绿，且没有 `SCRIPT ERROR`。窗口套件还要与 headless 的 checks 数对比，确认窗口段确实执行了。

## 1. 结论（相对 v1 的变化）

目标不变：**同一场景、同一展示模型、同一套渲染与交互实现，只有数据源和命令端两个适配器不同**。规则只由一处执行，本地不绕道虚拟网络。

v2 新增或纠正的内容如下。

1. **旧 UI 中被规则层复用的部分只有 16 个静态函数（约 421 行）和 2 个常量**，依赖闭包见 §2.1。它们可以按「位置规则 / 卡面文本 / 日志与费用文本」三个职责整体迁出。旧 UI 里只留一行转发，21 个仍在实例化旧 UI 的测试不受影响。
2. v1 漏了 `match_authority.gd:595`：权威端的 `cost_text` 直接调用了旧 UI 的 `_attach_cost_line` 和 `_resolve_effect_cost_items`，问题与 `:565` 同类。
3. v1 漏了调试链里的鸭子类型调用：`debug_map_adapter.gd:56–59` 通过 `host.call("_estimate_move_cost")` 调用宿主方法，但当前宿主 `battle_board_v2.gd` **没有这两个方法**（grep 结果为 0）。结果是魔力预检被静默跳过，玩家只看到笼统的「移动被规则拒绝」，看不到「魔力不足」。这是静态可判定、尚未复现的缺陷，由 B07 处理。
4. 网络权威端调用了 EffectManager 的 5 个私有方法：`_is_card_selection_valid`、`_location_option_origin_allowed`、`_effect_fact_actor_id`、`_effect_source_name`、`_guard_audit_failed`。另外，`effect_checkpoint`、`rule_state`、`match_replay` 直接读写 EffectManager 的 5 个私有容器，`rule_state` 和 `effect_checkpoint` 还会读写 `DummyBot` 的静态状态。合计 16 处访问、10 个私有成员，由只减不增的「棘轮」闸门逐步清零（A05、F 批）。
5. `match_authority._submit` 会按 kind 校验参数和座位，再分派执行，共 12 种 kind：cancel_choice、location_choice、activate、player_choice、card_choice、option_choice、active_choice、set_concealed、move、play_group、end_action、deploy。单机 UI 则直接调用 `_commands.*`，**缺少这一层校验**。按 D4=A，把「逐 kind 校验 + 分派」抽成与连接无关的分派器，权威端和本地命令适配器共用；peer、seq 和审计闸门仍只放在权威端。
6. `actions_for`、`pending_for`、`preview_group` 的主体是按座位做的规则投影，与 peer 无关。单机要做到与联机一比一，就复用这三段，不在 UI 里重算合法性（C04–C06）。
7. `battle_board_v2.gd` 中有 29 个函数含 `network_session` 分支，清单见 §2.3。这份清单就是 D 批的完成清单，清空才算统一完成。
8. 联机 UI（`scripts/net/ui/`）里**完全没有战斗播报代码**，而单机的播报会阻塞规则推进（`game_progress.gd:443–470`）。v1「需确认 1」背后的实际问题是这个缺口，而不只是口径没定。
9. `_fill_buff_rows`（`battle_board_v2.gd:2761`）同时处理 `Dictionary`（网络）和 `BaseBuff`（本地）两个分支，是「双数据源渲染」的典型例子，所以选它作为 C 批的样板迁移：迁移后删掉 `BaseBuff` 分支。
10. 命名冲突预检：拟新增的 `class_name` 都不与现有全局类重名。但 `view_builder.gd:4` 有一个局部常量叫 `CardText`，新模块**不能**用这个名字，否则会触发 Godot 4 的「常量遮蔽全局类」，因此改名为 `CardDescText`。
11. v1 中保持不变的部分：§3.1 数据边界的 7 条原则、§3.2 操作边界、各耦合点的验收清单、§6「必须新增或增强」的 9 项测试要求。本文 §4 把这些要求落到具体任务上，并逐项标注出处。

## 2. 当前源码证据

### 2.1 旧 UI 中被外部复用的静态函数（依赖闭包）

| 函数（`tactical_board_ui.gd`） | 行 | 行数 | 依赖 | 外部调用方 | 拟归属 |
|---|---:|---:|---|---|---|
| `_first_effect_location_target` | 2427 | 24 | MapData, SetLocation | match_driver:117, match_authority:692, v2:5010 | AreaActionRules |
| `_local_current_area` | 3275 | 8 | — | v2:5055 | AreaActionRules |
| `_estimate_move_cost` | 3283 | 17 | MoveLocation.step_cost_discount, MapData | match_authority:664, v2:5066, debug_map_adapter:57（鸭子类型） | AreaActionRules |
| `_is_magic_enough_for_move` | 3300 | 8 | — | v2:5067, debug_map_adapter:58（鸭子类型） | AreaActionRules |
| `area_action_block_reason_for` | 3312 | 71 | 上面四个函数 + move_lock_reason + _phase_shown_name；DeployRules, EffectManager, GameProgress, IsEngaged, GetLocation, GetMoveTargetLocation | match_authority:259,660；v2:1903,5029 | AreaActionRules |
| `move_lock_reason` | 3383 | 9 | SetLocation | 闭包内 | AreaActionRules |
| `_phase_shown_name` | 3396 | 9 | — | 闭包内；旧 UI:782,3351 | AreaActionRules（规则拒绝原因的用语） |
| `_object_shown_name` | 2809 | 12 | — | 闭包内；旧 UI 多处 | CardDescText.shown_name |
| `_build_card_desc` | 2756 | 53 | Attributes, FIELD_LABELS, ATTACK_CATEGORY_LABELS | view_builder:307,331；v2:4488；tests/san_no_tachi_test:44 | CardDescText |
| `_build_token_desc` | 2888 | 67 | _object_shown_name | view_builder:245；v2:2734,4304 | CardDescText |
| `_resolve_effect_cost_items` / `_collect_cost_items` / `_format_cost_item` / `_attach_cost_line` | 4024–4068 | 40 | — | match_authority:595；v2:3326,3332 | CostText |
| `_format_game_log_line` | 4912 | 90 | TimePoints, _player_shown_name_by_id | view_builder:218；v2:4993 | GameLogText |
| `_player_shown_name_by_id` | 5260 | 8 | GameData, GameDataManager | 闭包内 | 按 D5=B，经 golden 比对后合并到 `EffectManager.player_shown_name`（B25–B31），GameLogText 不再保留副本 |
| 常量 `ATTACK_CATEGORY_LABELS` / `FIELD_LABELS` | 128 / 134 | — | — | view_builder:370–371 | CardDescText |
| `native_choice_renderer.card_confirm` | 146 | 4 | — | match_authority:565 | ChoiceText |

### 2.2 其他已确认的跨层依赖与副作用（v1 已列条目，此处补充具体位置）

| 编号 | 位置 | 问题 |
|---|---|---|
| C02 | `game_data_manager.gd:23–28` | `get_player_data` 遇到不存在的玩家时会写入全局字典。全仓 195 处调用，其中 operations 有 75 处，global 有 9 个文件；`v2:554` 和 `ActionRules.requirements` 已各自手写「先 has 再取」。 |
| C05 | `game_progress.gd:443–470`；`rule_state.gd:53,58`；`effect_checkpoint.gd:41,59,66–73` | 规则推进是否等待播报，取决于某个 Node 消费者是否存活；快照和检查点都会捕获这个 Node 引用。 |
| C06 | `effect_checkpoint.gd:38–42,74–77`；`rule_state.gd:39–48`；`match_replay.gd:37,157` | 直接读写 EffectManager 的私有容器，以及 `DummyBot._phase_attempted_effect_ids` 静态字典。 |
| C07 | `load_game.gd:19–27`；`stored_jsons_path` 有 9 处写入（lobby_session:1389/1391/1399/1424/1745/1839，match_authority:516/535，server_room_worker:201，room_data_validation_worker:62），`LoadHelper.session_data_dir` 同步切换 | 全局数据根靠「保存旧值 → 改写 → 恢复」手工配对，失败路径容易漏掉恢复。 |
| C08 | `room_data_preparation.gd:43,90,97,106,109,121,169,185` | 直接访问 `session.room._humans` 和 `session.blobs.*`。 |
| C10 | `view_builder.gd:250–260`；`effect_manager.gd:374–425,636`；`network_choice_panel.gd:9,32,48,65–67` | 通知 ID 由「队列名 + 下标」拼成；本地 `pop_messages` 会删除或回插队列元素；客户端的 `_seen_messages` 只在切换观察者时才清空。 |
| C11 | `debug_session.gd:177–179`；`debug_console_ui.gd`；`debug_map_adapter.gd:56–59` | 用 `host.has_method/call` 以鸭子类型调用宿主的私有方法。 |
| C12 | `project.godot:41` 声明了 `_mcp_game_helper`，而 `export_presets.cfg:15,86` 的 exclude_filter 不含 `addons/godot_ai/*`；`tools/copy_data_after_export.py:24` 隐式取第一个 preset | 发行包可能带上开发期的 autoload。 |
| — | `battle_board_v2.gd:22` 的 `PHASE_NAMES`（「准备」）与旧 UI 的 `_phase_shown_name`（「准备阶段」） | 两处用语不同，**不能直接合并**，迁移时各自保持原样。 |

### 2.3 `battle_board_v2.gd` 中带网络分支的函数（D 批完成清单）

`_ready` `_exit_tree` `_default_area_index` `_return_to_network_lobby` `_process` `refresh_all_ui` `_on_strip_gui_input` `_input` `_scroll_target` `_select_scroll` `_layout_scroll` `_layout_held_group` `_held_card_playable` `_held_playable_signature` `_update_held_cards` `_on_held_card_input` `_on_held_effect_pressed` `_request_held_effect` `_manual_effects_of` `_bind_hand_card` `_held_input_available` `_can_confirm_held_cards` `_confirm_held_cards` `_on_tactical_confirm_execute` `_return_to_main_menu` `set_debug_console_enabled` `_update_drawer_visuals` `_bind_power_hover` `_on_played_card_input`（共 29 个）

最终只允许 4 类保留分支：`_ready`（选择适配器）、`_exit_tree` 和 `_return_to_*`（会话生命周期，E 批移交给宿主）、`set_debug_console_enabled`（单机与联机的能力差异）。

### 2.4 `v2_view_presenter.gd` 对 board 私有成员的访问

共访问 75 个不同成员、引用 177 次。高频成员：`_set_text`(39)、`_opponent_drawer`(6)、`_bind_avatar`(6)、`_sync_items`(5)、`_back`(5)、`_show_card_browser`(4)、`_phase_tween/_phase_banner`(4)、`_bind_pile`(4)、`_fill_buff_rows`(2)……C02 任务会把它们分成四类：①纯渲染原语，②渲染入口，③展示状态读写，④模态与生命周期。D 批结束后，①由共同控制器内部继续使用，②～④随模块迁移消失。

## 3. 目标结构

```text
规则全局（EffectManager/GameProgress/GameData/MapData…）
   │ 只读                                   │ 执行
   ▼                                        ▲
MatchViewBuilder.build(seat)   MatchSeatQuery(actions/pending/preview)   MatchCommandDispatcher(seat, kind, args)
   │                               │                                         ▲
   ├─ LocalBattleSource ───────────┤                       LocalBattleCommands ┤（同步，绑定本地座位）
   │                               │                                         │
   └─ 网络：Authority → Mirror → NetworkBattleSource          NetworkBattleCommands → session.request → Authority(peer/seq/审计) ┘
                    │
                    ▼
        battle_board_v2（唯一的渲染与交互实现：只读 source，只写 commands）
```

层规则由 A04 的闸门强制执行：
- `scripts/system/**`、`scripts/match/**`、`scripts/net/{authority,session,server,content,validation,transport,identity}/**` 不得引用 `scripts/game_scene/**`、`scripts/net/ui/**`、`assets/scenes/**`。唯一例外是 `server_bootstrap` 的场景路由，列入白名单。
- `scripts/ui/text/**` 不继承 Node，也不引用 game_scene，但可以读取规则对象（它的职责就是格式化规则对象）。权威端和 ViewBuilder 可以依赖它。
- **先授权，再格式化**：`card_desc` 只能用于本人拥有或已公开的对象。这个判断由 ViewBuilder 的 `own` 负责，不下放给文本模块。

拟新增组件：`AreaActionRules`（`scripts/system/area_action_rules.gd`）；`CardDescText`、`CostText`、`GameLogText`、`ChoiceText`（`scripts/ui/text/`）；`MatchSeatQuery`、`MatchCommandDispatcher`（`scripts/match/`）；`LocalBattleSource`、`NetworkBattleSource`、`LocalBattleCommands`、`NetworkBattleCommands`（`scripts/game_scene/battle_io/`）；`ContentEnvironment`（`scripts/system/global/`）。

已否决的方案：
- 通用服务定位器或事件总线：会把显式依赖变成隐式依赖，违背「数据显式声明」。
- 让本地也走 `NetworkMatchAuthority`：会凭空引入 peer、seq、审计等语义，还需要伪造一个 peer。
- 把 16 个函数合成一个 `BoardHelpers`：规则查询和展示文本的变化原因不同，合在一起只是把耦合换了个文件。
- 修改 `MoveLocation` 来提供估算函数：违背「尽量不改现有 operation」，见 D6。

## 4. 实施任务

### 批次 A：基线与闸门（不改生产代码）

- [ ] **A01** 新建 `tools/check_inventory_drift.py`：读取 `docs/refactoring-coupling-inventory.json`，逐个比对 `scripts/**/*.gd` 的 sha256，输出 new、gone、drift 三个列表。运行后，把输出连同 `git rev-parse HEAD` 和 `git status --short | wc -l` 一起写入 `reports/refactoring/baseline.txt`。→ 完成判据：drift 为空；不为空时，先用 `grep -n` 重新定位本文引用的行号。
- [ ] **A02** 逐个运行 headless 基线：`for s in match_view_test match_view_privacy_test match_commands_test match_driver_headless_test net_pending_test net_cards_test net_move_test net_locations_test net_authority_ui_preview_feedback_test area_lock_window_test bellerophon_edges_test misc_rules_fix_test mana_spend_test reported_ui_test number_display_test san_no_tachi_test debug_console_test battle_broadcast_test turn_transition_test battle_board_v2_test deploy_rules_layer_test player_name_test command_spell_test full_game_test; do echo "== $s"; t $s; done > reports/refactoring/baseline-headless.txt`。→ 完成判据：每个红项都注明原因（依赖真实鼠标、已知缺陷或新问题），不能笼统写成「历史失败」。
- [ ] **A03** 窗口基线：`for s in area_lock_window_test native_choices_window_test net_v2_browsing_window_test net_v2_ui_input_parity_window_test net_v2_area_window_test net_v2_residue_phase_window_test; do echo "== $s"; tw $s; done > reports/refactoring/baseline-window.txt`，逐个记录 checks 数。
- [ ] **A04** 新建 `tools/check_layer_deps.py`：扫描 §3 层规则涉及的目录，找出 `preload("res://…")`、`load("res://…")` 和 class_name 文本引用（跳过 `#` 注释行），与内置白名单比对。初始白名单恰好是现存的 6 处：`match_driver.gd:6`、`view_builder.gd:4`、`match_authority.gd:565`、`match_authority.gd:595`、`load_game.gd:22`、`server_bootstrap.gd:76–79`。出现白名单外的违规时返回 1；白名单中某一项已经消失时也返回 1，并提示「请删除白名单项」，这样白名单只减不增。→ 验证：运行 `gate`，退出码为 0。
- [ ] **A05** 在同一脚本中加第二条规则：除 EffectManager、GameProgress、DummyBot 自身外，任何文件访问 `EffectManager._x`、`GameProgress._x`、`DummyBot._x` 都算违规。初始白名单是 §1 第 4 条列出的 16 处。→ 验证：`gate` 退出码为 0。
- [ ] **A06** 新建 `tests/refactor_text_golden_test.gd/.tscn`。先用 `GameStart.game_start` 加固定种子开局，遍历 `GameData.objects`，对每张卡牌、每个 BUFF、每个效果记录 `_build_card_desc`、`_build_token_desc`、`_attach_cost_line("", _resolve_effect_cost_items(e))` 的结果；再用 `MatchDriver` 推进 3 个回合，对 `GameLog.query({}, null)` 的每条记录执行 `_format_game_log_line`。首次运行带 `-- capture`，把结果写入 `docs/refactoring-golden/text.json`；不带参数时为比对模式。→ 验证：capture 之后立即比对一次，结果全绿。
- [ ] **A07** 新建 `tests/refactor_area_golden_test.gd/.tscn`：用固定种子和 MatchDriver 推进完整一局。每一步都对每个玩家、每个战区记录 `area_action_block_reason_for`、`_estimate_move_cost(data, step)`、`_first_effect_location_target`（记录 NetIds 稳定 id），另加一个手工构造的 `area_locked` 场景。capture 和比对的用法同 A06。→ 完成判据：比对全绿；临时把 `move_lock_reason` 改成返回空串时，测试必须变红，验证后立即恢复。
- [ ] **A08** 新建 `tests/refactor_build_cost_probe.tscn`：7 人对局，每个阶段调用 `MatchViewBuilder.new().build(seat)` 100 次，打印 p50 和 p95 耗时。→ 产出写入 §6，作为 C01 的依据。

### 批次 B：去掉规则层对 UI 的反向依赖（C01），并提供无副作用的玩家查询（C02）

**B-1 位置规则**

- [ ] **B01** 新建 `scripts/system/area_action_rules.gd`（`class_name AreaActionRules extends RefCounted`），把 §2.1 中归属 AreaActionRules 的 7 个函数**原样复制**过来，改成公开名：`current_area`、`estimate_move_cost`、`magic_enough_for_move`、`block_reason(player_id, area_idx)`、`move_lock_reason`、`phase_shown_name`、`first_effect_location_target`，函数之间的互相调用同步改名。不改任何调用方。→ 验证：编辑器中 `script_manage find_symbols` 能解析，`logs_read source=editor` 无报错。
- [ ] **B02** 把 `tactical_board_ui.gd` 中这 7 个函数的函数体改成一行转发，例如 `return AreaActionRules.block_reason(player_id, target_area_idx)`，签名不变。→ 验证：`t refactor_area_golden_test && t area_lock_window_test && t misc_rules_fix_test`。
- [ ] **B03** `match_driver.gd`：删除第 6 行的 `const LocationQuery`，第 117 行改为调用 `AreaActionRules.first_effect_location_target`。→ 验证：`t match_driver_headless_test`；删除对应白名单项后 `gate` 通过。
- [ ] **B04** `match_authority.gd` 第 259、660、664、692 行：把 `driver.LocationQuery.*` 改成 `AreaActionRules.*`。→ 验证：`t net_move_test && t net_locations_test && t net_pending_test`。
- [ ] **B05** `battle_board_v2.gd` 第 1903、5029 行：把 `TacticalBoardUI.area_action_block_reason_for` 改成 `AreaActionRules.block_reason`。→ 验证：`tw area_lock_window_test`。
- [ ] **B06** `battle_board_v2.gd` 第 5010、5055、5066、5067 行：改为调用对应的 `AreaActionRules.*`。→ 验证：`t battle_board_v2_test && t bellerophon_edges_test`。
- [ ] **B07** `debug_map_adapter.gd` 第 56–59 行：删除 `host.has_method/call`，直接调用 `AreaActionRules.estimate_move_cost` 和 `magic_enough_for_move`。**这是行为修正**：魔力不足时，调试控制台将返回「魔力不足，不能执行常规移动」，而不是「移动被规则拒绝」。→ 先在 `tests/debug_console_test.gd` 新增用例：魔力为 0 时移动 1 步，断言 error 包含「魔力不足」。确认该用例改动前为红、改动后为绿，再运行 `t debug_console_test`。

**B-2 展示文本**

- [ ] **B08** 新建 `scripts/ui/text/card_desc_text.gd`（`class_name CardDescText`），复制 `ATTACK_CATEGORY_LABELS`、`FIELD_LABELS` 两个常量，以及 `_object_shown_name`（改名 `shown_name`）、`_build_card_desc`（改名 `card_desc`）、`_build_token_desc`（改名 `token_desc`）。→ 验证：编辑器能解析。
- [ ] **B09** 新建 `scripts/ui/text/cost_text.gd`（`class_name CostText`），复制费用相关的 4 个函数，分别改名为 `effect_cost_items`、`_collect`、`_format_item`、`attach_line`。→ 验证：编辑器能解析。
- [ ] **B10** 新建 `scripts/ui/text/game_log_text.gd`（`class_name GameLogText`），复制 `_format_game_log_line`（改名为 `line`）。函数里原来调用 `_player_shown_name_by_id` 的地方，先临时复制成一个私有函数 `_player_name`（内部调用 `CardDescText.shown_name`），保证 A06 golden 的输出逐字不变；这个副本由 B26 删除。→ 验证：编辑器能解析。
- [ ] **B11** 新建 `scripts/ui/text/choice_text.gd`（`class_name ChoiceText`），复制 `card_confirm`；`native_choice_renderer.gd:146` 的函数体改为转发。→ 验证：`tw native_choices_window_test`。
- [ ] **B12** 把 `tactical_board_ui.gd` 中 B08–B10 涉及的函数体改为转发；两个常量改为 `const ATTACK_CATEGORY_LABELS = CardDescText.ATTACK_CATEGORY_LABELS`，`FIELD_LABELS` 同理。→ 验证：`t refactor_text_golden_test && t reported_ui_test && t number_display_test`。
- [ ] **B13** `view_builder.gd`：删除第 4 行的 `const CardText`；第 218 行改为 `GameLogText.line`；第 245 行改为 `CardDescText.token_desc`；第 307 和 331 行改为 `CardDescText.card_desc`；第 370–371 行改为 `CardDescText.ATTACK_CATEGORY_LABELS`。→ 验证：`t match_view_test && t match_view_privacy_test`；删除白名单项后 `gate` 通过。
- [ ] **B14** `match_authority.gd:565` 改为调用 `ChoiceText.card_confirm`。→ 验证：`t net_pending_test`；删除白名单项后 `gate` 通过。
- [ ] **B15** `match_authority.gd:595` 改为 `CostText.attach_line("", CostText.effect_cost_items(effect)).strip_edges()`。→ 验证：`t net_pending_test && tw native_choices_window_test`；删除白名单项后 `gate` 通过。到这一步，白名单只剩 load_game 和 server_bootstrap 两项。
- [ ] **B16** `battle_board_v2.gd`：第 2734、4304 行改为 `CardDescText.token_desc`；第 4488 行改为 `CardDescText.card_desc`；第 3326、3332 行改为调用 `CostText`；第 4993 行改为 `GameLogText.line`。→ 验证：`t battle_board_v2_test && tw native_choices_window_test`。
- [ ] **B17** 用 `grep -n 'TacticalBoardUI\.' scripts/game_scene/battle_board_v2.gd` 确认没有剩余调用后，删除 `battle_board_v2.gd:279` 的 `const TacticalBoardUI`。→ 验证：编辑器能解析，且 `t battle_board_v2_test` 通过。

**B-3 无副作用的玩家查询（C02）**

- [ ] **B18** 在 `game_data_manager.gd` 的 `get_player_data` 下方新增 `func find_player_data(id:int) -> Dictionary: return GameData.player_data_library.get(id, {})`。这是纯查询，`get_player_data` 保持不变。→ 验证：编辑器能解析。
- [ ] **B19** 新建 `tests/player_query_purity_test`：先记录 `player_data_library.keys()`，再依次调用 `find_player_data(999)`、`MatchViewBuilder.new().build(999)`、`EffectManager.player_shown_name(999)`、`AreaActionRules.block_reason(999, 0)`，最后断言 keys 不变。→ 预期 `block_reason` 这一项当前为红，因为它内部调用了 `get_player_data`；记录下这个红项。
- [ ] **B20** 把 `AreaActionRules.block_reason` 里的 `GameDataManager.get_player_data` 改成 `find_player_data`；返回 `{}` 时给出原因「玩家不存在」。→ 验证：`t player_query_purity_test && t refactor_area_golden_test`。
- [ ] **B21** `battle_board_v2.gd:554` 目前手写了「先 has 再取」，改成 `find_player_data`。→ 验证：`t battle_board_v2_test`。
- [ ] **B22** `effect_manager.gd` 第 598、2612 行（已有 has 守卫）改成 `find_player_data`。→ 验证：`t player_name_test`。
- [ ] **B23** `match_authority.gd` 第 262、289、625、654、678 行改成 `find_player_data`，查不到时 `_reject("座位无玩家数据")` 或返回 `{}`。→ 验证：`t net_move_test && t net_cards_test && t net_authority_ui_preview_feedback_test`。
- [ ] **B24** 编写只读脚本 `tools/classify_player_data_calls.py`，把 195 处 `get_player_data(` 调用分为「只读」和「需创建」两类（判据：调用点的 id 是否来自初始化或召唤流程），输出到 `reports/refactoring/player-data-calls.json`。**本批不改 operations**，这份分类留给后续逐文件迁移。

**B-4 玩家显示名合并（D5=B）**

现有 6 份实现：`EffectManager.player_shown_name`（effect_manager:595）、`GameProgress._player_shown_name`（game_progress:220）、`ClimaxResolver._player_shown_name`（climax_resolver:63）、旧 UI `_player_shown_name_by_id`（tactical_board_ui:5260）、旧 UI `_player_shown_name`（tactical_board_ui:3722，回退文案是不带空格的「玩家%d」）、v2 `_player_name`（battle_board_v2:576）。差异有三点：①是否先检查 `has`（缺这一步的 climax 和旧 UI:3722 会隐式创建玩家）；②master 名称为空时是否回退到 `_name`（旧 UI:5260 和 v2 会回退，`EffectManager` 不会）；③回退文案是否带空格。

- [ ] **B25** 新建 `tests/player_shown_name_golden_test`：开局后对每个玩家 id 以及不存在的 id（999），记录上述 6 份实现的输出；另外构造 3 种情况：master 为 null、master 的 `_shown_name` 和 `_name` 都为空、`_shown_name` 为空但 `_name` 不为空。输出写入 `docs/refactoring-golden/player_names.json`，并在报告中列出 6 份实现之间的差异表。→ 完成判据：差异表落盘。由于 `BaseObject.get_shown_name()`（base_object:96）在 `_shown_name` 为空时已回退到 `_name`，预期差异②只在 master 不是 BaseObject 或两者都为空时出现，以实测为准。
- [ ] **B26** 用 B25 的差异表确定统一口径并写入本任务记录：先检查 has，不存在时返回「玩家 %d」（带空格）且不创建玩家；名称回退顺序为 `get_shown_name()` → `_name` → 「玩家 %d」。把 `EffectManager.player_shown_name` 改成这个口径（只是增加 `_name` 回退，并改用 B18 的 `find_player_data`），同时删除 B10 中 GameLogText 的私有副本 `_player_name`，改为调用 `EffectManager.player_shown_name`。→ 验证：`t player_shown_name_golden_test && t refactor_text_golden_test && t player_name_test`。若 text golden 有差异，必须逐条确认差异只来自 B25 差异表中列出的情况，再重新 capture。
- [ ] **B27** `game_progress.gd:220` 的函数体改为 `return EffectManager.player_shown_name(player_id)`。→ 验证：`t turn_order_test && t player_name_test`。
- [ ] **B28** `climax_resolver.gd:63` 的函数体同样改为转发（顺带修掉它隐式创建玩家的问题）。→ 验证：`t climax_elimination_test`。
- [ ] **B29** 旧 UI 的 `_player_shown_name_by_id`（5260）函数体改为转发。→ 验证：`t refactor_text_golden_test`。
- [ ] **B30** 旧 UI 的 `_player_shown_name`（3722）函数体改为转发。这会把回退文案「玩家%d」改成「玩家 %d」，属于可见的文案变化，报告中要列出。→ 验证：`t reported_ui_test`。
- [ ] **B31** v2 的 `_player_name`（576）函数体改为 `return EffectManager.player_shown_name(id)`。注意 D 批中联机路径会改成读 view，届时这里改读 `_source` 中的显示名字段，不再读规则全局。→ 验证：`t battle_board_v2_test`，并截图原生检查顶栏、横幅和战果榜中的名字。
- [ ] **B32** 用 grep 确认 `_player_shown_name` 的转发壳没有外部调用后，删除 game_progress 和 climax_resolver 中的私有壳函数，调用点改为直接调用 `EffectManager.player_shown_name`。→ 验证：同 B27、B28。

### 批次 C：展示契约与适配器骨架，先迁移样板模块

- [x] **C01** 主代理独占代理测试进程复测：28 组、2800 样本，p95 为 18.146–38.298 ms。采用每次 `refresh_all_ui` 显式失效后 build 一次，同次刷新内复用视图；不使用粗略状态键独立推断失效，不缓存 actions/pending 合法性。证据和范围见 `reports/refactoring/build-cost-exclusive-review.md`；C09 接线仍需验收。
- [ ] **C02** 编写 `tools/list_presenter_private_access.py`，输出 §2.4 中 75 个成员的四类分组，写入本文附录 A。
- [ ] **C03** 在 EffectManager 中新增两个公开包装方法 `is_card_selection_valid(...)` 和 `location_option_origin_allowed(...)`，内部转调对应私有方法；`match_authority.gd` 第 191、686 行改为调用公开版本。→ 验证：`t net_pending_test`；从 A05 白名单删除这 2 项后 `gate` 通过。
- [ ] **C04** 新建 `scripts/match/match_seat_query.gd`（`class_name MatchSeatQuery`，构造参数为 `builder`）。把 `match_authority.pending_for` 中座位解析之后的主体整段移入 `pending(seat)`，`_card_choice_secret`、`_card_choice_confirm_text`、`_location_candidates` 一并移入。权威端的 `pending_for` 只保留 `observer_for` 和 `started` 两项检查，然后转发。→ 验证：`t net_pending_test && t net_locations_test`。
- [ ] **C05** 同样把 `actions_for` 移为 `MatchSeatQuery.actions(seat)`，`_flip_modes` 一并移入。→ 验证：`t net_cards_test && t net_move_test`。
- [ ] **C06** 把 `preview_group` 中 seq/revision 检查之后的主体移为 `MatchSeatQuery.preview(seat, cards, flags)`；权威端保留 id 解析和 seq 检查。→ 验证：`t net_authority_ui_preview_feedback_test`。
- [ ] **C07** 新建 `scripts/game_scene/battle_io/local_battle_source.gd`，提供：`read_view()`，即 `builder.build(local_seat)`，按 C01 的策略缓存；`read_actions()`，即 `MatchSeatQuery.actions(local_seat)`；`read_pending()`，即 `MatchSeatQuery.pending(local_seat)`；以及由 `refresh_all_ui` 触发的 `signal changed`。座位由调用方显式传入：热座或调试视角传当前视角座位，观战传 -1（落实 v1 §3.1 第 4 条）。→ 验证：编辑器能解析。
- [ ] **C08** 新建 `network_battle_source.gd`：三个读取方法分别转发到 `session.read_match`、`read_actions`、`read_pending`，并转接 `session.changed` 信号。→ 验证：编辑器能解析。
- [ ] **C09** 在 `battle_board_v2._ready`（第 304 行附近）新增 `var _source`，按是否有 `network_session` **只选择一次**；本任务不让任何渲染代码读取它。→ 验证：`t battle_board_v2_test && tw net_v2_browsing_window_test`，结果与基线一致。
- [ ] **C10 样板：BUFF 行**，分 4 个子任务：
  - C10a：核对 `view.players[*].buffs` 的字段是否齐全。`ViewBuilder.buff_views(own=true)` 已包含 `description`（即 `token_desc`）、`image`、`zoom_kind`、`active`；如有缺失，在本任务中补齐，并补上隐私断言。
  - C10b：用 `grep -n '_fill_buff_rows' scripts/game_scene/battle_board_v2.gd` 找出本地传入 `BaseBuff` 数组的调用点，逐个改成传入 `_source.read_view()` 中对应玩家的 `buffs`。
  - C10c：删除 `_fill_buff_rows` 中的 `BaseBuff` 分支（第 2784–2797 行）。
  - C10d：验证。运行 `t battle_board_v2_test && t refactor_text_golden_test`；再用 `tw` 运行涉及 BUFF 的窗口测试，截图后原生查看本方和对手的 BUFF，悬浮说明必须与改动前逐字一致。
- [ ] **C11 牌堆**：本地 `_bind_situation_and_piles` 改为读取 `view.event_discard`、`situation_discard`、`deck_count` 和弃牌区；删除 `v2_view_presenter.gd` 第 413–414、450–452 行的重复绑定，改由共同函数完成。按 C10 的四步执行。
- [ ] **C12 法阵与资源**：`_bind_sigils` 只从 view 读取魔力、令咒、战果；删除 presenter 中对应的设置代码。
- [ ] **C13 顺位**：`_bind_rival_order` 只读取 `view.players` 的顺序和 `current_player`；删除 presenter 中的 `_bind_rivals` 和 `_bind_network_rival`。专项断言节点身份不重建、动画不重播：刷新前后节点的 `get_instance_id()` 相同。
- [ ] **C14 阶段条与残留**：`_bind_phase_timeline` 和 `_bind_residue_entries` 改为读取 `view.state`；删除 presenter 中 `_clear_phase_residue_visuals` 与之重复的部分。
- [ ] **C15 战区与席位**：`_bind_strips`、`_bind_seat_rows`、`_bind_groups` 改为读取 `view.areas`；删除 presenter 中的 `_bind_areas`、`_bind_area_seats`、`_bind_seat_avatar`、`_bind_area_groups`。专项：`tw net_v2_area_window_test`，并原生查看事件扇形展开和收拢的中间帧。

C11–C15 每完成一项，都运行 `gate`、`t battle_board_v2_test`、`tw net_v2_browsing_window_test`，并把 checks 数与 A03 基线对比。

### 批次 D：交互与命令统一

- [ ] **D01**（D4=A）新建 `scripts/match/match_command_dispatcher.gd`（`class_name MatchCommandDispatcher extends RefCounted`），接口 `dispatch(seat:int, kind:String, args:Dictionary, ids, run:Callable) -> Dictionary`，返回 `{ok, reason}`。本任务只迁移 `set_concealed` 的校验与执行（`match_authority.gd:240–249`）：原代码中的 `_reject(x)` 改为 `return {ok=false, reason=x}`，`_run_command(...)` 改为 `run.call(...)`。权威端改为 `var r = dispatcher.dispatch(seat, kind, args, builder.ids, _run_command)`，失败时 `_reject(r.reason)`；peer、seq、revision、审计、guard 暂停检查仍留在 `_submit` 前段，不搬进来。→ 验证：`t net_cards_test`。
- [ ] **D02–D12** 其余 kind 每种一个任务，依次为 `cancel_choice`、`location_choice`、`activate`、`player_choice`、`card_choice`、`option_choice`、`active_choice`、`move`、`play_group`、`end_action`、`deploy`。每项只迁移一种 kind，并运行对应的 net 专项（例如 move 运行 `net_move_test`，card_choice 运行 `net_pending_test`）。
- [ ] **D13** 新建 `local_battle_commands.gd`：`submit(kind, args)` 先把稳定 id 解析成对象，再调用 `dispatcher.dispatch(local_seat, …, run = MatchCommands.callv)`，然后同步发出 `result(request_id, ok, reason)`。
- [ ] **D14** 新建 `network_battle_commands.gd`：`submit` 调用 `session.request("match_command", …)`，并把 `request_rejected` 转接为 `result`。
- [ ] **D15** `battle_board_v2` 中共有 23 处 `_commands.*` 调用（`grep -n '_commands\.'`），逐个改为 `_battle_commands.submit(kind, params)`，**每处一个任务**。每处都要验证：请求被拒后 UI 恢复可点，连续点击不会重复扣费。验证方式是 `tw net_v2_ui_input_parity_window_test` 加上对应的单机窗口测试（落实 v1 §6「GUI 输入采样」）。
- [ ] **D16** `_held_card_playable`、`_held_playable_signature`、`_manual_effects_of` 改为只读 `_source.read_actions()`，删除这三处的网络分支和本地对 `RegularPlay` 的直接调用。
- [ ] **D17** `_bind_mana_cost_preview`：本地改用 `MatchSeatQuery.preview`，网络继续用 `group_preview`，两者合并成一个渲染函数；删除 presenter 第 466–475 行。
- [ ] **D18** 待答面板：`network_choice_panel` 只负责把 `read_pending` 转成 `native_choice_renderer` 的输入；本地的 `_show_effect_modal`、`_show_card_select_panel`、`_show_player_select_panel` 改为同样从 `read_pending` 读取。按 active、card、player、location 四类，每类一个子任务。
- [ ] **D19** 新建 `tests/natural_game_over_test`（单机部分）：实例化 `battle_board_v2.tscn`，用 MatchDriver 合法推进到 `GameProgress.is_game_over`，断言：战果榜 `Board` 可见且只打开一次；胜者提示 `_say` 只调用一次；`LogBrowser` 未显示；不自动切换场景（D2=A，界面保留）。
- [ ] **D19b** 同一测试的联机部分（net_server 夹具）：推进到 game_over 后断言客户端同样满足上述 4 条，并且**不弹日志窗**。改动前此项为红，用来锁定 D20 要删除的行为。
- [ ] **D20**（D2=A）删除 `v2_view_presenter.show_game_over` 中打开 `LogBrowser` 的 6 行（第 93–98 行：设置 entries、`show()`、`_raise_modal`），只保留打开战果榜。→ 验证：`t natural_game_over_test`，D19b 由红转绿。
- [ ] **D20b** 战果榜新增「返回房间大厅」和「返回主菜单」两个按钮，节点写在 `battle_board_v2.tscn` 的 `Board` 下，脚本只做接线。按钮的显示条件按能力声明：没有 `network_session` 时只显示「返回主菜单」，联机时两个都显示。分别连接现有的 `_return_to_network_lobby` 和 `_return_to_main_menu`，不新增清理逻辑。→ 验证：非 headless 截图原生检查结算界面；点击两个按钮后，分别断言 `network_session` 已移交（`_network_session_transferred == true`）或已 `close()`。
- [ ] **D20c** 合并单机的 `_check_game_over` 与 presenter 的 `show_game_over`：保留单机版本作为唯一入口，presenter 只负责从 view 读取 `game_over` 后调用它；`_score_sorted_ids` 和 `_player_name` 在联机时改读 `_source.read_view().players`。→ 验证：`t natural_game_over_test`（单机和联机两部分）。
- [ ] **D20d** 联机房主点击「返回房间大厅」时，由于 `room.phase` 仍为 playing，需要一个合法的回房入口。先 `grep -n 'return_to_lobby' scripts/net/session/room_state.gd` 核对 `room_state.return_to_lobby` 的授权条件：若已允许在 game_over 后调用，直接复用；若不允许，在 `lobby_session` 的命令表中新增 kind `match_finished_lobby`（只做一件事：权威端确认 `GameProgress.is_game_over` 为真后调用 `room.return_to_lobby`），非房主客户端只显示「等待房主返回大厅」。→ 验证：net_server 夹具推进到终局后，房主发出请求，断言所有客户端都收到 `match_reset`。
- [ ] **D21** 逐个删除 §2.3 清单中的网络分支，每个函数一个任务。每完成一项就在 §2.3 中划掉该函数，并运行 `tw net_v2_ui_input_parity_window_test`。
- [ ] **D22** 删除 `v2_view_presenter.gd` 中已无调用方的函数（每删一个之前先 `grep` 确认），最终只保留网络专属的外壳：连接等待、身份继承、guard 处置。

### 批次 E：消息生命周期、播报屏障、内容环境

**C10 消息**
- [ ] **E01** 在 `effect_manager.gd` 中新增 `var _message_serial:int = 0`。`push_message`（第 374 行）和 `push_effect_result`（第 408 行）在 append 时附带 `"serial": _message_serial` 并自增。`reset_runtime`（第 607 行）**不重置**这个计数，以保证单局内单调递增；跨局的区分由 E02 的 epoch 负责。→ 验证：`t match_view_test`。
- [ ] **E02** 把 `view_builder.notifications_for`（第 250 行）生成的 id 改为 `"%s:%d" % [epoch, serial]`，epoch 取自权威端的开局计数；同步修改 `view_mirror` 中的类型校验。→ 验证：`t match_view_privacy_test`。
- [ ] **E03** `network_choice_panel._seen_messages` 每次刷新时，删除当前 view 中已不存在的 id，使集合大小有界。→ 新增测试：同一文本推送两次，显示两次；同一快照重复送达，不重播；长局中集合大小不超过队列长度。
- [ ] **E04**（D3=A）只保证在线期间不重不漏：不做持久化和 ACK。在 `docs/refactoring-plan.md` §6 记录「断线期间的私有提示在重连后不补发」这一已知边界，并在 E03 的测试中加一条断言：重连后 `_seen_messages` 被清空，且只显示重连后新产生的提示，旧提示不重播。

**C05 播报屏障**
- [ ] **E05**（D1=A）在 `game_progress.gd` 新增 `var battle_broadcast_requires_confirm: bool = false`。由开局调用方显式设置：单机 v2 在 `_ready` 中设为 true，联机权威端在 `match_authority._start` 中设为 true，headless、AI 推演和 `rule_random_simulation` 保持 false。这一步只新增字段和赋值，不改判断逻辑。→ 验证：编辑器能解析，`t battle_broadcast_test` 结果与基线一致。
- [ ] **E05b** 把 `game_progress.gd:526` 推进判断中的 `has_battle_broadcast_consumer()`替换为 `battle_broadcast_requires_confirm`；`register/unregister_battle_broadcast_consumer` 保留，只供展示层使用。→ 验证：`t battle_broadcast_test && t full_game_test`（headless 下不阻塞）。
- [ ] **E06** `rule_state.gd` 第 53、58 行和 `effect_checkpoint.gd` 第 41、59、66–73 行不再捕获 Node 引用，改为捕获 E05 中声明的布尔值。→ 验证：`t battle_broadcast_test && t match_replay_test`。
- [ ] **E07**（D1=A）权威端在 view 中投影 `battle_broadcast: {pending, confirmers, confirmed}`（在 `view_builder.build` 中直接读取 GameProgress 的三个公开查询），并同步修改 `view_mirror` 的类型校验。→ 验证：`t match_view_test && t match_view_privacy_test`。
- [ ] **E07b** 按 D01 的方式在 dispatcher 中新增 kind `confirm_broadcast`：校验 seat 在 confirmers 中且尚未确认，执行 `MatchCommands.confirm_battle_broadcast(seat)`。→ 验证：新增 net 测试，两名真人各自确认后播报解除。
- [ ] **E07c** AI 座位的确认：权威端在 `match_authority._step` 中对 controller 为 0（AI）的座位逐个调用 confirm，节奏沿用单机的 `BROADCAST_AI_CONFIRM_STEP`；真人座位**不自动确认**。→ 验证：1 名真人加 6 名 AI 时，只有真人确认后播报才解除。
- [ ] **E07d** 掉线处理（D1=A：保持等待，由房主显式处置）：断线座位不自动确认；`_disconnected_players()` 非空时继续沿用现有的暂停推进机制（`lobby_session.gd:515`）。新增房主命令 kind `broadcast_confirm_absent`：只有房主能发出，只为当前断线且未确认的座位代为确认，并写入审计事实 `{actor: 房主, seats: [...]}`。→ 验证：一名真人断线时播报不解除；房主发出该命令后解除；非房主发出被拒绝。
- [ ] **E07e** v2 的 `_update_battle_broadcast` 和 `_refresh_broadcast_continue` 改为读取 `_source.read_view().battle_broadcast`，「继续」按钮改为 `_battle_commands.submit("confirm_broadcast", {})`；联机房主额外显示「代断线玩家确认」按钮（节点写在 tscn 中，仅在有断线座位时显示）。本地 AI 逐个确认的逻辑（`_tick_broadcast_ai_confirm`）迁到 LocalBattleCommands 一侧，保持单机现有节奏。→ 验证：非 headless 单机和联机各截图原生检查；`tw net_v2_ui_input_parity_window_test`。

**C07/C08 内容环境**
- [ ] **E08** 新建 `content_environment.gd`：`static func install(data_root, cache_path) -> Dictionary` 返回旧值作为 token，`static func restore(token)` 负责还原。它只切换 `LoadHelper.session_data_dir` 和 `LoadGame.stored_jsons_path` 这两个全局变量，不新增状态。
- [ ] **E09–E13** 把手工配对的切换逐处改为 install/restore，每处一个任务：`lobby_session.gd` 第 1389–1399 行、第 1424 行、第 1745/1839 行，`match_authority.gd` 第 516/535 行，`server_room_worker.gd` 第 201 行（进程级，只调用 install），`room_data_validation_worker.gd` 第 62 行。每处都运行对应的恢复或内容专项，并补一条「中途失败后全局值已恢复」的断言。
- [ ] **E14** 把 `load_game.gd` 第 19–27 行的进程角色路由移到 `server_bootstrap` 或主场景入口，`LoadGame._ready` 只负责加载。→ 验证：导出版的客户端和服务端各启动一次（使用 G 批的探针）。
- [ ] **E15** `room_data_preparation` 改为构造时显式注入 `humans: Callable`、`blobs`、`publish: Callable`、`download: Callable`，替换第 43、90、97、106、109、121、169、185 行对 session 内部的访问，每行一个子任务。

### 批次 F：会话拆分与内核状态边界（高风险，分子批执行）

- [ ] **F01** `effect_checkpoint.gd` 第 38–42、74–77 行：在 EffectManager 中新增 `capture_transaction_state() -> Dictionary` 和 `restore_transaction_state(d)`，checkpoint 改为调用这两个方法。→ 验证：`t match_replay_test` 加上 guard 相关回归；从 A05 白名单删除 8 项。
- [ ] **F02** `rule_state.gd` 第 41–42 行：新增 `EffectManager.paused_runs_snapshot()`。
- [ ] **F03** `match_replay.gd:37` 和 `match_authority.gd:25`：新增公开方法 `EffectManager.mark_guard_audit_failed(effect)`，替代对 `_guard_audit_failed` 的直接调用。
- [ ] **F04** `match_authority.gd` 第 310、312 行：新增公开方法 `EffectManager.effect_fact_actor_id` 和 `effect_source_name`。
- [ ] **F05** 在 DummyBot 中新增 `static func capture_attempts()`、`restore_attempts(d)`、`clear_attempts()`，替换 `effect_checkpoint.gd` 第 57、92 行、`rule_state.gd:48` 和 `match_replay.gd:157` 中的直接访问。→ 完成判据：A05 白名单清零后，删除该规则的白名单机制，之后任何新增访问都直接报错。
- [ ] **F06** `lobby_session._receive`（第 652–1057 行）的客户端分支：把 `group_preview`、`match_bind`、`match_reset`、`match_view`、`selection` 这 5 种 kind 移到 `scripts/net/session/client_match_inbox.gd`，session 只负责转发。新模块只拥有 `_mirror`、`_pending_view`、`_action_view`、`_match_bound` 这 4 个状态。→ 验证：`t net_server_one_round_test` 加上 net_v2 系列。
- [ ] **F07** 客户端的 `blob_error` 和 `blob_chunk` 移入 `blobs`。
- [ ] **F08** 客户端身份相关的 `lan_identity_*`、`server_identity_*`、`inheritance_*`、`identity` 移到 `scripts/net/identity/` 下的新协调器。全局顺序「认证 → 成员绑定 → 数据屏障 → 授权 → 执行 → 审计 → 发布」保持不变，并运行全部身份和恢复专项。
- [ ] **F09** 主机端的 22 种 kind 按房间管理、内容、对局、guard、身份分为 5 组，每组一个任务，做法同 F06–F08。
- [ ] **F10** server_room_manager（C09）：先写出生命周期状态表，列明 create、poll、discover、recover、stop 各自读写哪些字段，再确定拆分边界。本任务只产出文档。

**F10 后续政策实施：用户已确认，详见 `docs/refactoring-open-questions.md` Q01。**

- [ ] **F11 运行配额与恢复准入**：计运行资源而非休眠登记；恢复遵守当前配额、端口范围、部署模式与安全预算，UNKNOWN 不视为已释放。批准数据根由本机部署入口显式提供，移除失败创建隐式绑定。验证创建/休眠/恢复/未知状态与政策变更矩阵，旧档不合规时拒绝但保留。
- [ ] **F12 安全关闭与紧急停止分离**：正常关闭、全服与无人回收复用保存及绑定回执监督；超时/UNKNOWN 不升级强杀。紧急强停独立显式入口，记录风险与结果；析构清理不生成保存成功证据。逐个核对现有 stop 调用方，不将单一 operation 同时承担保存和强杀。
- [ ] **F13 启动与监督状态分离**：曾就绪实例遇能力丢失不回退为首次启动，不复用旧 deadline 强杀；恢复能力时复验当前 binding，新实例才新建启动期限。验证能力丢失/恢复/实例替换/关闭监督组合。
- [ ] **F14 心跳故障策略**：短暂失败重试、持续失败显式降级，不首次失败即强杀、不伪报保存。期限由部署配置传入，缺声明不能自行猜新规则数值。验证写失败、后续成功、持续失效与安全关闭未决状态。
- [ ] **F15 保守自动清理**：自动清理只针对有明确已消费/可回收证据的临时产物；正式存档和保存未知证据保留。使用显式清理配置与安全路径/实例复核，选择候选与删除执行分离，未配置不自动清理。验证未确认/当前实例/链接路径/缺配置均不删、成功清理可读回核验。
- [ ] **F16 生命周期边界整合**：前述策略组件保持单一职责、manager 登记单写者；部署入口负责显式注入，统一故障状态投影，安全保存与实际进程退出分开报告。完成专项后再运行真实 worker 创建/恢复/安全关停及发行回归，不以纯策略测试替代整合。

### 批次 G：可复现导出

- [ ] **G01** 导出后用 `--dump-pck` 或解包工具列出包内文件，确认 `_mcp_game_helper`（`project.godot:41`）是否被打进发行包，结果记入报告。
- [ ] **G02** 如果被打进包：在两个 preset 的 exclude_filter 中加入 `addons/godot_ai/*`，并由导出脚本临时移除该 autoload；不修改开发用的 project.godot。
- [ ] **G03** `tools/copy_data_after_export.py` 改为必须显式传入 preset 名或输出目录，缺少参数时报错，不再默认取第一个 preset。
- [ ] **G04** 把 agent-work 下的打包脚本迁入 `tools/release/`，所有路径改为参数；在一个全新的 E 盘目录从零构建，确认不依赖 agent-work。
- [ ] **G05** 用实际 EXE 验收：两个客户端开局，游戏服务端保存后关停，信令端独立 READY。每一步都检查退出码和日志。

## 5. 各批停止条件

| 批次 | 门槛 |
|---|---|
| A | 基线报告齐全；闸门和两个 golden 测试可运行，并验证过「撕掉修复就变红」 |
| B | `gate` 白名单只剩 load_game 和 server_bootstrap；golden 全绿；purity 全绿；B07 新用例由红转绿；玩家显示名只剩 `EffectManager.player_shown_name` 一份实现 |
| C | `_fill_buff_rows` 只剩一个分支；C11–C15 对应的 presenter 重复代码已删除；窗口测试的 checks 数不少于基线 |
| D | §2.3 只剩允许保留的 4 类分支；自然终局测试在单机和联机下都通过（含联机不弹日志窗、两种返回按钮）；23 处 `_commands.*` 全部改为 submit |
| E | 通知 id 不再依赖下标；`grep` 确认 `stored_jsons_path` 只在 ContentEnvironment 中赋值；播报决策已落地（真人确认、掉线等待、房主代确认留审计） |
| F | A05 白名单清零；`_receive` 各分组已迁出；身份与恢复全套专项通过 |
| G | 在新目录从零构建；实际 EXE 验收通过 |

通用约束（沿用 v1）：
- 每批完成后都保持可运行。
- 双轨只用于测试比对，生产代码中不对有副作用的动作双重执行。
- 存档或协议的变化单独版本化。
- 旧 `tactical_board_ui` 要等 21 个测试全部迁移、转发函数无人调用后再退役。
- 回退只撤销本任务涉及的文件，不撤用户未提交的修改。

## 6. 决策与数据（D1–D6 已于 2026-10-09 确认）

| 编号 | 问题 | 选项 | 结论 |
|---|---|---|---|
| D1 | 联机战斗播报是否要等全体真人确认？有人掉线怎么办？ | A 保持等待，由房主显式处置；B 不阻塞联机规则，只播放视觉效果 | **A**（E05–E07e）：真人逐个确认；掉线时保持等待，房主可以显式代确认并留审计，不自动托管 |
| D2 | 终局后回房间大厅还是主菜单？联机额外弹出的日志窗是否保留？ | A 保留结算界面，由玩家选择去向；B 自动返回 | **A**（D19–D20d）：保留结算界面，玩家自选回大厅或主菜单；联机不再额外弹日志窗 |
| D3 | 私有提示是否要跨崩溃、跨断线补发？ | A 只保证在线期间不重不漏；B 持久化并加 ACK | **A**（E01–E04）：在线期间不重复、不遗漏；断线期间的提示不补发（已知边界） |
| D4 | 本地命令是否也经过 `MatchCommandDispatcher` 的参数和座位校验？ | A 经过，单机多一层校验，与联机行为一致；B 本地仍直接调用 MatchCommands | **A**（D01–D15） |
| D5 | 玩家显示名的多份实现是否合并到 `EffectManager.player_shown_name`？各实现在回退规则、是否检查 has 上不一致 | A 不合并；B 由 golden 比对差异后再合并 | **B**（B25–B32）：先用 golden 测试锁定 6 份实现的差异，再统一到 `EffectManager.player_shown_name` |
| D6 | 移动费用估算放在哪里？ | A 放在 `AreaActionRules`，复用 `MoveLocation.step_cost_discount`，不改 operation；B 给 MoveLocation 加纯静态估算函数，exec 也复用它 | **A**（B01）：不改 operation；两份循环由 A07 golden 锁定一致 |
| 数据 | A08 主代理独占代理测试进程复测的 `build()` p50/p95 | — | 28 组、2800 样本；p50 16.385–33.156 ms，p95 18.146–38.298 ms；首次阶段稳定快照，不代表长局与渲染成本。采用显式失效及同刷新复用 |

## 7. 最新进度与停止交接（2026-10-12 11:38，UTC+08:00）

### 7.1 本轮停止决定与验收边界

- 用户最后确认：**不启动测试，把阻断和当前进度写入方案后停止**。本轮没有启动 Godot，不存在本轮 Godot PASS、冷导入通过、全量通过或人测包。
- 最新实测仍有用户编辑器 PID 6420、服务器 PID 28100；原两个引擎名额已占满。未关闭、输入或借用这些现场，也未临时提高引擎并发。
- 已请求停止两名仍在工作的子代理：Draw 调度修复 `sa-0-56419755`、F 结构准备接线 `sa-0-f5da2d70`。它们在停止边界前可能已有部分文件，**一律按中断候选、未完整收件、未运行验收**保留；不能把之前的开工说明当成最终交付。
- 本轮新增运行修复仍在 `E:/scratch/continuous-next-wave/` 隔离候选，未覆盖主项目生产代码、正式 DLL 或旧验收证据；本次主仓库仅补本文进度。没有提交、推送、出包或删除现场。
- 下面的 A1/A4/A9、RA 编号属于后续风险整改/原子执行方案，**不是**上文原始任务 A01–A08 的别名。原任务复选框不因“隔离候选有代码”自动勾选。

### 7.2 已有成果：实现、验证、发布分别记账

| 工作项 | 当前实证 | 尚未完成的部分 |
|---|---|---|
| 执行记录预算与费用 | 已落主代码；已有专项证据 | 不代表整套原子提交完成 |
| 会话代际、原来源、可信创建/克隆 | 基础原语与多批专项已有成果 | 统一最终冻结与业务接线复验 |
| 检查点半恢复 | 隔离候选 38 专项、2245 CHECK；来源专项 60/0 | 主源集成及最终同版本回归 |
| 效果登记、弃牌父流程、轮尾 | 登记恢复 1163/0、弃牌父 19/0、轮尾恢复 24/0 等历史专项 | 不能覆盖全部移牌、翻面与原子域 |
| 普通令咒移动 | 隔离候选原 91/7→91/0；正式命令 510/0；43 专项共3131 CHECK | 主源未接，最终冻结未验 |
| 权威移动预检 | 漏传原 context 的候选修复：33/9→33/0；实际费用、位置、重发保护已有证据 | 完整隔离路径与最终整合 |
| 事件亮出回执及调用方 | 隔离组合 117/0 | 撤门敏感性和修补后相关控制仍欠；S1 原81/4继承红未消除 |
| 环境校验与结果解析执行器 | 同一四文件候选已组成；主代理独立复跑73项保护测试、34项跨流测试，均exit0；子方原24例、64矩阵通过；两单门撤回真FAIL/exit1，恢复字节后通过 | 仅Python UNIT；七案实际Godot业务、原生加载、路径及退出链未验，主源未发布 |
| E14/LAN测试输出迁移 | 布尔oracle保真、标准CHECK/RESULT、静态负控与语法检查已有证据 | Godot实际编译/断言均未运行；静态14/22不能当实际CHECK数 |
| 编辑器move_target | 两候选、完整531文件/275类冻结已核；控件应用、保存读回探针已补 | target/codec、敏感性、实际保存读回未运行；旧回收站调用范围仍阻断 |
| 两Draw搬后通知续行 | 四候选、917文件冻结已有；28 AFTER场景及17控制已编排 | 尚无Godot恢复正例；见下表两个确证源码缺陷及中断修复 |
| F raw结构准备 | C/G/F三候选、1504文件冻结已核；独立owner结构资格、同M反向描述已实现 | 仅静态27/0；PREPARED最终描述与SEAL消费接线尚未完整收件、未动态验证 |
| 自有Fate原生库 | 真实编译8个翻译单元并链接新DLL；编译/链接exit0，主代理核产物SHA及AMD64/PE32+，命令与原始日志摘要一致 | 380条warning保留；旧SDK静态库构建来源仍未知；新DLL未加载，正式库未替换，运行安全未签 |

新原生构建产物：
`E:/scratch/continuous-next-wave/regression-fate-native-repro-build/artifacts/libfate_server_signals.windows.template_release.x86_64.dll`

SHA256：`0ee9ecc032638c3b26f9c64b5d084f56a77b010a37cc83238542d9f0658e8b36`。这是**新构建**，不补足旧生产库 `92a42b…` 的历史构建证明。

### 7.3 已定位但未验完的阻断

1. **Draw子监听丢队**：纯被动监听先从决策队列弹出，再做子审计；审计失败后既不在队列也不在结算池，较晚的重试入口接不到它。修复方向是精确Draw通知的准入延后到原结算池头，保原优先级、同child审计及已完成前缀；只在隔离EM修复，停止前部分实现不得记通过。
2. **Draw拒绝仍永久PENDING**：同token成员/容器失效或明确unsupported，只返回resume=false而未把同一原root置为REJECTED；paused包装还可能遮住拒绝。需要公开run终态和原GP等待能有限结束的补充断言，保已写partial，不重播动作、不撤销整局来掩盖。
3. **F准备与发布窗口时序**：原Core已有PREPARED关联复验，**无需新Core hook或移动窗口**。下一候选须OPEN保存原L/受管版本、PREPARED捕final-D浅槽证据与冻结描述、SEAL窗口内末次复验后消费并交原Domain安装；仅改阶段名单不够。该五文件接线已请求停止，未完整收件。
4. **完整原子链与效果换主**：有限结构/来源正例不授规则EXECUTE。效果换主、主体准备、统一提交、完整writer过程屏障尚未贯通；strict原128/13等继承红不因局部实现而清账。
5. **七案原生初始化/退出**：原32站有限源码投影26项限定模式不达、6项UNKNOWN；四旧DLL仅身份SHA相符，精确构建绑定均未取得。新Fate构建不自动解决旧SDK/Git/WebRTC来源、原生副作用及退出链。
6. **暂停续行覆盖**：Draw BEFORE、Discard父→Draw/Conceal、翻面恢复、部分通知完成尾暂停等尚未全部实现/认证；剪枝/反制的通知完成证书覆盖也有待补。
7. **全量未运行完**：历史757场景基线只启动308，449 safety_blocked；253有RESULT、55无RESULT、59含SCRIPT ERROR、94场景RESULT含失败。它们属于历史基线，不能当当前最终候选的统计；最终同版本全量回归尚未开展。
8. **最后画面与发行**：顶栏“我方”等最后画面复看未完成，完整非headless验收与最终出包均未执行。

纠正一项已排除的误报：七份旧 `request_sha256` 是规范化请求摘要，不是pretty JSON文件字节摘要；主代理按原生成算法重算七份全部匹配。**不再把它列为证据失配阻断**，但其它UNKNOWN仍使七案enabled=0/BLOCKED。

### 7.4 剩余编号（不能当成全部未开工）

| 方案编号 | 停止时的状态与剩余工作 |
|---|---|
| A1 | 基础已实现；A1-04/05/15/23/24/28/33相关恢复/续行/权威入口需随新合同联合签收；**A1-34最终统一冻结验收未执行** |
| A4 / RA-10 | 原子拒绝/统一提交整链未闭合；P0已有协调原语；**P1-C/E/F/L/G为部分完成**；P2整域合验、P3落位/移动/部署、P4及P4-C/U/A/D各入口接入、P5最终原子性/敏感性验收仍欠 |
| A9 / D4：已有组件但整项未签收 | **RA-00、RA-01、RA-02、RA-03、RA-04、RA-06、RA-09** |
| A9 / D4：仍欠完整链路或最终验收 | **RA-05、RA-07、RA-08、RA-10、RA-11、RA-12、RA-13、RA-14、RA-15、RA-16、RA-17、RA-18、RA-19、RA-20、RA-21、RA-22** |
| S1 | 原外层事件尾/nextarea四条继承失败未闭合，不改旧oracle凑绿 |
| Draw/Conceal追加项 | 搬后已写候选但未验、两个源码缺陷修复中断；搬前、弃牌父嵌套、翻面继续开放 |
| 31项风险整改 | 未完成最终逐项注销；本轮无新的“31项全部闭合”声明 |
| 最终收尾 | 生产写者结束→唯一候选整合/冻结→全量回归→修复复验→窗口验收→出人测包；**本轮在此前停止，不自动续跑** |

A9/D4共23个RA编号，7项有组件成果、16项欠完整链路或验收；二者都不等于最终签收。阶段声明/结构资格不等于动作完成，只有原Core保存的COMMITTED回执才可宣称原子动作成功。

### 7.5 接手位置与证据

- 总缺口台账：`E:/scratch/continuous-next-wave/INTEGRATION-GAPS.md`。
- 已联合验证的保护工具：`regression-guard-entry-unified/report.md`及同名`-receipt-decision.md`；候选gate `ebabcc…`、runner `418803…`、entry `a564be…`、可信JSON `072820…`。
- Draw语义审查：`draw-after-candidate-review/report.md`及同名`-receipt-decision.md`；中断写者目录 `draw-after-admission-terminal-fix/`，恢复前先读实际文件/停止回执，不能以原917冻结的结果认证新增文件。
- F阶段方案：`fg-core-structure-phase-boundary/report.md`及同名`-receipt-decision.md`；中断写者目录 `fg-prepared-structure-seal/`，Core/Domain/Source不应被它改动。
- 原生库：`regression-native-artifact-binding/report.md`、`regression-fate-native-repro-build/report.md`及构建manifest/commands/raw日志；新DLL只编译未加载。
- 编辑器冻结：`editor-move-target-complete-freeze/report.md`；E14/LAN输出：`regression-two-result-producers/report.md`。
- 以上相对报告目录均在 `E:/scratch/continuous-next-wave/`。保留全部候选、失败原件与停止现场，不清理、不发布、不继续调度。

### 7.6 用户要求继续后的接续（2026-10-14）

§7.1–7.5保留为上次停止快照；用户随后明确“继续”，现按Ponytail full复用半成品，不从零重建工具。

- **F结构五候选已静态收件**：修双参与者夹具、显式预算、精确映射复验与窗口外释放；主代理独立解析五文件语法exit0、核五文件补丁重放字节相同、原1504依赖SHA无漂移。Core/Domain/Source/Journal与旧控制不变。报告：`E:/scratch/continuous-next-wave/fg-prepared-structure-seal/report.md`。
- 最终生产候选SHA256：C `39b7cb28ad1a65092544729ba406e2a1410eb1bb2d731f2ebbf0ebd34b498469`；Graph `dec003de06075ed068ee424b95fc47a56c174ae79390e01643b2539ff221f01a`；F `3d78a86adbadde3ea56ba13655bcf3963bc0e5a0fe8b13ad4158b5758a84eebf`。这三份不是主源或动态已验版本。
- **F验收副本已静态装配**：`fg-prepared-validation/isolated-f544b9458fa5468f9ac67f8d7f7afed2/generated/project`。主代理独立核1504目标/原依赖/源映射与五候选SHA匹配；24条队列全NOTRUN。沿原runner、保原断言、明确审过四处pin适配。发现原1504含一枚未由唯一descriptor引用的旧DLL，现已仅从新运行树精确转存该枚并保原证据；后继运行清单1503项，SHA `c3f37c1d6cbe84c717315e36407e04d5d0ef3989e56cfd6783e8a28b2f571f12`。主代理独立核1503目标与转存SHA、实跑新清单静态检查exit0/旧清单拒绝exit1，并核9份进程回执及恢复负控。DLL装配范围阻断解除，但原生安全未签；原输入/正式库未动。真实路径探针、COMMITTED、PREDELETE、敏感性与独立预算触边仍未验；完整生产宿主与F执行能力未接，strict13不注销。
- **Draw接续已静态收件**：最终EM SHA256 `7b2b00f4656627175a5e9bbd2c3360a62caf742ce3b8a48a94d0176b927fc485`；原root拒绝清理、scope退役与精确监听池头审计已实现。主代理独立语法解析exit0、核917依赖无漂移、重放字节相同；CZ/两wrapper/原oracle/runner未变。报告在`draw-after-admission-terminal-fix/report.md`。后继`draw-after-validation/isolated-c7f6dc0b63f44c6ab394f861e4d54f2a/generated/project`已装配919文件；原1642输入沿旧resolver排731元数据，911正式输入加8探针/资源，不与旧917混称。主代理独立核全部919目标和原917源SHA、159条场景资源边、四候选未变，并真实复跑34项解析测试exit0；核两份静态负控exit1与8个动态CLI缺授权exit2。Job未创建，无Godot或真实RESULT。动态恢复、同token拒绝后原GP等待退出、完成尾故障及敏感性均未验；剪枝/反制和跨CP风险保留。
- 本轮实测原6420/28100不在当前名单；现有Godot主程序/console包装器属于`E:/scratch/replay-exp/proj`和`E:/scratch/perf-exp/proj`，均headless，未证明归属本任务。包装器不另算独立引擎；不终止它们，不启动新Godot。旧PID停止快照不得作当前状态。
- **SDK构建来源阻断继续处理**：首次`regression-sdk-source-build/`真实预检exit2，原SDK目录/ZIP已缺失，未生成或编译；旧7194输入当前5959匹配/1234缺失/1项上下文变化保留原记录。主代理独立核1240快照不变，并在`E:/scratch/repo-scratch-archive/scratch/native-process-ownership-v6`找到归档，1233项SDK输入与前批SHA全部匹配，ZIP也同字节。已明确授权后继`regression-sdk-source-build-archive/`仅用该只读来源离线生成/编译，不恢复主目录或改旧缺失证据。现已完成61个SDK源→新库→8插件源→新DLL，75条真实工具命令均自然exit0；主代理独立核命令/日志、8412输入、61个COFF成员→对象绑定、产物SHA与PE头。新SDK库SHA `03f801cd062c802a0091e0526e202c67d53e6f80d12f1731560da63b7c7f1384`，新DLL SHA `42203b2265e245f40556883082a2cc95212dde6945540f6d358c1b7897ebb378`，产物在`attempt-02/artifacts/`。首轮生成清单误纳.inc的自检失败与380警告保留，源码未改。仅新产物构建来源闭环，正式库及两份验收副本不替换，旧库历史来源不追认。
- **原生最小观察载体已收件，WAIT_ENGINE**：`native-source-bound-startup/`三个最小项目共13文件，正向只含新DLL/唯一descriptor，负向与路径探针不含扩展；复用原View/13方法合同，预期21检查。主代理独立核13文件、4来源pin、20源码审计引用SHA及同配置字节，实跑语法检查exit0。注册链有限源码投影不自动构造进程owner，但不签运行安全。主代理新观察为replay外部wrapper46860→main46992，仍占一槽；两阶段需要两个空槽，未启动任何Godot。不借用或关闭外部实例。复用已验证418803执行器的`continuation-commands.md`/`continuation-queue.json`已准备正向→无扩展负向→正向再存在三步，每步独立路径探针/冷导入/真实RESULT与Job证据；不另写执行器，不用旧3d05未执行引用。当前三步全NOTRUN，不实例化/调用native动作，不开启七案或449业务拦截。
- **未运行Godot、未合主源、未出包**。静态范围通过不等于真实提交/析构/恢复行为通过，所有历史动态结果继续绑定各自冻结。

## 附录 A：presenter 私有访问分组（由 C02 产出，待填）
