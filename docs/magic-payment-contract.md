# 魔力支付原语：实施、审计与未闭合边界

## 结论
- PlayAttack 与 RegularPlay 的实际支付已收敛到 `PayMagic`。缺省透支许可为 false；许可只属于本次显式调用，不查询效果名，不写玩家字段。
- 费用公式未改，前端未改，data 字节未改，既有测试断言未删；新增测试派生自已有两路径诊断夹具。
- **不是“全仓单一口径完成”**：PlaySkill 仍直接复核/扣费，位于本子任务写入范围之外。旧入口无已跟踪随机流时的通用对象图回滚不能恢复未知全局随机状态。见最后的阻断清单。

## 选择与耦合
`EditMagic` 的职责是设值/增减、限幅、日志与魔力变化时点，不具备“必须付清”的返回契约。特别是远坂凛 `placeholder_absolute_order_penalty` 的 -4 为强制失去，余额不足仍应削到 0，不能改成拒绝削减。已有 EditMagic + 比较 operation 的组合只能给出前置资格，不能在修改瞬间拒绝不足且保留全部余额。因此新增单一职责 `pay_magic`，普通 EditMagic 保持限幅；旧调用显式携带 payment_purpose 且目标减少时转交支付原语。
初版使用按效果名通用查询；用户 A1 逐字裁定「特殊效果可以用 operation 组合来实现」后，已移除查询和新增效果类。最终采用调用参数，比持有者标记更精确：只许可本次支付，不污染后续动作，不增加玩家数据/克隆/网络字段。

## 最终接口
```gdscript
PayMagic.can_pay(amount: BaseNumber, player_id=-1, available=null, allow_overdraft=false)
PayMagic.exec(amount: BaseNumber, player_id=-1, purpose="", source=null, dispatch_time_points=true, allow_overdraft=false)
PlayAttack.exec(attack, player_id=-1, cost=null, power=null, ignore_limit=false, allow_magic_overdraft=false)
RegularPlay.submit_group(id, cards, hidden_flags, allow_magic_overdraft=false)
```
费用由调用方传入；支付原语不算费用、不写规则数字。负金额或非有限金额拒绝。can_pay 的 available 只用于只读组合报价，exec 永远重新读取当前余额。免疫仍视作成功且不扣费、不记支付日志。卡牌出牌传 dispatch_time_points=false 保留旧时点行为；EditMagic 旧费用调用继续派 MAGIC_DECREASE。
纯 JSON 可表达的显式许可示例（不改正式数据）：
```json
{"func_name":"pay_magic","parameters":[{"number_index":0},-1,"effect_cost",null,true,true],"var_index":0}
```
最后一个 true 只许可本次支付，金额仍来自 effect_numbers。多动作效果组合必须以 var_index 返回的支付结果控制后续状态动作；不要先完成动作再忽略 false。PlayAttack 也可在原参数列表末尾追加 true，整张攻击的费用公式、入场语义不需要另做一套。

