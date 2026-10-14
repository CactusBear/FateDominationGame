# 常规出牌 operation 组合审计：逐步骤对照

## 1. 结论、范围与计数

**RegularPlay 是“直接规则状态写入 + 部分已有 operation + 时点/续行框架”的混合编排，不是完全通过 operation 组合实现。** 它已使用 CardCountsPower、ApplyCardKeywords、PlayerBuffsHaveEffect；不能说“完全没用 operation”。也不能把 PlayAttack/AddAttack 的整段调用当作无行为差异的替代。

- 工作树：`E:/Projects/Godot/FateDominationGame-master`；HEAD `8c0f946faf6cc0cd3f04f12f66f5a99a413088ca`，以实际只读核验补入。源码位置均是**本次工作树**行号，不是 HEAD 文件行号。
- 只读核对注册表和 operations 全部 `.gd`：**214 个注册项、214 个文件、214 个唯一 func_name；缺文件 0、未注册文件 0、文件名/类名不符 0**。候选不仅看名字，还阅读 exec 与相关基础实现。
- 规则状态/外部副作用表：RegularPlay **21 行：A=12、B=6、C=3**。A 中 **10 行已有等价原语但未用、2 行已使用**；R14 内查询 CardCountsPower 也已经使用。
- 另列续行/编排帧 **19 行：A=12、C=7**，不混入玩家规则状态计数。若把帧也合计，RegularPlay 为 **40 行：A=24、B=6、C=10**。
- PlayAttack 对照 **11 行：A=6、B=2、C=3**。这些 B 是同类缺口，不再重复计为新能力。
- **缺口按能力去重为 2 类：任意事实记录、无资源改写/无时点的支付事实记录。最小新增数量是 1：RecordLog；支付记录随后可由已有算术/条件原语与新 RecordLog 组合。** RecordResourcePayment 是便利替代候选，不是必需的第二个新增。
- 只写本报告；不改生产/数据/技能文件，不启动 Godot，不触碰 PID 17120/28100，不评估前端改动。工作树预先已有大量修改；不将其归因于本审计。

### 分类与穷尽边界

- **A**：已有语义等价 operation 或其组合，分清“已经调用”与“存在但没调用”。等价要求保留对象身份、数值约束、setter、日志、时点、顺序，不只是最终数值相同。
- **B**：当前注册的 operation 没有等价能力。GameLog 静态方法存在不代表 operation 存在；大型 Play/Add 操作中顺带做过也不代表有单独原语。
- **C**：应继续由编排/框架内联调用，负责时点实际 source、批次或续行生命周期。这里“必须内联”是保留当前框架语义的最小改造约束，**不是声称技术上永远不能再包一层 operation**。若追求每个框架调用都 operation 化，可另议包装，但不计入本次规则原语 B 缺口。
- 一行按**静态写入站点**计数，不按实际出牌张数计数；同一行 L63 的四个 erase 拆为四行，保留代码原文。直接 `_take_from_source` 调用与实际 erase 不重复计数。
- `can_submit_group`、`can_add` 等预检中的局部 `seen.append`、模拟余额 `magic -= cost(...)`、搜索数组 append/erase 是私有求值状态，**不改变对局**，不计为规则副作用；续行 `state` 因跨暂停保存，单独列出。
- ApplyCardKeywords / TimePointChecker 的副作用以边界调用为一行，不把任意卡牌效果产生的未知后继状态修改虚构为固定步骤；已知框架内部作用在 §5 说明。

## 2. RegularPlay：规则状态及副作用逐行

入口：`submit_group` L304–322 先完整预检；`add` L404–411 走单张预检。来源删除调用原文：`scripts/system/regular_play.gd:352`，`_take_from_source(d, card)`；其实际写入为 R08–R12。

