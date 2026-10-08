# ready → 网关 → 客户端回执链（只读审计）

## 结论与证据等级

- **当前代码中，精确文案「服务端房间操作失败，请联系管理员检查房间状态」只出现在两个同步失败入口**：`server_gateway.gd:164–166` 的 `create_room()` 返回空串；以及 `:195–196` 的 `recover_room()` 返回 false。它不是 ready 报告校验失败、内部连接失败或控制台 save 失败的统一文案。
- **同一轮首次创建若已由 manager 成功登记并等待 ready，后续 ready 拒绝不会走这句文案**，而走 `:63–70` 的「所选房间实例已停止或更换」/「房间缺少可信 OS 进程句柄验证」。所以“日志中曾有 READY”和“本轮客户端收到这句错误”不能不带房间 ID、instance_id、请求序号直接归为同一回执链。
- **静态确认一个能直接解释本套件首次创建失败的路径前置条件冲突**：测试给 `storage_root` 指向全新 `res://tests/runtime_reports/server_match/<ticks_usec>/workers`，却没有先建立 `<ticks_usec>`；manager 在递归 mkdir 之前调用 `RecoveryPaths.checked(parent, storage_root, true)`，而 `checked()` 即使 `allow_missing=true` 最后也要求批准根 `parent` 已存在（`recovery_path_safety.gd:85`）。新父目录不存在时 `create_room()` 在 `server_room_manager.gd:138–140` 返回空串，真实 `manager.error` 为「房间存储根不可安全建立」，网关把它掩盖为上述客户端文案。这个分支发生在 config/spawn/ready 之前。
- **不能把该静态缺陷宣称为用户那次运行已证实的唯一根因**：本次可读日志中未找到该次 `SERVER_JOIN_FAILURE` 或精确错误文案，也未得到它对应的 `manager.error`。没有运行 Godot，没有修改生产文件。下文区分确定分支、确定契约与尚缺的运行关联证据。

## 1. 测试实际入口，不是先执行 save

继承链：`net_server_console_save_test.gd` → `net_server_recovery_midmatch_test.gd` → `net_server_recovery_match_test.gd` → `net_server_archive_match_test.gd` → `net_server_match_test.gd`。

- `archive_match:3–4` 只设 `gateway.manager.record_matches=true`。
- `net_server_match:6–9,120–124` 生成唯一新目录，设 `storage_root=<directory>/workers`，直接 `gateway.listen()`；没有 mkdir 测试目录。`gateway.listen:37–43` 只检查数据根存在、启动公网 ENet，不建立 room 存储父目录。
- `net_server_match:23–32` 第一个客户端 `join_server(..., room_id="", room_name="服务端完整对局", settings)`，等待 `session.view` 最长 20 秒；失败打印 `SERVER_JOIN_FAILURE <session.error>`，清理并结束。直到真实中局才会进入子类 `_after_baseline()` 的 save。
- `net_server_match:112–116` 每轮先 `gateway.poll()`，再客户端 `session.poll()`，最后 await 帧。首次 `_server_sent` 只发送一次 server_list + server_create（不是每帧重试）。

## 2. 创建/ready/attach/room 的完整链

|阶段|生产代码|契约与失败点|
|---|---|---|
|客户端声明创建|`lobby_session.gd:352–357,374–377,391–402`|空 room_id → `_server_request.kind=server_create`；信封 `{v:1, seq:<int>, kind, args:{name,settings}}`；先发 list 再 create。|
|网关同步创建|`server_gateway.gd:154–172`|校验 name/settings；调用 manager。空 ID → 泛化错误；非空 ID → 保存 `_creators[id]` 与 `_pending[peer]`，绑定 `{room,pid,instance_id,authority_host_mode}`。此时没有向客户端发“创建成功”。|
|本机创建房间|`server_room_manager.gd:125–196`|所有权可用 → data_root 无链接/规范目录/树预算 → approved_data_root → storage_root 检查/创建 → 策略/settings/内部 UDP 端口 → room/instance 随机 ID → config.json → native spawn → 登记 ready=false/deadline。任何提前 return "" 都由网关变成同一句泛化错误。|
|工作进程初始化|`server_room_worker.gd:22–190`|三个主管参数（config 路径、批准数据根、批准存储根）→ 路径/实例/策略校验 → 建立校验后的独立数据 → `session.host(int(port),...,"127.0.0.1")` → 专用身份/恢复/选人/内容/审计配置。|
|原子发布 ready|`server_room_worker.gd:191–203`|`ready.json.tmp` 写入、flush、close、rename 到 `ready.json` 成功后才 print `SERVER_ROOM_READY <config.id>`。print 只含 room ID，不含 instance 或 PID。|
|主管接受 ready|`server_room_manager.gd:198–235`|先验证自己持有的 native process state==1；读取 `room.directory/ready.json`；`valid_ready_report()` 整体通过才设置 `room.capabilities` 和 `room.ready`。坏报告设置 room.error 并终止自己的 worker；不是扫描日志找 READY。|
|再次核验所有权|`server_gateway.gd:60–74`；`server_room_manager.gd:83–98`|pending 的完整实例必须仍匹配；room.error 必须为空；ready=true 时 `process_identity_verified()` 要 native `verify(process_token,pid)==true`；通过才 `_attach()`。|
|内部回环路由|`server_gateway.gd:280–306,75–94`|再次检查绑定，连接 127.0.0.1:room.port；每轮 link.poll；连接后发送 `{kind:"server_attached",room,peer_id:<internal ENet id>}`；只有发送入队成功才 route.attached=true；attach 超时预算 10 秒。|
|客户端真正 join|`lobby_session.gd:563–568,386–389`|收到 server_attached 且 room 为 String、peer_id 为 int>1，才设置 server_room_id/_server_peer_id，随后发普通 `join`；不是收到 ready 文件或日志就直接形成 view。|
|权威发布房间|`server_gateway.gd:128–133,316–322`；`lobby_session.gd:646–656`|网关注入可信 gateway_identity 后转发 join；worker 回 room/state；网关仅转发当前实例 sender==1 的回复；客户端要求 state.revision 为 int、members 为 Array，且 revision 更新，才写 session.view。测试等待的正是这个 view。|

