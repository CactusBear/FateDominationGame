# 游戏调试控制台设计

状态：已实现为按钮式控制台。实现位于 `assets/scripts/debug/` 与 `assets/scenes/debug/debug_console.tscn`，宿主接线位于 `tactical_board_ui.gd`。界面不提供命令行：操作页按分组列出按钮，选中后用下拉、多选、数值与开关控件填参数，提交时以结构化参数调用 registry；文中出现的命令名仅是 registry 的白名单键与审计用名，不是输入语法。

## 1. 依据、范围与阅读约定

依据已核对：项目根目录 `hermesWarning.txt`、`fate-domination-engine` 技能及其运行时数据模型与原语组合参考；《Fate/Domination 基础规则【墨水修订1版】》中的选择御主、召唤从者、四阶段、常规移动、常规出牌、真名、令咒及回合结束规则。规则文档与卡图路径只维护在技能的素材位置章节，代码与本方案都不复制绝对路径。

口径优先级：用户已确认的项目约定与卡面版本 → 卡牌显式例外 → 基础规则。技能里的历史描述若与当前源码冲突，以源码为准，并在本方案标注接缝。事件/局势对威力的影响在行动阶段计入合计威力，显示与战斗共用 `GetPlayerTotalPower`，不可改回延迟结算。

首版范围：只读检查、显式命令、规则动作、受控局面编辑、全体玩家的御主和从者更换、动作边界单步、独立调试审计。包括本地玩家和淘汰玩家，不增加或重新编号玩家。角色更换是调试造局，不声称基础规则允许局中随意换人。

非目标：任意 GDScript 执行、任意属性写入、网络远程控制、完整存档回档、逐条 operation 断点、强行取消不可取消效果、直接改回合号、自动复活、自动重放全局 `GAME_START`、升华技觉醒或规则补完。已有升华技只随御主对象保留既有加载与展示，不编辑其 JSON、克隆契约或觉醒状态。

原语边界：不新增 `DebugSetEverything` 一类多职责 operation，也不为换人、暂停、审计各写专用规则函数。控制台适配器只组合已有 operation 与现有管理器公开方法。`AllOperations.TABLE` 只提供名称与说明，不能代替命令 schema 与安全白名单。

## 2. 场景挂载与随时开关

控制台做成独立场景，由游戏 UI 实例化后挂为子节点，方便随时开启/禁用。

| 项 | 约定 |
|---|---|
| 场景 | `assets/scenes/debug/debug_console.tscn` |
| 脚本 | `assets/scripts/debug/debug_console_ui.gd` |
| 根节点 | `CanvasLayer`，`layer` 高于棋盘与常规弹窗、低于系统级遮罩即可；具体数值实施时按现有 `MODAL_Z_THRESHOLD` 对齐，不写死魔法数到别的文件 |
| 不注册 | 不进 `project.godot` autoload，不把面板骨架写进 `tactical_board_ui.tscn` |
| 宿主 | `tactical_board_ui.gd` 持有实例引用与启用开关 |
| 卸载 | `queue_free` 实例即可；禁用不是 `visible = false` |

宿主导出 `debug_console_enabled_on_start`，默认关闭；开发场景可在 Inspector 显式开启，也可由测试或调试入口调用 `set_debug_console_enabled(true)`。默认关闭时不加载控制台场景，不增加正式对局的常驻资源。

宿主公开两个方法，职责单一：

1. `set_debug_console_enabled(enabled: bool)`：未启用时不实例化。从关到开：以 `CACHE_MODE_IGNORE` 按需加载场景、`instantiate`、`add_child`，由独立 `CanvasLayer.layer` 管理层级，遮罩默认隐藏；不调用只接受宿主直属 `Control` 子节点的 `_reorder_child_by_z`。从开到关：先走安全关闭（收起面板、归还本控制台暂停令牌、清空命令焦点并断开 Session/Registry 引用环），再 `queue_free` 并置空引用。
2. `is_debug_console_enabled() -> bool`：只回答实例是否存在。

物理波浪号键对应 `KEY_QUOTELEFT`，是控制台的随时入口：实例不存在时首次按键按需启用并打开，实例存在时切换面板可见。输入框聚焦时仍由宿主优先处理该键，其余键盘输入不传给棋盘。忽略按键重复。面板打开期间全屏 `ColorRect` 遮罩 `MOUSE_FILTER_STOP`，位于棋盘之上、面板之下；关闭时同步隐藏遮罩。控制台在自己的 `CanvasLayer` 内处理拖动与输入层级；面板内按钮声明 `metadata/no_clickable_hint = true`，避免呼吸金框扫到调试按钮。

