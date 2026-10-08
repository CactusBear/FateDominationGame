# dedicated 房间恢复原子性审计（只读）

## 结论

**当前 dedicated 恢复不是失败原子事务。** 子进程启动、房间就绪、对局恢复和恢复状态持久化是分离的成功边界；已发现配置回滚失败被忽略、恢复状态写盘失败仍继续发布，以及对局恢复失败将旧 `restoring` 改成 `lobby` 并落盘的路径。原始崩溃存档目前通过实例副本隔离，没有发现该入口直接覆盖原始 `match.log`；但未提交的新存档目录可能被下次恢复误选。

本报告仅静态追踪真实源码和文档，**未运行 Godot、未执行故障注入、未改生产文件**。行号以本次读取工作树为准；仓库已有修改和未跟踪文件，不将这些既有状态归因于本次审计。

## 文档约束

- `docs/real-world-multiplayer-test-plan.md:166–171`（RW17）：先读旧状态、校验既有数据再持久化；`playing → restoring → playing`；全部原真人认证重连、通过数据屏障；`SERVER_ROOM_READY` 只代表就绪。
- 同文档 `:180–184`（RW19）：缺认证绑定的旧档失败关闭，原目录、配置和存档保留。
- `docs/package-real-test-checklist.md:138`：崩溃恢复不能仅验子进程重启。

## 实际发布顺序

1. `ServerRoomManager.recover_room` 验实例、原生所有权、配置路径/绑定、UDP 端口（`scripts/net/server/server_room_manager.gd:292–328`）。
2. **覆盖原 `config.json` 为新 instance_id**（`:329–336`），删除旧 ready（`:337–343`），spawn（`:344–352`），释放旧进程所有权（`:353–359`），然后发布内存 PID/token/instance，`ready=false` 并返回 true（`:360–368`）。
3. Worker 校验路径/配置，构建批准数据方案；已有 `data` 必须校验，禁止覆盖残留（`server_room_worker.gd:130–144`）；加载固定数据，`host()` 后才读取 recovery（`:145–164`）。初始 host 时 recovery_state_path 尚未开启，避免空房覆盖旧 recovery。
4. Worker 发布 blobs/清单，建立审计，然后发布 ready（`:171–202`）。**此时原真人还未必重连，存档也尚未重放。**
5. `restoring` 且尚未 started 时，检查恢复绑定真人已连接；扫描 `matches`，按目录字符串排序选最后一个；复制到 `restore-<instance>` 后调用共享恢复（`:222–261`）。
6. `LobbySession.restore_local_match` 先改房间 phase/revision 并 `_publish()`，再 await 重放；`MatchAuthority.restore_archive` 在清单/资源发布前完成新归档另存和续写（`lobby_session.gd:1370–1421`；`match_authority.gd:467–501`）。
7. 替换 match_authority，提交清单并发布恢复状态；后续 poll 在 data_ready 时改 playing 并再次发布（`lobby_session.gd:1411–1421,1012–1026,380–385`）。

## 缺陷

### DR-01 / 高：配置先覆盖，失败回滚没有确认；异步启动失败根本不回滚

证据：`server_room_manager.gd:329–357` 在 spawn/旧所有权释放之前发布新配置；`:341,350,357` 三处回写旧 instance_id 都忽略 `write_configuration()` 的 bool。`:198–235` 的 poll 在 worker 非就绪、退出/超时后只标错或终止，没有恢复旧配置。

触发：新配置 rename 成功后，旧 ready 删除失败或 spawn/旧所有权释放失败，同时回写配置失败。此时 API 返回 false、内存仍旧实例、磁盘却新实例；再次 recover 在 `:320–322` 拒绝配置与登记不一致。另一条直接路径是 spawn 成功、worker 后来拒绝损坏旧身份状态（`server_room_worker.gd:160–163`），管理器已返回 true 且原配置已更换。

影响：无法兑现“失败保留原配置”；错误回执掩盖混合状态，并可能卡死同一主管内的重试。清理新进程的 terminate/release（`:354–355`）也不检查返回值；若清理失败，新 token 未登记，不能证明失败关闭时新进程已停止。

建议：保留旧配置字节和提交状态；新实例配置使用独立路径/暂存世代，验收失败必须确认停止并回滚。回滚失败须明确进入隔离/待管理员修复状态，不使用普通恢复失败回执冒充原状态未变。

### DR-02 / 高：恢复状态写盘失败仍发布并返回恢复成功

证据：`lobby_session.gd:875–895` 的 `_publish()` 更新 view，调用 `_persist_recovery_state()`（`:890`）但忽略结果，随后照常广播与 changed。写入器确实可在 open/flush/rename 失败时返回 false（`:1351–1367`）。`restore_local_match` 通过无返回值 `_commit_room_files` 提交（`:1415–1421`；`:1012–1026`），最后无条件 true；`poll:380–385` 切 playing 同样不确认持久化。

触发：恢复日志、资源和候选权威已成功，但 recovery 临时文件写入/rename 失败。

影响：客户端看到成功状态、内存开始恢复/继续运行，磁盘却保留旧 revision/phase/data_revision/绑定；下一次崩溃不能按已对外宣布的提交状态恢复。这里的“日志已 flush”不能替代“房间恢复状态已提交”。

