# Round21 — F07 客户端 blob 收件职责迁移

## 结论与所有权

生产迁移完成；独占专项真实 RED→GREEN，最终 112 项/exit 0，无 ERROR/WARNING。真实独立 worker 两客户端内容同步、data barrier、第二轮及正式保存关闭专项 18 项/exit 0。旧直连夹具仍有红项，不能宣称全仓库 GREEN。

本轮仅修改 `scripts/net/session/lobby_session.gd` 的客户端 blob 分支，以及经真实定义确认后扩展独占权的既有 `scripts/net/content/blob_receiver.gd`。新增 `tests/client_blob_inbox_test.gd/.tscn` 和 `tests/client_blob_inbox_test.server.gd/.tscn`。没有修改 authority、mirror、UI、client_match_inbox、其他测试；content_cache/room_data_sync 原有未提交修改原样保留。未提交、未暂存、未启动窗口。注意 `.gitignore:47:/tests/` 忽略新增测试，磁盘文件存在，交付打包需要明确包含。

## 真实定义、入口与保持的契约

- `lobby_session.gd:52`：`blobs = preload("res://scripts/net/content/blob_receiver.gd").new()`；真实类为 MatchBlobReceiver，而非 content_cache 或 room_data_sync。
- 原公开原语为 `expect_blob/accept/offset_for/cancel_blob/cancel_peer`。新增 `receive_client(sender,message)`，返回同步 `{handled:bool,error?:String}`，不存 Session、Callable、第五状态，不增加总线或 signal。
- `blob_error` 的 String key 门槛、按 sender/key 取消及“请求的文件不可用”原文保持；畸形非 String key 不处理。`blob_chunk` 仅保留旧 String/int/PackedByteArray 字段门槛，分片预算、顺序、长度、SHA256、缓存发布、pin/unpin、完成回调及重入释放仍唯一调用原 `accept`，没有复制校验。
- Session 保留原 reset/restore/begin 禁入和 sender==1 来源门、F06 转发顺位，只转发同步回执并发布原 `error/rejected`。正常/畸形分块不增加 `changed`。provider_blob_request、主机 provider_blob_error、主机 accept 分支及 provider 请求、取消、发送预算均不修改。
- F06 四状态和实例方法连接的引用环修复不变；新增弱引用断言确认 Session close 后可销毁。D14、E04、E07d、D20d 通过下表真实专项复核。

## RED 与环境隔离

Godot：`D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`。

公共参数始终为 `--headless --fixed-fps 60 --path . --scene res://tests/<suite>.tscn`，cwd 为仓库根目录，每进程超时 180 秒；通过 Python subprocess 执行并读取真实 RESULT/退出码。

1. 生产代码修改前运行 client_blob_inbox_test：exit 1，`RESULT checks=1 failures=["F07 existing blobs owns public client receive entry"]`。日志 `C:/Users/Administrator/AppData/Local/hermes/cache/scratch/round21-F07-red.log`。
2. 初次 GREEN 运行：62 项中完整文件落盘失败。原回执为“缓存路径不安全”；Python 查询确认 `C:/Users/Administrator/AppData/Roaming/FateDomination` 是 junction，拒绝为原生产路径契约，未放宽。
3. Hermes scratch 本身亦为链接别名，实际物理根为 `E:/Caches/Hermes/cache/scratch`。后续仅给测试子进程设置物理 scratch 内的独占 APPDATA；不修改用户默认目录/生产配置。默认环境红日志 `round21-F07-green.log` 仍保留。
4. 最终测试 APPDATA=`E:/Caches/Hermes/cache/scratch/round21-F07-appdata`，112 项、exit 0；包含本地明确批准后真实 ENet→Session→blobs 多块下载落盘、畸形字段、错来源、乱序、取消后的迟到块、空块、哈希错误、blob_error、原错误发布、无 changed 和弱引用销毁。日志 `E:/Caches/Hermes/cache/scratch/round21-F07-green-final.log`。纯传输段不调用 join、不伪造身份认证；完整房间/worker 链另由服务端专项验证。

## GREEN 专项

以下全部 exit 0，日志未发现 SCRIPT ERROR/ERROR/WARNING。

