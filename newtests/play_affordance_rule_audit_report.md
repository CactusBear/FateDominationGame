# 可打出提示与 PlayAttack 判据审计（仅测试层）

## 结论

**不支持“提示与 PlayAttack 逐条相同”的验收结论。** 当前正式常规出牌不调用 PlayAttack：提示与 `RegularPlay.submit_group` 在本次无动态费用修改的边界夹具中同判；`PlayAttack` 是另一合同，默认调用会拒绝所有无效果链的普通出牌。费用计算时点改变费用时发现实际业务缺陷；正式 v2 卡顶明置/暗置按钮没有接线。

本专项是**诊断通过**，不是用户 UI 要求通过。发现差异的断言显式要求重现差异，故 CHECK 全通过并不代表产品没有问题。没有窗口验收、全量回归、测速或正式卡数据穷举。

## 实际路径及定位

- 正式提示：`scripts/game_scene/battle_board_v2.gd:2557-2565,2645-2666,2882-2897`；组预览 -> `LocalBattleSource.read_group_preview:54-59` -> `MatchSeatQuery.preview:54-88` -> `RegularPlay.pending_modes:180-224`。
- 正式提交：board `3124-3133` -> `MatchCommandDispatcher:187-201` -> `RegularPlay.submit_group:304-322` -> `_resume_group:325-378`。**不经过 PlayAttack**。
- 单卡特殊入口：`scripts/system/operations/PlayAttack.gd:6-92`。
- 共同卡面和场面规则：`scripts/system/play_rules.gd:11-44,55-61`。
- 旧界面已有卡顶模式条：`tactical_board_ui.gd:2236-2247,2276-2313`。不能把旧入口当成正式 v2 已完成。

## 逐条合同对照

记 M=现有魔力，C=max(0,印刷费用-卡自身折扣-攻击玩家折扣)，S=常规流程开始的魔力快照；false=明置，true=暗置。下面“提示”是正式组预览中的候选模式，而非独立 actions.cards。

| 判据 | 常规明置提示与组提交 | 常规暗置提示与组提交 | PlayAttack 实际校验 | 定位/评价 |
|---|---|---|---|---|
| null、玩家不存在 | 候选/玩家门拒绝 | 同左 | null/玩家门拒绝 | RP133/182/240；PA7/18。空/不存在仅静态追踪 |
| 正在效果选择、游戏结束 | query/command入口挡选择；command挡游戏结束 | 同左 | 无对应门 | query57、dispatcher 上游；未实测这两个边界 |
| 玩家出局 | 拒绝 | 拒绝 | 拒绝 | RP185/245；PA21；实测 |
| 当前行动者 | 必须本人 | 必须本人 | 非效果驱动必须本人；ignore_limit且activating_eff存在可绕过 | RP185；PA31-36；实测 |
| 准备/前哨/战斗/行动 | `GameProgress.is_phase_for(action)`，支持 phase_as 替换 | 同左 | 非效果驱动仅看实际阶段 name==action | RP185、GP99-113；PA33。三非行动阶段及映射正反例均实测 |
| 默认单卡调用许可 | 提示不要求 activating_eff | 同左 | ignore_limit=false且activating_eff为空立即 false | PA14-15；实测合法常规牌仍被默认 PA 拒绝 |
| 来源区声明/所有权 | regular_play_zones + 技能/御主特殊候选，非来源弃牌/牌库拒绝 | 必须处于声明的“视为手牌”区 | 不验证候选/实际来源，只从 hand_cards erase | RP5-63/116-119；PA72-75。声明弃牌正例/未声明弃牌负例实测 |
| 已激活、已打出同对象 | 候选拒绝 | 候选拒绝 | 拒绝已激活，不拒绝已在 played_cards 的未激活对象 | RP21；PA37。两者分别实测 |
| 升华/未觉醒技能 | 技能须 `_is_awakened`；升华不入常规候选 | 技能没有暗置模式 | 参数仅接受 BaseAttack，不是技能入口 | RP17-18/107/118；未觉醒技能实测，独立升华来源仅静态 |
| CannotPlayCards 激活 BUFF | 拒绝 | 拒绝 | 拒绝 | RP187/247；PA25；实测 |
| 宝具禁令 | PlayRules.board_allows，全局拒绝 | 同左 | PlayRules.can_play复用该门 | PR33；激活战区 BUFF 全局禁令实测；事件/局势来源分支静态 |
| 特殊攻击禁令 | 当前战区事件/BUFF + 全局局势拒绝 | 同左 | 同左 | PR35-43；所在战区禁令实测；其他来源仅静态 |
| 需追加打出 | can_play 拒绝 `_need_extra_play` | 隐藏支路显式拒绝 | can_play 拒绝，即使ignore_limit也不绕过 | PR15；RP118；PA40；实测 |
| 卡面 min_magic=N | M>=N，免魔力不豁免条件 | 只检查board/攻击/来源/非追加，**不执行 min_magic** | M>=N，免魔力不豁免 | RP104-119；PR57-59。N=8/魔力7、8及免魔力7实测 |
| 未识别条件类型 | 当前实现放行 | 不检查卡面条件 | 当前实现放行 | PR60-61；实测。说明的是代码事实，不为未识别规则背书 |
| 非手牌技能区魔力门槛 | S>=skill_zone_magic_limit；immune/ignore_skill_zone_magic_limit/BaseSkill._ignore_limit可豁免 | 非攻击/非来源，无模式 | 无技能入口；区域内攻击也无该门槛 | RP110-112；8/7、玩家/卡牌豁免、手牌技能实测 |
| 当前支付能力 | C<=min(M,player_magic_limit)，且C<=待选剩余魔力 | 不付费，可M=0 | C<=M，不看player_magic_limit，不看待选费用 | RP112/119/192-196；PA62。恰好/差一点/资源上限/待选费用实测 |
| 折扣下限 | C>=0，攻击扣玩家及卡自身折扣；技能只卡自身 | 支付0 | C>=0，同攻击折扣 | RP86-90；PA52-58；实测 |
| 免魔力 | 不检查支付能力、不扣费，但仍检查条件/禁令 | 不扣费 | 不检查支付能力、不扣费，但仍检查条件/禁令 | RP112/119/195；PA60-65；实测 |
| 已完成常规流程 | 拒绝新候选与提交 | 同左 | 不检查 regular_play 完成日志 | RP182/240；实测 |
| 张数最低/上限 | 当前日志+同批非extra张数须可完成 minimum<=count<=limit | 同左 | PA48的数量门永远不可达：要到此行已必有ignore_limit或activating_eff，但该if要求两者都没有 | RP204-205/264-266；PA14与48；数量已满/min不足/上限差一点/默认效果内零上限实测 |
| 战场至少一张明置 | 存在合法完成路径 | 达最低张数后至少一明，否则不提供暗置 | 不检查战场/同批至少一明 | RP123/214/267；混合/全暗/非战场全暗实测 |
| 费用计算时点后的重校验 | **未重新验证支付能力**，直接按新C扣费 | 暗置付0，但仍派发费用计算时点 | 派发后重算C、重验M，余额不足拒绝 | RP341-349；PA55-63；真实效果专项重现差异 |

