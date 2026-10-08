# 恢复数据屏障：只读时序追踪

## 结论

本机最新保留日志显示的不是“双方始终在线、都确认当前版但 data_ready 永远为 false”，而是**乙的网关→worker 内部连接在恢复期间断开，乙停在 revision 2；甲收到 revision 3 并确认后，权威排除了已掉线的乙，实际上已经进入 playing / data_ready=true。双方恢复目标仍不能完成，于是外层等待超时。**

这把问题定位到两层：

1. **直接阻断点有日志证据：乙的内部房间路由断开，未收到/未接受恢复最终 revision 3。** 日志没有内部 ENet 断开的原始原因，不能把 native 超时、重放阻塞或目录失败指定为已证实根因。
2. **恢复屏障语义存在静态缺口：`data_ready()` 只检查 connected 成员；恢复到 playing 的条件没有再次要求原真人全部在线。** 因此“恢复前全部重连”一旦在重放/最终清单发布期间被打破，掉线成员从检查集合消失，单端可以恢复成功。这不是本轮实施修复的报告。

本轮未运行 Godot，未更改任何生产/测试文件；仅读取当前源码和已有日志，新增本报告。网关为控制/路由面，worker 为规则权威，批准 manifest/blob 经过房间数据面；未做多机/跨网验证。

## 1. 已有运行证据及其限度

证据：`C:/Users/Administrator/AppData/Roaming/FateDomination/logs/godot.log:18-28`（读取时内容）。

- 18-24 行：崩溃前两真人绑定已持久化、worker 确实退出、两端原凭据 reconnect 调用成功、新 worker 数据校验及内部 ENet 就绪均为 true。
- 21 行：无凭据客户端不能触发恢复的断言为 **false**；这个旁支失败也必须保留，不能把本轮称为完整恢复验收通过。
- 25 行甲：error 空；view.phase=`playing`，room revision=22，data_ready=true；session.data_revision=3，files=204；权威视图中甲 connected=true、乙 connected=false。
- 26 行乙：error=`房间连接已断开`；view.phase=`restoring`，room revision=15，data_ready=false；session.data_revision=2，files=204；其最后保留视图仍显示两人 connected=true。
- 两条诊断的 `accepted=[3,2]` 是测试共享数组，表示测试端曾执行安装并尝试发送 ACK 的版本，**不是服务端接受 ACK 的回执**。两条都打印该数组，并不是双方各自拥有两个已接受版本。
- 27-28 行：双方恢复到同一局面、真实可继续中局均为 false。该日志没有最终 RESULT，也没有逐包时间戳。

因此能证明：甲已经过当前连接集合的屏障；乙最后停在中间版且内部路由报断开。不能证明：乙曾收到 revision 3、乙 ACK 3 到达、同步器错误是什么、内部路由因哪一种 ENet 原因断开。

另有 `server-dist/console-seed-save-recovery-test.log:31-44` 的历史成功 RESULT，但不是此次失败轨迹，不能混作本轮通过证据。23.46.08 的旧轮日志是“实例已停止或更换”的另一失败，也不能替代本轮第 26 行的内部路由断开事实。

## 2. data_revision 的生产与恢复时序

下述 revision 1→2→3 是最新诊断结合当前源码的路径解释，不是已有逐包 trace。

| 阶段 | 权威侧行为 | 客户端侧行为/屏障意义 |
|---|---|---|
| 崩溃前 | `_persist_recovery_state()` 保存独立 data_revision、成员凭据哈希及 player→member 绑定 | 已安装旧批准集合；恢复时不能把旧确认当新确认 |
| 启动新 worker | 逐文件验证已有 isolated data，加载固定数据，然后 host、load_recovery_state；playing 改 restoring，所有旧成员 connected=false / ready=false | 进程 ready 仅表示基础数据、监听及启动契约通过，不表示对局重放或全员屏障完成 |
| 启动清单 | 无 random_sim_enabled 配置时 `set_room_files(plan.files)` 调 `_commit_room_files()`，**在恢复保存的版本上再增版并清空确认**；随后 `_rules_revision=data_revision` | 普通当前测试配置产生中间版 2；预检配置分支不走此提交，不能固定假设所有房间都必有这一步 |
| 原成员 join/resume | reconnect 校验凭据及认证绑定；先 identity(data_revision)，后 `_send_room_files(sender)` | identity 可对“同版且已安装”自动重 ACK；新 revision 的 manifest 需要重新同步/安装 |
| 等原真人 | worker `_try_restore_match()` 检查 `_recovery_bindings` 中每个真人 connected 后才调用 restore | 此检查发生在重放入口，不是最终 playing 时再次检查 |
| 重放完成 | `restore_local_match()` 从存档初始数据重新发布 blobs、校验完整清单/安装 assets，设置 `_rules_revision=data_revision+1`，`_commit_room_files()` 再增版、清确认、广播最终清单 | 最新失败轮最终版是 3；中间版 2 的 ACK 不满足版 3 |
| 最终屏障 | host poll 要求 phase=restoring、match_authority.started、data_ready()，随后直接改 playing、bind 和发布 match | `data_ready()` 只遍历 connected 成员；乙若已断线，其 ACK 3 不再是条件 |