本地玩家身份仍只来自 `GameData.player_id`。换本地玩家的御主/从者不改这个 id，只改该 id 的 `player_data`。界面刷新走宿主已有 `refresh_all_ui()`。

## 3. 交互与页签

- 物理反引号切换面板；输入框聚焦时棋盘不收快捷键。
- 打开后面板暂停正常玩家提交、AI、自动阶段推进和等待自动答复，保留只读刷新。关闭面板只归还本控制台持有的暂停令牌，不解除其他暂停来源。
- 页签：全体玩家、牌区、地图、事件与局势、效果等待、日志、操作。操作页左侧是按类别分组的操作按钮，右侧是目标玩家选择与当前数据驱动的参数控件（下拉、多选、数值、开关）；底部只显示操作结果，没有指令输入框、历史上翻与 Tab 补全。
- 枚举全部 `GameData.player_data_library` 键，包括 `is_out == true`。同名牌用 `get_instance_id()` 定位。模板与实战对象必须区分，禁止编辑模板。
- 前六个页签是只读浏览器；所有写操作只从操作页按钮走 `DebugSession.execute_action(name, args)` 和 registry 白名单，不得直接改字段。命令文本仅用于内部兼容旧测试与日志，不作为交互入口。

页签数据来源（只读，不另写算法）：

| 页签 | 数据 |
|---|---|
| 全体玩家 | `GetAllPlayersId` + 各 `player_data`；魔力/战果/令咒读 `BaseNumber.number`；合计威力用 `GetPlayerTotalPower.breakdown`；真名用 `ReleaseTrueName.is_released`；本地玩家高亮 `id == GameData.player_id` |
| 牌区 | 选中玩家的 `deck` / `hand_cards` / `played_cards` / `discard` / `servant_skills` / `master_skills` / `side.*` / `out_of_game.*`；每张列出 `_name`、显示名、实例 ID、明暗、是否模板 |
| 地图 | `MapData.areas` 的席位 `_players` 与玩家 `location` 对照；地利读 `GetEffectiveLocationBenefit` |
| 事件与局势 | 各战区 `_events`、`MapData.active_situation`、两个弃牌区；模板池只展示不可点编辑 |
| 效果等待 | `EffectManager.is_waiting_for_choice()` 及 `waiting_effect` / `waiting_selection` / `waiting_location` / `waiting_players`、`decision_queue`、`is_running` |
| 日志 | `GameLog.query` 隔离副本；调试审计另列，不写入规则事实 |

## 4. 两种编辑语义

1. **规则动作**：正常部署、移动、整组出牌、真名解放/隐藏、淘汰。走现有规则入口，保留费用、时点与事实日志。失败时回读真实结果，不得把拒绝称为成功。
2. **局面编辑**：明确不等于一次规则动作。直接调整局面时维护牌区唯一归属、席位双向引用、效果登记与威力。每条命令 schema 显式声明 `emits_time_points`，不靠隐藏默认值。

未知字段默认只读，登记类型适配器后才开放编辑。规则数字、玩家数量、卡名、战区名不写死，从数据与查询读取。合计威力、牌数等派生值不增加假字段，只改构成来源，再按需 `SyncPower`。

`SetPlayerData` 可覆盖任意键，控制台不得把它暴露成通用 setter。只允许 schema 白名单里的键，且换御主/从者必须走第 8 节组合，不能单调一次 `set_player_data`。

## 5. 结构

```
assets/scenes/debug/debug_console.tscn
assets/scripts/debug/debug_console_ui.gd      # 面板、输入、展示；不改规则
assets/scripts/debug/debug_session.gd         # 暂停令牌、安全边界、事务、审计
assets/scripts/debug/debug_command_registry.gd
assets/scripts/debug/debug_validate.gd        # 提交后只报告，不静默修正
assets/scripts/debug/debug_adapters/
  debug_player_adapter.gd                     # 资源、淘汰恢复政策入口
  debug_card_adapter.gd                       # 搬运、克隆入区、明暗、关闭
  debug_map_adapter.gd                        # 部署/移动/瞬移/离板
  debug_board_adapter.gd                      # 事件/局势生命周期组合
  debug_identity_adapter.gd                   # 换御主、换从者
```