## 差异与最小修正建议（未改生产）

1. **费用事件后余额可成负数（明确业务缺陷）**：M=2,C=2,min=limit=1；本牌监听 SELF_CARD_COST_CALCULATED，通过正式 EditCardCost 将费用+1。明置提示为真，组提交返回true、牌实际入场、魔力=-1；同输入 PA 费用事件后返回false、牌未入场、魔力仍2。最小修正位置是RP“enter”扣费前，必须重验实际费用/魔力；整组需用既有完整检查点恢复并向命令端传播拒绝，避免修成“return但submit_group仍true”或留下前牌已扣费入场。不能仅把魔力clamp到0，也不能在只读UI查询中派效果。正式数据哪张牌会触发该增费尚未逐卡证实。
2. **PA不是常规出牌 oracle**：PA14-15默认拒绝、PA48不可达。保留特殊入口语义；最小契约修正是显式明确普通整组的唯一权威入口为RP，并让UI只消费该入口的模式投影，不把普通牌调用PA默认改成无条件放行。若业务确要求两个入口共用阶段/费用/禁令，将纯校验提取成显式 mode/context 参数 helper，保留特殊豁免，不复制第二份UI规则。
3. **阶段/候选/组合同不同**：phase_as battle->action 的普通明/暗可选、实际提交成功，PA拒绝；actual action->[] 提示拒绝而PA接受；未声明弃牌、已出未激活牌、completed、minimum/limit等PA均未检查。若PA仍要承载常规语义，需复用RP合法组合同而非零散补if；若保持特殊入口，这些差异应记录为有意合同，不作UI bug修补。
4. **暗置 min_magic 与PA不同**：N=8、M=7时常规只提供暗置，暗置实际成功；PA拒绝。PA没有“打出模式”参数，这不等于普通暗置违法，须先确认卡面条件是否也约束暗置。若确需暗置也检查条件，应在RP隐藏分支复用声明条件，不能绕过费用的同时绕过全部条件，也不要误禁止免费用暗置。
5. **player_magic_limit/待选组资源与PA不同**：M=20、cap=1、C=2时只有暗置，PA接受明置；待选前牌耗1、M=2、当前C=2也只有暗置，而PA独立调用接受。不同上下文不得拿PA独立结果扩大当前组候选。
6. **正式v2没有卡顶“明置/暗置”出牌按钮**：`_held_slot:2702-2715`仅 `_bind_effect_button`；`EffectButton`模板 `battle_board_v2.tscn:5331-5345`文案是“发动效果”，`_update_held_effect_button:2772-2794`可见性按manual_effects，不按合法出牌modes。现有右键入口 `2727-2736`读flip_cards，而 `MatchSeatQuery.flip_modes:124-134`对来源攻击直接返回[false,true]，不是pending_modes：它是预先翻面，不是合法出牌模式选择。最小UI接线应新增/复用独立卡顶模式条，严格从当前组 preview.candidates.modes 生成（false明/true暗），选择时再次验证当前组；不要搬回二级选牌窗、用flip_cards代替或为非法模式显示失败提示。
7. **金框混合了“可出牌/可发动效果”**：正式 `2648-2655,2962-2982`用`_held_card_playable OR manual_effects非空`；呼吸框 `2660-2666`还受输入可用/选择状态影响。“至少一种出牌方式合法”的纯规则判据本次已验证；**实际金框并非只表达出牌合法性**。若用户要求金框仅表示可打出，拆分gold出牌提示与主动效果提示，保持后者独立按钮，不删技能能力。