A 项路径均指向 `scripts/system/operations/<类名>.gd`；链接文本即类名。B 新增签名见 §7。
| 编号 | 步骤 | 文件:行 + 代码原文 | 分类 | 对应 operation / 留内联 | 等价条件或差异 |
|---|---|---|---|---|---|
| R01 | 整组开始事实 | `scripts/system/regular_play.gd:309`<br>`GameLog.record("regular_play_start", id, -1, "", null, [], {"magic":d.magic.number})` | B | 建议 `RecordLog`（N1） | 开始魔力只在本回合没有 regular_play_start 时记录；不是单纯调试日志。 |
| R02 | 整组预结算真名解放 | `scripts/system/regular_play.gd:318`<br>`ApplyCardKeywords.new().apply(ApplyCardKeywords.TRUE_NAME_RELEASE, id)` | A | [ApplyCardKeywords](scripts/system/operations/ApplyCardKeywords.gd)（类 `ApplyCardKeywords`） → [ReleaseTrueName](scripts/system/operations/ReleaseTrueName.gd)（类 `ReleaseTrueName`） | 已有且已使用：调用 ApplyCardKeywords.apply，不是泛化 exec。只对首张明置、带该词条的牌预结算；替换为 ReleaseTrueName.exec(id) 可保留当前分支，但留原写法更直接。 |
| R03 | 每张牌的费用计算时点 | `scripts/system/regular_play.gd:341`<br>`TimePointChecker.dynamic_time_point([TimePoints.CARD_COST_CALCULATED], id, cards[state.index])` | C | 保留 `TimePointChecker.dynamic_time_point` | 必须保留实际 source 和派发前的 phase 游标；EmitTimePoint/PlayedCards 均不能等价替代。 |
| R04 | 扣魔力 | `scripts/system/regular_play.gd:348`<br>`d.magic.minus(BaseNumber.new(paid))` | A | [EditNumAndReturn](scripts/system/operations/EditNumAndReturn.gd)（类 `EditNumAndReturn`） | 已有未用：保留 L346 免疫且 paid>0 条件，exec(d.magic, BaseNumber.new(-paid)) 原地改同一引用；不夹余额、不派魔力变化时点。 |
| R05 | 资源支付事实 | `scripts/system/regular_play.gd:349`<br>`GameLog.record_resource_payment("magic", id, before, d.magic.number, "regular_play", card)` | B | 建议 `RecordResourcePayment`（N2）；最小方案用新增 N1 组合 | GameLog 有该静态工具，不等于有 operation；EditMagic 内部虽调用它，却额外夹取、派 MAGIC_DECREASE，不等价。 |
| R06 | 写明暗置状态 | `scripts/system/regular_play.gd:350`<br>`card._is_concealed = hidden` | A | [SetProperty](scripts/system/operations/SetProperty.gd)（类 `SetProperty`） | 已有未用：exec(card, "_is_concealed", hidden)。不要用 SetCardConcealed：会同步威力/可能亮出。 |
| R07 | 写激活状态 | `scripts/system/regular_play.gd:351`<br>`card._is_activating = not hidden` | A | [SetProperty](scripts/system/operations/SetProperty.gd)（类 `SetProperty`） | 已有未用：exec(card, "_is_activating", not hidden)。通过对象属性 setter，与原赋值一样保留 source_deactivated 等可能副作用。 |
| R08 | 从声明的常规来源区删除 | `scripts/system/regular_play.gd:62`<br>`zone.erase(card)` | A | [RemoveFromArray](scripts/system/operations/RemoveFromArray.gd)（类 `RemoveFromArray`） | 由 L352 _take_from_source 调入；保留 play_zone_arrays(d) 的原循环、原数组和顺序，逐区 exec(card, zone)；只删一个匹配项。 |
| R09 | 从手牌删除 | `scripts/system/regular_play.gd:63`<br>`d.hand_cards.erase(card); d.servant_skills.erase(card); d.master_skills.erase(card); d.side.skills.erase(card)` | A | [RemoveFromArray](scripts/system/operations/RemoveFromArray.gd)（类 `RemoveFromArray`） | 由 L352 调入；本行原文有四次写，本行关注 `d.hand_cards.erase(card)`。应逐次替换，不对同一数组去重。 |
| R10 | 从从者技能区删除 | `scripts/system/regular_play.gd:63`<br>`d.hand_cards.erase(card); d.servant_skills.erase(card); d.master_skills.erase(card); d.side.skills.erase(card)` | A | [RemoveFromArray](scripts/system/operations/RemoveFromArray.gd)（类 `RemoveFromArray`） | 由 L352 调入；本行原文有四次写，本行关注 `d.servant_skills.erase(card)`。应逐次替换，不对同一数组去重。 |
| R11 | 从御主技能区删除 | `scripts/system/regular_play.gd:63`<br>`d.hand_cards.erase(card); d.servant_skills.erase(card); d.master_skills.erase(card); d.side.skills.erase(card)` | A | [RemoveFromArray](scripts/system/operations/RemoveFromArray.gd)（类 `RemoveFromArray`） | 由 L352 调入；本行原文有四次写，本行关注 `d.master_skills.erase(card)`。应逐次替换，不对同一数组去重。 |
| R12 | 从 side.skills 删除 | `scripts/system/regular_play.gd:63`<br>`d.hand_cards.erase(card); d.servant_skills.erase(card); d.master_skills.erase(card); d.side.skills.erase(card)` | A | [RemoveFromArray](scripts/system/operations/RemoveFromArray.gd)（类 `RemoveFromArray`） | 由 L352 调入；本行原文有四次写，本行关注 `d.side.skills.erase(card)`。应逐次替换，不对同一数组去重。 |
| R13 | 追加到 played_cards | `scripts/system/regular_play.gd:353`<br>`d.played_cards.append(card)` | A | [AddToArray](scripts/system/operations/AddToArray.gd)（类 `AddToArray`） | 已有未用：exec(card, d.played_cards, -1)，保留不去重、不登记效果的 append 语义。 |
| R14 | 入场后判定并累加威力 | `scripts/system/regular_play.gd:354`<br>`if CardCountsPower.new().exec(card, id): d.power.add(card._power)` | A | [CardCountsPower](scripts/system/operations/CardCountsPower.gd)（类 `CardCountsPower`） + [EditNumAndReturn](scripts/system/operations/EditNumAndReturn.gd)（类 `EditNumAndReturn`） / [SetProperty](scripts/system/operations/SetProperty.gd)（类 `SetProperty`） | CardCountsPower 已使用；纯增量写未用 operation。保留判定在 L353 后；非零威力可 EditNumAndReturn，完整零值/类型保真方案见 §6，不能无条件换 EditPower。 |
| R15 | 单牌 play 事实 | `scripts/system/regular_play.gd:355`<br>`GameLog.record("play", id, -1, "", card, ["play"], {"card_name":card._name, "card_type":"attack" if card is BaseAttack else "skill", "extra":state.extra_cards.has(card), "concealed":hidden})` | B | 建议 `RecordLog`（N1） | 保留 card 引用、play tag、extra 的整组计算与 concealed 字段；PlayAttack/AddAttack 的硬编码日志不能代替。 |
| R16 | 逐张明置词条结算 | `scripts/system/regular_play.gd:363`<br>`ApplyCardKeywords.new().exec(cards[state.index], id)` | A | [ApplyCardKeywords](scripts/system/operations/ApplyCardKeywords.gd)（类 `ApplyCardKeywords`） | 已有且已使用 exec(cards[state.index], id)；暗置分支跳过该阶段。不能因为仍有直写便声称完全没组合 operation。 |
| R17 | 逐张明置亮出事件 | `scripts/system/regular_play.gd:368`<br>`TimePointChecker.card_revealed(card)` | C | 保留 `TimePointChecker.card_revealed` | 一次全局批次包含 CARD_REVEALED/SELF_CARD_REVEALED/OTHERS_CARD_REVEALED，并保留 source；拆三个 EmitTimePoint 会改批次/来源。 |
| R18 | 整批入场后逐张 PLAYED_CARD | `scripts/system/regular_play.gd:376`<br>`TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], id, card)` | C | 保留 `TimePointChecker.dynamic_time_point` | 包括暗置牌；原 index 前移后派发，整批进场并完成 play 事实才开始这一轮。PlayedCards 无 source，不等价。 |
| R19 | 整组完成事实 | `scripts/system/regular_play.gd:381`<br>`GameLog.record("regular_play", id, -1, "", null, [], {"count":played_count(id), "forced":false})` | B | 建议 `RecordLog`（N1） | _finish_group；count=played_count(id)、forced=false。该事实决定 completed，不是可删日志。 |
| R20 | 增量开始事实 | `scripts/system/regular_play.gd:408`<br>`GameLog.record("regular_play_start", id, -1, "", null, [], {"magic":d.magic.number})` | B | 建议 `RecordLog`（N1） | add 的独立写入站点；同 R01 的本回合去重条件。 |
| R21 | 增量/显式 finalize 完成事实 | `scripts/system/regular_play.gd:396`<br>`GameLog.record("regular_play", id, -1, "", null, [], {"count":played_count(id), "forced":forced})` | B | 建议 `RecordLog`（N1） | finalize；由 _finish_incremental 调入或独立调用，须保留 can_finalize / forced&&!has_legal_add 的门禁及原 forced 参数。 |

