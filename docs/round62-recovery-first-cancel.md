# Round62：一次窄恢复 first-cancel 因果捕获

## 结论

本次实际首触发是 **恢复 worker 内的原生 ENet peer_disconnected**；`LobbySession._disconnected()` 随后锁存取消，不是客户端大厅 phase 变更直接取消，也不是 fixture cleanup 的显式 close 先发生。只证明这一取消因果；**原生为何断开仍 unknown，生产 bug/修复均未证实**。

唯一 scene 在 66.389 秒结束，exit1，唯一 RESULT 51 CHECK / 4 false；没有 SCRIPT ERROR/freed-instance error。worker 的真实 fail-closed ERROR 原样保留。恢复尚未提交完整镜像/新数据 ACK；没有 continuation、自然终局或最终 save，不能叫 sourcePASS。

## 预先假设及实际判定

1. **H1：lobby snapshot phase/revision 变化触发客户端取消。** 预测：快照变更后先见 close/请求世代撤销，再见 native disconnect。实际双方接受 restoring/revision15 后仍 authenticated、generation2、connected；首 native 回调入口 cancelled=false、changed_paths=[]。未出现快照触发的 close，H1 不支持。
2. **H2：transport 原生先断开。** 预测：worker 原生回调先见 cancelled=false，之后同事务锁存 cancelled=true/成员离线。原件严格出现这一顺序，H2 支持。
3. **H3：fixture owner/late 回调先结束会话。** 预测：恢复期间显式 close 的调用栈/请求换代先于失败。真实 cleanup close 在 clienterror 后、generation3，来源 `net_server_match_test.gd:230`，H3 不支持。此前 generation2 的 prepare_reconnect 是原公开重连入口，并非取消。

## 一次真实运行及 scope

```text
python -B tools/diagnostics/round61_restart_agent_runner.py --approved-root E:/scratch --mode first-cancel
```

独占根：`E:/scratch/isolated-7ee7ee28648c4e36a3b71869a8234316/`。

- 执行器只选 restart 一个 scene、runs=1、外层 ceiling600；原 target、选人/Agent、规则预算、seed、原DLL/引擎及生产代码未由本代理改动。
- 先物理E/path/Job监督探针及独占冷 import；没有 warm/retry、98套或 GUI，没有操作用户28100。
- 原真实两真人 RSA、原生 worker ready、正式数据逐文件同步/安装/ACK、真实规则到 round≥2、真实 save-close/EXITED/release、磁盘发现/原凭据 reconnect 均经过原入口。没有注入 accepted/pending/认证身份。
- 默认继承的 FD/FATE/ROUND 环境仍清理；仅本 case 显式设置 `FATE_R62_FIRST_CANCEL=1`、`FD_RESTORE_TRANSACTION_TRACE=1`、`FD_RECOVERY_DIAGNOSTICS=1`。主引擎 stdout第6行 `R62_ENGINE_SCOPE` 亲见两个旗标均为1；恢复worker真实输出 `RECOVERY_STAGE`、`RESTORE_TRANSACTION`、`RECOVERY_NET`，证明透传到子进程，不以日志模拟事件。
- 现成 public scene 的 baseline 是当前最小可用同timeline入口；未为紧化改原目标。恢复返回失败即短路；恢复若成功也诊断false即止，不能进入440秒continuation。

## 首取消精确链

恢复 room=`72feada342f2b82d471d4c72e4aa7b22`、PID38932、instance=`a5dc8ec601cd056fa7fd77908d1f427f`。

worker原件（相对独占根）：
`evidence/worker/net_server_gateway_restart_test/server-match-10804-3953268/workers/72feada342f2b82d471d4c72e4aa7b22/engine.a5dc8ec601cd056fa7fd77908d1f427f.log`。

|原件行号 / worker单调ticks_usec|真实事实|
|---|---|
|11–16|两条内部连接经 `_accept_identity` 保存并交付原成员身份；connection1077362028→member1989513435、connection988510555→member2111426756，sent=OK。客户端双方实际 RSA authenticated=true。|
|29–30 / 10447628、10449093|transaction1进入及 await_before；phase restoring、revision15、owner1989513435，两成员在线、cancelled=false、无changed_paths。|
|31–33|maintenance polls1/1001/2001均 maintained=true、same_snapshot=true。|
|34 / 12058491|ENet `peer_disconnected`，远端988510555；服务端整体 connection_status仍2，不意味着该远端还在线。|
|35 / 12058744|`_disconnected`入口：transaction1、member2111426756、phase restoring/revision15、cancelled=false、changed_paths=[]、两个成员仍在线。|
|36 / 12058983|维护返回：cancelled=true、revision16；仅 `revision`、`members/2111426756/connected` 变化，maintained=false/same_snapshot=false。|
|37–38|await_after recovered=false，随后 checkpoint_before_reject。|
|39 / 12172887|才见 worker transport close_requested（fail-closed出口）。|
|40–46|replay_return=false及原真实ERROR/worker源码回溯。|

准确源码路径（本次冻结与当前hash相同）：
`enet_transport.gd:_on_disconnected():81–85 → LobbySession._disconnected():714–716（716锁存取消）→ room.mark_disconnected():728 → _restore_checkpoint():1938–1944 → _fail_closed_restore():1902–1911`。
原生服务调用入口是 `enet_transport.gd:keep_alive():94 peer.poll()`；没有请求令牌触发这个 native callback。worker在这一时刻的业务请求seq未由既有trace暴露，不能拿客户端发送水位伪称worker实际在执行的request。

客户端/网关原件：`evidence/net_server_gateway_restart_test/agent-events.jsonl`，event_seq1–121连续核对；附 source/currentphase/request/generation/native-instance 安全字段和 close栈。