`DebugSession` 不是 autoload，由控制台 UI 持有。业务适配器组合已有 operations，不进 `operations/`，不登记 `AllOperations.TABLE`。

命令 schema 字段：

| 字段 | 含义 |
|---|---|
| `name` | 命令名，如 `identity.set_master` |
| `scope` | `inspect` / `rule_action` / `board_edit` |
| `params` | 参数类型、是否必填、取值来源（玩家 id、实例 id、模板名、区域键、bool） |
| `requires_idle` | 是否要求不在效果等待中 |
| `emits_time_points` | 是否允许走会派发时点的原语 |
| `undo_level` | `none` / `local` / `forbidden` |
| `steps` | 有序组合步骤，每步写调用的现有类与参数来源 |
| `validate` | 提交后要跑的检查项 |

解析命令时玩家 id 必须显式传入。适配器禁止把缺省 `-1` 交给 `EffectManager.resolve_player_id`，否则会落到 `GameData.player_id`。本地玩家写成 `player=local`，由 registry 翻译成 `GameData.player_id`。

## 6. 安全暂停与续行

`EffectManager.is_running == false` 仍可能 `is_waiting_for_choice()`，不代表能安全裸改。

暂停不用 `SceneTree.paused`，也不用 `reset_runtime()` 清空队列。增加由 `DebugSession` 持有的令牌，宿主与 AI 在现有推进点查询：

- `tactical_board_ui._process`：令牌有效时跳过 `_check_and_step_ai`、跳过本地结束行动与自动提交等待；仍刷新只读 UI、威力浮层、消息展示。
- `_check_waiting_effects` 等：令牌有效时不自动 `submit_active_choice`。
- `GameProgress.end_current_player_action`：不在进程层写死调试名；由 UI/AI 调用方在令牌有效时不要调用。控制台自己的规则动作命令在安全边界内可调用。

写事务只在顶层调用返回后、且 `is_running == false` 时执行。`requires_idle == true` 的命令在等待效果、选牌、选人、选位置时拒绝。需要先结束等待时，用现有 `submit_active_choice` / `submit_option_choice` / `submit_card_selection` / `submit_location_selection` / `submit_player_selection` 显式答复或取消，再编辑。

单步首版做到动作边界：当前行动者 `end_current_player_action` 一次，或 AI `DummyBot.step` 一次。时点/单效果级单步依赖可恢复调度，首版不做，不在同步函数中途 `return`。

关闭面板后：丢弃待确认出牌预览、重新校验选择器里的对象是否仍在树上，避免提交过期引用。

## 7. 对象身份、模板与区域

模板：`GameData.loaded_masters`、`GameData.loaded_servants`、`LoadAttack._attack_datas`、`LoadEvent.events`、`LoadSituation.situations` / `climax_situations`、`LoadCommandSpell.command_spells`。只读。增牌必须 `CloneObject.exec(template)` 后再入区。

`GameData.ingame_masters` / `ingame_servants` 当前仅声明与退出时清空，开局未写入。控制台不依赖这两数组判断占用；占用以各玩家 `player_data.master` / `servant` 引用为准。

实战对象：玩家区域里的克隆卡、场上事件/局势克隆体、令咒克隆卡（`out_of_game.command_spell`）。可编辑。

牌区唯一归属：一张实战卡不得同时出现在两个玩家数组里。搬运适配器枚举全体玩家的白名单牌区定位所有者，再用 `DrawCardByCard` 搬运（先校验下标再摘出再放入）；`FindPlayerArrayContaining` 仅作既有规则查询，不能单独证明全局唯一。减牌必须指定去处，禁止只 `erase`。`AddSkillToSkillZone` 只追加并登记，不从来源摘除；从其他区进技能区时必须再组合一次摘除。

席位双向引用：改位置后 `player_data.location` 与 `location._players` 必须互指。常规部署走 `DeployRules.deploy_to_area`（含收益）。瞬移走 `SetLocation(..., is_move=false)`，不记 `deploy`、不调用 `DeployRules.apply_benefit`。离板走 `RemoveFromBoard`。

效果登记：对象进出会影响时点的，成对调用 `UnregisterObjectEffects` / `RegisterObjectEffects`。令咒克隆不得登记模板本身。

## 8. 更换御主与从者