出处：`server_room_worker.gd:118-182,191-203,218-235,260-261`；`lobby_session.gd:244-285,380-385,828-844,1016-1060,1281-1353,1363-1365,1374-1430`。

关键排除：`_rules_revision=data_revision+1` 紧接提交增版，与最终版本对齐；甲的 data_ready=true 也反证本轮不是全局规则版本永久差一。恢复 data_revision 已接受 JSON int/整数 float 并转为 int，不应再次归因于 JSON 数值类型。

## 3. catalog → manifest → blob → ACK：各自是否是恢复依赖

### catalog（候选目录）

- 客户端 `catalog` 只能在 lobby 被权威接受，恢复阶段不能重新上传候选目录；`server_data_catalog/status` 客户端也只在 owner+lobby 处理。
- `_data_approval.configure()` 建立本机候选目录，但恢复期间 `_catalogs_changed()` 不发布，管理 prepare/commit 也要求 lobby。
- **恢复固定存档数据不依赖新的 catalog ACK 或再次 prepare/commit。** 本轮没有 catalog 拒绝日志，不能从“恢复没收到 catalog”推导死锁。
- 出处：`lobby_session.gd:506-514,587-598,730-758`；`server_data_approval.gd:21-58,183-187`。

### manifest（room_files / room_files_part）

- join 时发送一次当前清单；重放成功最终提交再发送新清单，均 channel 2。
- 客户端只接受 `revision > session.data_revision`；同版重发被忽略，这是去重契约，不是新版本收到后不升版。
- `_accept_room_files()` 替换 files、赋 data_revision、清 `_assets`，触发 changed；它不自动开始 RoomDataSync，也不自动 ACK。
- `_prepare_reconnect()` 保留 view、room_files、data_revision、安装表，只重置分片/连接/镜像状态。因此同步调用方必须区分保留旧数据与本轮新清单。
- 出处：`lobby_session.gd:188-202,579-613,1042-1060`；`transport/room_manifest_transfer.gd:50-83`。

### blob

- worker 启动先将计划文件放缓存并 publish；重放完成还按存档数据再次 publish。下载不要求 catalog 重登记或 phase=lobby。
- `_queue_blob()` 要求真实成员 connected、哈希存在、偏移及并发预算有效；`_pump_blobs()` 按 channel 2 发送 chunk。
- `RoomDataSync.poll()` 优先校验已缓存文件，只有未命中才发 blob_request；完整缓存也仍要逐条 poll，最终 assemble。断线直接 fail/cancel，失败不会自己恢复或重新 begin。
- 本轮 accepted[1]=2 说明测试曾对乙版 2 安装并尝试 ACK；不能证明全部 204 个文件都经网络重新下载，可能缓存命中。
- 出处：`lobby_session.gd:822-827,1077-1119,1397-1405`；`room_data_sync.gd:20-40,42-83,99-103`。

### data_ack / data_ready

- identity 的自动 ACK 仅在“本地版本>0、identity版本相等、assets已安装”时发生；最终升版后不会继续满足旧安装的自动 ACK 条件。
- 权威只接受 args.revision 是 int 且等于当前 data_revision，保存 `_data_confirmed[sender]`，增 room.revision 并发布。过时 ACK 2 不能确认版 3。
- 正式大厅同步安装成功才 ACK；但忽略 request 返回值，先标本地 synced。恢复测试同样先发送再把 accepted_revisions 设置为当前版，没有权威回执验证。
- `data_ready()` 检查 require_room_data 时的规则版本及所有 connected 成员（含在线观战者）；**不要求所有原真人 connected**。
- 出处：`lobby_session.gd:555-562,759-763,1016-1039`；`lobby_screen.gd:128-147`；`net_server_archive_match_test.gd:94-99`。

