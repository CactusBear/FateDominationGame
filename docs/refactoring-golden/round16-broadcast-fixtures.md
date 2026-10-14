# Round16 — E05/E06 播报测试夹具迁移

## 结果

仅修改获授权的四个测试，无生产 fallback，无窗口运行。最新版四套实际 headless 运行全部退出 0，且无 SCRIPT ERROR：

| 套件 | 首次 RED | 迁移后 GREEN |
|---|---|---|
| battle_broadcast_test | 55 秒超时；首次运行器未保存超时输出，不能声称取得 RESULT | checks=40 failures=[]，退出 0 |
| match_replay_pending_test | checks=12，退出 1；旧消费者启用/恢复断言和 record one 篡改拒绝断言失败 | checks=14 failures=[]，退出 0 |
| match_replay_recovered_copy_test | 55 秒超时；首次运行器未保存超时输出，不能声称取得 RESULT | checks=19 failures=[]，退出 0 |
| refactor_kernel_state_boundaries_test | checks=41，退出 1；E06 前消费者恢复断言失败 | checks=48 failures=[]，退出 0 |

首次 RED 运行器整体因 TimeoutExpired 退出 1；没有将超时当作完整 RED 验收。GREEN 运行器已改为保存超时或正常输出。pending 首次篡改拒绝失败保留在此，不吞旧报告；同一断言未改，最新真实运行通过，不据此臆断失败根因。

## 修改与边界

- `tests/battle_broadcast_test.gd`：显式设置 `battle_broadcast_requires_confirm`；正式界面注册后注销展示消费者，真实战斗入口建立无 consumer 仍等待的屏障；注册并直接销毁临时 Node，验证消费者消失不改变策略/等待。随后重新登记正式界面，保留战果、威力、原三秒延迟、确认计数、全员确认后下一轮和等待归零断言。
- `_bind_seat` 夹具不再把 BaseLocation 当 Dictionary：失效正式 source 缓存，再从它已有 `areas[].locations[]` 投影按同一 builder 的位置 ID 取 Dictionary。保留金色角标和地利文案断言，无手造显示字段、无生产兼容分支。
- `tests/match_replay_pending_test.gd`：旧消费者启用/恢复断言迁到显式 bool 策略，额外要求录制/恢复不伪造展示 consumer。保留真实待答、逻辑效果 ID、状态哈希、续写、再次恢复及篡改拒绝。
- `tests/match_replay_recovered_copy_test.gd`：恢复后命令验证显式 bool 关闭，新增启用且无展示 consumer 检查。保留截断原件保护、数据资源清单、完整校验链、另存续写、再次恢复、覆盖拒绝、外部追加检测和数据篡改拒绝全部断言。
- `tests/refactor_kernel_state_boundaries_test.gd`：真实 `end_phase()` 建立等待，保存部分确认后做检查点，修改资源/AI/策略并注销 consumer；恢复必须还原策略、等待与部分确认，但不复活 consumer，批次身份必须换代、旧批次确认拒绝且不改集合，新批次确认可继续。保留资源原对象身份与数值、AI 容器隔离与 scope/实例 ID、暂停 run 身份、事务原身份/外层隔离/原子拒绝、guard 回滚及存档另存续写的原断言。

## 真实命令与日志

运行目录：`E:/Projects/Godot/FateDominationGame-master`。

每套命令：

`D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . --scene res://tests/<套件>.tscn`

kernel 额外参数：`-- C:/Users/Administrator/AppData/Local/hermes/cache/scratch/round16-broadcast-fixtures`。

四套用独立 Godot 进程并行执行。RED 进程上限 55 秒；GREEN 上限 35 秒且四套均正常完成。日志目录：`C:/Users/Administrator/AppData/Local/hermes/cache/scratch/round16-broadcast-fixtures/`，含 pending/kernel 的 `*-RED.log` 和四套完整 `*-GREEN.log`。

`git diff --check`（四个授权测试范围）退出 0；普通 diff 仅显示 battle，因为其余三个既有文件命中 `.gitignore:47:/tests/`，并非丢失修改；未改忽略规则、未暂存/提交。

## 并行交接与缺口

已读取 hermesWarning.txt 与既有 `docs/refactoring-golden/round13-broadcast-command.md`；本地未检索到题述 `round13-broadcast-core` 文件，不伪造其内容。本次实际读到核心已有 int 型 `battle_broadcast_batch_id()`、`renew_battle_broadcast_batch()`、`battle_broadcast_confirmed()` 与带批次确认入口；EffectCheckpoint 恢复后换发身份，本次新增断言实际通过。未覆盖或删改任何 round13 报告。

不宣称网络/窗口/全量回归通过。本次生产由其他代理并行写入；结果只对应实际执行时版本。首次两个超时套件的 RED 完整输出缺失，后续若要求完整 RED 证据，应在隔离旧版本中重跑，不能以最终 GREEN 倒填。
