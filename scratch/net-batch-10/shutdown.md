# 安全关服与房间关闭回执只读审计

范围：`scripts/net/server/{server_console_channel,server_room_control,server_shutdown,server_room_manager}.gd`；沿调用链读取 `server_room_worker.gd`、`server_cli.gd`、`server_gateway.gd`、`lobby_session.gd`、`match_journal.gd` 及相关测试。未改生产文件，未运行 Godot。以下是静态确认，不是运行验收。

## 结论

**当前 save/close 的生产者与消费者存在直接契约冲突：worker 发布回执后删除请求，控制台却要求请求仍存在。正常完成的保存和关闭会被当作孤立回执拒绝，协调关服因此不能稳定确认成功。** 超时分支本身不强杀，但这不等于所有退出入口都安全保存。

## 发现

### S1 / 高：成功回执删除请求后必被消费者拒绝

- `server_room_control.gd:48-52`：写 `.response.json` 成功后删除 `.request.json`；close 成功随即发 `shutdown_ready` 并返回。
- `server_console_channel.gd:279-280`：回执存在时，要求相同编号 `.request.json` 也存在；否则返回“房间管理请求已丢失，拒绝使用孤立回执”。
- 同一 worker 的下一次 poll，`server_room_control.gd:24-26` 也会删除已有回执对应请求。
- `server_shutdown.gd:45-49` 将该拒绝写为失败并移除待跟踪房间。因此即使真实保存和退出成功，也不能得到可靠的 complete；只在跨进程短暂的“回执已写、请求尚未删除”窗口读取才可能通过，不能作为契约。
- `room forget`（channel:291-298）反而要求请求已删除，说明当前“结果查询”和“回执清理”也彼此矛盾。

建议：主管保留不可变的提交记录/已完成请求记录，查询用提交时绑定核对回执；或把请求移入完成记录而非删除。不要仅取消孤立回执校验而失去请求关联、动作绑定与实例校验。先修完整生命周期，再验 save、close、退出后 result、重复 result、forget。

### S2 / 中：提交路径未完整比对 ready 与主管四元组

- manager 的 `instance_binding` / `binding_matches` / `valid_ready_report`（77-106）完整绑定 room、PID、instance_id、authority_host_mode；实例别名 `instance` 也与规范字段保持一致。
- channel `_room_request`（246-266）先调用 manager.is_ready，但随后重读 ready 只检查 id、PID、instance 格式（253），不比较 `ready.instance == room.instance_id`，也不检查 ready 的 authority_host_mode。请求 instance 取自重读 ready，而 mode 取主管登记，形成混合绑定。
- worker（control:35）对请求四元组严格匹配，故该缺口通常失败关闭而不是执行到错误实例，但被替换/陈旧 ready 会让本应拒绝的管理请求先显示 pending，再被 worker 拒绝。

建议：提交前复用完整 ready 校验，固定主管 `instance_binding`；不得从未经完整核验的重读报告拼接目标。

### S3 / 中：关服协调保存了目标快照，却未用它校验回执和完成条件

- shutdown:32 保存 request_id、PID、instance_id、authority_host_mode；但 poll:45 仅按 room/request_id 调用 channel 查询，后者（286-288）比较的是**当前** manager 房间登记，不是 shutdown 提交快照。
- poll:50 只看 `result.closing`，未显式要求 `saved:true` 或大厅 `room_state_saved:true`；poll:51 用裸 `OS.is_process_running(request.pid)` 等待退出，未使用原生所有者的退出状态。当前合法 worker 的 prepare_close 保证先保存，因而正常生产者不直接产生虚假 closing；这是消费者缺少独立约束，不应夸大为已复现绕过。
- `_closed`（27、52）重试豁免仅比 PID+instance_id，未包括 mode。实例随机值通常足以隔离旧目标，但不符合完整四元组消费契约。

