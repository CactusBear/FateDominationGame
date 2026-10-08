# 数据屏障静态审计（net-batch-12）

## 结论

**常规客户端的“批准清单 → 下载/组装 → 安装 → 当前版本 ACK → 开局”主链已接线，但不能判定数据屏障完全完成。** 发现候选字节提前公开、Windows 损坏缓存无法在带 pin 的同步流程自愈、目录上报缺少业务 ACK 等缺口；另有“安装完成”和“确认已被权威接受”被 UI 混为同一状态。

本次只读审计当前工作树，未修改生产代码，**未运行 Godot、未执行网络/窗口套件**。项目已有大量未提交迁移/修改，证据引用当前 `scripts/net/{session,content,server,transport,validation,ui}/`，不是旧路径。测试仅阅读源码，不作为运行通过证据。

拓扑：独立服务端的网关路由连接和消息；room worker 持有批准/规则权威；素材数据面在该房间会话与成员之间传输。本文没有验证实际进程位置、多机或公网行为。

## 字段契约与时序

| 概念 | 实际字段/入口 | 语义及边界 |
|---|---|---|
| 候选目录 | `catalog.args.entries`、`catalogs[sender]` | 服务端按真实成员重新绑定 provider；不是批准清单 |
| 候选修订 | `server_data_catalog.catalog_revision` | prepare 请求须等于最新候选修订；不是数据版本 |
| 批准事务 | `request_id`、`_prepared_revision`、`server_data_status.state.stage` | commit 绑定 request_id；状态中的 catalog_revision 是建立请求时的修订 |
| 已批准集合 | `_approved`（provider/key）、`room_files`（path/hash/size）、`task.approved_files` | `_approved` 是 UI 选择来源；真正传输/安装使用 room_files；没有名为 approved_manifest 的独立字段 |
| 数据版本 | `room_files.revision` → `data_revision` | 只在完整清单通过验证后客户端替换，清空素材路径表 |
| 规则就绪 | `_rules_revision == data_revision` | `require_room_data` 开启时才强制检查 |
| 文件就绪 | cache.fetch/digest、RoomDataSync.complete、RoomAssets.install | 没有独立 blob_readiness 网络字段；completed 表示缓存完整落盘，不等于素材安装和 ACK |
| 成员确认 | `data_ack.args.revision` → `_data_confirmed[member]` | 只检查有效连接和当前数据版本，是成员声明，不是下载可信证明 |
| 总屏障 | `data_ready()` | 要求当前规则版本（强制模式下）和所有 connected 成员当前确认；包括观战者 |

服务端 `apply_room_data()` 先验证发布预算/全部文件与候选规则，随后提交规则，设置 `_rules_revision=data_revision+1`，最后 `_commit_room_files()` 增版、清确认、清 ready、广播清单。证据：`lobby_session.gd:995-1056,1129-1188`。

客户端 `RoomDataSync` 校验清单、持 pin、下载缺失内容、原子组装；大厅确认 `_sync_revision == session.data_revision` 后安装并发送 ACK。清单替换时取消旧任务。证据：`room_data_sync.gd:20-103`、`lobby_screen.gd:128-147,477-479`。

## 静态确认的缺口

### DB-01 / 高：候选 blob 在批准提交前进入远端可读发布池

- `room_data_preparation.gd:82-84` 每个候选文件完成下载就调用 `session.publish_blob(content)`，此时尚未隔离校验完成、更未房主 commit。
- `lobby_session.gd:1073-1078` 直接写 `_published_blobs`；`1093-1103` 的 `_queue_blob()` 仅要求成员在线和 key 在池中，不要求 key 属于当前 `room_files`。
- `server_room_worker.gd:171-180` 初始全部计划也先 publish，再依据预检配置决定是否仅作为候选。启用批准门槛时 `data_revision` 可以仍未建立，但内容池已可读取。
- `room_data_preparation.gd:119-125` cancel 没撤销已 publish 的候选；成功替换清单也未把发布池限制到新批准集合。

**结果：** 已知 hash 的在线成员可请求尚未确认、已取消/被拒绝的候选或旧清单字节。hash 可来自此前共享目录或本机已知源文件；本问题不声称能反推出未知 hash。这不直接解锁 start，但突破“仅分发批准内容”的授权边界。

建议：准备阶段只持有校验副本；提交后才授权分发，或让 host `_queue_blob` 显式限制当前批准哈希集合。provider 上传服务与权威下发应区分授权范围。补真实成员请求未批准/取消/旧清单 hash 的拒绝反例。

### DB-02 / 中：带 pin 的损坏缓存，在 Windows 同步链不能按未命中自愈

- `room_data_sync.gd:35-38` begin 对所有 hash 持 pin，再 `61-69` fetch 和下载。
- `content_cache.gd:114-117,120-126` 检出损坏时返回未命中，但共享 pin 存在时不删除损坏目标。
- 下载重取完成后，`blob_receiver.gd:50-54` 调用 store；`content_cache.gd:43-48` Windows 遇到已有且不相等的目标直接失败并保留旧文件。

**确定调用序列：** 损坏目标已存在 → sync.pin → fetch 发现损坏但不能删 → 下载正确字节 → store 遇旧目标失败 → sync 失败 → 释放 pin。再次直接点同步会重复该序列；需在任务外显式清缓存才能绕开。当前失败关闭保护旧文件本身是有意设计，不能为自愈直接删除仍被其他使用者持有的文件。