## 全部正式 data 调用点（递归包括 options、foreach 内层）
共 16 个 `func_name=edit_magic`，下列 pointer 可唯一定位；完整原参数见 JSON 回执。
| 文件 | JSON pointer | 效果 | 负值风险、正当理由与处理 |
|---|---|---|---|
| data/command_spells/normal_command_spell.json | `/effects/0/options/0/funcs/0` | `command_spell_use` | 获得 +4；当前非负；非费用，保留资源获得语义。 |
| data/servants/00005_medea/00005_medea.json | `/specials/SKILLS/0/effects/1/funcs/3` | `base_construction_deploy_workshop_gain` | 获得 +1；当前非负；非费用。 |
| data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json | `/specials/SKILLS/0/effects/1/options/0/funcs/5` | `ichi_no_tachi_close_and_play_strength` | 特殊攻击成功后获得 +2；非费用；此前攻击扣费现在由 PayMagic 拒绝/支付。 |
| data/servants/00008_angra_mainyu/00008_angra_mainyu.json | `/specials/SKILLS/0/effects/0/options/0/funcs/10` | `angra_left_right` | 独处战场获得 +4；技能区低于门槛可用不等于允许欠费。 |
| data/masters/00001_emiya_shirou/00001_emiya_shirou.json | `/effects/0/funcs/0` | `inexperienced` | 设值 2；初始化，无负值理由。 |
| data/masters/00001_emiya_shirou/00001_emiya_shirou.json | `/effects/2/funcs/1` | `avalon` | 设值 0；失去全部魔力是合法资源修改，不应被“必须付足”重解释。 |
| data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json | `/effects/2/funcs/4` | `placeholder_absolute_order_penalty` | 失去 4，余额不足时截到 0；合法强制削减，不是必须付足的费用，也不是透支声明。默认改为拒绝负目标会破坏本调用。 |
| data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json | `/specials/BUFFS/0/effects/0/options/0/funcs/6` | `jewel_sorcery_action` | 宝石获得 +1；非费用。 |
| data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json | `/specials/BUFFS/0/effects/1/options/0/funcs/6` | `jewel_sorcery_climax` | 文案获得 +1；effect_numbers 当前为空且使用 number_index 0：必须由既有加载上下文解析，本任务不修数据；不含负数/透支声明。 |
| data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json | `/upgrade_skill/0/effects/1/options/0/funcs/1` | `placeholder_jewel_sword_drain` | 从 magic_spend 日志累加 spent（非负）后获得魔力；不是允许透支。 |
| data/masters/00003_matou_shinji/00003_matou_shinji.json | `/effects/0/funcs/3` | `absorb_magic_command` | 进入深山町获得 +1；非费用。 |
| data/masters/00003_matou_shinji/00003_matou_shinji.json | `/specials/BUFFS/0/effects/0/funcs/18` | `false_servant_book_master_replace` | 御主替换时设值 4；无透支理由。 |
| data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json | `/effects/0/funcs/0` | `artificial_life_initial_magic` | 设值 6；初始化，无透支理由。 |
| data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json | `/effects/3/funcs/4` | `all_conceal_magic_gain` | 暗置条件下获得 +1；非费用。 |
| data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json | `/specials/BUFFS/0/effects/1/options/0/funcs/10` | `overseer_neutral_move` | 先比较可支付/免疫，再 set_location，扣 max(0,声明费用) 的负数；现有调用声明 move 支付用途，已由 EditMagic 转交 PayMagic；没有透支理由。 |
| data/events/origin/ley_line/ley_line.json | `/effects/0/funcs/3/parameters/0/0` | `ley_line_magic_plus_2` | 战斗后按 foreach 玩家获得 +2；非费用。 |

## 全部生产代码调用/同名项
- 注册表 all_operations.gd：edit_magic→EditMagic 保留原行，仅追加 pay_magic→PayMagic 一行。
- DeployRules.apply_benefit：读取席位印刷魔力；当前为资源获得，假如效果把值改负也会由 EditMagic 截到 0，不具有透支资格。
- SituationResolver._resume_activation、DebugBoardAdapter.replace_situation：读取局势印刷魔力；非支付，即使负值仍按普通资源修改限幅。
- EffectManager._pay_effect_cost：先做可支付性判断，再 EditMagic(...,"effect_cost",effect)；修改瞬间现已转交 PayMagic，但调用方仍忽略 EditMagic 的返回值，且前置资格不接受新许可参数。
- Move.exec：MoveLocation 先比较余额/免疫、完成落位，再 EditMagic(...,"move",location)；扣款现在转交 PayMagic。若落位时点另消耗魔力，则拒绝扣费能保住余额，但既有调用者忽略 false，移动结果不会自动撤销。这不等同 RegularPlay 的整组事务。
- BaseSituation.edit_magic：修改的是局势牌印刷 _magic，不是玩家余额，不属于支付路径。
- EditDataNumber、CalculateNumber、EffectManager 的其他命中为注释，不是调用。测试/newtests 里的 EditMagic 调用为限幅断言，原只读夹具未覆盖或改写；新增 tests/magic_payment_contract_test 派生其断言。
- PlayAttack 原直接减法已经移除；RegularPlay 原直接减法已经移除；PlaySkill 原直接减法仍保留（范围外）。
- json_maker/types.json 有 edit_magic 目录项，无执行调用。新增 pay_magic 的编辑器元数据未修改（范围外）。