### 2.1 Read-only 预检不是“提前扣费”

`can_submit_group` L249–267：`seen` 为新局部数组，`magic` 为数值副本，L260 `seen.append(card)`、L261 `faceup = faceup or not hidden`、L263 `magic -= cost(card, d)` 都不写玩家数据。实际扣费只在 R04。`candidates`、`PlayRules.can_play/board_allows`、`PlayerBuffsHaveEffect.exec` 是只读资格查询。

`cost` L86–90 原文：

```gdscript
static func cost(card: BaseHandCard, d: Dictionary) -> float:
	var discount: float = card._cost_discount.number
	if card is BaseAttack:
		discount += d.attack_cost_discount.number
	return maxf(0, card._cost.number - discount)
```

### 2.2 所有跨暂停续行帧写与编排动作

这些 A 只是机械字典写已有 SetDictionaryValue，不代表应把状态机改写成一长串效果描述。保留 phase/index 在可能暂停的动作**之前**推进，是避免恢复时重复扣费/重复派发的关键。
| 编号 | 步骤 | 文件:行 + 代码原文 | 分类 | 对应 operation / 留内联 | 等价条件或差异 |
|---|---|---|---|---|---|
| K01 | 构造整组续行帧 | `scripts/system/regular_play.gd:313`<br>`var state:Dictionary = {"id": id, "cards": cards.duplicate(), "hidden": hidden_flags.duplicate(), "phase": "extras", "index": 0, "finish": Callable(RegularPlay, "_finish_group").bind(id)}` | C | 留在 RegularPlay 编排层 | 保存本次 cards/hidden 的副本、起点与 finish Callable；属于生命周期框架，不新增“整组出牌 operation”。 |
| K02 | 预词条后的延期登记/同步续行 | `scripts/system/regular_play.gd:320-321`<br>`if not EffectManager.defer_until_runtime_guard_complete(Callable(RegularPlay, "_resume_group").bind(state)):`<br>`		_resume_group(state)` | C | 留在 RegularPlay 编排层 | 会登记 GuardContinuation/事务归属/审计尾票；必须和 frame 一起留在编排层。 |
| K03 | 缓存本批追加资格 | `scripts/system/regular_play.gd:333`<br>`state["extra_cards"] = batch_extra_cards(id, cards, hidden_flags)` | A | [SetDictionaryValue](scripts/system/operations/SetDictionaryValue.gd)（类 `SetDictionaryValue`） | 机械写字典已有等价原语（未使用）；值计算与阶段顺序仍须由调用方持有。最小改造不建议为换语法而包装这些游标。 |
| K04 | extras→cost | `scripts/system/regular_play.gd:334`<br>`state.phase = "cost"` | A | [SetDictionaryValue](scripts/system/operations/SetDictionaryValue.gd)（类 `SetDictionaryValue`） | 机械写字典已有等价原语（未使用）；值计算与阶段顺序仍须由调用方持有。最小改造不建议为换语法而包装这些游标。 |
| K05 | 重置 played 游标 | `scripts/system/regular_play.gd:337`<br>`state.index = 0` | A | [SetDictionaryValue](scripts/system/operations/SetDictionaryValue.gd)（类 `SetDictionaryValue`） | 机械写字典已有等价原语（未使用）；值计算与阶段顺序仍须由调用方持有。最小改造不建议为换语法而包装这些游标。 |
| K06 | cost→played | `scripts/system/regular_play.gd:338`<br>`state.phase = "played"` | A | [SetDictionaryValue](scripts/system/operations/SetDictionaryValue.gd)（类 `SetDictionaryValue`） | 机械写字典已有等价原语（未使用）；值计算与阶段顺序仍须由调用方持有。最小改造不建议为换语法而包装这些游标。 |
| K07 | cost→enter（先于派发） | `scripts/system/regular_play.gd:340`<br>`state.phase = "enter"` | A | [SetDictionaryValue](scripts/system/operations/SetDictionaryValue.gd)（类 `SetDictionaryValue`） | 机械写字典已有等价原语（未使用）；值计算与阶段顺序仍须由调用方持有。最小改造不建议为换语法而包装这些游标。 |
| K08 | 暗置：推进游标 | `scripts/system/regular_play.gd:357`<br>`state.index += 1` | A | [SetDictionaryValue](scripts/system/operations/SetDictionaryValue.gd)（类 `SetDictionaryValue`） | 机械写字典已有等价原语（未使用）；值计算与阶段顺序仍须由调用方持有。最小改造不建议为换语法而包装这些游标。 |
| K09 | 暗置：enter→cost | `scripts/system/regular_play.gd:358`<br>`state.phase = "cost"` | A | [SetDictionaryValue](scripts/system/operations/SetDictionaryValue.gd)（类 `SetDictionaryValue`） | 机械写字典已有等价原语（未使用）；值计算与阶段顺序仍须由调用方持有。最小改造不建议为换语法而包装这些游标。 |
| K10 | 明置：enter→keywords | `scripts/system/regular_play.gd:360`<br>`state.phase = "keywords"` | A | [SetDictionaryValue](scripts/system/operations/SetDictionaryValue.gd)（类 `SetDictionaryValue`） | 机械写字典已有等价原语（未使用）；值计算与阶段顺序仍须由调用方持有。最小改造不建议为换语法而包装这些游标。 |
| K11 | keywords→reveal（先于结算） | `scripts/system/regular_play.gd:362`<br>`state.phase = "reveal"` | A | [SetDictionaryValue](scripts/system/operations/SetDictionaryValue.gd)（类 `SetDictionaryValue`） | 机械写字典已有等价原语（未使用）；值计算与阶段顺序仍须由调用方持有。最小改造不建议为换语法而包装这些游标。 |
| K12 | 亮出前推进游标 | `scripts/system/regular_play.gd:366`<br>`state.index += 1` | A | [SetDictionaryValue](scripts/system/operations/SetDictionaryValue.gd)（类 `SetDictionaryValue`） | 机械写字典已有等价原语（未使用）；值计算与阶段顺序仍须由调用方持有。最小改造不建议为换语法而包装这些游标。 |
| K13 | 亮出前 reveal→cost | `scripts/system/regular_play.gd:367`<br>`state.phase = "cost"` | A | [SetDictionaryValue](scripts/system/operations/SetDictionaryValue.gd)（类 `SetDictionaryValue`） | 机械写字典已有等价原语（未使用）；值计算与阶段顺序仍须由调用方持有。最小改造不建议为换语法而包装这些游标。 |
| K14 | 完成回调 | `scripts/system/regular_play.gd:372`<br>`state.finish.call()` | C | 留在 RegularPlay 编排层 | 执行 _finish_group 或 _finish_incremental；其日志另见 R19/R21，不能替换成一个过早的“打出”动作。 |
| K15 | PLAYED_CARD 前推进游标 | `scripts/system/regular_play.gd:375`<br>`state.index += 1` | A | [SetDictionaryValue](scripts/system/operations/SetDictionaryValue.gd)（类 `SetDictionaryValue`） | 机械写字典已有等价原语（未使用）；值计算与阶段顺序仍须由调用方持有。最小改造不建议为换语法而包装这些游标。 |
| K16 | 阶段末延期登记 | `scripts/system/regular_play.gd:377-378`<br>`if EffectManager.defer_until_runtime_guard_complete(Callable(RegularPlay, "_resume_group").bind(state)):`<br>`			return` | C | 留在 RegularPlay 编排层 | 可能入延期队列、保存事务尾票；返回不代表已完成，不能移走或删除。 |
| K17 | 达到上限后 finalize | `scripts/system/regular_play.gd:384`<br>`if played_count(id) >= limit(id): finalize(id)` | C | 留在 RegularPlay 编排层 | 编排分支；实际完成日志见 R21。 |
| K18 | 无可追加时 forced finalize | `scripts/system/regular_play.gd:385`<br>`elif not has_legal_add(id): finalize(id, true)` | C | 留在 RegularPlay 编排层 | 编排分支；实际完成日志见 R21。 |
| K19 | 构造增量帧并执行 | `scripts/system/regular_play.gd:410`<br>`_resume_group({"id": id, "cards": [card], "hidden": [hidden], "phase": "cost", "index": 0, "extra_cards": [], "finish": Callable(RegularPlay, "_finish_incremental").bind(id)})` | C | 留在 RegularPlay 编排层 | phase=cost、extra_cards=[]；不预结算整组真名，不判整组追加资格，与 submit_group 不可偷换。 |

