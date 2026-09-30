# FSN 从者/御主 缺陷清单（探针实测）

## 阅读结论

这次核对了 7 名从者、7 名御主的技能与御主能力，方式是**逐条比对「卡面原文 → JSON 声明 → 引擎实际行为」**，并用临时探针走真实入口复现。

- 基线：`tests/*_test.tscn` 全量 53 个套件**全部通过**（0 失败、0 脚本错误）。也就是说，下面这些缺陷**都没有被现有回归覆盖**。
- 已复现 6 类、共 12 个具体触发点。全部集中在三个根因上：**buff 激活状态没人检查**、**「每回合一次」只靠数据声明而漏了几张牌**、**`is_pure_passive` 默认不需要牌处于激活状态**。
- 另有 3 条是静态可判、没跑的，单独列在第二档，标明缺什么证据。
- 第三档是 `do_nothing` 占位，属于「未实现」，和 bug 分开列。

本文行号是本次工作树快照（HEAD = `c46445f`，工作区有未提交改动）。

---

## 一、已复现的缺陷

### 1. buff 未激活时，它身上的效果照样结算

**位置**

| 角色 | 卡面 | 效果声明 |
|---|---|---|
| 言峰绮礼 | 执行者：战斗阶段你的总威力+2 | `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json:407`（buff 在 `:396`） |
| 伊莉雅斯菲尔 | 天之衣：归于虚无（回合开始时给 2 战果） | `data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json:342`（buff 在 `:331`） |
| 间桐樱 | 黑泥（准备阶段花 2 魔力换 2 战果） | `data/masters/00004_matou_sakura/00004_matou_sakura.json:513`（buff 在 `:502`） |
| 间桐樱 | 被污染的圣杯（无限魔力、常规攻击多打一张） | `data/masters/00004_matou_sakura/00004_matou_sakura.json:614`、`:624`（buff 在 `:603`） |

引擎侧：`assets/scripts/system/global/effect_manager.gd:866` `card_state_allows()` 只检查了「所属卡牌是否已激活」（`BaseHandCard._is_activating`，第 878 行），**没有检查 `BaseBuff._is_active`**。

数据侧：这 4 个 buff 在 JSON 里都是 `"is_active": false` 挂上去的，等条件满足才由效果 `set_property(..., "_is_active", true)` 点亮：

- 执行者：真名隐藏时为监督者，执行者应**未激活**
- 天之衣：第八回合开始时才激活
- 黑泥：回合结束时战果低于所有其他玩家才激活
- 被污染的圣杯：第八回合结束时战果排名不为第一才激活

**现象（探针实测）**

```
REPRODUCED A_kirei_executor_inactive_still_applies | executor.active=false bonus 0->2
REPRODUCED B_illya_heavenly_robe_inactive_scores | robe.active=false score 0->2 (round2)
```

- A：言峰真名隐藏（默认状态），执行者 buff 未激活，派发战斗阶段时点后总威力 0→2。**未激活的能力生效了。**
- B：第 2 回合（天之衣要到第 8 回合才激活），战斗阶段发生过有淘汰玩家的战斗后派发回合开始时点，战果 0→2。

**机制**

`register_effect` 只认效果的归属对象，不认 buff 的激活状态；`_is_active` 目前只被 `PlayerBuffsHaveEffect`、`BoardHasEffect`、`MapAreaHasEffect`、`DefeatBuff` 这几个「查询类」入口读取。凡是挂在效果池里自动触发的 buff 效果（本表 4 个），全部绕过了激活状态。

**建议修法**

在 `card_state_allows()` 里补一条：来源对象是 `BaseBuff` 且 `!_is_active` 时返回 false。这与上述三个查询类入口的口径一致，不新增 operation、不改数据。

需要注意影响面：全局只有 5 个 `is_active:false` 的 buff（上面 4 个 + 樱的「腐蚀」占位），其余 buff（宝石、伪臣之书、局外人）都是 `is_active:true`，不受影响。

---

### 2. 「每回合一次」缺失：同一回合可以反复发动阶段能力

**规则依据**：基础规则「能力的使用限制以及持续时间」——印刷于同一张牌上的、带有阶段的能力**每回合仅可被使用一次**。项目里已有的正确写法是「单选项 + `max_total_uses: 1` + `reset_counts_each_round: true`」，例如阿尔托莉雅的三张技能牌（`data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json:54`、`:285`、`:415`、`:496`）。

**位置**（都是 `is_manual: true`、没有 options、也没有 `max_total_uses`）