可作用于任意 `player_data_library` 键，包括本地玩家与淘汰玩家。不改玩家 id，不改 `GameData.player_id`。不重放全员 `GAME_START`。不把 `deal_player_cards(-1)` 误用于单人更换。

占用政策由命令参数声明，不写死「七人七从者」：

| `occupancy` | 行为 |
|---|---|
| `exclusive` | 默认。若其他玩家已持有同一模板引用则拒绝 |
| `steal` | 先对原持有者执行卸下（见下）再装到目标；原持有者 `master`/`servant` 置空并卸效果，不自动补另一个角色 |
| `allow_duplicate` | 首版拒绝。当前效果实例只允许一个 `_trigger_player_id`，共享模板会改写效果归属并污染原持有者 |

目标从 `GameData.loaded_masters` / `loaded_servants` 按 `_name` 查找，找不到拒绝。不得 `CloneObject` 整份御主/从者来「每人一份完整模板」——现有开局就是多人各持模板引用，牌库克隆才是每人一份。换人后新牌库仍由 `deal_player_cards` 从新从者 `_specials` 克隆。

### 8.1 卸下当前御主（可单独调用）

命令：`identity.unequip_master`

1. 读旧御主引用，空则返回未变更。
2. `UnregisterObjectEffects.exec(old_master)`。
3. 遍历该玩家 `buffs`：若 `buff.from` 解引用后是旧御主，或 buff 属于旧御主 `_specials.BUFFS`，则 `ManageBuff.exec(buff, player_id, false)`。不要按中文名猜。
4. 卸令咒克隆：对 `out_of_game.command_spell` 里每张卡 `UnregisterObjectEffects`，再把卡移到调试回收数组或留在该数组但已无效果；随后数组清空。`bind_command_spell_effects` 是 append，不先清空会叠两份令咒效果。
5. 御主技能区政策 `master_zone`：`keep` 保留现有 `master_skills`（仍要确认效果归属；来自旧御主的牌应注销并移出）；`clear` 把 `master_skills` 中对象注销后搬到 `out_of_game.skills`。
6. `SetPlayerData.exec("master", null, player_id)`。此时不要依赖它记 `master_assigned` 的新御主对象；卸下不是一次规则分配。
7. 不碰从者、不发牌、不改魔力/令咒数量，除非调用方另发资源命令。

### 8.2 装备御主（可单独调用）

命令：`identity.equip_master`

参数：`player`、`master_name`、`occupancy`、`rebind_command_spell`（默认 true）、`master_zone`（`keep` / `clear`）、`replay_game_start`（默认 false，首版只允许 false）。

1. 按占用政策处理冲突。
2. 若已有御主，先走 8.1。
3. `SetPlayerData.exec("master", new_master, player_id)`。现有实现会记 `master_assigned` 事实；调试审计另记一条，规则日志保留。
4. `RegisterObjectEffects.exec(new_master, player_id)`。也可用 `MasterManager.bind_master_effects(player_id)`，二者等价于登记 `_effects`；选一个，不要登记两次。
5. 若 `rebind_command_spell`：确保令咒数组已空，再 `MasterManager.bind_command_spell_effects(player_id)`。解析口径必须是 `LoadCommandSpell.resolve_player_command_spell(master, servant)`，与 UI 共用。
6. `replay_game_start == false`：不派 `GAME_START`，不给远坂凛自动叠宝石、不给卫宫士郎改初始魔力。需要那些状态时用资源/buff 命令另造。若未来开放重放，也只对目标玩家定向派发，且须另写规格。
7. 升华技数组只随御主对象展示，不改 `_is_awakened`。

### 8.3 卸下当前从者（可单独调用）

命令：`identity.unequip_servant`

参数：`dealt_zones` = `replace` / `keep`。

`replace`（默认，换从者语义）：

1. `UnregisterObjectEffects.exec(old_servant)`。
2. 对 `deck`、`hand_cards`、`played_cards`、`discard`、`servant_skills`、`side.skills` 中每张卡：注销效果；攻击搬到 `out_of_game.attacks`，技能搬到 `out_of_game.skills`。必须 `DrawCardByCard`，并先 `FindPlayerArrayContaining`。
3. 真名政策 `true_name`：`keep_log` 不删解放/隐藏事实；`hide_if_released` 若 `ReleaseTrueName.is_released` 则 `HideTrueName.exec(player_id)`。默认 `keep_log`。
4. `SetPlayerData.exec("servant", null, player_id)`。
5. 令咒若由从者声明专属，按 8.1 的令咒卸下处理，避免旧从者令咒残留。

