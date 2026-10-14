# 时点效果与 operation 实现只读盘点

## 结论摘要
- 真正的时点常量 **218** 个；另有 SELF_PREFIX/OTHERS_PREFIX 两个字符串前缀辅助常量（原始字符串常量合计 220），不是事件。已找到生产派发/持续窗口入口 **168** 个；无当前生产派发 **50** 个；静态映射 unknown=0。这里“已派发”指存在源码路径，不声称某次运行实际触发。
- 正式 data/** 共 71 个 JSON、135 条效果对象（含 1 条 build_effect 参数内嵌效果）；105 条有 time_points：77 条自动、28 条手动窗口。其普通执行描述共 1042 条，全部注册且具有对应 exec 文件；**没有发现这 105 条用未注册 func_name 代替 operation 的执行体**。但其中 2 条只含 do_nothing，不算功能实现。
- 4 条受空心派发影响的效果：美狄亚部署收益；远坂凛与葛木的自己战斗阶段结束效果；美杜莎石化延迟效果（目标 self_battle_phase_start）。前 3 条没有入口，后 1 条初始发动有入口但延迟目标没有入口。
- B 类按“互不重叠的处理职责块”登记 **29 条**：可将动作/固定生命周期策略改为 operation+数据 **14 条**，必须保留在派发/匹配/执行运行时 **15 条**。29 不是卡牌数量、也不是常量引用次数。若严格只统计读取/筛选特定已命名时点的非 operation 消费块，计 **5 条**：B01/B18/B21/B22/B23；其中只有 B01 是业务到期副作用，其余 4 条是引擎时点语义。扩展的 B02–B14 等显式标注为生命周期邻接动作，不冒充“比较常量后执行卡面效果”。
- 19 条未注册 contribution 描述全部在 power_query、所属 19 条效果的 time_points=[]；**不属于时点触发类效果**。源码没有相应 *Contribution.new().exec 调用；真实实现是 BoardPowerQuery.evaluate_one 的内联解释分支（125–156 行）。上下文“直接 new”说法不适用于当前读到的树。

## 范围、证据强度与只读约束
- 仓库：`E:/Projects/Godot/FateDominationGame-master`；HEAD：`8c0f946faf6cc0cd3f04f12f66f5a99a413088ca`，但工作树已有大量修改，本报告以读取到的当前源码为准，不把 HEAD 当冻结版本。
- 已读 hermesWarning.txt、CLAUDE.md、fate-domination-engine 及 effect-engine-rules；扫描 scripts 下 419 个 GDScript 的全部文本、71 个正式 JSON 的完整结构；逐段人工语义审阅下文涉及的派发器、效果引擎、流程与 operation。注册表 214 项，214 个类路径均存在且声明 exec，PascalCase 动态加载映射一致。未人工逐句解释 419 个文件的全部无关逻辑；文本扫描≠全部语义覆盖。
- 仓库全树 1800 个 .gd 另做时点符号筛选；tests/newtests、reports 快照、.claude/worktrees 不是当前生产派发源，不能用测试人工派发补齐空心声明。UI 日志格式化、网络/大厅 phase、动作名 move/deploy、GameLog.record 的 type/tags 与时点同名但并非事件派发，已排除。
- 动态前缀、phases 表、牌区映射、begin_pending_action、card_revealed、可变字符串 EmitTimePoint 均追踪。通用入口可接任意字符串，**不等于每个常量已有具体生产调用**；data 中 emit_time_point 使用为 0。
- 审计期间仅发现 scripts/net/session/lobby_session.gd 被其他工作改动；重读核对其时点派发/常量引用未变化。所有 scripts/system 审计源码及 JSON 与最初读取一致。未修改仓库、未启动 Godot、未触碰 PID 17120/28100；仅写本报告。
- 静态查证可断言入口存在/缺失；引擎解析、真实可达性、逐卡运行结果、用户自选外部数据、网络实战：**unknown（本轮禁止启动 Godot，未运行）**。不可据本报告宣称 105 条效果均正确可用。

## 1. 全部时点：派发与数据驱动表
表中的“数据驱动”指**响应效果体**是否能走 JSON→BaseEffect→operation，不是宣称派发器由 JSON 创建：大多数事实派发是引擎/operation 代码产生。`接口支持，当前0` 不是已有卡面效果；未派发一律写否。监听数只统计正式效果 time_points 字段，延迟目标和到期字段另列。

公共链：global_time_point `time_point_checker.gd:26–38` → run_time_point；dynamic_time_point `:110–131` → 原值加玩家前缀，其中 self 生成 `:115`、others 生成 `:125`。pending 事件是 `effect_manager.gd:1045–1091` 的同步匹配，不写 current_time_points，却是真实派发；只支持强制非手动监听。窗口 set_phase_time_points `time_point_checker.gd:14–21`/time_point_update `:139–143` 本身不执行效果，后续事件/检查才消费该窗口。

| 时点（常量名 / 值 / 声明行） | 是否已被派发 | 真实派发点（仓库相对路径:行） | 是否数据驱动 |
|---|---|---|---|
| `SKILL_AWAKENED` / `skill_awakened` / :10 | 是（源码入口） | `scripts/system/operations/AwakenSkill.gd:19` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_SKILL_AWAKENED` / `self_skill_awakened` / :11 | 是（源码入口） | `scripts/system/operations/AwakenSkill.gd:19` [dynamic→prefix] | 是：JSON+operation 监听 7 条 |
| `OTHERS_SKILL_AWAKENED` / `others_skill_awakened` / :12 | 是（源码入口） | `scripts/system/operations/AwakenSkill.gd:19` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `GAME_START` / `game_start` / :14 | 是（源码入口） | `scripts/system/global/game_progress.gd:144` [global] | 是：JSON+operation 监听 14 条 |
| `GAME` / `game` / :15 | 是（源码入口） | `scripts/system/global/game_progress.gd:138` [window] | 是：JSON+operation 监听 1 条 |
| `GAME_END` / `game_end` / :16 | 是（源码入口） | `scripts/system/global/game_progress.gd:220` [global] | 响应接口支持；现正式监听0 |
| `PREPARE_PHASE_START` / `prepare_phase_start` / :18 | 是（源码入口） | `scripts/system/global/game_progress.gd:425 ← phases:59–79` [global] | 响应接口支持；现正式监听0 |
| `PREPARE_PHASE` / `prepare_phase` / :19 | 是（源码入口） | `scripts/system/global/game_progress.gd:409–411` [window]；`scripts/system/global/game_progress.gd:574–579 ← effective_phase_mids:117–123` [dynamic] | 响应接口支持；现正式监听0 |
| `PREPARE_PHASE_END` / `prepare_phase_end` / :20 | 是（源码入口） | `scripts/system/global/game_progress.gd:535 ← phases:59–79` [global] | 响应接口支持；现正式监听0 |
| `SELF_PREPARE_PHASE_START` / `self_prepare_phase_start` / :21 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `SELF_PREPARE_PHASE` / `self_prepare_phase` / :22 | 是（源码入口） | `scripts/system/global/game_progress.gd:574–579 ← effective_phase_mids:117–123` [dynamic→prefix] | 是：JSON+operation 监听 2 条 |
| `SELF_PREPARE_PHASE_END` / `self_prepare_phase_end` / :23 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `OTHERS_PREPARE_PHASE_START` / `others_prepare_phase_start` / :24 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `OTHERS_PREPARE_PHASE` / `others_prepare_phase` / :25 | 是（源码入口） | `scripts/system/global/game_progress.gd:574–579 ← effective_phase_mids:117–123` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_PREPARE_PHASE_END` / `others_prepare_phase_end` / :26 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `OUTPOST_PHASE_START` / `outpost_phase_start` / :28 | 是（源码入口） | `scripts/system/global/game_progress.gd:425 ← phases:59–79` [global] | 响应接口支持；现正式监听0 |
| `OUTPOST_PHASE` / `outpost_phase` / :29 | 是（源码入口） | `scripts/system/global/game_progress.gd:409–411` [window]；`scripts/system/global/game_progress.gd:574–579 ← effective_phase_mids:117–123` [dynamic] | 响应接口支持；现正式监听0 |
| `OUTPOST_PHASE_END` / `outpost_phase_end` / :30 | 是（源码入口） | `scripts/system/global/game_progress.gd:535 ← phases:59–79` [global] | 响应接口支持；现正式监听0 |
| `SELF_OUTPOST_PHASE_START` / `self_outpost_phase_start` / :31 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `SELF_OUTPOST_PHASE` / `self_outpost_phase` / :32 | 是（源码入口） | `scripts/system/global/game_progress.gd:574–579 ← effective_phase_mids:117–123` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `SELF_OUTPOST_PHASE_END` / `self_outpost_phase_end` / :33 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `OTHERS_OUTPOST_PHASE_START` / `others_outpost_phase_start` / :34 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `OTHERS_OUTPOST_PHASE` / `others_outpost_phase` / :35 | 是（源码入口） | `scripts/system/global/game_progress.gd:574–579 ← effective_phase_mids:117–123` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_OUTPOST_PHASE_END` / `others_outpost_phase_end` / :36 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `ACTION_PHASE_START` / `action_phase_start` / :38 | 是（源码入口） | `scripts/system/global/game_progress.gd:425 ← phases:59–79` [global] | 响应接口支持；现正式监听0 |
| `ACTION_PHASE` / `action_phase` / :39 | 是（源码入口） | `scripts/system/global/game_progress.gd:409–411` [window]；`scripts/system/global/game_progress.gd:574–579 ← effective_phase_mids:117–123` [dynamic] | 响应接口支持；现正式监听0 |
| `ACTION_PHASE_END` / `action_phase_end` / :40 | 是（源码入口） | `scripts/system/global/game_progress.gd:535 ← phases:59–79` [global] | 响应接口支持；现正式监听0 |
| `SELF_ACTION_PHASE_START` / `self_action_phase_start` / :41 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `SELF_ACTION_PHASE` / `self_action_phase` / :42 | 是（源码入口） | `scripts/system/global/game_progress.gd:574–579 ← effective_phase_mids:117–123` [dynamic→prefix] | 是：JSON+operation 监听 18 条 |
| `SELF_ACTION_PHASE_END` / `self_action_phase_end` / :43 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `OTHERS_ACTION_PHASE_START` / `others_action_phase_start` / :44 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `OTHERS_ACTION_PHASE` / `others_action_phase` / :45 | 是（源码入口） | `scripts/system/global/game_progress.gd:574–579 ← effective_phase_mids:117–123` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_ACTION_PHASE_END` / `others_action_phase_end` / :46 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `BATTLE_PHASE_START` / `battle_phase_start` / :48 | 是（源码入口） | `scripts/system/global/game_progress.gd:425 ← phases:59–79` [global] | 响应接口支持；现正式监听0 |
| `BATTLE_PHASE` / `battle_phase` / :49 | 是（源码入口） | `scripts/system/global/game_progress.gd:409–411` [window]；`scripts/system/global/game_progress.gd:574–579 ← effective_phase_mids:117–123` [dynamic] | 响应接口支持；现正式监听0 |
| `BATTLE_PHASE_END` / `battle_phase_end` / :50 | 是（源码入口） | `scripts/system/global/game_progress.gd:535 ← phases:59–79` [global] | 响应接口支持；现正式监听0 |
| `SELF_BATTLE_PHASE_START` / `self_battle_phase_start` / :51 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `SELF_BATTLE_PHASE` / `self_battle_phase` / :52 | 是（源码入口） | `scripts/system/global/game_progress.gd:574–579 ← effective_phase_mids:117–123` [dynamic→prefix] | 是：JSON+operation 监听 20 条 |
| `SELF_BATTLE_PHASE_END` / `self_battle_phase_end` / :53 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 2 条 |
| `OTHERS_BATTLE_PHASE_START` / `others_battle_phase_start` / :54 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `OTHERS_BATTLE_PHASE` / `others_battle_phase` / :55 | 是（源码入口） | `scripts/system/global/game_progress.gd:574–579 ← effective_phase_mids:117–123` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_BATTLE_PHASE_END` / `others_battle_phase_end` / :56 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `PHASE_START` / `phase_start` / :58 | 是（源码入口） | `scripts/system/global/game_progress.gd:425` [global] | 响应接口支持；现正式监听0 |
| `PHASE` / `phase` / :59 | 是（源码入口） | `scripts/system/global/game_progress.gd:409–411` [window] | 响应接口支持；现正式监听0 |
| `PHASE_END` / `phase_end` / :60 | 是（源码入口） | `scripts/system/global/game_progress.gd:535` [global] | 响应接口支持；现正式监听0 |
| `SELF_PHASE_START` / `self_phase_start` / :61 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `SELF_PHASE` / `self_phase` / :62 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `SELF_PHASE_END` / `self_phase_end` / :63 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `OTHERS_PHASE_START` / `others_phase_start` / :64 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `OTHERS_PHASE` / `others_phase` / :65 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `OTHERS_PHASE_END` / `others_phase_end` / :66 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `DAY_START` / `day_start` / :68 | 是（源码入口） | `scripts/system/global/game_progress.gd:284` [global] | 是：JSON+operation 监听 3 条 |
| `DAY` / `day` / :69 | 是（源码入口） | `scripts/system/global/game_progress.gd:265` [window]；`scripts/system/global/game_progress.gd:318` [window] | 响应接口支持；现正式监听0 |
| `DAY_END` / `day_end` / :70 | 是（源码入口） | `scripts/system/global/game_progress.gd:319` [global] | 是：JSON+operation 监听 8 条 |
| `PLAYED_CARD` / `played_card` / :72 | 是（源码入口） | `scripts/system/regular_play.gd:376` [dynamic]；`scripts/system/operations/AddAttack.gd:29` [dynamic]；`scripts/system/operations/AddSkill.gd:31` [dynamic]；`scripts/system/operations/PlayAttack.gd:91` [dynamic]；`scripts/system/operations/PlayedCards.gd:7` [dynamic]；`scripts/system/operations/PlaySkill.gd:62` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_PLAYED_CARD` / `self_played_card` / :73 | 是（源码入口） | `scripts/system/regular_play.gd:376` [dynamic→prefix]；`scripts/system/operations/AddAttack.gd:29` [dynamic→prefix]；`scripts/system/operations/AddSkill.gd:31` [dynamic→prefix]；`scripts/system/operations/PlayAttack.gd:91` [dynamic→prefix]；`scripts/system/operations/PlayedCards.gd:7` [dynamic→prefix]；`scripts/system/operations/PlaySkill.gd:62` [dynamic→prefix] | 是：JSON+operation 监听 8 条 |
| `OTHERS_PLAYED_CARD` / `others_played_card` / :74 | 是（源码入口） | `scripts/system/regular_play.gd:376` [dynamic→prefix]；`scripts/system/operations/AddAttack.gd:29` [dynamic→prefix]；`scripts/system/operations/AddSkill.gd:31` [dynamic→prefix]；`scripts/system/operations/PlayAttack.gd:91` [dynamic→prefix]；`scripts/system/operations/PlayedCards.gd:7` [dynamic→prefix]；`scripts/system/operations/PlaySkill.gd:62` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `MAGIC_ADD` / `magic_add` / :76 | 是（源码入口） | `scripts/system/operations/EditMagic.gd:43` [dynamic] | 响应接口支持；现正式监听0 |
| `MAGIC_DECREASE` / `magic_decrease` / :77 | 是（源码入口） | `scripts/system/operations/EditMagic.gd:45` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_MAGIC_ADD` / `self_magic_add` / :78 | 是（源码入口） | `scripts/system/operations/EditMagic.gd:43` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `SELF_MAGIC_DECREASE` / `self_magic_decrease` / :79 | 是（源码入口） | `scripts/system/operations/EditMagic.gd:45` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_MAGIC_ADD` / `others_magic_add` / :80 | 是（源码入口） | `scripts/system/operations/EditMagic.gd:43` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_MAGIC_DECREASE` / `others_magic_decrease` / :81 | 是（源码入口） | `scripts/system/operations/EditMagic.gd:45` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `SCORE_ADD` / `score_add` / :83 | 是（源码入口） | `scripts/system/operations/EditScore.gd:30` [dynamic] | 响应接口支持；现正式监听0 |
| `SCORE_DECREASE` / `score_decrease` / :84 | 是（源码入口） | `scripts/system/operations/EditScore.gd:32` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_SCORE_ADD` / `self_score_add` / :85 | 是（源码入口） | `scripts/system/operations/EditScore.gd:30` [dynamic→prefix] | 是：JSON+operation 监听 1 条 |
| `SELF_SCORE_DECREASE` / `self_score_decrease` / :86 | 是（源码入口） | `scripts/system/operations/EditScore.gd:32` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_SCORE_ADD` / `others_score_add` / :87 | 是（源码入口） | `scripts/system/operations/EditScore.gd:30` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_SCORE_DECREASE` / `others_score_decrease` / :88 | 是（源码入口） | `scripts/system/operations/EditScore.gd:32` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `LIVES_ADD` / `lives_add` / :90 | 是（源码入口） | `scripts/system/operations/EditLives.gd:16` [dynamic] | 响应接口支持；现正式监听0 |
| `LIVES_DECREASE` / `lives_decrease` / :91 | 是（源码入口） | `scripts/system/operations/EditLives.gd:18` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_LIVES_ADD` / `self_lives_add` / :92 | 是（源码入口） | `scripts/system/operations/EditLives.gd:16` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `SELF_LIVES_DECREASE` / `self_lives_decrease` / :93 | 是（源码入口） | `scripts/system/operations/EditLives.gd:18` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_LIVES_ADD` / `others_lives_add` / :94 | 是（源码入口） | `scripts/system/operations/EditLives.gd:16` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_LIVES_DECREASE` / `others_lives_decrease` / :95 | 是（源码入口） | `scripts/system/operations/EditLives.gd:18` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `LAST_LIFE` / `last_life` / :97 | 是（源码入口） | `scripts/system/operations/EditLives.gd:28` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_LAST_LIFE` / `self_last_life` / :98 | 是（源码入口） | `scripts/system/operations/EditLives.gd:28` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_LAST_LIFE` / `others_last_life` / :99 | 是（源码入口） | `scripts/system/operations/EditLives.gd:28` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `ELIMINATED` / `eliminated` / :101 | 是（源码入口） | `scripts/system/global/climax_resolver.gd:58` [dynamic]；`scripts/system/operations/EditLives.gd:26` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_ELIMINATED` / `self_eliminated` / :102 | 是（源码入口） | `scripts/system/global/climax_resolver.gd:58` [dynamic→prefix]；`scripts/system/operations/EditLives.gd:26` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_ELIMINATED` / `others_eliminated` / :103 | 是（源码入口） | `scripts/system/global/climax_resolver.gd:58` [dynamic→prefix]；`scripts/system/operations/EditLives.gd:26` [dynamic→prefix] | 是：JSON+operation 监听 1 条 |
| `BATTLE_WIN` / `battle_win` / :105 | 是（源码入口） | `scripts/system/global/battle_resolver.gd:210` [dynamic]；`scripts/system/global/battle_resolver.gd:218` [dynamic] | 响应接口支持；现正式监听0 |
| `BATTLE` / `battle` / :106 | 是（源码入口） | `scripts/system/global/battle_resolver.gd:57` [dynamic] | 响应接口支持；现正式监听0 |
| `BATTLE_LOSE` / `battle_lose` / :107 | 是（源码入口） | `scripts/system/global/battle_resolver.gd:245` [dynamic]；`scripts/system/operations/Defeat.gd:13` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_BATTLE_WIN` / `self_battle_win` / :108 | 是（源码入口） | `scripts/system/global/battle_resolver.gd:210` [dynamic→prefix]；`scripts/system/global/battle_resolver.gd:218` [dynamic→prefix] | 是：JSON+operation 监听 2 条 |
| `SELF_BATTLE` / `self_battle` / :109 | 是（源码入口） | `scripts/system/global/battle_resolver.gd:57` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `SELF_BATTLE_LOSE` / `self_battle_lose` / :110 | 是（源码入口） | `scripts/system/global/battle_resolver.gd:245` [dynamic→prefix]；`scripts/system/operations/Defeat.gd:13` [dynamic→prefix] | 是：JSON+operation 监听 4 条 |
| `OTHERS_BATTLE_WIN` / `others_battle_win` / :111 | 是（源码入口） | `scripts/system/global/battle_resolver.gd:210` [dynamic→prefix]；`scripts/system/global/battle_resolver.gd:218` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_BATTLE` / `others_battle` / :112 | 是（源码入口） | `scripts/system/global/battle_resolver.gd:57` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_BATTLE_LOSE` / `others_battle_lose` / :113 | 是（源码入口） | `scripts/system/global/battle_resolver.gd:245` [dynamic→prefix]；`scripts/system/operations/Defeat.gd:13` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `BATTLE_RESOLVE` / `battle_resolve` / :114 | 是（源码入口） | `scripts/system/global/battle_resolver.gd:62` [global] | 响应接口支持；现正式监听0 |
| `CARD_REVEALED` / `card_revealed` / :123 | 是（源码入口） | `scripts/system/global/time_point_checker.gd:53–57` [global] | 响应接口支持；现正式监听0 |
| `SELF_CARD_REVEALED` / `self_card_revealed` / :124 | 是（源码入口） | `scripts/system/global/time_point_checker.gd:53–57` [global] | 是：JSON+operation 监听 9 条 |
| `OTHERS_CARD_REVEALED` / `others_card_revealed` / :125 | 是（源码入口） | `scripts/system/global/time_point_checker.gd:53–57` [global] | 响应接口支持；现正式监听0 |
| `BATTLE_END` / `battle_end` / :126 | 是（源码入口） | `scripts/system/global/battle_resolver.gd:78` [global] | 是：JSON+operation 监听 2 条 |
| `CLIMAX_START` / `climax_start` / :128 | 是（源码入口） | `scripts/system/global/game_progress.gd:323` [global] | 响应接口支持；现正式监听0 |
| `CLIMAX` / `climax` / :129 | 是（源码入口） | `scripts/system/global/game_progress.gd:409–411` [window]；`scripts/system/global/game_progress.gd:574–579` [dynamic] | 响应接口支持；现正式监听0 |
| `CLIMAX_END` / `climax_end` / :130 | 是（源码入口） | `scripts/system/global/game_progress.gd:329` [global] | 响应接口支持；现正式监听0 |
| `SELF_CLIMAX_START` / `self_climax_start` / :131 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `SELF_CLIMAX` / `self_climax` / :132 | 是（源码入口） | `scripts/system/global/game_progress.gd:574–579` [dynamic→prefix] | 是：JSON+operation 监听 3 条 |
| `SELF_CLIMAX_END` / `self_climax_end` / :133 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `OTHERS_CLIMAX_START` / `others_climax_start` / :134 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `OTHERS_CLIMAX` / `others_climax` / :135 | 是（源码入口） | `scripts/system/global/game_progress.gd:574–579` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_CLIMAX_END` / `others_climax_end` / :136 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `NON_CLIMAX` / `non_climax` / :139 | 是（源码入口） | `scripts/system/global/game_progress.gd:409–411` [window]；`scripts/system/global/game_progress.gd:574–579` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_NON_CLIMAX` / `self_non_climax` / :140 | 是（源码入口） | `scripts/system/global/game_progress.gd:574–579` [dynamic→prefix] | 是：JSON+operation 监听 1 条 |
| `OTHERS_NON_CLIMAX` / `others_non_climax` / :141 | 是（源码入口） | `scripts/system/global/game_progress.gd:574–579` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `DEPLOY_START` / `deploy_start` / :143 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `DEPLOY` / `deploy` / :144 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `DEPLOY_END` / `deploy_end` / :145 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `SELF_DEPLOY_START` / `self_deploy_start` / :146 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `SELF_DEPLOY` / `self_deploy` / :147 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 1 条 |
| `SELF_DEPLOY_END` / `self_deploy_end` / :148 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `OTHERS_DEPLOY_START` / `others_deploy_start` / :149 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `OTHERS_DEPLOY` / `others_deploy` / :150 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `OTHERS_DEPLOY_END` / `others_deploy_end` / :151 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `MOVE_START` / `move_start` / :153 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `MOVE` / `move` / :154 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `MOVE_END` / `move_end` / :155 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `SELF_MOVE_START` / `self_move_start` / :156 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `SELF_MOVE` / `self_move` / :157 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `SELF_MOVE_END` / `self_move_end` / :158 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `OTHERS_MOVE_START` / `others_move_start` / :159 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `OTHERS_MOVE` / `others_move` / :160 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `OTHERS_MOVE_END` / `others_move_end` / :161 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `EFFECT_START` / `effect_start` / :163 | 是（源码入口） | `scripts/system/global/effect_manager.gd:2483` [pending] | 响应接口支持；现正式监听0；仅同步强制监听 |
| `EFFECT_END` / `effect_end` / :164 | 是（源码入口） | `scripts/system/global/effect_manager.gd:2617` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_EFFECT_START` / `self_effect_start` / :165 | 是（源码入口） | `scripts/system/global/effect_manager.gd:2483` [pending→prefix] | 响应接口支持；现正式监听0；仅同步强制监听 |
| `SELF_EFFECT_END` / `self_effect_end` / :166 | 是（源码入口） | `scripts/system/global/effect_manager.gd:2617` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_EFFECT_START` / `others_effect_start` / :167 | 是（源码入口） | `scripts/system/global/effect_manager.gd:2483` [pending→prefix] | 响应接口支持；现正式监听0；仅同步强制监听 |
| `OTHERS_EFFECT_END` / `others_effect_end` / :168 | 是（源码入口） | `scripts/system/global/effect_manager.gd:2617` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `BUFF_START` / `buff_start` / :170 | 是（源码入口） | `scripts/system/operations/ManageBuff.gd:18` [dynamic] | 响应接口支持；现正式监听0 |
| `BUFF` / `buff` / :171 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `BUFF_END` / `buff_end` / :172 | 是（源码入口） | `scripts/system/operations/ManageBuff.gd:26` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_BUFF_START` / `self_buff_start` / :173 | 是（源码入口） | `scripts/system/operations/ManageBuff.gd:18` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `SELF_BUFF` / `self_buff` / :174 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `SELF_BUFF_END` / `self_buff_end` / :175 | 是（源码入口） | `scripts/system/operations/ManageBuff.gd:26` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_BUFF_START` / `others_buff_start` / :176 | 是（源码入口） | `scripts/system/operations/ManageBuff.gd:18` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_BUFF` / `others_buff` / :177 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `OTHERS_BUFF_END` / `others_buff_end` / :178 | 是（源码入口） | `scripts/system/operations/ManageBuff.gd:26` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `TRUE_NAME_RELEASE` / `true_name_release` / :180 | 是（源码入口） | `scripts/system/operations/ReleaseTrueName.gd:53` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_TRUE_NAME_RELEASE` / `self_true_name_release` / :181 | 是（源码入口） | `scripts/system/operations/ReleaseTrueName.gd:53` [dynamic→prefix] | 是：JSON+operation 监听 3 条 |
| `OTHERS_TRUE_NAME_RELEASE` / `others_true_name_release` / :182 | 是（源码入口） | `scripts/system/operations/ReleaseTrueName.gd:53` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `TRUE_NAME_HIDDEN` / `true_name_hidden` / :184 | 是（源码入口） | `scripts/system/operations/HideTrueName.gd:38` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_TRUE_NAME_HIDDEN` / `self_true_name_hidden` / :185 | 是（源码入口） | `scripts/system/operations/HideTrueName.gd:38` [dynamic→prefix] | 是：JSON+operation 监听 3 条 |
| `OTHERS_TRUE_NAME_HIDDEN` / `others_true_name_hidden` / :186 | 是（源码入口） | `scripts/system/operations/HideTrueName.gd:38` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `CARD_CLOSED` / `card_closed` / :188 | 是（源码入口） | `scripts/system/operations/CloseCard.gd:31` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_CARD_CLOSED` / `self_card_closed` / :189 | 是（源码入口） | `scripts/system/operations/CloseCard.gd:31` [dynamic→prefix] | 是：JSON+operation 监听 1 条 |
| `OTHERS_CARD_CLOSED` / `others_card_closed` / :190 | 是（源码入口） | `scripts/system/operations/CloseCard.gd:31` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `COMMAND_SPELL_USED` / `command_spell_used` / :192 | 是（源码入口） | `scripts/system/global/effect_manager.gd:1599` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_COMMAND_SPELL_USED` / `self_command_spell_used` / :193 | 是（源码入口） | `scripts/system/global/effect_manager.gd:1599` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_COMMAND_SPELL_USED` / `others_command_spell_used` / :194 | 是（源码入口） | `scripts/system/global/effect_manager.gd:1599` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `LOCATION_BENEFIT_CHANGED` / `location_benefit_changed` / :196 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `SELF_LOCATION_BENEFIT_CHANGED` / `self_location_benefit_changed` / :197 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `OTHERS_LOCATION_BENEFIT_CHANGED` / `others_location_benefit_changed` / :198 | 否 | —（无具体生产调用；泛型 emit 不计） | 否：无派发；JSON监听 0 条 |
| `CARD_COST_CALCULATED` / `card_cost_calculated` / :200 | 是（源码入口） | `scripts/system/regular_play.gd:341` [dynamic]；`scripts/system/operations/PlayAttack.gd:55` [dynamic]；`scripts/system/operations/PlaySkill.gd:33` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_CARD_COST_CALCULATED` / `self_card_cost_calculated` / :201 | 是（源码入口） | `scripts/system/regular_play.gd:341` [dynamic→prefix]；`scripts/system/operations/PlayAttack.gd:55` [dynamic→prefix]；`scripts/system/operations/PlaySkill.gd:33` [dynamic→prefix] | 是：JSON+operation 监听 2 条 |
| `OTHERS_CARD_COST_CALCULATED` / `others_card_cost_calculated` / :202 | 是（源码入口） | `scripts/system/regular_play.gd:341` [dynamic→prefix]；`scripts/system/operations/PlayAttack.gd:55` [dynamic→prefix]；`scripts/system/operations/PlaySkill.gd:33` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `ROUND_START_RESET` / `round_start_reset` / :204 | 是（源码入口） | `scripts/system/global/game_progress.gd:262` [dynamic] | 响应接口支持；现正式监听0 |
| `CARD_TO_HAND` / `card_to_hand` / :209 | 是（源码入口） | `scripts/system/card_zones.gd:104–106 ← ENTER_POINTS:12–18` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_CARD_TO_HAND` / `self_card_to_hand` / :210 | 是（源码入口） | `scripts/system/card_zones.gd:104–106 ← ENTER_POINTS:12–18` [dynamic→prefix] | 是：JSON+operation 监听 1 条 |
| `OTHERS_CARD_TO_HAND` / `others_card_to_hand` / :211 | 是（源码入口） | `scripts/system/card_zones.gd:104–106 ← ENTER_POINTS:12–18` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `CARD_TO_DISCARD` / `card_to_discard` / :213 | 是（源码入口） | `scripts/system/card_zones.gd:104–106 ← ENTER_POINTS:12–18` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_CARD_TO_DISCARD` / `self_card_to_discard` / :214 | 是（源码入口） | `scripts/system/card_zones.gd:104–106 ← ENTER_POINTS:12–18` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_CARD_TO_DISCARD` / `others_card_to_discard` / :215 | 是（源码入口） | `scripts/system/card_zones.gd:104–106 ← ENTER_POINTS:12–18` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `CARD_TO_DECK` / `card_to_deck` / :217 | 是（源码入口） | `scripts/system/card_zones.gd:104–106 ← ENTER_POINTS:12–18` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_CARD_TO_DECK` / `self_card_to_deck` / :218 | 是（源码入口） | `scripts/system/card_zones.gd:104–106 ← ENTER_POINTS:12–18` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_CARD_TO_DECK` / `others_card_to_deck` / :219 | 是（源码入口） | `scripts/system/card_zones.gd:104–106 ← ENTER_POINTS:12–18` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `CARD_LEAVE_DECK` / `card_leave_deck` / :221 | 是（源码入口） | `scripts/system/card_zones.gd:96–98 ← LEAVE_POINTS:22` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_CARD_LEAVE_DECK` / `self_card_leave_deck` / :222 | 是（源码入口） | `scripts/system/card_zones.gd:96–98 ← LEAVE_POINTS:22` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_CARD_LEAVE_DECK` / `others_card_leave_deck` / :223 | 是（源码入口） | `scripts/system/card_zones.gd:96–98 ← LEAVE_POINTS:22` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `CARD_TO_SKILL_ZONE` / `card_to_skill_zone` / :225 | 是（源码入口） | `scripts/system/card_zones.gd:104–106 ← ENTER_POINTS:12–18` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_CARD_TO_SKILL_ZONE` / `self_card_to_skill_zone` / :226 | 是（源码入口） | `scripts/system/card_zones.gd:104–106 ← ENTER_POINTS:12–18` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_CARD_TO_SKILL_ZONE` / `others_card_to_skill_zone` / :227 | 是（源码入口） | `scripts/system/card_zones.gd:104–106 ← ENTER_POINTS:12–18` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `CARD_REMOVED` / `card_removed` / :229 | 是（源码入口） | `scripts/system/card_zones.gd:104–106 ← ENTER_POINTS:12–18` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_CARD_REMOVED` / `self_card_removed` / :230 | 是（源码入口） | `scripts/system/card_zones.gd:104–106 ← ENTER_POINTS:12–18` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_CARD_REMOVED` / `others_card_removed` / :231 | 是（源码入口） | `scripts/system/card_zones.gd:104–106 ← ENTER_POINTS:12–18` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `CARD_DRAWN` / `card_drawn` / :233 | 是（源码入口） | `scripts/system/operations/DrawCardFromPlDeckToHand.gd:26` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_CARD_DRAWN` / `self_card_drawn` / :234 | 是（源码入口） | `scripts/system/operations/DrawCardFromPlDeckToHand.gd:26` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_CARD_DRAWN` / `others_card_drawn` / :235 | 是（源码入口） | `scripts/system/operations/DrawCardFromPlDeckToHand.gd:26` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `DECK_RESHUFFLED` / `deck_reshuffled` / :237 | 是（源码入口） | `scripts/system/operations/ReshuffleDiscard.gd:27` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_DECK_RESHUFFLED` / `self_deck_reshuffled` / :238 | 是（源码入口） | `scripts/system/operations/ReshuffleDiscard.gd:27` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_DECK_RESHUFFLED` / `others_deck_reshuffled` / :239 | 是（源码入口） | `scripts/system/operations/ReshuffleDiscard.gd:27` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `ENTER_LOCATION` / `enter_location` / :241 | 是（源码入口） | `scripts/system/operations/SetLocation.gd:61` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_ENTER_LOCATION` / `self_enter_location` / :242 | 是（源码入口） | `scripts/system/operations/SetLocation.gd:61` [dynamic→prefix] | 是：JSON+operation 监听 1 条 |
| `OTHERS_ENTER_LOCATION` / `others_enter_location` / :243 | 是（源码入口） | `scripts/system/operations/SetLocation.gd:61` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `LEAVE_LOCATION` / `leave_location` / :245 | 是（源码入口） | `scripts/system/operations/RemoveFromBoard.gd:22` [dynamic]；`scripts/system/operations/SetLocation.gd:60` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_LEAVE_LOCATION` / `self_leave_location` / :246 | 是（源码入口） | `scripts/system/operations/RemoveFromBoard.gd:22` [dynamic→prefix]；`scripts/system/operations/SetLocation.gd:60` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_LEAVE_LOCATION` / `others_leave_location` / :247 | 是（源码入口） | `scripts/system/operations/RemoveFromBoard.gd:22` [dynamic→prefix]；`scripts/system/operations/SetLocation.gd:60` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `CARD_FACE_FLIPPED` / `card_face_flipped` / :249 | 是（源码入口） | `scripts/system/operations/FlipCardFace.gd:41` [dynamic]；`scripts/system/operations/FlipCardFace.gd:43` [global] | 响应接口支持；现正式监听0 |
| `SELF_CARD_FACE_FLIPPED` / `self_card_face_flipped` / :250 | 是（源码入口） | `scripts/system/operations/FlipCardFace.gd:41` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_CARD_FACE_FLIPPED` / `others_card_face_flipped` / :251 | 是（源码入口） | `scripts/system/operations/FlipCardFace.gd:41` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `BEFORE_ELIMINATE` / `before_eliminate` / :253 | 是（源码入口） | `scripts/system/global/climax_resolver.gd:44` [pending]；`scripts/system/operations/EditLives.gd:22` [pending] | 响应接口支持；现正式监听0；仅同步强制监听 |
| `SELF_BEFORE_ELIMINATE` / `self_before_eliminate` / :254 | 是（源码入口） | `scripts/system/global/climax_resolver.gd:44` [pending→prefix]；`scripts/system/operations/EditLives.gd:22` [pending→prefix] | 是：JSON+operation 监听 1 条；仅同步强制监听 |
| `OTHERS_BEFORE_ELIMINATE` / `others_before_eliminate` / :255 | 是（源码入口） | `scripts/system/global/climax_resolver.gd:44` [pending→prefix]；`scripts/system/operations/EditLives.gd:22` [pending→prefix] | 响应接口支持；现正式监听0；仅同步强制监听 |
| `BEFORE_DEFEAT` / `before_defeat` / :257 | 是（源码入口） | `scripts/system/operations/Defeat.gd:10` [pending] | 响应接口支持；现正式监听0；仅同步强制监听 |
| `SELF_BEFORE_DEFEAT` / `self_before_defeat` / :258 | 是（源码入口） | `scripts/system/operations/Defeat.gd:10` [pending→prefix] | 是：JSON+operation 监听 1 条；仅同步强制监听 |
| `OTHERS_BEFORE_DEFEAT` / `others_before_defeat` / :259 | 是（源码入口） | `scripts/system/operations/Defeat.gd:10` [pending→prefix] | 响应接口支持；现正式监听0；仅同步强制监听 |
| `BEFORE_CARD_CLOSE` / `before_card_close` / :261 | 是（源码入口） | `scripts/system/operations/CloseCard.gd:14` [pending] | 响应接口支持；现正式监听0；仅同步强制监听 |
| `SELF_BEFORE_CARD_CLOSE` / `self_before_card_close` / :262 | 是（源码入口） | `scripts/system/operations/CloseCard.gd:14` [pending→prefix] | 响应接口支持；现正式监听0；仅同步强制监听 |
| `OTHERS_BEFORE_CARD_CLOSE` / `others_before_card_close` / :263 | 是（源码入口） | `scripts/system/operations/CloseCard.gd:14` [pending→prefix] | 响应接口支持；现正式监听0；仅同步强制监听 |
| `BEFORE_CARD_REMOVE` / `before_card_remove` / :265 | 是（源码入口） | `scripts/system/card_zones.gd:85–90 ← BEFORE_ENTER_POINTS:26` [pending] | 响应接口支持；现正式监听0；仅同步强制监听 |
| `SELF_BEFORE_CARD_REMOVE` / `self_before_card_remove` / :266 | 是（源码入口） | `scripts/system/card_zones.gd:85–90 ← BEFORE_ENTER_POINTS:26` [pending→prefix] | 响应接口支持；现正式监听0；仅同步强制监听 |
| `OTHERS_BEFORE_CARD_REMOVE` / `others_before_card_remove` / :267 | 是（源码入口） | `scripts/system/card_zones.gd:85–90 ← BEFORE_ENTER_POINTS:26` [pending→prefix] | 响应接口支持；现正式监听0；仅同步强制监听 |
| `BEFORE_SCORE_ADD` / `before_score_add` / :269 | 是（源码入口） | `scripts/system/operations/EditScore.gd:13` [pending] | 响应接口支持；现正式监听0；仅同步强制监听 |
| `SELF_BEFORE_SCORE_ADD` / `self_before_score_add` / :270 | 是（源码入口） | `scripts/system/operations/EditScore.gd:13` [pending→prefix] | 响应接口支持；现正式监听0；仅同步强制监听 |
| `OTHERS_BEFORE_SCORE_ADD` / `others_before_score_add` / :271 | 是（源码入口） | `scripts/system/operations/EditScore.gd:13` [pending→prefix] | 响应接口支持；现正式监听0；仅同步强制监听 |
| `BEFORE_MAGIC_ADD` / `before_magic_add` / :273 | 是（源码入口） | `scripts/system/operations/EditMagic.gd:18` [pending] | 响应接口支持；现正式监听0；仅同步强制监听 |
| `SELF_BEFORE_MAGIC_ADD` / `self_before_magic_add` / :274 | 是（源码入口） | `scripts/system/operations/EditMagic.gd:18` [pending→prefix] | 响应接口支持；现正式监听0；仅同步强制监听 |
| `OTHERS_BEFORE_MAGIC_ADD` / `others_before_magic_add` / :275 | 是（源码入口） | `scripts/system/operations/EditMagic.gd:18` [pending→prefix] | 响应接口支持；现正式监听0；仅同步强制监听 |
| `BEFORE_COMMAND_SPELL_SPEND` / `before_command_spell_spend` / :278 | 是（源码入口） | `scripts/system/global/effect_manager.gd:1589` [pending] | 响应接口支持；现正式监听0；仅同步强制监听 |
| `SELF_BEFORE_COMMAND_SPELL_SPEND` / `self_before_command_spell_spend` / :279 | 是（源码入口） | `scripts/system/global/effect_manager.gd:1589` [pending→prefix] | 响应接口支持；现正式监听0；仅同步强制监听 |
| `OTHERS_BEFORE_COMMAND_SPELL_SPEND` / `others_before_command_spell_spend` / :280 | 是（源码入口） | `scripts/system/global/effect_manager.gd:1589` [pending→prefix] | 响应接口支持；现正式监听0；仅同步强制监听 |
| `SURVIVE_ELIMINATION` / `survive_elimination` / :282 | 是（源码入口） | `scripts/system/global/climax_resolver.gd:45` [dynamic]；`scripts/system/operations/EditLives.gd:23` [dynamic] | 响应接口支持；现正式监听0 |
| `SELF_SURVIVE_ELIMINATION` / `self_survive_elimination` / :283 | 是（源码入口） | `scripts/system/global/climax_resolver.gd:45` [dynamic→prefix]；`scripts/system/operations/EditLives.gd:23` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `OTHERS_SURVIVE_ELIMINATION` / `others_survive_elimination` / :284 | 是（源码入口） | `scripts/system/global/climax_resolver.gd:45` [dynamic→prefix]；`scripts/system/operations/EditLives.gd:23` [dynamic→prefix] | 响应接口支持；现正式监听0 |
| `SITUATION_ACTIVATED` / `situation_activated` / :286 | 是（源码入口） | `scripts/system/global/situation_resolver.gd:51` [global] | 是：JSON+operation 监听 1 条 |
| `BEFORE_SITUATION_ACTIVATE` / `before_situation_activate` / :288 | 是（源码入口） | `scripts/system/global/situation_resolver.gd:17` [pending] | 响应接口支持；现正式监听0；仅同步强制监听 |

### 1.1 已声明但无生产派发：完整清单

- `SELF_PREPARE_PHASE_START` = `self_prepare_phase_start`（time_points.gd:21）
- `SELF_PREPARE_PHASE_END` = `self_prepare_phase_end`（time_points.gd:23）
- `OTHERS_PREPARE_PHASE_START` = `others_prepare_phase_start`（time_points.gd:24）
- `OTHERS_PREPARE_PHASE_END` = `others_prepare_phase_end`（time_points.gd:26）
- `SELF_OUTPOST_PHASE_START` = `self_outpost_phase_start`（time_points.gd:31）
- `SELF_OUTPOST_PHASE_END` = `self_outpost_phase_end`（time_points.gd:33）
- `OTHERS_OUTPOST_PHASE_START` = `others_outpost_phase_start`（time_points.gd:34）
- `OTHERS_OUTPOST_PHASE_END` = `others_outpost_phase_end`（time_points.gd:36）
- `SELF_ACTION_PHASE_START` = `self_action_phase_start`（time_points.gd:41）
- `SELF_ACTION_PHASE_END` = `self_action_phase_end`（time_points.gd:43）
- `OTHERS_ACTION_PHASE_START` = `others_action_phase_start`（time_points.gd:44）
- `OTHERS_ACTION_PHASE_END` = `others_action_phase_end`（time_points.gd:46）
- `SELF_BATTLE_PHASE_START` = `self_battle_phase_start`（time_points.gd:51）
- `SELF_BATTLE_PHASE_END` = `self_battle_phase_end`（time_points.gd:53）
- `OTHERS_BATTLE_PHASE_START` = `others_battle_phase_start`（time_points.gd:54）
- `OTHERS_BATTLE_PHASE_END` = `others_battle_phase_end`（time_points.gd:56）
- `SELF_PHASE_START` = `self_phase_start`（time_points.gd:61）
- `SELF_PHASE` = `self_phase`（time_points.gd:62）
- `SELF_PHASE_END` = `self_phase_end`（time_points.gd:63）
- `OTHERS_PHASE_START` = `others_phase_start`（time_points.gd:64）
- `OTHERS_PHASE` = `others_phase`（time_points.gd:65）
- `OTHERS_PHASE_END` = `others_phase_end`（time_points.gd:66）
- `SELF_CLIMAX_START` = `self_climax_start`（time_points.gd:131）
- `SELF_CLIMAX_END` = `self_climax_end`（time_points.gd:133）
- `OTHERS_CLIMAX_START` = `others_climax_start`（time_points.gd:134）
- `OTHERS_CLIMAX_END` = `others_climax_end`（time_points.gd:136）
- `DEPLOY_START` = `deploy_start`（time_points.gd:143）
- `DEPLOY` = `deploy`（time_points.gd:144）
- `DEPLOY_END` = `deploy_end`（time_points.gd:145）
- `SELF_DEPLOY_START` = `self_deploy_start`（time_points.gd:146）
- `SELF_DEPLOY` = `self_deploy`（time_points.gd:147）
- `SELF_DEPLOY_END` = `self_deploy_end`（time_points.gd:148）
- `OTHERS_DEPLOY_START` = `others_deploy_start`（time_points.gd:149）
- `OTHERS_DEPLOY` = `others_deploy`（time_points.gd:150）
- `OTHERS_DEPLOY_END` = `others_deploy_end`（time_points.gd:151）
- `MOVE_START` = `move_start`（time_points.gd:153）
- `MOVE` = `move`（time_points.gd:154）
- `MOVE_END` = `move_end`（time_points.gd:155）
- `SELF_MOVE_START` = `self_move_start`（time_points.gd:156）
- `SELF_MOVE` = `self_move`（time_points.gd:157）
- `SELF_MOVE_END` = `self_move_end`（time_points.gd:158）
- `OTHERS_MOVE_START` = `others_move_start`（time_points.gd:159）
- `OTHERS_MOVE` = `others_move`（time_points.gd:160）
- `OTHERS_MOVE_END` = `others_move_end`（time_points.gd:161）
- `BUFF` = `buff`（time_points.gd:171）
- `SELF_BUFF` = `self_buff`（time_points.gd:174）
- `OTHERS_BUFF` = `others_buff`（time_points.gd:177）
- `LOCATION_BENEFIT_CHANGED` = `location_benefit_changed`（time_points.gd:196）
- `SELF_LOCATION_BENEFIT_CHANGED` = `self_location_benefit_changed`（time_points.gd:197）
- `OTHERS_LOCATION_BENEFIT_CHANGED` = `others_location_benefit_changed`（time_points.gd:198）

原因：四种阶段 start/end 用 global_time_point，所以不会产生 self_/others_；玩家阶段只派 mid，不派通用 PHASE 的玩家变体；高潮 start/end 也只全局派；Deploy/Move 只产生位置事件和日志，未产生 DECLARE 的 DEPLOY/MOVE 三元生命周期；BUFF 只有 start/end，没有持续 BUFF；EditLocationBenefit/RestoreLocationBenefits 未派 LOCATION_BENEFIT_CHANGED。`GameLog.record("deploy"/"move", ...)` 不是动态时点。

### 1.2 当前数据已实际引用的空心声明
| 效果 / 精确 JSON 路径 | 空心时点 | operation 体（不是内联替身） | 影响 |
|---|---|---|---|
| `base_construction_deploy_workshop_gain`<br>`data/servants/00005_medea/00005_medea.json#/specials/SKILLS/0/effects/1` | `self_deploy` | `get_location_map_area, get_property, if_func, edit_magic, edit_score` | 普通生产路径没有该监听入口 |
| `placeholder_absolute_order_penalty`<br>`data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json#/effects/2` | `self_battle_phase_end` | `log_exists, get_current_round, if_func, and_func, edit_magic` | 普通生产路径没有该监听入口 |
| `outsider_battle_phase_score_gain`<br>`data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json#/effects/3` | `self_battle_phase_end` | `sum_log_data, if_func, get_location_map_area, get_property, get_players_in_map_area, array_length, and_func, if_else_func, edit_score` | 普通生产路径没有该监听入口 |
| 美杜莎 `petrification_defeat_if_no_magic_attack`<br>`data/servants/00004_medusa/00004_medusa.json#/specials/SKILLS/2/effects/0/funcs/0` | 延迟目标 `self_battle_phase_start` | `schedule_effect_on_time_point` + `defeat` 及查询/foreach | 初始 self_action_phase 已派；延迟时点未派，day_end 过期只会注销 |

### 1.3 CARD_REVEALED 的真实上游来源
统一三元组真正写入入口是 `time_point_checker.gd:53–57`；源调用逐项：
- `scripts/system/regular_play.gd:368`：`TimePointChecker.card_revealed(card)`
- `scripts/system/global/event_resolver.gd:80`：`TimePointChecker.card_revealed(event)`
- `scripts/system/global/situation_resolver.gd:45`：`TimePointChecker.card_revealed(situation)`
- `scripts/system/operations/AddAttack.gd:28`：`TimePointChecker.card_revealed(attack)`
- `scripts/system/operations/AddSkill.gd:30`：`TimePointChecker.card_revealed(skill)`
- `scripts/system/operations/PlayAttack.gd:90`：`TimePointChecker.card_revealed(attack)`
- `scripts/system/operations/PlaySkill.gd:61`：`TimePointChecker.card_revealed(skill)`
- `scripts/system/operations/SetCardConcealed.gd:34`：`TimePointChecker.card_revealed(card)`
暗置放置不派；事件翻面先登记再派；SetCardConcealed 中非 BaseHandCard 分支提前返回，事件的亮出必须由 EventResolver.register_entered 补上。

## 2. A 类：经过 operation 的时点逻辑
`A` 只代表动作/查询确实进入 operation，不保证触发时机已经数据声明；直接 `SomeOperation.new().exec(...)` 也是 A，不能误算 B。注册表不是实际加载门：LoadHelper 以 func_name 转类名，加载 exec，详见 `load_helper.gd:90–97,130–183,242–255`；执行由 `effect_manager.gd:2345–2422,2431–2458,2470–2559` 统一调用。

| operation 名 | 代码位置 | 时点与逻辑 |
|---|---|---|
| `when` | `scripts/system/operations/When.gd:6–14` | 读取触发快照中的参数时点，返回分支条件；时点由 JSON 传入 |
| `schedule_effect_on_time_point` | `scripts/system/operations/ScheduleEffectOnTimePoint.gd:6–27` | 目标时点和到期点由参数传入；克隆 funcs 后登记一次性效果 |
| `emit_time_point` | `scripts/system/operations/EmitTimePoint.gd:6–10` | 通用派发参数时点；现正式数据没有调用 |
| `activate_effect` | `scripts/system/operations/ActivateEffect.gd:28–29` | 显式发动及触发上下文，不是补齐某个缺失派发 |
| `get_player_time_points` | `scripts/system/operations/GetPlayerTimePoints.gd:6–8` | 读取当前窗口 |
| `close_time_point` | `scripts/system/operations/CloseTimePoint.gd` | 关闭参数时点（无硬编码常量） |
| `cancel_pending_action / edit_pending_action / get_pending_action_value` | `scripts/system/operations/CancelPendingAction.gd / EditPendingAction.gd / GetPendingActionValue.gd` | 操作当前待定动作，动作类型来自发起方时点 |
| `edit_magic` | `scripts/system/operations/EditMagic.gd:18–22,43–45` | before_magic_add + magic_add/decrease |
| `edit_score` | `scripts/system/operations/EditScore.gd:13–18,30–32` | before_score_add + score_add/decrease |
| `edit_lives` | `scripts/system/operations/EditLives.gd:15–28` | lives_add/decrease、last_life、before_eliminate/survive_elimination/eliminated |
| `defeat / remove_defeat` | `scripts/system/operations/Defeat.gd:7–13 / RemoveDefeat.gd:6–8` | before_defeat → 败北状态 → battle_lose；删除败北复用 ManageBuff |
| `manage_buff` | `scripts/system/operations/ManageBuff.gd:12–27` | buff_start/end（并非持续 buff） |
| `close_card` | `scripts/system/operations/CloseCard.gd:14–31` | before_card_close → 关闭/归区 → card_closed |
| `awaken_skill` | `scripts/system/operations/AwakenSkill.gd:19` | skill_awakened 动态三元组；有代码入口不表示正常玩法自动开放升华 |
| `release_true_name / hide_true_name / apply_card_keywords` | `scripts/system/operations/ReleaseTrueName.gd:39–66 / HideTrueName.gd:36–38 / ApplyCardKeywords.gd:30–38` | 真名事件与日志查询；词条路由转到 release_true_name |
| `play_attack / play_skill` | `scripts/system/operations/PlayAttack.gd:55,90–91 / PlaySkill.gd:33,61–62` | 费用、亮出、出牌时点；与非 operation RegularPlay 批流程区分 |
| `add_attack / add_skill / played_cards` | `scripts/system/operations/AddAttack.gd:28–29 / AddSkill.gd:30–31 / PlayedCards.gd:7` | 追加入场/显式派出牌事件 |
| `draw_card_by_card / draw_card_by_index` | `scripts/system/operations/DrawCardByCard.gd:19–29 / DrawCardByIndex.gd:22–31` | 通过 CardZones before/leave/enter 派牌区变化 |
| `draw_card_from_pl_deck_to_hand / reshuffle_discard` | `scripts/system/operations/DrawCardFromPlDeckToHand.gd:26 / ReshuffleDiscard.gd:27` | card_drawn / deck_reshuffled；抽牌还经搬运入口派牌区事件 |
| `set_location / remove_from_board` | `scripts/system/operations/SetLocation.gd:60–61 / RemoveFromBoard.gd:22` | leave_location / enter_location；不是 DEPLOY/MOVE 三元生命周期 |
| `flip_card_face` | `scripts/system/operations/FlipCardFace.gd:41–43` | card_face_flipped；无归属仅全局，有归属才带前缀 |
| `set_card_concealed` | `scripts/system/operations/SetCardConcealed.gd:9–34` | 明暗和威力同步；手牌亮出事件受分支返回条件影响 |
| `restrict_abilities` | `scripts/system/operations/RestrictAbilities.gd:5–7 → ability_restrictions.gd:7–11,23–35` | JSON 指定禁令玩家/阶段/期限；通过阶段时点判定禁用，DAY_END 固定清理却是 B01 |
| `board_has_effect` | `scripts/system/global/effect_manager.gd:1283–1300` | 阶段能力读取 effect._time_points；宝具禁令查 ForbidNoblePhantasmEffect.EFFECT_NAME 并经 BoardHasEffect.exec，不是内联赋予某卡收益 |
| `回合收尾已用原语` | `scripts/system/global/game_progress.gd:344–360,362` | remove_from_board、discard_played_cards、sync_power、restore_location_benefits、change_pl_order；B 仅记剩余字段操作/调度 |

## 3. B 类：非 operation 的时点处理块
这里同时给出狭义消费者与扩展生命周期动作。每行只计一个独立处理职责；行内标出的 A 委托不计为“没有 operation”。固定 `DAY_END` 监听副作用与 `end_round` 后半生命周期逻辑不同：前者由派发直接触发，后者由流程函数无条件推进，不能靠发一个 DAY_END 自动完成。

### 3.1 应可改为 operation / 数据声明的动作或策略（14 条）
| 编号 | 文件:行 | 时点/邻接时机 | 具体在做什么 | 处置边界 |
|---|---|---|---|---|
| B01 | `scripts/system/global/time_point_checker.gd:27–28` | DAY_END | 直接在全局派发器内清除本回合能力禁令；调用 AbilityRestrictions.round_ended:19–21，而非监听 DAY_END 的数据效果。 | 抽为单一禁令到期原语；期限仍由 expire_round 数据控制。 |
| B02 | `scripts/system/global/game_progress.gd:254–262` | ROUND_START_RESET | 派发重置时点之前写死将每人的 temp_locations 设为空数组。 | 已有 set_player_data；将重置动作与派发次序分别声明。 |
| B03 | `scripts/system/global/game_progress.gd:416–425` | ACTION_PHASE_START（对应阶段名 action） | 行动阶段开始前固定调用 EventResolver.reveal_planned；具体翻哪些区域读计划，但选择在行动阶段执行是代码调度。 | 翻牌动作已用 set_card_concealed；仍缺计划级动作/时机的数据声明，不要误称翻牌动作全内联。 |
| B04 | `scripts/system/global/game_progress.gd:338–344` | DAY_END 之后 | 记录 last_turn_location、清 is_battle；随后 remove_from_board 已是 operation（A）。 | 前两个字段动作可组合 get_player_data_value/set_player_data；不重复实现 remove_from_board。 |
| B05 | `scripts/system/global/game_progress.gd:347–351` | DAY_END 之后 | sync_power 已是 operation（A），但 total_power_bonus 归零直接调用 BaseNumber.set_num。 | edit_data_number/edit_num_and_return 可承担归零。 |
| B06 | `scripts/system/global/game_progress.gd:352–356` | DAY_END 之后 | 固定安排所有败北层到期、局势/事件离场；DefeatBuff.clear_all 的逐层删除最终经 manage_buff（A），非 operation 的是固定清理对象/时机调度。 | get_all_players_id + foreach_func/remove_defeat 可表达败北清理；局势/事件真正内联移区见 B07/B08。 |
| B07 | `scripts/system/global/situation_resolver.gd:55–68` | DAY_END → clear_all | unregister_object_effects、restore_map_area_move_flags、restore_location_pl_num_limits 是 A；内联的是局势入弃置区、active_situation=null。 | 可组合容器/属性操作，或独立局势离场原语；不能把已有还原原语列为缺失。 |
| B08 | `scripts/system/global/event_resolver.gd:85–97` | DAY_END → clear_all | 注销已走 A；事件从区域数组摘下、直接明置、追加 event_discard 为内联。 | 容器操作与 set_card_concealed 可组合；保留注销先于移区契约。 |
| B09 | `scripts/system/global/effect_manager.gd:1576–1600` | BEFORE_COMMAND_SPELL_SPEND / COMMAND_SPELL_USED | 读取可取消/改写的消耗量后，直接 spells.minus；日志和派发固定在费用引擎内；JSON cost 控数量但没有消耗 operation。 | 可抽单一资源消耗原语；取消、重新验证余额、事实和派发顺序不可散落。 |
| B10 | `scripts/system/global/climax_resolver.gd:36–59` | BEFORE_ELIMINATE / SURVIVE_ELIMINATION / ELIMINATED | 检查取消后直接写 is_out、记淘汰事实和公告；离场已用 remove_from_board（A）。 | 抽通用淘汰动作；edit_lives 的生命变化不等价于按战果淘汰，不能强行替代。 |
| B11 | `scripts/system/global/battle_resolver.gd:52–57` | BATTLE | 交战事件前直接置 player_data.is_battle=true。 | set_player_data 可表达，派发继续由战斗流程保持顺序。 |
| B12 | `scripts/system/global/battle_resolver.gd:71–78` | BATTLE_RESOLVE 之后 / BATTLE_END 之前 | 各战区本次胜负改写记录 _battle_override 固定清空。 | 可由 set_property 清理；一场结算一次的生命周期必须保留。 |
| B13 | `scripts/system/regular_play.gd:335–355` | CARD_COST_CALCULATED 后 / PLAYED_CARD 前 | 常规组出牌直接扣魔力、改明暗/激活、摘来源入场、累加威力；这段不走 play_attack/play_skill 的 operation 动作。 | 将入场和支付拆成可组合原语；必须保持整批入场后再逐牌派发，不能用单张 operation 循环破坏批语义。 |
| B14 | `scripts/system/global/situation_resolver.gd:11–22` | BEFORE_SITUATION_ACTIVATE | 被取消时直接追加 situation_discard/置空；未取消时直接写 active_situation。印刷魔力的赋予另经 edit_magic（A）。 | 独立局势入场/离场或显式容器属性动作；取消判断依旧是引擎契约。 |

### 3.2 必须内联：派发器、匹配器与效果执行运行时本身（15 条）
| 编号 | 文件:行 | 时点/邻接时机 | 具体在做什么 | 处置边界 |
|---|---|---|---|---|
| B15 | `scripts/system/global/time_point_checker.gd:14–21;139–143` | 阶段窗口 | 维护 phase_time_points、清旧动态表、刷新 current_time_points；set_phase_time_points 只更新，不自行运行效果。 | 时点状态维护者本身，不是效果体。 |
| B16 | `scripts/system/global/time_point_checker.gd:26–44;110–131` | 全局/动态玩家事件 | 写时点表、生成 self_/others_ 前缀、记录事实、调用 run_time_point；source 事件结束后清理。 | 真实派发基础设施，不能由触发它自己的数据效果代替。 |
| B17 | `scripts/system/global/time_point_checker.gd:50–57` | CARD_REVEALED 三元组 | 亮出时统一派三个卡牌语义时点；来源筛选在 B21。 | 自身/其他是卡牌身份而非玩家身份。 |
| B18 | `scripts/system/global/time_point_checker.gd:65–104` | self_/others_ 阶段窗口、CLIMAX/NON_CLIMAX | 清玩家级旧窗口、消费瞬时事件；特别识别高潮/非高潮持续窗口。 | 事件消费与窗口语义，非威力/奖励规则。 |
| B19 | `scripts/system/global/effect_manager.gd:1045–1091` | before_* / EFFECT_START | pending 栈同步匹配、生成 self_/others_、只执行强制非手动监听，再进入 activate_effect。 | 取消/改写效果体仍经 cancel_pending_action/edit_pending_action（A）。 |
| B20 | `scripts/system/global/effect_manager.gd:1129–1188;1192–1217;1237–1277` | 一般事件及 expire_time_points | 排队快照、到期注销、瞬态消费、持续窗口去重；全部使用效果数据的时点与期限。 | 通用执行管线；不是硬编码某张卡。 |
| B21 | `scripts/system/global/effect_manager.gd:1220–1229` | SELF_CARD_REVEALED / OTHERS_CARD_REVEALED | 同一 source 时排除 others；不同 source 时排除 self。 | 卡牌来源语义筛选。 |
| B22 | `scripts/system/global/effect_manager.gd:1345–1382` | 手动阶段窗口、CLIMAX/NON_CLIMAX | 查询时重建行动者的阶段/高潮窗口并匹配 OR/AND、关闭时点；不重派自动效果。 | 窗口查询不是新事件派发，不计入未派发时点的补齐。 |
| B23 | `scripts/system/global/effect_manager.gd:2477–2489;2590–2596;2611–2618` | EFFECT_START / EFFECT_END | 开始前派 pending 动作并服从取消；遇嵌套 EFFECT_START 不再派以防递归；完成后派 EFFECT_END。 | 效果生命周期引擎；不计为卡面效果写死。 |
| B24 | `scripts/system/global/game_progress.gd:56–81;117–123;409–425;535;574–579;635–639` | 阶段开始/结束/中、CLIMAX/NON_CLIMAX、通用派发 | phases 表选实际阶段 start/end，玩家阶段仅派有效 mids；高潮选择器与玩家窗口成对派；process_time_point 是可变字符串入口。 | 基础时序和阶段映射；没有据此声称所有 prefixed start/end 均已派。 |
| B25 | `scripts/system/card_zones.gd:10–26;83–106` | CARD_TO_* / CARD_LEAVE_DECK / BEFORE_CARD_REMOVE | 区路径映射为时点，搬运前问取消、搬运后派发；由 draw_card_by_card/index 等 A 调用。 | 牌区到事件词汇的桥接，不是牌面奖励逻辑。 |
| B26 | `scripts/system/regular_play.gd:324–341;361–377` | CARD_COST_CALCULATED / CARD_REVEALED / PLAYED_CARD | 入场、词条、亮出、整批完成后出牌事件的序列和续行游标。具体内联状态改写另见 B13。 | 批原子性和派发顺序。 |
| B27 | `scripts/system/global/event_resolver.gd:75–80` | CARD_REVEALED | 先以存活玩家为锚点登记事件效果，再派亮出事件。 | 注册和来源/锚点接线；卡面效果仍走 A。 |
| B28 | `scripts/system/global/situation_resolver.gd:39–51;86–95` | CARD_REVEALED / SITUATION_ACTIVATED | 以锚点登记局势效果；亮出后再派生效事件，续行时不重播。 | 注册与派发本身。 |
| B29 | `scripts/system/global/battle_resolver.gd:57–78;210–245` | BATTLE / BATTLE_RESOLVE / BATTLE_END / BATTLE_WIN / BATTLE_LOSE | 战斗前、结算前、结算后和胜负事件由战斗流程产生；战果实际编辑经 edit_score（A）。 | 战斗事实产生与时序；不是用常量比较后给某张卡写死收益。 |

### 3.3 B 类文件分布（宽口径；狭义 5 条另列）
| 文件 | B 总数 | 可改 | 必须内联 |
|---|---:|---:|---:|
| `scripts/system/global/time_point_checker.gd` | 5 | 1 | 4 |
| `scripts/system/global/game_progress.gd` | 6 | 5 | 1 |
| `scripts/system/global/situation_resolver.gd` | 3 | 2 | 1 |
| `scripts/system/global/event_resolver.gd` | 2 | 1 | 1 |
| `scripts/system/global/effect_manager.gd` | 6 | 1 | 5 |
| `scripts/system/global/climax_resolver.gd` | 1 | 1 | 0 |
| `scripts/system/global/battle_resolver.gd` | 3 | 2 | 1 |
| `scripts/system/regular_play.gd` | 2 | 1 | 1 |
| `scripts/system/card_zones.gd` | 1 | 0 | 1 |
| 合计 | 29 | 14 | 15 |
狭义5块：time_point_checker.gd 2（B01/B18），effect_manager.gd 3（B21/B22/B23）；只有 B01 建议业务原语化。B02–B14 中调用既有 operation 的部分已明确写 A，不把“调度在代码”偷换成“动作无 operation”。

## 4. 逐条数据时点效果：A 清单与缺口
完整列出 105 条：`manual` 的时点是可发动窗口，不是自动触发。操作列为递归去重 func_name（排除 power_query，嵌套新效果另有独立行）。`A/静态` 仅证实声明+operation 接线，不替代逐卡规则/运行验收。

| 精确 JSON 路径 / effect_name | time_points | 类型 / 静态结论 | operation 名 |
|---|---|---|---|
| `data/command_spells/normal_command_spell.json#/effects/0`<br>`command_spell_use` | `self_action_phase` | manual；A/静态 | `edit_magic, edit_data_number, schedule_effect_on_time_point, edit_score, get_activating_eff, get_property, set_location` |
| `data/situations/origin/battle_of_shinto/battle_of_shinto.json#/effects/0`<br>`battle_of_shinto_add_event` | `self_card_revealed` | 自动；A/静态 | `get_map_area_by_name, add_event_from_deck` |
| `data/situations/origin/gate_of_hell/gate_of_hell.json#/effects/0`<br>`gate_of_hell_limit_areas` | `self_card_revealed` | 自动；A/静态 | `array_length, get_active_players_id, compare_number, get_map_area_by_name, set_map_area_can_move_to, set_property, foreach_func, set_location_pl_num_limit, get_property` |
| `data/situations/origin/gate_of_hell/gate_of_hell.json#/effects/1`<br>`gate_of_hell_add_event` | `self_card_revealed` | 自动；A/静态 | `get_map_area_by_name, add_event_from_deck` |
| `data/situations/origin/heavens_feel/heavens_feel.json#/effects/0`<br>`heavens_feel_limit_areas` | `self_card_revealed` | 自动；A/静态 | `array_length, get_active_players_id, compare_number, get_map_area_by_name, set_map_area_can_move_to, set_property, foreach_func, set_location_pl_num_limit, get_property` |
| `data/situations/origin/heavens_feel/heavens_feel.json#/effects/1`<br>`heavens_feel_add_events` | `self_card_revealed` | 自动；A/静态 | `get_map_area_by_name, add_event_from_deck` |
| `data/situations/origin/killer_in_miyama/killer_in_miyama.json#/effects/0`<br>`killer_in_miyama_add_event` | `self_card_revealed` | 自动；A/静态 | `get_map_area_by_name, add_event_from_deck` |
| `data/situations/origin/night_of_fate/night_of_fate.json#/effects/0`<br>`night_of_fate_add_events` | `self_card_revealed` | 自动；A/静态 | `array_length, get_active_players_id, compare_number, get_map_area_by_name, add_event_from_deck` |
| `data/situations/origin/turnaround/turnaround.json#/effects/0`<br>`turnaround_add_events` | `self_card_revealed` | 自动；A/静态 | `get_map_area_by_name, add_event_from_deck` |
| `data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json#/specials/SKILLS/0/effects/0`<br>`np_bloom_score` | `self_battle_phase` | manual；A/静态 | `get_player_deck, get_player_hand_cards, get_player_played_cards, get_player_discard, get_player_servant_skills, get_player_master_skills, merge_arrays, get_cards_by_attributes_fr_arr, get_extreme_by_property, is_in_array, edit_score, get_property, compare_number, match_func` |
| `data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json#/specials/SKILLS/0/effects/1`<br>`zero_opponent_magic_power` | `self_battle_phase` | manual；A/静态 | `get_players_in_same_area, foreach_func, zero_attribute_power` |
| `data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json#/specials/SKILLS/1/effects/0`<br>`wind_barrier_cost` | `self_card_cost_calculated, self_true_name_release, self_true_name_hidden` | 自动；A/静态 | `is_true_name_released, if_else_func, edit_card_cost` |
| `data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json#/specials/SKILLS/1/effects/1`<br>`zero_opponent_strength_power` | `self_battle_phase` | manual；A/静态 | `get_players_in_same_area, foreach_func, zero_attribute_power` |
| `data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json#/specials/SKILLS/2/effects/0`<br>`combat` | `self_battle_phase, self_climax` | manual；A/静态 | `edit_power` |
| `data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json#/specials/SKILLS/2/effects/1`<br>`round11_win_victory` | `self_battle_win` | 自动；A/静态 | `get_current_round, if_func, set_player_data` |
| `data/servants/00002_emiya/00002_emiya.json#/specials/SKILLS/0/effects/0`<br>`zero_opponent_agility_power` | `self_battle_phase` | manual；A/静态 | `get_players_in_same_area, foreach_func, zero_attribute_power` |
| `data/servants/00002_emiya/00002_emiya.json#/specials/SKILLS/1/effects/0`<br>`terrain_advantage_triple` | `self_action_phase` | 自动；A/静态 | `log_exists, get_location, get_location_benefit, calculate_number, edit_location_benefit` |
| `data/servants/00002_emiya/00002_emiya.json#/specials/SKILLS/1/effects/1`<br>`battle_win_score_gain` | `self_battle_phase` | manual；A/静态 | `schedule_effect_on_time_point, edit_score` |
| `data/servants/00002_emiya/00002_emiya.json#/specials/SKILLS/2/effects/0`<br>`rebuild_hand_from_all_zones` | `self_played_card` | 自动；A/静态 | `get_player_hand_cards, get_activating_eff, get_property, array_difference, foreach_func, find_player_array_containing, draw_card_by_card, is_in_array, set_property` |
| `data/servants/00002_emiya/00002_emiya.json#/specials/SKILLS/2/effects/1`<br>`residue_limited_play_no_draw` | `self_played_card, self_prepare_phase` | 自动；A/静态 | `when, edit_data_number, set_player_data, get_player_hand_cards, array_length, if_func, get_eff_source_card, close_card` |
| `data/servants/00003_cu_chulainn/00003_cu_chulainn.json#/specials/SKILLS/0/effects/0`<br>`move_anywhere_except_workshop` | `self_action_phase` | manual；A/静态 | `get_activating_eff, get_property, set_location` |
| `data/servants/00003_cu_chulainn/00003_cu_chulainn.json#/specials/SKILLS/1/effects/0`<br>`battle_end_score_per_opponent` | `self_battle_phase` | manual；A/静态 | `schedule_effect_on_time_point, get_location_map_area, get_area_round_participants, get_activating_eff, get_property, remove_from_array, array_length, calculate_number, edit_score, get_area_round_winners, is_in_array, foreach_func` |
| `data/servants/00003_cu_chulainn/00003_cu_chulainn.json#/specials/SKILLS/2/effects/0`<br>`placeholder_permanent_cost_increase_on_play` | `self_played_card` | 自动；A/静态 | `get_eff_source_card, edit_card_cost` |
| `data/servants/00003_cu_chulainn/00003_cu_chulainn.json#/specials/SKILLS/2/effects/1`<br>`placeholder_pierce_heart_single_opponent_defeat` | `self_battle_phase` | manual；A/静态 | `get_players_in_same_area, array_length, compare_number, if_func, foreach_func, defeat` |
| `data/servants/00004_medusa/00004_medusa.json#/specials/SKILLS/0/effects/0`<br>`riding_draw_with_basic_attack` | `self_played_card` | 自动；A/静态 | `log_field_values, filter_by_property, array_length, compare_number, if_func, reshuffle_discard, draw_card_from_pl_deck_to_hand` |
| `data/servants/00004_medusa/00004_medusa.json#/specials/SKILLS/0/effects/1`<br>`riding_mount_summon_play_low_power_cards` | `self_action_phase` | manual；A/静态 | `get_activating_eff, get_property, foreach_func, play_attack` |
| `data/servants/00004_medusa/00004_medusa.json#/specials/SKILLS/1/effects/0`<br>`bellerophon_redeploy_terrain` | `self_action_phase` | manual；A/静态 | `is_true_name_released, get_activating_eff, get_property, set_location, get_location_map_area, get_map_area_score_need_win, merge_arrays, foreach_func, store_value, compare_number, if_func, array_length, and_func, add_to_array, get_move_target_location, get_pls_in_location, not_func, get_location, remove_from_array, deploy, is_in_array, schedule_effect_on_time_point, get_map_data_value` |
| `data/servants/00004_medusa/00004_medusa.json#/specials/SKILLS/2/effects/0`<br>`petrification_defeat_if_no_magic_attack` | `self_action_phase` | 自动；A 初始入口存在；延迟目标空心 | `schedule_effect_on_time_point, get_players_in_same_area, foreach_func, get_player_played_cards, get_cards_by_attributes_fr_arr, array_length, compare_number, if_func, defeat` |
| `data/servants/00005_medea/00005_medea.json#/specials/SKILLS/0/effects/0`<br>`base_construction_dynamic_cost` | `self_card_cost_calculated` | 自动；A/静态 | `get_current_round, calculate_number, get_eff_source_card, edit_card_cost` |
| `data/servants/00005_medea/00005_medea.json#/specials/SKILLS/0/effects/1`<br>`base_construction_deploy_workshop_gain` | `self_deploy` | 自动；A 体存在；空心派发 | `get_location_map_area, get_property, if_func, edit_magic, edit_score` |
| `data/servants/00005_medea/00005_medea.json#/specials/SKILLS/1/effects/0`<br>`rule_breaker_remove_command_spell` | `self_action_phase` | manual；A/静态 | `get_players_in_same_area, release_true_name, get_activating_eff, get_property, get_player_data_value, compare_number, match_func, defeat, edit_data_number` |
| `data/servants/00005_medea/00005_medea.json#/specials/SKILLS/2/effects/0`<br>`divine_words_retrieve_rule_breaker` | `self_battle_phase` | manual；A/静态 | `schedule_effect_on_time_point, get_pl_skills_out_game, get_objects_by_name_fr_arr, get_card_by_index_fr_arr, add_skill_to_skill_zone, remove_from_array` |
| `data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json#/specials/SKILLS/0/effects/1`<br>`ichi_no_tachi_close_and_play_strength` | `self_battle_phase` | manual；A/静态 | `get_eff_source_card, close_card, get_activating_eff, get_property, foreach_func, play_attack, edit_magic` |
| `data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json#/specials/SKILLS/0/effects/2`<br>`ichi_no_tachi_close_engaged_attack` | `self_battle_phase` | manual；A/静态 | `log_exists, get_eff_source_card, get_property, filter_by_property, get_card_by_index_fr_arr, get_players_in_same_area, get_activating_eff, foreach_func, close_card` |
| `data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json#/specials/SKILLS/1/effects/0`<br>`ni_no_tachi_lock_opponent_abilities` | `self_action_phase` | manual；A/静态 | `get_players_in_same_area, is_engaged, restrict_abilities` |
| `data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json#/specials/SKILLS/2/effects/1`<br>`placeholder_swallow_reversal_combo_true_name` | `self_battle_phase` | 自动；A/静态 | `get_player_played_cards, get_objects_by_name_fr_arr, array_length, compare_number, if_func, not_func, and_func, release_true_name, edit_data_number` |
| `data/servants/00007_heracles/00007_heracles.json#/specials/SKILLS/0/effects/0`<br>`twelve_labors_defeat_bonus` | `self_battle_lose` | 自动；A/静态 | `get_eff_source_card, get_player_servant_skills, get_player_played_cards, get_pl_skills_side, merge_arrays, get_objects_by_name_fr_arr, log_field_values, get_card_by_index_fr_arr, calculate_number, edit_score, foreach_func, remove_from_array, card_counts_power, get_property, edit_power, unregister_object_effects, set_property, find_player_array_containing, get_pl_skills_out_game, draw_card_by_card, edit_card_power` |
| `data/servants/00007_heracles/00007_heracles.json#/specials/SKILLS/1/effects/0`<br>`twelve_labors_defeat_bonus` | `self_battle_lose` | 自动；A/静态 | `get_eff_source_card, get_player_servant_skills, get_player_played_cards, get_pl_skills_side, merge_arrays, get_objects_by_name_fr_arr, log_field_values, get_card_by_index_fr_arr, calculate_number, edit_score, foreach_func, remove_from_array, card_counts_power, get_property, edit_power, unregister_object_effects, set_property, find_player_array_containing, get_pl_skills_out_game, draw_card_by_card, edit_card_power` |
| `data/servants/00007_heracles/00007_heracles.json#/specials/SKILLS/2/effects/0`<br>`twelve_labors_defeat_bonus` | `self_battle_lose` | 自动；A/静态 | `get_eff_source_card, get_player_servant_skills, get_player_played_cards, get_pl_skills_side, merge_arrays, get_objects_by_name_fr_arr, log_field_values, get_card_by_index_fr_arr, calculate_number, edit_score, foreach_func, remove_from_array, card_counts_power, get_property, edit_power, unregister_object_effects, set_property, find_player_array_containing, get_pl_skills_out_game, draw_card_by_card, edit_card_power` |
| `data/servants/00008_angra_mainyu/00008_angra_mainyu.json#/specials/SKILLS/0/effects/0`<br>`angra_left_right` | `self_action_phase` | manual；A/静态 | `get_location_map_area, is_null, not_func, get_players_in_same_area, array_length, compare_number, match_func, if_func, and_func, for_func, reshuffle_discard, draw_card_from_pl_deck_to_hand, edit_magic` |
| `data/servants/00008_angra_mainyu/00008_angra_mainyu.json#/specials/SKILLS/1/effects/0`<br>`angra_binding` | `self_action_phase` | manual；A/静态 | `get_player_discard, get_cards_by_name_fr_arr, get_player_hand_cards, log_field_values, array_length, compare_number, match_func, store_value, get_card_by_index_fr_arr, get_pl_id_using_eff, is_in_array, not_func, and_func, foreach_func, draw_card_by_card, remove_from_array, set_card_concealed, set_property, add_attack` |
| `data/servants/00008_angra_mainyu/00008_angra_mainyu.json#/specials/SKILLS/2/effects/0`<br>`angra_verg_avesta` | `self_action_phase` | manual；A/静态 | `schedule_effect_on_time_point, get_player_hand_cards, get_player_played_cards, merge_arrays, array_length, compare_number, match_func, not_func, store_value, ask_player_option, get_activating_eff, get_property, get_player_discard, foreach_func, find_player_array_containing, is_in_array, close_card, draw_card_by_card, set_property, get_cards_by_name_fr_arr, log_field_values, get_card_by_index_fr_arr, get_pl_id_using_eff, and_func, for_func, edit_score` |
| `data/masters/00001_emiya_shirou/00001_emiya_shirou.json#/effects/0`<br>`inexperienced` | `game_start` | 自动；A/静态 | `edit_magic` |
| `data/masters/00001_emiya_shirou/00001_emiya_shirou.json#/effects/1`<br>`projection_magic` | `game_start` | 自动；A/静态 | `add_skill_to_skill_zone` |
| `data/masters/00001_emiya_shirou/00001_emiya_shirou.json#/effects/2`<br>`avalon` | `self_before_eliminate` | 自动；A/静态 | `cancel_pending_action, edit_magic` |
| `data/masters/00001_emiya_shirou/00001_emiya_shirou.json#/upgrade_skill/0/effects/0`<br>`passive` | `self_card_revealed` | 自动；A/静态 | `modify_attack_power_by_attribute` |
| `data/masters/00001_emiya_shirou/00001_emiya_shirou.json#/upgrade_skill/0/effects/1`<br>`combat` | `self_battle_phase, self_climax` | manual；A/静态 | `edit_power` |
| `data/masters/00001_emiya_shirou/00001_emiya_shirou.json#/upgrade_skill/0/effects/2`<br>`upgrade_join_skill_zone` | `self_skill_awakened` | 自动；A/静态 | `get_eff_source_card, add_skill_to_skill_zone` |
| `data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json#/effects/0`<br>`jewel_sorcery_gain` | `game_start` | 自动；A/静态 | `get_player_master, get_property, get_dictionary_value, get_objects_by_name_fr_arr, get_card_by_index_fr_arr, set_property, manage_buff` |
| `data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json#/effects/1`<br>`absolute_order_first_turn` | `game_start, day_end` | 自动；A/静态 | `when, get_player_data_value, add_to_array, get_current_round, if_func, remove_from_array, log_exists, not_func, edit_data_number` |
| `data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json#/effects/2`<br>`placeholder_absolute_order_penalty` | `self_battle_phase_end` | 自动；A 体存在；空心派发 | `log_exists, get_current_round, if_func, and_func, edit_magic` |
| `data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json#/specials/ATTACKS/0/effects/0`<br>`yin_qi_bullet_remove_after_close` | `self_card_closed` | 自动；A/静态 | `get_eff_source_card, find_player_array_containing, get_pl_attacks_out_game, draw_card_by_card, unregister_object_effects` |
| `data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json#/specials/BUFFS/0/effects/0`<br>`jewel_sorcery_action` | `self_action_phase, self_non_climax` | manual；A/静态 | `get_player_master, get_property, get_cards_by_name_fr_arr, get_card_by_index_fr_arr, get_pl_others_out_game, draw_card_by_card, edit_magic, get_pl_attacks_out_game, array_length, compare_number, match_func, get_player_hand_cards, play_attack, get_player_discard, get_activating_eff, foreach_func, for_func, reshuffle_discard, draw_card_from_pl_deck_to_hand` |
| `data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json#/specials/BUFFS/0/effects/1`<br>`jewel_sorcery_climax` | `self_action_phase, self_climax` | manual；A/静态 | `get_player_master, get_property, get_cards_by_name_fr_arr, get_card_by_index_fr_arr, get_pl_others_out_game, draw_card_by_card, edit_magic, get_pl_attacks_out_game, array_length, compare_number, match_func, get_player_hand_cards, play_attack, get_player_discard, get_activating_eff, foreach_func, for_func, reshuffle_discard, draw_card_from_pl_deck_to_hand` |
| `data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json#/upgrade_skill/0/effects/0`<br>`placeholder_jewel_sword_passive_power` | `self_played_card` | 自动；A/静态 | `log_field_values, get_card_by_index_fr_arr, modify_attack_power_by_attribute, get_property, if_func` |
| `data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json#/upgrade_skill/0/effects/1`<br>`placeholder_jewel_sword_drain` | `self_action_phase` | manual；A/静态 | `sum_log_data, edit_magic, schedule_effect_on_time_point, get_eff_source_card, find_player_array_containing, get_pl_skills_out_game, draw_card_by_card, unregister_object_effects` |
| `data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json#/upgrade_skill/0/effects/2`<br>`upgrade_join_skill_zone` | `self_skill_awakened` | 自动；A/静态 | `get_eff_source_card, add_skill_to_skill_zone` |
| `data/masters/00003_matou_shinji/00003_matou_shinji.json#/effects/0`<br>`absorb_magic_command` | `self_enter_location` | 自动；A/静态 | `get_location_map_area, get_property, if_func, edit_magic` |
| `data/masters/00003_matou_shinji/00003_matou_shinji.json#/effects/1`<br>`useless_person` | `game_start` | 自动；A/静态 | `get_player_master, get_property, get_dictionary_value, get_objects_by_name_fr_arr, get_card_by_index_fr_arr, manage_buff` |
| `data/masters/00003_matou_shinji/00003_matou_shinji.json#/effects/2`<br>`clown` | `self_battle_lose` | 自动；A/静态 | `edit_data_number` |
| `data/masters/00003_matou_shinji/00003_matou_shinji.json#/specials/BUFFS/0/effects/0`<br>`false_servant_book_master_replace` | `day_end` | 自动；A/静态 | `get_player_data_value, is_in_array, not_func, get_data_number, if_func, get_players_field, get_objects_by_name_fr_arr, array_length, and_func, get_game_data_value, get_card_by_index_fr_arr, get_player_master, unregister_object_effects, set_player_data, register_object_effects, edit_magic, edit_data_number, get_player_buffs, manage_buff, add_to_array` |
| `data/masters/00003_matou_shinji/00003_matou_shinji.json#/specials/BUFFS/0/effects/1`<br>`false_servant_book_servant_replace` | `day_end` | 自动；A/静态 | `get_player_data_value, is_in_array, not_func, get_data_number, if_func, get_players_field, get_objects_by_name_fr_arr, array_length, compare_number, and_func, get_game_data_value, array_difference, calculate_number, random_int, get_card_by_index_fr_arr, get_player_servant, unregister_object_effects, set_player_data, register_object_effects, deal_player_cards, edit_data_number, add_to_array` |
| `data/masters/00003_matou_shinji/00003_matou_shinji.json#/upgrade_skill/0/effects/0`<br>`placeholder_grail_core_activation` | `day_end` | 自动；A/静态 | `get_eff_source_card, get_property, get_dictionary_value, if_func, not_func, get_current_round, compare_number, match_func, get_player_servant, and_func, get_player_buffs, get_objects_by_name_fr_arr, get_card_by_index_fr_arr, manage_buff, set_dictionary_value` |
| `data/masters/00003_matou_shinji/00003_matou_shinji.json#/upgrade_skill/0/effects/1`<br>`placeholder_grail_core_first_servant_bonus` | `self_battle_phase` | 自动；A/静态 | `get_eff_source_card, get_property, get_dictionary_value, if_func, get_player_servant, and_func, log_field_values, get_card_by_index_fr_arr, get_location_map_area, edit_power` |
| `data/masters/00003_matou_shinji/00003_matou_shinji.json#/upgrade_skill/0/effects/2`<br>`placeholder_grail_core_not_first_servant_bonus` | `day_end` | 自动；A/静态 | `get_eff_source_card, get_property, get_dictionary_value, if_func, get_player_servant, and_func, log_field_values, get_card_by_index_fr_arr, not_func, set_dictionary_value, edit_score` |
| `data/masters/00003_matou_shinji/00003_matou_shinji.json#/upgrade_skill/0/effects/3`<br>`grail_core_score_drain` | `self_score_add` | 自动；A/静态 | `get_eff_source_card, get_property, get_dictionary_value, if_func, get_player_servant, and_func, log_field_values, get_card_by_index_fr_arr, calculate_number, get_map_area_by_name, get_players_in_map_area, get_pl_id_using_eff, remove_from_array, foreach_func, edit_score` |
| `data/masters/00004_matou_sakura/00004_matou_sakura.json#/effects/0`<br>`deficient_vessel_black_mud` | `day_end` | 自动；A/静态 | `get_player_master, get_property, get_dictionary_value, get_objects_by_name_fr_arr, get_card_by_index_fr_arr, manage_buff, get_player_buffs, get_rank_by_data_number, get_players_field, array_length, compare_number, if_func, log_field_values, not_func, and_func, set_property` |
| `data/masters/00004_matou_sakura/00004_matou_sakura.json#/effects/1`<br>`all_evil_grail` | `game_start, day_end` | 自动；A/静态 | `when, get_player_master, get_property, get_dictionary_value, get_objects_by_name_fr_arr, get_card_by_index_fr_arr, manage_buff, get_current_round, if_func, get_rank_by_data_number, compare_number, not_func, and_func, get_player_buffs, set_property, set_player_data, edit_data_number` |
| `data/masters/00004_matou_sakura/00004_matou_sakura.json#/specials/BUFFS/0/effects/0`<br>`black_mud_score_gain` | `self_prepare_phase` | 自动；A/静态 | `get_player_buffs, get_objects_by_name_fr_arr, get_card_by_index_fr_arr, get_property, if_func, edit_score` |
| `data/masters/00004_matou_sakura/00004_matou_sakura.json#/specials/BUFFS/2/effects/0`<br>`placeholder_corrosion_steal_skill` | `others_eliminated` | 自动；A/静态 | `get_player_buffs, get_objects_by_name_fr_arr, get_card_by_index_fr_arr, get_property, get_activating_eff, get_player_servant_skills, foreach_func, card_counts_power, calculate_number, edit_data_number, set_property, find_player_array_containing, unregister_object_effects, register_object_effects, draw_card_by_card` |
| `data/masters/00004_matou_sakura/00004_matou_sakura.json#/upgrade_skill/0/effects/0`<br>`corrosion_bind_ability` | `self_skill_awakened` | 自动；A/静态 | `get_eff_source_card, get_property, get_dictionary_value, get_player_master, get_objects_by_name_fr_arr, get_card_by_index_fr_arr, set_property, manage_buff` |
| `data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json#/effects/0`<br>`artificial_life_initial_magic` | `game_start` | 自动；A/静态 | `edit_magic` |
| `data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json#/effects/1`<br>`grail_vessel_activate_heavenly_robe` | `game_start, day_start` | 自动；A/静态 | `when, get_player_master, get_property, get_dictionary_value, get_objects_by_name_fr_arr, get_card_by_index_fr_arr, manage_buff, get_current_round, if_func, get_player_buffs, set_property` |
| `data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json#/effects/2`<br>`little_grail_attack_discount` | `game_start` | 自动；A/静态 | `edit_data_number` |
| `data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json#/effects/3`<br>`all_conceal_magic_gain` | `day_end` | 自动；A/静态 | `log_field_values, filter_by_property, array_length, if_func, edit_magic` |
| `data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json#/specials/BUFFS/0/effects/0`<br>`return_to_nothingness` | `day_start` | 自动；A/静态 | `query_log, array_length, compare_number, if_func, edit_score` |
| `data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json#/upgrade_skill/0/effects/0`<br>`third_magic_remove_strength_cards` | `self_skill_awakened` | 自动；A/静态 | `get_player_hand_cards, get_player_deck, get_player_discard, merge_arrays, get_cards_by_attributes_fr_arr, get_pl_attacks_out_game, foreach_func, find_player_array_containing, draw_card_by_card` |
| `data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json#/upgrade_skill/0/effects/1`<br>`passive` | `self_played_card` | 自动；A/静态 | `modify_attack_power_by_attribute` |
| `data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json#/upgrade_skill/0/effects/2`<br>`placeholder_third_magic_heavens_feel_win` | `self_skill_awakened, situation_activated` | 自动；A/静态 | `get_situations, get_objects_by_name_fr_arr, array_length, if_func, not_func, get_active_players_id, end_game` |
| `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json#/effects/0`<br>`two_faces_identity_switch` | `game_start, self_true_name_release, self_true_name_hidden` | 自动；A/静态 | `get_player_master, get_property, get_dictionary_value, get_objects_by_name_fr_arr, get_card_by_index_fr_arr, manage_buff, get_player_buffs, get_player_servant, is_null, is_true_name_released, or_func, not_func, set_property, activate_effect` |
| `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json#/specials/BUFFS/0/effects/0`<br>`placeholder_overseer_reveal_class` | `game_start, self_true_name_hidden, day_start` | 自动；A/静态 | `get_player_data_value, is_null, clone_object, set_player_data, get_dictionary_value, set_dictionary_value, get_activating_eff, get_property, get_all_players_id, foreach_func, store_value, if_func, not_func, get_player_servant, and_func` |
| `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json#/specials/BUFFS/0/effects/1`<br>`overseer_neutral_move` | `self_action_phase` | 自动；A/静态 | `get_player_data_value, compare_number, match_func, or_func, get_location_map_area, map_area_has_effect, get_map_area_by_name, not_func, get_property, get_card_by_index_fr_arr, get_pls_in_location, array_length, if_func, set_location, calculate_number, edit_magic, show_message` |
| `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json#/specials/BUFFS/1/effects/0`<br>`executor_total_power_boost` | `self_battle_phase` | 自动；A/静态 | `edit_data_number` |
| `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json#/upgrade_skill/0/effects/0`<br>`placeholder_evil_protector_true_name_defeat` | `self_battle_phase` | manual；A/静态 | `get_activating_eff, get_property, release_true_name, defeat, get_players_in_same_area, get_player_buffs, get_objects_by_name_fr_arr, get_card_by_index_fr_arr, if_func` |
| `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json#/upgrade_skill/0/effects/1`<br>`placeholder_evil_protector_basic_attack_boost` | `self_played_card` | 自动；A/静态 | `get_player_buffs, get_objects_by_name_fr_arr, get_card_by_index_fr_arr, get_property, if_func, log_field_values, modify_attack_power_by_attribute` |
| `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json#/upgrade_skill/0/effects/2`<br>`evil_protector_ignore_defeat` | `self_before_defeat` | 自动；A/静态 | `get_player_buffs, get_objects_by_name_fr_arr, get_card_by_index_fr_arr, get_property, if_func, cancel_pending_action` |
| `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json#/effects/0`<br>`assassination_add_snake_cards` | `game_start` | 自动；A/静态 | `get_player_master, get_property, get_dictionary_value, get_objects_by_name_fr_arr, get_card_by_index_fr_arr, get_player_deck, for_func, clone_object, add_to_array` |
| `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json#/effects/1`<br>`outsider_no_magic_from_workshop` | `game_start` | 自动；A/静态 | `get_player_master, get_property, get_dictionary_value, get_objects_by_name_fr_arr, get_card_by_index_fr_arr, manage_buff` |
| `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json#/effects/2`<br>`outsider_leave_workshop_discount` | `game_start` | 自动；A/静态 | `edit_data_number` |
| `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json#/effects/3`<br>`outsider_battle_phase_score_gain` | `self_battle_phase_end` | 自动；A 体存在；空心派发 | `sum_log_data, if_func, get_location_map_area, get_property, get_players_in_map_area, array_length, and_func, if_else_func, edit_score` |
| `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json#/upgrade_skill/0/effects/0`<br>`perfect_breathing_remove_magic_cards` | `self_skill_awakened` | 自动；A/静态 | `get_player_hand_cards, get_player_deck, get_player_discard, merge_arrays, get_cards_by_attributes_fr_arr, get_pl_attacks_out_game, foreach_func, find_player_array_containing, draw_card_by_card` |
| `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json#/upgrade_skill/0/effects/1`<br>`passive` | `self_played_card` | 自动；A/静态 | `modify_attack_power_by_attribute` |
| `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json#/upgrade_skill/0/effects/2`<br>`placeholder_perfect_breathing_snake_becomes_attack` | `self_skill_awakened, self_card_to_hand` | 自动；A/静态 | `get_player_deck, get_player_hand_cards, get_player_discard, get_player_played_cards, merge_arrays, get_objects_by_name_fr_arr, foreach_func, store_value, card_has_effect, not_func, build_effect, get_property, add_to_array, register_object_effects` |
| `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json#/upgrade_skill/0/effects/2/funcs/6/parameters/0/3/parameters/0`<br>`perfect_breathing_snake_attack` | `self_battle_phase` | manual；A/静态 | `get_eff_source_card, find_player_array_containing, get_player_played_cards, draw_card_by_card, set_property, sync_power` |
| `data/events/origin/contain_third_party/contain_third_party.json#/effects/1`<br>`contain_third_party_winner_restore_seal` | `battle_end` | 自动；A/静态 | `get_eff_source_card, get_property, get_area_round_winners, queue_optional_effect_for_players, get_data_number, edit_data_number` |
| `data/events/origin/ley_line/ley_line.json#/effects/0`<br>`ley_line_magic_plus_2` | `battle_end` | 自动；A/静态 | `get_eff_source_card, get_property, get_area_round_participants, foreach_func, edit_magic` |
| `data/attacks/class/avenger_class/avenger_class.json#/effects/0`<br>`avenger_other_attacks_plus_one` | `self_battle_phase` | 自动；A/静态 | `get_eff_source_card, modify_attack_power_by_attribute` |
| `data/attacks/class/avenger_class/avenger_class.json#/effects/1`<br>`avenger_unspeakable_hatred_residue` | `self_battle_win` | 自动；A/静态 | `log_field_values, get_card_by_index_fr_arr, array_difference, array_length, compare_number, match_func, get_eff_source_card, close_card` |
| `data/attacks/class/foreigner_class/foreigner_class.json#/effects/0`<br>`foreigner_true_name_plus_power` | `self_true_name_release` | 自动；A/静态 | `edit_data_number, get_eff_source_card, get_players_field, filter_by_property, array_length, compare_number, if_func, get_card_by_index_fr_arr, get_player_ids_by_data_value, and_func, get_player_discard, find_player_array_containing, draw_card_by_card` |
| `data/attacks/class/mooncancer_class/mooncancer_class.json#/effects/0`<br>`mooncancer_passive_grail_events` | `game` | 自动；A 注册占位；未实现 | `do_nothing` |
| `data/attacks/class/mooncancer_class/mooncancer_class.json#/effects/1`<br>`mooncancer_event_swap` | `self_action_phase` | 自动；A 注册占位；未实现 | `do_nothing` |
| `data/attacks/basic/luck/luck.json#/effects/0`<br>`luck_ignore_defeat` | `self_battle_phase` | manual；A/静态 | `remove_defeat` |
| `data/attacks/basic/preparation/preparation.json#/effects/0`<br>`preparation_double_terrain` | `self_action_phase` | 自动；A/静态 | `get_location, get_location_benefit, calculate_number, edit_location_benefit` |
| `data/attacks/basic/preparation/preparation.json#/effects/1`<br>`preparation_win_vp` | `self_battle_phase` | 自动；A/静态 | `schedule_effect_on_time_point, edit_score` |
| `data/attacks/basic/surveil/surveil.json#/effects/0`<br>`surveil_move` | `self_action_phase` | manual；A/静态 | `get_location_map_area, map_area_has_effect, store_value, for_func, get_property, or_func, not_func, move_location` |

### 4.1 未注册的 19 个 contribution：在本问题中的正确归类
全部 1182 个 func_name 中 1163 项已注册，19 项未注册；1182=1042 普通时点执行描述+140 power_query 描述。未注册 19 项均在后者。`load_helper.gd:148` 保存 power_query 原始数组；`board_power_query.gd:40–69` 在 total 查询时遍历亮出局势/事件并 evaluate；`125–156` 内联处理贡献，无某个 TimePoints 比较、不走 run_time_point。因此它们是**数据驱动、非 operation 的只读查询 DSL**，不是“时点效果写死”。不计入上面的 B 时点总数，单列非 operation 查询分支 3 类。
| descriptor | 次数 | 实现位置 | 在做什么 |
|---|---:|---|---|
| power_contribution | 5 | `scripts/system/global/board_power_query.gd:125–127` | 对目标玩家累计额外合计威力 |
| attack_power_contribution | 13 | `scripts/system/global/board_power_query.gd:128–146` | 按属性、类别、最低威力等数据筛选出牌，逐牌累计加成 |
| card_power_contribution | 1 | `scripts/system/global/board_power_query.gd:147–156` | 在局部 card_values 中虚拟改威力、累计差额，不写真实卡 |
可以考虑未来抽为独立纯只读求值原语，但不能直接塞入有副作用的正常 operation 管线。所属效果逐项：
- `data/situations/origin/calm_before_storm/calm_before_storm.json#/effects/0` / `calm_before_storm_agility_plus_2`；time_points=`[]`；`attack_power_contribution`。
- `data/situations/origin/curse_of_angra_mainyu/curse_of_angra_mainyu.json#/effects/0` / `curse_of_angra_mainyu_strength_plus_1`；time_points=`[]`；`attack_power_contribution`。
- `data/situations/origin/hope_for_future/hope_for_future.json#/effects/0` / `hope_for_future_same_attr_plus_3`；time_points=`[]`；`power_contribution`。
- `data/situations/origin/outrage/outrage.json#/effects/0` / `outrage_strength_plus_2`；time_points=`[]`；`attack_power_contribution`。
- `data/situations/origin/perfect_flow/perfect_flow.json#/effects/0` / `perfect_flow_magic_plus_2`；time_points=`[]`；`attack_power_contribution`。
- `data/situations/origin/shadow_of_angra_mainyu/shadow_of_angra_mainyu.json#/effects/0` / `shadow_of_angra_mainyu_agility_plus_1`；time_points=`[]`；`attack_power_contribution`。
- `data/situations/origin/substance_of_angra_mainyu/substance_of_angra_mainyu.json#/effects/0` / `substance_of_angra_mainyu_magic_plus_1`；time_points=`[]`；`attack_power_contribution`。
- `data/events/origin/contain_third_party/contain_third_party.json#/effects/0` / `contain_third_party_basic_plus_1`；time_points=`[]`；`attack_power_contribution`。
- `data/events/origin/cooperation/cooperation.json#/effects/0` / `cooperation_same_attr_plus_4`；time_points=`[]`；`power_contribution`。
- `data/events/origin/desperate_measure/desperate_measure.json#/effects/0` / `desperate_measure_rank_bonus`；time_points=`[]`；`power_contribution`。
- `data/events/origin/fate_battle/fate_battle.json#/effects/0` / `fate_battle_power_to_5`；time_points=`[]`；`card_power_contribution`。
- `data/events/origin/glorious_duel/glorious_duel.json#/effects/0` / `glorious_duel_attr_plus_2`；time_points=`[]`；`attack_power_contribution`。
- `data/events/origin/holy_ground/holy_ground.json#/effects/0` / `holy_ground_attr_plus_3`；time_points=`[]`；`attack_power_contribution`。
- `data/events/origin/occupy_high_ground/occupy_high_ground.json#/effects/0` / `occupy_high_ground_double_benefit`；time_points=`[]`；`power_contribution`。
- `data/events/origin/sacrifice_ground/sacrifice_ground.json#/effects/0` / `sacrifice_ground_attr_plus_2`；time_points=`[]`；`attack_power_contribution`。
- `data/events/origin/sneak_attack/sneak_attack.json#/effects/0` / `sneak_attack_hidden_name_plus_5`；time_points=`[]`；`power_contribution`。
- `data/events/origin/strength_test/strength_test.json#/effects/0` / `strength_test_attr_plus_3`；time_points=`[]`；`attack_power_contribution`。
- `data/events/origin/suppressive_fire/suppressive_fire.json#/effects/0` / `suppressive_fire_attr_plus_3`；time_points=`[]`；`attack_power_contribution`。
- `data/events/origin/treacherous_terrain/treacherous_terrain.json#/effects/0` / `treacherous_terrain_attr_plus_2`；time_points=`[]`；`attack_power_contribution`。

## 5. 核验收据与未覆盖层
- 真实执行：git status --short；git rev-parse HEAD（退出码0）；Python 只读遍历/正则与 JSON 解析（各调用 status=success），JSON 解析失败0，注册类缺文件0、缺 exec 声明0、PascalCase 映射差异0，普通执行描述未注册0。
- 数量由 Python 集合/Counter 校验，不心算：218=168+50；105=77+28；1182=1042+140=1163+19；B29=14+15。二次核对所有相关脚本与 JSON 未变化。
- 只改本报告；没有仓库改动，没有测试/引擎启动，没有 PID 操作。未确认的数据文案正确性、卡状态条件、前缀业务是否应新增、抽象后的 operation 设计及任何真实运行结果均为 **unknown**。
- 特别注意：已有代码注释仍把部分威力查询描述称为挂 battle_resolve，但当前 JSON time_points=[] 且真实运行入口是 BoardPowerQuery.total；本报告以代码和数据而非陈旧注释判定。