## 3. ready 字段逐项对账

生产者：`server_room_worker.gd:195,319–327`；消费者：`server_room_manager.gd:100–106`。

|ready.json 字段|manager 期望|静态对账|
|---|---|---|
|ok|true|worker 写 true。|
|id、room_id|均为 room.id|worker 两者都写 config.id。|
|pid|room.pid|worker 写 OS.get_process_id()；manager 写 native spawn 返回 PID。native Windows 代码直接 CreateProcessW 并返回 dwProcessId，非 shell 包装（`process_owner_core.cpp:133–148,198–200`）。实际 DLL 装载/返回值仍须运行证据。|
|port|room.port|worker int(config.port)，manager 持有探测端口；JSON 数值读取后该函数用数值比较，不是 `is int` 强校验。这里没有“JSON 的 float 一定被拒”的依据。|
|instance、instance_id|均为 room.instance_id，32 位小写十六进制|worker 两者来自 `_control.instance_id=config.instance_id`。|
|authority_host_mode|room.authority_host_mode|worker 来自 config，manager 显式部署策略。|
|capabilities|Dictionary；7 个键全为 bool|root_transaction_rollback、can_rollback_now、execution_trace、root_transaction_audit、transaction_audit_persistence_enabled、match_recording_enabled、process_restart_is_rollback。消费者只要求布尔类型，不要求前六项均 true；最后一项必须 false。worker 当前全部按此声明。|

**未发现当前 ready 生产者/消费者之间确定的缺键或命名不一致。** native process_token 不写 ready；只能由主管在内存中验证。也不能拿旧 worker ready 或磁盘 PID 自动认领 native 所有权。

## 4. 具体路径冲突：新测试父目录尚不存在

在 `net_server_match_test.gd:6,121`：

```text
directory = res://tests/runtime_reports/server_match/<ticks_usec>
storage_root = directory/workers
```

在 `server_room_manager.gd:137–140`：

```text
若 workers 不存在：
  checked(absolute(workers).get_base_dir(), workers, true)
  AND make_dir_recursive_absolute(workers) 成功
否则 return ""，error="房间存储根不可安全建立"
```

`checked(root,path,allow_missing=true)` 允许路径扫描中某些目标/祖先尚不存在，但最后仍返回 `DirAccess.dir_exists_absolute(absolute(root)) && ...`。这里 root 恰是新 `<ticks_usec>`。所以 parent 未建时，短路条件令递归 mkdir 根本不会执行；所谓 allow_missing 不代表批准根也能缺失。

本套件在创建 worker 前只设置客户端 `blobs.cache.root=directory/client-cache`（`:19`），未读取/存储内容来建立它。client 初始 `_pump_blobs()` 是队列处理，不等于测试目录创建。其 settings、runtime_guard 的字段本身满足创建契约，`_gateway_identity_required` 额外键也不会被 `room_state._valid_settings()` 拒绝（`:158–172` 无全字段白名单）。

与 ready 现象的关系：这条确定的失败路径不可能生成本轮 worker；已有 READY 必须对 room ID/instance/日志路径查同轮关系。不要再修 ready 字段来掩盖这个 spawn 前的失败。

## 5. 其他静态确认的时序/回执缺口