## 3. PlayAttack：对应副作用逐行

`PlayAttack.exec` 自身已经是注册 operation，但内部依然直接扣资源、append、erase、add、写日志。不能因此推断 RegularPlay 的每个子动作已有单一职责 operation。它当前仅供显式特殊出牌：L14 默认在无 activating_eff 且不 ignore_limit 时拒绝；不是常规整组入口。
| 编号 | 步骤 | 文件:行 + 代码原文 | 分类 | 对应 operation / 留内联 | 等价条件或差异 |
|---|---|---|---|---|---|
| P01 | 费用计算时点 | `scripts/system/operations/PlayAttack.gd:55`<br>`TimePointChecker.dynamic_time_point([TimePoints.CARD_COST_CALCULATED], id, attack)` | C | 同 R03，保留 source | 一致：都在实际扣费之前；不一致：本入口费用时点后还验可支付性，并提前缓存费用/折扣对象引用。 |
| P02 | 扣魔力 | `scripts/system/operations/PlayAttack.gd:67`<br>`pl_magic.minus(BaseNumber.new(final_cost))` | A | [EditNumAndReturn](scripts/system/operations/EditNumAndReturn.gd)（类 `EditNumAndReturn`） | 同 R04 的原地非零扣减。这里条件仅 !is_magic_immune，final_cost=0 仍调用 minus；为严格保留零值数值类型，应零值保留原写或用 §6 的 SetProperty 组合。 |
| P03 | 支付事实 | `scripts/system/operations/PlayAttack.gd:69`<br>`GameLog.record_resource_payment("magic", id, magic_before, pl_magic.number, "effect_attack", attack)` | B | N2 或新增 N1 组合 | 实际支出记录口径一致，purpose 不同：effect_attack 对 regular_play。零支出不记日志。 |
| P04 | 激活 | `scripts/system/operations/PlayAttack.gd:70`<br>`attack._is_activating = true` | A | [SetProperty](scripts/system/operations/SetProperty.gd)（类 `SetProperty`） | 不一致：总写 true；没有写 _is_concealed=false，不能假设强制明置。RegularPlay 同时按 hidden 写两字段。 |
| P05 | 入场 append | `scripts/system/operations/PlayAttack.gd:73`<br>`playered_cards_arr.append(attack)` | A | [AddToArray](scripts/system/operations/AddToArray.gd)（类 `AddToArray`） | append 行为一致；在本入口先 append 再删除手牌，RegularPlay 先全来源删除再 append。 |
| P06 | 只移除手牌 | `scripts/system/operations/PlayAttack.gd:75`<br>`(player_data["hand_cards"] as Array).erase(attack)` | A | [RemoveFromArray](scripts/system/operations/RemoveFromArray.gd)（类 `RemoveFromArray`） | 不一致：仅 hand_cards；没有 regular_play_zones、servant_skills、master_skills、side.skills 的擦除。 |
| P07 | 入场后判定并累加威力 | `scripts/system/operations/PlayAttack.gd:79-81`<br>`if CardCountsPower.new().exec(attack, id):`<br>`		var pl_power = player_data["power"] as BaseNumber`<br>`		pl_power.add(power)` | A | [CardCountsPower](scripts/system/operations/CardCountsPower.gd)（类 `CardCountsPower`） + [EditNumAndReturn](scripts/system/operations/EditNumAndReturn.gd)（类 `EditNumAndReturn`） / [SetProperty](scripts/system/operations/SetProperty.gd)（类 `SetProperty`） | 一致：CardCountsPower 在 append 后；不一致：加 power 参数（默认开头捕获的 _power 引用），RegularPlay 在入场时取 card._power。 |
| P08 | play 事实 | `scripts/system/operations/PlayAttack.gd:84-85`<br>`GameLog.record("play", id, -1, "", attack, ["play"],`<br>`		{"card_name": attack._name, "card_type": "attack", "extra": true})` | B | 建议 N1 | 不一致：extra=true；不写 concealed；tags 同样只有 play（AddAttack 才有 extra tag）。 |
| P09 | 词条结算 | `scripts/system/operations/PlayAttack.gd:89`<br>`ApplyCardKeywords.new().exec(attack, id)` | A | [ApplyCardKeywords](scripts/system/operations/ApplyCardKeywords.gd)（类 `ApplyCardKeywords`） | 已有且已使用；先 play 日志后词条，再亮出和 PLAYED_CARD 的局部顺序一致，但无整组真名预结算，且不按 concealed 跳过。 |
| P10 | 亮出事件 | `scripts/system/operations/PlayAttack.gd:90`<br>`TimePointChecker.card_revealed(attack)` | C | 同 R17 | 同一 TimePointChecker 入口；但无 RegularPlay 的 hidden 分支，若原牌暗置仍派发亮出。 |
| P11 | PLAYED_CARD | `scripts/system/operations/PlayAttack.gd:91`<br>`TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], id, attack)` | C | 同 R18 | 单张亮出后立即派发；RegularPlay 的整组是在所有牌进场后再逐张派发，不可提前。 |