`keep`：只卸从者对象效果并清空 `servant` 引用，牌区不动。审计必须标明牌仍属于旧从者克隆。

### 8.4 装备从者（可单独调用）

命令：`identity.equip_servant`

参数：`player`、`servant_name`、`occupancy`、`dealt_zones`、`true_name`、`rebind_command_spell`。

1. 占用政策。
2. 若已有从者，先走 8.3。
3. `SetPlayerData.exec("servant", new_servant, player_id)`。
4. `RegisterObjectEffects.exec(new_servant, player_id)` 或 `ServantManager.bind_servant_effects`，只选一个。
5. 若 `dealt_zones == replace`：`DealPlayerCards.exec(player_id)`。它会覆盖 `deck` 与 `servant_skills` 并给新克隆登记效果。覆盖前 8.3 必须已经把旧牌搬走，否则引用丢失且效果可能残留。
6. 若 `rebind_command_spell`：令咒解析依赖御主与从者，卸旧克隆后重新 `bind_command_spell_effects`。
7. 手牌不会自动补到上限。需要时另发 `zone.refill_hand`。

### 8.5 对用户的合成命令

`identity.set_master` = 卸下当前御主 + 装备新御主。  
`identity.set_servant` = 卸下当前从者 + 装备新从者。  
`identity.set_pair` = 按参数顺序换御主再换从者，或相反；每步失败则停止，已成功步骤保留并写入审计（不是事务回滚）。

本地玩家与 AI 玩家走同一适配器。换完后宿主 `refresh_all_ui()`。底栏御主名、从者概览、令咒图、技能行都必须来自新引用；若本地信息栏仍显示旧名，视为未完成。

淘汰玩家可以换角色：只改归属与牌，不自动 `is_out = false`，不自动上板。

## 9. 命令一览与现有入口

下表是 registry 的命令键与参数来源；界面不解析任何文本，按钮按这张表生成控件并提交同名的结构化参数。布尔缺省见 schema。执行后回读真实结果并显示在操作结果区。

### 9.1 检查

| 命令 | 组合 | 注意 |
|---|---|---|
| `inspect.player player=` | 读 `player_data` + `GetPlayerTotalPower.breakdown` + `ReleaseTrueName.is_released` | 派生值只展示 |
| `inspect.card id=` | 按实例 ID 在 `GameData.objects` 与玩家区域查找 | 找不到拒绝 |
| `inspect.board` | 战区、局势、事件、弃牌 | 模板池只读 |
| `inspect.wait` | 等待队列与 `is_running` | |
| `inspect.log [filter]` | `GameLog.query` | 不公开抽到的具体牌名给玩家战报；调试页可以显示 object 类名与实例 ID |
| `inspect.identity player=` | 当前御主/从者 `_name`、显示名、占用者列表、令咒克隆数 | |

### 9.2 资源

| 命令 | 入口 | 注意 |
|---|---|---|
| `resource.magic player= set=\|vary=` | `EditMagic` | 保留 `BaseNumber` 引用；尊重 `is_magic_immune`；回读；会派魔力时点 |
| `resource.score player= set=\|vary=` | `EditScore` | 会派战果时点 |
| `resource.power player= set=\|vary=` | `EditPower` | 直接改 `power`；若目标是「与场上牌一致」应改用 `resource.sync_power` |
| `resource.sync_power player=` | `SyncPower` | 按计入威力的已出牌重建 |
| `resource.number player= key= set=\|vary= [min=] [max=]` | `EditDataNumber` | `key` 白名单：`command_spell_count`、`command_spell_limit`、`play_limit`、`regular_play_min`、`total_power_bonus`、`attack_cost_discount`、`move_cost_discount_from_workshop`、`order`。令咒扣减传 `min_value=0`；恢复先读当前上限再传 `max_value`。不开放 `lives` 作为界面资源，但 `edit_lives` 若调试需要可另条命令，界面仍不显示 HP |

局面编辑若声明 `emits_time_points=false` 且改魔力/战果：不得调用 `EditMagic`/`EditScore`；就地改同一 `BaseNumber`（`set_num`/`add`），并在审计写明未派时点。这不是回滚。

### 9.3 牌区

