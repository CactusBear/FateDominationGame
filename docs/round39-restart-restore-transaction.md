# Round39 restart / restore 事务诊断

## 当前结论

- **旧 round36 偶发 maintenance=false 尚未复现，不能宣称原根因已经修复。** 两次真实 180 秒诊断均成功恢复中局，事务 enter / await 前后 / 维护快照一致，身份复连在事务进入之前结束。原 60 秒完整终局断言仍 RED，原失败日志完整保留。
- 已实证另一个真实恢复安全缺陷：await 返回后关闭 ENet、不触发会话断线回调时，完整 room snapshot 不变、`_host=true`、取消位仍 false；旧维护代码未检查实际链路，错误提交候选。专项 RED 后做最小修复：维护前后检查真实链路并锁存取消，保留完整 snapshot 比较及全部原子提交门。
- 修复后事务专项真实 Godot exit 0，`RESULT checks=61 failures=[]`。self_publish 正例；owner / 正式 settings / 断线事件 / 真 ENet 关闭 / 未知成员字段全部分别验证。没有自动重放身份。
- 首次 600 秒正确性运行已自然终局，但测试新增 save 命令语序写错导致唯一 RED；不是生产提前 saved。精确短 save 前置修复后真实 Godot exit 0，28 checks；pending -> 完整实例绑定落盘回执 -> 19 条 journal 尾 hash/records 全部吻合。
- **最终完整正确性 GREEN：600 秒硬上限内真实 scene 用时 240.337 秒，exit 0 / `RESULT checks=61 failures=[]`。** 原 worker PID 29468 → 新 PID 31928；两名客户端新权威严格镜像、双方新操作、完整自然终局、正式 save 的 192 条 journal 尾 hash / records 全部通过。源码漂移 `[]`；主/worker 日志没有脚本或引擎错误。原 60 秒性能门 `passed=false`，没有以正确性 GREEN 冒充性能通过。
- 最终批准根/错钥负向另跑：bad-root exit 1 / 1 check、wrong-key exit 1 / 5 checks，均实际 fail-fast，无引擎错误，编排器 exit 0。错钥沿真实注册认证入口返回“用户名已被使用”，没有以旧用户名认领旧密钥身份；不冒称已经覆盖对局内换钥继承流程。

## 改前中文 V4A 与耦合边界

先重新读取 `hermesWarning.txt`、工作树、round36 说明和原始 diagnostic / green 日志；其他 owner 的广泛未提交改动不归本轮。写入仅限拥有的 `lobby_session.gd`、`net_server_gateway_restart_test.gd`、`round36_gateway_run.py`、独占新事务测试及本报告；`server_room_worker.gd` 实际只读，其他生产/测试只读。

1. 会话诊断只在 `FD_RESTORE_TRANSACTION_TRACE=1` 开启，输出 PID、事务编号、单调时间、owner/phase/revision、稳定 member 在线/准备位、差异路径、连接事件和维护结果。不序列化身份认证上下文、密钥、恢复票据、nonce 或身份指纹。未知字段输出通用路径而非任意内容。
2. 原生维护函数仍不取业务包、不分派规则命令。新增链路存在检查不把 keep_alive 忙栈返回值机械判为断线。真断开锁存取消，外层事务统一失败关闭；不在维护栈销毁规则。
3. checkpoint 仍比较同一 room 对象及整个 snapshot，维护前后都比较；并发 owner/settings/member/未知字段变化仍拒绝。自发布 `_publish()` 在事务内原守卫不变，不人为改基线；正式 room commit 后仍使用正式 committed_snapshot，不比较旧输入 snapshot。
4. 新事务测试复用真实 Authority / Journal / 正式选人和已采用数据入口；仅独占 Session 子类在正式 `archive_return` 阶段注入。初始小存档可能同步恢复，不能把 `await` 当必定让出帧。首次无效下一帧夹具 RED 保留，但不把它当生产根因证据。
5. restart 复用现有 LAN Agent 朝向修复：首候选在本人正式 held_cards 中读取 actual concealed，再验证 modes；未改 Agent、GroupSelection 或规则。
6. 长正确性有 600 秒 Windows Job 硬上限、440 秒续局阶段预算、每 15 秒进度日志及 90 秒无权威 seq 推进看门狗；decisions、预览和重复尝试不续命。非正常出口保存本人完整 view/pending/actions/sent_seq/last_request。没有缩短正式回合，没有制造 game_over。
7. 正式 save 经 `server_console_channel`，读取真实 request/room/PID/instance/mode 绑定回执；最终读回磁盘文件，再读整个 match.log 并核对尾 `after`（初始档为 initial_hash）及 records。pending 和已完成回执按不同协议分支处理，但最终证明相同。

## 最小差异与原因分类

|场景|同一事务差异|行为 / 判断|
|---|---|---|
|真实诊断复连|两名旧 member 经新 connection 复连，revision 在 enter 前完成；enter/await 前后一致|未见身份事件在恢复内变更 snapshot，不能归因复连时序|
|事务 self_publish|差异路径空，取消 false|原 publish 守卫正确；不是外部变化|
|owner 注入|仅 owner|完整 snapshot 前检查拒绝，合理并发取消|
|正式 settings 注入|revision、settings/spectator_limit|正式设置入口实际改变配置，拒绝|
|断线事件注入|revision、members/1/connected，取消 true|复用正式事件处理器的确定性注入，不冒称真实对端断线|
|真 ENet 关闭|snapshot 不变，旧取消 false；实际链路已关闭|唯一有效专项 RED；修复后 transport_unavailable 锁存取消并失败关闭|
|未知成员字段|members/1/unknown_field|保留整个 snapshot 保护，拒绝|