## 4. 两条路径的口径矩阵

| 项目 | RegularPlay | PlayAttack | 结论 |
|---|---|---|---|
| 攻击费用（无自定义 cost） | L86–90：max(0, 当前 card._cost − 当前 card._cost_discount − 当前 d.attack_cost_discount) | L9–10/L52–58：max(0, cost.number − attack_cost_discount.number − card_cost_discount.number) | 默认数学口径一致，均叠两层折扣；不能只看注释说不一致 |
| 自定义费用 | 没有 cost 覆盖参数 | L6 可传自定义 BaseNumber；之后仍扣两层折扣 | 接口/基数口径不一致 |
| 折扣/费用对象替换 | 费用时点之后调用 cost，读取当时字段引用 | `_cost` 默认引用在 L10 捕获、两层折扣引用在 L52–53 捕获，先于 L55 时点 | 原地修改同一 BaseNumber 会被两者看到；时点直接替换这些字段为另一对象时，PlayAttack 可能仍读旧引用，不是严格等价 |
| 费用下限 | maxf(0, …)；暗置 paid=0 | final_cost<0 时置 0 | 均为 0，当前源码不是负费用漏洞；类型构造/0 计算写法不同，严格替换要保留 |
| 暗置费用/词条/亮出 | L345 暗置免费；L356–360 跳过词条/亮出，但最终仍 PLAYED_CARD | 无 hidden 参数；仍计算费用、ApplyCardKeywords、card_revealed；不主动清 concealed | 不一致；不能宣称 PlayAttack 总会变为明置 |
| 支付时机/可支付性 | 提交预检在任何整组真名预结算/费用时点之前；L346–349 实际扣费前不重新验证余额 | L55 时点后才 L62 验余额，不够 return false | 不一致：RegularPlay 时点后若成本升高/余额下降，可能负余额；PlayAttack 拒绝但费用时点已发生。禁止把补验余额伪装成不改行为 |
| 魔力上限判据 | faceup_allowed L112 费用需≤min(余额,玩家魔力上限)；预检累计模拟费用 | 只看余额≥final_cost，无对应费用≤玩家上限判据 | 不一致 |
| 免疫与零费用调用 | 免疫不扣费不记支付；非免疫且 paid>0 才调用 minus/支付工具 | 免疫不扣费不记支付；非免疫即调用 minus/支付工具，0 也调用 | 真正支付事实一致：spent≤0 均无日志；调用次数/零数值类型细节不同 |
| 扣费后的余额下限/魔力时点 | 直接 BaseNumber.minus；没有余额夹取、MAGIC_DECREASE | 同样直接 minus；没有 MAGIC_DECREASE | 一致；EditMagic 不等价 |
| 来源区移除 | L60–63 删除全部声明 play zones，再四个固定来源区，之后 append | L73 先 append，L75 只删手牌 | 不一致；不要换 DrawCardByCard 来“顺便统一”，它还会派牌区事件 |
| 入场后判定威力 | L353 append 后 L354 CardCountsPower | L73 append 后 L79 CardCountsPower | 一致：查询包含是否在 played_cards，不可移到 append 前 |
| 采用的威力值 | L354 当时读取 card._power | L12 默认先捕获 power 引用；L6 允许自定义 power | 默认同一对象原地修改时一致；替换字段对象/自定义参数时不一致 |
| concealed / activating | 两者按 hidden 显式写；setter 保留 | 只设置 activating=true，保留既有 concealed | 不一致；PA 可能“激活但仍暗置”，威力例外由同一个 CardCountsPower 决定 |
| play 日志 | L355 extra=本批额外资格；concealed 明确记录 | L84–85 extra=true，省略 concealed | 不一致，会影响 RegularPlay.played_count / _has_faceup 等历史查询 |
| 开始/完成事实 | regular_play_start 与 regular_play | 不记这两种事实 | 不一致；调用 PA 不会等价完成常规出牌 |
| 真名解放预结算 | 整组 L314–319 在首张费用时点前先解放；add 不做这一步 | 单张费用/扣费/进场/play 日志后才词条 | 不一致；同批后牌的解放条件可从费用阶段就生效 |
| 主时点顺序 | 预解放（整组）→每张 COST→入场/日志→明置关键词→明置 REVEALED；全部结束后逐张 PLAYED→完成事实 | COST→扣费/进场/日志→关键词→REVEALED→PLAYED | 局部关键词/亮出先于打出一致；整组派发边界不一致 |
| “同时打出”的范围 | 仅 PLAYED_CARD 明确延后到整批入场；COST、词条、REVEALED 仍逐张交错 | 整条链按单张同步执行 | 不要错误报告成“RegularPlay 的全部时点都等所有牌入场后才触发” |
| 延期恢复 | 保存 phase/index/finish，并在预关键词后及每阶段后检查 runtime guard | exec 内没有相同续行帧/显式 defer 检查 | 不一致；静态只能证明调用结构，不能在禁启 Godot 时声称实际暂停链已验收 |
| 常规张数口径/入口门禁 | counts 所有 extra=false 的 play；校验整组 min/max、来源、重复、战场明置、玩家/阶段 | 计数查询 attack-only；L14 的前置门禁使 L48“!ignore_limit && activating_eff==null”的数量拒绝分支在当前代码下不可达 | 不一致；PA 注释不能替代实际控制流；本审计不调整规则 |