| 命令 | 入口 | 注意 |
|---|---|---|
| `zone.move card_id= to= [index=]` | `FindPlayerArrayContaining` + `DrawCardByCard` | `to` 为玩家区域键路径，如 `hand_cards`、`deck`、`discard`、`played_cards`、`servant_skills`、`side.skills`、`out_of_game.attacks` |
| `zone.add_clone player= source_name= to=` | 事件、局势、令咒与从者/御主 `_specials` 模板池中按内部名取模板 → `CloneObject` → 放入目标数组 → 若目标是会发动的区则 `RegisterObjectEffects` | 禁止把模板塞进玩家区 |
| `zone.draw player=` | `DrawCardFromPlDeckToHand` | 牌堆空时该原语内部应能触发洗牌；若当前实现只抽一张，空堆先 `ReshuffleDiscard` |
| `zone.refill_hand player=` | `RefillHand` | 补到 `GameData.hand_limit`，已满不抽 |
| `zone.shuffle player= zone=` | `ShuffleArray` | 只洗实战数组 |
| `card.cost card_id= set=\|vary=` | `EditCardCost` | 写修改历史 |
| `card.power card_id= set=\|vary=` | `EditCardPower` | 同步合计威力 |
| `card.attrs card_id= ...` | `EditCardAttributes` | |
| `card.conceal card_id= bool=` | `SetCardConcealed` | 非手牌只翻面 |
| `card.close card_id=` | `CloseCard` | 仅已打出牌 |

### 9.4 地图与行动

| 命令 | 入口 | 注意 |
|---|---|---|
| `map.deploy player= area=` | `DeployRules.deploy_to_area` | 规则部署，记 deploy，可能给工房魔力；满员失败 |
| `map.move player= steps=` | `Move` | 交战、费用、单向 |
| `map.teleport player= location_id=` | `SetLocation(..., is_move=false)` | 不冒充部署、不白拿地利 |
| `map.leave player=` | `RemoveFromBoard` | |
| `play.regular player= cards= hidden=` | `RegularPlay.can_submit_group/submit_group` | 两个数组等长；整组提交，不允许两次 `PlayAttack` 冒充 |
| `play.extra_attack` / `play.extra_skill` | `PlayAttack` / `PlaySkill` | 日志 `extra` 语义由原语决定 |
| `name.release player=` | `ReleaseTrueName` | 已解放则原语返回 false |
| `name.hide player=` | `HideTrueName` | |
| `out.eliminate player=` | `ClimaxResolver.eliminate_player` | 置 `is_out`、离板、记日志、派时点 |
| `out.restore player=` | 仅 `SetPlayerData("is_out", false)` | 不删除淘汰历史、不上板、不重排顺位；落位与效果另发命令。首版不自动恢复 |

### 9.5 Buff、事件、局势

| 命令 | 入口 | 注意 |
|---|---|---|
| `buff.add` / `buff.remove` | `ManageBuff` | 登记/注销随原语 |
| `buff.defeat` / `buff.undead` | `Defeat` / `RemoveDefeat` | |
| `event.place area= [concealed=]` | `AddEventFromDeck` | 克隆挂场；明置才 `register_entered`（派三种卡牌亮出时点） |
| `event.clear` | `EventResolver.clear_all` | 注销后入 `event_discard` |
| `event.reveal_planned` | `EventResolver.reveal_planned(GameProgress.event_placements)` | 不翻计划外暗置 |
| `situation.activate` | `SituationResolver.activate` | 会发印刷魔力并派三种 `CARD_REVEALED` 时点 |
| `situation.clear` | `SituationResolver.clear_all` | 还原移动与席位基线 |
| `situation.replace` | 先 `clear_all` 再按调用方选择模板 `CloneObject` 后写入 `active_situation` 并登记效果 | 是否发印刷魔力由参数 `grant_printed_magic` 显式决定，默认 false。不能把 `AddSituations` 当设置当前局势 |

### 9.6 身份

见第 8 节。`identity.set_master` / `identity.set_servant` / `identity.set_pair` / `unequip_*` / `equip_*`。

### 9.7 会话

| 命令 | 行为 |
|---|---|
| `session.pause` / `session.resume` | 令牌 |
| `session.undo` | 撤销最近一条仍满足后值快照的 `undo_level=local` 编辑；只在控制台暂停且效果管线空闲时执行 |
| `session.step_action` | 当前行动者 `end_current_player_action` 一次，仍受效果等待拦截 |
| `session.step_ai` | `DummyBot.step` 一次 |
| `wait.yes` / `wait.no` / `wait.option` / `wait.cards` / `wait.location` / `wait.players` | 现有 submit 接口 |

