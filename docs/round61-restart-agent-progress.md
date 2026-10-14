# Round61：Agent候选停滞诊断与确定性RED→GREEN

## 结论与未通过边界

- 已证测试Agent缺陷：只检查权威首候选的实际held朝向，首候选不匹配时静默return，遮蔽后续合法候选。修复只遍历原候选顺序，遵守可见/未出牌/实际朝向以及真实group.add结果，不新增翻牌、不清group/sent_seq。
- 原round60 seq41完整publicview经真实ClientMatchInbox/MatchViewMirror校验。JSON整数路径从原件记录并恢复原类型，未删字段/改值。空组候选使用原actions.cards声明；这是已知合同场景的确定性fixture，不冒称原失败瞬间已丢失的group.preview原件。因此**历史停滞完整首因仍未证实**。
- 候选回归3 CHECK：业务RED exit1 → GREEN exit0。新增观测代码的freed-Agent归档故障另行RED→GREEN；最终fixture5/5、exit0、无SCRIPT ERROR。
- 完整restart只跑一次（run1、外层600、原baseline180/续局440、原模拟15秒、原60秒性能门），实际baseline达到round≥2；随后恢复真实client_error停止，**不是终局/PASS，没有最终save/journal终局回执**。没有忽略client_error。旧client_error未宣称根治。
- 既有net_process及full_game双进程专项同冻结各一对均RED，均未开局，decisions=0；不能将候选fixtureGREEN代替专项GREEN。

## 真实运行与证据索引

|阶段|独占根token|exit/RESULT|判定|
|---|---|---|---|
|tight|`24bf317964df4f05b26062de26bc6d26`|125/无RESULT|RED|
|fixture-type-precondition|`9c31700014c542ac84071f845ba3c30e`|1/1|RED|
|candidate-RED|`be6f3accd9ac4800b2ece22ab4d0ed0c`|1/3|RED|
|candidate-GREEN|`695375e1ca534c259daa19e79a9ab978`|0/3|GREEN|
|full|`c4af90c082eb43159c5dcbff9814989f`|1/51; 1/4; 1/3; 1/5; 1/4|RED|
|lifetime-RED|`69b89b4b3c714af89bec5019a166c1ce`|1/4|RED|
|final-fixture-GREEN|`1644416e6a9a4eee858b0c0807b13eb7`|0/5|GREEN|

所有根都在`E:/scratch/isolated-<token>/`；manifest包含实际完整command、唯一RESULT解析、全部CHECK数量、错误列表、source/frozen hashes、原引擎/DLL hash、Job0与清理回执。最终fixture与完整restart源码不是同一冻结：完整restart在生命周期guard修复前运行，原两条SCRIPT ERROR严格保留，不追认整链GREEN。

实际入口命令：
```text
python -B tools/diagnostics/round61_restart_agent_runner.py --approved-root E:/scratch --mode tight
python -B tools/diagnostics/round61_restart_agent_runner.py --approved-root E:/scratch --mode fixture
python -B tools/diagnostics/round61_restart_agent_runner.py --approved-root E:/scratch --mode full
```
fixture分别为类型前置修正、候选RED/GREEN、观测生命周期RED/GREEN，全部独立冻结记录。tight和full均只有一次，不再180/600盲重跑。

### tight偏差（不能掩盖）

未修改候选策略的tight运行自然达到round2，没有捕捉持续同状态lock；诊断入口当时未在baseline目标成功处截断，继续进入恢复续局，180秒外层watchdog停止，46个CHECK均true但无RESULT。因此它是诊断执行器RED，不是完整correctness。记录中续局曾达到round8，不作为最终终局证据。后补tight成功分支明确报告诊断RED，未再运行tight。最初归档误按UTF-8解码二进制FATEJNL1，真实失败保留；只读finalize重新按原字节归档/摘要校验、Job0后清generated，未重跑业务。

### full首次业务失败与原错误

`E:/scratch/isolated-c4af90c082eb43159c5dcbff9814989f`：restart51/51 CHECK，exit1，4个false。两个cleanup诊断SCRIPT ERROR与worker实际ERROR均未豁免。