### 4.1 用“两张牌”看出时点差异（源码顺序，不是运行记录）

- RegularPlay：`COST(1) → enter/log(1) → keywords(1) → REVEALED(1) → COST(2) → enter/log(2) → keywords(2) → REVEALED(2) → PLAYED(1) → PLAYED(2) → regular_play`。暗置牌跳过自己的 keywords/revealed；整组预真名动作还在第一项之前。
- 连续 PlayAttack：`COST(1) → enter/log(1) → keywords(1) → REVEALED(1) → PLAYED(1) → COST(2) → … → PLAYED(2)`。
- 所以不能把 RegularPlay 的整组循环改成 `for card: PlayAttack.exec(card)`，也不能用 AddAttack/AddSkill 在 enter 阶段整段替代。

## 5. “已有但不等价”候选与已使用的框架副作用

| 候选 / 路径 / 类名 | 已存在的能力 | 为什么不能直接替换被审计步骤 |
|---|---|---|
| `scripts/system/operations/EditMagic.gd` / EditMagic，L4–45 | 设/变魔力、支付记录、夹取、魔力变化时点 | 本链不夹余额也不派 MAGIC_DECREASE；该 op 会夹玩家上限/0，并在变化时派点；额外行为可引发新效果，不是单纯“换写法” |
| `scripts/system/operations/EditPower.gd` / EditPower，L4–16 | 数值变化 + PowerSources.record | 新增 power_source 事实，并根据正在激活的效果归属记录来源；可能改变按来源排除的威力查询。已有≠等价纯加法 |
| `scripts/system/operations/EditDataNumber.gd` / EditDataNumber，L8–29 | 改任意玩家 BaseNumber；只对 total_power_bonus 记来源 | 对 magic/power、min/max=null 时没有日志/时点，正常稳定映射下可用。但它会按 id 重新取得 player_data；原代码写的是本帧已捕获的 d/数字引用。要涵盖时点替换字典/数值对象的极端情况，最小方案优先传原引用给 EditNumAndReturn/SetProperty，而非自动重读 |
| `scripts/system/operations/SetCardConcealed.gd` / SetCardConcealed，L9–34 | 翻明暗、威力差分、部分亮出派发 | 本链只赋明暗字段，随后在入场后计算威力，亮出另有阶段；该 op 会差分并可能立即派点 |
| `scripts/system/operations/DrawCardByCard.gd` / DrawCardByCard，L7–29 | 搬卡并 allow_move/notify_moved | 先问替代/取消、再发牌区变化通知；原 erase/append 不做这些，还会擦除多个来源数组。不是无风险换法 |
| `scripts/system/operations/PlayedCards.gd` / PlayedCards，L4–7 | 派 PLAYED_CARD | 无 source 参数；TimePointChecker.dynamic_time_point 原调用带实际 card，源绑定效果可能失配 |
| `scripts/system/operations/EmitTimePoint.gd` / EmitTimePoint，L6–10；`scripts/system/global/game_progress.gd:635–639` | 单个字符串时点，全局或玩家动态 | 无 source 参数；不能携真实卡引用。分三次亮出派发还改一次批次为三次 |
| `scripts/system/operations/PlayAttack.gd` / PlayAttack | 单卡特殊出牌整链 | 门禁、日志 extra、来源、concealed、时点顺序、续行都不同；含多个动作，不是进入场上单一职责原语 |
| `scripts/system/operations/AddAttack.gd` / AddAttack，L13–29 | 激活、append、威力、日志、关键词、亮出、PLAYED | 不擦来源、不扣费；extra=true 且 tags 有 extra；立即派发 PLAYED_CARD，会破坏整批边界 |
| `scripts/system/operations/PlaySkill.gd` / PlaySkill，L24–62 | 技能出牌整链 | 当前费用 max(0,cost.number)，**没有扣技能卡自身 _cost_discount**，与 RegularPlay 对技能的 cost 不同；无来源删除，extra=true、立即派点；不能因注释称一致就当一致 |
| `scripts/system/operations/AddSkill.gd` / AddSkill，L12–31 | 技能入场整链 | 另有技能区魔力门槛，来源不擦除；extra=true、立即派点，与 RegularPlay 来源/免疫/批次处理不等价 |
| `scripts/system/operations/SyncPower.gd` / SyncPower，L7–18 | 重建场上牌的威力和 | 会覆盖、舍弃回合内非卡牌增量；不是本张牌的一次累加 |
| QueryLog / LogExists / SumLogData / LogFieldValues | 只读日志 | 有日志查询原语，**没有任意日志写入原语**；不能把 query 视为 record |
| `scripts/system/operations/CreateFunc.gd` / CreateFunc；ForFunc / ForeachFunc | 构造 BaseFunc；由循环框架执行效果体 | CreateFunc L4–7 只构造不执行；ForFunc L9–11 / ForeachFunc L8–10 在无 activating_eff 时不执行，且会登记循环/预算/trace 状态。不能把任意 Callable 的构造说成常规出牌下已有无副作用日志执行原语 |

