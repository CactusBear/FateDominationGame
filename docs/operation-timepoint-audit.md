# Operation 与时点静态审计合成文档

## 0. 引用、范围与验收边界

本文件仅将三份既有审计带入仓库并汇总，不重新裁定规则、不实施改造。原报告按字节原样复制；正文中的数字、分类和结论沿用各报告各自口径，**三份报告的 A/B/C 不是同一种计数单位，禁止相加**。

| 引用 | 仓库内原报告 | 原始来源 | 重点定位 |
|---|---|---|---|
| [1] | [RegularPlay 原报告](audit/regular-play-ops-report.md) | `E:/scratch/audit-regular-play-ops/report.md` | §1 计数；§2 R01–R21；§4 对照矩阵；§6–7 最小方案；§8 未验 |
| [2] | [时点原报告](audit/timepoints-report.md) | `E:/scratch/audit-timepoints/report.md` | 摘要；§1.2 空心影响；§3.1–3.3 B 类；§4 占位效果；§4.1 contribution；§5 unknown |
| [3] | [绕过注册表原报告](audit/bypass-registry-report.md) | `E:/scratch/audit-bypass-registry/report.md` | §1 三档口径；§4 B 类；§6 contribution；开头及§9 边界 |

RegularPlay/时点报告记录 HEAD `8c0f946faf6cc0cd3f04f12f66f5a99a413088ca`；三份都以当时读取的**当前工作树**而非冻结提交为证据。工作树原有修改不能归因于本次审计，源码行号也是报告读取时的定位，不保证后续源码更新后仍对应。[1][2][3]

**统一验收声明：三份审计及本次整理均未启动 Godot；运行验收为 unknown。** 本次只验证文档字节复制、数字转录、引用及 SHA256，不将静态入口存在、静态等价候选、注册完整性写成运行通过。不改生产/测试/数据文件，不操作 PID 17120/28100。[1][2][3]

## 1. RegularPlay：直写、已有 operation 与最小缺口

### 1.1 关键计数

以下按静态写入站点计数，不按实际出牌张数计数；续行/编排帧单列，不混入规则状态表。[1]

| 范围 | 总行数 | A：已有等价原语/组合 | B：缺等价能力 | C：保留内联 |
|---|---:|---:|---:|---:|
| RegularPlay 规则状态/外部副作用 R01–R21 | 21 | 12 | 6 | 3 |
| 另列续行/编排帧 K01–K19 | 19 | 12 | 0 | 7 |
| 连帧合计（原报告另列口径） | 40 | 24 | 6 | 10 |
| PlayAttack 对照 P01–P11 | 11 | 6 | 2 | 3 |

| 规则状态表中的细分 | 原报告数量/结论 |
|---|---|
| A 已有等价原语但未用 | 10 行 |
| A 已使用 | 2 行（R02/R16）；R14 内的 `CardCountsPower` 查询也已使用 |
| B 按能力去重 | 2 类：任意事实记录；无资源改写/无时点的支付事实记录 |
| 最小必需新增 | **仅 1 个 operation：`RecordLog`** |
| `RecordResourcePayment` | 可选便利封装，不是必需第二个新增 |

RegularPlay 是“直接规则状态写入 + 部分已有 operation + 时点/续行框架”的混合编排，已使用 `CardCountsPower`、`ApplyCardKeywords`、`PlayerBuffsHaveEffect`，不能说完全没有使用 operation。已有 `RemoveFromArray`、`AddToArray`、`SetProperty`、纯数值原语可以承接部分直写；支付事实可在新增 `RecordLog` 后由已有算术/条件原语组合，不需要把 N1+N2 都列为最小必做。[1]

C=3 是费用计算派发、亮出派发、整批入场后的 `PLAYED_CARD` 派发。必须保留 source、批次、phase/index 与续行边界；“必须内联”是保留当前语义的最小改造约束，**不是技术上永远不能包装**。`EditMagic` 会夹取/派魔力时点、`EditPower` 会新增来源事实，不能当成等价纯扣费/累加。[1]

### 1.2 与 PlayAttack 一致与不一致