## 专项执行与证据

- 命令：`python newtests/run_play_affordance_rule_audit.py --label boundary-03`。
- 实际Godot：独占E盘引擎副本，`--headless --fixed-fps 60 --path <E冻结工程> --scene res://newtests/play_affordance_rule_audit_test.tscn`。600s每进程看门狗；主/派生落盘探针、import、专项均通过，Windows Job自有进程归零。
- **最新冻结专项 CHECK=438；RESULT checks=438 failures=[]；Godot exit=0；ERROR/SCRIPT ERROR=0；WARNING=0；全部已启动Job ActiveProcesses=0。runner exit=1（源码并行漂移门拒绝），不能宣称当前活工程一致性通过。** 前一版boundary-02为338 CHECK、runner exit0且无源码漂移；最新测试补上非法组真实提交拒绝/无扣费无入场后增加100 CHECK，不把两个版本计数相加。
- 45条运行记录：43条静态边界矩阵 + 2条费用时点记录；另有默认PA拒绝、效果驱动豁免、PA数量门不可达三项实测CHECK。
- 43条矩阵每项核对`pending_modes`、权威query投影、正式v2 `_held_card_playable`、对最多两张牌穷举`can_submit_group`合法完成见证、真实submit入场/明暗状态；不使用Python规则替身。禁用模式没有合法完成见证，且对所构造非法完整组实际submit_group均拒绝、魔力/来源/已出牌及激活明暗状态不变；有模式的见证实际提交成功。费用时点另行作为差异重现，而不混入静态同判结论。
- 非窗口边界：未实例化/入树正式board场景，只创建正式脚本对象调用提示函数；不声称画面、真实鼠标悬浮、按钮可点击、呼吸动画或失败提示弹窗已验收。按钮缺失及框语义混用是源码接线差异。
- boundary-03 `freeze_drift={}`，但另一个并行写入者修改了 `scripts/system/global/effect_manager.gd`：冻结源hash `626754ecdacb21cc22353e53ae743bd74a9f0586a85c8e0bb5b849ebc4bb1d68`，运行结束活源码hash `8d4526b0ccf550d6f0fa72f5248e9d8f25bba56a68a9c8a8cb0280cb11bc47e9`。一次当前源码稳定复核boundary-04在复制同一文件时再次发生hash漂移，预检拒绝，未启动Godot（无本次专项CHECK，不冒称Job执行通过）。不再争用复制重试；需主代理等effect_manager写入者结束后串行重跑同一个小专项。上述生成树均按所有权移除，证据保留。没有改生产GD/.tscn；初始工作树已有大量并行变更，未回滚。
- 首次boundary-01因测试夹具`BaseBuff.new()`漏两个必填参数解析失败（SCRIPT ERROR），未冒充通过；精确终止本runner自有Godot PID26352后记录exit15/Job0、归档并清理。仅修测试构造再完整重跑boundary-02通过。保留首红路径，不覆盖历史失败。