| 卡牌 | 效果 | 位置 |
|---|---|---|
| 炽天覆七重圆环 | 将同战场对手的迅捷攻击威力变为 0 | `data/servants/00002_emiya/00002_emiya.json:30` |
| 伪·螺旋剑 | 战斗阶段：若赢得战斗，获得 4 战果 | `data/servants/00002_emiya/00002_emiya.json:172` |
| 穿刺死棘之枪 | 贯穿心脏：仅一名对手时令其【败北】 | `data/servants/00003_cu_chulainn/00003_cu_chulainn.json:355` |
| 神言魔术式 | 战斗阶段：失败则回收被移除的【万符必应破戒】 | `data/servants/00005_medea/00005_medea.json:404` |
| 幸运（基本牌） | 战斗阶段：你本回合无视【直接败北】 | `data/attacks/basic/luck/luck.json:21` |
| 必胜黄金之剑（升华技） | 战斗阶段：此攻击在高潮回合威力+4 | `data/masters/00001_emiya_shirou/00001_emiya_shirou.json:184` |

引擎侧：`assets/scripts/system/global/load_helper.gd:173` —— `max_total_uses` / `reset_counts_each_round` **只在 JSON 里存在 `options` 时才加载**（第 170 行的 `if eff.has("options")` 分支内）。没有 options 的手动效果，这两个字段恒为默认值 `-1 / false`，等于不限制。而 `EffectManager.request_manual_activation()`（`assets/scripts/system/global/effect_manager.gd:1480`）每次会 `resolved_effects.erase(effect)`，所以同回合能反复点。

**现象（探针实测）**

```
REPRODUCED C_repeatable_zero_opponent_agility_power                   | first=true can_again=true
REPRODUCED C_repeatable_placeholder_pierce_heart_single_opponent_defeat | first=true can_again=true
REPRODUCED C_repeatable_battle_win_score_gain                          | first=true can_again=true
REPRODUCED C_repeatable_divine_words_retrieve_rule_breaker             | first=true can_again=true
REPRODUCED D_luck_repeatable                                           | first=true again=true
REPRODUCED J_caliburn_repeatable                                       | first=true again=true
```

其中**七重圆环**最危险：`ZeroAttributePower`（`assets/scripts/system/operations/ZeroAttributePower.gd`）的实现是「把该属性攻击的威力从合计威力里扣掉」，重复发动会**重复扣减**，威力会变成负数。

**建议修法（只改数据，用现有写法组合）**

把这 6 条改成与阿尔托莉雅技能牌同构的写法：一层单选项包住原来的 funcs，效果上加 `max_total_uses: 1` + `reset_counts_each_round: true`。不改 operation、不加新字段。

注意**例外情况**，不要一刀切：

- 「万符必应破戒」已经声明了 `once_per_game: true`，是「每局限一次」，不需要再叠每回合一次。
- 「一之太刀」的关闭交战玩家攻击那条（`data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json:141`）没有每回合限制，但它结束时**会关闭自己**，牌一旦离开激活状态就无法再发动，属于「靠状态自锁」而非「靠计数」。**这一条要不要一起改需要先确认**（见第二档第 3 条）。

---

### 3. `is_pure_passive` 效果没写 `need_activate`，牌留在技能区也会生效

**规则依据**：「打出时：」「残留：」和无任何前缀的文本，都等同于此牌**激活后**必须遵循的被动能力（基础规则「能力卡牌」一节）。技能牌上的这类能力应当要求牌已激活。

引擎侧默认值：`assets/scripts/system/global/load_helper.gd:139` —— `need_activate` 未声明时默认 `not is_pure_passive`。也就是**纯被动效果默认不需要激活**。这是为「被动：」类常驻能力设计的默认值，但被这三处误用了。

**位置**

| 卡牌 | 效果 | 卡面 | 位置 |
|---|---|---|---|
| 阵地建造 | 残留：部署于魔术工房时 +1 魔力 +2 战果 | 带「残留：」前缀，需要激活 | `data/servants/00005_medea/00005_medea.json:104` |
| 三之太刀 | 燕返：若【一之太刀】【二之太刀】同时在战场，则【真名解放】并合计威力+3 | 无前缀文本，需要激活 | `data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json:331` |
| 骑乘 | 打出时：若此牌与一张基础攻击一同打出，抽一张牌 | 带「打出时：」前缀 | `data/servants/00004_medusa/00004_medusa.json:30` |