| 专项 | checks | 日志目录 |
|---|---:|---|
| client_blob_inbox_test | 112 | 物理 scratch/round21-F07-green-final.log |
| client_blob_inbox_test.server | 18 | round21-F07-server-green/server-green.log |
| net_blob_test（真实 ENet） | 42 | round21-F07-regression |
| net_blob_concurrent_test（预算、生命周期） | 20 | round21-F07-regression |
| net_local_hash_sync_feedback_test | 7 | round21-F07-regression |
| net_sync_error_feedback_test | 4 | round21-F07-regression |
| net_ready_sync_feedback_test | 8 | round21-F07-regression |
| client_match_inbox_contract_test | 45（另输出原34项） | round21-F07-regression |
| lobby_content_environment_restore_test | 1544 | round21-F07-regression |
| replay_restore_batch_test | 40 | round21-F07-regression |
| authenticated_key_reconnect_test | 34 | round21-F07-contracts |
| authenticated_restart_reconnect_test seed/resume（两次独立进程） | 5/13 | round21-F07-restart/seed.log、resume.log |
| match_command_result_protocol_test | 39 | round21-F07-contracts |
| broadcast_absent_confirmation_test | 56 | round21-F07-contracts |
| match_finished_lobby_test | 41 | round21-F07-contracts |

物理 scratch=`E:/Caches/Hermes/cache/scratch`；目录内非独占专项日志名为 `<suite>.log`。分组原始机器可读结果为 regression/summary.json、contracts/summary.json；它们保留最初失败的前置调用，不覆盖为后来通过。

服务端专项执行参数另含 `-- E:/Caches/Hermes/cache/scratch/round21-F07-server-green`，子进程环境 FATE_TEST_SCRATCH_ROOT 指向同根、APPDATA 指向该根/appdata。派生夹具只复用原 server_round 并显式设置 `gateway.manager.record_matches=true`。真实核验：两个客户端采用服务端完整清单并下载组装/校验、双方 data_ack 后才开放准备屏障、第二轮真实指令与私有手牌过滤、客户端不执行规则、关闭保存回执/原生 EXITED/所有权释放。

跨进程恢复调用额外参数依次为 `-- seed E:/Caches/Hermes/cache/scratch/round21-F07-restart`、`-- resume E:/Caches/Hermes/cache/scratch/round21-F07-restart`，共享隔离身份/恢复目录，不打印密钥或票据。

## 保留的红项与边界

- net_blob_authorization_test：exit 1，4 项，三个旧直连端点未加入；net_data_sync_test：exit 1，8 项，真实下载/组装及既存目标断言失败。旧 `host/join` 夹具没有当前客户端 LAN 认证前置；没有改身份门让它们通过。
- net_blob_send_authorization_test：180 秒超时，无 RESULT；首个连接断言失败后访问不存在成员 Dictionary（日志中一处 SCRIPT ERROR）。net_lobby_concurrent_upload_test：180 秒超时，无 RESULT，认证前置失败后重复不存在成员访问。未修改其他代理测试或 provider 生产逻辑。
- 最初 server_round 无批准物理 scratch 参数时 fail-fast，随后补精确参数运行；内容/data barrier/第二轮通过，但派生 `_configure_gateway` 未启用录制，正式关闭报“当前对局未启用录制”。旧红日志 `round21-F07-server-round/server-round.log` 保留。新独占服务端场景显式打开原录制配置后18项干净GREEN。
- 旧失败运行 worker PID 35660、instance_id 8a22eea78731a6fdbd82953a9394c1bd；当次关闭不能声称释放。后续 CIM 系统查询已无该 PID，也无本次两个超时专项命令行；没有强杀其他代理进程或删除它们目录。
- 默认 user:// junction 环境没有修复；隔离环境通过不等于默认路径已可用。没有窗口、多机或跨网验收。

## 差异与交付复核

`git diff --check -- scripts/net/session/lobby_session.gd scripts/net/content/blob_receiver.gd` exit 0。receiver 的生产差异仅新增13行客户端入口；session 的全工作树 diff 含已有 D14/F06/E04/E07d/D20d 等修改，不能全部归属本轮。当前测试与报告已落盘，保留所有原有未提交修改。复用夹具覆盖配置导致录制缺失的经验已补入默认 profile 的 godot-recovery-validation-fixtures 技能。