旧 round36 的 `恢复期间房间已变化` 是一个合并出口文案，同时覆盖 snapshot/host/取消等条件；旧日志没有同事务差异，不能从这句话推导确切原因。本轮将维护原因分开，未来若再发生可区分原生断开/取消与真实 snapshot 变化。**本轮新 ENet 漏检缺陷与旧偶发 failclosed 不是同一个已证根因。**

## 原始命令与证据

仓库根：`E:/Projects/Godot/FateDominationGame-master`。真实场景 argv、冻结源 SHA-256、引擎 SHA-256、PID、退出码、耗时、主/子 user-root 回执、日志 hash 和清理状态见 manifest。

```text
python -B tests/round36_gateway_run.py diagnostic-restart
python -B tests/round36_gateway_run.py transaction
python -B tests/round36_gateway_run.py save-preflight
python -B tests/round36_gateway_run.py correctness-restart
python -B tests/round36_gateway_run.py security-restart
```

|证据目录（reports/refactoring 下）|结论|
|---|---|
|round36-gateway-diagnostic-restart-33427d3c1c644e0fb8a0a6a1a284a298|真实恢复成功；60 秒终局门 RED；exit 1 / 55 checks|
|round36-gateway-diagnostic-restart-d2d2b7fec4464856b470c08547d53b9b|第二次真实恢复成功；60 秒终局门 RED；exit 1 / 55 checks|
|round36-gateway-transaction-89f50cddcf004c50809d1b204d280d90|夹具误以为 await 必让出帧的无效 RED，保留且不作为生产证明|
|round36-gateway-transaction-4cce0f6fec6e4929915fe8f36289ae6a|有效 RED：61 checks，只有真 ENet 关闭的两条闭锁断言失败|
|round36-gateway-transaction-14fea24ca5594580bd3597eca23d017c|最小生产修复后 GREEN：exit 0 / 61 checks|
|round36-gateway-correctness-restart-fa5b7514b7404a63a0100a0afbbc5228|自然终局完成；新增 save 命令语序错误，唯一 RED；exit 1 / 57 checks|
|round36-gateway-save-preflight-70a9ec00c4924e8b994bed24b040d310|精确短 save 前置 GREEN：exit 0 / 28 checks，不作为 restart/终局通过证据|
|round36-gateway-correctness-restart-fd397e5f782d416b9175f258a8851337|最终完整正确性 GREEN：exit 0 / 61 checks / 240.337秒，60秒性能门仍RED|
|round36-gateway-security-restart-32c1260a239144338f0fd144b057e9da|坏根/错钥均真实预期拒绝，编排器exit 0|

save RED 的精确原因：解析器要求 `room <room_id> save` / `room <room_id> result <request_id>`；新增测试写成 `room save <room_id>`，在 handler 前返回未知命令，因此主日志没有 `SERVER_CONSOLE room save`。短专项修正语序后确实先得到 `status=pending,saved=false`，最终才得到落盘 `saved=true`。没有删除最终回执/hash 断言，没有修改 manager 或生产 save。

### 最终同一运行的正确性证据

- 主 scene PID **30808**；原 worker **29468**，恢复 worker **31928**；当前实例 `c84316a8307fdab0b08b615912f6238a`。实例文件/原生拥有、新实例就绪、旧PID/instance请求拒绝均由真实manager查询验证。
- 原60秒性能门：`budget_seconds=60, elapsed_msec=60006, passed=false`。续局15秒诊断中 round / 双方 seq 依次为 3:68/69、4:131/132、5:191/192、6:245/246、7:296/297、8:350/351、9:395/396、10:440/441、11:482/483；之后双方game_over为true。不是空转尝试或修改回合数。
- 正式save request `db2c16fb1492d53cdce7ca5fecef5168`，房间 `3eff8fd957e59d6de4e002fa1e67d632`，回执绑定恢复worker PID31928及上述instance；先pending/saved=false，随后落盘完整saved=true。
- 最终192条journal尾规则hash：`712a9fa8be02f4d760293c1a10708c735c3ced297f5e4f189a3c664e8ae3f6f0`，等于save回执state_hash。完整journal文件SHA-256：`3f9d2f2ce6c223293770beb8d245ff890d8f6dccc40a46063365054d2d1c4707`。这些是对局/文件完整性hash，不是身份指纹。
- 归档回执和摘要在最终证据目录 `worker/net_server_gateway_restart_test/server-match-30808-3984553/round39-final-save.json`，完整journal/transactions和control响应也保留；`game_over=true`。
- 同一冻结source_drift=[]；真实probe/import/scene退出码均0，进程树active_owned_processes=0，日志句柄释放，generated_removed。

## 安全、归档与未完成项

- 全部运行复用真实物理 E 独占 UUID 根，实际复制 E 引擎；APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR 仅子环境物理 E 路径。正式批准数据根仍先于恢复，凭据/稳定 member 仍由现有认证入口决定。
- Windows Job 拥有进程树，硬上限只清理本次拥有进程；不按名称或裸 PID 批杀。日志、worker 控制回执、恢复文件、journal 和逐文件 hash 先归档再回收独占 generated。具体退出/release、零活跃进程证明在各 manifest。
- 原 round36 证据和本轮所有 RED 保留。未复现旧偶发失败，不通过挑成功运行声称恢复已稳定。
- 未作 GUI、跨机、跨网验收；专项断线事件处理器注入与真实 ENet 关闭分别标注。