### 已使用边界调用里确实含有的副作用

1. `ApplyCardKeywords.gd:24–38`：按卡的关键词调用 apply；当前 true_name_release 分支调用 `ReleaseTrueName.exec`。RegularPlay R02 是单词条提前调用，R16/PA P09 是逐卡 exec。
2. `ReleaseTrueName.gd:39–53`：推进其自身续行游标、对技能 SetCardConcealed、必要时延期；然后写 true_name_release 事实并派 TRUE_NAME_RELEASE。已经处于解放状态时 exec L19–20 返回 false。不要新增同义“真名解放 operation”。
3. `TimePointChecker.dynamic_time_point`，`scripts/system/global/time_point_checker.gd:110–131`：写 actor 的原始+self 时点、其他玩家的原始+others 时点、各 current_time_points；写带 card source 的 time_point 事实；交 EffectManager.run_time_point。这些是 R03/R18 与 P01/P11 已经代表的框架副作用。
4. `TimePointChecker.card_revealed`，同文件 L50–57，经 global_time_point L26–44：一次批次写三种亮出时点与全局日志，run_time_point(source)，并处理瞬时源事件的清理。不是简单的一个不带 source 字符串。
5. `GameLog.record_resource_payment`，`scripts/system/global/game_log.gd:108–113`：spent=max(0,before-now)，spent≤0 不写；否则仅写一条 magic_decrease，tags=[magic_spend]，data={delta,now,spent,purpose}，object=card。不额外写普通 resource_change，也不自行派魔力时点。
6. `_is_activating` setter，`scripts/system/base_handcard.gd:26–30`：true→false 时调用 AbilityRestrictions.source_deactivated。SetProperty 使用 object.set，保留 setter；绕过 setter 改内部字段并不等价。
7. `EffectManager.defer_until_runtime_guard_complete`，`scripts/system/global/effect_manager.gd:325–336`：暂停且 Callable 有效时写尾票审计、append continuation 并绑定事务；false 代表调用方继续同步，不是对局完成。故 K02/K16 留框架编排。

## 6. 最小改造：先无行为风险的已有原语，再新增

这里只提出方案，**没有改代码，也没有 Godot 运行验证**。无风险指源码副作用集合/顺序可保持，并非已跑专项绿灯。

### 第一批：已有原语，不新增 operation

按以下顺序局部替换，并始终在原位置调用：

1. **来源 erase → RemoveFromArray**：R08–R12 / P06。继续遍历原 play_zone_arrays，并保留后续四次固定 erase 的次数/顺序；不能去重这些步骤或改成 DrawCardByCard。
2. **played_cards.append → AddToArray**：R13 / P05，显式 index=-1，不添去重、移动通知或效果登记。
3. **卡属性赋值 → SetProperty**：R06/R07 / P04。分别写 concealed 与 activating；不改原值，不强迫 PA 翻明，不改 setter 行为。
4. **非零原地扣费 → EditNumAndReturn**：R04 保留 `!d.is_magic_immune and paid>0`；PA P02 保留 !immune，且 final_cost=0 的分支需原写或以下完整纯数值组合。支付事实仍在同位置读实际前后余额，第一批不改 GameLog 调用。
5. **纯威力累加 → 既有纯数值原语组合**：始终保留 `CardCountsPower.exec` 在 append 后。非零增量可 `EditNumAndReturn.exec(原 power 引用, 原增量引用)`；若要求严格覆盖零值类型，用 SetProperty + can_change 的同语义组合，见下。
6. **已调用的 CardCountsPower、ApplyCardKeywords 不重复改造**。R02 直接 .apply 已有词条派发；无需新增词条/入场大 op。续行帧写虽可 SetDictionaryValue，最小方案**不改状态机**。

完整纯加法的已有组合（建议片段，不是已执行代码）：

```gdscript
# 保持当前捕获的 BaseNumber 引用；只做原 BaseNumber.add 的数字写入。
# BaseNumber.add 的原实现为 !can_change 时返回，否则 number += num.number。
if target.can_change:
	SetProperty.new().exec(target, "number", target.number + increment.number)
```