## 4. 直接故障链与测试为何一直等

日志与源码闭合的链条是：

`恢复中间版 2 / 两真人曾重连 → 乙内部路由失联 → 乙停留旧 view/manifest 2 → 最终提交版 3 清掉所有旧确认 → 甲安装/ACK 3 → 当前在线集合仅甲 → data_ready=true / playing → 乙没有最终 match_bind/view → 双端 _recovery_matches() 始终 false`。

其中内部路由失联的精确相对时刻未记录，不能断言断开发生在最终提交之前还是最终清单在途；能够断言乙未进入最终接受状态。

`房间连接已断开` 这个精确字符串来自 `server_gateway.gd:324-327`：当前 route 的内部 link 触发 peer_disconnected，网关发 error 并排队撤销该 route。它**不是** RoomDataSync 的“同步过程中连接中断”，也不是本地外网 transport 的“与房主连接中断”。甲随后看到乙 disconnected，与 worker 的 `_disconnected()` 删除成员确认并发布状态一致（`lobby_session.gd:479-501`）。这是目前最小、最有区分度的已证实断点。

恢复测试外循环的附加缺口（`net_server_archive_match_test.gd:74-103`）：

- 用旧 view/files 就能启动同步，未等本轮 identity 完成；accepted_revisions 初值 -1 不代表清单是新实例的。
- 若同步器运行后 fail，外循环只看 complete，不看 error/running，失败对象留在数组中；同版不会重建，能无进展地等满 180 秒。
- 一旦把乙 accepted 标为 2，且乙断线不再收新清单，则 `accepted_revisions[index] != session.data_revision` 为 false，同步器不会再推进，也不会主动重连。
- 退出条件只比较 round/phase/current_player/game_over/observer，没有明确“全员当前版 ACK 被权威接受、当前实例 playing、连接等待解除”判据。

因此当前超时不能简单命名为“data_ready 永远不完成”；应分别报告乙 route 断开、最终版缺失、全员恢复目标失败及单端屏障误放行。

## 5. 尚不能确定的上游原因与后续最小取证

此次禁止运行 Godot/修改生产代码，以下仅供父代理下一轮取证，不是已验证修复方案：

1. 优先记录每条内部 link 的 room/pid/instance/member、peer_disconnected 时刻及 transport 状态，确认乙是真正 ENet 超时/主动关闭还是被别的生命周期路径撤销；旧实例事件必须按绑定隔离。已有 route_current 防护不能由静态存在推断运行有效。
2. 同一时间轴记录 identity、manifest 完整接受、sync begin/progress/fail、ACK send 返回值、worker ACK 接受/拒绝、最终 `_commit_room_files`、原真人 connected 集合和 playing 转换。只记 revision/hash摘要/稳定ID；不要打印密钥、票据或私有牌面。
3. 收集 worker 重放开始/结束、最后一次 transport.poll、supervisor 心跳时间，以区分重放或同步文件操作阻塞与线路故障。`_maintain_restore_transport()` 已存在，不能只因恢复慢就断言它完全漏 poll。
4. 另有可证伪的跨 channel 排序风险：客户端 request 统一递增 seq，网关把 blob_request 转 channel 2、join/identity_ack/data_ack 转 channel 0，worker 却按 connection 使用一个 `_received_seq`。若高 seq blob 先到，较低 seq 控制请求会被拒为“重复或过期请求”；旧清单提前请求 blob 也可能在 join 前遭无权限拒绝，而 `_resume_inflight` 下任何 error 会关闭客户端连接。出处 `lobby_session.gd:391-402,657-661,680-694` 与 `server_gateway.gd:128-133,430-431`。**本轮日志未出现这些拒绝原因，不能将此风险认定为乙断线根因。**
5. 针对屏障语义的最小反例：两原真人完成重连后，在重放完成/最终清单 ACK 前让其中一人掉线；要求继续 restoring，不能因其退出 connected 集合就 playing。针对测试调度的反例：RoomDataSync 显式失败应立即带阶段原因失败，不应剩余预算空转。

## 交付边界

- 新增：`scratch/net-batch-13/recovery-data-barrier.md`。
- 修改生产/测试文件：无；Godot、网络恢复、解析/专项测试：均未执行。
- 已定位到有证据的内部路由断开及最终版确认缺失；上游 ENet 断开原因仍缺逐事件日志，不能称完整根因已动态验证。