**现象（探针实测，前置条件都是「技能卡留在技能区、未打出、未激活」，效果按真实发牌路径 `RegisterObjectEffects` 登记）**

```
REPRODUCED G_base_construction_unplayed_triggers | activating=false magic 10->11 score 0->2
REPRODUCED H_swallow_reversal_without_san_played | san.activating=false bonus 0->3 released=true
REPRODUCED I_riding_unplayed_draws               | riding.activating=false hand after play 0 -> after PLAYED_CARD 1
```

- G：阵地建造没打出，只要部署到魔术工房就白得 1 魔力 2 战果。
- H：三之太刀没打出，光是一之/二之在场，就真名解放并合计威力+3。
- I：骑乘没打出，打出任意卡牌时仍触发抽牌。

**机制（三处不完全相同，修法也不同）**

- G、H：纯粹是缺 `need_activate: true`。
- I 还有第二个问题：骑乘的 `riding_draw_with_basic_attack` **没有 `source_bound`**。`assets/scripts/system/global/effect_manager.gd:814` 只在 `_source_bound` 为真时才要求「触发来源就是自己」，所以它是**任何** `self_played_card` 都会命中，而不是「此牌与基础攻击一同打出」。修法要同时补 `need_activate: true` 和 `source_bound: true`，靠 `source_bound` 把触发限定在自己打出那一刻，再靠 `LogFieldValues` 查本回合是否还打出了基础攻击。
  - 另外这个「一同打出」的判断目前是查日志里本回合打出过的 attack 数量 ≥ 1，**不区分先后顺序**（先打基础攻击再打骑乘也会触发）。卡面「一同打出」是否要求同一批提交，**需要你确认口径**。

---

### 4. 必胜黄金之剑改了卡面威力，不还原

**位置**：`data/masters/00001_emiya_shirou/00001_emiya_shirou.json:184`（效果 `combat`），第 207 行用了 `edit_card_power`。

**卡面**：「战斗阶段：此攻击在高潮回合威力+4」——只应影响本回合。

**引擎侧对照**：同文件 `data/masters/00001_emiya_shirou/00001_emiya_shirou.json:152` 的「被动 - 你的力量和敏捷属性的基本牌威力+2」也用了 `modify_attack_power_by_attribute`；`assets/scripts/system/operations/EditCardPower.gd` 的注释写明「改威力前先记下这张牌原本贡献了多少，改完按同一判定入口重新贡献一次」——它是**永久改写卡面威力**。而阿尔托莉雅「誓约胜利之剑」的同类效果用的是 `edit_power`（回合结束由 `SyncPower` 还原）。

**现象（探针实测）**

```
REPRODUCED J_caliburn_repeatable                    | first=true again=true
REPRODUCED J2_caliburn_printed_power_not_restored   | printed 8 -> after use 12 -> after round cleanup 12
```

卡面威力 8 用一次变 12，回合清理（`DiscardPlayedCards`）后**仍是 12**；配合上面第 2 条，同一回合还能反复点。

**建议修法**：把 `edit_card_power` 换成 `edit_power`（本回合合计威力 +4，回合结束由 `SyncPower` 还原），与誓约胜利之剑同一写法。同时补第 2 条的每回合一次。

**待确认**：这张牌的 `require_all_time_points: true`（第 221 行）要求「战斗阶段 + 高潮」同时成立，这个口径与卡面一致；但「被动」那条（第 152 行）用的是 `self_card_revealed`，即**这张牌亮出的瞬间**给所有力量/敏捷基本牌 +2，与卡面「你的力量和敏捷属性的基本牌威力+2」是否为常驻，同样建议一并确认（本次未探测）。

---

### 5. 远坂凛的令咒罚则没有限定回合

**位置**：`data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json:196`（`placeholder_absolute_order_penalty`）。

**卡面**（3.1 版）：「绝对服从的命令-你必须于第一回合使用一枚令咒。**若你以该令咒获得了魔力**，战斗阶段结束后，你失去4点魔力。」处罚对象是**第一回合那枚**令咒。

**现状**：效果体是 `LogExists.new().exec(-1, {"tags": ["command_spell_gain_magic"]}, 0)` —— `round_offset = 0` 表示只看本回合，**没有判断是不是第 1 回合**。

**现象（探针实测，走真实令咒入口取「获得4魔力」选项）**

```
REPRODUCED K_rin_penalty_outside_round1 | used=true round2 magic after cs 12 -> after battle end 8
```