| 对照项 | 结论 | 必须保留的限定 |
|---|---|---|
| 折扣公式 | 一致 | 默认攻击费用、无自定义 cost 时，都叠加牌自身折扣与玩家攻击折扣；对象引用替换/自定义参数不保证等价 |
| 费用下限 | 一致：0 | RegularPlay 的 `maxf(0, …)` 与 PlayAttack 的负值归零同为下限 0；暗置与零值调用/类型细节不同 |
| 入场后判威力 | 一致 | 都先 append 再 `CardCountsPower`；采用的 power 引用/自定义值仍有差异 |
| 来源移除 | 不一致 | RegularPlay 先擦全部声明 play zones 与四个固定来源，再 append；PlayAttack 先 append，只删手牌 |
| 日志字段 | 不一致 | RegularPlay 记录本批 extra 与 concealed；PlayAttack 固定 extra=true、省略 concealed，也不记 regular_play_start/regular_play 完成事实 |
| 整批时点顺序 | 不一致 | RegularPlay 仅将 `PLAYED_CARD` 延后到全部入场；费用、词条、亮出仍逐张交错。连续 PlayAttack 会在下一张入场前派上一张 `PLAYED_CARD` |

该表摘录原报告§4，并非全部差异：暗置、支付时机/余额复核、上限判据、真名预结算、门禁、自定义参数和暂停恢复也有不一致。不能用 `for card: PlayAttack.exec(card)` 等整链替换声称不改行为；补扣费余额复核属于另行裁定，不混入机械原语替换。[1]

### 1.3 原报告“未验”声明

原报告§6原文：

> 这里只提出方案，**没有改代码，也没有 Godot 运行验证**。无风险指源码副作用集合/顺序可保持，并非已跑专项绿灯。

原报告§8原文：

> 新增建议均未落生产源码；**没有 Godot 解析/类型检查、实际费用/时点/暂停恢复测试**，也未验证 UI。不能把静态等价候选当作已通过引擎回归。

因此本节运行验收：**unknown**；静态组合方案不等于已经实施或运行通过。[1]

## 2. 时点：派发空心声明与硬编码处理块

### 2.1 关键计数与结论

| 项目 | 原报告计数 | 口径 |
|---|---:|---|
| 真正时点常量 | 218 | 不含 SELF_PREFIX/OTHERS_PREFIX 两个辅助字符串；原始字符串常量 220 |
| 有生产派发/持续窗口入口 | 168 | 源码入口存在，不声称实际运行触发 |
| 无当前生产派发（空心声明） | 50 | 泛型 EmitTimePoint 可接字符串不能补齐具体入口 |
| 静态映射 unknown | 0 | **不代表运行 unknown=0** |
| B 类处理职责块（宽口径） | 29 | 非卡牌数、非常量引用次数 |
| B：可改 operation+数据 | 14 | 动作或固定生命周期策略 |
| B：必须保留运行时 | 15 | 派发/匹配/执行基础设施 |
| 狭义特定命名时点消费者 | 5 | B01/B18/B21/B22/B23；仅 B01 是业务到期副作用，其余 4 条为引擎语义 |
| 正式 JSON / 效果对象 | 71 / 135 | 含 1 条 build_effect 参数内嵌效果 |
| 有 time_points 的效果 | 105 | 自动 77；手动窗口 28 |
| 普通时点执行描述 | 1042 | 全部注册且有对应 exec 文件；未注册 0 |
| 受空心派发影响效果 | 4 | 3 条监听无入口；1 条延迟目标无入口 |
| 仅 do_nothing 的效果 | 2 | 注册占位，不算功能实现 |

B02–B14 等扩展块包括生命周期邻接动作；源码调度固定不等于动作本身没有 operation。B15–B29 是派发、匹配、执行和续行时序本身，不应把它们误当某张卡收益写死；已委托 operation 的子动作仍归 A。105 条执行描述已接线也不能推出 105 条均正确可用。[2]

### 2.2 B 类文件分布（原报告§3.3）

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

狭义分布另为 `time_point_checker.gd` 2 块（B01/B18）、`effect_manager.gd` 3 块（B21/B22/B23），不与宽口径合计混算。[2]

### 2.3 4 条受空心派发影响的效果（原报告§1.2）

| 效果 | 精确数据位置 | 空心时点 / 影响 |
|---|---|---|
| 美狄亚 `base_construction_deploy_workshop_gain` | `data/servants/00005_medea/00005_medea.json#/specials/SKILLS/0/effects/1` | `self_deploy`：普通生产路径没有监听入口 |
| 远坂凛 `placeholder_absolute_order_penalty` | `data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json#/effects/2` | `self_battle_phase_end`：普通生产路径没有监听入口 |
| 葛木 `outsider_battle_phase_score_gain` | `data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json#/effects/3` | `self_battle_phase_end`：普通生产路径没有监听入口 |
| 美杜莎 `petrification_defeat_if_no_magic_attack` | `data/servants/00004_medusa/00004_medusa.json#/specials/SKILLS/2/effects/0/funcs/0` | 初始 `self_action_phase` 有入口；延迟目标 `self_battle_phase_start` 无入口，day_end 过期只会注销 |