- event115：客户端1 member2111426756、内部peer988510555、外部peer1898508167，generation2/request45、authenticated/connected=true、phase restoring/revision15；后续清理水位46不是失败回执绑定号。
- event116：网关另一内部路由（客户端0 external485481343/internal1077362028）收到 native disconnect；栈 `enet_transport.gd:85/94/106 → server_gateway.gd:102 → restart_test.gd:377`。这是 worker fail-closed后另一链路的下游断开观察，不把它混作worker首断线member。
- event117–119：真实客户端0 error=`房间连接已断开`，generation2/request水位251、phase restoring/revision15、外部网关链路仍connected/authenticated；error回执 `request_seq=-1`，绑定PID38932/新instance。来源 `server_gateway.gd:119 → _fail():494–497`，客户端处理 `lobby_session.gd:878`。它不是有正请求序号的业务拒绝，不能兼容消费/忽略。
- event120–121：**此后** fixture cleanup才 `session.close()`，generation3；栈 `lobby_session.gd:637 → net_server_match_test.gd:230/106`。不是restorepending期间的fixture explicitclose，故不改fixture生命周期。

worker与客户端的ticks是不同进程起点，不能按数字跨进程硬排序；worker物理行号/transaction与客户端event_seq各自定义顺序，再按room/instance/member/connection绑定消息链。新增route探针初次接线时 internal_peer为0（尚未连接）；准确真实internal-peer取既有 RECOVERY_NET/客户端状态，不将0冒作最终身份。

## 保留的未知及主接可证伪fixture

- 原生断线具体原因、ENet内部超时/断线请求来源仍未暴露。主stdout714/717/720/722/724行记录约4.95秒真实poll gap，但无调用区间定位/timeout getter，**不能把gap直接判成timeout根因**；未调用timeout setter，未重试或改transport。
- 未证生产bug，因此不提交生产patch建议。下一主接fixture可复用此次同真实认证/saveclose/recover链，仅断言：自然路径不出现 native_disconnected；另以真实已认证内部ENet连接关闭做负向，必须出现相同member的native callback→cancel→revision变化→fail-closed。禁止注入accepted/pending或清取消锁。只有找到具体不应关闭的调用点/原生原因后再给单一最小patch；本轮不再执行该fixture或长scene。
- 完整恢复提交、新数据ACK/镜像等价、终局及最终管理save仍未到达，保留原目标。

## 保存关闭回执及冻结差异

重启前真实落盘response：
`.../control/a6589032e2bd0aab8a6a9508f7a37bdf.response.json`；SHA256=`d8c5a6c7383d3116e37d2a693fb6e5ce8a7f552620c7964a3def56bb0fbc0558`，saved=true/closing=true/records19，绑定旧PID25380、旧instance7af8672ed23f51f5c3d399c98a7c86f6、原room/request/mode。它只证明真实重启前保存关闭，不是恢复成功或终局save。

本次2094份明确输入；source=start→end drift=[]、frozen_drift=[]，额外读回 current_vs_end drift=[]。相对round61原full的生产树**确有另外actor修改的两份GD**：

- `room_data_validation_worker.gd`：`afbcbb5d94cffd60db27d74ba7a2a27ea5b0db052481ab201b35a32e9e93631b` → `a3d94c8af2723022d62420ed5cf81486711425c72c7a90232e246f2ce05d793a`。
- `load_game.gd`：`4d41443a38b2894ec414290313ba3b4a3208ce64baafaeaa7592c23056e12a99` → `2a78f90ac18bd76ea2ea3181349d069874bda5df3ce8280134e17f9ef17c92e5`。

因此不把原full与此次冒称同冻结。此次worker实际恢复依赖仍 `server_room_worker.gd:287–290 _load_process_content() → LoadGame.reload_game()` **无参合同**；load_game新增error_sink默认Callable为空，未向此恢复注入validationworker错误收集。`server_data_approval.poll():110` actor0返回，本fixture未发server_data_prepare，恢复无需启动validationworker；没有混入其GREEN/验收。生产authority/transport/server_room_worker与原fullhash一致。

## 归档与修改边界

- `manifest.json`保存command、start/end/current冻结hash、flags/scope、引擎/DLL摘要、唯一RESULT、Job回执和762份artifact逐SHA256；全部读回true。
- 三个真实Job（probe/import/scene）均 exited=true、active_owned_processes=0、log_handles_released=true；scene无budget_failure。只在Job0后删除本次generated，旧round61原档/证据未动；本次原/恢复journal二进制、真实controlresponse、worker/主stdout/stderr及源码原件已保留。
- 追加只读分析 `round62-first-cancel-readback.json` 在独占根（不改原manifest），明确记录worker真实ERROR；主suite errors=[]不冒称worker无错误。运行后安全关闭失败及房间登记未释放仍RED，Job0不是正式shutdown成功。
- 仅修改仓库 `tools/diagnostics/round61_restart_agent_runner.py`、`tests/net_server_gateway_restart_test.gd`诊断，新增本报告。readonly `tests/net_process_full_game_test.gd` hash仍 `2c65c602229872cd0919c8efb81bd2562d2b0caa91588bf3d731d7ab6c12a7e9`，无越权生产修复。
- 实际执行冻结hash：runner=`13cc36d9fe6414692ad764f5c103b5342a9c61a0b932be1dea86127a9aff62e5`；restart GD=`f5c25d584886153de2f2363cdc2f91384a05346b3278eeb9d55e6ad7e518cbcd`。源码归档包含 `evidence/executor.py`，冷import和诊断scene实际检验本版。
- 这两个文件不在git tracked基线中；不把空git diff当零改动。限定路径 `git -c core.safecrlf=false diff --check` exit0；全工作树check最初因已有CRLF警告exit2，未修其他文件。没有提交/推送。