建议：明确提供安全的坏缓存隔离/清理后重试路径，或提示用户先清理再同步；补 Windows 的“已有损坏 blob + 正常大厅同步 + 正确源”端到端反例。未动态复现。

### DB-03 / 中：catalog 缺少业务 ACK；发送成功被当成目录已共享

- 全项目 GDScript 搜索无 `catalog_ack`/对应回执；`lobby_session.gd:898-909` submit_catalog 返回的是 `request(...) == OK`。
- host `744-758` 接收 catalog 后校验、更新并发 catalogs_changed；没有向提供者返回绑定 seq/目录指纹的 accepted ACK。拒绝可以经 error 回来，但成功没有终态。
- `room_data_panel.gd:149-150` 在 share_catalog 返回 true 时立刻显示“所选条目已共享，等待房主选择”。`share_catalog:963-967` 此时只是本地发送成功并换了服务字节池。

**结果：** 对方尚未处理、目录在途或随后遭业务拒绝时，UI 已显示共享成功；无法区分 pending 和权威已接受。该缺口不等于现有 data_ack 缺失：两者用途不同。

建议：目录提交使用明确 pending/accepted/rejected，成功回执绑定请求 seq 和提交指纹/修订；重复提交及碎片完成时统一发回执。若不新增协议，至少把 UI 文案改成“目录已发送，等待确认”，不声称已登记。

### DB-04 / 中：素材安装成功即锁住同步按钮，未等待 data_ack 被权威接受

- `lobby_screen.gd:132-135` 先 `_synced_revision = _sync_revision`，再发送 ACK；忽略 request 返回值，马上写“同步完成”。
- `lobby_screen.gd:479,553` 依据本地 `_synced_revision` 禁用同步并显示完成；权威屏障仍独立等待 `_data_confirmed`。
- `lobby_session.gd:759-763` 权威 ACK 接受会增 room.revision 并发布新资格，正常成功路径正确。但没有本次确认的 pending/accepted/retry 状态；失败可以留下“客户端已同步、权威未确认”的分叉。

**结果：** ACK 发送/接收失败时不能把当前 UI 完成当全员屏障已通过；本地安装版本和权威确认版本应分开表达。重连 identity 路径在 `560` 会对已安装且同版重新 ACK，是部分补救，不是首次失败的即时重试保证。

建议：保留 installed_revision，另管理确认在途/已接受状态及可重试确认入口；检查 send 返回值，以新权威快照/专用回执确认终态。

### DB-05 / 低：状态 catalog_revision 和最新目录修订不是同一时点，不能混用

- `server_data_approval.gd:101` 固定 `_prepared_revision`；目录刷新 `42-46` 增 `_catalog_revision`。
- commit `139-144` 再增最新目录修订，但 `_status:157` 的 applied 状态仍携带旧 `_prepared_revision`。
- `_proposal_is_current:183-184` **有意不要求最新 catalog_revision 相等**；已经收齐并隔离校验的固定副本允许在提供者撤回/离线后批准。`tests/net_server_data_withdraw_test.gd:4-7` 明确覆盖该口径。

这不是应通过“commit 再校验最新候选修订”修复的漏洞；那会撤销有效固定副本。问题是字段名称容易被消费者误认为当前目录版本；取消原因 `109-110` 文案也提到目录变化，但实际判据不看目录修订。

建议：状态中区分 proposal_catalog_revision 与当前 catalog_revision/data_revision；至少补协议注释和消费端测试，不擅自加强目录新鲜度门槛。

## 已存在的正确保护（不误报）

- manifest 单包/分片均只接受比当前更新的版本；分片连续偏移、总数、累计预算及最终全清单验证后原子替换：`room_manifest_transfer.gd:50-83`、`lobby_session.gd:579-613,1051-1056`。
- start 与 begin_match 都调用 data_ready，公开快照按钮资格也用同一函数：`lobby_session.gd:775,848,878-880`。
- ACK 接受后增 room.revision，避免客户端丢弃资格变更：`759-763`。
- 更换清单清准备与旧确认；错误清单/未发布内容在提交之前拒绝：`995-1026`。
- RoomAssets.install 逐文件核对长度/读错误/hash，全部成功才替换路径表：`room_assets.gd:20-47`。is_installed 仅表示路径表非空，不应解释成持续验证磁盘或权威 ACK。
- blob receiver 按 sender+hash 与预声明大小授权，错误偏移终止文件，完整 hash 校验落盘之后才 emit completed，完成回调后再释放接收 pin：`blob_receiver.gd:14-60`。
- 确认消息不能证明恶意客户端真的下载/安装。现有 ACK 可由客户端直接发送，属于协议信任边界而非“加一个 hash 就可信”的可修复证明问题。`tests/net_data_barrier_test.gd:43,61` 也直接发 ACK，不能用该测试证明安装门槛已端到端验收。
- 无强制房间数据且 data_revision=0 时 data_ready 返回 true，是显式兼容路径：`lobby_session.gd:1028-1036`；不能据此宣称所有普通建房已强制全量同步。

## 后续验收范围

本轮只有静态证据，没有 Godot 解析/RESULT/窗口结果。父代理后续应串行补：未批准 blob 拒绝、Windows pinned 损坏缓存、目录 ACK 在途/拒绝、data_ack 发送失败重试、清单换版取消旧任务、批准事务 applied 与客机 manifest 独立到达条件。已有 catalog/blob/cache/barrier/room_assets/server approval 套件可复用，但须新增上述反例，不能只复跑原有正例。