第 2 回合用令咒获得魔力，战斗阶段结束后照样 -4。

**建议修法**：加一个「是否第 1 回合」的判断，用现有的 `get_current_round`（`func_name`）+ `if_func` 组合，不需要新 operation。第一回合以外不扣。

**待确认**：这张牌有两个版本——3.1 版没有「否则于该回合结束失去一枚令咒」，3.3 版加了这一句。当前 JSON 实现的是 3.1 版口径 + 「第一回合必须使用一枚令咒」的 `action_requirements`（`data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json:95`）。**要不要按 3.3 版补上「未使用则回合结束失去一枚令咒」，请你定版本**；本次只按现有实现报缺陷。

---

### 6. 技能卡打出入口没有把费用下限取 0，负费用会反向加魔力

**位置**：`assets/scripts/system/operations/PlaySkill.gd:39-45`。

**对照**：`assets/scripts/system/operations/PlayAttack.gd:62-63` 有 `if final_cost < 0: final_cost = 0`；`assets/scripts/system/regular_play.gd:100` 的 `cost()` 是 `maxf(0, ...)`。**只有 `PlaySkill` 这一条入口没有取 0**。

**触发条件**：`data/servants/00005_medea/00005_medea.json:30`「阵地建造」的动态费用是 `16 - 当前回合数 × 2`，第 9 回合为 `-2`。

**现象（探针实测）**

```
REPRODUCED L_base_construction_negative_cost  | round9 card cost=-2 RegularPlay.cost=0.0
REPRODUCED L2_play_skill_gains_magic          | PlaySkill ok=true magic 10->12
```

第 9 回合，常规出牌入口 `RegularPlay.cost()` 正确地返回 0（不受影响），但经 `PlaySkill` 打出时魔力 **10→12，反增**。

**建议修法**：把 `PlayAttack` 已有的下限口径搬进 `PlaySkill`，让两条出牌入口对「费用不为负」给出一致结果。这是同一规则在两处入口分叉，属于一致性修复，不新增 operation。

**待确认**：「费用下限为 0」是要按规则确认的口径（基础规则没有直接写「费用不能为负」）。若不希望引擎强制，也可以改为在数据层给阵地建造的费用公式加上限判断——但数据层需要新增取最大值的能力，反而更麻烦。**建议按引擎侧取 0 处理，请你确认。**

---

## 二、静态可判、未复现

以下几条看代码/数据就能判断与卡面或规则不一致，但**这次没有跑**，缺什么证据一并写明。

### 1. 还有 4 条阶段能力同样没有「每回合一次」

与第 2 条同源，但它们都不是「手动发动」，所以行为路径不同，未验证：

| 卡牌 | 效果 | 位置 |
|---|---|---|
| 月之癌 | 行动阶段：将你所在地点的事件牌与月之圣杯的互换 | `data/attacks/class/mooncancer_class/mooncancer_class.json:39` |
| 监督者 | 中立：行动阶段可花 2 魔力无视交战移动到侦察 | `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json:264` |
| 石化之魔眼 | 行动阶段：对手本回合没打魔术攻击则【败北】 | `data/servants/00004_medusa/00004_medusa.json:257` |
| 骑英之缰绳 | 行动阶段：移动到任一地点并重部署地利 | `data/servants/00004_medusa/00004_medusa.json:208` |

后两条同时还是 `do_nothing` 占位（见第三档）。**缺的证据**：需要一个非手动、非纯被动的效果在同一阶段窗口内被询问两次的探针。`_first_settlement_of_phase_windows()`（`assets/scripts/system/global/effect_manager.gd:842`）只对纯被动效果去重，对这类效果的覆盖范围要实测。

### 2. 石化之魔眼的能力时点与卡面不符

**卡面**：「行动阶段：**在战斗阶段开始前**，若与你进行战斗的对手本回合没有打出/加入魔术属性攻击，则其【败北】。」判定对象是「本回合最终会与你战斗的对手、其本回合的全部出牌」。

**现状**：`data/servants/00004_medusa/00004_medusa.json:257` 的时点是 `self_action_phase` 且 `is_pure_passive: false`（会被自动询问），效果体直接读 `get_players_in_same_area` 和对手**当时已打出**的牌。行动阶段按顺位进行，排在后面的对手还没出牌，此时判定会漏判。

**缺的证据**：需要一局「对手顺位在自己之后」的实测，比较行动阶段判定与战斗阶段判定的结果差异。**这条属于规则口径问题（判定时刻），修法不是加一个字段就能定的，建议先确认口径。**

