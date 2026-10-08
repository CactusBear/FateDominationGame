# 恢复期间 transport / blob pump 审计

## 结论

**静态确认：当前代码没有“进入 restoring 就停止 poll/pump，再等待 data_ack”的必然互锁。** 正常等待重连、异步重放让帧、恢复完成后的数据屏障期间，transport.poll 和 blob pump 都有推进路径；data_ack / blob_request 也未被 restoring 阶段拒绝。

**但不能说整个恢复过程持续运行网络。** 恢复副本复制、日志读取/校验、开局重建、单条规则执行、恢复另存和内容发布仍有同步长区间，期间没有维护回调。若这些区间过长，会导致客户端同步超时、连接掉线；若某次 blob_chunk 发送失败，发送任务直接丢弃且客户端不自动重试，数据屏障可无限等待。因此“目录/文件 ack 永远不完成”不是恢复状态直接停泵的必然结果，却仍存在失败后恢复屏障无退出路径的风险。

审计对象是工作树（HEAD `8b46af0e4064cfcbe465bd8c06e87bc1428bf058`）；相关网络文件当前为未跟踪文件，match_replay.gd 有工作树修改，结论不代表 HEAD 原始版本。按要求未运行 Godot，以下均为源码证据，非运行验收。

## 调用链与状态

1. `server_room_worker.gd:155-164` 先 host，再 load_recovery_state；LAN/P2P 有既存恢复文件时在 `86-90` 安全拒绝启动，不进入此次恢复流程。
2. `lobby_session.gd:1330-1339` 将成员全部置为未连接，旧 playing 改为 restoring。
3. worker `_process` 在 `218-223` 先执行 session.poll / 数据批准 poll / 控制 poll，再尝试恢复。`_try_restore_match:231-235` 发现任一原真人未重连就重置 `_recovery_attempted` 并返回，**没有阻塞循环**，下一帧继续网络服务。
4. worker `260` await restore_local_match；调用前 `_recovery_attempted=true`（226），防止让帧时逐帧重复启动恢复。await 的调用者是普通 `_process`，没有关闭处理或暂停 SceneTree；真实让帧时后续 `_process` 仍可执行。
5. `lobby_session.poll:364-370` 无 phase 门禁地调用 transport.poll 和 `_pump_blobs`。只有权威规则 step 限于 playing（378），并非网络限于 playing。
6. `restore_local_match:1382-1386` 发布 restoring，并将 `_maintain_restore_transport` 显式传给 candidate.restore_archive。
7. `match_authority.restore_archive:467,484` 将 Callable 继续传给 match_replay.restore。
8. `match_replay._restore:201-236` 每条记录成功重放/校验后调用 maintenance。frames 记录在 `222-224` await 两次 process_frame，普通操作调用 `_execute`（230）；普通操作之间维护网络，但没有逐操作固定让帧。
9. `_maintain_restore_transport:1427-1430` 在主机会话且 phase=restoring 时执行 **transport.poll + `_pump_blobs`**，并不调用 match_authority.step，也不提前进入 playing。
10. 恢复成功后 `restore_local_match:1419-1424` 才采用已启动的 candidate、设置 `_rules_revision=data_revision+1` 并提交清单。`_commit_room_files:1021-1030` 增加数据版本、清空旧确认、向已连接成员发送新版清单。
11. 后续普通 `session.poll:380-385` 等待 started + data_ready，再切 playing、绑定并发布对局；等待期间仍先 poll/pump。

## ACK 实际闭环

- worker 的 transport 是主机 listen 后的 ENet，`enet_transport.is_connected_to_host:160-161` 判断底层 CONNECTION_CONNECTED，不是检查存在某个已连接客机。因此不能因为函数名就认定主机没有客机时无法轮询。其 Godot 实际状态变化仍需运行验证。
- transport.poll `83-92` 先 `_peer.poll()`，再有预算地读包、派发消息；正常 poll 与维护回调都能驱动这一入口。
- 恢复清单由 `_send_room_files:1042-1053` 编码并走通道 2 发出。这里没有独立的“目录 ack”；恢复数据屏障使用最终 `data_ack`。候选 catalog 消息 `744-757` 限制大厅，不属于恢复文件清单确认，不能混为一谈。
- `blob_request:822-827` 没有 phase 门禁，调用 `_queue_blob`；后者 `1097-1106` 检查已连接成员、已发布 hash 和队列预算，不要求 lobby/playing。
- `_pump_blobs:1109-1119` 每次按 blob_chunks_per_poll 推进；默认值 `lobby_session:42` 为 2，不是一次发送全部文件。
- 客户端 `lobby_screen._process:115-138` 先 session.poll，再 data_sync.poll；同步完成且版本相同、资产安装成功后发送 data_ack（132-134）。同步按钮 `_sync_data:140-146` 未排除 restoring。
- 服务端 `data_ack:759-763` 校验当前 data_revision，不检查 phase，因此 restoring 可以收取确认。`data_ready:1032-1040` 检查规则版本和全部已连接成员确认，包括观众，不只原真人。
- 这是“服务数据 → 客户端校验安装 → 最终确认 → 开放对局”，没有“必须先 playing 才能取文件/确认”的循环依赖。