建议：关服协调逐字段核对提交快照与响应，明确验证保存证明分支；完成判断复用原生进程所有权/退出状态。恢复或替换登记时拒绝旧关闭协调，不将另一实例的状态混入结果。

### S4 / 中：心跳仍是三元组，退出旁路不提供保存确认

- manager `_write_supervisor`（370-383）仅写 id、PID、instance_id、version；worker（205-216）仅校验对应字段，不携带 authority_host_mode。
- worker 主管心跳超时直接 quit，不先调用 prepare_close/save，不发布 close 回执。manager poll（217-235）的启动失败/错误路径会原生 terminate；stop_room、close、析构（385-408）也是强制生命周期清理，不是安全关服。
- 这些路径与 shutdown 的“关闭等待超时不强杀”是不同入口：不能把启动超时清理误称关服超时强杀，也不能把整个服务端所有退出都称为“保存后关服”。

建议：补齐心跳 mode；明确异常退出与确认保存关服的语义边界。关服失败后继续泵送主管心跳，禁止用释放 manager/停止主管来间接替代超时不强杀。

## 静态确认符合项

- 请求、worker 校验、回执和 result 查询都有 room+PID+instance+authority_host_mode；request_id 随机 32 位小写十六进制且结果核对编号（channel:265-288；control:35、43-47）。
- 保存提交只报告 pending / saved:false（channel:267-269），不把入队当保存。
- 保存明确要求 started、recorder、无 recorder.error、当前 state_hash 与最后记录一致，再检查 journal.flush 和恢复状态持久化（control:80-88）。大厅关闭另要求 recovery 写成功；对局关闭保存失败不返回 closing（64-74）。
- worker 回执写成功后才发 shutdown_ready；worker 的实际退出入口位于 room_worker:312-314。回执发布失败不会立即关闭。
- 恢复状态使用临时文件、flush/get_error、rename 发布（lobby_session:1351-1367）；这里确认的是应用层 I/O 返回值，不声称已证明断电级持久性。
- shutdown:54-61 超时仅记失败、清跟踪、不发 completed；源码没有 OS.kill / stop_room / manager.close / terminate 调用。失败后 accepting_rooms 保持 false；CLI 每帧仍先 gateway.poll，再 shutdown.poll（server_cli:245-248），不会由此分支停止心跳。
- manager 原生所有者验证取代按 PID 任意杀进程；ready 含完整四元组，恢复换新实例/新日志并在 spawn 前清旧 ready。安全关服模块应复用而不是降回裸 PID 判断。

## 测试覆盖与待验收

- `tests/net_server_console_save_test.gd:13-20` 已有真实 worker 保存及日志哈希核对；`net_server_console_close_test.gd:19-30` 已有先保存关闭、真实退出和退出后结果读取断言。它们直接覆盖 S1，应在修复后串行执行；本次未运行，不能引用历史日志宣称当前通过。
- `tests/net_server_shutdown_failure_test.gd:16-27` 的夹具缺 instance_id、authority_host_mode、process_token，ready 也缺规范字段与 capabilities；当前 manager.is_ready 要求原生身份核验。第二阶段的 ready=true 不足以抵达真实超时分支，现有夹具不能证明当前超时契约。
- 必补：完成请求删除后查询、重复/退出后查询、孤立和旧实例回执拒绝、ready mode/instance 被替换拒绝、receipt 写失败、save hash 未记账拒绝、无录制拒绝、大厅状态保存失败、真实 pending 超时仍保活且持续心跳、超时后迟到 close 回执处理、重试目标完整绑定。

## 本次验证与文件边界

仅执行源码读取与 Python 字符串证据检查：worker 发布后删除请求=True；消费者要求请求存在=True；关服超时清跟踪=True；shutdown 直接强杀调用=False。该检查只是静态证据复核，非行为替身或运行测试。

唯一创建文件：`scratch/net-batch-10/shutdown.md`。未运行 Godot、未创建游戏数据、未修改生产代码或测试。