### 3. 一之太刀两条效果的激活要求组合

`data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json:54`（关闭此牌并打出一张力量基本攻击）和 `:141`（关闭一名交战玩家的一张基础攻击）。卡面原文是一句连写：「关闭此牌，然后从手牌打出一张力量基本攻击。**若如此**，获得2点魔力**且**关闭一名交战玩家至多一张基础攻击。」

现状把「若如此」之后的两个结果拆成两条独立选项，第二条可以**在第一条没发动的情况下**单独发动。现有测试 `tests/ichi_no_tachi_test.gd` 的注释承认了这个拆分（「一个选项只能声明一个 select_cards，所以两条半句各自成一条效果」），并把「关闭此牌」放在了第二条以维持激活状态。

**缺的证据**：未探测「只发动第二条、不打出力量攻击」时是否真的生效（按现状应该会生效）。**这是现有测试已知的设计取舍，要不要合并成一条请先定口径。**

### 4. 骑乘「一同打出」的顺序

见第一档第 3 条的 I 项说明：目前不区分「先打基础攻击再打骑乘」和「同批打出」。**缺的证据**：需要一批提交（`RegularPlay.submit_group`）里两张牌同打的探针。

---

## 三、未实现 / 占位（与 bug 分开）

以下都是效果体里只有 `do_nothing`，属于**功能未实现**，不是缺陷：

| 卡牌/来源 | 效果 | 位置 |
|---|---|---|
| 无限剑制 | 【真名解放】打出时：以你打出的牌、手牌、牌库和弃牌堆任意组建一组至多 12 张牌的手牌 | `data/servants/00002_emiya/00002_emiya.json:244` |
| 一之太刀 | 你拥有的魔力少于 8 点也可打出此牌 | `data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json:30` |
| 二之太刀 | 行动阶段：与你同战场的对手无法使用行动/战斗阶段能力 | `data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json:267` |
| 三之太刀 | 你可于打出 2 张迅捷攻击时追加打出此牌 | `data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json:307` |
| 骑英之缰绳 | 【真名解放】行动阶段的重部署地利 | `data/servants/00004_medusa/00004_medusa.json:208` |
| 月之癌 | 两条（月之圣杯事件牌效果范围、行动阶段互换） | `data/attacks/class/mooncancer_class/mooncancer_class.json:21`、`:39` |
| 复仇者 | 无声业火残留 | `data/attacks/class/avenger_class/avenger_class.json:61` |
| 监督者 | 管理者：所有玩家秘密告诉你从者职阶 | `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json:246` |
| 恶的庇护者 | 监督者/执行者两种形态的能力 | `data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json:460` |
| 宝石剑泽尔里奇 | 行动阶段：获得本回合所有玩家花费的魔力 | `data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json:1145` |
| 腐蚀 | 每局限一次，夺取被淘汰玩家的从者技能牌 | `data/masters/00004_matou_sakura/00004_matou_sakura.json:654` |

补充：「圣杯核心」（间桐慎二的升华技，`data/masters/00003_matou_shinji/00003_matou_shinji.json:833`、`:857`、`:881`）也还没接线，条件里写着「莎士比亚是你的从者」——本项目当前没有莎士比亚，属于**卡面条件在当前卡池下恒不成立**，实现与否建议先确认是否要纳入范围。

**基线里已核实正确的（不要误改）**

- 穿刺死棘之枪「打出时：此牌+2魔力消耗（可叠加）直至游戏结束」：3→5，正确（`placeholder_permanent_cost_increase_on_play`，`data/servants/00003_cu_chulainn/00003_cu_chulainn.json:317`）。
- 贯穿心脏「若仅有一名对手与你位于同一战场」：同战场有 2 名对手时**不会**让任何人败北，正反例都正确。
- 阿尔托莉雅三张技能牌的「每回合一次」、誓约胜利之剑「合计威力+4 且卡面不变」、第 11 回合胜利只在激活时生效：已有 `tests/artoria_skills_test.gd` 覆盖并通过。

---

## 四、建议的修复顺序

1. **第 1 条（buff 激活）** —— 引擎一处判断，覆盖言峰/伊莉雅/间桐樱四张牌，收益最大。
2. **第 2、4、5 条** —— 全部是数据改动，用现有写法组合，不新增字段。
3. **第 3 条（`need_activate` / `source_bound`）** —— 数据改动，但骑乘那条要先确认「一同打出」口径。
4. **第 6 条（负费用）** —— 引擎一处判断，需确认「费用下限为 0」口径。