1. **错误原因在网关被抹掉。** `create_room()` 内部有专用 `manager.error`；`:166` 发固定文案且没有对应本机原因日志。由于 `_pending` 尚未登记，`_diagnostic_context()` 常只能给 `room="",pid=-1,instance_id=""`，不能由客户端回执关联到一个 worker。管理员的 console room_create 路径倒会返回 manager.error（`server_console_channel.gd:192–194`）。
2. **序号字段不一致。** 网关 `_fail:407–410` 发 `request_seq`；客户端 `lobby_session:662–663` 只查 `seq` 才发 `request_rejected(seq,reason)`。文本 error 能显示，但按请求序号订阅的 UI 不会收到该拒绝信号。ready/pending 异步失败 `_fail()` 又不传原 request，默认 request_seq=-1；pending 只存实例，不存创建 seq。不是 ready 校验错误，但会损害完整拒绝回执关联。
3. **测试和 manager 的预算不同。** 测试 `:24` 20 秒等 view，manager 默认 startup_seconds=30，attach 另有 10 秒。worker 很晚打印 READY 也可能已超过测试等待/cleanup；仅比 READY 字符串不能排除晚到。不能声称本次已经实际超时。
4. **心跳成功不等于 ready 成功。** manager 每秒写 supervisor.json（`:205–209,370–394`），worker READY 后开始 5 秒监督超时计时（worker `:203,205–216`）。Windows File.Replace 已存在；失败只写 manager.error，没有写 room.error。worker 可先 READY、之后打印 SUPERVISOR_LOST 并退出。其后公网应收到实例停止/连接断开等文案，不是首次创建的同步泛化文案。
5. **恢复死进程 PID 门槛不连通。** manager.poll 退出分支（`:212–216`）没有把 room.pid 设成 -1；网关恢复分支（`:194–198`）只在 binding.pid<=0 才调用 recover_room，注释却说 poll 会登记 pid=-1。已退出但保留正 PID 的已登记房间会被放入 pending，下一轮因 room.error 被拒；generic recover 失败不是该分支的直接结果。这是独立恢复缺口，不应误归为首次 ready 字段错误。
6. **身份策略双写存在覆盖。** 网关 `:163` 根据 identity_registry 写 settings._gateway_identity_required；manager `:180` 又根据自己的 identity_binding_required 写 config 同名字段。正式 server_cli `:122` 同步 manager 标志，但直接实例化网关并开 registry 的其他入口若未同步，会让 worker 的认证要求被降为 false。当前 save 套件 registry 为空，两者均 false，不能用它解释该首次失败。

## 6. save 管理回执是另一条链

只有大厅、数据屏障、真实中局都完成后，`net_server_console_save_test.gd:3–15` 才执行 `room <id> save`。

- `server_console_channel.gd:246–269` 先 manager.is_ready（完整 native binding），再读同目录 ready.json 校验 id/pid/instance；写 `control/<request_id>.request.json`，字段 `{room,pid,instance,authority_host_mode,action}`；返回 `{status:"pending",request_id,saved:false}`。
- worker 每帧 `_control.poll()`（worker `:221`），回执由控制通道生成。
- 测试 `:29–35` 等真实 `<request_id>.response.json`，然后 `room <id> result <request_id>`；channel `:271–289` 检查 request_id、room/pid/instance/authority_host_mode，返回落盘响应。测试再读取 match.log 对照 records/state_hash（`:16–20`）。
- 因此 console save 未执行前的 SERVER_JOIN_FAILURE 不能称为“save ready 回执失败”；必须先确认失败发生于父类 `run()` 还是子类 `_after_baseline()`。

## 7. 已完成的只读核验与尚缺证据

已读：manager、worker、gateway、bootstrap、recovery_path_safety、room_state、lobby_session 关键入口、console_channel 与该测试继承链；native ProcessOwner binding/core；server_cli 身份配置接线。生产路径经 git status 显示为 untracked，不能用 git diff 当作历史版本对照。

只读扫描包含 gitignored 的 `tests/runtime_reports`、仓库 scratch，以及 Hermes cache/scratch 的 `.log`；没有查到所述精确失败记录。现有 `tests/runtime_reports/server_match` 目录中可见若干历史 client-0/client-1/client-cache，没有此次可关联的 workers/engine.<instance>.log。另扫描已知外部 `E:/Projects/Godot/FateDomination/test` 的 console/save 日志文件名，但这些旧导出日志不能冒充当前源码这次失败证据。

父代理下一次获准运行时，最小关联记录应是：

- 同一次 server_create 的 seq、manager.create_room 返回值与 manager.error（在服务器本地，不回传敏感路径）；
- 本轮 storage_root 及其 parent 在创建前是否存在；
- 成功登记后的 room.id、pid、instance_id、deadline、room.error/ready；
- 对应 `room.log_file=engine.<instance_id>.log` 的 READY/退出证据与 ready.json；
- pending → attach_notice → 客户端 join → room.state 的阶段和发送结果。

本报告不运行 Godot、不写测试替身、不放宽所有权或路径安全校验。只创建本文件；所有根因候选以静态契约为限，缺少同轮证据处明确未确认。