## RegularPlay 原子性与续行
在 regular_play_start 与真名解放等首个副作用前建立现有检查点，复用已有事实事务；每张牌在费用计算时点之后用 PayMagic 按当前余额支付。任何不足先终止游标，再取消事实投递并 restore 整组，恢复首张已付费/入场、后续牌、威力、费用数字与日志。增量 add 也经过同一流程，保留此前已经成功完成的增量动作。
游标 rejected/done 为终态，同一迟到续行不再次扣款；费用与其他时点的阶段游标仍在派发前前移。真实 guard 暂停时 submit 返回的是已调度，最终是否完成以 regular_play 事实/状态为准，这沿用原接口异步语义。
已跟踪随机会话用现有 EffectCheckpoint 恢复整组及 RNG；旧未跟踪入口只用现有 RuleCheckpoint 恢复对象图，不能宣称恢复未知全局随机流。本轮回归验证了旧入口现有静态费用场景、已跟踪 RNG 的真实暂停/拒绝恢复；不证明旧任意随机效果的完整回滚。

## 数据依赖“扣成负数”的效果清单
当前明确声明透支的正式 data：空。当前可证实依赖负余额作为机制的效果：空。负变化明确项是远坂凛失去4魔力，但既有 EditMagic 已截到0，它不依赖负余额，不建议改成透支。费用增长本身也不是透支声明；不足时应拒绝，只有后续确认要允许透支的效果链才显式把许可参数设 true。没有按名称/文案自动授权，没有更改 data。

## 真实 headless 验证
同一最终冻结：13 场景 / 552 条 CHECK，全 true，所有 exit=0、ERROR=0、Job0；source_drift=[]、data_changed=[]。
看门狗 600 秒/自有进程；APPDATA/LOCALAPPDATA/TMPDIR/TEMP/TMP 全 E 盘。真实主/worker user:// 探针、Windows Job Object 与继承日志句柄释放均有回执。未触碰 PID 17120/28100；未执行 GUI 或全量回归。
| 场景 | CHECK | exit | ERROR | Job0 |
|---|---:|---:|---:|---|
| tests/magic_payment_contract_test.tscn | 219 | 0 | 0 | True |
| tests/regular_play_test.tscn | 54 | 0 | 0 | True |
| tests/battle_command_adapter_test.tscn | 29 | 0 | 0 | True |
| tests/mana_spend_test.tscn | 45 | 0 | 0 | True |
| tests/piercing_cost_test.tscn | 11 | 0 | 0 | True |
| tests/card_effect_runtime_test.tscn | 80 | 0 | 0 | True |
| tests/extra_play_limit_test.tscn | 22 | 0 | 0 | True |
| tests/ui_refresh_cost_test.tscn | 25 | 0 | 0 | True |
| tests/magic_limit_test.tscn | 8 | 0 | 0 | True |
| tests/servant_skill_eight_magic_test.tscn | 26 | 0 | 0 | True |
| tests/rule_guard_situation_magic_test.tscn | 6 | 0 | 0 | True |
| tests/rule_guard_regular_group_test.tscn | 9 | 0 | 0 | True |
| tests/rule_guard_regular_add_test.tscn | 18 | 0 | 0 | True |

专项包括：费用2→3而魔力2，拒绝、整组原余额、手牌/打出区/激活/威力/日志恢复；第二张才不足时撤销第一张；费用时点降低魔力后拒绝；真实 guard 暂停/恢复后同样拒绝；恢复已跟踪 RNG；重复提交与迟到同一游标无再次扣费；显式 true 的数据 operation 调用、攻击、整组可透支且许可不泄漏。
历史 RED（168 CHECK，30 false，exit1，ERROR0，Job0）已保留。中间一轮 descriptor 夹具未设置 _using_numbers 导致3条 false，修的是合法夹具，不删断言；refactor_build_cost_probe 的 checks=0 是诊断输出，不作为通过套件计入最终13套。第一次 final 清单含不存在场景，未启动业务进程；改为实际发现的 regular_group/add 场景再冻结。
真实命令：
```text
python E:/scratch/magic-payment-focused/run_focused.py final tests/magic_payment_contract_test.tscn tests/regular_play_test.tscn tests/battle_command_adapter_test.tscn tests/mana_spend_test.tscn tests/piercing_cost_test.tscn tests/card_effect_runtime_test.tscn tests/extra_play_limit_test.tscn tests/ui_refresh_cost_test.tscn tests/magic_limit_test.tscn tests/servant_skill_eight_magic_test.tscn tests/rule_guard_situation_magic_test.tscn tests/rule_guard_regular_group_test.tscn tests/rule_guard_regular_add_test.tscn
```
每场景实际 argv、PID、exit、Job0 和日志摘要见 manifest；全部 Godot argv 使用 --headless --fixed-fps 60。
- 最终 manifest：`E:\scratch\magic-payment-focused\isolated-2b9bdfe6da304ed0849607d365dd99b4\manifest.json`
- RED manifest：`E:\scratch\magic-payment-focused\isolated-1f519ce7a6354641a996fc3f47cbe75c\manifest.json`
- 完整 SHA/审计/回执：`E:/scratch/magic-payment-focused/delivery-receipt.json`
- minimal diff（仅本任务七个源/测试文件）：`E:\scratch\magic-payment-focused\minimal.diff`