## 10. 日志、撤销、校验

规则事实仍走 `GameLog`。另记调试审计：命令 ID、玩家 id、对象实例 ID、参数、前后值、拒绝原因、校验结果。审计不进规则查询。

撤销仅对暂停期间、`emits_time_points=false`、无随机、无销毁、未换身份的局部编辑开放。撤销前验证当前值仍等于修改后快照。资源反向再调 `EditMagic` 不是回滚。出牌、真名、部署、一次性能力、淘汰、换人 `undo_level=forbidden`。

完整回档不做。`CloneObject` 会重置运行态，不可当存档。

`DebugValidate` 在每条写命令后检查并只报告：

- 每张实战卡只属于一个玩家数组
- `location` 与席位 `_players` 双向一致，淘汰者不应占席
- 玩家 `self_effects` 与对象 `_effects`、令咒克隆一致；旧御主/从者效果不在池里
- `loaded_*` 与牌堆模板未被改字段
- `GetPlayerTotalPower.breakdown` 四分量可加总
- 换人后 `deal_player_cards` 覆盖区不再持有旧从者克隆
- 令咒 `out_of_game.command_spell` 至多一份克隆，效果已登记且非模板

## 11. 实施顺序（得到指令后）

1. 空场景 + 宿主 `set_debug_console_enabled`，反引号与遮罩，不停游戏。
2. `DebugSession` 令牌，AI 与自动推进停住，只读刷新仍在。
3. 只读页签与 `inspect.*`。
4. 资源与牌区命令 + 校验。
5. 地图规则动作与瞬移。
6. 身份更换（先 AI 玩家，再本地玩家，再占用冲突与淘汰者）。
7. 事件/局势组合、等待答复命令、动作边界单步。
8. 审计与有限撤销。

每步都可单独验收；不把换人塞进资源命令。

## 12. 验收

命令级：参数与对象来源检查；提交后跑第 10 节校验；失败只报告。

交互级：真实键盘打开关闭；输入不穿透棋盘；启用/禁用反复多次无残留节点与残留暂停；AI 暂停与恢复后能继续完整对局。

换人级：

- 把某 AI 换成未被占用的从者：牌库与技能区变成新从者克隆，旧牌不在原区，旧效果不触发，新技能可被规则检查到。
- 把本地玩家御主换成另一御主：底栏名字、令咒图、御主技能展示更新；`GameData.player_id` 不变；不出现两份令咒效果。
- `occupancy=exclusive` 抢已占用从者应拒绝。
- 换从者不传全员 `deal_player_cards(-1)`：其他玩家牌堆张数与实例不变。
- 不重放 `GAME_START`：换到远坂凛不会凭空出现宝石层。

回归：现有 `tests/*_test.tscn` 不因未启用控制台而失败。控制台专项场景为 `tests/debug_console_test.tscn`，覆盖启停、暂停、检查、规则边界拒绝、局部撤销、牌区唯一归属、身份占用政策与安全卸载。最终验收仍包含非 headless 完整对局与控制台打开截图。

## 13. 不新增的 operation

下列需求都能组合，不要加文件：

- 换御主/从者：`UnregisterObjectEffects`、`ManageBuff`、`SetPlayerData`、`RegisterObjectEffects`、`DealPlayerCards`、`MasterManager.bind_command_spell_effects`、`DrawCardByCard`
- 暂停：会话令牌 + 现有 UI/AI 查询
- 瞬移：`SetLocation` `is_move=false`
- 校验：只读遍历现有容器

若实施中发现某一步必须改现有 operation 才能组合，停下来先改方案，不在控制台里复制一套规则。

## 14. 历史调查记录，不能作为当前实现结论

不据此扩大控制台范围。源码复核：`EffectManager.run_time_point()` 已有 `time_point_id += 1`，等待时已有 `_queued_time_point_batches`；对应旧判断过时，不得按旧文档再修。其余须先复现再立项：

- 延迟令咒奖励没有显式到期机制，未获胜时可能跨回合保留。
- 卡牌搬运的非法下标可能与追加哨兵 `-1` 混淆。
- 部分连续派发时点覆盖等待：战后路径已有排队，开局与阶段开始另测。
- 资源日志缺少统一来源信息。

令咒卡图「每赢一场」与项目既定「一次性奖励」口径差异，保留既定语义，另待确认。