## 风险与边界

### R1：同步区间无网络维护，长恢复可能造成同步/连接失败（静态确认）

维护不是定时线程，只在成功重放记录边界调用。以下区间没有 transport maintenance 或 process_frame：

- worker `236-259` 扫描/路径验证/创建恢复副本；`_copy_recovery_tree:263-306` 同步递归读写并反复哈希，限制总字节/单文件/条目数，但没有时间片与让帧。
- match_authority `471-483` 全量读取日志、验证头和座位。
- match_replay `166-200` 日志/事务链/manifest 校验、`_start` 和初始状态哈希；单条 `_execute`（230）以及相邻 state_hash 也没有内部维护保障。
- replay `238-253` 尾部哈希/校验，以及 `save_restored_as:256-297` 复制数据、读写/校验日志；authority `484` 的 resume_recording / flush_audit。
- lobby `1397-1414` 全量读出和发布恢复文件、检查资产。

这意味着超长单条规则或 I/O 卡住时，正常 `_process` 与维护回调都无法运行。客户端 RoomDataSync `82-83` 用墙钟判断无进展超时，默认 30 秒（5）；它可在另一客户端进程继续轮询时失败。副本复制上限不是耗时上限。

此外维护回调仅服务 transport/blob，不刷新 worker 主管心跳、不执行 `_control.poll` / `_data_approval.poll` / session 的 manifest/catalog expire。即使重放条目边界仍在泵网络，长时间不让帧仍可能延迟管理/主管检查。主管文件在恢复期间持续更新是否导致实际退出，依赖外部监督调度，不能仅凭此文件断言。

### R2：blob 发送失败后丢任务，恢复数据屏障无超时/失败出口（静态确认）

`_pump_blobs:1113-1119` 先 pop_front；仅 `result==OK && end<bytes.size()` 才重排后续任务。result 非 OK 时既不重试，也不发 blob_error。RoomDataSync `67-83` 一次下载请求后只观察 offset，直至超时；`_fail:99-103` 取消同步，不发送成功 data_ack。

服务端继续在 `poll:380` 等 data_ready；`data_ready:1037-1039` 对仍连接但未确认的成员始终返回 false，未见恢复数据屏障自己的超时、失败状态或踢出/重试策略。因此具体发送失败或客户端同步超时后，房间可以无限留在 restoring；不是 transport/pump 不再调用，而是已无任务或成功确认可推进。

lobby 界面同步依赖用户点击，`_refresh:479,552-553` 提示新版数据并允许同步，没有自动开始恢复同步的调用。未点击、同步失败后未重试的已连接玩家/观众也可以让屏障长期等待。不得把这种等待诊断成网络停止。

### R3：单条规则不返回时，维护无法救活（边界）

maintenance 在 `_execute` 返回并且后置哈希成功后才调用。它不提供强制抢占、超时或线程隔离。无限循环/原生不可暂停的规则阻塞仍会导致真正的永久停泵。是否存在可触发的具体规则死循环不在本次审计范围，不能宣称已复现。

## 已有测试覆盖与缺口

`tests/net_lobby_archive_test.gd:24-39` 有实际恢复→清单同步→data_ack→playing 的专项源码；恢复后 `28` 明确检查 restoring 期间没有提前推进 AI/发送对局，`33-35` 显式轮询双方并推进同步。

它不能证明长恢复期间持续轮询：在 restore_local_match 返回后才开始文件同步，没有覆盖复制阻塞、长记录重放时在途 blob、维护回调计数、发送失败重试或恢复屏障超时。该套件也不是 dedicated worker 崩溃重启完整链。本次只读取测试，未运行。

建议主代理后续验证：

- 已有在途 blob + 大量非 frames 重放记录，断言维护期间请求和下载偏移继续增长；保证 candidate 的规则 step 不被触发。
- 长复制/单记录/另存压力下分别记录最后 transport poll、pump、主管维护时间，验证时间片策略，不仅以最终成功断言代替持续活性。
- 注入一次 blob_chunk 发送错误，验证可重试或显式失败，不能静默留在 restoring。
- 原真人已重连但观众未确认、用户未点击同步、客户端同步超时等情形，验证明确等待文案与可恢复/退出机制。

## 交付范围

仅新增本审计 Markdown；未修改生产代码、未创建 GDScript 探针、未运行 Godot。结论是源码调用链与失败路径审计，不是网络、多机、重启或运行性能验收。