- 原码证据：`scripts/system/base_number.gd:38–50`；SetProperty L6–13 不记日志/派点。该组合不改 BaseNumber 对象身份，也不额外更新 is_float（原 add 同样不更新）。
- `EditNumAndReturn.gd:8` 会跳过 add.number==0；BaseNumber.add 即使增量为浮点零也执行 `+=`。只要求数值相等时通常无差异，但“不得改行为”的审计不能自动抹掉数值类型这一边界，所以提供完整组合或保留零值原写。PA 的零扣费可对原 pl_magic 用相同组合，表达式改为 `target.number - final_cost`。
- 不推荐为了看起来语义更漂亮而直接用 EditPower（新增 power_source）或 EditMagic（夹余额/派时点）。这两项属于**已有 operation 但不等价**，不是根本不存在。

### 第二批：新增最少一个事实写入原语

1. **新增 N1 RecordLog**，只转发 GameLog.record；无费用、无区域修改、无时点、无自动玩家 id 解析。替换 R01/R15/R19/R20/R21 与 PA P08，只搬原参数，保持原去重/完成门禁在调用方。
2. **支付事实不必再新增 N2**：有 N1 后，复用 CalculateNumber 算 before-now/max，再保留 spent>0 条件，构造原标量 data 调 N1，便能复现 R05/P03。也可第一轮继续调用既有 GameLog.record_resource_payment，避免复制标准 payload。
3. 只有确实需要“直接包装支付工具、不在调用方重复标准结构”的接口时再考虑 N2；它是可选便利封装，不是组合能力卡住后的必需原语。**不把 N1+N2 同时列为最小必做新增，遵守先组合再新增。**
4. 时点 source/批次、phase/index、guard/defer、finish 留原位；不新增 PlayCard/EnterPlayedCard 这种揉合费用、搬牌、威力、日志、关键词、时点的大 operation。

### 不能混进“无行为改动”的事项

统一来源区擦除、强迫 PA 明置、改变 extra/concealed 日志、统一自定义 cost/power、补扣费后余额检查、补 MAGIC_DECREASE、把 per-card REVEALED 延到整批后、修复 PlaySkill 折扣、改 PA 数量门禁、改暂停恢复行为都需要单独规则/接口裁定，**不属于本次原语替换**。

## 7. B 类建议的单一职责签名与最小组合

### N1：RecordLog（最小必需新增）

建议路径 `scripts/system/operations/RecordLog.gd`，类名 `RecordLog`，注册 func_name `record_log`。

```gdscript
func exec(type:String, actor:int = -1, target:int = -1,
		place:String = "", object = null, tags:Array = [],
		params:Dictionary = {}) -> Dictionary:
	return GameLog.record(type, actor, target, place, object, tags, params)
```

单一职责：**记录一条调用方声明的事实**。直接使用现有 GameLog 规范化/上下文/观察者链，不能对 `_journal` 用 AddToArray 伪造日志；那会绕过 _freeze、事件上下文及事实观察链。actor/target 的 -1 是合法日志语义，不自动 resolve 到当前效果玩家。

### N2：RecordResourcePayment（可选，最小方案不要求）

建议路径 `scripts/system/operations/RecordResourcePayment.gd`，类名 `RecordResourcePayment`，注册 func_name `record_resource_payment`。

```gdscript
func exec(prefix:String, player_id:int, before, now,
		purpose:String, source = null):
	return GameLog.record_resource_payment(prefix, player_id, before, now, purpose, source)
```

单一职责：**以现有标准结构记录真实支付事实**。不扣资源、不检查余额、不夹取、不派时点、不替调用方判断免疫。当前此接口仅为 GameLog 静态方法，并没有注册 operation。

### 新 N1 + 已有原语为何足以替代 N2

```gdscript
var difference = CalculateNumber.new().exec(before, "-", now)
var spent = CalculateNumber.new().exec(0, "max", difference).number
if spent > 0:
	RecordLog.new().exec("magic_decrease", id, -1, "", card, ["magic_spend"],
		{"delta": -spent, "now": now, "spent": spent, "purpose": purpose})
```

CalculateNumber 路径 `scripts/system/operations/CalculateNumber.gd`，类名 CalculateNumber；L7 参数接受普通数字/BaseNumber，L15–16 实现减法、L29–30 实现 max。条件与标量构造仍由调用方传入；效果描述可用 CompareNumber/IfFunc 控制该条执行，不把支付意图塞进扣数 operation。`prefix` 如需通用也由调用方提供，不把 magic 固定进新日志原语。以上为**源码可组合方案，未运行验证**。

若未来实施新增，除注册 AllOperations.TABLE 外，应按项目契约同步 `json_maker/types.json`；本审计没有写这些文件。

## 8. 证据、限制与验收

- 已重新读取 hermesWarning.txt、CLAUDE.md，并加载 fate-domination-engine 及 compose-before-add/effect-engine-rules 参考；报告按源码优先，不将旧技能注释当当前行为。
- 真实只读命令：`git status --short`、`git rev-parse HEAD`，退出码 0；工作树已有大量非本次修改。
- 真实只读 inventory：Python 扫描 AllOperations.TABLE 每项 func_name/class，与 operations/*.gd 的文件名/class_name/exec 和副作用站点核对，退出码 0；结果为 214/214，一一对应。
- 阅读 RegularPlay 全 418 行、PlayAttack 全 92 行；阅读全部注册项及候选原语 exec、BaseNumber、BaseHandCard、PlayRules、GameLog、TimePointChecker、PowerSources、guard/defer 相关函数。
- 新增建议均未落生产源码；**没有 Godot 解析/类型检查、实际费用/时点/暂停恢复测试**，也未验证 UI。不能把静态等价候选当作已通过引擎回归。
- 交付前再次用 Python SHA-256 对比 RegularPlay、AllOperations 注册表与全部 214 个 operation 文件，共 216 个：变化 0、新增 0、删除 0，命令退出码 0。计数用程序汇总，不手算。报告是本审计唯一写入产物。
