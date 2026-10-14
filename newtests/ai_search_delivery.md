# 正式搜索 AI 交付回执

## 结论与当前验收

已落盘正式搜索器、B 档效果规划和 v2 分帧接线；**不是规则全绿或自然终局已修复**。

当前最终代码复验（`ai-current-source-check` + `ai-current-natural`）：

| 场景 | 退出码 | RESULT / 结果 |
|---|---:|---|
| ai_checkpoint_feasibility | 0 | `RESULT {"checks":23,"failures":[],"suite":"ai_checkpoint_feasibility"}` |
| ai_group_search | 0 | `RESULT {"checks":12,"failures":[],"suite":"ai_group_search"}` |
| ai_rule_bot | 0 | `RESULT {"checks":148,"failures":[],"suite":"ai_rule_bot"}` |
| match_view | 0 | `RESULT checks=225 failures=[]` |
| a1_06_regular_origin | 0 | `RESULT {"checks":148,"failures":[],"suite":"a1_06_regular_origin"}` |
| card_effect_runtime | 1 | `RESULT checks=228 failures=["real closed sword returns inactive to skill zone", "a closed sword no longer counts as being on the battlefield"]` |
| natural_game_over | 0 | **无 RESULT，不可判定**；`NATURAL_TERMINAL local steps=3994 round=1 end=[]`，249.5 秒退出；本地部署/真实战斗检查为 true，网络段走到正式开局后未打印终局或 RESULT |

以上最新两次调用之间，1297 个脚本/测试输入指纹前后无漂移。所有场景日志均无 `SCRIPT ERROR` / `ERROR:`。natural 的原始 CHECK 共 11 条、2 红，不能拿退出码 0 代替唯一 RESULT。

给定历史基线是 2812 步仍第 1 回合、20 CHECK/3 红；本次仍第 1 回合，**不能称回合推进更远**，也不能把动态循环步数变化称性能提升。此前因 driver 缺原来源，初轮曾 40000 步完全不部署；该创建边界已接上，当前部署/战斗确实发生，但自然终局仍阻断。

## 文件与用途

仅本任务写入：
- `scripts/system/ai/group_search.gd`：纯回调搜索器。稳定组合 DFS、明暗分支、贪心初解、同层等价去重、上界剪枝、统计和同步/分帧共用游标。
- `scripts/system/ai/effect_planner.gd`：B 档选项次数/数量、候选目标组合估计；帧间规则图投影变化检测；不运行效果体、不建立试结算检查点。
- `scripts/system/ai/rule_bot.gd`：部署、整组出牌、阶段能力、令咒、强制结束条件及选择答复编排。
- `scripts/system/ai/temp/dummy_bot.gd`：保留 DummyBot 类名和继承的同步/静态尝试记录 ABI，兼容回放/旧界面/检查点。
- `scripts/match/match_driver.gd`：构造边界保存成功开局的原来源；同步回合签名不变，添加异步回合/效果/选择入口及防重入标记。
- `scripts/game_scene/battle_board_v2.gd`：本地成功开局交接原来源；AI 回合及效果/目标答复接 await 异步入口。
- `newtests/ai_group_search_test.gd/.tscn`、`newtests/ai_rule_bot_test.gd/.tscn`：真实 Godot 专项。
- `newtests/ai_search_delivery.md/.json`：本回执及逐命令机器证据。

保留未改：`newtests/ai_checkpoint_feasibility_test.gd/.tscn`、`newtests/ai_search_blockers.md`。后者为历史停止回执，不代表当前实现状态。未改 operations、加载器、RegularPlay、EffectManager、PlayRules、match_replay、tactical_board_ui、现有 tests 断言；不回退其它写者内容。未提交 git。没有新增 class_name，故无需新增类缓存导入；没有创建项目副本。

## 预算、确定性与最优性

- 正式默认：**4096 节点**，`TIMEOUT_USEC = 15000000`，切片目标 `SLICE_USEC = 4000`。贪心单牌评分/排序准备同样切片并计节点。
- 等分只保留先找到的组合；稳定候选次序，模式次序来自规则；同步/异步共用同一搜索状态机。
- 最新真实 15 秒保险专项：`AI_SEARCH_TIMEOUT nodes=6349618`；`AI_TIMEOUT_EVIDENCE elapsed_usec=15000700 budget=4096 safety_usec=15000000 nodes=6349618`。**该压力用例特意将节点预算覆盖为 1000000000**，用于真正到达墙钟上限，打印行里的 budget=4096 是生产默认常量，不是压力实例预算。
- 最新真实 16 候选集成还打印 `AI_SEARCH_TIMEOUT nodes=171`，确认真实规则查询也会先撞墙钟保险；该实例并未穷尽 4096 节点。测试确认返回不差于贪心。
- 独立三态暴力枚举对照：纯搜索、INF 协同、有限上界剪枝、同层重复牌、真实五牌/0 魔力/魔免/战场/正式开局均通过。
- 同步/分帧读回组合及节点统计一致；实际 driver 同步与异步提交相同最优组合，跨帧 `_acting` 防重入检查通过。
- **边界**：节点预算或墙钟命中后只是最好已知解，不能保证全局最优。固定节点带来的机器无关确定性以未触发墙钟保险为前提；不同机器在墙钟保险下可能停在不同节点，未宣称跨机回放整链验收。计时为节点边界协作检查，单次规则查询和图投影不可抢占，所以 4ms 是切片目标而非硬实时保证；真实 15 秒压力例多出 700 微秒。