1. 原target CHECK为true，真实双客户端round≥2；baseline记录19条accepted、0条match_command rejected。102条增量事件包含每个静默return首次/状态变化、seq/sent_seq/last_request/decisions/attempted/group snapshot/全部原候选/held朝向。
2. recover阶段ticks63342，客户端0收到`房间连接已断开`；真实error消息绑定恢复worker PID17248、instance`82d9c418d970d0b5acd5a5e84d1f641b`。
3. 对应worker原件：`evidence/worker/net_server_gateway_restart_test/server-match-9504-3779105/workers/925710c553fab326a8b78769470fc916/engine.82d9c418d970d0b5acd5a5e84d1f641b.log`。原错误：`存档恢复失败关闭：恢复失败并关闭会话（未回滚原对局）；请丢弃此会话并重启权威：恢复连接已取消或断开，原子恢复不可用`，调用`server_room_worker.gd:550/364/322`。
4. 恢复未完成立即短路。保存关闭cleanup未确认成功，房间登记未正常释放，Job0证明自有进程树最终退出，不将Job清理冒称正式shutdown成功。
5. client拒绝/断线、worker取消、cleanup失败是不同证据层。不能从最后错误断定是谁先取消/断连，**production根因尚unknown**；未越权改production。

交main的最小公开复现入口就是上述未篡改target/seed/预算的restart场景与本次完整冻结原件。进一步定位可使用已存在`FD_RESTORE_TRANSACTION_TRACE=1`/`FD_RECOVERY_DIAGNOSTICS=1`（执行器需要显式透传，默认清理FD变量），关联`lobby_session.gd:632/716/1914–1944`取消、原生断线及房间快照差异。建议只记录现有安全字段，保留失败关闭，不做重试、清锁或假成功。本代理不再发起恢复重跑。

### 性能和终局

tight真实60秒性能输出为false；full未进入continuation，因此本次完整运行性能门未到达，不是GREEN。原60秒RED仍保留。完整终局、最终save、最终journal尾hash验收未到达；已归档的21条记录save-close回执只证明重启前真实保存关闭，不证明终局。回执request`52d2a980cbe5a1d0b9d37d4e2c98d1c9`绑定旧PID36200/instance`05802c7944a0e28632ab889f53eea325`，不是恢复worker的终局回执。

## 冻结、归档、修改范围

- full冻结2098份明确输入，与round60共用的2069份非tests文件hash全部一致；本次full source_drift/frozen_drift均空。production/authority/transport/规则/data/原DLL/引擎只读。
- full的7个实际Job全部exited=true、active_owned_processes=0、log_handles_released=true。768份artifact逐SHA256读回；所有7个本次独占根generated均已删除，无用户进程/旧28100操作。
- stdout/stderr、worker engine/logger、错误原件、二进制journal、实际control response都已归档。Agent事件每条立即追加artifact JSONL，失败即写原诊断；控制回执由Job0后归档，未补造即时终局回执。审计汇总在full根`round61-audit.json`，位于manifest artifact index之外，不重写原执行manifest。
- 仅改`tests/net_process_full_game_test.gd`、`tests/net_server_match_test.gd`、`tests/net_server_gateway_restart_test.gd`；新增`tools/diagnostics/round61_restart_agent_runner.py`及本报告。没有98套、GUI、release验证，没有提交/推送。
- 三个net测试文件当前不在git ls-files中，git diff不提供它们的基线；修改核验使用round60原冻结字节与本次逐文件SHA256，而不是将空git diff误认零改动。git diff --check退出0。

最终测试文件hash（最终fixture实际运行冻结）：
- `tests/net_process_full_game_test.gd`: `2c65c602229872cd0919c8efb81bd2562d2b0caa91588bf3d731d7ab6c12a7e9`
- `tests/net_server_match_test.gd`: `ab91d362dbc7588bc2c8fc5e3df796b02e2d7718bb79bd4b05a2a9a11b854e7d`
- `tests/net_server_gateway_restart_test.gd`: `aff0f80cf6feb217401602c4ce1cd7e9299be58f081a688686a6f6e6d8fd7662`

已验证：候选缺陷及诊断生命周期确定性RED→GREEN、全量证据摘要/Job0/清理。仍阻断：历史停滞精确首因、恢复取消/断线首发因果、相关process开局合同、完整自然终局/save读回、原60秒性能。到此停止，不宣称整链完成。