建议：把持久化结果纳入唯一提交入口；写盘确认前不交换权威、不宣布新清单/playing。若内存已不可逆变化，须保持暂停并报告未确认/混合状态，不返回 true。

### DR-03 / 高：重放或资源发布失败将旧 restoring 房间降为 lobby 并覆盖 recovery

证据：`lobby_session.gd:1377–1382` 未保存完整原房间/phase/revision，而是先改 phase/revision 并发布；重放失败分支 `:1386–1392` 和资源失败分支 `:1401–1410` 都设置 `room.phase = "lobby"` 再 `_publish()`。正常写盘时这会覆盖旧 recovery。Worker `_recovery_attempted` 在 `server_room_worker.gd:225–235` 已置 true，仅等真人分支置回 false；最终恢复失败只是 push_error（`:260–261`），不退出、不撤 ready，也不保留可自动重试状态。

触发：日志重放/另存/续写/审计失败，或日志已恢复后清单/资源安装失败。

影响：崩溃前 playing 的房间不再保持 restoring，仍保留原进程 ready 的外观；该 worker 不自动重试，下次重启读取 lobby 后也不会进入自动恢复分支。原 match.log 字节虽保留，但恢复入口语义和磁盘恢复状态已丢失，可能误以为大厅恢复成功。

建议：失败保留原恢复相位、修订和绑定，显式区分恢复失败与普通大厅；提供安全重试/管理员选择，不把恢复失败自动转换成可新开的大厅。完整候选事务提交前禁止写原 recovery。

### DR-04 / 中高：新续写目录早于房间事务提交发布，失败残留可成为下次“最新存档”

证据：`match_authority.gd:484` 顺序为 restore → save_restored_as(target) → resume_recording → flush_audit；`match_replay.gd:271–292` 直接向正式新目录拷数据、创建/逐条追加 match.log，再复制事务审计，任一步失败均无整个目标目录回滚。成功另存后仍可能续写/审计失败，或回到 `lobby_session.gd:1401–1410` 才资源失败。`server_room_worker.gd:239–251` 只按存在安全 match.log 的目录排序选最后一个，没有提交标记或上次成功归档指针。

触发：新日志只写了头/部分记录后写盘失败；或已完整另存但事务审计/资源发布失败，留下新目录。下一次 worker 重启，该目录可能排序最后。

影响：完整旧崩溃档没有被物理覆盖，但逻辑恢复目标会被失败产物替代；损坏候选会挡住恢复，合法完整前缀则可能恢复比旧完整档更早的状态。具体结果依赖失败字节边界及日志校验，不宣称已经运行复现。

建议：暂存目录完成日志/审计/资源/房间恢复提交后才发布为候选；用持久归档 ID 和完成标记关联 recovery，不用目录排序推断成功。失败产物隔离并保留诊断，不与已提交档混扫。

## 已有防护与不能夸大的成功边界

- `recover_room:true` 只表示成功登记新子进程，函数注释 `server_room_manager.gd:290–291` 也明确不代表对局恢复；ready 报告有 room/PID/instance/mode 核验（`:100–106`）。该 API 返回值本身不应被命名或解释成对局恢复成功。
- `server_room_worker.gd:133–144` 已有数据目录逐文件校验、未知残留拒绝覆盖；`:252–306` 使用唯一实例副本且校验复制字节/哈希，原始崩溃目录没有直接作为续写目标。
- recovery 先校验身份绑定再安装内存状态（`lobby_session.gd:1277–1313`）；host 初始发布不会写原 recovery。但 manager 新配置已在 worker 拒绝之前发布，因此不能据此宣称所有恢复材料都不变。
- LAN/P2P 的安全阻断（worker `:86–90,227–230`）不覆盖本次 dedicated 路径。

## 验证覆盖缺口（交主代理，不在本次运行）

`tests/net_server_rooms_test.gd:66–80` 仅重启、检查 config 存在、ready 与原成员大厅重连；没有逐字节检查原配置/恢复档不变，也没有 playing 的完整存档恢复或写盘失败注入。`recover_room` 相关其他搜索命中为过期实例/越界路径拒绝，不能据此证明提交事务。

建议串行补真实故障矩阵：

1. 新配置发布后 ready 删除失败；spawn 失败；旧 ownership release 失败；三者分别叠加配置回滚失败与新进程 terminate/release 失败。
2. spawn 返回后 worker 拒绝损坏旧档/身份绑定；核对原 config、recovery、存档哈希、内存绑定、实际进程和重试状态。
3. recovery open/flush/rename 在恢复开始、清单提交、playing 提交处分别失败；不得发布持久成功或开始推进行动。
4. 重放失败与重放成功后资源发布失败；原 restoring/revision 保留且可重试，ready/诊断不得暗示原局已恢复。
5. 新归档在 header/部分记录/审计复制/续写/房间提交各步失败后重启；未提交目录不得成为恢复源，成功源必须由显式提交引用决定。

## 本次文件/执行范围

- 唯一新增：`scratch/net-batch-10/dedicated-recovery.md`。
- 生产源码、docs、测试文件均只读；未启动/运行 Godot，未创建恢复副本，未修改真实配置、存档或进程。
- Git 状态读取显示已有大量修改/未跟踪网络源码，审计的是当前工作树而非干净 HEAD；未执行清理/回滚。