## 裁定落实与 B 档含义

1. 同步 DummyBot.step / driver.run_bot_turn 保留 void 同步 ABI；v2 使用另加的分帧入口，未改回放或旧界面。
2. 场上有任意非空 BoardPowerQuery 声明时，保守使用 INF，同时停用身份敏感去重；其它分支用当前预览已计入印刷威力加剩余非负印刷威力作上界。没有新增规则查询。
3. 仅无效果/无打出要求/无追加打出/无词条/无双面/无附属牌，并且名字、脚本类别、费用、折扣、威力、属性、类别、明暗、觉醒、忽略限制、来源区相同的牌可同层去重，其余分支保留。
4. 位置候选复用 MatchSeatQuery.location_candidates，每战区一个 UI 合法落点，不假造全部席位查询。
5. A 档探针 23 项通过但审计 identity 0→1，严格不变不成立。**采用 B 档静态估计，不是试结算穷举真实结果**，日志使用 `AI_EFFECT_ESTIMATE tier=B`。
6. 部署使用 RuleRandom.shuffle，可复现种子及合法落点已实测。

B 档估计值以当前 GetPlayerTotalPower.breakdown 总威力为底，读取直接 `edit_power`、`edit_magic`、`edit_data_number(power/total_power_bonus)` 的声明增量，支持数字索引和选项数量；魔力增量是启发价值，**不是已结算的威力**。JSON 数字主体允许 int/float（例如正式 JSON 的 -1.0），非数值主体先拒绝估计，避免非法比较。

未知操作、条件/变量/延迟链、直接 set_num 的复杂效果未模拟，贡献按零估计。选牌用印刷威力、选人用当前总威力、选位置用地利数字作代理评分；无法证明弃牌/攻击/移动等具体用途的真实因果最优。枚举的目标在实际等待请求出现后独立估计，**不是将全部选项与全部后续目标作真实因果联合模拟**。

B 档测试：最大直接威力、负增益不发动、真实选项结算 +7、计划前后状态不变、同步/异步计划一致、重复次数与 max_choices=-1、数量 1..4、无可用选项、付不起费用、魔力/合计威力声明形状、必须目标和目标不限数量、正式异步令咒均通过。真实等待态的选牌/选人/选位置完整业务整链未单独新增专项，不能用共享目标枚举测试冒充此层验收。

## 极限情况处理

| 情况 | 测试/处理 |
|---|---|
| 无手牌、无合法组 | 真实空手和候选不足最低张数返回空组；编排只在规则 can_end 允许时调用显式原来源 finalize，否则不强行出牌 |
| 最低出牌要求 | 真实 min=2/只有1张、战场至少明置测试；所有最低/上限仍由原 pending_modes/can_submit_group 负责 |
| 15+ 候选 | 纯18张/64节点、真实16张/4096默认，验证预算及不差于贪心；真实16张有墙钟保险命中 |
| 魔力0 | 与独立暴力枚举一致；免费/暗置候选仍按原规则查询 |
| 魔免 | 魔力0且魔免与枚举一致；不自算支付豁免 |
| 可透支声明 | AI 不自行开启 allow_magic_overdraft；常规提交沿用现有 false 入口语义，声明的效果支付由规则引擎负责。本批未新增透支效果专项 |
| 明暗都合法 | 纯/真实三态枚举；战场全暗且无可支付明牌返回空组 |
| 搜索中变化 | 原来源、行动者、轮次/阶段、淘汰和选择等待轻量检查；帧间现有规则图比较。真实魔力变化/行动者交接取消不提交，重置/淘汰守卫通过 |
| 效果多选/-1 | 现有可用性/次数/资源查询与 validate_selection；重复用量、数量范围枚举；不限空间只取节点预算内前缀，绝不冒称穷尽无限空间 |
| 付不起费用 | can_pay_effect_cost 先拒绝，不试扣款；实际提交仍由原支付入口再次检查 |
| 必须满足才能结束 | 保留 ActionRules.requirements/unmet + 强制使用令咒路径；未知要求仍留给规则拒绝，不猜新解法 |

## 回归阻断与证据保全

- 当前 `card_effect_runtime` 两条红定位于现有测试第 213/217 行的 close_card 业务链，未在本任务允许的 AI 写入层找到可修根因。此前 `ai-delivery-final` 同一旧输入批次 228 项全绿；后续 6 个规则文件并行变化，最新稳定 1297 输入复验仍重复两条红。**这里只记录版本变化与新红，不宣称已经证明哪一处规则改动是因果。**
- `natural_game_over` 最新仍第1回合，局部终局检查两红且网络段无 RESULT；不放宽断言、不把退出0刷成通过。
- `ai-handoff-verification` 外层在420秒截断，runner 退出未知；前六项落盘子回执保留，最后项不冒充完成。确认自有无活体后另建独立 label 补跑，再完成最新稳定源码复验。
- 最终 `git diff --check` exit0；只读进程查询 exit0 且目标源码项目无 Godot 活体；未结束其它项目/主代理进程。
- 所有17次 runner命令、47次请求场景的实际退出码/RESULT原文/诊断原文/完整日志路径详见 `newtests/ai_search_delivery.json`。其中外层截断未完成项 observation=null，不能计为真实完成运行。

未做：窗口输入、跨机回放/权威网络整链、真实效果沙箱模拟、全仓回归/导出；风险是静态效果目标评分可能与真实收益方向相反，以及预算/墙钟截断不保证全局最优。