最新专项manifest：`E:/scratch/play-affordance-rule-audit-boundary-03/isolated-a107ee8932f74500aa35ff728ba1a7f4/manifest.json`。
前次完整干净manifest：`E:/scratch/play-affordance-rule-audit-boundary-02/isolated-50b0fe906eac41c58f0ac336ff614f14/manifest.json`。
稳定复核预检拒绝manifest：`E:/scratch/play-affordance-rule-audit-boundary-04/isolated-5f46eae26f22405ea4721233dc5edf8a/manifest.json`。
首红manifest：`E:/scratch/play-affordance-rule-audit-boundary-01/isolated-aecaa816ebaa42cd873ae66ab43f5a18/manifest.json`。
仓内精简证据：`newtests/play_affordance_rule_audit_evidence.json`。

## 逐用例真实观测

PlayAttack列为`ignore_limit=true, activating_eff=null`的普通阶段约束单卡调用，技能不适用；默认及效果驱动模式另列上述三项。该调用不含待选牌，刻意展示合同差异，不假称同一整组。

| 真实用例 | 提示模式 | 已执行模式 | v2 可出判据 | PlayAttack 单卡结果 |
|---|---|---|---|---|
| magic exact 2 | 明置、暗置 | 明置、暗置 | 是 | 通过 |
| magic short 1 | 暗置 | 暗置 | 是 | 拒绝 |
| magic zero | 暗置 | 暗置 | 是 | 拒绝 |
| discount exact | 明置、暗置 | 明置、暗置 | 是 | 通过 |
| discount short | 暗置 | 暗置 | 是 | 拒绝 |
| discount clamps zero | 明置、暗置 | 明置、暗置 | 是 | 通过 |
| immune bypass cost | 明置、暗置 | 明置、暗置 | 是 | 通过 |
| magic cap exact | 明置、暗置 | 明置、暗置 | 是 | 通过 |
| magic cap short | 暗置 | 暗置 | 是 | 通过 |
| min magic exact | 明置、暗置 | 明置、暗置 | 是 | 通过 |
| min magic short | 暗置 | 暗置 | 是 | 拒绝 |
| immune does not bypass min magic | 暗置 | 暗置 | 是 | 拒绝 |
| unknown requirement | 明置、暗置 | 明置、暗置 | 是 | 通过 |
| extra play prohibited | 无 | 无 | 否 | 拒绝 |
| activated prohibited | 无 | 无 | 否 | 拒绝 |
| already played candidate excluded | 无 | 无 | 否 | 通过 |
| undeclared discard excluded | 无 | 无 | 否 | 通过 |
| declared discard allowed | 明置、暗置 | 明置、暗置 | 是 | 通过 |
| out prohibited | 无 | 无 | 否 | 拒绝 |
| wrong actor prohibited | 无 | 无 | 否 | 拒绝 |
| phase 0 prohibited | 无 | 无 | 否 | 拒绝 |
| phase 1 prohibited | 无 | 无 | 否 | 拒绝 |
| phase 3 prohibited | 无 | 无 | 否 | 拒绝 |
| effective action in battle | 明置、暗置 | 明置、暗置 | 是 | 拒绝 |
| actual action remapped away | 无 | 无 | 否 | 通过 |
| play limit short | 无 | 无 | 否 | 通过 |
| no completion support | 无 | 无 | 否 | 通过 |
| committed at limit | 无 | 无 | 否 | 通过 |
| flow completed | 无 | 无 | 否 | 通过 |
| cannot play buff | 无 | 无 | 否 | 拒绝 |
| noble forbidden | 无 | 无 | 否 | 拒绝 |
| special area forbidden | 无 | 无 | 否 | 拒绝 |
| battle second all hidden | 明置 | 明置 | 是 | 通过 |
| battle second after faceup | 明置、暗置 | 明置、暗置 | 是 | 通过 |
| nonbattle second all hidden | 明置、暗置 | 明置、暗置 | 是 | 通过 |
| pending cost exactly | 明置、暗置 | 明置、暗置 | 是 | 通过 |
| pending cost short | 暗置 | 暗置 | 是 | 通过 |
| skill zone exact 8 | 明置 | 明置 | 是 | 不适用（技能） |
| skill zone short 7 | 无 | 无 | 否 | 不适用（技能） |
| skill zone explicit bypass | 明置 | 明置 | 是 | 不适用（技能） |
| skill card zone bypass | 明置 | 明置 | 是 | 不适用（技能） |
| unawakened skill prohibited | 无 | 无 | 否 | 不适用（技能） |
| hand skill no zone threshold | 明置 | 明置 | 是 | 不适用（技能） |
| dynamic cost group | 明置可选 | 实际入场 | 是 | 费用=3，魔力余量=-1.0 |
| dynamic cost single | 明置可选 | 拒绝入场 | 是 | 费用=3，魔力余量=2 |
