# Operation 注册目录绕过：直接实例化效果/规则类只读清单

- 仓库：`E:/Projects/Godot/FateDominationGame-master`。对象是当前工作树，不是提交版本；工作树原有大量修改，均未改动。
- 只写本报告；未启动 Godot，未向 PID 17120/28100 发任何操作；结论是源码/数据静态证据，不冒充运行验收。
- 扫描 GDScript 源文件 **1808** 个（包括被 ignore 的测试及历史副本），正式 `data/**/*.json` **71** 个，解析错误 **0**；`AllOperations.TABLE` **214** 项，func_name↔class 无重复。

## 1. 三档计数与口径

| 口径 | A 已注册仍有代码直连 | B 未注册的效果/规则承载类 | C 工具/查询类 | 合计 |
|---|---:|---:|---:|---:|
| 用户所给 `Xxx.new().exec/apply(...)` 字面生产调用 | 28 | 3 | 19 | 50 |
| 穷尽补充实例变量、其他公开入口、贡献求值器与构造型规则载荷后的总清单 | **28** | **9** | **37** | **74** |

补充口径明确列开，不把非字面命中冒充 grep 命中：
- B 增加 `EventResolver`、`SituationResolver`（new 后调用其他公开方法）、`BoardPowerQuery`（new→evaluate，承载 19 条贡献描述符）；另加入 `DefeatBuff`、`CannotPlayCardsEffect`、`ExcludedFromBattleWinEffect` 三个**构造型**系统规则载荷。后两个没有 exec/apply，只调用 `_init` 后由查询解释其规则。
- C 增加 `CardHasEffect`、`GetProperty`、`HasAttribute`（先 new 到实例变量再 exec），以及 `BoardPowerQuery.READERS` 代码白名单直接 new/callv 的 15 个新增查询/数学类。READERS 共 18 项，其中 3 个已由字面或实例变量命中，合并去重。
- C 优先于 A：纯查询/通用构造/洗牌工具即使已注册，也不冒充“效果执行类”。`ShuffleArray` 有就地数组副作用，仍是通用集合工具，**不声称它纯只读**。
- 时点判定与三档独立：🔴包括自发时点、直接控制时点派发、时点结算/边界副作用及效果池生命周期；纯查询仅因被上层效果调用不自动当成时点操作。对明确处于时点链且门控副作用的查询，说明“本类不发时点”。
- 这里的“绕过注册表”是**不经 TABLE 取类的代码直连**。TABLE 并不是普通效果唯一运行派发器：其注释说明分类仅供查阅；`LoadHelper.load_funcs` 本身按名字转换/路径 load/new/exec，不直接查 TABLE。
> `scripts/system/global/all_operations.gd:4` `#JSON里的func_name(下划线) -> 本表的键。加载时由LoadHelper.func_name_to_class_name转成类名。`
> `scripts/system/global/all_operations.gd:5` `#分类只用于查阅，不参与运行。效果结算仍按文件名动态load。`
> `scripts/system/global/load_helper.gd:242` `if _func.has("func_name"):`
> `scripts/system/global/load_helper.gd:243` `var key = _func["func_name"] as String`
> `scripts/system/global/load_helper.gd:244` `var _class_name = func_name_to_class_name(key)`
> `scripts/system/global/load_helper.gd:245` `var func_path = "res://scripts/system/operations/" + _class_name + ".gd"`
> `scripts/system/global/load_helper.gd:246` `if !ResourceLoader.exists(func_path):`
> `scripts/system/global/load_helper.gd:247` `print("没有操作:" + "'" + key + "'")`
> `scripts/system/global/load_helper.gd:248` `continue`
> `scripts/system/global/load_helper.gd:249` `var func_instance = load(func_path).new()`
> `scripts/system/global/load_helper.gd:250` `var main_callable = Callable(func_instance, "exec")`

### A 档类名
`AddEventFromDeck`, `AddMapAreaEvents`, `AddSkillToSkillZone`, `ApplyCardKeywords`, `AskPlayerOption`, `ChangePlOrder`, `Deploy`, `DiscardPlayedCards`, `DrawCardByCard`, `DrawCardFromPlDeckToHand`, `EditMagic`, `EditPower`, `EditScore`, `ManageBuff`, `Move`, `MoveLocation`, `RefillHand`, `RegisterObjectEffects`, `ReleaseTrueName`, `RemoveFromBoard`, `ReshuffleDiscard`, `RestoreLocationBenefits`, `RestoreLocationPlNumLimits`, `RestoreMapAreaMoveFlags`, `SetCardConcealed`, `SetLocation`, `SyncPower`, `UnregisterObjectEffects`

### B 档类名
`BattleResolver`, `BoardPowerQuery`, `CannotPlayCardsEffect`, `ClimaxResolver`, `DefeatBuff`, `EventResolver`, `ExcludedFromBattleWinEffect`, `SituationResolver`, `VictoryResolver`

## 2. 全仓检索与排除区

真实使用 `search_files` 全仓 grep 后，以 Python 对所有 `.gd` 做不受 ignore 影响的递归复核、去重、计数；复核模式（允许空白/跨行）：
```regex
\b([A-Za-z_]\w*)\s*\.\s*new\s*\([^)]*\)\s*\.\s*(exec|apply)\s*\(
```
`#` 独立注释行不计。正式主清单保留 `scripts/game_scene/tactical_board_ui.gd` 的旧 UI 代码（它仍是生产源码，不因入口旧而漏计）；`scripts/system/ai/temp` 不因 temp 字样当测试排除。

| 区域 | 字面匹配次数（同一行多次调用分别计） | 计入三档总数 |
|---|---:|---|
| 当前生产源码 | 143 | 是，去重为 50 类 |
| 测试/诊断：tests、test、newtests、window、scratch、tools/diagnostics、tools/tests | 719 | 否，附录逐项列出 |
| scripts/debug 及 debug_adapters | 78 | 否，附录逐项列出 |
| docs / reports 下历史快照、addons 更新备份 | 58 | 否，附录逐项列出 |
| .claude/worktrees 独立旧工作树 | 13 | 否，附录逐项列出 |
另发现 Python 内嵌 GDScript 调用 **4** 处，全是测试/工具探针字符串，不是另一个生产入口，单列在附录。

## 3. A 档：已注册但代码仍直接调用（双轨）（28 类）

### A — AddEventFromDeck
- **定义**：`scripts/system/operations/AddEventFromDeck.gd:1`。
- **公开入口**：`scripts/system/operations/AddEventFromDeck.gd:9` `func exec(map_area:BaseMapArea, add_count:int = 1, concealed:bool = false) -> int:`; `scripts/system/operations/AddEventFromDeck.gd:14` `func start(map_area:BaseMapArea, add_count:int = 1, concealed:bool = false) -> Dictionary:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:201`，`add_event_from_deck → AddEventFromDeck`，分类 `EDIT_MAP`。依据：`"add_event_from_deck" : { "category": EDIT_MAP, "class": "AddEventFromDeck", "summary": "从事件牌堆取克隆体挂到区域" },`。
- **正式数据 func_name 引用**：`add_event_from_deck` **8** 条（递归计出现次数，不按卡文件去重）。证据：`data/situations/origin/battle_of_shinto/battle_of_shinto.json:32`; `data/situations/origin/gate_of_hell/gate_of_hell.json:163`; `data/situations/origin/heavens_feel/heavens_feel.json:163`; `data/situations/origin/killer_in_miyama/killer_in_miyama.json:32`; `data/situations/origin/night_of_fate/night_of_fate.json:60,80`; `data/situations/origin/turnaround/turnaround.json:32,49`。
- **是否涉及时点**：<span style="color:#d00000">🔴 是：挂事件后登记效果并派发卡牌亮出时点；本次代码直连来自 EventResolver.place。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/event_resolver.gd:23` `var area = GetMapAreaByName.new().exec(p["area_name"])`
> `scripts/system/global/event_resolver.gd:24` `if area == null:`
> `scripts/system/global/event_resolver.gd:25` `continue`
> `scripts/system/global/event_resolver.gd:26` `#取牌堆头模板克隆挂载的完整链路在 AddEventFromDeck 里，这里只按计划传参`
> `scripts/system/global/event_resolver.gd:27` `var count:int = AddEventFromDeck.new().exec(area, 1, p.get("concealed", false))`
> `scripts/system/global/event_resolver.gd:28` `if count > 0:`
> `scripts/system/global/event_resolver.gd:29` `state.placed.append(true)`
> `scripts/system/global/event_resolver.gd:30` `if EffectManager.defer_until_runtime_guard_complete(Callable(EventResolver, "_resume_place").bind(state)):`
> `scripts/system/operations/AddEventFromDeck.gd:32` `var event = CloneObject.new().exec(template) as BaseEvent`
> `scripts/system/operations/AddEventFromDeck.gd:33` `AddMapAreaEvents.new().exec(state.area, event)`
> `scripts/system/operations/AddEventFromDeck.gd:34` `SetCardConcealed.new().exec(event, state.concealed)`
> `scripts/system/operations/AddEventFromDeck.gd:35` `#暗置牌放置时不派发"本牌亮出时"：牌没亮出，提前执行等于泄露暗置信息（ActionPhase 翻开时才派）`
> `scripts/system/operations/AddEventFromDeck.gd:36` `state.placed += 1`
> `scripts/system/operations/AddEventFromDeck.gd:37` `if not state.concealed: EventResolver.new().register_entered(event)`
> `scripts/system/operations/AddEventFromDeck.gd:38` `if EffectManager.defer_until_runtime_guard_complete(Callable(AddEventFromDeck, "_resume_add").bind(state)):`
> `scripts/system/global/event_resolver.gd:75` `func register_entered(event:BaseEvent):`
> `scripts/system/global/event_resolver.gd:76` `var ids:Array = GameDataManager.get_active_player_ids()`
> `scripts/system/global/event_resolver.gd:77` `if ids.is_empty(): return`
> `scripts/system/global/event_resolver.gd:78` `for effect in event._effects:`
> `scripts/system/global/event_resolver.gd:79` `if effect._trigger_player_id == -1: EffectManager.register_effect(effect, int(ids[0]))`
> `scripts/system/global/event_resolver.gd:80` `TimePointChecker.card_revealed(event)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/event_resolver.gd:27` | 直接实例调用 | `var count:int = AddEventFromDeck.new().exec(area, 1, p.get("concealed", false))` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/reported_board_power_test.gd:37,85`; `tests/rule_guard_event_add_test.gd:25`; `tests/rule_guard_native_event_test.gd:17`。
- **排除区（不计本类生产数）/debug**：`scripts/debug/debug_adapters/debug_board_adapter.gd:16`。

### A — AddMapAreaEvents
- **定义**：`scripts/system/operations/AddMapAreaEvents.gd:1`。
- **公开入口**：`scripts/system/operations/AddMapAreaEvents.gd:4` `func exec(map_area:BaseMapArea, add_event:BaseEvent):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:200`，`add_map_area_events → AddMapAreaEvents`，分类 `EDIT_MAP`。依据：`"add_map_area_events" : { "category": EDIT_MAP, "class": "AddMapAreaEvents", "summary": "给区域加事件" },`。
- **正式数据 func_name 引用**：`add_map_area_events` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：<span style="color:#d00000">🔴 是（时点前的场地副作用）：直连把事件挂入区域；同一调用链随后 register_entered / CARD_REVEALED。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/operations/AddEventFromDeck.gd:32` `var event = CloneObject.new().exec(template) as BaseEvent`
> `scripts/system/operations/AddEventFromDeck.gd:33` `AddMapAreaEvents.new().exec(state.area, event)`
> `scripts/system/operations/AddEventFromDeck.gd:34` `SetCardConcealed.new().exec(event, state.concealed)`
> `scripts/system/operations/AddEventFromDeck.gd:35` `#暗置牌放置时不派发"本牌亮出时"：牌没亮出，提前执行等于泄露暗置信息（ActionPhase 翻开时才派）`
> `scripts/system/operations/AddEventFromDeck.gd:36` `state.placed += 1`
> `scripts/system/operations/AddEventFromDeck.gd:37` `if not state.concealed: EventResolver.new().register_entered(event)`
> `scripts/system/operations/AddEventFromDeck.gd:38` `if EffectManager.defer_until_runtime_guard_complete(Callable(AddEventFromDeck, "_resume_add").bind(state)):`
> `scripts/system/global/event_resolver.gd:75` `func register_entered(event:BaseEvent):`
> `scripts/system/global/event_resolver.gd:76` `var ids:Array = GameDataManager.get_active_player_ids()`
> `scripts/system/global/event_resolver.gd:77` `if ids.is_empty(): return`
> `scripts/system/global/event_resolver.gd:78` `for effect in event._effects:`
> `scripts/system/global/event_resolver.gd:79` `if effect._trigger_player_id == -1: EffectManager.register_effect(effect, int(ids[0]))`
> `scripts/system/global/event_resolver.gd:80` `TimePointChecker.card_revealed(event)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/operations/AddEventFromDeck.gd:33` | 直接实例调用 | `AddMapAreaEvents.new().exec(state.area, event)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/battle_event_discard_test.gd:42`; `tests/battle_score_report_test.gd:62`; `tests/command_spell_test.gd:294`; `tests/post_battle_choice_test.gd:68`。
- **排除区（不计本类生产数）/debug**：无。

### A — AddSkillToSkillZone
- **定义**：`scripts/system/operations/AddSkillToSkillZone.gd:1`。
- **公开入口**：`scripts/system/operations/AddSkillToSkillZone.gd:5` `func exec(skill, player_id:int = -1):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:218`，`add_skill_to_skill_zone → AddSkillToSkillZone`，分类 `TRANSFER`。依据：`"add_skill_to_skill_zone" : { "category": TRANSFER, "class": "AddSkillToSkillZone", "summary": "技能进技能区并登记效果" },`。
- **正式数据 func_name 引用**：`add_skill_to_skill_zone` **4** 条（递归计出现次数，不按卡文件去重）。证据：`data/masters/00001_emiya_shirou/00001_emiya_shirou.json:48,242`; `data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json:1414`; `data/servants/00005_medea/00005_medea.json:457`。
- **是否涉及时点**：<span style="color:#d00000">🔴 是（时点效果生命周期）：关闭/回合清场时回收技能，并登记它的时点效果；不是自行发射一个时点。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/operations/CloseCard.gd:20` `#技能牌离场后不再计入合计威力，先按判定入口扣掉它此前贡献的威力再移出场`
> `scripts/system/operations/CloseCard.gd:21` `if CardCountsPower.new().exec(card, id):`
> `scripts/system/operations/CloseCard.gd:22` `EditPower.new().exec(null, BaseNumber.new(-card._power.number), id)`
> `scripts/system/operations/CloseCard.gd:23` `played_cards.erase(card)`
> `scripts/system/operations/CloseCard.gd:24` `#技能牌关闭后立刻明置返回技能区，复用AddSkillToSkillZone一并重新登记其效果`
> `scripts/system/operations/CloseCard.gd:25` `card.set_concealed(false)`
> `scripts/system/operations/CloseCard.gd:26` `AddSkillToSkillZone.new().exec(card, id)`
> `scripts/system/operations/CloseCard.gd:27` `elif card is BaseAttack:`
> `scripts/system/operations/CloseCard.gd:28` `#转暗置后不再计入合计威力，由SetCardConcealed同步扣减`
> `scripts/system/operations/CloseCard.gd:29` `SetCardConcealed.new().exec(card, true, id)`
> `scripts/system/operations/CloseCard.gd:30` ``
> `scripts/system/operations/DiscardPlayedCards.gd:19` `card._is_activating = false`
> `scripts/system/operations/DiscardPlayedCards.gd:20` `if card is BaseSkill:`
> `scripts/system/operations/DiscardPlayedCards.gd:21` `#技能牌回合结束保持明置并放回技能区，不进入弃牌堆`
> `scripts/system/operations/DiscardPlayedCards.gd:22` `SetCardConcealed.new().exec(card, false, id)`
> `scripts/system/operations/DiscardPlayedCards.gd:23` `cards_arr.erase(card)`
> `scripts/system/operations/DiscardPlayedCards.gd:24` `AddSkillToSkillZone.new().exec(card, id)`
> `scripts/system/operations/DiscardPlayedCards.gd:25` `continue`
> `scripts/system/operations/DiscardPlayedCards.gd:26` `#普通攻击牌弃置前暗置，再进入弃牌堆`
> `scripts/system/operations/DiscardPlayedCards.gd:27` `if card is BaseAttack:`
> `scripts/system/operations/DiscardPlayedCards.gd:28` `SetCardConcealed.new().exec(card, true, id)`
> `scripts/system/operations/DiscardPlayedCards.gd:29` `DrawCardByCard.new().exec(card, cards_arr, discard, BaseNumber.new(0))`
> `scripts/system/operations/AddSkillToSkillZone.gd:15` `zone.append(skill_obj)`
> `scripts/system/operations/AddSkillToSkillZone.gd:16` ``
> `scripts/system/operations/AddSkillToSkillZone.gd:17` `#技能进入技能区后，它自己的效果才开始参与时点检查`
> `scripts/system/operations/AddSkillToSkillZone.gd:18` `EffectManager.register_effects(skill_obj._effects, id)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/operations/CloseCard.gd:26` | 直接实例调用 | `AddSkillToSkillZone.new().exec(card, id)` |
| `scripts/system/operations/DiscardPlayedCards.gd:24` | 直接实例调用 | `AddSkillToSkillZone.new().exec(card, id)` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### A — ApplyCardKeywords
- **定义**：`scripts/system/operations/ApplyCardKeywords.gd:1`。
- **公开入口**：`scripts/system/operations/ApplyCardKeywords.gd:18` `func exec(card, player_id:int = -1) -> void:`; `scripts/system/operations/ApplyCardKeywords.gd:30` `func apply(keyword:String, player_id:int = -1) -> void:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:255`，`apply_card_keywords → ApplyCardKeywords`，分类 `ACTION`。依据：`"apply_card_keywords" : { "category": ACTION, "class": "ApplyCardKeywords", "summary": "结算一张牌的词条规则" },`。
- **正式数据 func_name 引用**：`apply_card_keywords` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：<span style="color:#d00000">🔴 是：打出链在 PLAYED_CARD 前执行词条，经 ReleaseTrueName 触发 TRUE_NAME_RELEASE；整组也提前调用 apply。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/regular_play.gd:310` `#整组常规出牌是同时打出：只要本批次有明置的【真名解放】牌，`
> `scripts/system/regular_play.gd:311` `#同批其他牌从费用计算开始就应读取到已解放状态，不受数组先后顺序影响。`
> `scripts/system/regular_play.gd:312` `#这里只提前结算会改变整组条件上下文的词条；其他词条仍在各自进场时结算。`
> `scripts/system/regular_play.gd:313` `var state:Dictionary = {"id": id, "cards": cards.duplicate(), "hidden": hidden_flags.duplicate(), "phase": "extras", "index": 0, "finish": Callable(RegularPlay, "_finish_group").bind(id)}`
> `scripts/system/regular_play.gd:314` `for i in range(cards.size()):`
> `scripts/system/regular_play.gd:315` `var batch_card = cards[i]`
> `scripts/system/regular_play.gd:316` `if not bool(hidden_flags[i]) and batch_card is BaseCard \`
> `scripts/system/regular_play.gd:317` `and batch_card.has_keyword(ApplyCardKeywords.TRUE_NAME_RELEASE):`
> `scripts/system/regular_play.gd:318` `ApplyCardKeywords.new().apply(ApplyCardKeywords.TRUE_NAME_RELEASE, id)`
> `scripts/system/regular_play.gd:319` `break`
> `scripts/system/operations/PlayAttack.gd:84` `GameLog.record("play", id, -1, "", attack, ["play"],`
> `scripts/system/operations/PlayAttack.gd:85` `{"card_name": attack._name, "card_type": "attack", "extra": true})`
> `scripts/system/operations/PlayAttack.gd:86` `#词条带来的规则行为（如【真名解放】）在打出时点之前结算：`
> `scripts/system/operations/PlayAttack.gd:87` `#规则是"使用带此词条的牌后立即解放"，而有些牌监听 self_true_name_release，`
> `scripts/system/operations/PlayAttack.gd:88` `#顺序反了它们就接不上这次解放`
> `scripts/system/operations/PlayAttack.gd:89` `ApplyCardKeywords.new().exec(attack, id)`
> `scripts/system/operations/PlayAttack.gd:90` `TimePointChecker.card_revealed(attack)`
> `scripts/system/operations/PlayAttack.gd:91` `TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], id, attack)`
> `scripts/system/operations/ApplyCardKeywords.gd:29` `#新增词条时在这里加一个分支，不改任何已有 operation`
> `scripts/system/operations/ApplyCardKeywords.gd:30` `func apply(keyword:String, player_id:int = -1) -> void:`
> `scripts/system/operations/ApplyCardKeywords.gd:31` `player_id = EffectManager.resolve_player_id(player_id)`
> `scripts/system/operations/ApplyCardKeywords.gd:32` `if player_id == -1:`
> `scripts/system/operations/ApplyCardKeywords.gd:33` `return`
> `scripts/system/operations/ApplyCardKeywords.gd:34` `match keyword:`
> `scripts/system/operations/ApplyCardKeywords.gd:35` `TRUE_NAME_RELEASE:`
> `scripts/system/operations/ApplyCardKeywords.gd:36` `#规则：使用带【真名解放】词条的牌后，立即展示从者概览卡与所有技能牌，`
> `scripts/system/operations/ApplyCardKeywords.gd:37` `#并处于【真名解放】状态。已解放时 ReleaseTrueName 自己会跳过，这里不重复判断`
> `scripts/system/operations/ApplyCardKeywords.gd:38` `ReleaseTrueName.new().exec(player_id)`
> `scripts/system/operations/ReleaseTrueName.gd:50` `#tags用客观时点名，与TimePointChecker记的时点日志口径一致`
> `scripts/system/operations/ReleaseTrueName.gd:51` `GameLog.record("true_name_release", id, -1, "", null, [TimePoints.TRUE_NAME_RELEASE],`
> `scripts/system/operations/ReleaseTrueName.gd:52` `{"shown_count": state.shown_count})`
> `scripts/system/operations/ReleaseTrueName.gd:53` `TimePointChecker.dynamic_time_point([TimePoints.TRUE_NAME_RELEASE], id)`
> `scripts/system/operations/ReleaseTrueName.gd:54` ``
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/operations/AddAttack.gd:27` | 直接实例调用 | `ApplyCardKeywords.new().exec(attack, id)` |
| `scripts/system/operations/AddSkill.gd:29` | 直接实例调用 | `ApplyCardKeywords.new().exec(skill, id)` |
| `scripts/system/operations/PlayAttack.gd:89` | 直接实例调用 | `ApplyCardKeywords.new().exec(attack, id)` |
| `scripts/system/operations/PlaySkill.gd:60` | 直接实例调用 | `ApplyCardKeywords.new().exec(skill, id)` |
| `scripts/system/regular_play.gd:318` | 直接实例调用 | `ApplyCardKeywords.new().apply(ApplyCardKeywords.TRUE_NAME_RELEASE, id)` |
| `scripts/system/regular_play.gd:363` | 直接实例调用 | `ApplyCardKeywords.new().exec(cards[state.index], id)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/card_keyword_test.gd:84,109,126,133`。
- **排除区（不计本类生产数）/debug**：无。

### A — AskPlayerOption
- **定义**：`scripts/system/operations/AskPlayerOption.gd:1`。
- **公开入口**：`scripts/system/operations/AskPlayerOption.gd:10` `func exec(options:Array, shown_name:String = "", player_id:int = -1, max_choices:int = 1) -> BaseEffect:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:251`，`ask_player_option → AskPlayerOption`，分类 `CONTROL`。依据：`"ask_player_option" : { "category": CONTROL, "class": "AskPlayerOption", "summary": "执行到这一步时让玩家选一项" },`。
- **正式数据 func_name 引用**：`ask_player_option` **2** 条（递归计出现次数，不按卡文件去重）。证据：`data/servants/00008_angra_mainyu/00008_angra_mainyu.json:673,982`。
- **是否涉及时点**：<span style="color:#d00000">🔴 是（结算期间等待与触发上下文副作用）：复制父效果 trigger_time_points，登记临时选择并暂停当前结算。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/operations/AskPlayerNumber.gd:15` `var result := BaseNumber.new(low)`
> `scripts/system/operations/AskPlayerNumber.gd:16` `#上下限相同就没有可选的，直接给出`
> `scripts/system/operations/AskPlayerNumber.gd:17` `if high == low:`
> `scripts/system/operations/AskPlayerNumber.gd:18` `return result`
> `scripts/system/operations/AskPlayerNumber.gd:19` `var choice:BaseEffect = AskPlayerOption.new().exec([{`
> `scripts/system/operations/AskPlayerNumber.gd:20` `"shown_option_name": shown_name,`
> `scripts/system/operations/AskPlayerNumber.gd:21` `"quantity_range": [low, high],`
> `scripts/system/operations/AskPlayerNumber.gd:22` `"funcs": []`
> `scripts/system/operations/AskPlayerNumber.gd:23` `}], shown_name, player_id)`
> `scripts/system/operations/AskPlayerNumber.gd:24` `#选择结算时把玩家定的数量写进 result。直接挂一个内部 func，不经 JSON`
> `scripts/system/operations/AskPlayerNumber.gd:25` `var writer := _QuantityWriter.new()`
> `scripts/system/operations/AskPlayerNumber.gd:26` `writer.target = result`
> `scripts/system/operations/AskPlayerNumber.gd:27` `writer.choice = choice`
> `scripts/system/operations/AskPlayersSecretOption.gd:22` `var tags:Array = (copied.get("tags", []) as Array).duplicate()`
> `scripts/system/operations/AskPlayersSecretOption.gd:23` `if !tags.has("secret_choice"):`
> `scripts/system/operations/AskPlayersSecretOption.gd:24` `tags.append("secret_choice")`
> `scripts/system/operations/AskPlayersSecretOption.gd:25` `copied["tags"] = tags`
> `scripts/system/operations/AskPlayersSecretOption.gd:26` `marked.append(copied)`
> `scripts/system/operations/AskPlayersSecretOption.gd:27` `var choice:BaseEffect = AskPlayerOption.new().exec(marked, shown_name, id)`
> `scripts/system/operations/AskPlayersSecretOption.gd:28` `for i in range(choice._options.size()):`
> `scripts/system/operations/AskPlayersSecretOption.gd:29` `var writer := _ResultWriter.new()`
> `scripts/system/operations/AskPlayersSecretOption.gd:30` `writer.results = results`
> `scripts/system/operations/AskPlayerOption.gd:10` `func exec(options:Array, shown_name:String = "", player_id:int = -1, max_choices:int = 1) -> BaseEffect:`
> `scripts/system/operations/AskPlayerOption.gd:11` `var source:BaseEffect = EffectManager.activating_eff`
> `scripts/system/operations/AskPlayerOption.gd:12` `var id:int = EffectManager.resolve_player_id(player_id)`
> `scripts/system/operations/AskPlayerOption.gd:13` `var choice := BaseEffect.new(source._name + "_choice" if source != null else "ask_player_option", [], 0, false, false)`
> `scripts/system/operations/AskPlayerOption.gd:14` `choice._shown_name = shown_name if shown_name != "" else (str(source._shown_name) if source != null else "")`
> `scripts/system/operations/AskPlayerOption.gd:15` `choice._need_activate = false`
> `scripts/system/operations/AskPlayerOption.gd:16` `choice._remove_after_trigger = true`
> `scripts/system/operations/AskPlayerOption.gd:17` `choice._max_choices = max_choices`
> `scripts/system/operations/AskPlayerOption.gd:18` `if source != null:`
> `scripts/system/operations/AskPlayerOption.gd:19` `choice.from = source.from`
> `scripts/system/operations/AskPlayerOption.gd:20` `choice._using_numbers = source._using_numbers`
> `scripts/system/operations/AskPlayerOption.gd:21` `choice.numbers = source.numbers`
> `scripts/system/operations/AskPlayerOption.gd:22` `choice._trigger_time_points = source._trigger_time_points.duplicate()`
> `scripts/system/operations/AskPlayerOption.gd:23` `choice._options = LoadHelper.load_effect_options(options, choice)`
> `scripts/system/operations/AskPlayerOption.gd:24` `EffectManager.register_effect(choice, id)`
> `scripts/system/operations/AskPlayerOption.gd:25` `EffectManager.request_choice(choice)`
> `scripts/system/operations/AskPlayerOption.gd:26` `return choice`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/operations/AskPlayerNumber.gd:19` | 直接实例调用 | `var choice:BaseEffect = AskPlayerOption.new().exec([{` |
| `scripts/system/operations/AskPlayersSecretOption.gd:27` | 直接实例调用 | `var choice:BaseEffect = AskPlayerOption.new().exec(marked, shown_name, id)` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### A — ChangePlOrder
- **定义**：`scripts/system/operations/ChangePlOrder.gd:1`。
- **公开入口**：`scripts/system/operations/ChangePlOrder.gd:4` `func exec(set_order:BaseNumber = null, vary_order:BaseNumber = BaseNumber.new(0), player_id = -1):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:183`，`change_pl_order → ChangePlOrder`，分类 `EDIT_PLAYER`。依据：`"change_pl_order" : { "category": EDIT_PLAYER, "class": "ChangePlOrder", "summary": "轮转顺位" },`。
- **正式数据 func_name 引用**：`change_pl_order` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：<span style="color:#d00000">🔴 是（回合时点副作用）：end_round 先派 DAY_END，随后执行本项清理/重置/轮转；不是本类额外派 DAY_END。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/game_progress.gd:311` `func end_round():`
> `scripts/system/global/game_progress.gd:312` `if _round_end_running:`
> `scripts/system/global/game_progress.gd:313` `return`
> `scripts/system/global/game_progress.gd:314` `_round_end_running = true`
> `scripts/system/global/game_progress.gd:315` `current_phase_index = -1`
> `scripts/system/global/game_progress.gd:316` `current_phase_player_index = 0`
> `scripts/system/global/game_progress.gd:317` `current_player_id = -1`
> `scripts/system/global/game_progress.gd:318` `TimePointChecker.set_phase_time_points([TimePoints.DAY])`
> `scripts/system/global/game_progress.gd:319` `TimePointChecker.global_time_point([TimePoints.DAY_END])`
> `scripts/system/global/game_progress.gd:320` `if not await _wait_round_choices():`
> `scripts/system/global/game_progress.gd:321` `return`
> `scripts/system/global/game_progress.gd:322` `if climax_keep_counts.has(current_round):`
> `scripts/system/global/game_progress.gd:323` `TimePointChecker.global_time_point([TimePoints.CLIMAX_START])`
> `scripts/system/global/game_progress.gd:324` `if not await _wait_round_choices():`
> `scripts/system/global/game_progress.gd:325` `return`
> `scripts/system/global/game_progress.gd:326` `ClimaxResolver.new().exec(climax_keep_counts[current_round])`
> `scripts/system/global/game_progress.gd:358` `#把各席位的地利按印刷基线还原，否则同一席位的地利会跨回合越乘越大，`
> `scripts/system/global/game_progress.gd:359` `#而且改的是共享地图数据，会连带影响之后占据该席位的其他玩家`
> `scripts/system/global/game_progress.gd:360` `RestoreLocationBenefits.new().exec()`
> `scripts/system/global/game_progress.gd:361` `#规则：每个回合结束时，将回合顺位顺时针后移一位（原第二位成为新回合首位）`
> `scripts/system/global/game_progress.gd:362` `ChangePlOrder.new().exec(null, BaseNumber.new(-1))`
> `scripts/system/global/game_progress.gd:363` `_round_end_running = false`
> `scripts/system/global/game_progress.gd:364` `start_round()`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/game_progress.gd:362` | 直接实例调用 | `ChangePlOrder.new().exec(null, BaseNumber.new(-1))` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/_probe_round.gd:28`; `tests/_probe_roundbusy.gd:25`; `tests/_probe_roundshift.gd:19`; `tests/net_round_identity_feedback_test.gd:12`; `tests/residue_pile_test.gd:124`; `tests/round_change_test.gd:58`; `tests/section5_engine_test.gd:329`; `tests/turn_transition_test.gd:118`。
- **排除区（不计本类生产数）/debug**：无。

### A — Deploy
- **定义**：`scripts/system/operations/Deploy.gd:1`。
- **公开入口**：`scripts/system/operations/Deploy.gd:7` `func exec(deploy_location:BaseLocation, player_id:int = -1, ignore_limit:bool = false):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:225`，`deploy → Deploy`，分类 `ACTION`。依据：`"deploy" : { "category": ACTION, "class": "Deploy", "summary": "部署到地点" },`。
- **正式数据 func_name 引用**：`deploy` **1** 条（递归计出现次数，不按卡文件去重）。证据：`data/servants/00004_medusa/00004_medusa.json:614`。
- **是否涉及时点**：<span style="color:#d00000">🔴 是：直连部署经 SetLocation 发 ENTER_LOCATION/LEAVE_LOCATION；Deploy 自身另记部署事实。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/deploy_rules.gd:76` `static func deploy_to_area(area:BaseMapArea, player_id:int) -> BaseLocation:`
> `scripts/system/deploy_rules.gd:77` `var loc:BaseLocation = pick_location(area)`
> `scripts/system/deploy_rules.gd:78` `if loc == null:`
> `scripts/system/deploy_rules.gd:79` `return null`
> `scripts/system/deploy_rules.gd:80` `if !Deploy.new().exec(loc, player_id):`
> `scripts/system/deploy_rules.gd:81` `return null`
> `scripts/system/deploy_rules.gd:82` `apply_benefit(loc, player_id)`
> `scripts/system/operations/Deploy.gd:7` `func exec(deploy_location:BaseLocation, player_id:int = -1, ignore_limit:bool = false):`
> `scripts/system/operations/Deploy.gd:8` ``
> `scripts/system/operations/Deploy.gd:9` `player_id = EffectManager.resolve_player_id(player_id)`
> `scripts/system/operations/Deploy.gd:10` `var settled:bool = SetLocation.new().exec(deploy_location, player_id, false, ignore_limit, false)`
> `scripts/system/operations/Deploy.gd:11` `#部署是独立的规则动作，由入口自己记一条；SetLocation 只记中性的位置变化，`
> `scripts/system/operations/Deploy.gd:12` `#它分不清"部署"和"效果搬运"。只在真正落位后才记，落位失败（位置满）不记`
> `scripts/system/operations/Deploy.gd:13` `if settled:`
> `scripts/system/operations/Deploy.gd:14` `var area := deploy_location.get_from() as BaseMapArea`
> `scripts/system/operations/Deploy.gd:15` `GameLog.record("deploy", player_id, -1,`
> `scripts/system/operations/Deploy.gd:16` `str(area._area_name) if area != null else "", deploy_location, ["deploy"], {})`
> `scripts/system/operations/SetLocation.gd:59` `if old_location != null:`
> `scripts/system/operations/SetLocation.gd:60` `TimePointChecker.dynamic_time_point([TimePoints.LEAVE_LOCATION], player_id, old_location)`
> `scripts/system/operations/SetLocation.gd:61` `TimePointChecker.dynamic_time_point([TimePoints.ENTER_LOCATION], player_id, setted_location)`
> `scripts/system/operations/SetLocation.gd:62` `return true`
> `scripts/system/operations/SetLocation.gd:63` ``
> `scripts/system/operations/SetLocation.gd:64` ``
> `scripts/system/operations/SetLocation.gd:65` `#战区锁的效果名（如固有结界的"不能移动至此也不能离开"）。`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/game_scene/tactical_board_ui.gd:2589` | 直接实例调用 | `Deploy.new().exec(target_loc, _local_player_id)` |
| `scripts/match/match_commands.gd:16` | 直接实例调用 | `Deploy.new().exec(location, player_id)` |
| `scripts/system/ai/temp/dummy_bot.gd:141` | 直接实例调用 | `Deploy.new().exec(target, bot_id)` |
| `scripts/system/deploy_rules.gd:80` | 直接实例调用 | `if !Deploy.new().exec(loc, player_id):` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/bellerophon_edges_test.gd:66,73`; `tests/bellerophon_rules_test.gd:66,105,106`; `tests/bellerophon_window_test.gd:26`; `tests/card_keyword_test.gd:187`; `tests/climax_elimination_test.gd:58`; `tests/deploy_rules_layer_test.gd:53,55`; `tests/deploy_rules_test.gd:25,27,28,29,55`; `tests/engagement_test.gd:65,66,79,80,94,95`; `tests/fd39_operations_test.gd:381,482,588`; `tests/full_game_test.gd:88`; `tests/location_benefit_test.gd:31,68`; `tests/misc_rules_fix_test.gd:149,200,221`; `tests/pending_board_power_test.gd:52,53`; `tests/prepare_phase_test.gd:41`; `tests/section5_engine_test.gd:125,139,160,176,177,180`; `tests/session_restart_test.gd:44`。
- **排除区（不计本类生产数）/debug**：无。

### A — DiscardPlayedCards
- **定义**：`scripts/system/operations/DiscardPlayedCards.gd:1`。
- **公开入口**：`scripts/system/operations/DiscardPlayedCards.gd:4` `func exec(player_id:int = -1):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:219`，`discard_played_cards → DiscardPlayedCards`，分类 `TRANSFER`。依据：`"discard_played_cards" : { "category": TRANSFER, "class": "DiscardPlayedCards", "summary": "回合结束清理场上牌" },`。
- **正式数据 func_name 引用**：`discard_played_cards` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：<span style="color:#d00000">🔴 是（回合时点副作用）：end_round 先派 DAY_END，随后执行本项清理/重置/轮转；不是本类额外派 DAY_END。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/game_progress.gd:311` `func end_round():`
> `scripts/system/global/game_progress.gd:312` `if _round_end_running:`
> `scripts/system/global/game_progress.gd:313` `return`
> `scripts/system/global/game_progress.gd:314` `_round_end_running = true`
> `scripts/system/global/game_progress.gd:315` `current_phase_index = -1`
> `scripts/system/global/game_progress.gd:316` `current_phase_player_index = 0`
> `scripts/system/global/game_progress.gd:317` `current_player_id = -1`
> `scripts/system/global/game_progress.gd:318` `TimePointChecker.set_phase_time_points([TimePoints.DAY])`
> `scripts/system/global/game_progress.gd:319` `TimePointChecker.global_time_point([TimePoints.DAY_END])`
> `scripts/system/global/game_progress.gd:320` `if not await _wait_round_choices():`
> `scripts/system/global/game_progress.gd:321` `return`
> `scripts/system/global/game_progress.gd:322` `if climax_keep_counts.has(current_round):`
> `scripts/system/global/game_progress.gd:323` `TimePointChecker.global_time_point([TimePoints.CLIMAX_START])`
> `scripts/system/global/game_progress.gd:324` `if not await _wait_round_choices():`
> `scripts/system/global/game_progress.gd:325` `return`
> `scripts/system/global/game_progress.gd:326` `ClimaxResolver.new().exec(climax_keep_counts[current_round])`
> `scripts/system/global/game_progress.gd:342` `#规则：回合结束时将每名御主的立牌移除版图（下回合前哨阶段重新部署）。`
> `scripts/system/global/game_progress.gd:343` `#必须在记完 last_turn_location 之后调用，否则查不到本回合结束时的位置`
> `scripts/system/global/game_progress.gd:344` `RemoveFromBoard.new().exec(id)`
> `scripts/system/global/game_progress.gd:345` `#残留牌留在场上，回合结束不处理（残留牌只在自身效果满足条件时自行关闭）`
> `scripts/system/global/game_progress.gd:346` `DiscardPlayedCards.new().exec(id)`
> `scripts/system/global/game_progress.gd:347` `#先清理再重建合计威力基线：规则上残留牌跨回合留场并继续提供威力，`
> `scripts/system/global/game_progress.gd:348` `#所以基线是留场明置牌的威力之和，同时丢弃回合内的非卡牌来源加成`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/game_progress.gd:346` | 直接实例调用 | `DiscardPlayedCards.new().exec(id)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/misc_rules_fix_test.gd:251`; `tests/residue_pile_test.gd:117`; `tests/twelve_labors_lifecycle_test.gd:53`。
- **排除区（不计本类生产数）/debug**：无。

### A — DrawCardByCard
- **定义**：`scripts/system/operations/DrawCardByCard.gd:1`。
- **公开入口**：`scripts/system/operations/DrawCardByCard.gd:7` `func exec(card:BaseCard, from:Array, to:Array, to_index = -1):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:216`，`draw_card_by_card → DrawCardByCard`，分类 `TRANSFER`。依据：`"draw_card_by_card" : { "category": TRANSFER, "class": "DrawCardByCard", "summary": "指定卡在两数组间移动" },`。
- **正式数据 func_name 引用**：`draw_card_by_card` **23** 条（递归计出现次数，不按卡文件去重）。证据：`data/attacks/class/foreigner_class/foreigner_class.json:125`; `data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json:372,481,585,629,697,740,858,962,1006,1074,1117,1362`; `data/masters/00004_matou_sakura/00004_matou_sakura.json:842`; `data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json:513`; `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json:489,677`; `data/servants/00002_emiya/00002_emiya.json:289`; `data/servants/00007_heracles/00007_heracles.json:267,565,863`; `data/servants/00008_angra_mainyu/00008_angra_mainyu.json:434,772`。
- **是否涉及时点**：<span style="color:#d00000">🔴 是：回合弃牌直连经 CardZones.allow_move/notify_moved 进入 before/牌区变化时点。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/operations/DiscardPlayedCards.gd:26` `#普通攻击牌弃置前暗置，再进入弃牌堆`
> `scripts/system/operations/DiscardPlayedCards.gd:27` `if card is BaseAttack:`
> `scripts/system/operations/DiscardPlayedCards.gd:28` `SetCardConcealed.new().exec(card, true, id)`
> `scripts/system/operations/DiscardPlayedCards.gd:29` `DrawCardByCard.new().exec(card, cards_arr, discard, BaseNumber.new(0))`
> `scripts/system/operations/DrawCardByCard.gd:18` `#进入游戏外等区之前先问一次"即将发生"：效果可以取消这次搬运（守护、量子甲胄这类替代）`
> `scripts/system/operations/DrawCardByCard.gd:19` `if !CardZones.allow_move(card, from, to):`
> `scripts/system/operations/DrawCardByCard.gd:20` `return`
> `scripts/system/operations/DrawCardByCard.gd:21` `#先记下两端各是谁的哪个区，搬完再派发牌区变化时点（搬完之后来源数组里已经没有这张牌）`
> `scripts/system/operations/DrawCardByCard.gd:22` `var from_info:Dictionary = CardZones.locate(from)`
> `scripts/system/operations/DrawCardByCard.gd:23` `var to_info:Dictionary = CardZones.locate(to)`
> `scripts/system/operations/DrawCardByCard.gd:24` `from.pop_at(i)`
> `scripts/system/operations/DrawCardByCard.gd:25` `if index == -1:`
> `scripts/system/operations/DrawCardByCard.gd:26` `to.append(card)`
> `scripts/system/operations/DrawCardByCard.gd:27` `else:`
> `scripts/system/operations/DrawCardByCard.gd:28` `to.insert(index, card)`
> `scripts/system/operations/DrawCardByCard.gd:29` `CardZones.notify_moved(card, from_info, to_info)`
> `scripts/system/card_zones.gd:83` `static func allow_move(card, from:Array, to:Array) -> bool:`
> `scripts/system/card_zones.gd:84` `var target := locate(to)`
> `scripts/system/card_zones.gd:85` `var point := _point_of(BEFORE_ENTER_POINTS, target.zone)`
> `scripts/system/card_zones.gd:86` `if point == "":`
> `scripts/system/card_zones.gd:87` `return true`
> `scripts/system/card_zones.gd:88` `var owner:int = int(target.player_id)`
> `scripts/system/card_zones.gd:89` `var action:Dictionary = EffectManager.begin_pending_action(point, owner,`
> `scripts/system/card_zones.gd:90` `{"card": card, "from_zone": locate(from).zone, "to_zone": target.zone}, card)`
> `scripts/system/card_zones.gd:91` `return !bool(action.get("cancelled", false))`
> `scripts/system/card_zones.gd:92` ``
> `scripts/system/card_zones.gd:93` ``
> `scripts/system/card_zones.gd:94` `#搬运完成后派发牌区变化时点。当事人取牌所在区的玩家；两个区都不属于玩家时不派发`
> `scripts/system/card_zones.gd:95` `static func notify_moved(card, from_info:Dictionary, to_info:Dictionary) -> void:`
> `scripts/system/card_zones.gd:96` `var leave := _point_of(LEAVE_POINTS, str(from_info.get("zone", "")))`
> `scripts/system/card_zones.gd:97` `if leave != "" and int(from_info.get("player_id", -1)) >= 0:`
> `scripts/system/card_zones.gd:98` `TimePointChecker.dynamic_time_point([leave], int(from_info.player_id), card)`
> `scripts/system/card_zones.gd:99` `if not EffectManager.defer_until_runtime_guard_complete(Callable(CardZones, "_notify_entered").bind(card, to_info)):`
> `scripts/system/card_zones.gd:100` `_notify_entered(card, to_info)`
> `scripts/system/card_zones.gd:101` ``
> `scripts/system/card_zones.gd:102` ``
> `scripts/system/card_zones.gd:103` `static func _notify_entered(card, to_info:Dictionary) -> void:`
> `scripts/system/card_zones.gd:104` `var enter := _point_of(ENTER_POINTS, str(to_info.get("zone", "")))`
> `scripts/system/card_zones.gd:105` `if enter != "" and int(to_info.get("player_id", -1)) >= 0:`
> `scripts/system/card_zones.gd:106` `TimePointChecker.dynamic_time_point([enter], int(to_info.player_id), card)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/operations/DiscardPlayedCards.gd:29` | 直接实例调用 | `DrawCardByCard.new().exec(card, cards_arr, discard, BaseNumber.new(0))` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/bellerophon_rules_test.gd:98`; `tests/card_zone_browser_test.gd:320`; `tests/debug_identity_hand_test.gd:95`; `tests/fd39_operations_test.gd:186,190,228,232`; `tests/unlimited_blade_activation_test.gd:110,269,272,286`。
- **排除区（不计本类生产数）/debug**：`scripts/debug/debug_adapters/debug_card_adapter.gd:65,115`; `scripts/debug/debug_adapters/debug_identity_adapter.gd:205,372`。

### A — DrawCardFromPlDeckToHand
- **定义**：`scripts/system/operations/DrawCardFromPlDeckToHand.gd:1`。
- **公开入口**：`scripts/system/operations/DrawCardFromPlDeckToHand.gd:7` `func exec(from_index = 0, player_id:int = -1):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:214`，`draw_card_from_pl_deck_to_hand → DrawCardFromPlDeckToHand`，分类 `TRANSFER`。依据：`"draw_card_from_pl_deck_to_hand" : { "category": TRANSFER, "class": "DrawCardFromPlDeckToHand", "summary": "从牌库抽到手数" },`。
- **正式数据 func_name 引用**：`draw_card_from_pl_deck_to_hand` **4** 条（递归计出现次数，不按卡文件去重）。证据：`data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json:775,1152`; `data/servants/00004_medusa/00004_medusa.json:105`; `data/servants/00008_angra_mainyu/00008_angra_mainyu.json:171`。
- **是否涉及时点**：<span style="color:#d00000">🔴 是：回合开始 RefillHand 的直接子调用派 CARD_DRAWN，并通知牌区移动。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/game_progress.gd:271` `"refill":`
> `scripts/system/global/game_progress.gd:272` `if state.index >= state.players.size():`
> `scripts/system/global/game_progress.gd:273` `state.phase = "situation"`
> `scripts/system/global/game_progress.gd:274` `continue`
> `scripts/system/global/game_progress.gd:275` `var id:int = state.players[state.index]`
> `scripts/system/global/game_progress.gd:276` `state.index += 1`
> `scripts/system/global/game_progress.gd:277` `#上限仍读数据，牌堆处理仍由原补牌 operation 负责。`
> `scripts/system/global/game_progress.gd:278` `RefillHand.new().exec(id, GameData.player_hand_limit(id))`
> `scripts/system/operations/RefillHand.gd:30` `if state.hand.size() >= state.target:`
> `scripts/system/operations/RefillHand.gd:31` `break`
> `scripts/system/operations/RefillHand.gd:32` `if not EffectManager.runtime_guard_checkpoint(state):`
> `scripts/system/operations/RefillHand.gd:33` `return`
> `scripts/system/operations/RefillHand.gd:34` `if state.data.deck.is_empty() and not ReshuffleDiscard.new().exec(state.player):`
> `scripts/system/operations/RefillHand.gd:35` `break`
> `scripts/system/operations/RefillHand.gd:36` `state["before"] = state.hand.size()`
> `scripts/system/operations/RefillHand.gd:37` `state.phase = "after_draw"`
> `scripts/system/operations/RefillHand.gd:38` `DrawCardFromPlDeckToHand.new().exec(0, state.player)`
> `scripts/system/operations/RefillHand.gd:39` `if EffectManager.defer_until_runtime_guard_complete(Callable(RefillHand, "_resume_refill").bind(state)):`
> `scripts/system/operations/DrawCardFromPlDeckToHand.gd:19` `deck.pop_at(index)`
> `scripts/system/operations/DrawCardFromPlDeckToHand.gd:20` `var hand = player_data["hand_cards"] as Array`
> `scripts/system/operations/DrawCardFromPlDeckToHand.gd:21` `hand.append(card)`
> `scripts/system/operations/DrawCardFromPlDeckToHand.gd:22` `#日志：抽牌事实（谁在第几回合哪个阶段抽了哪张），排查"手牌莫名多出来"时的第一手依据`
> `scripts/system/operations/DrawCardFromPlDeckToHand.gd:23` `GameLog.record("draw", player_id, -1, "", card, ["draw"],`
> `scripts/system/operations/DrawCardFromPlDeckToHand.gd:24` `{"card_name": card.get_shown_name() if card.has_method("get_shown_name") else str(card), "from_index": index})`
> `scripts/system/operations/DrawCardFromPlDeckToHand.gd:25` `#抽牌时点带上这张牌作来源；牌区变化（离开牌库、进入手牌）与其它搬运入口同一套派发`
> `scripts/system/operations/DrawCardFromPlDeckToHand.gd:26` `TimePointChecker.dynamic_time_point([TimePoints.CARD_DRAWN], player_id, card)`
> `scripts/system/operations/DrawCardFromPlDeckToHand.gd:27` `if not EffectManager.defer_until_runtime_guard_complete(Callable(DrawCardFromPlDeckToHand, "_notify_moved").bind(card, player_id)):`
> `scripts/system/operations/DrawCardFromPlDeckToHand.gd:28` `_notify_moved(card, player_id)`
> `scripts/system/operations/DrawCardFromPlDeckToHand.gd:29` ``
> `scripts/system/operations/DrawCardFromPlDeckToHand.gd:30` ``
> `scripts/system/operations/DrawCardFromPlDeckToHand.gd:31` `static func _notify_moved(card:BaseCard, player_id:int) -> void:`
> `scripts/system/operations/DrawCardFromPlDeckToHand.gd:32` `CardZones.notify_moved(card, {"player_id": player_id, "zone": "deck"}, {"player_id": player_id, "zone": "hand_cards"})`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/operations/RefillHand.gd:38` | 直接实例调用 | `DrawCardFromPlDeckToHand.new().exec(0, state.player)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/fd39_operations_test.gd:204`; `tests/held_cards_window_test.gd:180`; `tests/rule_guard_zone_notify_test.gd:23`。
- **排除区（不计本类生产数）/debug**：`scripts/debug/debug_adapters/debug_card_adapter.gd:147`。

### A — EditMagic
- **定义**：`scripts/system/operations/EditMagic.gd:1`。
- **公开入口**：`scripts/system/operations/EditMagic.gd:4` `func exec(set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0), player_id:int = -1, payment_purpose:String = "", payment_source = null):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:177`，`edit_magic → EditMagic`，分类 `EDIT_PLAYER`。依据：`"edit_magic" : { "category": EDIT_PLAYER, "class": "EditMagic", "summary": "改魔力并派发时点" },`。
- **正式数据 func_name 引用**：`edit_magic` **16** 条（递归计出现次数，不按卡文件去重）。证据：`data/command_spells/normal_command_spell.json:45`; `data/events/origin/ley_line/ley_line.json:57`; `data/masters/00001_emiya_shirou/00001_emiya_shirou.json:26,79`; `data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json:301,495,872,1326`; `data/masters/00003_matou_shinji/00003_matou_shinji.json:51,389`; `data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json:26,311`; `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json:743`; `data/servants/00005_medea/00005_medea.json:151`; `data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json:134`; `data/servants/00008_angra_mainyu/00008_angra_mainyu.json:189`。
- **是否涉及时点**：<span style="color:#d00000">🔴 是：即将增魔/增魔/减魔时点；直连来自局势激活、部署收益、移动/效果支付。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/situation_resolver.gd:29` `while state.index < state.players.size():`
> `scripts/system/global/situation_resolver.gd:30` `var id:int = state.players[state.index]`
> `scripts/system/global/situation_resolver.gd:31` `state.index += 1`
> `scripts/system/global/situation_resolver.gd:32` `EditMagic.new().exec(null, situation._magic, id)`
> `scripts/system/global/situation_resolver.gd:33` `if EffectManager.defer_until_runtime_guard_complete(Callable(SituationResolver, "_resume_activation").bind(state)):`
> `scripts/system/deploy_rules.gd:63` `#限制类效果按来源名查询（如"无法从魔术工房获得魔力"）：来源名由战区数据声明，`
> `scripts/system/deploy_rules.gd:64` `#不写死"workshop"；没有声明来源的席位只受总闸限制`
> `scripts/system/deploy_rules.gd:65` `var area := loc.get_from() as BaseMapArea`
> `scripts/system/deploy_rules.gd:66` `var source:String = area._magic_source if area != null else ""`
> `scripts/system/deploy_rules.gd:67` `if !CanGainMagic.new().exec(source, player_id):`
> `scripts/system/deploy_rules.gd:68` `return 0`
> `scripts/system/deploy_rules.gd:69` `EditMagic.new().exec(null, BaseNumber.new(gain.number), player_id)`
> `scripts/system/operations/EditMagic.gd:15` `var target = (set_num.number if set_num != null else before) + (vary_num.number if vary_num != null else 0)`
> `scripts/system/operations/EditMagic.gd:16` `#即将获得魔力：效果可以取消，或改写获得的数量（来源倍率、每回合获得上限）`
> `scripts/system/operations/EditMagic.gd:17` `if target > before:`
> `scripts/system/operations/EditMagic.gd:18` `var action:Dictionary = EffectManager.begin_pending_action(TimePoints.BEFORE_MAGIC_ADD, id,`
> `scripts/system/operations/EditMagic.gd:19` `{"amount": BaseNumber.new(target - before)})`
> `scripts/system/operations/EditMagic.gd:20` `if action.get("cancelled", false):`
> `scripts/system/operations/EditMagic.gd:21` `return`
> `scripts/system/operations/EditMagic.gd:22` `target = before + (action.values.amount as BaseNumber).number`
> `scripts/system/operations/EditMagic.gd:23` `magic.set_num(BaseNumber.new(target))`
> `scripts/system/operations/EditMagic.gd:24` ``
> `scripts/system/operations/EditMagic.gd:25` `#规则：魔力是 0 到上限之间的资源（上限本身是数据、效果可以改）。`
> `scripts/system/operations/EditMagic.gd:39` `else:`
> `scripts/system/operations/EditMagic.gd:40` `GameLog.record_resource_change("magic", id, before, magic.number)`
> `scripts/system/operations/EditMagic.gd:41` ``
> `scripts/system/operations/EditMagic.gd:42` `if delta > 0:`
> `scripts/system/operations/EditMagic.gd:43` `TimePointChecker.dynamic_time_point([TimePoints.MAGIC_ADD], id)`
> `scripts/system/operations/EditMagic.gd:44` `elif delta < 0:`
> `scripts/system/operations/EditMagic.gd:45` `TimePointChecker.dynamic_time_point([TimePoints.MAGIC_DECREASE], id)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/deploy_rules.gd:69` | 直接实例调用 | `EditMagic.new().exec(null, BaseNumber.new(gain.number), player_id)` |
| `scripts/system/global/effect_manager.gd:1565` | 直接实例调用 | `EditMagic.new().exec(null, BaseNumber.new(0 - cost.number), id, "effect_cost", effect)` |
| `scripts/system/global/situation_resolver.gd:32` | 直接实例调用 | `EditMagic.new().exec(null, situation._magic, id)` |
| `scripts/system/operations/Move.gd:21` | 直接实例调用 | `EditMagic.new().exec(null, BaseNumber.new(0 - max(0, cost.number)), player_id, "move", player_data.location)` |
- **排除区（不计本类生产数）/测试/诊断**：`newtests/magic_overdraft_declaration_test.gd:94,96,99`; `tests/debug_unbounded_number_test.gd:105,107`; `tests/fd39_operations_test.gd:172,174,461,462`; `tests/magic_limit_test.gd:35,43,47,51`; `tests/mana_spend_test.gd:46,51,61,127,145`; `tests/masters_audit_fix_test.gd:62,64`; `tests/net_guard_rollback_test.gd:11`; `tests/refactor_kernel_state_boundaries_test.gd:18`; `tests/rule_guard_continuation_fixture.gd:13,16`; `tests/rule_guard_rollback_fixture.gd:16`; `tests/rule_guard_root_transaction_v2_test.gd:16`。
- **排除区（不计本类生产数）/debug**：`scripts/debug/debug_adapters/debug_board_adapter.gd:85`。

### A — EditPower
- **定义**：`scripts/system/operations/EditPower.gd:1`。
- **公开入口**：`scripts/system/operations/EditPower.gd:4` `func exec(set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0), player_id:int = -1):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:180`，`edit_power → EditPower`，分类 `EDIT_PLAYER`。依据：`"edit_power" : { "category": EDIT_PLAYER, "class": "EditPower", "summary": "改合计威力" },`。
- **正式数据 func_name 引用**：`edit_power` **6** 条（递归计出现次数，不按卡文件去重）。证据：`data/masters/00001_emiya_shirou/00001_emiya_shirou.json:212`; `data/masters/00003_matou_shinji/00003_matou_shinji.json:1209`; `data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json:503`; `data/servants/00007_heracles/00007_heracles.json:219,517,815`。
- **是否涉及时点**：<span style="color:#d00000">🔴 是（时点结算副作用，不自行派时点）：ZeroAttributePower/ModifyAttackPowerByAttribute 直连改威力；前者是战斗结算前规则动作，后者有正式阶段效果数据。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/operations/ZeroAttributePower.gd:4` `#将目标玩家指定属性的攻击威力按0计：扫描其场上这些属性的攻击牌，`
> `scripts/system/operations/ZeroAttributePower.gd:5` `#把它们的威力贡献从合计威力里一次性扣掉。`
> `scripts/system/operations/ZeroAttributePower.gd:6` `#在战斗结算前的时点(所有人出完牌后)调用；回合结束 SyncPower 重建基线时恢复，不永久改牌。`
> `scripts/system/operations/ZeroAttributePower.gd:7` `#属性由调用方传入，不写死迅捷/魔术/力量；player_id 默认当前效果归属玩家。`
> `scripts/system/operations/ZeroAttributePower.gd:8` `func exec(player_id:int = -1, attributes:Array = []):`
> `scripts/system/operations/ZeroAttributePower.gd:21` `for attribute in attributes:`
> `scripts/system/operations/ZeroAttributePower.gd:22` `if card.has_attribute(attribute):`
> `scripts/system/operations/ZeroAttributePower.gd:23` `total += (card._power as BaseNumber).number`
> `scripts/system/operations/ZeroAttributePower.gd:24` `break`
> `scripts/system/operations/ZeroAttributePower.gd:25` `if total > 0:`
> `scripts/system/operations/ZeroAttributePower.gd:26` `EditPower.new().exec(null, BaseNumber.new(-total), id)`
> `scripts/system/operations/ModifyAttackPowerByAttribute.gd:36` `total += power_delta.number`
> `scripts/system/operations/ModifyAttackPowerByAttribute.gd:37` `if total == 0:`
> `scripts/system/operations/ModifyAttackPowerByAttribute.gd:38` `return`
> `scripts/system/operations/ModifyAttackPowerByAttribute.gd:39` `#复用EditPower统一改写玩家的合计威力`
> `scripts/system/operations/ModifyAttackPowerByAttribute.gd:40` `EditPower.new().exec(null, BaseNumber.new(total), id)`
> `scripts/system/operations/EditPower.gd:9` `var before = power.number`
> `scripts/system/operations/EditPower.gd:10` `#就地改写玩家自己的数字，避免把效果自带的数字对象挂到玩家身上`
> `scripts/system/operations/EditPower.gd:11` `if set_num != null:`
> `scripts/system/operations/EditPower.gd:12` `power.set_num(set_num)`
> `scripts/system/operations/EditPower.gd:13` `power.add(vary_num)`
> `scripts/system/operations/EditPower.gd:14` `#记下这次合计威力变化来自哪类对象（局势/事件/御主/令咒/他人的牌……），`
> `scripts/system/operations/EditPower.gd:15` `#供"排除局势与事件影响后的合计威力"这类查询按来源统计，不给玩家加字段`
> `scripts/system/operations/EditPower.gd:16` `PowerSources.record(id, "power", power.number - before)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/operations/CloseCard.gd:22` | 直接实例调用 | `EditPower.new().exec(null, BaseNumber.new(-card._power.number), id)` |
| `scripts/system/operations/ModifyAttackPowerByAttribute.gd:40` | 直接实例调用 | `EditPower.new().exec(null, BaseNumber.new(total), id)` |
| `scripts/system/operations/ZeroAttributePower.gd:26` | 直接实例调用 | `EditPower.new().exec(null, BaseNumber.new(-total), id)` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### A — EditScore
- **定义**：`scripts/system/operations/EditScore.gd:1`。
- **公开入口**：`scripts/system/operations/EditScore.gd:4` `func exec(set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0), player_id:int = -1):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:178`，`edit_score → EditScore`，分类 `EDIT_PLAYER`。依据：`"edit_score" : { "category": EDIT_PLAYER, "class": "EditScore", "summary": "改战果并派发时点" },`。
- **正式数据 func_name 引用**：`edit_score` **21** 条（递归计出现次数，不按卡文件去重）。证据：`data/attacks/basic/preparation/preparation.json:104`; `data/command_spells/normal_command_spell.json:70`; `data/masters/00003_matou_shinji/00003_matou_shinji.json:1432,1656`; `data/masters/00004_matou_sakura/00004_matou_sakura.json:580`; `data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json:403`; `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json:331`; `data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json:178,254`; `data/servants/00002_emiya/00002_emiya.json:214`; `data/servants/00003_cu_chulainn/00003_cu_chulainn.json:207,254`; `data/servants/00005_medea/00005_medea.json:164`; `data/servants/00007_heracles/00007_heracles.json:137,151,435,449,733,747`; `data/servants/00008_angra_mainyu/00008_angra_mainyu.json:1042,1055`。
- **是否涉及时点**：<span style="color:#d00000">🔴 是：BattleResolver 直连加战果，派 BEFORE_SCORE_ADD、SCORE_ADD/DECREASE；成功收益后再发 BATTLE_WIN。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/battle_resolver.gd:205` `#平分按参战条目数算（两个条目并列就是两份），与原规则一致`
> `scripts/system/global/battle_resolver.gd:206` `if winners.size() == 1:`
> `scripts/system/global/battle_resolver.gd:207` `var winner_id:int = winners[0]`
> `scripts/system/global/battle_resolver.gd:208` `var rep_id:int = GameDataManager.represented_id(winner_id)`
> `scripts/system/global/battle_resolver.gd:209` `EditScore.new().exec(null, BaseNumber.new(total_score), rep_id)`
> `scripts/system/global/battle_resolver.gd:210` `TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], rep_id)`
> `scripts/system/global/battle_resolver.gd:211` `result["winners_by_area"][area._area_name] = [winner_id]`
> `scripts/system/global/battle_resolver.gd:212` `elif winners.size() > 1:`
> `scripts/system/global/battle_resolver.gd:213` `#平局：战果平分并向上取整`
> `scripts/system/global/battle_resolver.gd:214` `var split_score:int = ceili(float(total_score) / winners.size())`
> `scripts/system/global/battle_resolver.gd:215` `for winner_id in winners:`
> `scripts/system/global/battle_resolver.gd:216` `var rep_id:int = GameDataManager.represented_id(winner_id)`
> `scripts/system/global/battle_resolver.gd:217` `EditScore.new().exec(null, BaseNumber.new(split_score), rep_id)`
> `scripts/system/global/battle_resolver.gd:218` `TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], rep_id)`
> `scripts/system/global/battle_resolver.gd:219` `result["winners_by_area"][area._area_name] = winners`
> `scripts/system/operations/EditScore.gd:9` `var before = score.number`
> `scripts/system/operations/EditScore.gd:10` `var target = (set_num.number if set_num != null else before) + (vary_num.number if vary_num != null else 0)`
> `scripts/system/operations/EditScore.gd:11` `#即将获得战果：效果可以取消，或改写这次获得的数量（减半、翻倍、设上限）`
> `scripts/system/operations/EditScore.gd:12` `if target > before:`
> `scripts/system/operations/EditScore.gd:13` `var action:Dictionary = EffectManager.begin_pending_action(TimePoints.BEFORE_SCORE_ADD, player_id,`
> `scripts/system/operations/EditScore.gd:14` `{"amount": BaseNumber.new(target - before)})`
> `scripts/system/operations/EditScore.gd:15` `if action.get("cancelled", false):`
> `scripts/system/operations/EditScore.gd:16` `return`
> `scripts/system/operations/EditScore.gd:17` `target = before + (action.values.amount as BaseNumber).number`
> `scripts/system/operations/EditScore.gd:27` `GameLog.record_resource_change("score", player_id, before, score.number)`
> `scripts/system/operations/EditScore.gd:28` ``
> `scripts/system/operations/EditScore.gd:29` `if delta > 0:`
> `scripts/system/operations/EditScore.gd:30` `TimePointChecker.dynamic_time_point([TimePoints.SCORE_ADD], player_id)`
> `scripts/system/operations/EditScore.gd:31` `elif delta < 0:`
> `scripts/system/operations/EditScore.gd:32` `TimePointChecker.dynamic_time_point([TimePoints.SCORE_DECREASE], player_id)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/battle_resolver.gd:209` | 直接实例调用 | `EditScore.new().exec(null, BaseNumber.new(total_score), rep_id)` |
| `scripts/system/global/battle_resolver.gd:217` | 直接实例调用 | `EditScore.new().exec(null, BaseNumber.new(split_score), rep_id)` |
| `scripts/system/global/battle_resolver.gd:271` | 直接实例调用 | `EditScore.new().exec(null, BaseNumber.new(score), id)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/battle_score_report_test.gd:238`; `tests/fd39_operations_test.gd:130,138,140,142,472,473,476,477`; `tests/masters_audit_fix_test.gd:117`。
- **排除区（不计本类生产数）/debug**：无。

### A — ManageBuff
- **定义**：`scripts/system/operations/ManageBuff.gd:1`。
- **公开入口**：`scripts/system/operations/ManageBuff.gd:4` `func exec(buff, player_id:int = -1, add_or_del:bool = true):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:234`，`manage_buff → ManageBuff`，分类 `BUFF`。依据：`"manage_buff" : { "category": BUFF, "class": "ManageBuff", "summary": "给玩家加或删buff" },`。
- **正式数据 func_name 引用**：`manage_buff` **11** 条（递归计出现次数，不按卡文件去重）。证据：`data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json:84`; `data/masters/00003_matou_shinji/00003_matou_shinji.json:123,451,998`; `data/masters/00004_matou_sakura/00004_matou_sakura.json:65,315,1022`; `data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json:124`; `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json:67,96`; `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json:166`。
- **是否涉及时点**：<span style="color:#d00000">🔴 是：DefeatBuff.apply/remove 直接创建/删除状态；本类登记/注销效果并发 BUFF_START/BUFF_END。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/buffs/defeat_buff.gd:29` `#给指定玩家附加一层【败北】，可叠加`
> `scripts/system/buffs/defeat_buff.gd:30` `static func apply(player_id:int = GameData.player_id) -> DefeatBuff:`
> `scripts/system/buffs/defeat_buff.gd:31` `var defeat = DefeatBuff.new()`
> `scripts/system/buffs/defeat_buff.gd:32` `ManageBuff.new().exec(defeat, player_id, true)`
> `scripts/system/buffs/defeat_buff.gd:33` `return defeat`
> `scripts/system/buffs/defeat_buff.gd:34` ``
> `scripts/system/buffs/defeat_buff.gd:35` ``
> `scripts/system/buffs/defeat_buff.gd:36` `#移除指定玩家的所有【败北】(通常由回合结束清理调用)`
> `scripts/system/buffs/defeat_buff.gd:37` `static func remove(player_id:int = GameData.player_id):`
> `scripts/system/buffs/defeat_buff.gd:38` `var player_data = GameDataManager.get_player_data(player_id) as Dictionary`
> `scripts/system/buffs/defeat_buff.gd:39` `var buffs:Array = player_data["buffs"]`
> `scripts/system/buffs/defeat_buff.gd:40` `for i in range(buffs.size() - 1, -1, -1):`
> `scripts/system/buffs/defeat_buff.gd:41` `if buffs[i] is DefeatBuff:`
> `scripts/system/buffs/defeat_buff.gd:42` `var defeat = buffs[i] as DefeatBuff`
> `scripts/system/buffs/defeat_buff.gd:43` `#BaseEffect构造时会登记进GameData.effects，随buff一起摘除，避免残留`
> `scripts/system/buffs/defeat_buff.gd:44` `for eff in defeat._effects:`
> `scripts/system/buffs/defeat_buff.gd:45` `if eff is BaseEffect:`
> `scripts/system/buffs/defeat_buff.gd:46` `eff.del()`
> `scripts/system/buffs/defeat_buff.gd:47` `ManageBuff.new().exec(defeat, player_id, false)`
> `scripts/system/operations/ManageBuff.gd:12` `if add_or_del:`
> `scripts/system/operations/ManageBuff.gd:13` `if buffs.has(buff):`
> `scripts/system/operations/ManageBuff.gd:14` `return false`
> `scripts/system/operations/ManageBuff.gd:15` `buffs.append(buff)`
> `scripts/system/operations/ManageBuff.gd:16` `if buff is BaseBuff:`
> `scripts/system/operations/ManageBuff.gd:17` `EffectManager.register_effects(buff._effects, id)`
> `scripts/system/operations/ManageBuff.gd:18` `TimePointChecker.dynamic_time_point([TimePoints.BUFF_START], id)`
> `scripts/system/operations/ManageBuff.gd:19` `return true`
> `scripts/system/operations/ManageBuff.gd:20` ``
> `scripts/system/operations/ManageBuff.gd:21` `if !buffs.has(buff):`
> `scripts/system/operations/ManageBuff.gd:22` `return false`
> `scripts/system/operations/ManageBuff.gd:23` `if buff is BaseBuff:`
> `scripts/system/operations/ManageBuff.gd:24` `for effect:BaseEffect in buff._effects:`
> `scripts/system/operations/ManageBuff.gd:25` `EffectManager.unregister_effect(effect)`
> `scripts/system/operations/ManageBuff.gd:26` `TimePointChecker.dynamic_time_point([TimePoints.BUFF_END], id)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/buffs/defeat_buff.gd:32` | 直接实例调用 | `ManageBuff.new().exec(defeat, player_id, true)` |
| `scripts/system/buffs/defeat_buff.gd:47` | 直接实例调用 | `ManageBuff.new().exec(defeat, player_id, false)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/mana_spend_test.gd:99,103,107,113,119`; `tests/masters_audit_fix_test.gd:82,109`; `tests/opponent_drawer_test.gd:48,220`; `tests/private_knowledge_corrosion_test.gd:7,9`。
- **排除区（不计本类生产数）/debug**：`scripts/debug/debug_adapters/debug_identity_adapter.gd:236,237,248,260`; `scripts/debug/debug_adapters/debug_player_adapter.gd:122`。

### A — Move
- **定义**：`scripts/system/operations/Move.gd:1`。
- **公开入口**：`scripts/system/operations/Move.gd:4` `func exec(move_num:BaseNumber, player_id:int = -1, ignore_limit:bool = false, ignore_battle:bool = false):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:226`，`move → Move`，分类 `ACTION`。依据：`"move" : { "category": ACTION, "class": "Move", "summary": "常规移动并扣魔力" },`。
- **正式数据 func_name 引用**：`move` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：<span style="color:#d00000">🔴 是：代码直连移动经 MoveLocation→SetLocation 发位置时点，经 EditMagic 发减魔时点。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/match/match_commands.gd:19` `DeployRules.apply_benefit(location, player_id)`
> `scripts/match/match_commands.gd:20` `return true`
> `scripts/match/match_commands.gd:21` ``
> `scripts/match/match_commands.gd:22` `func move(step: int, player_id: int) -> void:`
> `scripts/match/match_commands.gd:23` `Move.new().exec(BaseNumber.new(step), player_id)`
> `scripts/match/match_commands.gd:24` ``
> `scripts/system/operations/Move.gd:13` `if !ignore_battle and !ignore_engagement and IsEngaged.new().exec(player_id):`
> `scripts/system/operations/Move.gd:14` `EffectManager.push_message("处于交战状态，无法移动", player_id)`
> `scripts/system/operations/Move.gd:15` `return`
> `scripts/system/operations/Move.gd:16` `var cost = MoveLocation.new().exec(move_num, player_id, ignore_limit)`
> `scripts/system/operations/Move.gd:17` `#目标落位失败时不扣费；MoveLocation 用 null 表示没有完成移动。`
> `scripts/system/operations/Move.gd:18` `if cost == null:`
> `scripts/system/operations/Move.gd:19` `return`
> `scripts/system/operations/Move.gd:20` `#MoveLocation 返回 BaseNumber，扣费 operation 需要同样的数值对象，不能直接做 int/Object 运算。`
> `scripts/system/operations/Move.gd:21` `EditMagic.new().exec(null, BaseNumber.new(0 - max(0, cost.number)), player_id, "move", player_data.location)`
> `scripts/system/operations/SetLocation.gd:59` `if old_location != null:`
> `scripts/system/operations/SetLocation.gd:60` `TimePointChecker.dynamic_time_point([TimePoints.LEAVE_LOCATION], player_id, old_location)`
> `scripts/system/operations/SetLocation.gd:61` `TimePointChecker.dynamic_time_point([TimePoints.ENTER_LOCATION], player_id, setted_location)`
> `scripts/system/operations/SetLocation.gd:62` `return true`
> `scripts/system/operations/SetLocation.gd:63` ``
> `scripts/system/operations/SetLocation.gd:64` ``
> `scripts/system/operations/SetLocation.gd:65` `#战区锁的效果名（如固有结界的"不能移动至此也不能离开"）。`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/game_scene/tactical_board_ui.gd:2600` | 直接实例调用 | `Move.new().exec(BaseNumber.new(step), _local_player_id)` |
| `scripts/match/match_commands.gd:23` | 直接实例调用 | `Move.new().exec(BaseNumber.new(step), player_id)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/engagement_test.gd:69,85,136`; `tests/mana_spend_test.gd:38,68,96`; `tests/misc_rules_fix_test.gd:192,198`。
- **排除区（不计本类生产数）/debug**：`scripts/debug/debug_adapters/debug_map_adapter.gd:60`。

### A — MoveLocation
- **定义**：`scripts/system/operations/MoveLocation.gd:1`。
- **公开入口**：`scripts/system/operations/MoveLocation.gd:7` `func exec(move_num:BaseNumber, player_id:int = -1, ignore_limit:bool = false):`; `scripts/system/operations/MoveLocation.gd:78` `static func step_cost_discount(player_data:Dictionary) -> int:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:227`，`move_location → MoveLocation`，分类 `ACTION`。依据：`"move_location" : { "category": ACTION, "class": "MoveLocation", "summary": "只改位置并返回费用" },`。
- **正式数据 func_name 引用**：`move_location` **1** 条（递归计出现次数，不按卡文件去重）。证据：`data/attacks/basic/surveil/surveil.json:127`。
- **是否涉及时点**：<span style="color:#d00000">🔴 是：Move 的直接子调用，经 SetLocation 触发位置变化时点。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/operations/Move.gd:13` `if !ignore_battle and !ignore_engagement and IsEngaged.new().exec(player_id):`
> `scripts/system/operations/Move.gd:14` `EffectManager.push_message("处于交战状态，无法移动", player_id)`
> `scripts/system/operations/Move.gd:15` `return`
> `scripts/system/operations/Move.gd:16` `var cost = MoveLocation.new().exec(move_num, player_id, ignore_limit)`
> `scripts/system/operations/Move.gd:17` `#目标落位失败时不扣费；MoveLocation 用 null 表示没有完成移动。`
> `scripts/system/operations/Move.gd:18` `if cost == null:`
> `scripts/system/operations/Move.gd:19` `return`
> `scripts/system/operations/Move.gd:20` `#MoveLocation 返回 BaseNumber，扣费 operation 需要同样的数值对象，不能直接做 int/Object 运算。`
> `scripts/system/operations/Move.gd:21` `EditMagic.new().exec(null, BaseNumber.new(0 - max(0, cost.number)), player_id, "move", player_data.location)`
> `scripts/system/operations/MoveLocation.gd:57` `#"挑哪个点位"与界面提示共用 GetMoveTargetLocation：落点规则只实现一处`
> `scripts/system/operations/MoveLocation.gd:58` `var target_location:BaseLocation = GetMoveTargetLocation.new().exec(area, ignore_limit)`
> `scripts/system/operations/MoveLocation.gd:59` `if target_location == null:`
> `scripts/system/operations/MoveLocation.gd:60` `EffectManager.push_message("【%s】的常规落点已满" % area._area_name, player_id)`
> `scripts/system/operations/MoveLocation.gd:61` `return null`
> `scripts/system/operations/MoveLocation.gd:62` ``
> `scripts/system/operations/MoveLocation.gd:63` `#先确定折扣后的费用并校验余额，拒绝时不能先落位再部分扣费。`
> `scripts/system/operations/MoveLocation.gd:64` `if origin_area == MapData.magic_workshop:`
> `scripts/system/operations/MoveLocation.gd:65` `var discount = (player_data["move_cost_discount_from_workshop"] as BaseNumber).number`
> `scripts/system/operations/MoveLocation.gd:66` `total_cost.number = max(0, total_cost.number - discount)`
> `scripts/system/operations/MoveLocation.gd:67` `if not player_data.get("is_magic_immune", false) and player_data.magic.number < total_cost.number:`
> `scripts/system/operations/MoveLocation.gd:68` `EffectManager.push_message("魔力不足，无法移动", player_id)`
> `scripts/system/operations/MoveLocation.gd:69` `return null`
> `scripts/system/operations/MoveLocation.gd:70` `if !SetLocation.new().exec(target_location, player_id, true, ignore_limit):`
> `scripts/system/operations/MoveLocation.gd:71` `EffectManager.push_message("无法在【%s】落位" % area._area_name, player_id)`
> `scripts/system/operations/MoveLocation.gd:72` `return null`
> `scripts/system/operations/MoveLocation.gd:73` ``
> `scripts/system/operations/MoveLocation.gd:74` `return total_cost`
> `scripts/system/operations/SetLocation.gd:59` `if old_location != null:`
> `scripts/system/operations/SetLocation.gd:60` `TimePointChecker.dynamic_time_point([TimePoints.LEAVE_LOCATION], player_id, old_location)`
> `scripts/system/operations/SetLocation.gd:61` `TimePointChecker.dynamic_time_point([TimePoints.ENTER_LOCATION], player_id, setted_location)`
> `scripts/system/operations/SetLocation.gd:62` `return true`
> `scripts/system/operations/SetLocation.gd:63` ``
> `scripts/system/operations/SetLocation.gd:64` ``
> `scripts/system/operations/SetLocation.gd:65` `#战区锁的效果名（如固有结界的"不能移动至此也不能离开"）。`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/area_action_rules.gd:17` | 类/静态公开入口 | `var step_discount: int = MoveLocation.step_cost_discount(pl_data)` |
| `scripts/system/operations/Move.gd:16` | 直接实例调用 | `var cost = MoveLocation.new().exec(move_num, player_id, ignore_limit)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/fd39_operations_test.gd:493`; `tests/misc_rules_fix_test.gd:133,137,144`。
- **排除区（不计本类生产数）/debug**：无。

### A — RefillHand
- **定义**：`scripts/system/operations/RefillHand.gd:1`。
- **公开入口**：`scripts/system/operations/RefillHand.gd:8` `func exec(player_id:int = -1, limit = 0) -> int:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:229`，`refill_hand → RefillHand`，分类 `ACTION`。依据：`"refill_hand" : { "category": ACTION, "class": "RefillHand", "summary": "把玩家手牌补充到上限" },`。
- **正式数据 func_name 引用**：`refill_hand` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：<span style="color:#d00000">🔴 是：回合开始补牌链；直接子调用抽牌/洗回引发 CARD_DRAWN / DECK_RESHUFFLED。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/game_progress.gd:263` `"window":`
> `scripts/system/global/game_progress.gd:264` `state.phase = "refill_setup"`
> `scripts/system/global/game_progress.gd:265` `TimePointChecker.set_phase_time_points([TimePoints.DAY])`
> `scripts/system/global/game_progress.gd:266` `"refill_setup":`
> `scripts/system/global/game_progress.gd:267` `#重置效果可能改变顺位，所以仍在补牌前读取当前顺位。`
> `scripts/system/global/game_progress.gd:268` `state.players = get_ordered_player_ids()`
> `scripts/system/global/game_progress.gd:269` `state.index = 0`
> `scripts/system/global/game_progress.gd:270` `state.phase = "refill"`
> `scripts/system/global/game_progress.gd:271` `"refill":`
> `scripts/system/global/game_progress.gd:272` `if state.index >= state.players.size():`
> `scripts/system/global/game_progress.gd:273` `state.phase = "situation"`
> `scripts/system/global/game_progress.gd:274` `continue`
> `scripts/system/global/game_progress.gd:275` `var id:int = state.players[state.index]`
> `scripts/system/global/game_progress.gd:276` `state.index += 1`
> `scripts/system/global/game_progress.gd:277` `#上限仍读数据，牌堆处理仍由原补牌 operation 负责。`
> `scripts/system/global/game_progress.gd:278` `RefillHand.new().exec(id, GameData.player_hand_limit(id))`
> `scripts/system/global/game_progress.gd:279` `"situation":`
> `scripts/system/global/game_progress.gd:280` `state.phase = "day_start"`
> `scripts/system/global/game_progress.gd:281` `SituationResolver.new().activate()`
> `scripts/system/global/game_progress.gd:282` `"day_start":`
> `scripts/system/global/game_progress.gd:283` `state.phase = "events"`
> `scripts/system/global/game_progress.gd:284` `TimePointChecker.global_time_point([TimePoints.DAY_START])`
> `scripts/system/operations/RefillHand.gd:30` `if state.hand.size() >= state.target:`
> `scripts/system/operations/RefillHand.gd:31` `break`
> `scripts/system/operations/RefillHand.gd:32` `if not EffectManager.runtime_guard_checkpoint(state):`
> `scripts/system/operations/RefillHand.gd:33` `return`
> `scripts/system/operations/RefillHand.gd:34` `if state.data.deck.is_empty() and not ReshuffleDiscard.new().exec(state.player):`
> `scripts/system/operations/RefillHand.gd:35` `break`
> `scripts/system/operations/RefillHand.gd:36` `state["before"] = state.hand.size()`
> `scripts/system/operations/RefillHand.gd:37` `state.phase = "after_draw"`
> `scripts/system/operations/RefillHand.gd:38` `DrawCardFromPlDeckToHand.new().exec(0, state.player)`
> `scripts/system/operations/RefillHand.gd:39` `if EffectManager.defer_until_runtime_guard_complete(Callable(RefillHand, "_resume_refill").bind(state)):`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/game_progress.gd:278` | 直接实例调用 | `RefillHand.new().exec(id, GameData.player_hand_limit(id))` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/fd39_operations_test.gd:469`; `tests/prepare_phase_test.gd:20,22,24,29,35`; `tests/rule_guard_loop_owner_test.gd:21`; `tests/rule_guard_native_refill_test.gd:11`; `tests/rule_guard_refill_test.gd:23`。
- **排除区（不计本类生产数）/debug**：`scripts/debug/debug_adapters/debug_card_adapter.gd:156`; `scripts/debug/debug_adapters/debug_identity_adapter.gd:176`。

### A — RegisterObjectEffects
- **定义**：`scripts/system/operations/RegisterObjectEffects.gd:1`。
- **公开入口**：`scripts/system/operations/RegisterObjectEffects.gd:5` `func exec(object, player_id:int = -1):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:239`，`register_object_effects → RegisterObjectEffects`，分类 `EFFECT`。依据：`"register_object_effects" : { "category": EFFECT, "class": "RegisterObjectEffects", "summary": "登记对象上的效果" },`。
- **正式数据 func_name 引用**：`register_object_effects` **4** 条（递归计出现次数，不按卡文件去重）。证据：`data/masters/00003_matou_shinji/00003_matou_shinji.json:377,759`; `data/masters/00004_matou_sakura/00004_matou_sakura.json:834`; `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json:765`。
- **是否涉及时点**：<span style="color:#d00000">🔴 是（时点效果生命周期）：开局发牌、技能觉醒等路径直连登记效果进入 effect_pool，影响之后时点可触发集合。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/game_progress.gd:183` `for rule in card_deal_rules:`
> `scripts/system/global/game_progress.gd:184` `var cards:Array = clone_cards(servant._specials.get(rule["special_key"], []))`
> `scripts/system/global/game_progress.gd:185` `if rule.get("shuffle", false):`
> `scripts/system/global/game_progress.gd:186` `ShuffleArray.new().exec(cards)`
> `scripts/system/global/game_progress.gd:187` `if rule.get("concealed", false):`
> `scripts/system/global/game_progress.gd:188` `for card in cards:`
> `scripts/system/global/game_progress.gd:189` `card.set_concealed(true)`
> `scripts/system/global/game_progress.gd:190` `player_data[rule["area"]] = cards`
> `scripts/system/global/game_progress.gd:191` `#实际发到玩家区域的克隆体才是后续出牌与时点检查的来源。`
> `scripts/system/global/game_progress.gd:192` `for card in cards:`
> `scripts/system/global/game_progress.gd:193` `RegisterObjectEffects.new().exec(card, id)`
> `scripts/system/global/game_progress.gd:194` ``
> `scripts/system/global/game_progress.gd:195` ``
> `scripts/system/operations/AwakenSkill.gd:14` `if last_round >= 0 and GameProgress.current_round > last_round:`
> `scripts/system/operations/AwakenSkill.gd:15` `return false`
> `scripts/system/operations/AwakenSkill.gd:16` `skill._is_awakened = true`
> `scripts/system/operations/AwakenSkill.gd:17` `RegisterObjectEffects.new().exec(skill, id)`
> `scripts/system/operations/AwakenSkill.gd:18` `GameLog.record("skill_awakened", id, -1, "", skill, ["skill_awakened"], {})`
> `scripts/system/operations/AwakenSkill.gd:19` `TimePointChecker.dynamic_time_point([TimePoints.SKILL_AWAKENED], id, skill)`
> `scripts/system/operations/AwakenSkill.gd:20` `return true`
> `scripts/system/operations/RegisterObjectEffects.gd:5` `func exec(object, player_id:int = -1):`
> `scripts/system/operations/RegisterObjectEffects.gd:6` ``
> `scripts/system/operations/RegisterObjectEffects.gd:7` `if object == null or !("_effects" in object):`
> `scripts/system/operations/RegisterObjectEffects.gd:8` `return`
> `scripts/system/operations/RegisterObjectEffects.gd:9` `var id = EffectManager.resolve_player_id(player_id)`
> `scripts/system/operations/RegisterObjectEffects.gd:10` `EffectManager.register_effects(object._effects, id)`
> `scripts/system/global/effect_manager.gd:979` `func register_effect(effect:BaseEffect, player_id:int = -1):`
> `scripts/system/global/effect_manager.gd:980` `if effect == null:`
> `scripts/system/global/effect_manager.gd:981` `return`
> `scripts/system/global/effect_manager.gd:982` `if not _inherit_guard_transaction(effect): return`
> `scripts/system/global/effect_manager.gd:983` `if player_id != -1:`
> `scripts/system/global/effect_manager.gd:984` `effect._trigger_player_id = player_id`
> `scripts/system/global/effect_manager.gd:985` `if !effect_pool.has(effect):`
> `scripts/system/global/effect_manager.gd:986` `effect_pool.append(effect)`
> `scripts/system/global/effect_manager.gd:987` `if player_id != -1:`
> `scripts/system/global/effect_manager.gd:988` `var pl_data = GameDataManager.get_player_data(player_id) as Dictionary`
> `scripts/system/global/effect_manager.gd:989` `var self_effects = pl_data["self_effects"] as Array`
> `scripts/system/global/effect_manager.gd:990` `if !self_effects.has(effect):`
> `scripts/system/global/effect_manager.gd:991` `self_effects.append(effect)`
> `scripts/system/global/effect_manager.gd:992` ``
> `scripts/system/global/effect_manager.gd:993` ``
> `scripts/system/global/effect_manager.gd:994` `func register_effects(effects:Array, player_id:int = -1):`
> `scripts/system/global/effect_manager.gd:995` `for effect in effects:`
> `scripts/system/global/effect_manager.gd:996` `if effect is BaseEffect:`
> `scripts/system/global/effect_manager.gd:997` `register_effect(effect, player_id)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/game_progress.gd:193` | 直接实例调用 | `RegisterObjectEffects.new().exec(card, id)` |
| `scripts/system/global/master_manager.gd:32` | 直接实例调用 | `RegisterObjectEffects.new().exec(card, player_id)` |
| `scripts/system/operations/AwakenSkill.gd:17` | 直接实例调用 | `RegisterObjectEffects.new().exec(skill, id)` |
- **排除区（不计本类生产数）/测试/诊断**：`newtests/action_completion_public_contract_test.gd:70`; `tests/angra_mainyu_test.gd:17`; `tests/artoria_skills_test.gd:40`; `tests/card_audit_probe.gd:242`; `tests/card_history_test.gd:51,68,83,95,96`; `tests/card_keyword_test.gd:158`; `tests/climax_gated_ability_test.gd:77`; `tests/fd39_operations_test.gd:351`; `tests/held_skill_input_test.gd:64`; `tests/local_spell_restore_test.gd:68`; `tests/mana_spend_test.gd:90`; `tests/masters_audit_fix_test.gd:134`; `tests/newspecial_spell_materialization_test.gd:130`; `tests/piercing_cost_test.gd:17`; `tests/private_knowledge_corrosion_test.gd:18`; `tests/reported_activation_test.gd:143,233,289`; `tests/san_no_tachi_test.gd:14`; `tests/san_no_tachi_window_test.gd:62`。
- **排除区（不计本类生产数）/debug**：`scripts/debug/debug_adapters/debug_board_adapter.gd:88`; `scripts/debug/debug_adapters/debug_card_adapter.gd:69,117,134`; `scripts/debug/debug_adapters/debug_identity_adapter.gd:50,92,121,122,160,161,206`。

### A — ReleaseTrueName
- **定义**：`scripts/system/operations/ReleaseTrueName.gd:1`。
- **公开入口**：`scripts/system/operations/ReleaseTrueName.gd:13` `func exec(player_id:int = -1, shown_areas:Array = ["servant_skills", "master_skills", "master._specials.SKILLS", "side.skills", "hand_cards", "played_cards", "deck", "discard"]) -> bool:`; `scripts/system/operations/ReleaseTrueName.gd:58` `static func is_released(player_id:int) -> bool:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:254`，`release_true_name → ReleaseTrueName`，分类 `ACTION`。依据：`"release_true_name" : { "category": ACTION, "class": "ReleaseTrueName", "summary": "真名解放并展示技能牌" },`。
- **正式数据 func_name 引用**：`release_true_name` **3** 条（递归计出现次数，不按卡文件去重）。证据：`data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json:874`; `data/servants/00005_medea/00005_medea.json:255`; `data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json:574`。
- **是否涉及时点**：<span style="color:#d00000">🔴 是：ApplyCardKeywords 直连；翻技能牌，记录事实，再派 TRUE_NAME_RELEASE。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/operations/ApplyCardKeywords.gd:29` `#新增词条时在这里加一个分支，不改任何已有 operation`
> `scripts/system/operations/ApplyCardKeywords.gd:30` `func apply(keyword:String, player_id:int = -1) -> void:`
> `scripts/system/operations/ApplyCardKeywords.gd:31` `player_id = EffectManager.resolve_player_id(player_id)`
> `scripts/system/operations/ApplyCardKeywords.gd:32` `if player_id == -1:`
> `scripts/system/operations/ApplyCardKeywords.gd:33` `return`
> `scripts/system/operations/ApplyCardKeywords.gd:34` `match keyword:`
> `scripts/system/operations/ApplyCardKeywords.gd:35` `TRUE_NAME_RELEASE:`
> `scripts/system/operations/ApplyCardKeywords.gd:36` `#规则：使用带【真名解放】词条的牌后，立即展示从者概览卡与所有技能牌，`
> `scripts/system/operations/ApplyCardKeywords.gd:37` `#并处于【真名解放】状态。已解放时 ReleaseTrueName 自己会跳过，这里不重复判断`
> `scripts/system/operations/ApplyCardKeywords.gd:38` `ReleaseTrueName.new().exec(player_id)`
> `scripts/system/operations/ReleaseTrueName.gd:42` `var card = state.cards[state.index]`
> `scripts/system/operations/ReleaseTrueName.gd:43` `state.index += 1`
> `scripts/system/operations/ReleaseTrueName.gd:44` `if card._is_concealed:`
> `scripts/system/operations/ReleaseTrueName.gd:45` `state.shown_count += 1`
> `scripts/system/operations/ReleaseTrueName.gd:46` `SetCardConcealed.new().exec(card, false, id)`
> `scripts/system/operations/ReleaseTrueName.gd:47` `if EffectManager.defer_until_runtime_guard_complete(Callable(ReleaseTrueName, "_resume_release").bind(state)):`
> `scripts/system/operations/ReleaseTrueName.gd:48` `return`
> `scripts/system/operations/ReleaseTrueName.gd:49` `#日志：谁解放了真名（"本局解放过真名吗"直接查这条事实）。`
> `scripts/system/operations/ReleaseTrueName.gd:50` `#tags用客观时点名，与TimePointChecker记的时点日志口径一致`
> `scripts/system/operations/ReleaseTrueName.gd:51` `GameLog.record("true_name_release", id, -1, "", null, [TimePoints.TRUE_NAME_RELEASE],`
> `scripts/system/operations/ReleaseTrueName.gd:52` `{"shown_count": state.shown_count})`
> `scripts/system/operations/ReleaseTrueName.gd:53` `TimePointChecker.dynamic_time_point([TimePoints.TRUE_NAME_RELEASE], id)`
> `scripts/system/operations/ReleaseTrueName.gd:54` ``
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/game_scene/battle_board_v2.gd:2542` | 类/静态公开入口 | `or (entry.card is BaseSkill and not ReleaseTrueName.is_released(_local_player_id)))` |
| `scripts/game_scene/tactical_board_ui.gd:4339` | 类/静态公开入口 | `var released := ReleaseTrueName.is_released(player_id)` |
| `scripts/game_scene/tactical_board_ui.gd:4391` | 类/静态公开入口 | `var revealed := ReleaseTrueName.is_released(bot_id)` |
| `scripts/match/view_builder.gd:38` | 类/静态公开入口 | `var released: bool = ReleaseTrueName.is_released(pid)` |
| `scripts/match/view_builder.gd:202` | 类/静态公开入口 | `result.append({"card": view, "group": origin.group if played.has(card) else group, "label": origin.label if played.has(card) else label, "played": played.has(card), "unpublished": bool(card._is_concealed) or (card is BaseSkill and not ReleaseTrueName.is_released(pid))})` |
| `scripts/match/view_builder.gd:391` | 类/静态公开入口 | `return ReleaseTrueName.is_released(pid)` |
| `scripts/system/global/game_data_manager.gd:20` | 类/静态公开入口 | `return ReleaseTrueName.is_released(target_id) or knows_servant_info(observer_id, target_id)` |
| `scripts/system/operations/ApplyCardKeywords.gd:38` | 直接实例调用 | `ReleaseTrueName.new().exec(player_id)` |
| `scripts/system/operations/HideTrueName.gd:16` | 类/静态公开入口 | `if !ReleaseTrueName.is_released(id):` |
| `scripts/system/operations/IsTrueNameReleased.gd:7` | 类/静态公开入口 | `return ReleaseTrueName.is_released(EffectManager.resolve_player_id(player_id))` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/_probe_conceal_click.gd:59,82`; `tests/angra_mainyu_window_test.gd:69`; `tests/board_requested_ui_test.gd:85`; `tests/card_audit_probe.gd:245`; `tests/card_effect_runtime_test.gd:143,152,160,172`; `tests/card_history_test.gd:55,101,107,109,110,111`; `tests/card_keyword_test.gd:81,85,93,105,127,134,161`; `tests/masters_audit_fix_test.gd:89`; `tests/match_view_test.gd:28`; `tests/opponent_drawer_test.gd:177`; `tests/overseer_knowledge_test.gd:19,20`; `tests/overseer_window_test.gd:26`; `tests/reported_activation_test.gd:323,328,337`; `tests/reported_ui_test.gd:182,190,427,428`; `tests/rule_guard_true_name_test.gd:29,33`。
- **排除区（不计本类生产数）/debug**：`scripts/debug/debug_adapters/debug_identity_adapter.gd:154,341`; `scripts/debug/debug_adapters/debug_map_adapter.gd:129,130,136`; `scripts/debug/debug_adapters/debug_player_adapter.gd:32`。

### A — RemoveFromBoard
- **定义**：`scripts/system/operations/RemoveFromBoard.gd:1`。
- **公开入口**：`scripts/system/operations/RemoveFromBoard.gd:9` `func exec(player_id:int = -1) -> bool:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:205`，`remove_from_board → RemoveFromBoard`，分类 `EDIT_MAP`。依据：`"remove_from_board" : { "category": EDIT_MAP, "class": "RemoveFromBoard", "summary": "把御主移出版图(回合结束)" },`。
- **正式数据 func_name 引用**：`remove_from_board` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：<span style="color:#d00000">🔴 是：end_round / 高潮淘汰直连；移走棋子并派 LEAVE_LOCATION。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/game_progress.gd:340` `player_data["last_turn_location"] = player_data["location"]`
> `scripts/system/global/game_progress.gd:341` `player_data["is_battle"] = false`
> `scripts/system/global/game_progress.gd:342` `#规则：回合结束时将每名御主的立牌移除版图（下回合前哨阶段重新部署）。`
> `scripts/system/global/game_progress.gd:343` `#必须在记完 last_turn_location 之后调用，否则查不到本回合结束时的位置`
> `scripts/system/global/game_progress.gd:344` `RemoveFromBoard.new().exec(id)`
> `scripts/system/global/game_progress.gd:345` `#残留牌留在场上，回合结束不处理（残留牌只在自身效果满足条件时自行关闭）`
> `scripts/system/global/game_progress.gd:346` `DiscardPlayedCards.new().exec(id)`
> `scripts/system/global/climax_resolver.gd:49` `#带上当时的战果：事后核对"为什么是他被淘汰"不必再翻别的记录`
> `scripts/system/global/climax_resolver.gd:50` `var score:int = (player_data["score"] as BaseNumber).number`
> `scripts/system/global/climax_resolver.gd:51` `GameLog.record("eliminated", player_id, -1, "", null, ["eliminated"], {"score": score})`
> `scripts/system/global/climax_resolver.gd:52` `#被淘汰的玩家离开版图：只置is_out不摘席位，他仍会占着位置、也仍显示在战区上。`
> `scripts/system/global/climax_resolver.gd:53` `#复用回合结束用的同一个原语，不在这里另写一套摘除逻辑`
> `scripts/system/global/climax_resolver.gd:54` `RemoveFromBoard.new().exec(player_id)`
> `scripts/system/global/climax_resolver.gd:55` `#提示全员：谁被淘汰了。文案由显示名接口生成，不按id编号示人`
> `scripts/system/global/climax_resolver.gd:56` `var shown:String = EffectManager.player_shown_name(player_id)`
> `scripts/system/global/climax_resolver.gd:57` `EffectManager.push_message("%s 被淘汰，战果 %d" % [shown, score])`
> `scripts/system/global/climax_resolver.gd:58` `TimePointChecker.dynamic_time_point([TimePoints.ELIMINATED], player_id)`
> `scripts/system/operations/RemoveFromBoard.gd:20` `GameLog.record("leave_board", player_id, -1,`
> `scripts/system/operations/RemoveFromBoard.gd:21` `str(area._area_name) if area != null else "", loc, ["leave_board"], {})`
> `scripts/system/operations/RemoveFromBoard.gd:22` `TimePointChecker.dynamic_time_point([TimePoints.LEAVE_LOCATION], player_id, loc)`
> `scripts/system/operations/RemoveFromBoard.gd:23` `return true`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/climax_resolver.gd:54` | 直接实例调用 | `RemoveFromBoard.new().exec(player_id)` |
| `scripts/system/global/game_progress.gd:344` | 直接实例调用 | `RemoveFromBoard.new().exec(id)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/angra_fang_window_test.gd:24`; `tests/angra_mainyu_test.gd:66,72`; `tests/bellerophon_edges_test.gd:32,40`; `tests/bellerophon_rules_test.gd:100,103`; `tests/bellerophon_window_test.gd:62`; `tests/debug_console_test.gd:119`; `tests/fd39_operations_test.gd:217,450,485,488,495,587`; `tests/outpost_identity_test.gd:59`; `tests/prepare_phase_test.gd:44,47`; `tests/twelve_labors_lifecycle_test.gd:55`。
- **排除区（不计本类生产数）/debug**：`scripts/debug/debug_adapters/debug_map_adapter.gd:84`。

### A — ReshuffleDiscard
- **定义**：`scripts/system/operations/ReshuffleDiscard.gd:1`。
- **公开入口**：`scripts/system/operations/ReshuffleDiscard.gd:8` `func exec(player_id:int = -1) -> bool:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:215`，`reshuffle_discard → ReshuffleDiscard`，分类 `TRANSFER`。依据：`"reshuffle_discard" : { "category": TRANSFER, "class": "ReshuffleDiscard", "summary": "牌堆耗尽时把弃牌堆洗成新牌堆" },`。
- **正式数据 func_name 引用**：`reshuffle_discard` **4** 条（递归计出现次数，不按卡文件去重）。证据：`data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json:771,1148`; `data/servants/00004_medusa/00004_medusa.json:97`; `data/servants/00008_angra_mainyu/00008_angra_mainyu.json:164`。
- **是否涉及时点**：<span style="color:#d00000">🔴 是：RefillHand 直接洗牌后派 DECK_RESHUFFLED。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/operations/RefillHand.gd:30` `if state.hand.size() >= state.target:`
> `scripts/system/operations/RefillHand.gd:31` `break`
> `scripts/system/operations/RefillHand.gd:32` `if not EffectManager.runtime_guard_checkpoint(state):`
> `scripts/system/operations/RefillHand.gd:33` `return`
> `scripts/system/operations/RefillHand.gd:34` `if state.data.deck.is_empty() and not ReshuffleDiscard.new().exec(state.player):`
> `scripts/system/operations/RefillHand.gd:35` `break`
> `scripts/system/operations/RefillHand.gd:36` `state["before"] = state.hand.size()`
> `scripts/system/operations/RefillHand.gd:37` `state.phase = "after_draw"`
> `scripts/system/operations/RefillHand.gd:38` `DrawCardFromPlDeckToHand.new().exec(0, state.player)`
> `scripts/system/operations/RefillHand.gd:39` `if EffectManager.defer_until_runtime_guard_complete(Callable(RefillHand, "_resume_refill").bind(state)):`
> `scripts/system/operations/ReshuffleDiscard.gd:19` `deck.append_array(discard)`
> `scripts/system/operations/ReshuffleDiscard.gd:20` `discard.clear()`
> `scripts/system/operations/ReshuffleDiscard.gd:21` `ShuffleArray.new().exec(deck)`
> `scripts/system/operations/ReshuffleDiscard.gd:22` `#日志：牌堆抽空后把弃牌堆洗回（供"这局洗过几次"这类历史查询）`
> `scripts/system/operations/ReshuffleDiscard.gd:23` `GameLog.record("reshuffle_discard", player_id, -1, "", null, ["reshuffle_discard"],`
> `scripts/system/operations/ReshuffleDiscard.gd:24` `{"count": count})`
> `scripts/system/operations/ReshuffleDiscard.gd:25` `#提示当事玩家：牌堆抽干了、弃牌堆已洗回。只给他看，别人不需要知道`
> `scripts/system/operations/ReshuffleDiscard.gd:26` `EffectManager.push_message("牌库已抽空，弃牌堆 %d 张洗混作为新牌库" % count, player_id)`
> `scripts/system/operations/ReshuffleDiscard.gd:27` `TimePointChecker.dynamic_time_point([TimePoints.DECK_RESHUFFLED], player_id)`
> `scripts/system/operations/ReshuffleDiscard.gd:28` `return true`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/operations/RefillHand.gd:34` | 直接实例调用 | `if state.data.deck.is_empty() and not ReshuffleDiscard.new().exec(state.player):` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/prepare_phase_test.gd:36`。
- **排除区（不计本类生产数）/debug**：`scripts/debug/debug_adapters/debug_card_adapter.gd:146`。

### A — RestoreLocationBenefits
- **定义**：`scripts/system/operations/RestoreLocationBenefits.gd:1`。
- **公开入口**：`scripts/system/operations/RestoreLocationBenefits.gd:11` `func exec() -> int:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:210`，`restore_location_benefits → RestoreLocationBenefits`，分类 `EDIT_MAP`。依据：`"restore_location_benefits" : { "category": EDIT_MAP, "class": "RestoreLocationBenefits", "summary": "按基线还原地点地利" },`。
- **正式数据 func_name 引用**：`restore_location_benefits` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：<span style="color:#d00000">🔴 是（回合时点副作用）：end_round 先派 DAY_END，随后执行本项清理/重置/轮转；不是本类额外派 DAY_END。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/game_progress.gd:311` `func end_round():`
> `scripts/system/global/game_progress.gd:312` `if _round_end_running:`
> `scripts/system/global/game_progress.gd:313` `return`
> `scripts/system/global/game_progress.gd:314` `_round_end_running = true`
> `scripts/system/global/game_progress.gd:315` `current_phase_index = -1`
> `scripts/system/global/game_progress.gd:316` `current_phase_player_index = 0`
> `scripts/system/global/game_progress.gd:317` `current_player_id = -1`
> `scripts/system/global/game_progress.gd:318` `TimePointChecker.set_phase_time_points([TimePoints.DAY])`
> `scripts/system/global/game_progress.gd:319` `TimePointChecker.global_time_point([TimePoints.DAY_END])`
> `scripts/system/global/game_progress.gd:320` `if not await _wait_round_choices():`
> `scripts/system/global/game_progress.gd:321` `return`
> `scripts/system/global/game_progress.gd:322` `if climax_keep_counts.has(current_round):`
> `scripts/system/global/game_progress.gd:323` `TimePointChecker.global_time_point([TimePoints.CLIMAX_START])`
> `scripts/system/global/game_progress.gd:324` `if not await _wait_round_choices():`
> `scripts/system/global/game_progress.gd:325` `return`
> `scripts/system/global/game_progress.gd:326` `ClimaxResolver.new().exec(climax_keep_counts[current_round])`
> `scripts/system/global/game_progress.gd:356` `EventResolver.new().clear_all()`
> `scripts/system/global/game_progress.gd:357` `#地利修正类效果（远隔操作地利翻倍、占领高地、卫宫地利变3倍）只在本回合有效：`
> `scripts/system/global/game_progress.gd:358` `#把各席位的地利按印刷基线还原，否则同一席位的地利会跨回合越乘越大，`
> `scripts/system/global/game_progress.gd:359` `#而且改的是共享地图数据，会连带影响之后占据该席位的其他玩家`
> `scripts/system/global/game_progress.gd:360` `RestoreLocationBenefits.new().exec()`
> `scripts/system/global/game_progress.gd:361` `#规则：每个回合结束时，将回合顺位顺时针后移一位（原第二位成为新回合首位）`
> `scripts/system/global/game_progress.gd:362` `ChangePlOrder.new().exec(null, BaseNumber.new(-1))`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/game_progress.gd:360` | 直接实例调用 | `RestoreLocationBenefits.new().exec()` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/bellerophon_rules_test.gd:24`; `tests/location_benefit_test.gd:22,54,64,78`; `tests/misc_rules_fix_test.gd:27`。
- **排除区（不计本类生产数）/debug**：无。

### A — RestoreLocationPlNumLimits
- **定义**：`scripts/system/operations/RestoreLocationPlNumLimits.gd:1`。
- **公开入口**：`scripts/system/operations/RestoreLocationPlNumLimits.gd:7` `func exec():`。
- **注册表**：有；`scripts/system/global/all_operations.gd:209`，`restore_location_pl_num_limits → RestoreLocationPlNumLimits`，分类 `EDIT_MAP`。依据：`"restore_location_pl_num_limits" : { "category": EDIT_MAP, "class": "RestoreLocationPlNumLimits", "summary": "按基线还原地点席位上限" },`。
- **正式数据 func_name 引用**：`restore_location_pl_num_limits` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：<span style="color:#d00000">🔴 是（DAY_END 后局势退场的还原副作用）：SituationResolver.clear_all 直连恢复临时场地规则。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/game_progress.gd:318` `TimePointChecker.set_phase_time_points([TimePoints.DAY])`
> `scripts/system/global/game_progress.gd:319` `TimePointChecker.global_time_point([TimePoints.DAY_END])`
> `scripts/system/global/game_progress.gd:353` `DefeatBuff.clear_all()`
> `scripts/system/global/game_progress.gd:354` `#规则：回合结束时弃置所有激活的局势牌和事件牌`
> `scripts/system/global/game_progress.gd:355` `SituationResolver.new().clear_all()`
> `scripts/system/global/game_progress.gd:356` `EventResolver.new().clear_all()`
> `scripts/system/global/situation_resolver.gd:54` `#回合结束：弃置激活的局势牌`
> `scripts/system/global/situation_resolver.gd:55` `func clear_all():`
> `scripts/system/global/situation_resolver.gd:56` `var situation = MapData.active_situation`
> `scripts/system/global/situation_resolver.gd:57` `if situation == null:`
> `scripts/system/global/situation_resolver.gd:58` `return`
> `scripts/system/global/situation_resolver.gd:59` `UnregisterObjectEffects.new().exec(situation)`
> `scripts/system/global/situation_resolver.gd:60` `#移入局势牌弃牌区而不是销毁：玩家要能回看本局展示过哪些局势牌。`
> `scripts/system/global/situation_resolver.gd:61` `#弃牌区在每局开始时统一销毁并清空`
> `scripts/system/global/situation_resolver.gd:62` `MapData.situation_discard.append(situation)`
> `scripts/system/global/situation_resolver.gd:63` `MapData.active_situation = null`
> `scripts/system/global/situation_resolver.gd:64` `#封区类局势牌(如身处地狱之门)只在本回合有效：弃置时把被改动的`
> `scripts/system/global/situation_resolver.gd:65` `#战区"能否常规进入"按印刷基线还原，防止一回合的封区永久生效`
> `scripts/system/global/situation_resolver.gd:66` `RestoreMapAreaMoveFlags.new().exec()`
> `scripts/system/global/situation_resolver.gd:67` `#限员类局势牌(如"魔术工房仅限一人部署")同理：弃置时还原席位人数基线`
> `scripts/system/global/situation_resolver.gd:68` `RestoreLocationPlNumLimits.new().exec()`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/situation_resolver.gd:68` | 直接实例调用 | `RestoreLocationPlNumLimits.new().exec()` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/deploy_rules_layer_test.gd:56`。
- **排除区（不计本类生产数）/debug**：无。

### A — RestoreMapAreaMoveFlags
- **定义**：`scripts/system/operations/RestoreMapAreaMoveFlags.gd:1`。
- **公开入口**：`scripts/system/operations/RestoreMapAreaMoveFlags.gd:7` `func exec():`。
- **注册表**：有；`scripts/system/global/all_operations.gd:207`，`restore_map_area_move_flags → RestoreMapAreaMoveFlags`，分类 `EDIT_MAP`。依据：`"restore_map_area_move_flags" : { "category": EDIT_MAP, "class": "RestoreMapAreaMoveFlags", "summary": "按基线还原区域进入开关" },`。
- **正式数据 func_name 引用**：`restore_map_area_move_flags` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：<span style="color:#d00000">🔴 是（DAY_END 后局势退场的还原副作用）：SituationResolver.clear_all 直连恢复临时场地规则。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/game_progress.gd:318` `TimePointChecker.set_phase_time_points([TimePoints.DAY])`
> `scripts/system/global/game_progress.gd:319` `TimePointChecker.global_time_point([TimePoints.DAY_END])`
> `scripts/system/global/game_progress.gd:353` `DefeatBuff.clear_all()`
> `scripts/system/global/game_progress.gd:354` `#规则：回合结束时弃置所有激活的局势牌和事件牌`
> `scripts/system/global/game_progress.gd:355` `SituationResolver.new().clear_all()`
> `scripts/system/global/game_progress.gd:356` `EventResolver.new().clear_all()`
> `scripts/system/global/situation_resolver.gd:54` `#回合结束：弃置激活的局势牌`
> `scripts/system/global/situation_resolver.gd:55` `func clear_all():`
> `scripts/system/global/situation_resolver.gd:56` `var situation = MapData.active_situation`
> `scripts/system/global/situation_resolver.gd:57` `if situation == null:`
> `scripts/system/global/situation_resolver.gd:58` `return`
> `scripts/system/global/situation_resolver.gd:59` `UnregisterObjectEffects.new().exec(situation)`
> `scripts/system/global/situation_resolver.gd:60` `#移入局势牌弃牌区而不是销毁：玩家要能回看本局展示过哪些局势牌。`
> `scripts/system/global/situation_resolver.gd:61` `#弃牌区在每局开始时统一销毁并清空`
> `scripts/system/global/situation_resolver.gd:62` `MapData.situation_discard.append(situation)`
> `scripts/system/global/situation_resolver.gd:63` `MapData.active_situation = null`
> `scripts/system/global/situation_resolver.gd:64` `#封区类局势牌(如身处地狱之门)只在本回合有效：弃置时把被改动的`
> `scripts/system/global/situation_resolver.gd:65` `#战区"能否常规进入"按印刷基线还原，防止一回合的封区永久生效`
> `scripts/system/global/situation_resolver.gd:66` `RestoreMapAreaMoveFlags.new().exec()`
> `scripts/system/global/situation_resolver.gd:67` `#限员类局势牌(如"魔术工房仅限一人部署")同理：弃置时还原席位人数基线`
> `scripts/system/global/situation_resolver.gd:68` `RestoreLocationPlNumLimits.new().exec()`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/situation_resolver.gd:66` | 直接实例调用 | `RestoreMapAreaMoveFlags.new().exec()` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### A — SetCardConcealed
- **定义**：`scripts/system/operations/SetCardConcealed.gd:1`。
- **公开入口**：`scripts/system/operations/SetCardConcealed.gd:9` `func exec(card:BaseCard, concealed:bool, player_id:int = -1):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:191`，`set_card_concealed → SetCardConcealed`，分类 `EDIT_CARD`。依据：`"set_card_concealed" : { "category": EDIT_CARD, "class": "SetCardConcealed", "summary": "明暗置并同步威力" },`。
- **正式数据 func_name 引用**：`set_card_concealed` **1** 条（递归计出现次数，不按卡文件去重）。证据：`data/servants/00008_angra_mainyu/00008_angra_mainyu.json:483`。
- **是否涉及时点**：<span style="color:#d00000">🔴 是：翻明的直接调用可经 card_revealed 发亮出时点；事件分支由 EventResolver 登记后发出，不重复派。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/event_resolver.gd:62` `var event = area._events[state.event_index]`
> `scripts/system/global/event_resolver.gd:63` `state.event_index += 1`
> `scripts/system/global/event_resolver.gd:64` `if event is BaseEvent and event._is_concealed:`
> `scripts/system/global/event_resolver.gd:65` `SetCardConcealed.new().exec(event, false)`
> `scripts/system/global/event_resolver.gd:66` `state.count += 1`
> `scripts/system/global/event_resolver.gd:67` `EventResolver.new().register_entered(event)`
> `scripts/system/global/event_resolver.gd:68` `if EffectManager.defer_until_runtime_guard_complete(Callable(EventResolver, "_resume_reveal").bind(state)):`
> `scripts/system/operations/ReleaseTrueName.gd:42` `var card = state.cards[state.index]`
> `scripts/system/operations/ReleaseTrueName.gd:43` `state.index += 1`
> `scripts/system/operations/ReleaseTrueName.gd:44` `if card._is_concealed:`
> `scripts/system/operations/ReleaseTrueName.gd:45` `state.shown_count += 1`
> `scripts/system/operations/ReleaseTrueName.gd:46` `SetCardConcealed.new().exec(card, false, id)`
> `scripts/system/operations/ReleaseTrueName.gd:47` `if EffectManager.defer_until_runtime_guard_complete(Callable(ReleaseTrueName, "_resume_release").bind(state)):`
> `scripts/system/operations/SetCardConcealed.gd:12` ``
> `scripts/system/operations/SetCardConcealed.gd:13` `if !(card is BaseHandCard):`
> `scripts/system/operations/SetCardConcealed.gd:14` `card.set_concealed(concealed)`
> `scripts/system/operations/SetCardConcealed.gd:15` `return`
> `scripts/system/operations/SetCardConcealed.gd:16` ``
> `scripts/system/operations/SetCardConcealed.gd:29` `pl_power.add(handcard._power)`
> `scripts/system/operations/SetCardConcealed.gd:30` `else:`
> `scripts/system/operations/SetCardConcealed.gd:31` `pl_power.minus(handcard._power)`
> `scripts/system/operations/SetCardConcealed.gd:32` `#其他手牌翻明时也属于卡牌亮出；事件牌由 EventResolver 在登记效果后统一派发，避免漏触发`
> `scripts/system/operations/SetCardConcealed.gd:33` `if not concealed and not (card is BaseEvent):`
> `scripts/system/operations/SetCardConcealed.gd:34` `TimePointChecker.card_revealed(card)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/match/match_commands.gd:12` | 直接实例调用 | `SetCardConcealed.new().exec(card, concealed, player_id)` |
| `scripts/system/global/event_resolver.gd:65` | 直接实例调用 | `SetCardConcealed.new().exec(event, false)` |
| `scripts/system/operations/AddEventFromDeck.gd:34` | 直接实例调用 | `SetCardConcealed.new().exec(event, state.concealed)` |
| `scripts/system/operations/CloseCard.gd:29` | 直接实例调用 | `SetCardConcealed.new().exec(card, true, id)` |
| `scripts/system/operations/DiscardPlayedCards.gd:22` | 直接实例调用 | `SetCardConcealed.new().exec(card, false, id)` |
| `scripts/system/operations/DiscardPlayedCards.gd:28` | 直接实例调用 | `SetCardConcealed.new().exec(card, true, id)` |
| `scripts/system/operations/HideTrueName.gd:34` | 直接实例调用 | `SetCardConcealed.new().exec(card, true, id)` |
| `scripts/system/operations/ReleaseTrueName.gd:46` | 直接实例调用 | `SetCardConcealed.new().exec(card, false, id)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/_probe_conceal_click.gd:92`; `tests/current_skill_group_test.gd:106`。
- **排除区（不计本类生产数）/debug**：`scripts/debug/debug_adapters/debug_card_adapter.gd:223`。

### A — SetLocation
- **定义**：`scripts/system/operations/SetLocation.gd:1`。
- **公开入口**：`scripts/system/operations/SetLocation.gd:14` `func exec(setted_location:BaseLocation, player_id:int = -1, is_move:bool = true, ignore_limit:bool = false, check_area_lock:bool = true) -> bool:`; `scripts/system/operations/SetLocation.gd:71` `static func area_locked(area:BaseMapArea) -> bool:`; `scripts/system/operations/SetLocation.gd:79` `static func locked_area_for_move(player_id:int, target_area:BaseMapArea) -> BaseMapArea:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:204`，`set_location → SetLocation`，分类 `EDIT_MAP`。依据：`"set_location" : { "category": EDIT_MAP, "class": "SetLocation", "summary": "设置玩家地点" },`。
- **正式数据 func_name 引用**：`set_location` **5** 条（递归计出现次数，不按卡文件去重）。证据：`data/command_spells/normal_command_spell.json:98`; `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json:715`; `data/servants/00003_cu_chulainn/00003_cu_chulainn.json:69`; `data/servants/00004_medusa/00004_medusa.json:268,553`。
- **是否涉及时点**：<span style="color:#d00000">🔴 是：Deploy/MoveLocation 直连；落位写事实后发 LEAVE_LOCATION/ENTER_LOCATION。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/operations/Deploy.gd:7` `func exec(deploy_location:BaseLocation, player_id:int = -1, ignore_limit:bool = false):`
> `scripts/system/operations/Deploy.gd:8` ``
> `scripts/system/operations/Deploy.gd:9` `player_id = EffectManager.resolve_player_id(player_id)`
> `scripts/system/operations/Deploy.gd:10` `var settled:bool = SetLocation.new().exec(deploy_location, player_id, false, ignore_limit, false)`
> `scripts/system/operations/Deploy.gd:11` `#部署是独立的规则动作，由入口自己记一条；SetLocation 只记中性的位置变化，`
> `scripts/system/operations/Deploy.gd:12` `#它分不清"部署"和"效果搬运"。只在真正落位后才记，落位失败（位置满）不记`
> `scripts/system/operations/Deploy.gd:13` `if settled:`
> `scripts/system/operations/Deploy.gd:14` `var area := deploy_location.get_from() as BaseMapArea`
> `scripts/system/operations/Deploy.gd:15` `GameLog.record("deploy", player_id, -1,`
> `scripts/system/operations/Deploy.gd:16` `str(area._area_name) if area != null else "", deploy_location, ["deploy"], {})`
> `scripts/system/operations/MoveLocation.gd:68` `EffectManager.push_message("魔力不足，无法移动", player_id)`
> `scripts/system/operations/MoveLocation.gd:69` `return null`
> `scripts/system/operations/MoveLocation.gd:70` `if !SetLocation.new().exec(target_location, player_id, true, ignore_limit):`
> `scripts/system/operations/MoveLocation.gd:71` `EffectManager.push_message("无法在【%s】落位" % area._area_name, player_id)`
> `scripts/system/operations/MoveLocation.gd:72` `return null`
> `scripts/system/operations/MoveLocation.gd:73` ``
> `scripts/system/operations/MoveLocation.gd:74` `return total_cost`
> `scripts/system/operations/SetLocation.gd:54` `GameLog.record("move", player_id, -1,`
> `scripts/system/operations/SetLocation.gd:55` `str(area._area_name) if area != null else "", null,`
> `scripts/system/operations/SetLocation.gd:56` `["move"], {"is_move": is_move, "from_area": old_area_name})`
> `scripts/system/operations/SetLocation.gd:57` `#进入/离开地点是比常规移动更宽的事实（部署、效果搬运都算），带落点/旧位置作来源派发`
> `scripts/system/operations/SetLocation.gd:58` `if old_location != setted_location:`
> `scripts/system/operations/SetLocation.gd:59` `if old_location != null:`
> `scripts/system/operations/SetLocation.gd:60` `TimePointChecker.dynamic_time_point([TimePoints.LEAVE_LOCATION], player_id, old_location)`
> `scripts/system/operations/SetLocation.gd:61` `TimePointChecker.dynamic_time_point([TimePoints.ENTER_LOCATION], player_id, setted_location)`
> `scripts/system/operations/SetLocation.gd:62` `return true`
> `scripts/system/operations/SetLocation.gd:63` ``
> `scripts/system/operations/SetLocation.gd:64` ``
> `scripts/system/operations/SetLocation.gd:65` `#战区锁的效果名（如固有结界的"不能移动至此也不能离开"）。`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/area_action_rules.gd:108` | 类/静态公开入口 | `var locked: BaseMapArea = SetLocation.locked_area_for_move(player_id, target_area)` |
| `scripts/system/area_action_rules.gd:129` | 类/静态公开入口 | `if SetLocation.area_locked(area):` |
| `scripts/system/global/effect_manager.gd:817` | 类/静态公开入口 | `if SetLocation.area_locked(area):` |
| `scripts/system/global/effect_manager.gd:1889` | 类/静态公开入口 | `if SetLocation.locked_area_for_move(effect._trigger_player_id, target_area) != null:` |
| `scripts/system/operations/Deploy.gd:10` | 直接实例调用 | `var settled:bool = SetLocation.new().exec(deploy_location, player_id, false, ignore_limit, false)` |
| `scripts/system/operations/MoveLocation.gd:51` | 类/静态公开入口 | `var locked:BaseMapArea = SetLocation.locked_area_for_move(player_id, area)` |
| `scripts/system/operations/MoveLocation.gd:70` | 直接实例调用 | `if !SetLocation.new().exec(target_location, player_id, true, ignore_limit):` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/_probe_broadcast.gd:30,35`; `tests/_probe_conceal.gd:62`; `tests/_probe_conceal_click.gd:99`; `tests/_probe_head_fade.gd:79,97,125`; `tests/area_lock_window_test.gd:39`; `tests/artoria_skills_test.gd:81,82`; `tests/avatar_parallel_test.gd:39`; `tests/battle_broadcast_test.gd:90`; `tests/battle_play_groups_test.gd:50,258`; `tests/battle_score_report_test.gd:65`; `tests/battle_scroll_test.gd:171`; `tests/bellerophon_composition_test.gd:45,53`; `tests/bellerophon_edges_test.gd:3,9,21,22,26,34,41,53,65`; `tests/bellerophon_rules_test.gd:65,91,101,110`; `tests/bellerophon_window_test.gd:25,65`; `tests/broadcast_absent_confirmation_test.gd:39`; `tests/broadcast_authority_test.gd:30`; `tests/broadcast_command_dispatch_test.gd:44`; `tests/broadcast_policy_boundary_test.gd:23`; `tests/broadcast_worker_capability_test.gd:42`; `tests/card_audit_probe.gd:106`; `tests/card_effect_runtime_test.gd:41`; `tests/command_spell_test.gd:80`; `tests/debug_console_test.gd:85,88,98,117`; `tests/deploy_rules_test.gd:58,61`; `tests/effect_body_fill2_test.gd:72,83`; `tests/effect_body_fill_test.gd:89`; `tests/effect_execution_input_contract_test.gd:37,52,82`; `tests/engagement_test.gd:97,98,105,109,131,132`; `tests/fd39_operations_test.gd:215,216,449,486,491,581,583,585`; `tests/ichi_no_tachi_test.gd:47`; `tests/location_benefit_test.gd:61`; `tests/mana_spend_test.gd:94`; `tests/masters_audit_fix_test.gd:25,26`; `tests/misc_rules_fix_test.gd:105,109,119,120,132,135,136,140,142,143,145,147,148,150,173,187,195,201,207,213,234,245,246`; `tests/ni_no_tachi_test.gd:39`; `tests/opponent_drawer_test.gd:37`; `tests/post_battle_choice_test.gd:55`; `tests/refactor_area_golden_test.gd:81,93`; `tests/surveil_window_test.gd:37,38`; `tests/switch_performance_test.gd:17`; `tests/takeoff_refresh_test.gd:49`; `tests/zoom_and_desc_test.gd:181`。
- **排除区（不计本类生产数）/debug**：`scripts/debug/debug_adapters/debug_map_adapter.gd:74`。

### A — SyncPower
- **定义**：`scripts/system/operations/SyncPower.gd:1`。
- **公开入口**：`scripts/system/operations/SyncPower.gd:7` `func exec(player_id:int = -1):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:184`，`sync_power → SyncPower`，分类 `EDIT_PLAYER`。依据：`"sync_power" : { "category": EDIT_PLAYER, "class": "SyncPower", "summary": "按场上牌重建合计威力" },`。
- **正式数据 func_name 引用**：`sync_power` **1** 条（递归计出现次数，不按卡文件去重）。证据：`data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json:714`。
- **是否涉及时点**：<span style="color:#d00000">🔴 是（回合时点副作用）：end_round 先派 DAY_END，随后执行本项清理/重置/轮转；不是本类额外派 DAY_END。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/game_progress.gd:311` `func end_round():`
> `scripts/system/global/game_progress.gd:312` `if _round_end_running:`
> `scripts/system/global/game_progress.gd:313` `return`
> `scripts/system/global/game_progress.gd:314` `_round_end_running = true`
> `scripts/system/global/game_progress.gd:315` `current_phase_index = -1`
> `scripts/system/global/game_progress.gd:316` `current_phase_player_index = 0`
> `scripts/system/global/game_progress.gd:317` `current_player_id = -1`
> `scripts/system/global/game_progress.gd:318` `TimePointChecker.set_phase_time_points([TimePoints.DAY])`
> `scripts/system/global/game_progress.gd:319` `TimePointChecker.global_time_point([TimePoints.DAY_END])`
> `scripts/system/global/game_progress.gd:320` `if not await _wait_round_choices():`
> `scripts/system/global/game_progress.gd:321` `return`
> `scripts/system/global/game_progress.gd:322` `if climax_keep_counts.has(current_round):`
> `scripts/system/global/game_progress.gd:323` `TimePointChecker.global_time_point([TimePoints.CLIMAX_START])`
> `scripts/system/global/game_progress.gd:324` `if not await _wait_round_choices():`
> `scripts/system/global/game_progress.gd:325` `return`
> `scripts/system/global/game_progress.gd:326` `ClimaxResolver.new().exec(climax_keep_counts[current_round])`
> `scripts/system/global/game_progress.gd:345` `#残留牌留在场上，回合结束不处理（残留牌只在自身效果满足条件时自行关闭）`
> `scripts/system/global/game_progress.gd:346` `DiscardPlayedCards.new().exec(id)`
> `scripts/system/global/game_progress.gd:347` `#先清理再重建合计威力基线：规则上残留牌跨回合留场并继续提供威力，`
> `scripts/system/global/game_progress.gd:348` `#所以基线是留场明置牌的威力之和，同时丢弃回合内的非卡牌来源加成`
> `scripts/system/global/game_progress.gd:349` `SyncPower.new().exec(id)`
> `scripts/system/global/game_progress.gd:350` `#规则：合计威力加成只在本回合有效，回合一结束就归零`
> `scripts/system/global/game_progress.gd:351` `(player_data["total_power_bonus"] as BaseNumber).set_num(BaseNumber.new(0))`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/game_progress.gd:349` | 直接实例调用 | `SyncPower.new().exec(id)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/artoria_skills_test.gd:87,92,114`; `tests/debug_identity_hand_test.gd:104`; `tests/twelve_labors_lifecycle_test.gd:54`。
- **排除区（不计本类生产数）/debug**：`scripts/debug/debug_adapters/debug_card_adapter.gd:71,73,136`; `scripts/debug/debug_adapters/debug_identity_adapter.gd:181`; `scripts/debug/debug_adapters/debug_player_adapter.gd:88`。

### A — UnregisterObjectEffects
- **定义**：`scripts/system/operations/UnregisterObjectEffects.gd:1`。
- **公开入口**：`scripts/system/operations/UnregisterObjectEffects.gd:5` `func exec(object):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:240`，`unregister_object_effects → UnregisterObjectEffects`，分类 `EFFECT`。依据：`"unregister_object_effects" : { "category": EFFECT, "class": "UnregisterObjectEffects", "summary": "取消登记对象上的效果" },`。
- **正式数据 func_name 引用**：`unregister_object_effects` **8** 条（递归计出现次数，不按卡文件去重）。证据：`data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json:387,1377`; `data/masters/00003_matou_shinji/00003_matou_shinji.json:352,734`; `data/masters/00004_matou_sakura/00004_matou_sakura.json:827`; `data/servants/00007_heracles/00007_heracles.json:233,531,829`。
- **是否涉及时点**：<span style="color:#d00000">🔴 是（时点效果生命周期）：事件/局势退场直连；删除效果池和 matched_time_points 等等待结算状态。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/event_resolver.gd:85` `func clear_all():`
> `scripts/system/global/event_resolver.gd:86` `for area:BaseMapArea in MapData.areas:`
> `scripts/system/global/event_resolver.gd:87` `var events:Array = area._events`
> `scripts/system/global/event_resolver.gd:88` `for i in range(events.size() - 1, -1, -1):`
> `scripts/system/global/event_resolver.gd:89` `var event = events[i]`
> `scripts/system/global/event_resolver.gd:90` `#先注销效果：离场的牌不能继续生效`
> `scripts/system/global/event_resolver.gd:91` `UnregisterObjectEffects.new().exec(event)`
> `scripts/system/global/event_resolver.gd:92` `events.remove_at(i)`
> `scripts/system/global/event_resolver.gd:93` `if event is BaseEvent:`
> `scripts/system/global/event_resolver.gd:94` `#移入事件牌弃牌区而不是销毁：玩家要能回看本局出过哪些事件牌。`
> `scripts/system/global/event_resolver.gd:95` `#弃牌区在每局开始时统一销毁并清空，不会跨局累积`
> `scripts/system/global/event_resolver.gd:96` `event.set_concealed(false)`
> `scripts/system/global/situation_resolver.gd:55` `func clear_all():`
> `scripts/system/global/situation_resolver.gd:56` `var situation = MapData.active_situation`
> `scripts/system/global/situation_resolver.gd:57` `if situation == null:`
> `scripts/system/global/situation_resolver.gd:58` `return`
> `scripts/system/global/situation_resolver.gd:59` `UnregisterObjectEffects.new().exec(situation)`
> `scripts/system/global/situation_resolver.gd:60` `#移入局势牌弃牌区而不是销毁：玩家要能回看本局展示过哪些局势牌。`
> `scripts/system/global/situation_resolver.gd:61` `#弃牌区在每局开始时统一销毁并清空`
> `scripts/system/global/situation_resolver.gd:62` `MapData.situation_discard.append(situation)`
> `scripts/system/global/situation_resolver.gd:63` `MapData.active_situation = null`
> `scripts/system/operations/UnregisterObjectEffects.gd:5` `func exec(object):`
> `scripts/system/operations/UnregisterObjectEffects.gd:6` ``
> `scripts/system/operations/UnregisterObjectEffects.gd:7` `if object == null or !("_effects" in object):`
> `scripts/system/operations/UnregisterObjectEffects.gd:8` `return`
> `scripts/system/operations/UnregisterObjectEffects.gd:9` `for effect in object._effects:`
> `scripts/system/operations/UnregisterObjectEffects.gd:10` `if effect is BaseEffect:`
> `scripts/system/operations/UnregisterObjectEffects.gd:11` `EffectManager.unregister_effect(effect)`
> `scripts/system/global/effect_manager.gd:1000` `#效果离场(卡牌被移除游戏等)时取消登记，之后的时点不再检查它`
> `scripts/system/global/effect_manager.gd:1001` `func unregister_effect(effect:BaseEffect):`
> `scripts/system/global/effect_manager.gd:1002` `if effect == null:`
> `scripts/system/global/effect_manager.gd:1003` `return`
> `scripts/system/global/effect_manager.gd:1004` `effect_pool.erase(effect)`
> `scripts/system/global/effect_manager.gd:1005` `decision_queue.erase(effect)`
> `scripts/system/global/effect_manager.gd:1006` `activation_pool.erase(effect)`
> `scripts/system/global/effect_manager.gd:1007` `matched_time_points.erase(effect)`
> `scripts/system/global/effect_manager.gd:1008` `if waiting_effect == effect:`
> `scripts/system/global/effect_manager.gd:1009` `waiting_effect = null`
> `scripts/system/global/effect_manager.gd:1010` `if waiting_selection == effect:`
> `scripts/system/global/effect_manager.gd:1011` `waiting_selection = null`
> `scripts/system/global/effect_manager.gd:1012` `_waiting_selection_option = -1`
> `scripts/system/global/effect_manager.gd:1013` `_pending_selection_choice.erase(effect)`
> `scripts/system/global/effect_manager.gd:1014` `if waiting_location == effect:`
> `scripts/system/global/effect_manager.gd:1015` `waiting_location = null`
> `scripts/system/global/effect_manager.gd:1016` `_pending_location_choice.erase(effect)`
> `scripts/system/global/effect_manager.gd:1017` `if waiting_players == effect:`
> `scripts/system/global/effect_manager.gd:1018` `waiting_players = null`
> `scripts/system/global/effect_manager.gd:1019` `_pending_player_choice.erase(effect)`
> `scripts/system/global/effect_manager.gd:1020` `var id = effect._trigger_player_id`
> `scripts/system/global/effect_manager.gd:1021` `if id != -1:`
> `scripts/system/global/effect_manager.gd:1022` `var pl_data = GameDataManager.get_player_data(id) as Dictionary`
> `scripts/system/global/effect_manager.gd:1023` `(pl_data["self_effects"] as Array).erase(effect)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/event_resolver.gd:91` | 直接实例调用 | `UnregisterObjectEffects.new().exec(event)` |
| `scripts/system/global/situation_resolver.gd:59` | 直接实例调用 | `UnregisterObjectEffects.new().exec(situation)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/local_spell_restore_test.gd:170`; `tests/newspecial_spell_materialization_test.gd:122`。
- **排除区（不计本类生产数）/debug**：`scripts/debug/debug_adapters/debug_card_adapter.gd:64,114`; `scripts/debug/debug_adapters/debug_identity_adapter.gd:113,114,144,145,204,316,337,371,388,399`。

## 4. B 档：未注册、代码直接承载的规则/效果（9 类）

### B — BattleResolver
- **定义**：`scripts/system/global/battle_resolver.gd:1`。
- **公开入口**：`scripts/system/global/battle_resolver.gd:12` `func exec(active_player_ids:Array = [], area_battle_score:BaseNumber = BaseNumber.new(1)) -> Dictionary:`; `scripts/system/global/battle_resolver.gd:87` `static func finalize_result(result:Dictionary) -> Dictionary:`。
- **注册表**：无；逐项检查 `AllOperations.TABLE` 的 214 个 class 值与键，`BattleResolver`/`battle_resolver` 均未出现；定义在上列文件，非目录缺文件造成。
- **正式数据 func_name 引用**：`battle_resolver` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：<span style="color:#d00000">🔴 是：战斗阶段收尾代码直连；发 BATTLE / BATTLE_RESOLVE / BATTLE_END，以及胜/败与战果时点。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/game_progress.gd:514` `func end_phase():`
> `scripts/system/global/game_progress.gd:515` `if is_game_over or _phase_end_running or _effects_block_progress() or _battle_broadcast_pending:`
> `scripts/system/global/game_progress.gd:516` `return`
> `scripts/system/global/game_progress.gd:517` `var phase = get_current_phase()`
> `scripts/system/global/game_progress.gd:518` `if phase.is_empty():`
> `scripts/system/global/game_progress.gd:519` `return`
> `scripts/system/global/game_progress.gd:520` `_phase_end_pending = true`
> `scripts/system/global/game_progress.gd:521` `_phase_end_running = true`
> `scripts/system/global/game_progress.gd:522` `if phase["name"] == "battle" and !has_battle_resolved:`
> `scripts/system/global/game_progress.gd:523` `has_battle_resolved = true`
> `scripts/system/global/game_progress.gd:524` `last_battle_result = BattleResolver.new().exec(GameDataManager.get_board_player_ids(), BaseNumber.new(1))`
> `scripts/system/global/game_progress.gd:525` `#BATTLE_END 的选择尚未完成时保留阶段、事件和原决策队列，不能开 PHASE_END 新批次。`
> `scripts/system/global/game_progress.gd:526` `if is_game_over or _effects_block_progress():`
> `scripts/system/global/game_progress.gd:527` `_phase_end_running = false`
> `scripts/system/global/game_progress.gd:528` `return`
> `scripts/system/global/game_progress.gd:529` `if !_phase_end_dispatched:`
> `scripts/system/global/game_progress.gd:530` `# 战后选择全部结束后封存本次实得，不能把阶段结束收益混入战报。`
> `scripts/system/global/game_progress.gd:531` `if phase["name"] == "battle":`
> `scripts/system/global/game_progress.gd:532` `BattleResolver.finalize_result(last_battle_result)`
> `scripts/system/global/game_progress.gd:533` `#先记已派发，避免结束效果回调重入或稍后续行时重发同一时点。`
> `scripts/system/global/game_progress.gd:534` `_phase_end_dispatched = true`
> `scripts/system/global/game_progress.gd:535` `TimePointChecker.global_time_point([TimePoints.PHASE_END, phase["end"]])`
> `scripts/system/global/battle_resolver.gd:52` `for id in ids:`
> `scripts/system/global/battle_resolver.gd:53` `var player_data = GameDataManager.get_player_data(id) as Dictionary`
> `scripts/system/global/battle_resolver.gd:54` `if player_data["is_out"]:`
> `scripts/system/global/battle_resolver.gd:55` `continue`
> `scripts/system/global/battle_resolver.gd:56` `player_data["is_battle"] = true`
> `scripts/system/global/battle_resolver.gd:57` `TimePointChecker.dynamic_time_point([TimePoints.BATTLE], id)`
> `scripts/system/global/battle_resolver.gd:58` ``
> `scripts/system/global/battle_resolver.gd:59` `#注册场上所有事件牌效果（归属存活玩家作锚点），再派发一次全局战斗结算时点。`
> `scripts/system/global/battle_resolver.gd:60` `#事件牌效果挂battle_resolve时点，触发时用event.from反查所在战场遍历战场玩家。`
> `scripts/system/global/battle_resolver.gd:61` `_register_event_effects(ids)`
> `scripts/system/global/battle_resolver.gd:62` `TimePointChecker.global_time_point([TimePoints.BATTLE_RESOLVE])`
> `scripts/system/global/battle_resolver.gd:63` ``
> `scripts/system/global/battle_resolver.gd:64` `#逐区域结算`
> `scripts/system/global/battle_resolver.gd:65` `for area:BaseMapArea in area_to_players.keys():`
> `scripts/system/global/battle_resolver.gd:66` `var player_ids:Array = area_to_players[area]`
> `scripts/system/global/battle_resolver.gd:67` `if area._score_need_win:`
> `scripts/system/global/battle_resolver.gd:68` `_resolve_battle_area(area, player_ids, result)`
> `scripts/system/global/battle_resolver.gd:69` `else:`
> `scripts/system/global/battle_resolver.gd:70` `_resolve_non_battle_area(area, player_ids, result)`
> `scripts/system/global/battle_resolver.gd:71` `#胜负改写只对本回合这一次结算有效：没人参战、不比威力的战场上的声明也一并作废，不留到下一回合`
> `scripts/system/global/battle_resolver.gd:72` `for area:BaseMapArea in MapData.areas:`
> `scripts/system/global/battle_resolver.gd:73` `area._battle_override = {}`
> `scripts/system/global/battle_resolver.gd:74` ``
> `scripts/system/global/battle_resolver.gd:75` `#胜者判定之后的时点：派发在全部区域结算完之后。`
> `scripts/system/global/battle_resolver.gd:76` `#"此战场胜者可恢复1枚令咒"这类规则要在知道本场胜者之后才能触发，`
> `scripts/system/global/battle_resolver.gd:77` `#而 battle_resolve 派发在胜者计算之前，查不到本场结果——所以另设全局时点`
> `scripts/system/global/battle_resolver.gd:78` `TimePointChecker.global_time_point([TimePoints.BATTLE_END])`
> `scripts/system/global/battle_resolver.gd:205` `#平分按参战条目数算（两个条目并列就是两份），与原规则一致`
> `scripts/system/global/battle_resolver.gd:206` `if winners.size() == 1:`
> `scripts/system/global/battle_resolver.gd:207` `var winner_id:int = winners[0]`
> `scripts/system/global/battle_resolver.gd:208` `var rep_id:int = GameDataManager.represented_id(winner_id)`
> `scripts/system/global/battle_resolver.gd:209` `EditScore.new().exec(null, BaseNumber.new(total_score), rep_id)`
> `scripts/system/global/battle_resolver.gd:210` `TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], rep_id)`
> `scripts/system/global/battle_resolver.gd:211` `result["winners_by_area"][area._area_name] = [winner_id]`
> `scripts/system/global/battle_resolver.gd:212` `elif winners.size() > 1:`
> `scripts/system/global/battle_resolver.gd:213` `#平局：战果平分并向上取整`
> `scripts/system/global/battle_resolver.gd:214` `var split_score:int = ceili(float(total_score) / winners.size())`
> `scripts/system/global/battle_resolver.gd:215` `for winner_id in winners:`
> `scripts/system/global/battle_resolver.gd:216` `var rep_id:int = GameDataManager.represented_id(winner_id)`
> `scripts/system/global/battle_resolver.gd:217` `EditScore.new().exec(null, BaseNumber.new(split_score), rep_id)`
> `scripts/system/global/battle_resolver.gd:218` `TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], rep_id)`
> `scripts/system/global/battle_resolver.gd:239` `for id in player_ids:`
> `scripts/system/global/battle_resolver.gd:240` `if winners.has(id):`
> `scripts/system/global/battle_resolver.gd:241` `continue`
> `scripts/system/global/battle_resolver.gd:242` `var player_data = GameDataManager.get_player_data(id) as Dictionary`
> `scripts/system/global/battle_resolver.gd:243` `var already_excluded:bool = buffs_checker.exec(ExcludedFromBattleWinEffect.EFFECT_NAME, id)`
> `scripts/system/global/battle_resolver.gd:244` `if !already_excluded:`
> `scripts/system/global/battle_resolver.gd:245` `TimePointChecker.dynamic_time_point([TimePoints.BATTLE_LOSE], GameDataManager.represented_id(id))`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/game_progress.gd:524` | 直接实例调用 | `last_battle_result = BattleResolver.new().exec(GameDataManager.get_board_player_ids(), BaseNumber.new(1))` |
| `scripts/system/global/game_progress.gd:532` | 类/静态公开入口 | `BattleResolver.finalize_result(last_battle_result)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/battle_score_report_test.gd:117,156`; `tests/bellerophon_edges_test.gd:60`; `tests/card_audit_probe.gd:130`; `tests/card_effect_runtime_test.gd:121,511`; `tests/command_spell_test.gd:89,296`; `tests/fd39_operations_test.gd:391,398,406,418,426`; `tests/location_benefit_test.gd:42`; `tests/misc_rules_fix_test.gd:249`; `tests/reported_board_power_test.gd:48`; `tests/section5_engine_test.gd:141,152,162`; `tests/twelve_labors_lifecycle_test.gd:90`。
- **排除区（不计本类生产数）/debug**：无。

### B — BoardPowerQuery
- **定义**：`scripts/system/global/board_power_query.gd:1`。
- **公开入口**：`scripts/system/global/board_power_query.gd:30` `static func supports_descriptor(name: String) -> bool:`; `scripts/system/global/board_power_query.gd:40` `static func total(id:int, preview_cards:Array = [], preview_hidden:Array = []) -> int:`; `scripts/system/global/board_power_query.gd:71` `func counts_power(card) -> bool:`; `scripts/system/global/board_power_query.gd:75` `func shared_attack_attribute():`; `scripts/system/global/board_power_query.gd:81` `func evaluate(descriptors:Array):`; `scripts/system/global/board_power_query.gd:84` `func resolve(value) -> Array:`; `scripts/system/global/board_power_query.gd:94` `func evaluate_one(desc:Dictionary):`; `scripts/system/global/board_power_query.gd:181` `static func number(value):`。
- **注册表**：无；逐项检查 `AllOperations.TABLE` 的 214 个 class 值与键，`BoardPowerQuery`/`board_power_query` 均未出现；定义在上列文件，非目录缺文件造成。
- **正式数据 func_name 引用**：`board_power_query` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **特别计数**：没有 JSON 以 `board_power_query` 调此类；本类分支承载 `power_contribution` 5 + `attack_power_contribution` 13 + `card_power_contribution` 1 = **19** 条。不是 19 个 `power_contribution` 同名调用；逐条数据证据见第 6 节。
- **是否涉及时点**：否（实时、无时点触发）：纯作用域求值，仅写 query.variables/contribution/card_values；战斗与 UI 预览均读取。仍按本次要求归 B：承载 19 条未注册的贡献描述符。
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/board_power_query.gd:4` `#Pure evaluation scope for explicitly declared board power expressions.`
> `scripts/system/global/board_power_query.gd:5` `#Never activates effects, changes global context, writes cards, or records logs.`
> `scripts/system/global/board_power_query.gd:6` `#Only the audited read-only operations below are accepted; unknown descriptors fail closed.`
> `scripts/system/global/board_power_query.gd:57` `for card in cards:`
> `scripts/system/global/board_power_query.gd:58` `if card._is_concealed: continue`
> `scripts/system/global/board_power_query.gd:59` `for eff in card._effects:`
> `scripts/system/global/board_power_query.gd:60` `if eff._power_query.is_empty(): continue`
> `scripts/system/global/board_power_query.gd:61` `var query = BoardPowerQuery.new()`
> `scripts/system/global/board_power_query.gd:62` `query.effect = eff`
> `scripts/system/global/board_power_query.gd:63` `query.player_id = id`
> `scripts/system/global/board_power_query.gd:64` `query.card_values = values`
> `scripts/system/global/board_power_query.gd:65` `query.played_cards_view = played`
> `scripts/system/global/board_power_query.gd:66` `query.concealed_overrides = hidden`
> `scripts/system/global/board_power_query.gd:67` `query.evaluate(eff._power_query)`
> `scripts/system/global/board_power_query.gd:68` `result += query.contribution`
> `scripts/system/global/board_power_query.gd:125` `elif name == "power_contribution":`
> `scripts/system/global/board_power_query.gd:126` `if params.size() > 2 and params[2] != null and int(params[2]) == player_id:`
> `scripts/system/global/board_power_query.gd:127` `contribution += int(number(params[1]))`
> `scripts/system/global/board_power_query.gd:128` `elif name == "attack_power_contribution":`
> `scripts/system/global/board_power_query.gd:129` `if params.size() < 3 or params[2] == null or int(params[2]) != player_id: return`
> `scripts/system/global/board_power_query.gd:130` `for card in played_cards_view:`
> `scripts/system/global/board_power_query.gd:131` `if not card is BaseHandCard or not counts_power(card): continue`
> `scripts/system/global/board_power_query.gd:132` `if params.size() > 3 and params[3] != null and params[3] != card: continue`
> `scripts/system/global/board_power_query.gd:133` `if params.size() > 4 and params[4] == card: continue`
> `scripts/system/global/board_power_query.gd:134` `var required_category: String = str(params[5]) if params.size() > 5 else ""`
> `scripts/system/global/board_power_query.gd:135` `var min_power: int = int(params[6]) if params.size() > 6 else -1`
> `scripts/system/global/board_power_query.gd:136` `if required_category != "" and str(card.get("_category")) != required_category: continue`
> `scripts/system/global/board_power_query.gd:137` `if min_power >= 0 and (card._power as BaseNumber).number < min_power: continue`
> `scripts/system/global/board_power_query.gd:138` `var attrs: Array = params[0] if params[0] is Array else []`
> `scripts/system/global/board_power_query.gd:139` `if not attrs.is_empty():`
> `scripts/system/global/board_power_query.gd:140` `var matched: bool = false`
> `scripts/system/global/board_power_query.gd:141` `for attr in attrs:`
> `scripts/system/global/board_power_query.gd:142` `if card._attributes.has(attr):`
> `scripts/system/global/board_power_query.gd:143` `matched = true`
> `scripts/system/global/board_power_query.gd:144` `break`
> `scripts/system/global/board_power_query.gd:145` `if not matched: continue`
> `scripts/system/global/board_power_query.gd:146` `contribution += int(number(params[1]))`
> `scripts/system/global/board_power_query.gd:147` `elif name == "card_power_contribution":`
> `scripts/system/global/board_power_query.gd:148` `if params.size() < 4 or params[3] == null or int(params[3]) != player_id: return`
> `scripts/system/global/board_power_query.gd:149` `var card = params[0]`
> `scripts/system/global/board_power_query.gd:150` `if not card is BaseAttack or not counts_power(card): return`
> `scripts/system/global/board_power_query.gd:151` `if not card._power.can_change: return`
> `scripts/system/global/board_power_query.gd:152` `var old:int = int(card_values.get(card, card._power.number))`
> `scripts/system/global/board_power_query.gd:153` `var current:int = int(number(params[2])) if params[2] != null else old`
> `scripts/system/global/board_power_query.gd:154` `current += int(number(params[1]))`
> `scripts/system/global/board_power_query.gd:155` `card_values[card] = current`
> `scripts/system/global/board_power_query.gd:156` `contribution += current - old`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/net/validation/room_data_validator.gd:108` | 类/静态公开入口 | `supported = BoardPowerQuery.supports_descriptor(value.func_name) if query_scope else AllOperations.TABLE.has(value.func_name)` |
| `scripts/system/global/board_power_query.gd:61` | 直接构造 | `var query = BoardPowerQuery.new()` |
| `scripts/system/global/board_power_query.gd:67` | 实例变量调用（new 在 61 行） | `query.evaluate(eff._power_query)` |
| `scripts/system/operations/GetPlayerTotalPower.gd:44` | 类/静态公开入口 | `var board = BoardPowerQuery.total(id, preview_cards, preview_hidden)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/net_data_validation_test.gd:28,29`; `tests/pending_board_power_test.gd:201,214,217`; `tests/reported_board_power_test.gd:124,128,131`。
- **排除区（不计本类生产数）/debug**：无。

### B — CannotPlayCardsEffect
- **定义**：`scripts/system/effects/CannotPlayCardsEffect.gd:1`。
- **公开入口**：无独立 exec/apply；直接构造入口 `scripts/system/effects/CannotPlayCardsEffect.gd:14` `_init()`，继承 BaseEffect。
- **注册表**：无；逐项检查 `AllOperations.TABLE` 的 214 个 class 值与键，`CannotPlayCardsEffect`/`cannot_play_cards_effect` 均未出现；定义在上列文件，非目录缺文件造成。
- **正式数据 func_name 引用**：`cannot_play_cards_effect` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **不是漏登 operation 的假 exec**：它是 `BaseEffect` 持续规则标记，空时点表；数据中的同名 `effect_name` 与 `func_name` 是两个字段，本表未将 effect_name 当作 operation 引用。
- **是否涉及时点**：<span style="color:#d00000">🔴 是（仅挂载/移除生命周期）：DefeatBuff 直接构造的持续规则载荷经 ManageBuff 产生 BUFF_START/END；本类 _time_points=[]，自身没有时点触发入口，不能当作时点 operation。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/buffs/defeat_buff.gd:18` `func _init():`
> `scripts/system/buffs/defeat_buff.gd:19` `#BaseBuff._init只需要name和img；败北buff不需要图片`
> `scripts/system/buffs/defeat_buff.gd:20` `super(DEFEAT_BUFF_NAME, "")`
> `scripts/system/buffs/defeat_buff.gd:21` `var excluded = ExcludedFromBattleWinEffect.new()`
> `scripts/system/buffs/defeat_buff.gd:22` `excluded.from = self`
> `scripts/system/buffs/defeat_buff.gd:23` `add_buff_effect(excluded)`
> `scripts/system/buffs/defeat_buff.gd:24` `var cannot_play = CannotPlayCardsEffect.new()`
> `scripts/system/buffs/defeat_buff.gd:25` `cannot_play.from = self`
> `scripts/system/buffs/defeat_buff.gd:26` `add_buff_effect(cannot_play)`
> `scripts/system/buffs/defeat_buff.gd:27` ``
> `scripts/system/buffs/defeat_buff.gd:28` ``
> `scripts/system/buffs/defeat_buff.gd:29` `#给指定玩家附加一层【败北】，可叠加`
> `scripts/system/buffs/defeat_buff.gd:30` `static func apply(player_id:int = GameData.player_id) -> DefeatBuff:`
> `scripts/system/buffs/defeat_buff.gd:31` `var defeat = DefeatBuff.new()`
> `scripts/system/buffs/defeat_buff.gd:32` `ManageBuff.new().exec(defeat, player_id, true)`
> `scripts/system/operations/ManageBuff.gd:12` `if add_or_del:`
> `scripts/system/operations/ManageBuff.gd:13` `if buffs.has(buff):`
> `scripts/system/operations/ManageBuff.gd:14` `return false`
> `scripts/system/operations/ManageBuff.gd:15` `buffs.append(buff)`
> `scripts/system/operations/ManageBuff.gd:16` `if buff is BaseBuff:`
> `scripts/system/operations/ManageBuff.gd:17` `EffectManager.register_effects(buff._effects, id)`
> `scripts/system/operations/ManageBuff.gd:18` `TimePointChecker.dynamic_time_point([TimePoints.BUFF_START], id)`
> `scripts/system/operations/ManageBuff.gd:19` `return true`
> `scripts/system/operations/ManageBuff.gd:20` ``
> `scripts/system/operations/ManageBuff.gd:21` `if !buffs.has(buff):`
> `scripts/system/operations/ManageBuff.gd:22` `return false`
> `scripts/system/operations/ManageBuff.gd:23` `if buff is BaseBuff:`
> `scripts/system/operations/ManageBuff.gd:24` `for effect:BaseEffect in buff._effects:`
> `scripts/system/operations/ManageBuff.gd:25` `EffectManager.unregister_effect(effect)`
> `scripts/system/operations/ManageBuff.gd:26` `TimePointChecker.dynamic_time_point([TimePoints.BUFF_END], id)`
> `scripts/system/effects/CannotPlayCardsEffect.gd:12` ``
> `scripts/system/effects/CannotPlayCardsEffect.gd:13` ``
> `scripts/system/effects/CannotPlayCardsEffect.gd:14` `func _init():`
> `scripts/system/effects/CannotPlayCardsEffect.gd:15` `#时点表为空：持续型被动，不进效果池的时点结算流程`
> `scripts/system/effects/CannotPlayCardsEffect.gd:16` `super(EFFECT_NAME, [], 0, true, false)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/buffs/defeat_buff.gd:24` | 直接构造（入口 _init；无 exec/apply） | `var cannot_play = CannotPlayCardsEffect.new()` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### B — ClimaxResolver
- **定义**：`scripts/system/global/climax_resolver.gd:1`。
- **公开入口**：`scripts/system/global/climax_resolver.gd:6` `func exec(keep_count:BaseNumber) -> Array:`; `scripts/system/global/climax_resolver.gd:36` `func eliminate_player(player_id:int) -> bool:`。
- **注册表**：无；逐项检查 `AllOperations.TABLE` 的 214 个 class 值与键，`ClimaxResolver`/`climax_resolver` 均未出现；定义在上列文件，非目录缺文件造成。
- **正式数据 func_name 引用**：`climax_resolver` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：<span style="color:#d00000">🔴 是：在 CLIMAX_START/CLIMAX_END 之间直连；淘汰含 BEFORE_ELIMINATE / SURVIVE_ELIMINATION / ELIMINATED。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/game_progress.gd:318` `TimePointChecker.set_phase_time_points([TimePoints.DAY])`
> `scripts/system/global/game_progress.gd:319` `TimePointChecker.global_time_point([TimePoints.DAY_END])`
> `scripts/system/global/game_progress.gd:320` `if not await _wait_round_choices():`
> `scripts/system/global/game_progress.gd:321` `return`
> `scripts/system/global/game_progress.gd:322` `if climax_keep_counts.has(current_round):`
> `scripts/system/global/game_progress.gd:323` `TimePointChecker.global_time_point([TimePoints.CLIMAX_START])`
> `scripts/system/global/game_progress.gd:324` `if not await _wait_round_choices():`
> `scripts/system/global/game_progress.gd:325` `return`
> `scripts/system/global/game_progress.gd:326` `ClimaxResolver.new().exec(climax_keep_counts[current_round])`
> `scripts/system/global/game_progress.gd:327` `if not await _wait_round_choices():`
> `scripts/system/global/game_progress.gd:328` `return`
> `scripts/system/global/game_progress.gd:329` `TimePointChecker.global_time_point([TimePoints.CLIMAX_END])`
> `scripts/system/global/climax_resolver.gd:40` `if player_data["is_out"]:`
> `scripts/system/global/climax_resolver.gd:41` `return false`
> `scripts/system/global/climax_resolver.gd:42` `#即将淘汰：效果可以取消（遥远的理想乡、阿瓦隆这类"首次淘汰时继续"的替代）。`
> `scripts/system/global/climax_resolver.gd:43` `#被取消就派发"免于淘汰"，供"每次从淘汰幸存"类效果监听`
> `scripts/system/global/climax_resolver.gd:44` `if EffectManager.begin_pending_action(TimePoints.BEFORE_ELIMINATE, player_id).get("cancelled", false):`
> `scripts/system/global/climax_resolver.gd:45` `TimePointChecker.dynamic_time_point([TimePoints.SURVIVE_ELIMINATION], player_id)`
> `scripts/system/global/climax_resolver.gd:46` `return false`
> `scripts/system/global/climax_resolver.gd:47` `player_data["is_out"] = true`
> `scripts/system/global/climax_resolver.gd:48` `#日志：谁被淘汰（供"当时场上有被淘汰的玩家吗"这类历史查询）。`
> `scripts/system/global/climax_resolver.gd:49` `#带上当时的战果：事后核对"为什么是他被淘汰"不必再翻别的记录`
> `scripts/system/global/climax_resolver.gd:50` `var score:int = (player_data["score"] as BaseNumber).number`
> `scripts/system/global/climax_resolver.gd:51` `GameLog.record("eliminated", player_id, -1, "", null, ["eliminated"], {"score": score})`
> `scripts/system/global/climax_resolver.gd:52` `#被淘汰的玩家离开版图：只置is_out不摘席位，他仍会占着位置、也仍显示在战区上。`
> `scripts/system/global/climax_resolver.gd:53` `#复用回合结束用的同一个原语，不在这里另写一套摘除逻辑`
> `scripts/system/global/climax_resolver.gd:54` `RemoveFromBoard.new().exec(player_id)`
> `scripts/system/global/climax_resolver.gd:55` `#提示全员：谁被淘汰了。文案由显示名接口生成，不按id编号示人`
> `scripts/system/global/climax_resolver.gd:56` `var shown:String = EffectManager.player_shown_name(player_id)`
> `scripts/system/global/climax_resolver.gd:57` `EffectManager.push_message("%s 被淘汰，战果 %d" % [shown, score])`
> `scripts/system/global/climax_resolver.gd:58` `TimePointChecker.dynamic_time_point([TimePoints.ELIMINATED], player_id)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/game_progress.gd:326` | 直接实例调用 | `ClimaxResolver.new().exec(climax_keep_counts[current_round])` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/bellerophon_rules_test.gd:99`; `tests/climax_elimination_test.gd:33,41,43,45,52,60`; `tests/fd39_operations_test.gd:155,156,157,552,553,556,558`; `tests/player_shown_name_golden_test.gd:110,121`; `tests/private_knowledge_corrosion_test.gd:36,39,44,46,61,66,71,79,100`。
- **排除区（不计本类生产数）/debug**：`scripts/debug/debug_adapters/debug_player_adapter.gd:95`。

### B — DefeatBuff

**目录身份区别**：`Defeat` / `RemoveDefeat` 是已注册 operation 包装器，但它们代码直连调用的 `DefeatBuff` 类本身不在 TABLE 中；这里按实际类身份归 B，不声称“败北规则完全没有注册入口”。
- **定义**：`scripts/system/buffs/defeat_buff.gd:1`。
- **公开入口**：`scripts/system/buffs/defeat_buff.gd:30` `static func apply(player_id:int = GameData.player_id) -> DefeatBuff:`; `scripts/system/buffs/defeat_buff.gd:37` `static func remove(player_id:int = GameData.player_id):`; `scripts/system/buffs/defeat_buff.gd:51` `static func clear_all():`; `scripts/system/buffs/defeat_buff.gd:57` `static func get_defeat_count(player_id:int = GameData.player_id) -> int:`; `scripts/system/buffs/defeat_buff.gd:66` `static func is_defeated(player_id:int = GameData.player_id) -> bool:`。
- **注册表**：无；逐项检查 `AllOperations.TABLE` 的 214 个 class 值与键，`DefeatBuff`/`defeat_buff` 均未出现；定义在上列文件，非目录缺文件造成。
- **正式数据 func_name 引用**：`defeat_buff` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：<span style="color:#d00000">🔴 是（状态生命周期副作用）：Defeat 的 BEFORE_DEFEAT 与 BATTLE_LOSE 之间创建；ManageBuff 会发 BUFF_START/END；DAY_END 后 clear_all。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/operations/Defeat.gd:7` `func exec(player_id:int = -1):`
> `scripts/system/operations/Defeat.gd:8` `player_id = EffectManager.resolve_player_id(player_id)`
> `scripts/system/operations/Defeat.gd:9` `#即将败北：效果可以取消（守护、幸运这类"无视败北"的替代）`
> `scripts/system/operations/Defeat.gd:10` `if EffectManager.begin_pending_action(TimePoints.BEFORE_DEFEAT, player_id).get("cancelled", false):`
> `scripts/system/operations/Defeat.gd:11` `return`
> `scripts/system/operations/Defeat.gd:12` `DefeatBuff.apply(player_id)`
> `scripts/system/operations/Defeat.gd:13` `TimePointChecker.dynamic_time_point([TimePoints.BATTLE_LOSE], player_id)`
> `scripts/system/buffs/defeat_buff.gd:18` `func _init():`
> `scripts/system/buffs/defeat_buff.gd:19` `#BaseBuff._init只需要name和img；败北buff不需要图片`
> `scripts/system/buffs/defeat_buff.gd:20` `super(DEFEAT_BUFF_NAME, "")`
> `scripts/system/buffs/defeat_buff.gd:21` `var excluded = ExcludedFromBattleWinEffect.new()`
> `scripts/system/buffs/defeat_buff.gd:22` `excluded.from = self`
> `scripts/system/buffs/defeat_buff.gd:23` `add_buff_effect(excluded)`
> `scripts/system/buffs/defeat_buff.gd:24` `var cannot_play = CannotPlayCardsEffect.new()`
> `scripts/system/buffs/defeat_buff.gd:25` `cannot_play.from = self`
> `scripts/system/buffs/defeat_buff.gd:26` `add_buff_effect(cannot_play)`
> `scripts/system/buffs/defeat_buff.gd:27` ``
> `scripts/system/buffs/defeat_buff.gd:28` ``
> `scripts/system/buffs/defeat_buff.gd:29` `#给指定玩家附加一层【败北】，可叠加`
> `scripts/system/buffs/defeat_buff.gd:30` `static func apply(player_id:int = GameData.player_id) -> DefeatBuff:`
> `scripts/system/buffs/defeat_buff.gd:31` `var defeat = DefeatBuff.new()`
> `scripts/system/buffs/defeat_buff.gd:32` `ManageBuff.new().exec(defeat, player_id, true)`
> `scripts/system/global/game_progress.gd:352` `#规则：【败北】状态持续至回合结束`
> `scripts/system/global/game_progress.gd:353` `DefeatBuff.clear_all()`
> `scripts/system/global/game_progress.gd:354` `#规则：回合结束时弃置所有激活的局势牌和事件牌`
> `scripts/system/global/game_progress.gd:355` `SituationResolver.new().clear_all()`
> `scripts/system/global/game_progress.gd:356` `EventResolver.new().clear_all()`
> `scripts/system/operations/ManageBuff.gd:12` `if add_or_del:`
> `scripts/system/operations/ManageBuff.gd:13` `if buffs.has(buff):`
> `scripts/system/operations/ManageBuff.gd:14` `return false`
> `scripts/system/operations/ManageBuff.gd:15` `buffs.append(buff)`
> `scripts/system/operations/ManageBuff.gd:16` `if buff is BaseBuff:`
> `scripts/system/operations/ManageBuff.gd:17` `EffectManager.register_effects(buff._effects, id)`
> `scripts/system/operations/ManageBuff.gd:18` `TimePointChecker.dynamic_time_point([TimePoints.BUFF_START], id)`
> `scripts/system/operations/ManageBuff.gd:19` `return true`
> `scripts/system/operations/ManageBuff.gd:20` ``
> `scripts/system/operations/ManageBuff.gd:21` `if !buffs.has(buff):`
> `scripts/system/operations/ManageBuff.gd:22` `return false`
> `scripts/system/operations/ManageBuff.gd:23` `if buff is BaseBuff:`
> `scripts/system/operations/ManageBuff.gd:24` `for effect:BaseEffect in buff._effects:`
> `scripts/system/operations/ManageBuff.gd:25` `EffectManager.unregister_effect(effect)`
> `scripts/system/operations/ManageBuff.gd:26` `TimePointChecker.dynamic_time_point([TimePoints.BUFF_END], id)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/buffs/defeat_buff.gd:31` | 直接构造 | `var defeat = DefeatBuff.new()` |
| `scripts/system/global/game_progress.gd:353` | 类/静态公开入口 | `DefeatBuff.clear_all()` |
| `scripts/system/operations/Defeat.gd:12` | 类/静态公开入口 | `DefeatBuff.apply(player_id)` |
| `scripts/system/operations/RemoveDefeat.gd:8` | 类/静态公开入口 | `DefeatBuff.remove(player_id)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/card_effect_runtime_test.gd:37,94,103,111,187,204,212`; `tests/effect_body_fill_test.gd:104,115,127`; `tests/fd39_operations_test.gd:165,415,416,420`; `tests/masters_audit_fix_test.gd:89,92`; `tests/twelve_labors_lifecycle_test.gd:57`。
- **排除区（不计本类生产数）/debug**：无。

### B — EventResolver
- **定义**：`scripts/system/global/event_resolver.gd:1`。
- **公开入口**：`scripts/system/global/event_resolver.gd:13` `func place(plan:Array) -> Array:`; `scripts/system/global/event_resolver.gd:37` `func reveal_planned(plan:Array) -> int:`; `scripts/system/global/event_resolver.gd:42` `func start_reveal(plan:Array) -> Dictionary:`; `scripts/system/global/event_resolver.gd:75` `func register_entered(event:BaseEvent):`; `scripts/system/global/event_resolver.gd:85` `func clear_all():`。
- **注册表**：无；逐项检查 `AllOperations.TABLE` 的 214 个 class 值与键，`EventResolver`/`event_resolver` 均未出现；定义在上列文件，非目录缺文件造成。
- **正式数据 func_name 引用**：`event_resolver` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：<span style="color:#d00000">🔴 是：回合开始放置、行动阶段前翻明、DAY_END 后清场；登记效果并派 CARD_REVEALED。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/game_progress.gd:284` `TimePointChecker.global_time_point([TimePoints.DAY_START])`
> `scripts/system/global/game_progress.gd:285` `"events":`
> `scripts/system/global/game_progress.gd:286` `state.phase = "advance"`
> `scripts/system/global/game_progress.gd:287` `EventResolver.new().place(event_placements)`
> `scripts/system/global/game_progress.gd:415` `#阶段固定窗口完成后才翻计划事件；翻牌完成后才派发阶段开始。`
> `scripts/system/global/game_progress.gd:416` `func _begin_phase_events(phase:Dictionary) -> void:`
> `scripts/system/global/game_progress.gd:417` `#规则：行动阶段开始时展示暗置放置的事件牌（基础规则写明是"位于新都"的那张）。`
> `scripts/system/global/game_progress.gd:418` `#翻在派发阶段时点之前：阶段能力跑的时候应该已经看得到这张明置牌`
> `scripts/system/global/game_progress.gd:419` `if str(phase.get("name", "")) == "action":`
> `scripts/system/global/game_progress.gd:420` `EventResolver.new().reveal_planned(event_placements)`
> `scripts/system/global/game_progress.gd:421` `if not EffectManager.defer_until_runtime_guard_complete(Callable(self, "_dispatch_phase_start").bind(phase)):`
> `scripts/system/global/game_progress.gd:422` `_dispatch_phase_start(phase)`
> `scripts/system/global/game_progress.gd:423` ``
> `scripts/system/global/game_progress.gd:424` `func _dispatch_phase_start(phase:Dictionary) -> void:`
> `scripts/system/global/game_progress.gd:425` `TimePointChecker.global_time_point([TimePoints.PHASE_START, phase["start"]])`
> `scripts/system/global/game_progress.gd:353` `DefeatBuff.clear_all()`
> `scripts/system/global/game_progress.gd:354` `#规则：回合结束时弃置所有激活的局势牌和事件牌`
> `scripts/system/global/game_progress.gd:355` `SituationResolver.new().clear_all()`
> `scripts/system/global/game_progress.gd:356` `EventResolver.new().clear_all()`
> `scripts/system/global/event_resolver.gd:62` `var event = area._events[state.event_index]`
> `scripts/system/global/event_resolver.gd:63` `state.event_index += 1`
> `scripts/system/global/event_resolver.gd:64` `if event is BaseEvent and event._is_concealed:`
> `scripts/system/global/event_resolver.gd:65` `SetCardConcealed.new().exec(event, false)`
> `scripts/system/global/event_resolver.gd:66` `state.count += 1`
> `scripts/system/global/event_resolver.gd:67` `EventResolver.new().register_entered(event)`
> `scripts/system/global/event_resolver.gd:68` `if EffectManager.defer_until_runtime_guard_complete(Callable(EventResolver, "_resume_reveal").bind(state)):`
> `scripts/system/global/event_resolver.gd:69` `return`
> `scripts/system/global/event_resolver.gd:70` `state.completed = true`
> `scripts/system/global/event_resolver.gd:71` ``
> `scripts/system/global/event_resolver.gd:72` ``
> `scripts/system/global/event_resolver.gd:73` `#明置放置（AddEventFromDeck）与暗置翻开（reveal_planned）共用这一条：`
> `scripts/system/global/event_resolver.gd:74` `#登记本牌效果，再带 source 派发"本牌亮出时"——只唤醒本牌的效果，不广播给别处监听`
> `scripts/system/global/event_resolver.gd:75` `func register_entered(event:BaseEvent):`
> `scripts/system/global/event_resolver.gd:76` `var ids:Array = GameDataManager.get_active_player_ids()`
> `scripts/system/global/event_resolver.gd:77` `if ids.is_empty(): return`
> `scripts/system/global/event_resolver.gd:78` `for effect in event._effects:`
> `scripts/system/global/event_resolver.gd:79` `if effect._trigger_player_id == -1: EffectManager.register_effect(effect, int(ids[0]))`
> `scripts/system/global/event_resolver.gd:80` `TimePointChecker.card_revealed(event)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/event_resolver.gd:67` | 直接实例调用 | `EventResolver.new().register_entered(event)` |
| `scripts/system/global/game_progress.gd:287` | 直接实例调用 | `EventResolver.new().place(event_placements)` |
| `scripts/system/global/game_progress.gd:356` | 直接实例调用 | `EventResolver.new().clear_all()` |
| `scripts/system/global/game_progress.gd:420` | 直接实例调用 | `EventResolver.new().reveal_planned(event_placements)` |
| `scripts/system/operations/AddEventFromDeck.gd:37` | 直接实例调用 | `if not state.concealed: EventResolver.new().register_entered(event)` |
- **排除区（不计本类生产数）/测试/诊断**：`newtests/action_completion_public_contract_test.gd:30`; `newtests/round74_outpost_public_contract_test.gd:28`; `tests/battle_event_discard_test.gd:37,44`; `tests/card_zone_browser_test.gd:159,165,175,179`; `tests/command_spell_test.gd:226,239,251,263,282,295`; `tests/deploy_rules_test.gd:12`; `tests/engagement_test.gd:49`; `tests/post_battle_choice_test.gd:25,69`; `tests/reported_board_power_test.gd:39,86`; `tests/rule_guard_event_place_test.gd:28`; `tests/rule_guard_event_reveal_test.gd:30`。
- **排除区（不计本类生产数）/debug**：`scripts/debug/debug_adapters/debug_board_adapter.gd:38,43`。

### B — ExcludedFromBattleWinEffect
- **定义**：`scripts/system/effects/ExcludedFromBattleWinEffect.gd:1`。
- **公开入口**：无独立 exec/apply；直接构造入口 `scripts/system/effects/ExcludedFromBattleWinEffect.gd:14` `_init()`，继承 BaseEffect。
- **注册表**：无；逐项检查 `AllOperations.TABLE` 的 214 个 class 值与键，`ExcludedFromBattleWinEffect`/`excluded_from_battle_win_effect` 均未出现；定义在上列文件，非目录缺文件造成。
- **正式数据 func_name 引用**：`excluded_from_battle_win_effect` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **不是漏登 operation 的假 exec**：它是 `BaseEffect` 持续规则标记，空时点表；数据中的同名 `effect_name` 与 `func_name` 是两个字段，本表未将 effect_name 当作 operation 引用。
- **是否涉及时点**：<span style="color:#d00000">🔴 是（仅挂载/移除生命周期）：DefeatBuff 直接构造的持续规则载荷经 ManageBuff 产生 BUFF_START/END；本类 _time_points=[]，自身没有时点触发入口，不能当作时点 operation。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/buffs/defeat_buff.gd:18` `func _init():`
> `scripts/system/buffs/defeat_buff.gd:19` `#BaseBuff._init只需要name和img；败北buff不需要图片`
> `scripts/system/buffs/defeat_buff.gd:20` `super(DEFEAT_BUFF_NAME, "")`
> `scripts/system/buffs/defeat_buff.gd:21` `var excluded = ExcludedFromBattleWinEffect.new()`
> `scripts/system/buffs/defeat_buff.gd:22` `excluded.from = self`
> `scripts/system/buffs/defeat_buff.gd:23` `add_buff_effect(excluded)`
> `scripts/system/buffs/defeat_buff.gd:24` `var cannot_play = CannotPlayCardsEffect.new()`
> `scripts/system/buffs/defeat_buff.gd:25` `cannot_play.from = self`
> `scripts/system/buffs/defeat_buff.gd:26` `add_buff_effect(cannot_play)`
> `scripts/system/buffs/defeat_buff.gd:27` ``
> `scripts/system/buffs/defeat_buff.gd:28` ``
> `scripts/system/buffs/defeat_buff.gd:29` `#给指定玩家附加一层【败北】，可叠加`
> `scripts/system/buffs/defeat_buff.gd:30` `static func apply(player_id:int = GameData.player_id) -> DefeatBuff:`
> `scripts/system/buffs/defeat_buff.gd:31` `var defeat = DefeatBuff.new()`
> `scripts/system/buffs/defeat_buff.gd:32` `ManageBuff.new().exec(defeat, player_id, true)`
> `scripts/system/operations/ManageBuff.gd:12` `if add_or_del:`
> `scripts/system/operations/ManageBuff.gd:13` `if buffs.has(buff):`
> `scripts/system/operations/ManageBuff.gd:14` `return false`
> `scripts/system/operations/ManageBuff.gd:15` `buffs.append(buff)`
> `scripts/system/operations/ManageBuff.gd:16` `if buff is BaseBuff:`
> `scripts/system/operations/ManageBuff.gd:17` `EffectManager.register_effects(buff._effects, id)`
> `scripts/system/operations/ManageBuff.gd:18` `TimePointChecker.dynamic_time_point([TimePoints.BUFF_START], id)`
> `scripts/system/operations/ManageBuff.gd:19` `return true`
> `scripts/system/operations/ManageBuff.gd:20` ``
> `scripts/system/operations/ManageBuff.gd:21` `if !buffs.has(buff):`
> `scripts/system/operations/ManageBuff.gd:22` `return false`
> `scripts/system/operations/ManageBuff.gd:23` `if buff is BaseBuff:`
> `scripts/system/operations/ManageBuff.gd:24` `for effect:BaseEffect in buff._effects:`
> `scripts/system/operations/ManageBuff.gd:25` `EffectManager.unregister_effect(effect)`
> `scripts/system/operations/ManageBuff.gd:26` `TimePointChecker.dynamic_time_point([TimePoints.BUFF_END], id)`
> `scripts/system/effects/ExcludedFromBattleWinEffect.gd:12` ``
> `scripts/system/effects/ExcludedFromBattleWinEffect.gd:13` ``
> `scripts/system/effects/ExcludedFromBattleWinEffect.gd:14` `func _init():`
> `scripts/system/effects/ExcludedFromBattleWinEffect.gd:15` `#时点表为空：持续型被动，不进效果池的时点结算流程`
> `scripts/system/effects/ExcludedFromBattleWinEffect.gd:16` `super(EFFECT_NAME, [], 0, true, false)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/buffs/defeat_buff.gd:21` | 直接构造（入口 _init；无 exec/apply） | `var excluded = ExcludedFromBattleWinEffect.new()` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### B — SituationResolver
- **定义**：`scripts/system/global/situation_resolver.gd:1`。
- **公开入口**：`scripts/system/global/situation_resolver.gd:11` `func activate():`; `scripts/system/global/situation_resolver.gd:55` `func clear_all():`。
- **注册表**：无；逐项检查 `AllOperations.TABLE` 的 214 个 class 值与键，`SituationResolver`/`situation_resolver` 均未出现；定义在上列文件，非目录缺文件造成。
- **正式数据 func_name 引用**：`situation_resolver` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：<span style="color:#d00000">🔴 是：在 DAY_START 前直接激活；BEFORE_SITUATION_ACTIVATE、亮出和 SITUATION_ACTIVATED；DAY_END 后退场还原。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/game_progress.gd:279` `"situation":`
> `scripts/system/global/game_progress.gd:280` `state.phase = "day_start"`
> `scripts/system/global/game_progress.gd:281` `SituationResolver.new().activate()`
> `scripts/system/global/game_progress.gd:282` `"day_start":`
> `scripts/system/global/game_progress.gd:283` `state.phase = "events"`
> `scripts/system/global/game_progress.gd:284` `TimePointChecker.global_time_point([TimePoints.DAY_START])`
> `scripts/system/global/game_progress.gd:285` `"events":`
> `scripts/system/global/game_progress.gd:286` `state.phase = "advance"`
> `scripts/system/global/game_progress.gd:287` `EventResolver.new().place(event_placements)`
> `scripts/system/global/game_progress.gd:353` `DefeatBuff.clear_all()`
> `scripts/system/global/game_progress.gd:354` `#规则：回合结束时弃置所有激活的局势牌和事件牌`
> `scripts/system/global/game_progress.gd:355` `SituationResolver.new().clear_all()`
> `scripts/system/global/game_progress.gd:356` `EventResolver.new().clear_all()`
> `scripts/system/global/situation_resolver.gd:16` `#局势牌即将生效：效果可以取消（直接进弃牌区，本回合没有局势牌），不属于任何玩家`
> `scripts/system/global/situation_resolver.gd:17` `if EffectManager.begin_pending_action(TimePoints.BEFORE_SITUATION_ACTIVATE, -1, {"situation": situation}, situation).get("cancelled", false):`
> `scripts/system/global/situation_resolver.gd:18` `MapData.situation_discard.append(situation)`
> `scripts/system/global/situation_resolver.gd:19` `MapData.active_situation = null`
> `scripts/system/global/situation_resolver.gd:20` `return`
> `scripts/system/global/situation_resolver.gd:21` `MapData.active_situation = situation`
> `scripts/system/global/situation_resolver.gd:22` `_resume_activation({"situation": situation, "players": GameDataManager.get_active_player_ids(), "index": 0})`
> `scripts/system/global/situation_resolver.gd:39` `#把局势牌效果登记进效果池(挂battle_resolve的属性加成等)`
> `scripts/system/global/situation_resolver.gd:40` `_register_situation_effects()`
> `scripts/system/global/situation_resolver.gd:41` `#局势牌已亮出：派发本牌亮出时点，让布置类效果（增加事件牌、封锁战区、改席位上限）立刻执行。`
> `scripts/system/global/situation_resolver.gd:42` `#不派的话这些效果要等到战斗结算才跑，整个行动阶段玩家都看不到牌面宣告的场地变化，`
> `scripts/system/global/situation_resolver.gd:43` `#表现就是"局势牌效果没结算"。威力加成类仍挂 battle_resolve，不受影响`
> `scripts/system/global/situation_resolver.gd:44` `#带 source 派发三种卡牌亮出时点：自身、其他、任意。`
> `scripts/system/global/situation_resolver.gd:45` `TimePointChecker.card_revealed(situation)`
> `scripts/system/global/situation_resolver.gd:46` `if not EffectManager.defer_until_runtime_guard_complete(Callable(SituationResolver, "_dispatch_activated").bind(situation)):`
> `scripts/system/global/situation_resolver.gd:47` `_dispatch_activated(situation)`
> `scripts/system/global/situation_resolver.gd:48` ``
> `scripts/system/global/situation_resolver.gd:49` ``
> `scripts/system/global/situation_resolver.gd:50` `static func _dispatch_activated(situation:BaseSituation) -> void:`
> `scripts/system/global/situation_resolver.gd:51` `TimePointChecker.global_time_point([TimePoints.SITUATION_ACTIVATED], situation)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/game_progress.gd:281` | 直接实例调用 | `SituationResolver.new().activate()` |
| `scripts/system/global/game_progress.gd:355` | 直接实例调用 | `SituationResolver.new().clear_all()` |
- **排除区（不计本类生产数）/测试/诊断**：`newtests/action_completion_public_contract_test.gd:31`; `newtests/round74_outpost_public_contract_test.gd:29`; `tests/card_revealed_test.gd:78,116`; `tests/deploy_rules_test.gd:13`; `tests/engagement_test.gd:50`; `tests/post_battle_choice_test.gd:26`; `tests/reported_board_power_test.gd:82`; `tests/rule_guard_situation_magic_test.gd:24`; `tests/rule_guard_situation_test.gd:36`; `tests/twelve_labors_lifecycle_test.gd:15`。
- **排除区（不计本类生产数）/debug**：`scripts/debug/debug_adapters/debug_board_adapter.gd:61,69,78`。

### B — VictoryResolver
- **定义**：`scripts/system/global/victory_resolver.gd:1`。
- **公开入口**：`scripts/system/global/victory_resolver.gd:9` `func exec(battle_result:Dictionary = {}) -> Array:`。
- **注册表**：无；逐项检查 `AllOperations.TABLE` 的 214 个 class 值与键，`VictoryResolver`/`victory_resolver` 均未出现；定义在上列文件，非目录缺文件造成。
- **正式数据 func_name 引用**：`victory_resolver` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：<span style="color:#d00000">🔴 是（结束时点前的胜负副作用）：直接写 is_victory，结果交 end_game 随即派 GAME_END；本类不自行派。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/game_progress.gd:211` `names.append(EffectManager.player_shown_name(int(id)))`
> `scripts/system/global/game_progress.gd:212` `GameLog.record("game_end", -1, -1, "", null, ["game_end"],`
> `scripts/system/global/game_progress.gd:213` `{"winners": winners.duplicate(), "round": current_round})`
> `scripts/system/global/game_progress.gd:214` `if winners.is_empty():`
> `scripts/system/global/game_progress.gd:215` `#规则：并列且决胜仍无法分出唯一胜者时，圣杯溢出，所有人都输`
> `scripts/system/global/game_progress.gd:216` `EffectManager.push_message("圣杯溢出，全员判负")`
> `scripts/system/global/game_progress.gd:217` `else:`
> `scripts/system/global/game_progress.gd:218` `EffectManager.push_message("游戏结束，胜者：" + "、".join(names))`
> `scripts/system/global/game_progress.gd:219` `TimePointChecker.set_phase_time_points([])`
> `scripts/system/global/game_progress.gd:220` `TimePointChecker.global_time_point([TimePoints.GAME_END])`
> `scripts/system/global/game_progress.gd:332` `if current_round == total_rounds.number or GameDataManager.get_active_player_ids().size() <= 1:`
> `scripts/system/global/game_progress.gd:333` `#胜者由 VictoryResolver 判定（战果最高 → 并列看深山町胜者 → 仍并列则圣杯溢出），`
> `scripts/system/global/game_progress.gd:334` `#结果传给 end_game 记进日志并提示玩家；这里不重复判定规则`
> `scripts/system/global/game_progress.gd:335` `_round_end_running = false`
> `scripts/system/global/game_progress.gd:336` `end_game(VictoryResolver.new().exec(last_battle_result))`
> `scripts/system/global/victory_resolver.gd:21` `if !overridden_winners.is_empty():`
> `scripts/system/global/victory_resolver.gd:22` `for id in active_ids:`
> `scripts/system/global/victory_resolver.gd:23` `var player_data = GameDataManager.get_player_data(id) as Dictionary`
> `scripts/system/global/victory_resolver.gd:24` `player_data["is_victory"] = overridden_winners.has(id)`
> `scripts/system/global/victory_resolver.gd:25` `return overridden_winners`
> `scripts/system/global/victory_resolver.gd:26` ``
> `scripts/system/global/victory_resolver.gd:27` `var highest_score = null`
> `scripts/system/global/victory_resolver.gd:28` `var winners:Array = []`
> `scripts/system/global/victory_resolver.gd:29` `for id in active_ids:`
> `scripts/system/global/victory_resolver.gd:30` `var player_data = GameDataManager.get_player_data(id) as Dictionary`
> `scripts/system/global/victory_resolver.gd:31` `player_data["is_victory"] = false`
> `scripts/system/global/victory_resolver.gd:32` `var score = (player_data["score"] as BaseNumber).number`
> `scripts/system/global/victory_resolver.gd:33` `if highest_score == null or score > highest_score:`
> `scripts/system/global/victory_resolver.gd:34` `highest_score = score`
> `scripts/system/global/victory_resolver.gd:35` `winners = [id]`
> `scripts/system/global/victory_resolver.gd:36` `elif score == highest_score:`
> `scripts/system/global/victory_resolver.gd:37` `winners.append(id)`
> `scripts/system/global/victory_resolver.gd:38` ``
> `scripts/system/global/victory_resolver.gd:39` `if winners.size() > 1:`
> `scripts/system/global/victory_resolver.gd:40` `winners = _resolve_tie_by_miyama_battle(winners, battle_result)`
> `scripts/system/global/victory_resolver.gd:41` ``
> `scripts/system/global/victory_resolver.gd:42` `for id in winners:`
> `scripts/system/global/victory_resolver.gd:43` `var player_data = GameDataManager.get_player_data(id) as Dictionary`
> `scripts/system/global/victory_resolver.gd:44` `player_data["is_victory"] = true`
> `scripts/system/global/victory_resolver.gd:45` `return winners`
> `scripts/system/global/victory_resolver.gd:46` ``
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/game_progress.gd:232` | 直接实例调用 | `end_game(VictoryResolver.new().exec(last_battle_result))` |
| `scripts/system/global/game_progress.gd:336` | 直接实例调用 | `end_game(VictoryResolver.new().exec(last_battle_result))` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/section5_engine_test.gd:169`。
- **排除区（不计本类生产数）/debug**：无。

## 5. C 档：工具/纯查询（不是效果执行）（37 类）

### C — AndFunc
- **定义**：`scripts/system/operations/AndFunc.gd:1`。
- **公开入口**：`scripts/system/operations/AndFunc.gd:4` `func exec(a:bool, b:bool) -> bool:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:171`，`and_func → AndFunc`，分类 `QUERY_COMPARE`。依据：`"and_func" : { "category": QUERY_COMPARE, "class": "AndFunc", "summary": "逻辑与" },`。
- **正式数据 func_name 引用**：`and_func` **29** 条（递归计出现次数，不按卡文件去重）。证据：`data/attacks/class/foreigner_class/foreigner_class.json:99`; `data/events/origin/fate_battle/fate_battle.json:144`; `data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json:289`; `data/masters/00003_matou_shinji/00003_matou_shinji.json:284,296,587,599,949,961,1106,1185,1197,1302,1394,1406,1519,1573`; `data/masters/00004_matou_sakura/00004_matou_sakura.json:195,407`; `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json:472`; `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json:304`; `data/servants/00004_medusa/00004_medusa.json:409,541,580,836`; `data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json:562`; `data/servants/00008_angra_mainyu/00008_angra_mainyu.json:148,407,964`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/AndFunc.gd:4` `func exec(a:bool, b:bool) -> bool:`
> `scripts/system/operations/AndFunc.gd:5` ``
> `scripts/system/operations/AndFunc.gd:6` `return a and b`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/board_power_query.gd:169` | READERS 显式映射实例化 | `var reader = READERS[name].new() # 映射 and_func 在 18 行` |
| `scripts/system/global/board_power_query.gd:175` | READERS 实例入口 callv | `result = reader.exec.callv(params)` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### C — BoardHasEffect
- **定义**：`scripts/system/operations/BoardHasEffect.gd:1`。
- **公开入口**：`scripts/system/operations/BoardHasEffect.gd:8` `func exec(effect_name:String) -> bool:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:144`，`board_has_effect → BoardHasEffect`，分类 `QUERY_EFFECT`。依据：`"board_has_effect" : { "category": QUERY_EFFECT, "class": "BoardHasEffect", "summary": "全局面(局势+事件+区域buff)是否含效果名" },`。
- **正式数据 func_name 引用**：`board_has_effect` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：<span style="color:#d00000">🔴 是（查询上下文）：ability_is_disabled 先按 effect._time_points 识别阶段窗口，再直接查询此禁令；本类不执行效果/不派时点。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/effect_manager.gd:1280` `#统一的能力禁用入口：自动询问、手动请求与直接 ActivateEffect 都经 card_state_allows。`
> `scripts/system/global/effect_manager.gd:1281` `#阶段能力按显式 time_points 的阶段 mid 声明识别；不猜 shown 文案，`
> `scripts/system/global/effect_manager.gd:1282` `#不把纯被动事件、打出时或残留结算误当成使用卡牌。`
> `scripts/system/global/effect_manager.gd:1283` `func ability_is_disabled(effect:BaseEffect) -> bool:`
> `scripts/system/global/effect_manager.gd:1284` `if AbilityRestrictions.is_disabled(effect):`
> `scripts/system/global/effect_manager.gd:1285` `return true`
> `scripts/system/global/effect_manager.gd:1286` `if effect == null:`
> `scripts/system/global/effect_manager.gd:1287` `return true`
> `scripts/system/global/effect_manager.gd:1288` `var owner = effect.from.get_ref() if effect.from is WeakRef else effect.from`
> `scripts/system/global/effect_manager.gd:1289` `if not (owner is BaseHandCard):`
> `scripts/system/global/effect_manager.gd:1290` `return false`
> `scripts/system/global/effect_manager.gd:1291` `if not owner._attributes.has(Attributes.NOBLE_PHANTASM):`
> `scripts/system/global/effect_manager.gd:1292` `return false`
> `scripts/system/global/effect_manager.gd:1293` `var has_phase_window:bool = false`
> `scripts/system/global/effect_manager.gd:1294` `for phase in GameProgress.phases:`
> `scripts/system/global/effect_manager.gd:1295` `for prefix in [TimePoints.SELF_PREFIX, TimePoints.OTHERS_PREFIX, ""]:`
> `scripts/system/global/effect_manager.gd:1296` `if effect._time_points.has(prefix + str(phase["mid"])):`
> `scripts/system/global/effect_manager.gd:1297` `has_phase_window = true`
> `scripts/system/global/effect_manager.gd:1298` `if not has_phase_window:`
> `scripts/system/global/effect_manager.gd:1299` `return false`
> `scripts/system/global/effect_manager.gd:1300` `return BoardHasEffect.new().exec(ForbidNoblePhantasmEffect.EFFECT_NAME)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/effect_manager.gd:1300` | 直接实例调用 | `return BoardHasEffect.new().exec(ForbidNoblePhantasmEffect.EFFECT_NAME)` |
| `scripts/system/play_rules.gd:33` | 直接实例调用 | `if card._attributes.has(Attributes.NOBLE_PHANTASM) and BoardHasEffect.new().exec(ForbidNoblePhantasmEffect.EFFECT_NAME):` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/servant_skill_eight_magic_test.gd:29,80,90`。
- **排除区（不计本类生产数）/debug**：无。

### C — BuildCard
- **定义**：`scripts/system/operations/BuildCard.gd:1`。
- **公开入口**：`scripts/system/operations/BuildCard.gd:11` `func exec(card_data:Dictionary, card_type:String, owner = null, image_dir:String = "", card_back_type:String = ""):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:264`，`build_card → BuildCard`，分类 `CONSTRUCT`。依据：`"build_card" : { "category": CONSTRUCT, "class": "BuildCard", "summary": "按完整卡牌数据新建一张自定义牌，不放进区域" },`。
- **正式数据 func_name 引用**：`build_card` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/BuildCard.gd:11` `func exec(card_data:Dictionary, card_type:String, owner = null, image_dir:String = "", card_back_type:String = ""):`
> `scripts/system/operations/BuildCard.gd:12` ``
> `scripts/system/operations/BuildCard.gd:13` `if card_data == null or card_data.is_empty():`
> `scripts/system/operations/BuildCard.gd:14` `return null`
> `scripts/system/operations/BuildCard.gd:15` `#每次建牌用一份独立的数据：加载函数会往里写东西，同一块积木重复执行也不能互相影响`
> `scripts/system/operations/BuildCard.gd:16` `var data:Dictionary = card_data.duplicate(true)`
> `scripts/system/operations/BuildCard.gd:17` `var source = _source_object()`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/operations/FlipCardFace.gd:18` | 直接实例调用 | `var face = BuildCard.new().exec(card._faces[index], _card_type(card), card.from, card._card_img.get_base_dir())` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/create_card_test.gd:104,106`。
- **排除区（不计本类生产数）/debug**：无。

### C — CalculateNumber
- **定义**：`scripts/system/operations/CalculateNumber.gd:1`。
- **公开入口**：`scripts/system/operations/CalculateNumber.gd:7` `func exec(a, op:String, b = 0) -> BaseNumber:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:276`，`calculate_number → CalculateNumber`，分类 `MATH`。依据：`"calculate_number" : { "category": MATH, "class": "CalculateNumber", "summary": "运算后返回新数字，不改原值" },`。
- **正式数据 func_name 引用**：`calculate_number` **20** 条（递归计出现次数，不按卡文件去重）。证据：`data/attacks/basic/preparation/preparation.json:53`; `data/events/origin/desperate_measure/desperate_measure.json:98,111`; `data/events/origin/occupy_high_ground/occupy_high_ground.json:66`; `data/masters/00003_matou_shinji/00003_matou_shinji.json:684,1608`; `data/masters/00004_matou_sakura/00004_matou_sakura.json:780`; `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json:727,732`; `data/servants/00002_emiya/00002_emiya.json:150`; `data/servants/00003_cu_chulainn/00003_cu_chulainn.json:194,239`; `data/servants/00005_medea/00005_medea.json:58,71`; `data/servants/00007_heracles/00007_heracles.json:126,205,424,503,722,801`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/CalculateNumber.gd:7` `func exec(a, op:String, b = 0) -> BaseNumber:`
> `scripts/system/operations/CalculateNumber.gd:8` ``
> `scripts/system/operations/CalculateNumber.gd:9` `var left = _unwrap(a)`
> `scripts/system/operations/CalculateNumber.gd:10` `var right = _unwrap(b)`
> `scripts/system/operations/CalculateNumber.gd:11` `var result = 0`
> `scripts/system/operations/CalculateNumber.gd:12` `match op:`
> `scripts/system/operations/CalculateNumber.gd:13` `"+", "add":`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/board_power_query.gd:169` | READERS 显式映射实例化 | `var reader = READERS[name].new() # 映射 calculate_number 在 12 行` |
| `scripts/system/global/board_power_query.gd:175` | READERS 实例入口 callv | `result = reader.exec.callv(params)` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### C — CanGainMagic
- **定义**：`scripts/system/operations/CanGainMagic.gd:1`。
- **公开入口**：`scripts/system/operations/CanGainMagic.gd:9` `func exec(source:String = "", player_id:int = -1) -> bool:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:147`，`can_gain_magic → CanGainMagic`，分类 `QUERY_EFFECT`。依据：`"can_gain_magic" : { "category": QUERY_EFFECT, "class": "CanGainMagic", "summary": "能否从某来源获得魔力" },`。
- **正式数据 func_name 引用**：`can_gain_magic` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：<span style="color:#d00000">🔴 是（时点门控查询）：部署收益先直接查询，再决定是否调用会派魔力时点的 EditMagic；本类仍是纯判定。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/deploy_rules.gd:63` `#限制类效果按来源名查询（如"无法从魔术工房获得魔力"）：来源名由战区数据声明，`
> `scripts/system/deploy_rules.gd:64` `#不写死"workshop"；没有声明来源的席位只受总闸限制`
> `scripts/system/deploy_rules.gd:65` `var area := loc.get_from() as BaseMapArea`
> `scripts/system/deploy_rules.gd:66` `var source:String = area._magic_source if area != null else ""`
> `scripts/system/deploy_rules.gd:67` `if !CanGainMagic.new().exec(source, player_id):`
> `scripts/system/deploy_rules.gd:68` `return 0`
> `scripts/system/deploy_rules.gd:69` `EditMagic.new().exec(null, BaseNumber.new(gain.number), player_id)`
> `scripts/system/operations/EditMagic.gd:39` `else:`
> `scripts/system/operations/EditMagic.gd:40` `GameLog.record_resource_change("magic", id, before, magic.number)`
> `scripts/system/operations/EditMagic.gd:41` ``
> `scripts/system/operations/EditMagic.gd:42` `if delta > 0:`
> `scripts/system/operations/EditMagic.gd:43` `TimePointChecker.dynamic_time_point([TimePoints.MAGIC_ADD], id)`
> `scripts/system/operations/EditMagic.gd:44` `elif delta < 0:`
> `scripts/system/operations/EditMagic.gd:45` `TimePointChecker.dynamic_time_point([TimePoints.MAGIC_DECREASE], id)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/deploy_rules.gd:67` | 直接实例调用 | `if !CanGainMagic.new().exec(source, player_id):` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### C — CardCountsPower
- **定义**：`scripts/system/operations/CardCountsPower.gd:1`。
- **公开入口**：`scripts/system/operations/CardCountsPower.gd:9` `func exec(card:BaseHandCard, player_id:int = -1) -> bool:`; `scripts/system/operations/CardCountsPower.gd:29` `func counts_when_played(card:BaseHandCard, concealed:bool, player_id:int = -1) -> bool:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:102`，`card_counts_power → CardCountsPower`，分类 `QUERY_CARD`。依据：`"card_counts_power" : { "category": QUERY_CARD, "class": "CardCountsPower", "summary": "此牌是否计入合计威力" },`。
- **正式数据 func_name 引用**：`card_counts_power` **4** 条（递归计出现次数，不按卡文件去重）。证据：`data/masters/00004_matou_sakura/00004_matou_sakura.json:762`; `data/servants/00007_heracles/00007_heracles.json:182,480,778`。
- **是否涉及时点**：<span style="color:#d00000">🔴 是（时点链内的威力副作用判据）：出牌时点链在实际入场后直接查询决定 d.power.add，再处理词条与 PLAYED_CARD；本类自身只查询、不发时点。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/regular_play.gd:341` `TimePointChecker.dynamic_time_point([TimePoints.CARD_COST_CALCULATED], id, cards[state.index])`
> `scripts/system/regular_play.gd:342` `"enter":`
> `scripts/system/regular_play.gd:343` `var card:BaseHandCard = cards[state.index]`
> `scripts/system/regular_play.gd:344` `var hidden:bool = bool(hidden_flags[state.index])`
> `scripts/system/regular_play.gd:345` `var paid:float = 0.0 if hidden else cost(card, d)`
> `scripts/system/regular_play.gd:346` `if not d.is_magic_immune and paid > 0:`
> `scripts/system/regular_play.gd:347` `var before = d.magic.number`
> `scripts/system/regular_play.gd:348` `d.magic.minus(BaseNumber.new(paid))`
> `scripts/system/regular_play.gd:349` `GameLog.record_resource_payment("magic", id, before, d.magic.number, "regular_play", card)`
> `scripts/system/regular_play.gd:350` `card._is_concealed = hidden`
> `scripts/system/regular_play.gd:351` `card._is_activating = not hidden`
> `scripts/system/regular_play.gd:352` `_take_from_source(d, card)`
> `scripts/system/regular_play.gd:353` `d.played_cards.append(card)`
> `scripts/system/regular_play.gd:354` `if CardCountsPower.new().exec(card, id): d.power.add(card._power)`
> `scripts/system/regular_play.gd:355` `GameLog.record("play", id, -1, "", card, ["play"], {"card_name":card._name, "card_type":"attack" if card is BaseAttack else "skill", "extra":state.extra_cards.has(card), "concealed":hidden})`
> `scripts/system/regular_play.gd:356` `if hidden:`
> `scripts/system/regular_play.gd:357` `state.index += 1`
> `scripts/system/regular_play.gd:358` `state.phase = "cost"`
> `scripts/system/regular_play.gd:359` `else:`
> `scripts/system/regular_play.gd:360` `state.phase = "keywords"`
> `scripts/system/regular_play.gd:361` `"keywords":`
> `scripts/system/regular_play.gd:362` `state.phase = "reveal"`
> `scripts/system/regular_play.gd:363` `ApplyCardKeywords.new().exec(cards[state.index], id)`
> `scripts/system/regular_play.gd:364` `"reveal":`
> `scripts/system/regular_play.gd:365` `var card = cards[state.index]`
> `scripts/system/regular_play.gd:366` `state.index += 1`
> `scripts/system/regular_play.gd:367` `state.phase = "cost"`
> `scripts/system/regular_play.gd:368` `TimePointChecker.card_revealed(card)`
> `scripts/system/regular_play.gd:369` `"played":`
> `scripts/system/regular_play.gd:370` `#整批入场及 play 日志完成后才逐张派发，保持同时打出口径。`
> `scripts/system/regular_play.gd:371` `if state.index >= cards.size():`
> `scripts/system/regular_play.gd:372` `state.finish.call()`
> `scripts/system/regular_play.gd:373` `return`
> `scripts/system/regular_play.gd:374` `var card = cards[state.index]`
> `scripts/system/regular_play.gd:375` `state.index += 1`
> `scripts/system/regular_play.gd:376` `TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], id, card)`
> `scripts/system/operations/PlayAttack.gd:75` `(player_data["hand_cards"] as Array).erase(attack)`
> `scripts/system/operations/PlayAttack.gd:76` ``
> `scripts/system/operations/PlayAttack.gd:77` `#是否计入合计威力交给CardCountsPower判定(默认暗置牌不计，例外由卡上的效果声明)。`
> `scripts/system/operations/PlayAttack.gd:78` `#必须在入场后再判定，因为判定包含"是否在场上"这一条`
> `scripts/system/operations/PlayAttack.gd:79` `if CardCountsPower.new().exec(attack, id):`
> `scripts/system/operations/PlayAttack.gd:80` `var pl_power = player_data["power"] as BaseNumber`
> `scripts/system/operations/PlayAttack.gd:81` `pl_power.add(power)`
> `scripts/system/operations/PlayAttack.gd:82` ``
> `scripts/system/operations/PlayAttack.gd:83` `#日志：谁打出了哪张牌（供"本回合我打出了什么"这类历史查询）`
> `scripts/system/operations/PlayAttack.gd:84` `GameLog.record("play", id, -1, "", attack, ["play"],`
> `scripts/system/operations/PlayAttack.gd:85` `{"card_name": attack._name, "card_type": "attack", "extra": true})`
> `scripts/system/operations/PlayAttack.gd:86` `#词条带来的规则行为（如【真名解放】）在打出时点之前结算：`
> `scripts/system/operations/PlayAttack.gd:87` `#规则是"使用带此词条的牌后立即解放"，而有些牌监听 self_true_name_release，`
> `scripts/system/operations/PlayAttack.gd:88` `#顺序反了它们就接不上这次解放`
> `scripts/system/operations/PlayAttack.gd:89` `ApplyCardKeywords.new().exec(attack, id)`
> `scripts/system/operations/PlayAttack.gd:90` `TimePointChecker.card_revealed(attack)`
> `scripts/system/operations/PlayAttack.gd:91` `TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], id, attack)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/game_scene/battle_board_v2.gd:3103` | 直接构造 | `var counts := CardCountsPower.new()` |
| `scripts/game_scene/battle_board_v2.gd:3110` | 实例变量调用（new 在 3103 行） | `if counts.counts_when_played(card, bool(hidden[i]), _local_player_id):` |
| `scripts/game_scene/tactical_board_ui.gd:2224` | 直接构造 | `var counts = CardCountsPower.new()` |
| `scripts/game_scene/tactical_board_ui.gd:2231` | 实例变量调用（new 在 2224 行） | `if counts.counts_when_played(card, hidden, _local_player_id):` |
| `scripts/match/match_seat_query.gd:80` | 直接构造 | `var counts := CardCountsPower.new()` |
| `scripts/match/match_seat_query.gd:85` | 实例变量调用（new 在 80 行） | `if counts.counts_when_played(card, flags[index], seat):` |
| `scripts/system/global/board_power_query.gd:73` | 直接实例调用 | `return CardCountsPower.new().counts_when_played(card, bool(concealed_overrides.get(card, card._is_concealed)), player_id)` |
| `scripts/system/operations/AddAttack.gd:19` | 直接实例调用 | `if CardCountsPower.new().exec(attack, id):` |
| `scripts/system/operations/AddSkill.gd:22` | 直接实例调用 | `if CardCountsPower.new().exec(skill, id):` |
| `scripts/system/operations/CloseCard.gd:21` | 直接实例调用 | `if CardCountsPower.new().exec(card, id):` |
| `scripts/system/operations/EditCardPower.gd:12` | 直接构造 | `var counts_power = CardCountsPower.new()` |
| `scripts/system/operations/EditCardPower.gd:13` | 实例变量调用（new 在 12 行） | `var counted:bool = counts_power.exec(card, id)` |
| `scripts/system/operations/FlipCardFace.gd:76` | 直接实例调用 | `var counted:bool = id >= 0 and CardCountsPower.new().exec(card, id)` |
| `scripts/system/operations/GetSharedAttackAttribute.gd:15` | 直接构造 | `var counts_power := CardCountsPower.new()` |
| `scripts/system/operations/GetSharedAttackAttribute.gd:18` | 实例变量调用（new 在 15 行） | `if !(card is BaseAttack) or !counts_power.exec(card, id):` |
| `scripts/system/operations/ModifyAttackPowerByAttribute.gd:22` | 直接构造 | `var counts_power = CardCountsPower.new()` |
| `scripts/system/operations/ModifyAttackPowerByAttribute.gd:26` | 实例变量调用（new 在 22 行） | `if _match(attack, required_attributes, required_category, min_power) and counts_power.exec(attack, id):` |
| `scripts/system/operations/ModifyAttackPowerByAttribute.gd:33` | 实例变量调用（new 在 22 行） | `if card is BaseAttack and _match(card, required_attributes, required_category, min_power) and counts_power.exec(card, id):` |
| `scripts/system/operations/PlayAttack.gd:79` | 直接实例调用 | `if CardCountsPower.new().exec(attack, id):` |
| `scripts/system/operations/PlaySkill.gd:53` | 直接实例调用 | `if CardCountsPower.new().exec(skill, id):` |
| `scripts/system/operations/SetCardConcealed.gd:19` | 直接构造 | `var counts_power = CardCountsPower.new()` |
| `scripts/system/operations/SetCardConcealed.gd:20` | 实例变量调用（new 在 19 行） | `var counted_before:bool = counts_power.exec(handcard, id)` |
| `scripts/system/operations/SetCardConcealed.gd:22` | 实例变量调用（new 在 19 行） | `var counted_after:bool = counts_power.exec(handcard, id)` |
| `scripts/system/operations/SyncPower.gd:14` | 直接构造 | `var counts_power = CardCountsPower.new()` |
| `scripts/system/operations/SyncPower.gd:16` | 实例变量调用（new 在 14 行） | `if card is BaseHandCard and counts_power.exec(card, id):` |
| `scripts/system/operations/ZeroAttributePower.gd:15` | 直接构造 | `var counts_power = CardCountsPower.new()` |
| `scripts/system/operations/ZeroAttributePower.gd:19` | 实例变量调用（new 在 15 行） | `if !counts_power.exec(card, id):` |
| `scripts/system/power_sources.gd:34` | 直接实例调用 | `if card is BaseHandCard and CardCountsPower.new().exec(card, player_id):` |
| `scripts/system/regular_play.gd:354` | 直接实例调用 | `if CardCountsPower.new().exec(card, id): d.power.add(card._power)` |
- **排除区（不计本类生产数）/测试/诊断**：`newtests/four_kind_real_execution_test.gd:107,111`; `tests/reported_board_power_test.gd:65,67,69,70,71,73,77`。
- **排除区（不计本类生产数）/debug**：无。

### C — CardHasEffect
- **定义**：`scripts/system/operations/CardHasEffect.gd:1`。
- **公开入口**：`scripts/system/operations/CardHasEffect.gd:7` `func exec(effect_name:String, card:BaseCard) -> bool:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:103`，`card_has_effect → CardHasEffect`，分类 `QUERY_CARD`。依据：`"card_has_effect" : { "category": QUERY_CARD, "class": "CardHasEffect", "summary": "卡上是否有指定效果名" },`。
- **正式数据 func_name 引用**：`card_has_effect` **1** 条（递归计出现次数，不按卡文件去重）。证据：`data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json:625`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/CardHasEffect.gd:7` `func exec(effect_name:String, card:BaseCard) -> bool:`
> `scripts/system/operations/CardHasEffect.gd:8` ``
> `scripts/system/operations/CardHasEffect.gd:9` `if card == null:`
> `scripts/system/operations/CardHasEffect.gd:10` `return false`
> `scripts/system/operations/CardHasEffect.gd:11` `for eff in card._effects:`
> `scripts/system/operations/CardHasEffect.gd:12` `if eff is BaseEffect and eff._name == effect_name:`
> `scripts/system/operations/CardHasEffect.gd:13` `return true`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/operations/CardCountsPower.gd:36` | 直接构造 | `var has_effect = CardHasEffect.new()` |
| `scripts/system/operations/CardCountsPower.gd:37` | 实例变量调用（new 在 36 行） | `if has_effect.exec(NeverCountsPowerEffect.EFFECT_NAME, card):` |
| `scripts/system/operations/CardCountsPower.gd:41` | 实例变量调用（new 在 36 行） | `return has_effect.exec(CountsPowerWhileConcealedEffect.EFFECT_NAME, card)` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### C — CloneObject
- **定义**：`scripts/system/operations/CloneObject.gd:1`。
- **公开入口**：`scripts/system/operations/CloneObject.gd:5` `func exec(object):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:262`，`clone_object → CloneObject`，分类 `CONSTRUCT`。依据：`"clone_object" : { "category": CONSTRUCT, "class": "CloneObject", "summary": "复制对象，不放进区域" },`。
- **正式数据 func_name 引用**：`clone_object` **3** 条（递归计出现次数，不按卡文件去重）。证据：`data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json:325,367`; `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json:80`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/CloneObject.gd:5` `func exec(object):`
> `scripts/system/operations/CloneObject.gd:6` `return CloneContext.new().copy(object)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/game_progress.gd:200` | 直接实例调用 | `cloned.append(CloneObject.new().exec(card))` |
| `scripts/system/global/master_manager.gd:30` | 直接实例调用 | `var card = CloneObject.new().exec(template)` |
| `scripts/system/global/master_manager.gd:48` | 直接实例调用 | `var card = CloneObject.new().exec(template) as BaseCard` |
| `scripts/system/global/situation_resolver.gd:77` | 直接实例调用 | `return CloneObject.new().exec(template) as BaseSituation` |
| `scripts/system/global/situation_resolver.gd:81` | 直接实例调用 | `return CloneObject.new().exec(template) as BaseSituation` |
| `scripts/system/map_data.gd:156` | 直接实例调用 | `deck.append(CloneObject.new().exec(template))` |
| `scripts/system/operations/ActivateEffect.gd:16` | 直接实例调用 | `target = CloneObject.new().exec(effect) as BaseEffect` |
| `scripts/system/operations/AddEventFromDeck.gd:32` | 直接实例调用 | `var event = CloneObject.new().exec(template) as BaseEvent` |
| `scripts/system/operations/CreateCard.gd:41` | 直接实例调用 | `return CloneObject.new().exec(spell) if spell != null else null` |
| `scripts/system/operations/CreateCard.gd:49` | 直接实例调用 | `return CloneObject.new().exec(template)` |
- **排除区（不计本类生产数）/测试/诊断**：`newtests/action_completion_public_contract_test.gd:67`; `newtests/current_card_info_ui_contract_test.gd:78`; `newtests/round71_shared_discard_browsing_test.gd:182,191,192,230,241`; `newtests/round74_shared_out_of_game_test.gd:21,28,30,200,202`; `tests/_probe_conceal.gd:63`; `tests/_probe_conceal_click.gd:101`; `tests/angra_mainyu_test.gd:10`; `tests/area_lock_window_test.gd:105`; `tests/artoria_skills_test.gd:38`; `tests/battle_board_activation_command_test.gd:46`; `tests/battle_event_discard_test.gd:41`; `tests/battle_score_report_test.gd:75`; `tests/battle_scroll_test.gd:93,126,138`; `tests/battle_source_board_projection_test.gd:98,133,137`; `tests/bellerophon_rules_test.gd:29,32`; `tests/card_audit_probe.gd:100`; `tests/card_choice_source_command_test.gd:40`; `tests/card_effect_runtime_test.gd:52,133,325,337,418,433`; `tests/card_history_test.gd:48,66,79,90,91,116,129,144`; `tests/card_keyword_test.gd:75,83,122`; `tests/card_revealed_test.gd:76,86,87,114`; `tests/card_selection_owner_test.gd:49`; `tests/card_zone_browser_test.gd:264,273,308`; `tests/climax_gated_ability_test.gd:61`; `tests/command_spell_test.gd:67,293`; `tests/current_skill_group_test.gd:50`; `tests/effect_body_fill2_test.gd:41,106`; `tests/effect_body_fill_test.gd:41,63`; `tests/fd39_operations_test.gd:123`; `tests/hand_fan_arc_test.gd:48`; `tests/hand_fan_limits_test.gd:34`; `tests/held_cards_test.gd:78,95`; `tests/held_cards_window_test.gd:89`; `tests/held_skill_input_test.gd:53`; `tests/ichi_no_tachi_test.gd:60,74,185,194`; `tests/local_spell_restore_test.gd:56,66`; `tests/mana_spend_test.gd:89`; `tests/masters_audit_fix_test.gd:27,40,98,106,120,121`; `tests/misc_rules_fix_test.gd:155,178`; `tests/net_v2_area_window_test.gd:13,15,18`; `tests/newspecial_spell_materialization_test.gd:31,128`; `tests/ni_no_tachi_test.gd:28`; `tests/overseer_knowledge_test.gd:8,9,23,30`; `tests/overseer_window_test.gd:10`; `tests/pending_board_power_test.gd:58,65,227`; `tests/piercing_cost_test.gd:14,15`; `tests/played_stack_test.gd:89,197`; `tests/post_battle_choice_test.gd:64`; `tests/private_knowledge_corrosion_test.gd:14,16,99`; `tests/refactor_net_area_diagnostic.gd:13,15,18`; `tests/reported_activation_test.gd:23,140`; `tests/reported_board_power_test.gd:97,121,137,145,147`; `tests/residue_pile_test.gd:51,59`; `tests/round29-shared-presentation_test.gd:244,246`; `tests/round70_declared_card_backs_test.gd:73`; `tests/san_no_tachi_test.gd:9,35,36,47,48`; `tests/san_no_tachi_window_test.gd:58,59,60`; `tests/unlimited_blade_activation_test.gd:127,130,133,137,289`; `tests/zoom_and_desc_test.gd:87,182,211`。
- **排除区（不计本类生产数）/debug**：`scripts/debug/debug_adapters/debug_board_adapter.gd:79`; `scripts/debug/debug_adapters/debug_card_adapter.gd:127`; `scripts/debug/debug_adapters/debug_player_adapter.gd:117`。

### C — GetAllPlayersId
- **定义**：`scripts/system/operations/GetAllPlayersId.gd:1`。
- **公开入口**：`scripts/system/operations/GetAllPlayersId.gd:4` `func exec():`。
- **注册表**：有；`scripts/system/global/all_operations.gd:52`，`get_all_players_id → GetAllPlayersId`，分类 `QUERY_PLAYER`。依据：`"get_all_players_id" : { "category": QUERY_PLAYER, "class": "GetAllPlayersId", "summary": "全部玩家id" },`。
- **正式数据 func_name 引用**：`get_all_players_id` **1** 条（递归计出现次数，不按卡文件去重）。证据：`data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json:408`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/GetAllPlayersId.gd:4` `func exec():`
> `scripts/system/operations/GetAllPlayersId.gd:5` ``
> `scripts/system/operations/GetAllPlayersId.gd:6` `return GameData.player_data_library.keys()`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/operations/ChangePlOrder.gd:10` | 直接实例调用 | `var pl_ids = GetAllPlayersId.new().exec()` |
| `scripts/system/operations/ChangePlOrder.gd:32` | 直接实例调用 | `var pl_ids = GetAllPlayersId.new().exec()` |
| `scripts/system/operations/GetPlIdUsingEff.gd:14` | 直接实例调用 | `var pl_ids = GetAllPlayersId.new().exec() as Array` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### C — GetAttackPrintedPower
- **定义**：`scripts/system/operations/GetAttackPrintedPower.gd:1`。
- **公开入口**：`scripts/system/operations/GetAttackPrintedPower.gd:4` `func exec(attack:BaseAttack):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:96`，`get_attack_printed_power → GetAttackPrintedPower`，分类 `QUERY_CARD`。依据：`"get_attack_printed_power" : { "category": QUERY_CARD, "class": "GetAttackPrintedPower", "summary": "攻击印刷威力" },`。
- **正式数据 func_name 引用**：`get_attack_printed_power` **1** 条（递归计出现次数，不按卡文件去重）。证据：`data/events/origin/fate_battle/fate_battle.json:112`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/GetAttackPrintedPower.gd:4` `func exec(attack:BaseAttack):`
> `scripts/system/operations/GetAttackPrintedPower.gd:5` ``
> `scripts/system/operations/GetAttackPrintedPower.gd:6` `return attack.numbers[1]`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/board_power_query.gd:169` | READERS 显式映射实例化 | `var reader = READERS[name].new() # 映射 get_attack_printed_power 在 24 行` |
| `scripts/system/global/board_power_query.gd:175` | READERS 实例入口 callv | `result = reader.exec.callv(params)` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### C — GetCardsByAttributesFrArr
- **定义**：`scripts/system/operations/GetCardsByAttributesFrArr.gd:1`。
- **公开入口**：`scripts/system/operations/GetCardsByAttributesFrArr.gd:6` `func exec(attributes:Array, cards:Array, require_all:bool = false) -> Array:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:106`，`get_cards_by_attributes_fr_arr → GetCardsByAttributesFrArr`，分类 `QUERY_CARD`。依据：`"get_cards_by_attributes_fr_arr" : { "category": QUERY_CARD, "class": "GetCardsByAttributesFrArr", "summary": "数组中按属性筛卡" },`。
- **正式数据 func_name 引用**：`get_cards_by_attributes_fr_arr` **5** 条（递归计出现次数，不按卡文件去重）。证据：`data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json:485`; `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json:461`; `data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json:139,196`; `data/servants/00004_medusa/00004_medusa.json:950`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/GetCardsByAttributesFrArr.gd:6` `func exec(attributes:Array, cards:Array, require_all:bool = false) -> Array:`
> `scripts/system/operations/GetCardsByAttributesFrArr.gd:7` ``
> `scripts/system/operations/GetCardsByAttributesFrArr.gd:8` `var got_cards:Array = []`
> `scripts/system/operations/GetCardsByAttributesFrArr.gd:9` `if cards == null:`
> `scripts/system/operations/GetCardsByAttributesFrArr.gd:10` `return got_cards`
> `scripts/system/operations/GetCardsByAttributesFrArr.gd:11` `var has_attribute = HasAttribute.new()`
> `scripts/system/operations/GetCardsByAttributesFrArr.gd:12` `for card in cards:`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/effect_manager.gd:1700` | 直接实例调用 | `arr = GetCardsByAttributesFrArr.new().exec(wanted, arr)` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### C — GetEffSourceCard
- **定义**：`scripts/system/operations/GetEffSourceCard.gd:1`。
- **公开入口**：`scripts/system/operations/GetEffSourceCard.gd:6` `func exec(effect:BaseEffect = null):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:101`，`get_eff_source_card → GetEffSourceCard`，分类 `QUERY_CARD`。依据：`"get_eff_source_card" : { "category": QUERY_CARD, "class": "GetEffSourceCard", "summary": "当前效果所属卡" },`。
- **正式数据 func_name 引用**：`get_eff_source_card` **35** 条（递归计出现次数，不按卡文件去重）。证据：`data/attacks/class/avenger_class/avenger_class.json:38,162`; `data/attacks/class/foreigner_class/foreigner_class.json:44`; `data/events/origin/contain_third_party/contain_third_party.json:33,103`; `data/events/origin/cooperation/cooperation.json:28`; `data/events/origin/desperate_measure/desperate_measure.json:38`; `data/events/origin/fate_battle/fate_battle.json:33`; `data/events/origin/glorious_duel/glorious_duel.json:28`; `data/events/origin/holy_ground/holy_ground.json:28`; `data/events/origin/ley_line/ley_line.json:29`; `data/events/origin/occupy_high_ground/occupy_high_ground.json:22`; `data/events/origin/sacrifice_ground/sacrifice_ground.json:28`; `data/events/origin/sneak_attack/sneak_attack.json:33`; `data/events/origin/strength_test/strength_test.json:28`; `data/events/origin/suppressive_fire/suppressive_fire.json:28`; `data/events/origin/treacherous_terrain/treacherous_terrain.json:28`; `data/masters/00001_emiya_shirou/00001_emiya_shirou.json:237`; `data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json:353,1343,1409`; `data/masters/00003_matou_shinji/00003_matou_shinji.json:850,1046,1242,1459`; `data/masters/00004_matou_sakura/00004_matou_sakura.json:939`; `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json:658`; `data/servants/00002_emiya/00002_emiya.json:435`; `data/servants/00003_cu_chulainn/00003_cu_chulainn.json:335`; `data/servants/00005_medea/00005_medea.json:84`; `data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json:81,192`; `data/servants/00007_heracles/00007_heracles.json:58,356,654`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/GetEffSourceCard.gd:6` `func exec(effect:BaseEffect = null):`
> `scripts/system/operations/GetEffSourceCard.gd:7` ``
> `scripts/system/operations/GetEffSourceCard.gd:8` `var eff = effect`
> `scripts/system/operations/GetEffSourceCard.gd:9` `if eff == null:`
> `scripts/system/operations/GetEffSourceCard.gd:10` `eff = EffectManager.activating_eff`
> `scripts/system/operations/GetEffSourceCard.gd:11` `if eff == null:`
> `scripts/system/operations/GetEffSourceCard.gd:12` `return null`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/match/effect_checkpoint.gd:20` | 直接实例调用 | `var source = GetEffSourceCard.new().exec(effect)` |
| `scripts/match/effect_checkpoint.gd:21` | 直接实例调用 | `if source == null and effect != root: source = GetEffSourceCard.new().exec(root)` |
| `scripts/net/authority/match_authority.gd:314` | 直接实例调用 | `var source = GetEffSourceCard.new().exec(effect)` |
| `scripts/net/authority/match_authority.gd:317` | 直接实例调用 | `source = GetEffSourceCard.new().exec(origin)` |
| `scripts/system/global/effect_manager.gd:1689` | 直接实例调用 | `arr.erase(GetEffSourceCard.new().exec(effect))` |
| `scripts/system/operations/BuildEffect.gd:13` | 直接实例调用 | `owner = GetEffSourceCard.new().exec()` |
| `scripts/system/operations/CreateCard.gd:21` | 直接实例调用 | `owner = GetEffSourceCard.new().exec()` |
| `scripts/system/operations/EditCardAttributes.gd:9` | 直接实例调用 | `target = GetEffSourceCard.new().exec()` |
| `scripts/system/operations/EditCardCost.gd:10` | 直接实例调用 | `var source = GetEffSourceCard.new().exec()` |
| `scripts/system/operations/GetCardAttributes.gd:10` | 直接实例调用 | `target = GetEffSourceCard.new().exec()` |
| `scripts/system/operations/GetEffectNumber.gd:11` | 直接实例调用 | `target = GetEffSourceCard.new().exec()` |
| `scripts/system/operations/HasAttribute.gd:10` | 直接实例调用 | `target = GetEffSourceCard.new().exec()` |
| `scripts/system/operations/RestrictAbilities.gd:6` | 直接实例调用 | `if source == null: source = GetEffSourceCard.new().exec()` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### C — GetEffectiveLocationBenefit
- **定义**：`scripts/system/operations/GetEffectiveLocationBenefit.gd:1`。
- **公开入口**：`scripts/system/operations/GetEffectiveLocationBenefit.gd:15` `func exec(player_id:int = -1) -> int:`; `scripts/system/operations/GetEffectiveLocationBenefit.gd:42` `static func current_benefit(loc) -> int:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:119`，`get_effective_location_benefit → GetEffectiveLocationBenefit`，分类 `QUERY_MAP`。依据：`"get_effective_location_benefit" : { "category": QUERY_MAP, "class": "GetEffectiveLocationBenefit", "summary": "当前实际享有的地利(部署才算)" },`。
- **正式数据 func_name 引用**：`get_effective_location_benefit` **1** 条（递归计出现次数，不按卡文件去重）。证据：`data/events/origin/occupy_high_ground/occupy_high_ground.json:57`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/GetEffectiveLocationBenefit.gd:15` `func exec(player_id:int = -1) -> int:`
> `scripts/system/operations/GetEffectiveLocationBenefit.gd:16` ``
> `scripts/system/operations/GetEffectiveLocationBenefit.gd:17` `var id = EffectManager.resolve_player_id(player_id)`
> `scripts/system/operations/GetEffectiveLocationBenefit.gd:18` `var loc = GetLocation.new().exec(id)`
> `scripts/system/operations/GetEffectiveLocationBenefit.gd:19` `if loc == null:`
> `scripts/system/operations/GetEffectiveLocationBenefit.gd:20` `return 0`
> `scripts/system/operations/GetEffectiveLocationBenefit.gd:21` `var area := loc.get_from() as BaseMapArea`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/game_scene/battle_board_v2.gd:806` | 类/静态公开入口 | `var benefit := GetEffectiveLocationBenefit.current_benefit(loc)` |
| `scripts/game_scene/battle_board_v2.gd:5425` | 类/静态公开入口 | `var bn: int = GetEffectiveLocationBenefit.current_benefit(target_loc)` |
| `scripts/game_scene/tactical_board_ui.gd:2450` | 类/静态公开入口 | `var benefit: int = GetEffectiveLocationBenefit.current_benefit(loc)` |
| `scripts/match/view_builder.gd:94` | 类/静态公开入口 | `locations.append({"id": ids.id_for(loc), "magic": number(loc._magic), "benefit": GetEffectiveLocationBenefit.current_benefit(loc), "capacity": loc._pl_num_limit, "players": loc._players.duplicate()})` |
| `scripts/system/global/board_power_query.gd:169` | READERS 显式映射实例化 | `var reader = READERS[name].new() # 映射 get_effective_location_benefit 在 22 行` |
| `scripts/system/global/board_power_query.gd:175` | READERS 实例入口 callv | `result = reader.exec.callv(params)` |
| `scripts/system/operations/GetPlayerTotalPower.gd:46` | 直接实例调用 | `var benefit = GetEffectiveLocationBenefit.new().exec(id)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/battle_broadcast_test.gd:57,78`; `tests/battle_score_report_test.gd:68`; `tests/bellerophon_edges_test.gd:44,46,48,50,58`; `tests/bellerophon_rules_test.gd:78,85,90`; `tests/bellerophon_window_test.gd:59`; `tests/deploy_rules_test.gd:57,59`; `tests/fd39_operations_test.gd:484,487`; `tests/location_benefit_test.gd:33,37,51,56,63,76,79`。
- **排除区（不计本类生产数）/debug**：`scripts/debug/debug_adapters/debug_map_adapter.gd:21`; `scripts/debug/debug_validate.gd:87`。

### C — GetLocation
- **定义**：`scripts/system/operations/GetLocation.gd:1`。
- **公开入口**：`scripts/system/operations/GetLocation.gd:4` `func exec(player_id:int = -1):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:116`，`get_location → GetLocation`，分类 `QUERY_MAP`。依据：`"get_location" : { "category": QUERY_MAP, "class": "GetLocation", "summary": "玩家地点" },`。
- **正式数据 func_name 引用**：`get_location` **4** 条（递归计出现次数，不按卡文件去重）。证据：`data/attacks/basic/preparation/preparation.json:39`; `data/servants/00002_emiya/00002_emiya.json:136`; `data/servants/00004_medusa/00004_medusa.json:520,754`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/GetLocation.gd:4` `func exec(player_id:int = -1):`
> `scripts/system/operations/GetLocation.gd:5` ``
> `scripts/system/operations/GetLocation.gd:6` `player_id = EffectManager.resolve_player_id(player_id)`
> `scripts/system/operations/GetLocation.gd:7` `var player_data:Dictionary = GameDataManager.get_player_data(player_id)`
> `scripts/system/operations/GetLocation.gd:8` `return player_data["location"]`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/area_action_rules.gd:56` | 直接实例调用 | `var origin: BaseLocation = GetLocation.new().exec(trigger_id)` |
| `scripts/system/global/effect_manager.gd:809` | 直接实例调用 | `var origin:BaseLocation = GetLocation.new().exec(effect._trigger_player_id)` |
| `scripts/system/global/effect_manager.gd:1872` | 直接实例调用 | `var origin:BaseLocation = GetLocation.new().exec(effect._trigger_player_id)` |
| `scripts/system/operations/GetEffectiveLocationBenefit.gd:18` | 直接实例调用 | `var loc = GetLocation.new().exec(id)` |
| `scripts/system/operations/GetLocationMapArea.gd:10` | 直接实例调用 | `loc = GetLocation.new().exec(player_id)` |
| `scripts/system/operations/GetPlayerLocationBenefit.gd:11` | 直接实例调用 | `var loc = GetLocation.new().exec(player_id)` |
| `scripts/system/operations/IsEngaged.gd:17` | 直接实例调用 | `var loc = GetLocation.new().exec(id)` |
| `scripts/system/operations/IsEngaged.gd:32` | 直接实例调用 | `var other_loc = GetLocation.new().exec(other_id)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/area_lock_window_test.gd:89,115,122`; `tests/bellerophon_edges_test.gd:19,24,69`; `tests/bellerophon_rules_test.gd:75,76`; `tests/bellerophon_window_test.gd:70`; `tests/deploy_rules_test.gd:56`; `tests/engagement_test.gd:68,70,83,86,134,137`; `tests/location_benefit_test.gd:32,62`; `tests/misc_rules_fix_test.gd:126,129,161,170,193,199,218`; `tests/surveil_window_test.gd:54,71`。
- **排除区（不计本类生产数）/debug**：无。

### C — GetMapAreaByName
- **定义**：`scripts/system/operations/GetMapAreaByName.gd:1`。
- **公开入口**：`scripts/system/operations/GetMapAreaByName.gd:5` `func exec(area_name:String):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:123`，`get_map_area_by_name → GetMapAreaByName`，分类 `QUERY_MAP`。依据：`"get_map_area_by_name" : { "category": QUERY_MAP, "class": "GetMapAreaByName", "summary": "按名取区域" },`。
- **正式数据 func_name 引用**：`get_map_area_by_name` **31** 条（递归计出现次数，不按卡文件去重）。证据：`data/masters/00003_matou_shinji/00003_matou_shinji.json:1619`; `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json:609,651`; `data/situations/origin/battle_of_shinto/battle_of_shinto.json:25`; `data/situations/origin/calm_before_storm/calm_before_storm.json:30,46`; `data/situations/origin/curse_of_angra_mainyu/curse_of_angra_mainyu.json:30,46`; `data/situations/origin/gate_of_hell/gate_of_hell.json:53,73,93,156`; `data/situations/origin/heavens_feel/heavens_feel.json:53,73,93,156`; `data/situations/origin/hope_for_future/hope_for_future.json:30,46`; `data/situations/origin/killer_in_miyama/killer_in_miyama.json:25`; `data/situations/origin/night_of_fate/night_of_fate.json:53,73`; `data/situations/origin/outrage/outrage.json:30,46`; `data/situations/origin/perfect_flow/perfect_flow.json:30,46`; `data/situations/origin/shadow_of_angra_mainyu/shadow_of_angra_mainyu.json:30,46`; `data/situations/origin/substance_of_angra_mainyu/substance_of_angra_mainyu.json:30,46`; `data/situations/origin/turnaround/turnaround.json:25,42`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/GetMapAreaByName.gd:5` `func exec(area_name:String):`
> `scripts/system/operations/GetMapAreaByName.gd:6` ``
> `scripts/system/operations/GetMapAreaByName.gd:7` `for area:BaseMapArea in MapData.areas:`
> `scripts/system/operations/GetMapAreaByName.gd:8` `if area._area_name == area_name:`
> `scripts/system/operations/GetMapAreaByName.gd:9` `return area`
> `scripts/system/operations/GetMapAreaByName.gd:10` `return null`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/board_power_query.gd:169` | READERS 显式映射实例化 | `var reader = READERS[name].new() # 映射 get_map_area_by_name 在 9 行` |
| `scripts/system/global/board_power_query.gd:175` | READERS 实例入口 callv | `result = reader.exec.callv(params)` |
| `scripts/system/global/event_resolver.gd:23` | 直接实例调用 | `var area = GetMapAreaByName.new().exec(p["area_name"])` |
| `scripts/system/operations/AddMapArea.gd:27` | 直接实例调用 | `link_to = GetMapAreaByName.new().exec(str(data.get("linked_map_area_name", "")))` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/effect_body_fill2_test.gd:118`; `tests/effect_execution_input_contract_test.gd:51`。
- **排除区（不计本类生产数）/debug**：无。

### C — GetMoveTargetLocation
- **定义**：`scripts/system/operations/GetMoveTargetLocation.gd:1`。
- **公开入口**：`scripts/system/operations/GetMoveTargetLocation.gd:10` `func exec(target_area:BaseMapArea, ignore_limit:bool = false):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:128`，`get_move_target_location → GetMoveTargetLocation`，分类 `QUERY_MAP`。依据：`"get_move_target_location" : { "category": QUERY_MAP, "class": "GetMoveTargetLocation", "summary": "常规移动落点(满了返回null)" },`。
- **正式数据 func_name 引用**：`get_move_target_location` **1** 条（递归计出现次数，不按卡文件去重）。证据：`data/servants/00004_medusa/00004_medusa.json:446`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/GetMoveTargetLocation.gd:10` `func exec(target_area:BaseMapArea, ignore_limit:bool = false):`
> `scripts/system/operations/GetMoveTargetLocation.gd:11` `if target_area == null:`
> `scripts/system/operations/GetMoveTargetLocation.gd:12` `return null`
> `scripts/system/operations/GetMoveTargetLocation.gd:13` `for loc:BaseLocation in target_area._locations:`
> `scripts/system/operations/GetMoveTargetLocation.gd:14` `if !loc._will_move_to:`
> `scripts/system/operations/GetMoveTargetLocation.gd:15` `continue`
> `scripts/system/operations/GetMoveTargetLocation.gd:16` `if ignore_limit or loc._pl_num_limit == -1 or loc._players.size() < loc._pl_num_limit:`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/area_action_rules.gd:96` | 直接实例调用 | `if target_area == MapData.scout and GetMoveTargetLocation.new().exec(target_area) == null:` |
| `scripts/system/area_action_rules.gd:100` | 直接实例调用 | `if GetMoveTargetLocation.new().exec(target_area) == null:` |
| `scripts/system/operations/MoveLocation.gd:58` | 直接实例调用 | `var target_location:BaseLocation = GetMoveTargetLocation.new().exec(area, ignore_limit)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/bellerophon_composition_test.gd:28`; `tests/debug_console_test.gd:88`; `tests/deploy_rules_test.gd:22`。
- **排除区（不计本类生产数）/debug**：无。

### C — GetPlCommandSpellOutGame
- **定义**：`scripts/system/operations/GetPlCommandSpellOutGame.gd:1`。
- **公开入口**：`scripts/system/operations/GetPlCommandSpellOutGame.gd:4` `func exec(player_id:int = -1):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:88`，`get_pl_command_spell_out_game → GetPlCommandSpellOutGame`，分类 `QUERY_ZONE`。依据：`"get_pl_command_spell_out_game" : { "category": QUERY_ZONE, "class": "GetPlCommandSpellOutGame", "summary": "移出游戏的令咒" },`。
- **正式数据 func_name 引用**：`get_pl_command_spell_out_game` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/GetPlCommandSpellOutGame.gd:4` `func exec(player_id:int = -1):`
> `scripts/system/operations/GetPlCommandSpellOutGame.gd:5` ``
> `scripts/system/operations/GetPlCommandSpellOutGame.gd:6` `player_id = EffectManager.resolve_player_id(player_id)`
> `scripts/system/operations/GetPlCommandSpellOutGame.gd:7` `var player_data:Dictionary = GameDataManager.get_player_data(player_id)`
> `scripts/system/operations/GetPlCommandSpellOutGame.gd:8` `return player_data["out_of_game"]["command_spell"]`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/game_scene/tactical_board_ui.gd:464` | 直接实例调用 | `var cards: Array = GetPlCommandSpellOutGame.new().exec(_local_player_id)` |
| `scripts/system/action_rules.gd:59` | 直接实例调用 | `for card in GetPlCommandSpellOutGame.new().exec(player_id):` |
| `scripts/system/ai/temp/dummy_bot.gd:122` | 直接实例调用 | `for card in GetPlCommandSpellOutGame.new().exec(bot_id):` |
- **排除区（不计本类生产数）/测试/诊断**：`newtests/four_kind_real_execution_test.gd:178`; `tests/engagement_test.gd:114`; `tests/net_full_game_test.gd:59`。
- **排除区（不计本类生产数）/debug**：无。

### C — GetPlayerLocationBenefit
- **定义**：`scripts/system/operations/GetPlayerLocationBenefit.gd:1`。
- **公开入口**：`scripts/system/operations/GetPlayerLocationBenefit.gd:9` `func exec(player_id:int = -1) -> int:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:120`，`get_player_location_benefit → GetPlayerLocationBenefit`，分类 `QUERY_MAP`。依据：`"get_player_location_benefit" : { "category": QUERY_MAP, "class": "GetPlayerLocationBenefit", "summary": "玩家所在地印刷地利数" },`。
- **正式数据 func_name 引用**：`get_player_location_benefit` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/GetPlayerLocationBenefit.gd:9` `func exec(player_id:int = -1) -> int:`
> `scripts/system/operations/GetPlayerLocationBenefit.gd:10` ``
> `scripts/system/operations/GetPlayerLocationBenefit.gd:11` `var loc = GetLocation.new().exec(player_id)`
> `scripts/system/operations/GetPlayerLocationBenefit.gd:12` `if loc == null:`
> `scripts/system/operations/GetPlayerLocationBenefit.gd:13` `return 0`
> `scripts/system/operations/GetPlayerLocationBenefit.gd:14` `var benefit:BaseNumber = loc._printed_benefit`
> `scripts/system/operations/GetPlayerLocationBenefit.gd:15` `if benefit == null:`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/board_power_query.gd:169` | READERS 显式映射实例化 | `var reader = READERS[name].new() # 映射 get_player_location_benefit 在 23 行` |
| `scripts/system/global/board_power_query.gd:175` | READERS 实例入口 callv | `result = reader.exec.callv(params)` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### C — GetPlayerPlayedCards
- **定义**：`scripts/system/operations/GetPlayerPlayedCards.gd:1`。
- **公开入口**：`scripts/system/operations/GetPlayerPlayedCards.gd:4` `func exec(player_id:int = -1):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:72`，`get_player_played_cards → GetPlayerPlayedCards`，分类 `QUERY_ZONE`。依据：`"get_player_played_cards" : { "category": QUERY_ZONE, "class": "GetPlayerPlayedCards", "summary": "场上已打出" },`。
- **正式数据 func_name 引用**：`get_player_played_cards` **12** 条（递归计出现次数，不按卡文件去重）。证据：`data/events/origin/fate_battle/fate_battle.json:68`; `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json:581,672`; `data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json:78,189`; `data/servants/00004_medusa/00004_medusa.json:943`; `data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json:459`; `data/servants/00007_heracles/00007_heracles.json:68,366,664`; `data/servants/00008_angra_mainyu/00008_angra_mainyu.json:593,716`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/GetPlayerPlayedCards.gd:4` `func exec(player_id:int = -1):`
> `scripts/system/operations/GetPlayerPlayedCards.gd:5` ``
> `scripts/system/operations/GetPlayerPlayedCards.gd:6` `var id = EffectManager.resolve_player_id(player_id)`
> `scripts/system/operations/GetPlayerPlayedCards.gd:7` `var player_data:Dictionary = GameDataManager.get_player_data(id)`
> `scripts/system/operations/GetPlayerPlayedCards.gd:8` `return player_data["played_cards"]`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/board_power_query.gd:169` | READERS 显式映射实例化 | `var reader = READERS[name].new() # 映射 get_player_played_cards 在 21 行` |
| `scripts/system/global/board_power_query.gd:175` | READERS 实例入口 callv | `result = reader.exec.callv(params)` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### C — GetPlayerTotalPower
- **定义**：`scripts/system/operations/GetPlayerTotalPower.gd:1`。
- **公开入口**：`scripts/system/operations/GetPlayerTotalPower.gd:18` `func exec(player_id:int = -1, preview_power:int = 0, preview_cards:Array = [], preview_hidden:Array = []) -> int:`; `scripts/system/operations/GetPlayerTotalPower.gd:30` `static func breakdown(player_id:int = -1, preview_power:int = 0, preview_cards:Array = [], preview_hidden:Array = []) -> Dictionary:`; `scripts/system/operations/GetPlayerTotalPower.gd:59` `static func breakdown_lines(player_id:int = -1, preview_power:int = 0, preview_cards:Array = [], preview_hidden:Array = []) -> Array:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:256`，`get_player_total_power → GetPlayerTotalPower`，分类 `QUERY_PLAYER`。依据：`"get_player_total_power" : { "category": QUERY_PLAYER, "class": "GetPlayerTotalPower", "summary": "查玩家合计威力及构成" },`。
- **正式数据 func_name 引用**：`get_player_total_power` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：<span style="color:#d00000">🔴 是（战斗时点窗口内查询）：BATTLE_RESOLVE 后、BATTLE_END 前计算胜负威力；也服务 UI，类自身不派发或登记时点。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/battle_resolver.gd:59` `#注册场上所有事件牌效果（归属存活玩家作锚点），再派发一次全局战斗结算时点。`
> `scripts/system/global/battle_resolver.gd:60` `#事件牌效果挂battle_resolve时点，触发时用event.from反查所在战场遍历战场玩家。`
> `scripts/system/global/battle_resolver.gd:61` `_register_event_effects(ids)`
> `scripts/system/global/battle_resolver.gd:62` `TimePointChecker.global_time_point([TimePoints.BATTLE_RESOLVE])`
> `scripts/system/global/battle_resolver.gd:63` ``
> `scripts/system/global/battle_resolver.gd:64` `#逐区域结算`
> `scripts/system/global/battle_resolver.gd:65` `for area:BaseMapArea in area_to_players.keys():`
> `scripts/system/global/battle_resolver.gd:66` `var player_ids:Array = area_to_players[area]`
> `scripts/system/global/battle_resolver.gd:67` `if area._score_need_win:`
> `scripts/system/global/battle_resolver.gd:68` `_resolve_battle_area(area, player_ids, result)`
> `scripts/system/global/battle_resolver.gd:69` `else:`
> `scripts/system/global/battle_resolver.gd:70` `_resolve_non_battle_area(area, player_ids, result)`
> `scripts/system/global/battle_resolver.gd:71` `#胜负改写只对本回合这一次结算有效：没人参战、不比威力的战场上的声明也一并作废，不留到下一回合`
> `scripts/system/global/battle_resolver.gd:72` `for area:BaseMapArea in MapData.areas:`
> `scripts/system/global/battle_resolver.gd:73` `area._battle_override = {}`
> `scripts/system/global/battle_resolver.gd:74` ``
> `scripts/system/global/battle_resolver.gd:75` `#胜者判定之后的时点：派发在全部区域结算完之后。`
> `scripts/system/global/battle_resolver.gd:76` `#"此战场胜者可恢复1枚令咒"这类规则要在知道本场胜者之后才能触发，`
> `scripts/system/global/battle_resolver.gd:77` `#而 battle_resolve 派发在胜者计算之前，查不到本场结果——所以另设全局时点`
> `scripts/system/global/battle_resolver.gd:78` `TimePointChecker.global_time_point([TimePoints.BATTLE_END])`
> `scripts/system/global/battle_resolver.gd:167` `var powers:Dictionary = {}`
> `scripts/system/global/battle_resolver.gd:168` `for id in effective_ids:`
> `scripts/system/global/battle_resolver.gd:169` `#威力构成统一走 GetPlayerTotalPower：结算与界面共用同一份公式，`
> `scripts/system/global/battle_resolver.gd:170` `#避免两边各算一套导致"界面显示 12、结算按 10 判"（本项目已出过这类误报）。`
> `scripts/system/global/battle_resolver.gd:171` `#合计威力加成(言峰执行者、佐佐木燕返等)只在比较胜负时叠加、不写回 power 本身，`
> `scripts/system/global/battle_resolver.gd:172` `#这条口径也在那个查询里`
> `scripts/system/global/battle_resolver.gd:173` `var pw:Dictionary = GetPlayerTotalPower.breakdown(id)`
> `scripts/system/global/battle_resolver.gd:174` `var power:int = int(pw["total"])`
> `scripts/system/global/battle_resolver.gd:175` `powers[id] = pw`
> `scripts/system/global/battle_resolver.gd:176` `if highest_power == null or power > highest_power:`
> `scripts/system/global/battle_resolver.gd:177` `highest_power = power`
> `scripts/system/global/battle_resolver.gd:178` `winners = [id]`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/game_scene/battle_board_v2.gd:2389` | 类/静态公开入口 | `brk = GetPlayerTotalPower.breakdown(_local_player_id, _selected_cards_power(), _selected_cards.duplicate(), _selected_cards_hidden())` |
| `scripts/game_scene/battle_board_v2.gd:5197` | 类/静态公开入口 | `var lines: Array = _network_presenter.power_lines(_network_presenter.player_view(pid)) if network_session != null else GetPlayerTotalPower.breakdown_lines(pid, preview_power, preview_cards, preview_hidden)` |
| `scripts/game_scene/tactical_board_ui.gd:819` | 类/静态公开入口 | `var pw_break: Dictionary = GetPlayerTotalPower.breakdown(_local_player_id, pending_pow, _regular_play_pending_cards, _regular_play_pending_hidden)` |
| `scripts/game_scene/tactical_board_ui.gd:993` | 直接实例调用 | `var power_num: int = GetPlayerTotalPower.new().exec(bot_id)` |
| `scripts/game_scene/tactical_board_ui.gd:1254` | 直接实例调用 | `var total_power_num: int = GetPlayerTotalPower.new().exec(id)` |
| `scripts/game_scene/tactical_board_ui.gd:4381` | 直接实例调用 | `var opp_power: int = GetPlayerTotalPower.new().exec(bot_id)` |
| `scripts/game_scene/tactical_board_ui.gd:4431` | 直接实例调用 | `var opp_power_num: int = GetPlayerTotalPower.new().exec(bot_id)` |
| `scripts/game_scene/tactical_board_ui.gd:4614` | 类/静态公开入口 | `var lines := GetPlayerTotalPower.breakdown_lines(pid, pending_power, preview_cards, preview_hidden)` |
| `scripts/match/match_seat_query.gd:87` | 类/静态公开入口 | `var breakdown: Dictionary = GetPlayerTotalPower.breakdown(seat, preview_power, cards, flags)` |
| `scripts/match/view_builder.gd:48` | 类/静态公开入口 | `var breakdown: Dictionary = GetPlayerTotalPower.breakdown(pid)` |
| `scripts/system/global/battle_resolver.gd:173` | 类/静态公开入口 | `var pw:Dictionary = GetPlayerTotalPower.breakdown(id)` |
| `scripts/system/operations/GetPlayerPowerBreakdown.gd:17` | 类/静态公开入口 | `var b:Dictionary = GetPlayerTotalPower.breakdown(id)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/battle_score_report_test.gd:211`; `tests/bellerophon_rules_test.gd:88`; `tests/card_audit_probe.gd:175,178`; `tests/card_keyword_test.gd:171,176,180,184,188,189,193`; `tests/fd39_operations_test.gd:512`; `tests/match_seat_query_test.gd:27`; `tests/misc_rules_fix_test.gd:223,227,236`; `tests/net_authority_ui_preview_feedback_test.gd:25`; `tests/net_v2_ui_input_parity_window_test.gd:146`; `tests/net_v2_ui_parity_remaining_red_window_test.gd:120`; `tests/opponent_drawer_test.gd:174`; `tests/pending_board_power_test.gd:136,137,155,162,192,200`; `tests/phase_window_settlement_test.gd:49`; `tests/reported_board_power_test.gd:38,40,42,46,54,55,56,57,60,109,110,124,138,141,148,153`; `tests/reported_ui_test.gd:375`; `tests/self_power_single_render_test.gd:137,143`。
- **排除区（不计本类生产数）/debug**：`scripts/debug/debug_adapters/debug_player_adapter.gd:33`; `scripts/debug/debug_validate.gd:147`。

### C — GetPlayersInMapArea
- **定义**：`scripts/system/operations/GetPlayersInMapArea.gd:1`。
- **公开入口**：`scripts/system/operations/GetPlayersInMapArea.gd:6` `func exec(map_area:BaseMapArea, include_out:bool = false, anchor_player_id:int = -2, include_self:bool = true) -> Array:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:136`，`get_players_in_map_area → GetPlayersInMapArea`，分类 `QUERY_MAP`。依据：`"get_players_in_map_area" : { "category": QUERY_MAP, "class": "GetPlayersInMapArea", "summary": "指定区域内的玩家" },`。
- **正式数据 func_name 引用**：`get_players_in_map_area` **28** 条（递归计出现次数，不按卡文件去重）。证据：`data/events/origin/contain_third_party/contain_third_party.json:48`; `data/events/origin/cooperation/cooperation.json:43`; `data/events/origin/desperate_measure/desperate_measure.json:53`; `data/events/origin/fate_battle/fate_battle.json:48`; `data/events/origin/glorious_duel/glorious_duel.json:43`; `data/events/origin/holy_ground/holy_ground.json:43`; `data/events/origin/occupy_high_ground/occupy_high_ground.json:37`; `data/events/origin/sacrifice_ground/sacrifice_ground.json:43`; `data/events/origin/sneak_attack/sneak_attack.json:48`; `data/events/origin/strength_test/strength_test.json:43`; `data/events/origin/suppressive_fire/suppressive_fire.json:43`; `data/events/origin/treacherous_terrain/treacherous_terrain.json:43`; `data/masters/00003_matou_shinji/00003_matou_shinji.json:1626`; `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json:276`; `data/situations/origin/calm_before_storm/calm_before_storm.json:37,53`; `data/situations/origin/curse_of_angra_mainyu/curse_of_angra_mainyu.json:37,53`; `data/situations/origin/hope_for_future/hope_for_future.json:37,53`; `data/situations/origin/outrage/outrage.json:37,53`; `data/situations/origin/perfect_flow/perfect_flow.json:37,53`; `data/situations/origin/shadow_of_angra_mainyu/shadow_of_angra_mainyu.json:37,53`; `data/situations/origin/substance_of_angra_mainyu/substance_of_angra_mainyu.json:37,53`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/GetPlayersInMapArea.gd:6` `func exec(map_area:BaseMapArea, include_out:bool = false, anchor_player_id:int = -2, include_self:bool = true) -> Array:`
> `scripts/system/operations/GetPlayersInMapArea.gd:7` ``
> `scripts/system/operations/GetPlayersInMapArea.gd:8` `if map_area == null:`
> `scripts/system/operations/GetPlayersInMapArea.gd:9` `return []`
> `scripts/system/operations/GetPlayersInMapArea.gd:10` `var ids:Array = GameDataManager.get_active_player_ids() if !include_out else GameData.player_data_library.keys()`
> `scripts/system/operations/GetPlayersInMapArea.gd:11` `var result:Array = []`
> `scripts/system/operations/GetPlayersInMapArea.gd:12` `for id in ids:`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/board_power_query.gd:169` | READERS 显式映射实例化 | `var reader = READERS[name].new() # 映射 get_players_in_map_area 在 10 行` |
| `scripts/system/global/board_power_query.gd:175` | READERS 实例入口 callv | `result = reader.exec.callv(params)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/bellerophon_edges_test.gd:64`; `tests/bellerophon_rules_test.gd:79`; `tests/fd39_operations_test.gd:449`。
- **排除区（不计本类生产数）/debug**：无。

### C — GetProperty
- **定义**：`scripts/system/operations/GetProperty.gd:1`。
- **公开入口**：`scripts/system/operations/GetProperty.gd:6` `func exec(object, property:String):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:114`，`get_property → GetProperty`，分类 `QUERY_CARD`。依据：`"get_property" : { "category": QUERY_CARD, "class": "GetProperty", "summary": "读任意对象属性" },`。
- **正式数据 func_name 引用**：`get_property` **92** 条（递归计出现次数，不按卡文件去重）。证据：`data/attacks/basic/surveil/surveil.json:75`; `data/command_spells/normal_command_spell.json:93`; `data/events/origin/contain_third_party/contain_third_party.json:38,108`; `data/events/origin/cooperation/cooperation.json:33`; `data/events/origin/desperate_measure/desperate_measure.json:43`; `data/events/origin/fate_battle/fate_battle.json:38,88,121`; `data/events/origin/glorious_duel/glorious_duel.json:33`; `data/events/origin/holy_ground/holy_ground.json:33`; `data/events/origin/ley_line/ley_line.json:34`; `data/events/origin/occupy_high_ground/occupy_high_ground.json:27`; `data/events/origin/sacrifice_ground/sacrifice_ground.json:33`; `data/events/origin/sneak_attack/sneak_attack.json:38`; `data/events/origin/strength_test/strength_test.json:33`; `data/events/origin/suppressive_fire/suppressive_fire.json:33`; `data/events/origin/treacherous_terrain/treacherous_terrain.json:33`; `data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json:31,446,550,662,726,823,927,1039,1103,1257`; `data/masters/00003_matou_shinji/00003_matou_shinji.json:31,83,855,929,1051,1086,1140,1165,1247,1282,1336,1464,1499,1553`; `data/masters/00004_matou_sakura/00004_matou_sakura.json:25,166,263,560,714,733,743,772,944,969`; `data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json:72`; `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json:27,246,398,658,864,929,997,1099`; `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json:31,126,256,737`; `data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json:219`; `data/servants/00002_emiya/00002_emiya.json:285`; `data/servants/00003_cu_chulainn/00003_cu_chulainn.json:59,163`; `data/servants/00004_medusa/00004_medusa.json:148,258,303,324,348,640,744,774,793`; `data/servants/00005_medea/00005_medea.json:131,267`; `data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json:101,197,228,277,287`; `data/servants/00007_heracles/00007_heracles.json:192,490,788`; `data/servants/00008_angra_mainyu/00008_angra_mainyu.json:694,1032`; `data/situations/origin/gate_of_hell/gate_of_hell.json:127`; `data/situations/origin/heavens_feel/heavens_feel.json:127`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/GetProperty.gd:6` `func exec(object, property:String):`
> `scripts/system/operations/GetProperty.gd:7` ``
> `scripts/system/operations/GetProperty.gd:8` `if object == null or property == "":`
> `scripts/system/operations/GetProperty.gd:9` `return null`
> `scripts/system/operations/GetProperty.gd:10` `if object is Object and object.get(property) == null and !_has_property(object, property):`
> `scripts/system/operations/GetProperty.gd:11` `return null`
> `scripts/system/operations/GetProperty.gd:12` `return object.get(property)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/board_power_query.gd:169` | READERS 显式映射实例化 | `var reader = READERS[name].new() # 映射 get_property 在 8 行` |
| `scripts/system/global/board_power_query.gd:175` | READERS 实例入口 callv | `result = reader.exec.callv(params)` |
| `scripts/system/operations/FilterByProperty.gd:11` | 直接构造 | `var getter = GetProperty.new()` |
| `scripts/system/operations/FilterByProperty.gd:13` | 实例变量调用（new 在 11 行） | `if getter.exec(object, property) == value:` |
| `scripts/system/operations/GetExtremeByProperty.gd:10` | 直接构造 | `var getter = GetProperty.new()` |
| `scripts/system/operations/GetExtremeByProperty.gd:14` | 实例变量调用（new 在 10 行） | `var raw = getter.exec(object, property)` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### C — GetRankByDataNumber
- **定义**：`scripts/system/operations/GetRankByDataNumber.gd:1`。
- **公开入口**：`scripts/system/operations/GetRankByDataNumber.gd:7` `func exec(key:String, player_id:int = -1, descending:bool = true, include_out:bool = false) -> int:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:63`，`get_rank_by_data_number → GetRankByDataNumber`，分类 `QUERY_PLAYER`。依据：`"get_rank_by_data_number" : { "category": QUERY_PLAYER, "class": "GetRankByDataNumber", "summary": "按某数值字段排名" },`。
- **正式数据 func_name 引用**：`get_rank_by_data_number` **3** 条（递归计出现次数，不按卡文件去重）。证据：`data/events/origin/desperate_measure/desperate_measure.json:73`; `data/masters/00004_matou_sakura/00004_matou_sakura.json:99,359`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/GetRankByDataNumber.gd:7` `func exec(key:String, player_id:int = -1, descending:bool = true, include_out:bool = false) -> int:`
> `scripts/system/operations/GetRankByDataNumber.gd:8` ``
> `scripts/system/operations/GetRankByDataNumber.gd:9` `var id = EffectManager.resolve_player_id(player_id)`
> `scripts/system/operations/GetRankByDataNumber.gd:10` `if !GameData.player_data_library.has(id):`
> `scripts/system/operations/GetRankByDataNumber.gd:11` `return 0`
> `scripts/system/operations/GetRankByDataNumber.gd:12` `var my_num = _read_number(id, key)`
> `scripts/system/operations/GetRankByDataNumber.gd:13` `if my_num == null:`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/board_power_query.gd:169` | READERS 显式映射实例化 | `var reader = READERS[name].new() # 映射 get_rank_by_data_number 在 19 行` |
| `scripts/system/global/board_power_query.gd:175` | READERS 实例入口 callv | `result = reader.exec.callv(params)` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### C — GetSharedAttackAttribute
- **定义**：`scripts/system/operations/GetSharedAttackAttribute.gd:1`。
- **公开入口**：`scripts/system/operations/GetSharedAttackAttribute.gd:9` `func exec(player_id:int = -1):`; `scripts/system/operations/GetSharedAttackAttribute.gd:25` `static func from_cards(cards:Array):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:146`，`get_shared_attack_attribute → GetSharedAttackAttribute`，分类 `QUERY_EFFECT`。依据：`"get_shared_attack_attribute" : { "category": QUERY_EFFECT, "class": "GetSharedAttackAttribute", "summary": "玩家场上攻击的共同属性，无则null" },`。
- **正式数据 func_name 引用**：`get_shared_attack_attribute` **2** 条（递归计出现次数，不按卡文件去重）。证据：`data/events/origin/cooperation/cooperation.json:63`; `data/situations/origin/hope_for_future/hope_for_future.json:85`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/GetSharedAttackAttribute.gd:9` `func exec(player_id:int = -1):`
> `scripts/system/operations/GetSharedAttackAttribute.gd:10` ``
> `scripts/system/operations/GetSharedAttackAttribute.gd:11` `var id:int = EffectManager.resolve_player_id(player_id)`
> `scripts/system/operations/GetSharedAttackAttribute.gd:12` `var player_data:Dictionary = GameDataManager.get_player_data(id)`
> `scripts/system/operations/GetSharedAttackAttribute.gd:13` `if player_data == null or player_data.is_empty():`
> `scripts/system/operations/GetSharedAttackAttribute.gd:14` `return null`
> `scripts/system/operations/GetSharedAttackAttribute.gd:15` `var counts_power := CardCountsPower.new()`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/board_power_query.gd:79` | 类/静态公开入口 | `return GetSharedAttackAttribute.from_cards(attacks)` |
| `scripts/system/global/board_power_query.gd:169` | READERS 显式映射实例化 | `var reader = READERS[name].new() # 映射 get_shared_attack_attribute 在 20 行` |
| `scripts/system/global/board_power_query.gd:175` | READERS 实例入口 callv | `result = reader.exec.callv(params)` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### C — HasAttribute
- **定义**：`scripts/system/operations/HasAttribute.gd:1`。
- **公开入口**：`scripts/system/operations/HasAttribute.gd:6` `func exec(attributes:Array, card:BaseCard = null):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:104`，`has_attribute → HasAttribute`，分类 `QUERY_CARD`。依据：`"has_attribute" : { "category": QUERY_CARD, "class": "HasAttribute", "summary": "卡是否含给定属性" },`。
- **正式数据 func_name 引用**：`has_attribute` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/HasAttribute.gd:6` `func exec(attributes:Array, card:BaseCard = null):`
> `scripts/system/operations/HasAttribute.gd:7` ``
> `scripts/system/operations/HasAttribute.gd:8` `var target = card`
> `scripts/system/operations/HasAttribute.gd:9` `if target == null:`
> `scripts/system/operations/HasAttribute.gd:10` `target = GetEffSourceCard.new().exec()`
> `scripts/system/operations/HasAttribute.gd:11` `if target == null:`
> `scripts/system/operations/HasAttribute.gd:12` `return false`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/operations/GetCardsByAttributesFrArr.gd:11` | 直接构造 | `var has_attribute = HasAttribute.new()` |
| `scripts/system/operations/GetCardsByAttributesFrArr.gd:23` | 实例变量调用（new 在 11 行） | `elif has_attribute.exec(attributes, card):` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### C — IfElseFunc
- **定义**：`scripts/system/operations/IfElseFunc.gd:1`。
- **公开入口**：`scripts/system/operations/IfElseFunc.gd:6` `func exec(condition, then_value, else_value = null):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:169`，`if_else_func → IfElseFunc`，分类 `QUERY_COMPARE`。依据：`"if_else_func" : { "category": QUERY_COMPARE, "class": "IfElseFunc", "summary": "按条件二选一返回值" },`。
- **正式数据 func_name 引用**：`if_else_func` **4** 条（递归计出现次数，不按卡文件去重）。证据：`data/events/origin/desperate_measure/desperate_measure.json:124`; `data/events/origin/sneak_attack/sneak_attack.json:84`; `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json:316`; `data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json:375`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/IfElseFunc.gd:6` `func exec(condition, then_value, else_value = null):`
> `scripts/system/operations/IfElseFunc.gd:7` ``
> `scripts/system/operations/IfElseFunc.gd:8` `if _is_true(condition):`
> `scripts/system/operations/IfElseFunc.gd:9` `return then_value`
> `scripts/system/operations/IfElseFunc.gd:10` `return else_value`
> `scripts/system/operations/IfElseFunc.gd:11` ``
> `scripts/system/operations/IfElseFunc.gd:12` ``
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/board_power_query.gd:169` | READERS 显式映射实例化 | `var reader = READERS[name].new() # 映射 if_else_func 在 15 行` |
| `scripts/system/global/board_power_query.gd:175` | READERS 实例入口 callv | `result = reader.exec.callv(params)` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### C — IfFunc
- **定义**：`scripts/system/operations/IfFunc.gd:1`。
- **公开入口**：`scripts/system/operations/IfFunc.gd:6` `func exec(_var1, _var2 = true):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:168`，`if_func → IfFunc`，分类 `QUERY_COMPARE`。依据：`"if_func" : { "category": QUERY_COMPARE, "class": "IfFunc", "summary": "两值是否相等" },`。
- **正式数据 func_name 引用**：`if_func` **56** 条（递归计出现次数，不按卡文件去重）。证据：`data/attacks/class/foreigner_class/foreigner_class.json:69,94`; `data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json:163,279,1267`; `data/masters/00003_matou_shinji/00003_matou_shinji.json:41,238,274,531,577,671,875,939,1071,1096,1150,1175,1267,1292,1346,1375,1484,1509,1563`; `data/masters/00004_matou_sakura/00004_matou_sakura.json:134,176,344,382,570`; `data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json:153,301,393,605`; `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json:424,696,939,1007,1109`; `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json:241,266,294`; `data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json:540`; `data/servants/00002_emiya/00002_emiya.json:388`; `data/servants/00003_cu_chulainn/00003_cu_chulainn.json:402`; `data/servants/00004_medusa/00004_medusa.json:87,368,399,499,529,719,815,981`; `data/servants/00005_medea/00005_medea.json:141`; `data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json:495,543`; `data/servants/00008_angra_mainyu/00008_angra_mainyu.json:138`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/IfFunc.gd:6` `func exec(_var1, _var2 = true):`
> `scripts/system/operations/IfFunc.gd:7` ``
> `scripts/system/operations/IfFunc.gd:8` `return _unwrap(_var1) == _unwrap(_var2)`
> `scripts/system/operations/IfFunc.gd:9` ``
> `scripts/system/operations/IfFunc.gd:10` ``
> `scripts/system/operations/IfFunc.gd:11` `func _unwrap(_var):`
> `scripts/system/operations/IfFunc.gd:12` `if _var is BaseNumber:`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/board_power_query.gd:169` | READERS 显式映射实例化 | `var reader = READERS[name].new() # 映射 if_func 在 14 行` |
| `scripts/system/global/board_power_query.gd:175` | READERS 实例入口 callv | `result = reader.exec.callv(params)` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### C — IsEngaged
- **定义**：`scripts/system/operations/IsEngaged.gd:1`。
- **公开入口**：`scripts/system/operations/IsEngaged.gd:14` `func exec(player_id:int = -1) -> bool:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:121`，`is_engaged → IsEngaged`，分类 `QUERY_MAP`。依据：`"is_engaged" : { "category": QUERY_MAP, "class": "IsEngaged", "summary": "是否处于交战状态(与对手同处会发生战斗的战场)" },`。
- **正式数据 func_name 引用**：`is_engaged` **1** 条（递归计出现次数，不按卡文件去重）。证据：`data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json:373`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/IsEngaged.gd:14` `func exec(player_id:int = -1) -> bool:`
> `scripts/system/operations/IsEngaged.gd:15` ``
> `scripts/system/operations/IsEngaged.gd:16` `var id = EffectManager.resolve_player_id(player_id)`
> `scripts/system/operations/IsEngaged.gd:17` `var loc = GetLocation.new().exec(id)`
> `scripts/system/operations/IsEngaged.gd:18` `if loc == null:`
> `scripts/system/operations/IsEngaged.gd:19` `return false`
> `scripts/system/operations/IsEngaged.gd:20` `var area := loc.get_from() as BaseMapArea`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/game_scene/battle_board_v2.gd:5436` | 直接实例调用 | `if IsEngaged.new().exec(_local_player_id):` |
| `scripts/game_scene/tactical_board_ui.gd:2462` | 直接实例调用 | `if IsEngaged.new().exec(_local_player_id):` |
| `scripts/system/area_action_rules.gd:79` | 直接实例调用 | `if IsEngaged.new().exec(player_id):` |
| `scripts/system/operations/Move.gd:13` | 直接实例调用 | `if !ignore_battle and !ignore_engagement and IsEngaged.new().exec(player_id):` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/battlefield_conceal_test.gd:45`; `tests/debug_console_test.gd:108`; `tests/engagement_test.gd:67,74,82,96,99,106,110,133`; `tests/section5_engine_test.gd:178,181`; `tests/surveil_window_test.gd:44`。
- **排除区（不计本类生产数）/debug**：无。

### C — IsNull
- **定义**：`scripts/system/operations/IsNull.gd:1`。
- **公开入口**：`scripts/system/operations/IsNull.gd:5` `func exec(value) -> bool:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:175`，`is_null → IsNull`，分类 `QUERY_COMPARE`。依据：`"is_null" : { "category": QUERY_COMPARE, "class": "IsNull", "summary": "是否为null" },`。
- **正式数据 func_name 引用**：`is_null` **7** 条（递归计出现次数，不按卡文件去重）。证据：`data/events/origin/cooperation/cooperation.json:72`; `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json:155,316,358,454`; `data/servants/00008_angra_mainyu/00008_angra_mainyu.json:81`; `data/situations/origin/hope_for_future/hope_for_future.json:94`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/IsNull.gd:5` `func exec(value) -> bool:`
> `scripts/system/operations/IsNull.gd:6` ``
> `scripts/system/operations/IsNull.gd:7` `return value == null`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/board_power_query.gd:169` | READERS 显式映射实例化 | `var reader = READERS[name].new() # 映射 is_null 在 16 行` |
| `scripts/system/global/board_power_query.gd:175` | READERS 实例入口 callv | `result = reader.exec.callv(params)` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### C — IsTrueNameReleased
- **定义**：`scripts/system/operations/IsTrueNameReleased.gd:1`。
- **公开入口**：`scripts/system/operations/IsTrueNameReleased.gd:6` `func exec(player_id:int = -1) -> bool:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:151`，`is_true_name_released → IsTrueNameReleased`，分类 `QUERY_LOG`。依据：`"is_true_name_released" : { "category": QUERY_LOG, "class": "IsTrueNameReleased", "summary": "查询当前真名是否解放" },`。
- **正式数据 func_name 引用**：`is_true_name_released` **4** 条（递归计出现次数，不按卡文件去重）。证据：`data/events/origin/sneak_attack/sneak_attack.json:68`; `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json:164`; `data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json:370`; `data/servants/00004_medusa/00004_medusa.json:242`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/IsTrueNameReleased.gd:6` `func exec(player_id:int = -1) -> bool:`
> `scripts/system/operations/IsTrueNameReleased.gd:7` `return ReleaseTrueName.is_released(EffectManager.resolve_player_id(player_id))`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/board_power_query.gd:169` | READERS 显式映射实例化 | `var reader = READERS[name].new() # 映射 is_true_name_released 在 25 行` |
| `scripts/system/global/board_power_query.gd:175` | READERS 实例入口 callv | `result = reader.exec.callv(params)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/bellerophon_rules_test.gd:69`。
- **排除区（不计本类生产数）/debug**：无。

### C — MapAreaHasEffect
- **定义**：`scripts/system/operations/MapAreaHasEffect.gd:1`。
- **公开入口**：`scripts/system/operations/MapAreaHasEffect.gd:7` `func exec(map_area:BaseMapArea, effect_name:String) -> bool:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:145`，`map_area_has_effect → MapAreaHasEffect`，分类 `QUERY_EFFECT`。依据：`"map_area_has_effect" : { "category": QUERY_EFFECT, "class": "MapAreaHasEffect", "summary": "某战区是否含指定效果名" },`。
- **正式数据 func_name 引用**：`map_area_has_effect` **4** 条（递归计出现次数，不按卡文件去重）。证据：`data/attacks/basic/surveil/surveil.json:52,92`; `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json:599,616`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/MapAreaHasEffect.gd:7` `func exec(map_area:BaseMapArea, effect_name:String) -> bool:`
> `scripts/system/operations/MapAreaHasEffect.gd:8` ``
> `scripts/system/operations/MapAreaHasEffect.gd:9` `if map_area == null or effect_name == "":`
> `scripts/system/operations/MapAreaHasEffect.gd:10` `return false`
> `scripts/system/operations/MapAreaHasEffect.gd:11` `for event in map_area._events:`
> `scripts/system/operations/MapAreaHasEffect.gd:12` `# 暗置事件尚未公开，其禁令/地利修正等声明也不能提前生效。`
> `scripts/system/operations/MapAreaHasEffect.gd:13` `if event is BaseCard and event._is_concealed:`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/operations/GetEffectiveLocationBenefit.gd:22` | 直接实例调用 | `if area != null and MapAreaHasEffect.new().exec(area, NoLocationBenefitEffect.EFFECT_NAME):` |
| `scripts/system/operations/GetEffectiveLocationBenefit.gd:46` | 直接实例调用 | `if MapAreaHasEffect.new().exec(area, NoLocationBenefitEffect.EFFECT_NAME):` |
| `scripts/system/operations/SetLocation.gd:74` | 直接实例调用 | `return MapAreaHasEffect.new().exec(area, AREA_LOCKED)` |
| `scripts/system/play_rules.gd:38` | 直接实例调用 | `if MapAreaHasEffect.new().exec(area, ForbidSpecialAttackEffect.EFFECT_NAME):` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/battlefield_conceal_test.gd:112,114`。
- **排除区（不计本类生产数）/debug**：无。

### C — MatchFunc
- **定义**：`scripts/system/operations/MatchFunc.gd:1`。
- **公开入口**：`scripts/system/operations/MatchFunc.gd:4` `func exec(_var, cases:Array):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:174`，`match_func → MatchFunc`，分类 `QUERY_COMPARE`。依据：`"match_func" : { "category": QUERY_COMPARE, "class": "MatchFunc", "summary": "值是否落在cases里" },`。
- **正式数据 func_name 引用**：`match_func` **17** 条（递归计出现次数，不按卡文件去重）。证据：`data/attacks/class/avenger_class/avenger_class.json:150`; `data/events/origin/desperate_measure/desperate_measure.json:84`; `data/events/origin/fate_battle/fate_battle.json:98,131`; `data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json:536,913`; `data/masters/00003_matou_shinji/00003_matou_shinji.json:911`; `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json:557`; `data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json:241`; `data/servants/00005_medea/00005_medea.json:299,322`; `data/servants/00008_angra_mainyu/00008_angra_mainyu.json:126,300,357,631,857,914`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/MatchFunc.gd:4` `func exec(_var, cases:Array):`
> `scripts/system/operations/MatchFunc.gd:5` `var value = _var.number if _var is BaseNumber else _var`
> `scripts/system/operations/MatchFunc.gd:6` `for candidate in cases:`
> `scripts/system/operations/MatchFunc.gd:7` `var normalized = candidate.number if candidate is BaseNumber else candidate`
> `scripts/system/operations/MatchFunc.gd:8` `if value == normalized:`
> `scripts/system/operations/MatchFunc.gd:9` `return true`
> `scripts/system/operations/MatchFunc.gd:10` `return false`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/board_power_query.gd:169` | READERS 显式映射实例化 | `var reader = READERS[name].new() # 映射 match_func 在 13 行` |
| `scripts/system/global/board_power_query.gd:175` | READERS 实例入口 callv | `result = reader.exec.callv(params)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/venue_rule_fixes_test.gd:87`。
- **排除区（不计本类生产数）/debug**：无。

### C — MergeArrays
- **定义**：`scripts/system/operations/MergeArrays.gd:1`。
- **公开入口**：`scripts/system/operations/MergeArrays.gd:5` `func exec(a:Array = [], b:Array = [], c:Array = [], d:Array = []) -> Array:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:163`，`merge_arrays → MergeArrays`，分类 `QUERY_COLLECTION`。依据：`"merge_arrays" : { "category": QUERY_COLLECTION, "class": "MergeArrays", "summary": "合并最多四个数组" },`。
- **正式数据 func_name 引用**：`merge_arrays` **19** 条（递归计出现次数，不按卡文件去重）。证据：`data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json:470`; `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json:446,586`; `data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json:106,124`; `data/servants/00004_medusa/00004_medusa.json:316,479`; `data/servants/00007_heracles/00007_heracles.json:78,376,674`; `data/servants/00008_angra_mainyu/00008_angra_mainyu.json:598,660`; `data/situations/origin/calm_before_storm/calm_before_storm.json:62`; `data/situations/origin/curse_of_angra_mainyu/curse_of_angra_mainyu.json:62`; `data/situations/origin/hope_for_future/hope_for_future.json:62`; `data/situations/origin/outrage/outrage.json:62`; `data/situations/origin/perfect_flow/perfect_flow.json:62`; `data/situations/origin/shadow_of_angra_mainyu/shadow_of_angra_mainyu.json:62`; `data/situations/origin/substance_of_angra_mainyu/substance_of_angra_mainyu.json:62`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/MergeArrays.gd:5` `func exec(a:Array = [], b:Array = [], c:Array = [], d:Array = []) -> Array:`
> `scripts/system/operations/MergeArrays.gd:6` ``
> `scripts/system/operations/MergeArrays.gd:7` `var result:Array = []`
> `scripts/system/operations/MergeArrays.gd:8` `if a != null:`
> `scripts/system/operations/MergeArrays.gd:9` `result.append_array(a)`
> `scripts/system/operations/MergeArrays.gd:10` `if b != null:`
> `scripts/system/operations/MergeArrays.gd:11` `result.append_array(b)`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/board_power_query.gd:169` | READERS 显式映射实例化 | `var reader = READERS[name].new() # 映射 merge_arrays 在 11 行` |
| `scripts/system/global/board_power_query.gd:175` | READERS 实例入口 callv | `result = reader.exec.callv(params)` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### C — NotFunc
- **定义**：`scripts/system/operations/NotFunc.gd:1`。
- **公开入口**：`scripts/system/operations/NotFunc.gd:4` `func exec(_bool:bool) -> bool:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:173`，`not_func → NotFunc`，分类 `QUERY_COMPARE`。依据：`"not_func" : { "category": QUERY_COMPARE, "class": "NotFunc", "summary": "逻辑非" },`。
- **正式数据 func_name 引用**：`not_func` **30** 条（递归计出现次数，不按卡文件去重）。证据：`data/attacks/basic/surveil/surveil.json:114`; `data/events/origin/cooperation/cooperation.json:81`; `data/events/origin/sneak_attack/sneak_attack.json:75`; `data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json:214`; `data/masters/00003_matou_shinji/00003_matou_shinji.json:222,515,885,1356,1385`; `data/masters/00004_matou_sakura/00004_matou_sakura.json:186,395`; `data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json:615`; `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json:181,436,463,638,706`; `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json:635`; `data/servants/00004_medusa/00004_medusa.json:511,571,660,827`; `data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json:505,553`; `data/servants/00008_angra_mainyu/00008_angra_mainyu.json:90,395,422,644,952`; `data/situations/origin/hope_for_future/hope_for_future.json:103`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/NotFunc.gd:4` `func exec(_bool:bool) -> bool:`
> `scripts/system/operations/NotFunc.gd:5` ``
> `scripts/system/operations/NotFunc.gd:6` `return !_bool`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/board_power_query.gd:169` | READERS 显式映射实例化 | `var reader = READERS[name].new() # 映射 not_func 在 17 行` |
| `scripts/system/global/board_power_query.gd:175` | READERS 实例入口 callv | `result = reader.exec.callv(params)` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### C — PlayerBuffsHaveEffect
- **定义**：`scripts/system/operations/PlayerBuffsHaveEffect.gd:1`。
- **公开入口**：`scripts/system/operations/PlayerBuffsHaveEffect.gd:7` `func exec(effect_name:String, player_id:int = -1) -> bool:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:143`，`player_buffs_have_effect → PlayerBuffsHaveEffect`，分类 `QUERY_EFFECT`。依据：`"player_buffs_have_effect" : { "category": QUERY_EFFECT, "class": "PlayerBuffsHaveEffect", "summary": "玩家激活buff是否含效果名" },`。
- **正式数据 func_name 引用**：`player_buffs_have_effect` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：<span style="color:#d00000">🔴 是（时点门控查询）：BattleResolver 直接构造 checker；already_excluded 查询结果决定是否派 BATTLE_LOSE。</span>
- **时点证据（包含调用点上下文）**：
> `scripts/system/global/battle_resolver.gd:129` `var buffs_checker = PlayerBuffsHaveEffect.new()`
> `scripts/system/global/battle_resolver.gd:130` `for id in player_ids:`
> `scripts/system/global/battle_resolver.gd:131` `#带有"排除出胜负判定"效果(如【败北】)的玩家被忽略，`
> `scripts/system/global/battle_resolver.gd:132` `#既不能获胜也不能阻止他人获胜。按效果名通用查询，不关心具体buff类型`
> `scripts/system/global/battle_resolver.gd:133` `if buffs_checker.exec(ExcludedFromBattleWinEffect.EFFECT_NAME, id):`
> `scripts/system/global/battle_resolver.gd:134` `excluded_ids.append(id)`
> `scripts/system/global/battle_resolver.gd:135` `continue`
> `scripts/system/global/battle_resolver.gd:136` `effective_ids.append(id)`
> `scripts/system/global/battle_resolver.gd:236` `#非胜者标记为战斗失败，并派发 BATTLE_LOSE 时点。`
> `scripts/system/global/battle_resolver.gd:237` `#被排除出胜负判定的玩家(如已被效果赋予【败北】)在获得该状态时已经派发过 BATTLE_LOSE，`
> `scripts/system/global/battle_resolver.gd:238` `#这里不再重复派发，避免同一状态触发两次`
> `scripts/system/global/battle_resolver.gd:239` `for id in player_ids:`
> `scripts/system/global/battle_resolver.gd:240` `if winners.has(id):`
> `scripts/system/global/battle_resolver.gd:241` `continue`
> `scripts/system/global/battle_resolver.gd:242` `var player_data = GameDataManager.get_player_data(id) as Dictionary`
> `scripts/system/global/battle_resolver.gd:243` `var already_excluded:bool = buffs_checker.exec(ExcludedFromBattleWinEffect.EFFECT_NAME, id)`
> `scripts/system/global/battle_resolver.gd:244` `if !already_excluded:`
> `scripts/system/global/battle_resolver.gd:245` `TimePointChecker.dynamic_time_point([TimePoints.BATTLE_LOSE], GameDataManager.represented_id(id))`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/global/battle_resolver.gd:129` | 直接构造 | `var buffs_checker = PlayerBuffsHaveEffect.new()` |
| `scripts/system/global/battle_resolver.gd:133` | 实例变量调用（new 在 129 行） | `if buffs_checker.exec(ExcludedFromBattleWinEffect.EFFECT_NAME, id):` |
| `scripts/system/global/battle_resolver.gd:243` | 实例变量调用（new 在 129 行） | `var already_excluded:bool = buffs_checker.exec(ExcludedFromBattleWinEffect.EFFECT_NAME, id)` |
| `scripts/system/operations/CanGainMagic.gd:12` | 直接构造 | `var checker = PlayerBuffsHaveEffect.new()` |
| `scripts/system/operations/CanGainMagic.gd:13` | 实例变量调用（new 在 12 行） | `if checker.exec("cannot_gain_magic", id):` |
| `scripts/system/operations/CanGainMagic.gd:15` | 实例变量调用（new 在 12 行） | `if source != "" and checker.exec("cannot_gain_magic_from_" + source, id):` |
| `scripts/system/operations/PlayAttack.gd:25` | 直接实例调用 | `if PlayerBuffsHaveEffect.new().exec(CannotPlayCardsEffect.EFFECT_NAME, id):` |
| `scripts/system/operations/PlaySkill.gd:18` | 直接实例调用 | `if PlayerBuffsHaveEffect.new().exec(CannotPlayCardsEffect.EFFECT_NAME, id):` |
| `scripts/system/regular_play.gd:137` | 直接实例调用 | `if PlayerBuffsHaveEffect.new().exec(CannotPlayCardsEffect.EFFECT_NAME, id): return false` |
| `scripts/system/regular_play.gd:187` | 直接实例调用 | `if PlayerBuffsHaveEffect.new().exec(CannotPlayCardsEffect.EFFECT_NAME, id):` |
| `scripts/system/regular_play.gd:247` | 直接实例调用 | `if PlayerBuffsHaveEffect.new().exec(CannotPlayCardsEffect.EFFECT_NAME, id):` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### C — QueryLog
- **定义**：`scripts/system/operations/QueryLog.gd:1`。
- **公开入口**：`scripts/system/operations/QueryLog.gd:11` `func exec(filter:Dictionary = {}, round_offset = 0, limit:int = -1) -> Array:`。
- **注册表**：有；`scripts/system/global/all_operations.gd:148`，`query_log → QueryLog`，分类 `QUERY_LOG`。依据：`"query_log" : { "category": QUERY_LOG, "class": "QueryLog", "summary": "查游戏日志（历史事实）" },`。
- **正式数据 func_name 引用**：`query_log` **1** 条（递归计出现次数，不按卡文件去重）。证据：`data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json:359`。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/QueryLog.gd:11` `func exec(filter:Dictionary = {}, round_offset = 0, limit:int = -1) -> Array:`
> `scripts/system/operations/QueryLog.gd:12` `var f:Dictionary = filter.duplicate(true)`
> `scripts/system/operations/QueryLog.gd:13` `#actor 传 -1 表示"当前效果的触发者"；省略或传 null 表示不限玩家`
> `scripts/system/operations/QueryLog.gd:14` `if f.has("actor"):`
> `scripts/system/operations/QueryLog.gd:15` `if f["actor"] == null:`
> `scripts/system/operations/QueryLog.gd:16` `#显式写 null 是"不限玩家"，要从条件里去掉；`
> `scripts/system/operations/QueryLog.gd:17` `#留着会被当成"actor 必须等于 null"从而一条都匹配不到`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/system/operations/LogExists.gd:16` | 直接实例调用 | `return !QueryLog.new().exec(f, round_offset, 1).is_empty()` |
| `scripts/system/operations/LogFieldValues.gd:10` | 直接实例调用 | `for entry in QueryLog.new().exec(filter, round_offset, limit):` |
| `scripts/system/operations/SumLogData.gd:9` | 直接实例调用 | `for entry in QueryLog.new().exec(filter, round_offset, -1):` |
- **排除区（不计本类生产数）/测试/诊断**：无。
- **排除区（不计本类生产数）/debug**：无。

### C — ShuffleArray
- **定义**：`scripts/system/operations/ShuffleArray.gd:1`。
- **公开入口**：`scripts/system/operations/ShuffleArray.gd:7` `func exec(arr:Array):`。
- **注册表**：有；`scripts/system/global/all_operations.gd:267`，`shuffle_array → ShuffleArray`，分类 `QUERY_COLLECTION`。依据：`"shuffle_array" : { "category": QUERY_COLLECTION, "class": "ShuffleArray", "summary": "就地洗乱数组" },`。
- **正式数据 func_name 引用**：`shuffle_array` **0** 条（递归计出现次数，不按卡文件去重）。完整扫描 71 个 data JSON，出现次数 0。
- **是否涉及时点**：否（该类自身不处理时点；代码直连仅为查询/构造/集合工具，可被上层时点链复用）。
- **非时点入口证据**：
> `scripts/system/operations/ShuffleArray.gd:7` `func exec(arr:Array):`
> `scripts/system/operations/ShuffleArray.gd:8` ``
> `scripts/system/operations/ShuffleArray.gd:9` `if arr == null or arr.size() <= 1:`
> `scripts/system/operations/ShuffleArray.gd:10` `return arr`
> `scripts/system/operations/ShuffleArray.gd:11` `for i in range(arr.size() - 1, 0, -1):`
> `scripts/system/operations/ShuffleArray.gd:12` `var j:int = RuleRandom.int_in_range(0, i)`
> `scripts/system/operations/ShuffleArray.gd:13` `var tmp = arr[i]`
- **全部生产代码调用/构造点**（类静态公共消费者一并给出；不把它们都称为 new 命中）：

| 文件:行 | 路径类型 | 实际代码 |
|---|---|---|
| `scripts/selection/class_pool_selection.gd:5` | 直接构造 | `var _shuffle := ShuffleArray.new()` |
| `scripts/selection/class_pool_selection.gd:88` | 实例变量调用（new 在 5 行） | `_shuffle.exec(candidates)` |
| `scripts/selection/class_pool_selection.gd:90` | 实例变量调用（new 在 5 行） | `_shuffle.exec(pool)` |
| `scripts/selection/class_pool_selection.gd:118` | 实例变量调用（new 在 5 行） | `_shuffle.exec(initial_order)` |
| `scripts/system/global/game_progress.gd:186` | 直接实例调用 | `ShuffleArray.new().exec(cards)` |
| `scripts/system/map_data.gd:157` | 直接实例调用 | `ShuffleArray.new().exec(deck)` |
| `scripts/system/map_data.gd:169` | 直接实例调用 | `ShuffleArray.new().exec(non_climax)` |
| `scripts/system/operations/ReshuffleDiscard.gd:21` | 直接实例调用 | `ShuffleArray.new().exec(deck)` |
- **排除区（不计本类生产数）/测试/诊断**：`tests/rule_random_test.gd:53`。
- **排除区（不计本类生产数）/debug**：`scripts/debug/debug_adapters/debug_card_adapter.gd:178`。

## 6. 19 条 power contribution 的真实承载证据

唯一承载类：**B — BoardPowerQuery**。普通 operation 目录没有对应三类贡献 operation；其 `evaluate_one` 中按 func_name 分支求值，`total` 对每个 power_query 建实例，只有明置局势/事件参与。查询不依赖效果 time_points，不激活效果、不写玩家 power，结果由 `GetPlayerTotalPower.breakdown` 消费。
> `scripts/system/global/board_power_query.gd:57` `for card in cards:`
> `scripts/system/global/board_power_query.gd:58` `if card._is_concealed: continue`
> `scripts/system/global/board_power_query.gd:59` `for eff in card._effects:`
> `scripts/system/global/board_power_query.gd:60` `if eff._power_query.is_empty(): continue`
> `scripts/system/global/board_power_query.gd:61` `var query = BoardPowerQuery.new()`
> `scripts/system/global/board_power_query.gd:62` `query.effect = eff`
> `scripts/system/global/board_power_query.gd:63` `query.player_id = id`
> `scripts/system/global/board_power_query.gd:64` `query.card_values = values`
> `scripts/system/global/board_power_query.gd:65` `query.played_cards_view = played`
> `scripts/system/global/board_power_query.gd:66` `query.concealed_overrides = hidden`
> `scripts/system/global/board_power_query.gd:67` `query.evaluate(eff._power_query)`
> `scripts/system/global/board_power_query.gd:68` `result += query.contribution`
> `scripts/system/global/board_power_query.gd:125` `elif name == "power_contribution":`
> `scripts/system/global/board_power_query.gd:126` `if params.size() > 2 and params[2] != null and int(params[2]) == player_id:`
> `scripts/system/global/board_power_query.gd:127` `contribution += int(number(params[1]))`
> `scripts/system/global/board_power_query.gd:128` `elif name == "attack_power_contribution":`
> `scripts/system/global/board_power_query.gd:129` `if params.size() < 3 or params[2] == null or int(params[2]) != player_id: return`
> `scripts/system/global/board_power_query.gd:146` `contribution += int(number(params[1]))`
> `scripts/system/global/board_power_query.gd:147` `elif name == "card_power_contribution":`
> `scripts/system/global/board_power_query.gd:148` `if params.size() < 4 or params[3] == null or int(params[3]) != player_id: return`
> `scripts/system/global/board_power_query.gd:149` `var card = params[0]`
> `scripts/system/global/board_power_query.gd:150` `if not card is BaseAttack or not counts_power(card): return`
> `scripts/system/global/board_power_query.gd:151` `if not card._power.can_change: return`
> `scripts/system/global/board_power_query.gd:152` `var old:int = int(card_values.get(card, card._power.number))`
> `scripts/system/global/board_power_query.gd:153` `var current:int = int(number(params[2])) if params[2] != null else old`
> `scripts/system/global/board_power_query.gd:154` `current += int(number(params[1]))`
> `scripts/system/global/board_power_query.gd:155` `card_values[card] = current`
> `scripts/system/global/board_power_query.gd:156` `contribution += current - old`
> `scripts/system/operations/GetPlayerTotalPower.gd:41` `#场上明置的事件牌与局势牌声明的威力加成（协同、占领高地、对未来的憧憬等）。`
> `scripts/system/operations/GetPlayerTotalPower.gd:42` `#单独一项而不并进 power：并进去的话战报只会显示一个变大的"出牌威力"，`
> `scripts/system/operations/GetPlayerTotalPower.gd:43` `#玩家看不出这几点是哪张场上牌给的，也无法核对`
> `scripts/system/operations/GetPlayerTotalPower.gd:44` `var board = BoardPowerQuery.total(id, preview_cards, preview_hidden)`
> `scripts/system/operations/GetPlayerTotalPower.gd:45` `#地利的两条例外（战区声明不提供地利、只有部署到该位置才算）都在这个查询里处理`
> `scripts/system/operations/GetPlayerTotalPower.gd:46` `var benefit = GetEffectiveLocationBenefit.new().exec(id)`

| 序号 | func_name | 数据文件:行 | JSON Pointer |
|---:|---|---|---|
| 1 | `attack_power_contribution` | `data/events/origin/contain_third_party/contain_third_party.json:61` | `/effects/0/power_query/3/parameters/0/0` |
| 2 | `power_contribution` | `data/events/origin/cooperation/cooperation.json:90` | `/effects/0/power_query/3/parameters/0/4` |
| 3 | `power_contribution` | `data/events/origin/desperate_measure/desperate_measure.json:139` | `/effects/0/power_query/3/parameters/0/6` |
| 4 | `card_power_contribution` | `data/events/origin/fate_battle/fate_battle.json:156` | `/effects/0/power_query/3/parameters/0/2/parameters/0/7` |
| 5 | `attack_power_contribution` | `data/events/origin/glorious_duel/glorious_duel.json:56` | `/effects/0/power_query/3/parameters/0/0` |
| 6 | `attack_power_contribution` | `data/events/origin/holy_ground/holy_ground.json:56` | `/effects/0/power_query/3/parameters/0/0` |
| 7 | `power_contribution` | `data/events/origin/occupy_high_ground/occupy_high_ground.json:77` | `/effects/0/power_query/3/parameters/0/3` |
| 8 | `attack_power_contribution` | `data/events/origin/sacrifice_ground/sacrifice_ground.json:56` | `/effects/0/power_query/3/parameters/0/0` |
| 9 | `power_contribution` | `data/events/origin/sneak_attack/sneak_attack.json:99` | `/effects/0/power_query/3/parameters/0/4` |
| 10 | `attack_power_contribution` | `data/events/origin/strength_test/strength_test.json:56` | `/effects/0/power_query/3/parameters/0/0` |
| 11 | `attack_power_contribution` | `data/events/origin/suppressive_fire/suppressive_fire.json:56` | `/effects/0/power_query/3/parameters/0/0` |
| 12 | `attack_power_contribution` | `data/events/origin/treacherous_terrain/treacherous_terrain.json:56` | `/effects/0/power_query/3/parameters/0/0` |
| 13 | `attack_power_contribution` | `data/situations/origin/calm_before_storm/calm_before_storm.json:78` | `/effects/0/power_query/5/parameters/0/0` |
| 14 | `attack_power_contribution` | `data/situations/origin/curse_of_angra_mainyu/curse_of_angra_mainyu.json:78` | `/effects/0/power_query/5/parameters/0/0` |
| 15 | `power_contribution` | `data/situations/origin/hope_for_future/hope_for_future.json:112` | `/effects/0/power_query/5/parameters/0/4` |
| 16 | `attack_power_contribution` | `data/situations/origin/outrage/outrage.json:78` | `/effects/0/power_query/5/parameters/0/0` |
| 17 | `attack_power_contribution` | `data/situations/origin/perfect_flow/perfect_flow.json:78` | `/effects/0/power_query/5/parameters/0/0` |
| 18 | `attack_power_contribution` | `data/situations/origin/shadow_of_angra_mainyu/shadow_of_angra_mainyu.json:78` | `/effects/0/power_query/5/parameters/0/0` |
| 19 | `attack_power_contribution` | `data/situations/origin/substance_of_angra_mainyu/substance_of_angra_mainyu.json:78` | `/effects/0/power_query/5/parameters/0/0` |

### READERS 的另一条注册目录外实例化路径
`READERS` 显式写脚本 preload 映射，`READERS[name].new()` 与 `reader.exec.callv(params)` 不经 AllOperations；18 个类均已在 C 档去重列出。其运行分支有 player_slot 守卫，不把 null/-1 查询误传入创建玩家回退路径。
> `scripts/system/global/board_power_query.gd:157` `elif READERS.has(name):`
> `scripts/system/global/board_power_query.gd:158` `#Malformed legacy foreach slots stay malformed rather than silently changing targets.`
> `scripts/system/global/board_power_query.gd:159` `#Do not call player readers with null/-1: those can create fallback player state.`
> `scripts/system/global/board_power_query.gd:160` `var player_slot:int = 1 if name == "get_rank_by_data_number" else 0`
> `scripts/system/global/board_power_query.gd:161` `if name in ["get_rank_by_data_number", "get_shared_attack_attribute", "get_player_played_cards", "get_player_location_benefit", "get_effective_location_benefit", "is_true_name_released"]:`
> `scripts/system/global/board_power_query.gd:162` `if params.size() <= player_slot or params[player_slot] == null or int(params[player_slot]) < 0: return`
> `scripts/system/global/board_power_query.gd:163` `if not GameData.player_data_library.has(int(params[player_slot])): return`
> `scripts/system/global/board_power_query.gd:164` `if name == "get_player_played_cards" and int(params[0]) == player_id:`
> `scripts/system/global/board_power_query.gd:165` `result = played_cards_view.duplicate()`
> `scripts/system/global/board_power_query.gd:166` `elif name == "get_shared_attack_attribute" and int(params[0]) == player_id:`
> `scripts/system/global/board_power_query.gd:167` `result = shared_attack_attribute()`
> `scripts/system/global/board_power_query.gd:168` `else:`
> `scripts/system/global/board_power_query.gd:169` `var reader = READERS[name].new()`
> `scripts/system/global/board_power_query.gd:170` `var count:int = 0`
> `scripts/system/global/board_power_query.gd:171` `for method in reader.get_method_list():`
> `scripts/system/global/board_power_query.gd:172` `if method.name == "exec": count = method.args.size(); break`
> `scripts/system/global/board_power_query.gd:173` `#Foreach pads every descriptor, while native Callable ignores no surplus arguments.`
> `scripts/system/global/board_power_query.gd:174` `params.resize(mini(params.size(), count))`
> `scripts/system/global/board_power_query.gd:175` `result = reader.exec.callv(params)`

## 7. 测试/debug 专用字面命中类（不计生产三档）

测试/debug 中、总清单生产类集合之外另有 **44** 类。这里的“已注册”只说明 TABLE 目录存在，不表示本轮生产源码存在该类直连。
| 类 | 定义文件 | 公开入口 | TABLE 依据 | data func_name 次数 | 排除区全部字面调用点 |
|---|---|---|---|---:|---|
| `ActivateEffect` | `scripts/system/operations/ActivateEffect.gd:1` | 9: func exec(effect:BaseEffect, player_id:int = -1): | `all_operations.gd:247` `activate_effect` | 1 | `tests/fd39_operations_test.gd:328,332` |
| `AddAttack` | `scripts/system/operations/AddAttack.gd:1` | 4: func exec(attack:BaseAttack, player_id:int = -1, power:BaseNumber = null): | `all_operations.gd:223` `add_attack` | 1 | `tests/card_effect_runtime_test.gd:449` |
| `AddMapArea` | `scripts/system/operations/AddMapArea.gd:1` | 11: func exec(area_data:Dictionary, link_from:BaseMapArea = null, link_to:BaseMapArea = null): | `all_operations.gd:211` `add_map_area` | 0 | `tests/fd39_operations_test.gd:444,453` |
| `AddPlayer` | `scripts/system/operations/AddPlayer.gd:1` | 18: func exec(controller_id:int = -2, shared_keys:Array = [], overrides:Dictionary = {}) -> int: | `all_operations.gd:232` `add_player` | 0 | `tests/section5_engine_test.gd:94,116,120,133,138,159,175,179,332` |
| `AddSkill` | `scripts/system/operations/AddSkill.gd:1` | 4: func exec(skill:BaseSkill, player_id:int = -1, ignore_limit:bool = false, power:BaseNumber = null): | `all_operations.gd:224` `add_skill` | 0 | `tests/card_effect_runtime_test.gd:450` |
| `AwakenSkill` | `scripts/system/operations/AwakenSkill.gd:1` | 6: func exec(skill:BaseSkill, player_id:int = -1) -> bool: | `all_operations.gd:236` `awaken_skill` | 0 | `scripts/debug/debug_adapters/debug_card_adapter.gd:232` |
| `CancelPendingAction` | `scripts/system/operations/CancelPendingAction.gd:1` | 7: func exec() -> bool: | `all_operations.gd:248` `cancel_pending_action` | 2 | `tests/fd39_operations_test.gd:176` |
| `CloseCard` | `scripts/system/operations/CloseCard.gd:1` | 6: func exec(card:BaseHandCard, player_id:int = -1): | `all_operations.gd:192` `close_card` | 5 | `scripts/debug/debug_adapters/debug_card_adapter.gd:245`; `tests/bellerophon_rules_test.gd:95,97`; `tests/ni_no_tachi_test.gd:53`; `tests/piercing_cost_test.gd:28` |
| `CreateCard` | `scripts/system/operations/CreateCard.gd:1` | 9: func exec(card_name:String, card_type:String = "", owner = null): | `all_operations.gd:263` `create_card` | 0 | `tests/create_card_test.gd:111,113` |
| `DealPlayerCards` | `scripts/system/operations/DealPlayerCards.gd:1` | 7: func exec(player_id:int = -1): | `all_operations.gd:228` `deal_player_cards` | 1 | `scripts/debug/debug_adapters/debug_identity_adapter.gd:97,163,164`; `tests/angra_fang_window_test.gd:21`; `tests/angra_mainyu_window_test.gd:46` |
| `Defeat` | `scripts/system/operations/Defeat.gd:1` | 7: func exec(player_id:int = -1): | `all_operations.gd:235` `defeat` | 4 | `scripts/debug/debug_adapters/debug_player_adapter.gd:130`; `tests/fd39_operations_test.gd:163,164`; `tests/masters_audit_fix_test.gd:91` |
| `DrawCardByIndex` | `scripts/system/operations/DrawCardByIndex.gd:1` | 6: func exec(from:Array, to:Array, from_index = 0, to_index = -1): | `all_operations.gd:217` `draw_card_by_index` | 0 | `tests/fd39_operations_test.gd:194` |
| `EditCardAttributes` | `scripts/system/operations/EditCardAttributes.gd:1` | 5: func exec(add_attributes:Array = [], del_attributes:Array = [], set_attributes:Array = [""], card:BaseCard = null): | `all_operations.gd:190` `edit_card_attributes` | 0 | `scripts/debug/debug_adapters/debug_card_adapter.gd:214`; `tests/reported_ui_test.gd:399` |
| `EditCardCost` | `scripts/system/operations/EditCardCost.gd:1` | 6: func exec(vary_num:BaseNumber = BaseNumber.new(0), set_num:BaseNumber = null, card:BaseHandCard = null): | `all_operations.gd:189` `edit_card_cost` | 3 | `scripts/debug/debug_adapters/debug_card_adapter.gd:187`; `tests/reported_ui_test.gd:264,398` |
| `EditCardPower` | `scripts/system/operations/EditCardPower.gd:1` | 5: func exec(card:BaseHandCard, vary_num:BaseNumber = BaseNumber.new(0), set_num:BaseNumber = null, player_id:int = -1): | `all_operations.gd:188` `edit_card_power` | 3 | `scripts/debug/debug_adapters/debug_card_adapter.gd:203` |
| `EditDataNumber` | `scripts/system/operations/EditDataNumber.gd:1` | 8: func exec(key:String, set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0), player_id:int = -1, min_value = null, max_value = null): | `all_operations.gd:181` `edit_data_number` | 20 | `scripts/debug/debug_adapters/debug_player_adapter.gd:52,76` |
| `EditLives` | `scripts/system/operations/EditLives.gd:1` | 4: func exec(set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0), player_id:int = -1): | `all_operations.gd:179` `edit_lives` | 0 | `tests/fd39_operations_test.gd:152,562` |
| `EditLocationBenefit` | `scripts/system/operations/EditLocationBenefit.gd:1` | 9: func exec(location:BaseLocation, set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0)): | `all_operations.gd:197` `edit_location_benefit` | 2 | `tests/bellerophon_edges_test.gd:42,45`; `tests/location_benefit_test.gd:36,50,60,69`; `tests/session_restart_test.gd:51` |
| `EditPendingAction` | `scripts/system/operations/EditPendingAction.gd:1` | 7: func exec(key:String, set_num = null, vary_num = null): | `all_operations.gd:249` `edit_pending_action` | 0 | `tests/fd39_operations_test.gd:176` |
| `EndGame` | `scripts/system/operations/EndGame.gd:1` | 8: func exec(winner_ids:Array = []) -> bool: | `all_operations.gd:231` `end_game` | 1 | `tests/fd39_operations_test.gd:433,436` |
| `FlipCardFace` | `scripts/system/operations/FlipCardFace.gd:1` | 9: func exec(card:BaseCard, face_index = -1): | `all_operations.gd:194` `flip_card_face` | 0 | `tests/fd39_operations_test.gd:353,360` |
| `ForFunc` | `scripts/system/operations/ForFunc.gd:1` | 8: func exec(body, count): | `all_operations.gd:269` `for_func` | 7 | `tests/rule_guard_loop_owner_test.gd:8` |
| `ForeachFunc` | `scripts/system/operations/ForeachFunc.gd:1` | 7: func exec(body, arr:Array, parameter_index:int = 0): | `all_operations.gd:270` `foreach_func` | 57 | `tests/rule_guard_loop_owner_test.gd:9` |
| `GetAreaRoundParticipants` | `scripts/system/operations/GetAreaRoundParticipants.gd:1` | 5: func exec(map_area:BaseMapArea) -> Array: | `all_operations.gd:155` `get_area_round_participants` | 2 | `tests/venue_rule_fixes_test.gd:84` |
| `GetCardByIndexFrArr` | `scripts/system/operations/GetCardByIndexFrArr.gd:1` | 4: func exec(card_index, cards:Array): | `all_operations.gd:108` `get_card_by_index_fr_arr` | 54 | `tests/array_result_drag_test.gd:121` |
| `GetCardsByNameFrArr` | `scripts/system/operations/GetCardsByNameFrArr.gd:1` | 4: func exec(card_name:String, cards:Array): | `all_operations.gd:105` `get_cards_by_name_fr_arr` | 12 | `tests/fd39_operations_test.gd:376,377` |
| `GetObjectsByNameFrArr` | `scripts/system/operations/GetObjectsByNameFrArr.gd:1` | 5: func exec(object_name:String, objects:Array) -> Array: | `all_operations.gd:109` `get_objects_by_name_fr_arr` | 33 | `tests/fd39_operations_test.gd:376` |
| `GetPendingActionValue` | `scripts/system/operations/GetPendingActionValue.gd:1` | 9: func exec(key:String): | `all_operations.gd:250` `get_pending_action_value` | 0 | `tests/section5_engine_test.gd:288` |
| `GetPhaseOrder` | `scripts/system/operations/GetPhaseOrder.gd:1` | 7: func exec(player_id:int = -1): | `all_operations.gd:64` `get_phase_order` | 0 | `tests/section5_engine_test.gd:328,331,333` |
| `GetRoundBattleWins` | `scripts/system/operations/GetRoundBattleWins.gd:1` | 7: func exec(player_id:int = -1) -> int: | `all_operations.gd:153` `get_round_battle_wins` | 0 | `tests/card_audit_probe.gd:135` |
| `HideTrueName` | `scripts/system/operations/HideTrueName.gd:1` | 11: func exec(player_id:int = -1, hidden_areas:Array = ["servant_skills", "master_skills", "master._specials.SKILLS", "side.skills"]) -> bool: | `all_operations.gd:257` `hide_true_name` | 0 | `scripts/debug/debug_adapters/debug_identity_adapter.gd:155,342`; `scripts/debug/debug_adapters/debug_map_adapter.gd:135`; `tests/bellerophon_edges_test.gd:6`; `tests/card_history_test.gd:57,108`; `tests/card_keyword_test.gd:112`; `tests/overseer_knowledge_test.gd:28`; `tests/overseer_window_test.gd:13`; `tests/reported_ui_test.gd:199,200` |
| `PlayAttack` | `scripts/system/operations/PlayAttack.gd:1` | 6: func exec(attack:BaseAttack, player_id:int = -1, cost:BaseNumber = null, power:BaseNumber = null, ignore_limit:bool = false) -> bool: | `all_operations.gd:221` `play_attack` | 4 | `newtests/magic_overdraft_declaration_test.gd:63`; `newtests/play_affordance_rule_audit_test.gd:138,191,194,198,220`; `scripts/debug/debug_adapters/debug_map_adapter.gd:117`; `tests/card_effect_runtime_test.gd:447`; `tests/extra_play_limit_test.gd:35`; `tests/mana_spend_test.gd:76`; `tests/misc_rules_fix_test.gd:93,108,112`; `tests/piercing_cost_test.gd:25`; `tests/unlimited_blade_activation_test.gd:245` |
| `PlaySkill` | `scripts/system/operations/PlaySkill.gd:1` | 4: func exec(skill:BaseSkill, player_id:int = -1, ignore_limit:bool = false, cost:BaseNumber = null, power:BaseNumber = null): | `all_operations.gd:222` `play_skill` | 0 | `scripts/debug/debug_adapters/debug_map_adapter.gd:119`; `tests/card_effect_runtime_test.gd:448`; `tests/card_history_test.gd:60`; `tests/mana_spend_test.gd:78,80`; `tests/misc_rules_fix_test.gd:96`; `tests/piercing_cost_test.gd:22,32`; `tests/reported_activation_test.gd:178` |
| `QueueOptionalEffectForPlayers` | `scripts/system/operations/QueueOptionalEffectForPlayers.gd:1` | 11: func exec(players:Array, funcs:Array, shown_name:String = "", effect_name:String = "queued_optional_effect", options:Array = []) -> Array: | `all_operations.gd:245` `queue_optional_effect_for_players` | 1 | `tests/net_guard_rollback_test.gd:13`; `tests/net_opponent_window_test.gd:18,57`; `tests/net_process_test.gd:61`; `tests/rule_guard_choice_test.gd:6`; `tests/rule_guard_continuation_fixture.gd:27`; `tests/rule_guard_root_transaction_v2_test.gd:35` |
| `RandomFloat` | `scripts/system/operations/RandomFloat.gd:1` | 6: func exec(range_start:float, range_end:float): | `all_operations.gd:278` `random_float` | 0 | `tests/rule_random_test.gd:50` |
| `RandomInt` | `scripts/system/operations/RandomInt.gd:1` | 9: func exec(range_start, range_end): | `all_operations.gd:277` `random_int` | 1 | `tests/rule_random_test.gd:47` |
| `RemoveDefeat` | `scripts/system/operations/RemoveDefeat.gd:1` | 6: func exec(player_id:int = -1): | `all_operations.gd:237` `remove_defeat` | 1 | `scripts/debug/debug_adapters/debug_player_adapter.gd:132` |
| `RemoveFromArray` | `scripts/system/operations/RemoveFromArray.gd:1` | 5: func exec(item, arr:Array): | `all_operations.gd:165` `remove_from_array` | 10 | `scripts/debug/debug_adapters/debug_map_adapter.gd:121` |
| `SetBattleResult` | `scripts/system/operations/SetBattleResult.gd:1` | 15: func exec(map_area:BaseMapArea, winner_ids:Array = [], mode:String = "replace"): | `all_operations.gd:212` `set_battle_result` | 0 | `tests/fd39_operations_test.gd:397,405,417,421,425` |
| `SetLocationPlNumLimit` | `scripts/system/operations/SetLocationPlNumLimit.gd:1` | 9: func exec(location:BaseLocation, limit:int = -1): | `all_operations.gd:208` `set_location_pl_num_limit` | 2 | `tests/deploy_rules_layer_test.gd:54` |
| `SetPlayerData` | `scripts/system/operations/SetPlayerData.gd:1` | 4: func exec(key_name:String, value, player_id:int = -1): | `all_operations.gd:182` `set_player_data` | 7 | `scripts/debug/debug_adapters/debug_identity_adapter.gd:49,91,119,120,158,159,322,344`; `scripts/debug/debug_adapters/debug_player_adapter.gd:104`; `tests/masters_audit_fix_test.gd:107,120,122` |
| `ShowCards` | `scripts/system/operations/ShowCards.gd:1` | 8: func exec(cards:Array, viewer_ids:Array = [], shown_name:String = "") -> Array: | `all_operations.gd:280` `show_cards` | 0 | `tests/fd39_operations_test.gd:304` |
| `SumLogData` | `scripts/system/operations/SumLogData.gd:1` | 6: func exec(filter:Dictionary = {}, round_offset = 0, key:String = "delta") -> BaseNumber: | `all_operations.gd:149` `sum_log_data` | 2 | `tests/mana_spend_test.gd:4`; `tests/refactor_mana_leak_probe.gd:30` |
| `WhileFunc` | `scripts/system/operations/WhileFunc.gd:1` | 10: func exec(body, condition, max_iterations:int = MAX_ITERATIONS): | `all_operations.gd:272` `while_func` | 0 | `tests/rule_guard_loop_owner_test.gd:10` |

## 8. 被排除的全部字面调用原始定位
按区域→类→文件:行列出；同类同一行多次调用在定位清单合并为一个行号，上文原始匹配次数按实际调用次数计。测试/debug 已与正文每类调用点合并，不混入生产总数。
### 测试/诊断
- `ActivateEffect`：`tests/fd39_operations_test.gd:328,332`
- `AddAttack`：`tests/card_effect_runtime_test.gd:449`
- `AddEventFromDeck`：`tests/reported_board_power_test.gd:37,85`; `tests/rule_guard_event_add_test.gd:25`
- `AddMapArea`：`tests/fd39_operations_test.gd:444,453`
- `AddMapAreaEvents`：`tests/battle_event_discard_test.gd:42`; `tests/battle_score_report_test.gd:62`; `tests/command_spell_test.gd:294`; `tests/post_battle_choice_test.gd:68`
- `AddPlayer`：`tests/section5_engine_test.gd:94,116,120,133,138,159,175,179,332`
- `AddSkill`：`tests/card_effect_runtime_test.gd:450`
- `ApplyCardKeywords`：`tests/card_keyword_test.gd:84,109,126,133`
- `BattleResolver`：`tests/battle_score_report_test.gd:117,156`; `tests/bellerophon_edges_test.gd:60`; `tests/card_audit_probe.gd:130`; `tests/card_effect_runtime_test.gd:121,511`; `tests/command_spell_test.gd:89,296`; `tests/fd39_operations_test.gd:391,398,406,418,426`; `tests/location_benefit_test.gd:42`; `tests/misc_rules_fix_test.gd:249`; `tests/reported_board_power_test.gd:48`; `tests/section5_engine_test.gd:141,152,162`; `tests/twelve_labors_lifecycle_test.gd:90`
- `BoardHasEffect`：`tests/servant_skill_eight_magic_test.gd:29,80,90`
- `BuildCard`：`tests/create_card_test.gd:104,106`
- `CancelPendingAction`：`tests/fd39_operations_test.gd:176`
- `CardCountsPower`：`newtests/four_kind_real_execution_test.gd:107,111`
- `ChangePlOrder`：`tests/_probe_round.gd:28`; `tests/_probe_roundbusy.gd:25`; `tests/_probe_roundshift.gd:19`; `tests/net_round_identity_feedback_test.gd:12`; `tests/residue_pile_test.gd:124`; `tests/round_change_test.gd:58`; `tests/section5_engine_test.gd:329`; `tests/turn_transition_test.gd:118`
- `ClimaxResolver`：`tests/climax_elimination_test.gd:33,41,43,45,52,60`
- `CloneObject`：`newtests/action_completion_public_contract_test.gd:67`; `newtests/current_card_info_ui_contract_test.gd:78`; `newtests/round71_shared_discard_browsing_test.gd:182,191,192,230,241`; `newtests/round74_shared_out_of_game_test.gd:21,28,30,200,202`; `tests/_probe_conceal.gd:63`; `tests/_probe_conceal_click.gd:101`; `tests/angra_mainyu_test.gd:10`; `tests/area_lock_window_test.gd:105`; `tests/artoria_skills_test.gd:38`; `tests/battle_board_activation_command_test.gd:46`; `tests/battle_event_discard_test.gd:41`; `tests/battle_score_report_test.gd:75`; `tests/battle_scroll_test.gd:93,126,138`; `tests/battle_source_board_projection_test.gd:98,133,137`; `tests/bellerophon_rules_test.gd:29,32`; `tests/card_audit_probe.gd:100`; `tests/card_choice_source_command_test.gd:40`; `tests/card_effect_runtime_test.gd:52,133,325,337,418,433`; `tests/card_history_test.gd:48,66,79,90,91,116,129,144`; `tests/card_keyword_test.gd:75,83,122`; `tests/card_revealed_test.gd:76,86,87,114`; `tests/card_selection_owner_test.gd:49`; `tests/card_zone_browser_test.gd:264,273,308`; `tests/climax_gated_ability_test.gd:61`; `tests/command_spell_test.gd:67,293`; `tests/current_skill_group_test.gd:50`; `tests/effect_body_fill2_test.gd:41,106`; `tests/effect_body_fill_test.gd:41,63`; `tests/fd39_operations_test.gd:123`; `tests/hand_fan_arc_test.gd:48`; `tests/hand_fan_limits_test.gd:34`; `tests/held_cards_test.gd:78,95`; `tests/held_cards_window_test.gd:89`; `tests/held_skill_input_test.gd:53`; `tests/ichi_no_tachi_test.gd:60,74,185,194`; `tests/local_spell_restore_test.gd:56,66`; `tests/mana_spend_test.gd:89`; `tests/masters_audit_fix_test.gd:27,40,98,106,120,121`; `tests/misc_rules_fix_test.gd:155,178`; `tests/net_v2_area_window_test.gd:13,15,18`; `tests/newspecial_spell_materialization_test.gd:31,128`; `tests/ni_no_tachi_test.gd:28`; `tests/overseer_knowledge_test.gd:8,9,23,30`; `tests/overseer_window_test.gd:10`; `tests/pending_board_power_test.gd:58,65,227`; `tests/piercing_cost_test.gd:14,15`; `tests/played_stack_test.gd:89,197`; `tests/post_battle_choice_test.gd:64`; `tests/private_knowledge_corrosion_test.gd:14,16,99`; `tests/refactor_net_area_diagnostic.gd:13,15,18`; `tests/reported_activation_test.gd:23,140`; `tests/reported_board_power_test.gd:97,121,137,145,147`; `tests/residue_pile_test.gd:51,59`; `tests/round29-shared-presentation_test.gd:244,246`; `tests/round70_declared_card_backs_test.gd:73`; `tests/san_no_tachi_test.gd:9,35,36,47,48`; `tests/san_no_tachi_window_test.gd:58,59,60`; `tests/unlimited_blade_activation_test.gd:127,130,133,137,289`; `tests/zoom_and_desc_test.gd:87,182,211`
- `CloseCard`：`tests/bellerophon_rules_test.gd:95,97`; `tests/ni_no_tachi_test.gd:53`; `tests/piercing_cost_test.gd:28`
- `CreateCard`：`tests/create_card_test.gd:111,113`
- `DealPlayerCards`：`tests/angra_fang_window_test.gd:21`; `tests/angra_mainyu_window_test.gd:46`
- `Defeat`：`tests/fd39_operations_test.gd:163,164`; `tests/masters_audit_fix_test.gd:91`
- `Deploy`：`tests/bellerophon_edges_test.gd:66,73`; `tests/bellerophon_rules_test.gd:66,105,106`; `tests/bellerophon_window_test.gd:26`; `tests/card_keyword_test.gd:187`; `tests/climax_elimination_test.gd:58`; `tests/deploy_rules_layer_test.gd:53,55`; `tests/deploy_rules_test.gd:25,27,28,29,55`; `tests/engagement_test.gd:65,66,79,80,94,95`; `tests/fd39_operations_test.gd:381,482,588`; `tests/full_game_test.gd:88`; `tests/location_benefit_test.gd:31,68`; `tests/misc_rules_fix_test.gd:149,200,221`; `tests/pending_board_power_test.gd:52,53`; `tests/prepare_phase_test.gd:41`; `tests/section5_engine_test.gd:125,139,160,176,177,180`; `tests/session_restart_test.gd:44`
- `DiscardPlayedCards`：`tests/misc_rules_fix_test.gd:251`; `tests/residue_pile_test.gd:117`; `tests/twelve_labors_lifecycle_test.gd:53`
- `DrawCardByCard`：`tests/bellerophon_rules_test.gd:98`; `tests/card_zone_browser_test.gd:320`; `tests/debug_identity_hand_test.gd:95`; `tests/fd39_operations_test.gd:186,190,228,232`; `tests/unlimited_blade_activation_test.gd:110,269,272,286`
- `DrawCardByIndex`：`tests/fd39_operations_test.gd:194`
- `DrawCardFromPlDeckToHand`：`tests/fd39_operations_test.gd:204`; `tests/held_cards_window_test.gd:180`; `tests/rule_guard_zone_notify_test.gd:23`
- `EditCardAttributes`：`tests/reported_ui_test.gd:399`
- `EditCardCost`：`tests/reported_ui_test.gd:264,398`
- `EditLives`：`tests/fd39_operations_test.gd:152,562`
- `EditLocationBenefit`：`tests/bellerophon_edges_test.gd:42,45`; `tests/location_benefit_test.gd:36,50,60,69`; `tests/session_restart_test.gd:51`
- `EditMagic`：`newtests/magic_overdraft_declaration_test.gd:94,96,99`; `tests/debug_unbounded_number_test.gd:105,107`; `tests/fd39_operations_test.gd:172,174,461,462`; `tests/magic_limit_test.gd:35,43,47,51`; `tests/mana_spend_test.gd:46,51,61,127,145`; `tests/masters_audit_fix_test.gd:62,64`; `tests/net_guard_rollback_test.gd:11`; `tests/refactor_kernel_state_boundaries_test.gd:18`; `tests/rule_guard_continuation_fixture.gd:13,16`; `tests/rule_guard_rollback_fixture.gd:16`; `tests/rule_guard_root_transaction_v2_test.gd:16`
- `EditPendingAction`：`tests/fd39_operations_test.gd:176`
- `EditScore`：`tests/battle_score_report_test.gd:238`; `tests/fd39_operations_test.gd:130,138,140,142,472,473,476,477`; `tests/masters_audit_fix_test.gd:117`
- `EndGame`：`tests/fd39_operations_test.gd:433,436`
- `FlipCardFace`：`tests/fd39_operations_test.gd:353,360`
- `ForFunc`：`tests/rule_guard_loop_owner_test.gd:8`
- `ForeachFunc`：`tests/rule_guard_loop_owner_test.gd:9`
- `GetAreaRoundParticipants`：`tests/venue_rule_fixes_test.gd:84`
- `GetCardByIndexFrArr`：`tests/array_result_drag_test.gd:121`
- `GetCardsByNameFrArr`：`tests/fd39_operations_test.gd:376,377`
- `GetEffectiveLocationBenefit`：`tests/battle_score_report_test.gd:68`; `tests/bellerophon_edges_test.gd:44,46,48,50,58`; `tests/bellerophon_rules_test.gd:78,85,90`; `tests/bellerophon_window_test.gd:59`; `tests/deploy_rules_test.gd:57,59`; `tests/fd39_operations_test.gd:484,487`; `tests/location_benefit_test.gd:33,37,51,56,63,76,79`
- `GetLocation`：`tests/area_lock_window_test.gd:89,115,122`; `tests/bellerophon_edges_test.gd:19,24,69`; `tests/bellerophon_rules_test.gd:75,76`; `tests/bellerophon_window_test.gd:70`; `tests/deploy_rules_test.gd:56`; `tests/engagement_test.gd:68,70,83,86,134,137`; `tests/location_benefit_test.gd:32,62`; `tests/misc_rules_fix_test.gd:126,129,161,170,193,199,218`; `tests/surveil_window_test.gd:54,71`
- `GetMapAreaByName`：`tests/effect_body_fill2_test.gd:118`; `tests/effect_execution_input_contract_test.gd:51`
- `GetMoveTargetLocation`：`tests/bellerophon_composition_test.gd:28`; `tests/debug_console_test.gd:88`; `tests/deploy_rules_test.gd:22`
- `GetObjectsByNameFrArr`：`tests/fd39_operations_test.gd:376`
- `GetPendingActionValue`：`tests/section5_engine_test.gd:288`
- `GetPhaseOrder`：`tests/section5_engine_test.gd:328,331,333`
- `GetPlCommandSpellOutGame`：`newtests/four_kind_real_execution_test.gd:178`; `tests/engagement_test.gd:114`; `tests/net_full_game_test.gd:59`
- `GetPlayerTotalPower`：`tests/battle_score_report_test.gd:211`; `tests/bellerophon_rules_test.gd:88`; `tests/card_audit_probe.gd:175,178`; `tests/card_keyword_test.gd:176,180,184,188,189`; `tests/fd39_operations_test.gd:512`; `tests/pending_board_power_test.gd:136,137,155,162,192,200`; `tests/reported_board_power_test.gd:38,40,42,46,54,55,56,109,110,124,138,141,148,153`; `tests/reported_ui_test.gd:375`
- `GetPlayersInMapArea`：`tests/bellerophon_edges_test.gd:64`; `tests/bellerophon_rules_test.gd:79`; `tests/fd39_operations_test.gd:449`
- `GetRoundBattleWins`：`tests/card_audit_probe.gd:135`
- `HideTrueName`：`tests/bellerophon_edges_test.gd:6`; `tests/card_history_test.gd:57,108`; `tests/card_keyword_test.gd:112`; `tests/overseer_knowledge_test.gd:28`; `tests/overseer_window_test.gd:13`; `tests/reported_ui_test.gd:199,200`
- `IsEngaged`：`tests/battlefield_conceal_test.gd:45`; `tests/debug_console_test.gd:108`; `tests/engagement_test.gd:67,74,82,96,99,106,110,133`; `tests/section5_engine_test.gd:178,181`; `tests/surveil_window_test.gd:44`
- `IsTrueNameReleased`：`tests/bellerophon_rules_test.gd:69`
- `ManageBuff`：`tests/mana_spend_test.gd:99,103,107,113,119`; `tests/masters_audit_fix_test.gd:82,109`; `tests/opponent_drawer_test.gd:48,220`; `tests/private_knowledge_corrosion_test.gd:7,9`
- `MapAreaHasEffect`：`tests/battlefield_conceal_test.gd:112,114`
- `MatchFunc`：`tests/venue_rule_fixes_test.gd:87`
- `Move`：`tests/engagement_test.gd:69,85,136`; `tests/mana_spend_test.gd:38,68,96`; `tests/misc_rules_fix_test.gd:192,198`
- `MoveLocation`：`tests/fd39_operations_test.gd:493`; `tests/misc_rules_fix_test.gd:133,137,144`
- `PlayAttack`：`newtests/magic_overdraft_declaration_test.gd:63`; `newtests/play_affordance_rule_audit_test.gd:138,191,194,198,220`; `tests/card_effect_runtime_test.gd:447`; `tests/extra_play_limit_test.gd:35`; `tests/mana_spend_test.gd:76`; `tests/misc_rules_fix_test.gd:93,108,112`; `tests/piercing_cost_test.gd:25`; `tests/unlimited_blade_activation_test.gd:245`
- `PlaySkill`：`tests/card_effect_runtime_test.gd:448`; `tests/card_history_test.gd:60`; `tests/mana_spend_test.gd:78,80`; `tests/misc_rules_fix_test.gd:96`; `tests/piercing_cost_test.gd:22,32`; `tests/reported_activation_test.gd:178`
- `QueueOptionalEffectForPlayers`：`tests/net_guard_rollback_test.gd:13`; `tests/net_opponent_window_test.gd:18,57`; `tests/net_process_test.gd:61`; `tests/rule_guard_choice_test.gd:6`; `tests/rule_guard_continuation_fixture.gd:27`; `tests/rule_guard_root_transaction_v2_test.gd:35`
- `RandomFloat`：`tests/rule_random_test.gd:50`
- `RandomInt`：`tests/rule_random_test.gd:47`
- `RefillHand`：`tests/fd39_operations_test.gd:469`; `tests/prepare_phase_test.gd:20,22,24,29,35`; `tests/rule_guard_loop_owner_test.gd:21`; `tests/rule_guard_refill_test.gd:23`
- `RegisterObjectEffects`：`newtests/action_completion_public_contract_test.gd:70`; `tests/angra_mainyu_test.gd:17`; `tests/artoria_skills_test.gd:40`; `tests/card_audit_probe.gd:242`; `tests/card_history_test.gd:51,68,83,95,96`; `tests/card_keyword_test.gd:158`; `tests/climax_gated_ability_test.gd:77`; `tests/fd39_operations_test.gd:351`; `tests/held_skill_input_test.gd:64`; `tests/local_spell_restore_test.gd:68`; `tests/mana_spend_test.gd:90`; `tests/masters_audit_fix_test.gd:134`; `tests/newspecial_spell_materialization_test.gd:130`; `tests/piercing_cost_test.gd:17`; `tests/private_knowledge_corrosion_test.gd:18`; `tests/reported_activation_test.gd:143,233,289`; `tests/san_no_tachi_test.gd:14`; `tests/san_no_tachi_window_test.gd:62`
- `ReleaseTrueName`：`tests/_probe_conceal_click.gd:82`; `tests/board_requested_ui_test.gd:85`; `tests/card_history_test.gd:55,107,110`; `tests/card_keyword_test.gd:105`; `tests/overseer_knowledge_test.gd:20`; `tests/reported_activation_test.gd:323,328`; `tests/reported_ui_test.gd:182,190,427,428`; `tests/rule_guard_true_name_test.gd:29`
- `RemoveFromBoard`：`tests/angra_fang_window_test.gd:24`; `tests/angra_mainyu_test.gd:66,72`; `tests/bellerophon_edges_test.gd:32,40`; `tests/bellerophon_rules_test.gd:100,103`; `tests/bellerophon_window_test.gd:62`; `tests/debug_console_test.gd:119`; `tests/fd39_operations_test.gd:217,450,485,488,495,587`; `tests/outpost_identity_test.gd:59`; `tests/prepare_phase_test.gd:44,47`; `tests/twelve_labors_lifecycle_test.gd:55`
- `ReshuffleDiscard`：`tests/prepare_phase_test.gd:36`
- `RestoreLocationBenefits`：`tests/bellerophon_rules_test.gd:24`; `tests/location_benefit_test.gd:22,54,64,78`; `tests/misc_rules_fix_test.gd:27`
- `RestoreLocationPlNumLimits`：`tests/deploy_rules_layer_test.gd:56`
- `SetBattleResult`：`tests/fd39_operations_test.gd:397,405,417,421,425`
- `SetCardConcealed`：`tests/_probe_conceal_click.gd:92`; `tests/current_skill_group_test.gd:106`
- `SetLocation`：`tests/_probe_broadcast.gd:30,35`; `tests/_probe_conceal.gd:62`; `tests/_probe_conceal_click.gd:99`; `tests/_probe_head_fade.gd:79,97,125`; `tests/area_lock_window_test.gd:39`; `tests/artoria_skills_test.gd:81,82`; `tests/avatar_parallel_test.gd:39`; `tests/battle_broadcast_test.gd:90`; `tests/battle_play_groups_test.gd:50,258`; `tests/battle_score_report_test.gd:65`; `tests/battle_scroll_test.gd:171`; `tests/bellerophon_composition_test.gd:45,53`; `tests/bellerophon_edges_test.gd:3,9,21,22,26,34,41,53,65`; `tests/bellerophon_rules_test.gd:65,91,101,110`; `tests/bellerophon_window_test.gd:25,65`; `tests/broadcast_absent_confirmation_test.gd:39`; `tests/broadcast_authority_test.gd:30`; `tests/broadcast_command_dispatch_test.gd:44`; `tests/broadcast_policy_boundary_test.gd:23`; `tests/broadcast_worker_capability_test.gd:42`; `tests/card_audit_probe.gd:106`; `tests/card_effect_runtime_test.gd:41`; `tests/command_spell_test.gd:80`; `tests/debug_console_test.gd:98,117`; `tests/deploy_rules_test.gd:58,61`; `tests/effect_body_fill2_test.gd:72,83`; `tests/effect_body_fill_test.gd:89`; `tests/effect_execution_input_contract_test.gd:37,52`; `tests/engagement_test.gd:97,98,105,109,131,132`; `tests/fd39_operations_test.gd:215,216,449,486,491,581,583,585`; `tests/ichi_no_tachi_test.gd:47`; `tests/location_benefit_test.gd:61`; `tests/mana_spend_test.gd:94`; `tests/masters_audit_fix_test.gd:25,26`; `tests/misc_rules_fix_test.gd:105,109,119,120,132,135,136,140,142,143,145,147,148,150,173,187,195,201,207,213,234,245,246`; `tests/ni_no_tachi_test.gd:39`; `tests/opponent_drawer_test.gd:37`; `tests/post_battle_choice_test.gd:55`; `tests/refactor_area_golden_test.gd:81`; `tests/surveil_window_test.gd:37,38`; `tests/switch_performance_test.gd:17`; `tests/takeoff_refresh_test.gd:49`; `tests/zoom_and_desc_test.gd:181`
- `SetLocationPlNumLimit`：`tests/deploy_rules_layer_test.gd:54`
- `SetPlayerData`：`tests/masters_audit_fix_test.gd:107,120,122`
- `ShowCards`：`tests/fd39_operations_test.gd:304`
- `ShuffleArray`：`tests/rule_random_test.gd:53`
- `SumLogData`：`tests/mana_spend_test.gd:4`; `tests/refactor_mana_leak_probe.gd:30`
- `SyncPower`：`tests/artoria_skills_test.gd:87,92,114`; `tests/debug_identity_hand_test.gd:104`; `tests/twelve_labors_lifecycle_test.gd:54`
- `UnregisterObjectEffects`：`tests/local_spell_restore_test.gd:170`; `tests/newspecial_spell_materialization_test.gd:122`
- `VictoryResolver`：`tests/section5_engine_test.gd:169`
- `WhileFunc`：`tests/rule_guard_loop_owner_test.gd:10`
### debug
- `AwakenSkill`：`scripts/debug/debug_adapters/debug_card_adapter.gd:232`
- `CloneObject`：`scripts/debug/debug_adapters/debug_board_adapter.gd:79`; `scripts/debug/debug_adapters/debug_card_adapter.gd:127`; `scripts/debug/debug_adapters/debug_player_adapter.gd:117`
- `CloseCard`：`scripts/debug/debug_adapters/debug_card_adapter.gd:245`
- `DealPlayerCards`：`scripts/debug/debug_adapters/debug_identity_adapter.gd:97,163,164`
- `Defeat`：`scripts/debug/debug_adapters/debug_player_adapter.gd:130`
- `DrawCardByCard`：`scripts/debug/debug_adapters/debug_card_adapter.gd:65,115`; `scripts/debug/debug_adapters/debug_identity_adapter.gd:205,372`
- `DrawCardFromPlDeckToHand`：`scripts/debug/debug_adapters/debug_card_adapter.gd:147`
- `EditCardAttributes`：`scripts/debug/debug_adapters/debug_card_adapter.gd:214`
- `EditCardCost`：`scripts/debug/debug_adapters/debug_card_adapter.gd:187`
- `EditCardPower`：`scripts/debug/debug_adapters/debug_card_adapter.gd:203`
- `EditDataNumber`：`scripts/debug/debug_adapters/debug_player_adapter.gd:52,76`
- `EditMagic`：`scripts/debug/debug_adapters/debug_board_adapter.gd:85`
- `HideTrueName`：`scripts/debug/debug_adapters/debug_identity_adapter.gd:155,342`; `scripts/debug/debug_adapters/debug_map_adapter.gd:135`
- `ManageBuff`：`scripts/debug/debug_adapters/debug_identity_adapter.gd:236,237,248,260`; `scripts/debug/debug_adapters/debug_player_adapter.gd:122`
- `Move`：`scripts/debug/debug_adapters/debug_map_adapter.gd:60`
- `PlayAttack`：`scripts/debug/debug_adapters/debug_map_adapter.gd:117`
- `PlaySkill`：`scripts/debug/debug_adapters/debug_map_adapter.gd:119`
- `RefillHand`：`scripts/debug/debug_adapters/debug_card_adapter.gd:156`; `scripts/debug/debug_adapters/debug_identity_adapter.gd:176`
- `RegisterObjectEffects`：`scripts/debug/debug_adapters/debug_board_adapter.gd:88`; `scripts/debug/debug_adapters/debug_card_adapter.gd:69,117,134`; `scripts/debug/debug_adapters/debug_identity_adapter.gd:50,92,121,122,160,161,206`
- `ReleaseTrueName`：`scripts/debug/debug_adapters/debug_map_adapter.gd:129`
- `RemoveDefeat`：`scripts/debug/debug_adapters/debug_player_adapter.gd:132`
- `RemoveFromArray`：`scripts/debug/debug_adapters/debug_map_adapter.gd:121`
- `RemoveFromBoard`：`scripts/debug/debug_adapters/debug_map_adapter.gd:84`
- `ReshuffleDiscard`：`scripts/debug/debug_adapters/debug_card_adapter.gd:146`
- `SetCardConcealed`：`scripts/debug/debug_adapters/debug_card_adapter.gd:223`
- `SetLocation`：`scripts/debug/debug_adapters/debug_map_adapter.gd:74`
- `SetPlayerData`：`scripts/debug/debug_adapters/debug_identity_adapter.gd:49,91,119,120,158,159,322,344`; `scripts/debug/debug_adapters/debug_player_adapter.gd:104`
- `ShuffleArray`：`scripts/debug/debug_adapters/debug_card_adapter.gd:178`
- `SyncPower`：`scripts/debug/debug_adapters/debug_card_adapter.gd:71,73,136`; `scripts/debug/debug_adapters/debug_identity_adapter.gd:181`; `scripts/debug/debug_adapters/debug_player_adapter.gd:88`
- `UnregisterObjectEffects`：`scripts/debug/debug_adapters/debug_card_adapter.gd:64,114`; `scripts/debug/debug_adapters/debug_identity_adapter.gd:113,114,144,145,204,316,337,371,388,399`
### 历史证据与备份
- `CloneObject`：`reports/refactoring/headless-logs/mana_spend_cleanup_diagnostic.gd:89`; `reports/refactoring/headless-logs/mana_spend_deferred_diagnostic.gd:89`; `reports/round35-command-spell-action/held_skill_input/evidence/failure/target/tests/held_skill_input_test.gd:53`
- `EditMagic`：`reports/refactoring/headless-logs/mana_spend_cleanup_diagnostic.gd:46,51,61,127,148`; `reports/refactoring/headless-logs/mana_spend_deferred_diagnostic.gd:46,51,61,127,146`
- `GetLocation`：`docs/refactor-a06-a07-compare-68b556faf22044668ffd2caae802b640/evidence/area_action_rules.original.gd:56`; `docs/refactor-a06-a07-compare-68b556faf22044668ffd2caae802b640/snapshot1/area_action_rules.original.gd:56`; `docs/refactor-a06-a07-compare-68b556faf22044668ffd2caae802b640/snapshot2/area_action_rules.original.gd:56`
- `GetMoveTargetLocation`：`docs/refactor-a06-a07-compare-68b556faf22044668ffd2caae802b640/evidence/area_action_rules.original.gd:96,100`; `docs/refactor-a06-a07-compare-68b556faf22044668ffd2caae802b640/snapshot1/area_action_rules.original.gd:96,100`; `docs/refactor-a06-a07-compare-68b556faf22044668ffd2caae802b640/snapshot2/area_action_rules.original.gd:96,100`
- `IsEngaged`：`docs/refactor-a06-a07-compare-68b556faf22044668ffd2caae802b640/evidence/area_action_rules.original.gd:79`; `docs/refactor-a06-a07-compare-68b556faf22044668ffd2caae802b640/snapshot1/area_action_rules.original.gd:79`; `docs/refactor-a06-a07-compare-68b556faf22044668ffd2caae802b640/snapshot2/area_action_rules.original.gd:79`; `reports/refactoring/round42-integrated-209dfbe7d04a4b1dbdb7743b3703fc0b/evidence/freeze-first-red/copied-battle_board_v2.gd:5420`; `reports/refactoring/round42-integrated-209dfbe7d04a4b1dbdb7743b3703fc0b/evidence/freeze-first-red/current-battle_board_v2.gd:5420`
- `ManageBuff`：`reports/refactoring/headless-logs/mana_spend_cleanup_diagnostic.gd:99,103,107,113,119`; `reports/refactoring/headless-logs/mana_spend_deferred_diagnostic.gd:99,103,107,113,119`
- `Move`：`reports/refactoring/headless-logs/mana_spend_cleanup_diagnostic.gd:38,68,96`; `reports/refactoring/headless-logs/mana_spend_deferred_diagnostic.gd:38,68,96`
- `PlayAttack`：`reports/refactoring/headless-logs/mana_spend_cleanup_diagnostic.gd:76`; `reports/refactoring/headless-logs/mana_spend_deferred_diagnostic.gd:76`
- `PlaySkill`：`reports/refactoring/headless-logs/mana_spend_cleanup_diagnostic.gd:78,80`; `reports/refactoring/headless-logs/mana_spend_deferred_diagnostic.gd:78,80`
- `RegisterObjectEffects`：`reports/refactoring/headless-logs/mana_spend_cleanup_diagnostic.gd:90`; `reports/refactoring/headless-logs/mana_spend_deferred_diagnostic.gd:90`; `reports/refactoring/round33-integrated-b9fbd2011963493eaf6b76f02032de1e/evidence/failed-source/local_spell_restore_test.gd:61`; `reports/round35-command-spell-action/held_skill_input/evidence/failure/target/tests/held_skill_input_test.gd:64`; `reports/round35-command-spell-action/local_spell_restore_fail_fast/evidence/failure/target/tests/local_spell_restore_test.gd:62`
- `SetLocation`：`reports/refactoring/headless-logs/mana_spend_cleanup_diagnostic.gd:94`; `reports/refactoring/headless-logs/mana_spend_deferred_diagnostic.gd:94`
- `SumLogData`：`reports/refactoring/headless-logs/mana_spend_cleanup_diagnostic.gd:4`; `reports/refactoring/headless-logs/mana_spend_deferred_diagnostic.gd:4`
### 独立旧工作树
- `ChangePlOrder`：`.claude/worktrees/agent-a53a6b3ea94b1f0e3/assets/scripts/system/global/game_progress.gd:101`
- `DrawCardByCard`：`.claude/worktrees/agent-a53a6b3ea94b1f0e3/assets/scripts/system/effects/DiscardPlayedCards.gd:18`
- `EditMagic`：`.claude/worktrees/agent-a53a6b3ea94b1f0e3/assets/scripts/system/effects/Move.gd:11`
- `GetAllPlayersId`：`.claude/worktrees/agent-a53a6b3ea94b1f0e3/assets/scripts/system/effects/ChangePlOrder.gd:9,31`; `.claude/worktrees/agent-a53a6b3ea94b1f0e3/assets/scripts/system/effects/GetPlIdUsingEff.gd:14`
- `GetEffSourceCard`：`.claude/worktrees/agent-a53a6b3ea94b1f0e3/assets/scripts/system/effects/EditCardAttributes.gd:9`; `.claude/worktrees/agent-a53a6b3ea94b1f0e3/assets/scripts/system/effects/GetCardAttributes.gd:10`; `.claude/worktrees/agent-a53a6b3ea94b1f0e3/assets/scripts/system/effects/GetEffectNumber.gd:11`; `.claude/worktrees/agent-a53a6b3ea94b1f0e3/assets/scripts/system/effects/HasAttribute.gd:10`
- `MoveLocation`：`.claude/worktrees/agent-a53a6b3ea94b1f0e3/assets/scripts/system/effects/Move.gd:10`
- `PlayAttack`：`.claude/worktrees/agent-a53a6b3ea94b1f0e3/assets/scripts/editor/verify_play_card.gd:30`
- `SetLocation`：`.claude/worktrees/agent-a53a6b3ea94b1f0e3/assets/scripts/system/effects/Deploy.gd:7`
### Python 内嵌探针字符串
- `newtools/round74_outpost_public_retirement.py:51` `tRemoveFromBoard`：`cut='\tRemoveFromBoard.new().exec(local)'`
- `tests/round47_public_test_mutations.py:10` `BattleResolver`：`'\tvar battle := BattleResolver.new().exec([0, 1])',`
- `tests/round47_public_test_mutations.py:11` `BattleResolver`：`'\tvar wrong_source := BaseMaster.new("wrong_source", "错误来源", "", "", "")\n\tfor candidate in EffectManager.effect_pool:\n\t\tif candidate is BaseEffect and candidate._name == "scheduled_effect":\n\t\t\tcandidate.from = wrong_source\n\tvar battle := BattleResolver.new().exec([0, 1])'),`
- `tools/tests/round69_modal_hover.py:68` `CloneObject`：`var card: BaseCard = CloneObject.new().exec(models[key])`

## 9. 边界与校核
- 本清单不纳入通用数据对象 BaseNumber/BaseCard/BaseEffect 的构造、UI 控件、Crypto、网络/日志基础设施与 AI 策略 DummyBot：它们不是本次 operation 效果/规则绕过候选。对真正具有规则语义但非 exec/apply 的事件/局势/威力/败北载荷已专门补列，未用字面 regex 隐去。
- `BaseFunc` 的通用 clone/get_script().new、LoadHelper 的数据动态 load/new 是正常动态调用机制，不按某个效果类的“代码显式直连”计数；其路径在正文给出以区别 TABLE 目录的作用。
- `BoardPowerQuery` 的特殊 `foreach_func` / `store_value` / `get_eff_source_card` / `log_exists` 是本类内联解释分支，不是实例化相应 ForEach/Get 等 class；没有凭 descriptor 名虚增对应 class。
- A/B/C 全部类名、TABLE 唯一性、JSON 引用出现次数、19 条贡献的逐条清单均由程序集合/计数核对；语义及时点证据来自实际调用点和定义，不按命名猜测。
- 生产类定义、生产调用者及全部时点证据源文件已与磁盘再次比对，未变化；扫描期间新增测试文件已纳入排除区复扫。本报告不包含改代码建议。