四条都有 operation 体；缺的是监听或延迟目标的生产派发，不是拿未注册函数代替执行体。[2]

### 2.4 2 条仅 do_nothing（原报告§4）

| 效果 | 精确数据位置 | 时点 | 静态结论 |
|---|---|---|---|
| `mooncancer_passive_grail_events` | `data/attacks/class/mooncancer_class/mooncancer_class.json#/effects/0` | `game` | 仅 `do_nothing`，注册占位，未实现 |
| `mooncancer_event_swap` | `data/attacks/class/mooncancer_class/mooncancer_class.json#/effects/1` | `self_action_phase` | 仅 `do_nothing`，注册占位，未实现 |

这两条不是“空心派发影响的 4 条”中的条目，不将注册占位写成已实现。[2]

### 2.5 原报告 unknown 声明

原报告“范围、证据强度与只读约束”原文：

> 静态查证可断言入口存在/缺失；引擎解析、真实可达性、逐卡运行结果、用户自选外部数据、网络实战：**unknown（本轮禁止启动 Godot，未运行）**。不可据本报告宣称 105 条效果均正确可用。

原报告§5原文：

> 只改本报告；没有仓库改动，没有测试/引擎启动，没有 PID 操作。未确认的数据文案正确性、卡状态条件、前缀业务是否应新增、抽象后的 operation 设计及任何真实运行结果均为 **unknown**。

此外，原报告明确“未人工逐句解释 419 个文件的全部无关逻辑；文本扫描≠全部语义覆盖”。本节运行验收仍为 **unknown**，不是静态映射 unknown=0 的延伸。[2]

## 3. 绕过注册表：代码直连类与查询 DSL

### 3.1 关键计数与口径

| 范围 | A 已注册仍有代码直连 | B 未注册效果/规则承载类 | C 工具/查询类 | 合计 |
|---|---:|---:|---:|---:|
| `Xxx.new().exec/apply(...)` 字面生产调用 | 28 | 3 | 19 | 50 |
| 补实例变量、其他入口、贡献求值器及构造型规则载荷后的总清单 | **28** | **9** | **37** | **74** |

| 其他关键计数 | 原报告值 |
|---|---:|
| 全树 GDScript 扫描（含 ignore 的测试/历史副本） | 1808 |
| 正式 JSON / 解析错误 | 71 / 0 |
| AllOperations.TABLE 注册项 | 214，func_name↔class 无重复 |
| 生产字面调用次数 | 143，去重为 50 类 |
| BoardPowerQuery.READERS | 18 项；其中 3 项已有命中，新增去重 15 类纳入 C |
| contribution 描述 | 19 条 |

“绕过注册表”指不经 TABLE 取类的代码直连，**不是绕过唯一运行派发器**：TABLE 分类只供查阅；普通 LoadHelper 也按 func_name 转类名、动态加载 operation 文件，再取得 exec。C 优先于 A，纯查询/通用构造/洗牌工具即使已注册也不冒充效果执行类；`ShuffleArray` 有就地数组副作用，不能称 C 全部纯只读。[3]

### 3.2 B 类类名清单（原报告§1/§4）

1. `BattleResolver`
2. `BoardPowerQuery`
3. `CannotPlayCardsEffect`
4. `ClimaxResolver`
5. `DefeatBuff`
6. `EventResolver`
7. `ExcludedFromBattleWinEffect`
8. `SituationResolver`
9. `VictoryResolver`

总数为 9 类。`EventResolver`/`SituationResolver` 有 new 后调用其他公开入口；`CannotPlayCardsEffect`/`ExcludedFromBattleWinEffect` 是无独立 exec/apply 的构造型持续规则标记，不能冒充字面 new().exec 命中。`Defeat`/`RemoveDefeat` 本身已有注册包装器，但被直连的 `DefeatBuff` 类身份仍归 B，不代表败北规则完全没有注册入口。[3]

### 3.3 19 条 contribution：内联解释器承载，**不涉时点**

| descriptor | 条数 | 承载位置（报告源码行号） |
|---|---:|---|
| `power_contribution` | 5 | `scripts/system/global/board_power_query.gd:125–127` |
| `attack_power_contribution` | 13 | `scripts/system/global/board_power_query.gd:128–146` |
| `card_power_contribution` | 1 | `scripts/system/global/board_power_query.gd:147–156` |
| 合计 | 19 | `BoardPowerQuery.evaluate_one` 内联解释分支 |

