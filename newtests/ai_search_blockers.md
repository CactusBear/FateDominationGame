# 正式搜索 AI：前置阻断回执

## 状态

**未实现正式 AI；按“规则查询不够用时停下”停止。生产 AI、driver、v2 和规则层均未由本子代理修改。**

本次仅新增：
- `newtests/ai_checkpoint_feasibility_test.gd`：继承现有可信来源夹具，创建真实手动加威力效果，执行并调用完整效果检查点恢复，逐项记录业务状态和图外审计边界。
- `newtests/ai_checkpoint_feasibility_test.tscn`：该探针的 Node 场景。
- `newtests/ai_search_blockers.md`：本回执。

无新 class_name，所以本次没有类缓存导入需求；没有创建项目副本，没有保留自启动 Godot 进程，没有提交 git。

## A/B 档真实证据

首轮真实 Godot 4.7.2：23 checks，exit 0，唯一 RESULT，failures=[]，无 SCRIPT ERROR/ERROR。真实效果使总威力变为 5，restore 返回 true；keys、hand、played、magic、power、logs、transaction、messages、random、progress、token 都逐项相同。

但审计边界的 identity 从 0 变成 1，不能承诺“所有状态逐项不变”。本轮战斗确认批次序号为 0→0，**未实证序号变化**；源码 `effect_checkpoint.gd:120-121` 会调用 renew_battle_broadcast_batch，只能作为契约风险，不计为本次实测变化。

因此严格不变要求下 A 档不合格，应选 B 档静态估计。**B 档尚未实现，不能称已经穷举真实效果结算。**

原文：
```text
AI_A_TIER_EVIDENCE {"audit_after":{"error":"","hash":"","identity":1,"records":0,"revision":0},"audit_before":{"error":"","hash":"","identity":0,"records":0,"revision":0},"batch_after":0,"batch_before":0,"reason":"audit_identity_and_broadcast_token_are_not_rollback_state","rule_fields_unchanged":{"hand":true,"keys":true,"logs":true,"magic":true,"messages":true,"played":true,"power":true,"progress":true,"random":true,"token":true,"transaction":true},"tier":"B"}
RESULT {"checks":23,"failures":[],"suite":"ai_checkpoint_feasibility"}
```

最终脚本只把上面 reason 改为精确的 `audit_identity_is_not_rollback_state`。第二轮复验 exit 0 **但无 RESULT，出现 LoadHelper 类解析错误与 autoload 级联错误**。runner 判 RED（missing_result、engine_error），不能把最终工作树称为验证通过；不得以首轮绿覆盖第二轮缺失结果。首轮有效证据只认证当时加载的工作树。

## 真实命令与日志

第一轮：
```text
python E:/scratch/refactor-main/run_suites.py ai-checkpoint-feasibility res://newtests/ai_checkpoint_feasibility_test.tscn
```
Godot 子进程命令（exit 0，2.8 秒）：
```text
D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --quit-after 36000 --path E:/Projects/Godot/FateDominationGame-master --scene res://newtests/ai_checkpoint_feasibility_test.tscn
```
日志：`E:/scratch/refactor-main/runs/ai-checkpoint-feasibility/`。

第二轮：
```text
python E:/scratch/refactor-main/run_suites.py ai-checkpoint-feasibility-final res://newtests/ai_checkpoint_feasibility_test.tscn
```
子进程 argv 同上，exit 0，1.6 秒；RESULT 原文：**不存在**。最早错误：
```text
SCRIPT ERROR: Parse Error: Could not resolve class "LoadHelper", because of a parser error.
   at: GDScript::reload (res://scripts/system/global/game_data.gd:337)
```
日志：`E:/scratch/refactor-main/runs/ai-checkpoint-feasibility-final/`。
runner 自身 exit 0 不能代替子场景通过。

## 必须由主代理解决/授权的缺口

1. **异步回放消费者超出本次授权**：`scripts/match/match_replay.gd:542-579` 的 `_execute` 同步派发，`:570` 直接 `driver.run_bot_turn(...)`。只在 driver/v2 await 不能保证回放等待搜索完成再取状态；需主代理授权并迁移回放/记录链，或提供可等候完成的现有命令边界。旧 tactical_board_ui:4081 同样同步 DummyBot.step，当前禁止本子代理写该文件；旧完整对局夹具也有同步调用。不能宣称确定性只靠节点数已完成。
2. **安全上界查询不存在**：`BoardPowerQuery` 的 `scripts/system/global/board_power_query.gd:97-195` 支持条件、foreach、变量、牌间协同与对象身份判断。总威力不是印刷威力的简单求和；“单牌最大分累加”没有通用安全性保证。需要一个可信保守上界查询，或者明确批准有动态贡献时使用 +INF 禁用该项剪枝。后者不改变规则，但不满足 PLAN 当前要求的通用有限上界剪枝，不能悄悄删掉必做优化。
3. **名字/费用/威力/属性/明暗不是规则等价证明**：还存在 `_need_extra_play`、`_play_requirements`、discount、技能觉醒/忽略限制、效果和 BoardPowerQuery 的对象身份等区别。不能按 PLAN 的五字段键盲去重。需要规则等价查询，或明确允许只对已经证明无其它相关差异的牌去重、其余保留分支。
4. **所有合法位置的只读枚举缺口**：`AreaActionRules.first_effect_location_target():182-216` 返回一个位置；`MatchSeatQuery.location_candidates():155-169` 每个战区只有一个位置。若需求是 UI 所允许的“每战区一个落点”，已有查询够用；若需求是所有符合规则的具体席位（PLAN “每个候选目标”），缺少全部合法位置查询。AI 不得复制这些规则或调用提交入口试探 live 状态。
5. 当前工作树复验 LoadHelper 解析受阻。未定位为本次两份测试导致；未修改/回退他人热文件，需写者排空后统一复验。

## 未执行的验收

正式搜索器、rule_bot、B 档效果规划、随机部署接线、最低出牌与空候选/免疫/透支/明暗/局面变化/多选等集成测试均未实施。
15 秒产品上限、确定性节点预算、每帧 4ms 切片：**没有实际取值，没有超时和确定性结果**，不以探针的 2.8 秒冒充搜索性能。
未运行 PLAN 的四项回归（natural_game_over、match_view、a1_06_regular_origin、card_effect_runtime）；只使用 a1_06 的可信夹具，未运行其整套断言。未做窗口、跨机、回放整链验证。