## 改前/改后 SHA256
新增文件 before=null。
| 文件 | before | after |
|---|---|---|
| scripts/system/operations/EditMagic.gd | 6578c2e92535b9f62ecc3c25dd7a00027daeaa3f1ebe5f62c71ae09162fa5ecf | 7403e2a0f2a3949147a7f726345eacd319930611f3c6dfe611d6e24940df4a8b |
| scripts/system/operations/PlayAttack.gd | 94385a0532baab8222cdd21a22b56c97525b513474667f1f3eb6e40571cb7c04 | b2e42b80d1602fa0d52c4c4b59bd00baae3d063870e49880bfe9c95431489444 |
| scripts/system/regular_play.gd | f6fce80464730c6a259bc188b5d252efe7da5ab70cafecb9901cbabfdb825d27 | 40ad584c500f5a327b248b528175b33ffe9574b9b3998ed36aec700b09eec064 |
| scripts/system/operations/PayMagic.gd | None | f2dc69593ab7ad442e250e6a5afaf904cd4ce2c4db06e9da73e17a9c155dadd1 |
| scripts/system/global/all_operations.gd | 5449d6373ea3e52823fe0c5f2c6e71a9260e71de0594ec95aa9ceec17e3ad787 | 8f39c2dfa98a2989a79040fba436d69bc93c8e6c93a86e7f3664e0f44fbd775a |
| tests/magic_payment_contract_test.gd | None | fe80c259f7a7c0c9e5fdbffd5e7e429d2c6b33654c875e4990684d43d86e0377 |
| tests/magic_payment_contract_test.tscn | None | 8a611c65ce4344b65cf2f893a5030623a012d1949578e6f1ea7645d9c9df12a2 |

## 未闭合项，不能升级为全仓验收
1. PlaySkill 不在本子任务授权写入文件中；仍有独立支付判定/减法。要满足“所有扣费路径且只有一处口径”，需由该文件写入者改为 PayMagic，并按需要传递本次许可。
2. EffectManager.can_pay_effect_cost 与 MoveLocation 仍有原前置余额比较，既有费用调用者忽略 EditMagic 失败返回。普通现有费用守住负值下限，但这些整链还不能共享显式透支许可/动作失败回执；若授权主代理扩大范围，应串行迁移调用/前置资格，不改费用公式。
3. 旧未跟踪全局随机流不能证明完整回滚；完整任意效果原子性还须统一接入现有可恢复随机会话或失败关闭，不能伪造种子。
4. json_maker/types.json 未纳入授权写入；若需要在编辑器配置新增 operation，要单独补登记/参数说明。
5. 暂停后的异步拒绝沿原 submit 返回“调度成功”语义；最终 regular_play 不会完成，未增加新命令 receipt 协议。

所有已有前端/共享脏文件均未写入。

## 收尾

- 五份有完整所有权回执的 generated 冻结树已由现有保守清理器删除；日志、manifest、改前源字节、minimal diff 保留在 E 盘。回执：`E:/scratch/magic-payment-focused/cleanup-receipt.json`。预检缺场景的分配发生在旧执行器保存 manifest 前，未作为未知所有权目标自动清扫。
- 已备份并更新默认 profile 的 fate-domination-engine `references/compose-before-add.md`：区分“强制失去资源”与“必须付清”，记录本次调用显式许可而非玩家持有者标记。未改其他 profile；备份 `E:/scratch/magic-payment-focused/compose-before-add.skill.before.md`。