两份报告均确认这 19 条位于 power_query，真实承载者是 `BoardPowerQuery` 的内联解释器，不是 `*Contribution.new().exec`。时点报告进一步明确所属 19 条效果 `time_points=[]`，不比较 TimePoints、不走 run_time_point；它们是数据驱动、非 operation 的只读查询 DSL，**不涉时点、不计入时点 B=29**。查询仅写局部 variables/contribution/card_values，不改真实卡或玩家 power，不激活效果或记录日志；战斗和 UI 预览读取其结果。[2][3]

时点报告原计数为：全部 func_name 1182；普通时点执行描述 1042 + power_query 描述 140；已注册 1163 + 未注册 contribution 19。不能说 19 个同名 power_contribution，也不能说 19 条时点效果未注册。[2][3]

### 3.4 原报告“未验”声明

原报告开头原文：

> 只写本报告；未启动 Godot，未向 PID 17120/28100 发任何操作；结论是源码/数据静态证据，不冒充运行验收。

原报告§9说明这是限定范围的类清单，不纳入通用 BaseNumber/BaseCard/BaseEffect 构造、UI、Crypto、网络/日志基础设施与 AI 策略；报告不包含改代码建议。它没有声称引擎测试通过，本节运行验收显式记为 **unknown**。[3]

## 4. 跨报告核对与冲突项

### 4.1 冲突：全树 GDScript 扫描总数不一致，未裁定

并列原文，不取其中一个数字替代另一个：

**时点报告“范围、证据强度与只读约束”（原报告第13行）：**[2]

> 仓库全树 1800 个 .gd 另做时点符号筛选；tests/newtests、reports 快照、.claude/worktrees 不是当前生产派发源，不能用测试人工派发补齐空心声明。UI 日志格式化、网络/大厅 phase、动作名 move/deploy、GameLog.record 的 type/tags 与时点同名但并非事件派发，已排除。

**绕过注册表报告开头（原报告第5行）：**[3]

> 扫描 GDScript 源文件 **1808** 个（包括被 ignore 的测试及历史副本），正式 `data/**/*.json` **71** 个，解析错误 **0**；`AllOperations.TABLE` **214** 项，func_name↔class 无重复。

**状态：冲突/未统一（1800 vs 1808）。** 绕过报告§9另记“扫描期间新增测试文件已纳入排除区复扫”，但没有共同冻结版本与逐文件差集证据，不能据此自行解释或消除差额；本次不重扫裁定，原报告数字均保留。[2][3]

### 4.2 不同口径不能误报为数字矛盾

- RegularPlay A/B/C 是写入站点/编排帧；时点 B 是处理职责块；绕过 A/B/C 是去重类。RegularPlay B=6、时点 B=29、绕过 B=9 并非同一集合，不能合并或选一个覆盖另一个。[1][2][3]
- RegularPlay 报告的“PlayAttack 自身是注册 operation，但内部有直写”与时点报告 B13 的“不走 play_attack/play_skill 的 operation 动作”不否定 RegularPlay 已调用查询与关键词 operation。[1][2]
- 两份报告 contribution 都是 19 条，三种描述符分别 5/13/1，且不涉时点；不存在将绕过 B 类中的 BoardPowerQuery 再计入时点 B=29 的依据。[2][3]
- 三份注册目录均为 214 项，时点/绕过报告正式 JSON 均为 71 个。上述关键数值一致；全树扫描数冲突保持未裁定。[1][2][3]

## 5. 归档完整性与本次可验证范围

| 新增原报告文件 | SHA256（原始来源与仓库副本相同） |
|---|---|
| `docs/audit/regular-play-ops-report.md` | `a88727300a59520ef23051dcd6fc5a3cb90eb88e92bef490fe2700f4326962f7` |
| `docs/audit/timepoints-report.md` | `3f7b1ebc93fa8212bbff26177843ef8bac4a19d729c28c7a7b800a48711f9698` |
| `docs/audit/bypass-registry-report.md` | `7aa70cae8f912376c3611746b3088dfa91588e2ee67ccf7a00441e512f655168` |

合成文档路径：`docs/operation-timepoint-audit.md`。本文件自身 SHA256 在交付回执中另列，避免自引用哈希。本次可验证范围仅为原样复制、计数/清单转录、文件引用与工作树文档增量；**Godot 解析、运行、暂停恢复、逐卡和 UI/网络验收全部 unknown**。

## Sources

[1] audit/regular-play-ops-report.md — 常规出牌 operation 组合审计：逐步骤对照
[2] audit/timepoints-report.md — 时点效果与 operation 实现只读盘点
[3] audit/bypass-registry-report.md — Operation 注册目录绕过：直接实例化效果/规则类只读清单