按项目约定，改 JSON 前先把涉及卡牌的**卡面原文**交出来核对（牌名、费用、威力、属性、类别、效果全文），再动手。

---

## 五、本次未覆盖的部分

- **UI / 非 headless 对局没有检查**。本次全部是 headless 探针与静态比对，没有跑非 headless 完整对局，也没有检查画面。
- **只审了 FSN 的 7 从者 + 7 御主**。基本牌、职介牌、事件牌、局势牌只做了「顺带扫过」级别的关注（`data/events`、`data/situations`、`data/attacks/basic` 里没发现同源问题，但未逐条核卡面）。
- **没有覆盖的时点**：准备阶段、前哨阶段的多数能力；战斗结算（battle_resolver）与事件/局势结算；淘汰与终局判定；AI 决断路径（`dummy_bot`）。
- **没做的验证方式**：没有跑导出后的外部 data 版本；没有做跨回合连续对局的长链验证。
- 昇华技（`upgrade_skill`）本次只核了卫宫士郎的必胜黄金之剑与远坂凛的宝石剑、间桐慎二的圣杯核心、伊莉雅的第三法、葛木的完美呼吸、言峰的恶的庇护者（后几张仅静态看了一眼，占位与第 3 条同源问题未展开）。

---

## 附录：探针方法与原始输出

**方法**：在 `tests/` 下临时写 `zz_audit_probe.gd/.tscn`（`extends Node`，`call_deferred("run")`，输出 `RESULT`），用

```
<console exe> --headless --fixed-fps 60 --path <项目> --scene res://tests/zz_audit_probe.tscn
```

运行，`<out>/<场景>.log` 里取 `AUDIT` 行。**探针文件与产物已全部删除，工作区没有残留。**

> 注意：`--script <外部 .gd>` 这条路径在本项目**不可用** —— `base_object.gd` 等业务脚本引用了 `GameData` 等 autoload 标识符，外部脚本编译期会报 `Identifier not found: GameData`，然后卡死到超时。只能在 `tests/` 下用场景方式跑。

**判据**：`REPRODUCED` / `not_reproduced` 由探针自己打标，每条都带实测值（前后数量、返回值、错误原文）。探针自身报错或没能执行到断言的，不记成「未复现」——第一版 I 项因为常规出牌的 `minimum` 下限校验没通过、出牌直接失败，已改为按 `submit_group` 的真实顺序（移区 → 记 play 日志 → 派 `PLAYED_CARD` 时点）重跑，才得到结论。

**完整原始输出**

```
REPRODUCED A_kirei_executor_inactive_still_applies | executor.active=false bonus 0->2
REPRODUCED B_illya_heavenly_robe_inactive_scores | robe.active=false score 0->2 (round2)
REPRODUCED C_repeatable_zero_opponent_agility_power | first=true can_again=true
REPRODUCED C_repeatable_placeholder_pierce_heart_single_opponent_defeat | first=true can_again=true
REPRODUCED C_repeatable_battle_win_score_gain | first=true can_again=true
REPRODUCED C_repeatable_divine_words_retrieve_rule_breaker | first=true can_again=true
REPRODUCED D_luck_repeatable | first=true again=true
not_reproduced E_gae_bolg_cost_growth_missing | cost 3->5
not_reproduced F_pierce_heart_two_opponents_defeats | p1 defeat=0 p2 defeat=0
REPRODUCED G_base_construction_unplayed_triggers | activating=false magic 10->11 score 0->2
REPRODUCED H_swallow_reversal_without_san_played | san.activating=false bonus 0->3 released=true
REPRODUCED I_riding_unplayed_draws | riding.activating=false hand after play 0 -> after PLAYED_CARD 1
REPRODUCED J_caliburn_repeatable | first=true again=true
REPRODUCED J2_caliburn_printed_power_not_restored | printed 8 -> after use 12 -> after round cleanup 12
REPRODUCED K_rin_penalty_outside_round1 | used=true round2 magic after cs 12 -> after battle end 8
REPRODUCED L_base_construction_negative_cost | round9 card cost=-2 RegularPlay.cost=0.0
REPRODUCED L2_play_skill_gains_magic | PlaySkill ok=true magic 10->12
```

**基线（本次审计开始时跑的全量回归）**

```
53 suites, 0 failed, 0 SCRIPT ERROR
（scripts/run_all_tests.py --no-kill --timeout 120）
```
