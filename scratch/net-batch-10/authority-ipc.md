# LAN/P2P 权威 worker：恢复 IPC / 密钥绑定只读审计

## 结论与范围

- **LAN/P2P 恢复目前是明确失败关闭，不是已实现的恢复 IPC。** 没发现从正式大厅恢复入口绕过此阻断的远端路径。
- 静态确认三个实际实现缺口：关闭回执永远不能匹配房间、关闭监督仍使用裸 PID 判断退出、主管恢复先改配置再被 worker 阻断（“原配置保留”不覆盖端到端）。
- 只读取生产源码与恢复文档；唯一写入为本报告。未运行 Godot、未执行规则或网络测试、未改生产文件、未 commit。以下“确认”均指源码控制流，不冒充运行复现。

## 拓扑与认证链

信令面：P2P 信令节点只辅助连接；本次没有跨网验证。数据面：LAN/P2P 客端 → 房主 gateway → 本机 loopback worker；房主 UI 自身也通过 loopback 加入 worker。权威面：规则由房主机器的 worker 执行，UI 不调用恢复重放。

证据：`scripts/net/session/authority_host_client.gd:31–41,58–76` 设置 host mode、创建 worker、连接本机端口；`scripts/net/server/server_room_worker.gd:155–159` 仅监听 `127.0.0.1` 并设置 dedicated/身份策略。

### 当前安全阻断（功能缺口，不是认证绕过）

1. `authority_host_client.gd:102–117` 的 `restore_local_match` 不读 source、不发 IPC、返回 false，diagnostics 明示不可用。
2. `scripts/net/ui/lobby_screen.gd:399–410` 有 authority_host 时调用该入口并立即 return，不落回 UI 的共享恢复。
3. `server_room_worker.gd:84–90` LAN/P2P 存在 recovery.json 时，在 host/load recovery 前退出；`:225–230` 自动恢复二次拒绝。
4. `scripts/net/server/server_room_control.gd:35–42` 只允许 save/seed/close/pause/resume，**没有 restore action**。因此不能把现有 pause/resume、进程重启或复制原档称作恢复 IPC。

LAN/P2P 密钥认证也没有正式接线：authority_host 的 gateway registry 保持默认空路径，`:61` 房主 hello 写 required=false/key=""；manager 的 identity_binding_required 默认 false（`server_room_manager.gd:18`），网关每次 join 按 registry 路径重建上下文（`server_gateway.gd:505–516`）。`lobby_screen.gd:417–419` 只有独立服务端模式准备密钥身份。当前 LAN/P2P 成员恢复仍是 bearer ticket，同一密钥验证/认证房主继承不能由 dedicated 的现成代码自动推导为已支持。开通前须先建立真实认证再解除恢复阻断，不能只把 required 改 true。

## 实际缺口

### AIPC-01｜中：关闭后回执 room 校验使用了已清空的字段

- 位置：`authority_host_client.gd:125–129,137–138,148–155`；`server_room_control.gd:43–47`。
- 控制流：close 保存 `_closing_target` 并发送包含原 room_id 的请求，随后无条件 `room_id = ""`；异步 `_drain_close` 却比较 `response.room != room_id`。worker 回执总是包含原 room_id，故实际回执被拒绝，`:153–155` 的关闭拒绝警告不可达。
- 可观测后果：worker 因存档/恢复状态写盘失败拒绝 close 时，UI 已断开、会话引用已清除；manager 仍被持续 poll，worker 留存，却收不到设计中的失败提示。特别是未开启录制的正在运行对局，`server_room_control.gd:80–87` 会明确拒绝保存/关闭，容易触发该盲区。
- 最小修正建议：用冻结的 closing binding（如 `_closing_target.id`）核对 room，并同时核对 request_id；不要用清空后的活动会话字段。
- 待运行反例：构造同一 room/PID/instance/mode 的 `ok=false` 回执，close 后推进 drain，必须产生一次明确拒绝提示，而非静默忽略。

### AIPC-02｜中：关闭监督绕过原生进程所有权，以裸 PID 判定退出

- 位置：`authority_host_client.gd:140–146`，对照 `server_room_manager.gd:53–75,198–216`。
- `_drain_close` 用 `OS.is_process_running(_closing_target.pid)` 决定是否停止心跳/回调；manager 已有私有 process_token 的原生 owner.state 路径，这里没有复用它。
- PID 若在原 worker 退出后被无关进程复用，close drain 会继续挂在 SceneTree、继续 poll manager，不能判定原实例已经退出。**本处没有 kill 调用，不应夸大成杀错进程漏洞**；真实缺口是生命周期退出判据和清理泄漏。
- 最小修正建议：由 manager 暴露对冻结实例/私有 owner token 的退出查询，拒绝把新 PID 的存活当作原实例存活；包括所有权失效时明确错误终态。
- 未执行：真实 PID 复用/原生所有权运行验证。

### AIPC-03｜中：LAN/P2P 启动阻断不保证主管恢复原 config 字节保留

- 位置：`server_room_manager.gd:292–368`，尤其 `:329–336,337–345,360–368`；`server_room_worker.gd:84–90`。
- 直接本机调用 manager.recover_room 对已登记的 LAN/P2P 旧房间时，主管先随机轮换 instance_id 并发布 config.json、删除旧 ready，再 spawn；worker 发现 recovery.json 才拒绝。worker 的“原配置保留”仅意味着自己没有覆盖配置，主管实际上已经替换配置；异步启动失败不触发 recover_room 中那些同步 spawn-failure 回滚分支。
- 可达性限定：authority_host 的手选恢复并不调用该方法，LAN/P2P 对外管理消息也被过滤；本缺口在公共 manager 本机恢复 API 上，**不是已证明的公网攻击路径**。
- 后果：被安全拒绝的恢复尝试仍改变 config.instance_id/ready 事实；无法满足文档宣称的全链路原配置保留。recovery.json 与 matches 原档在所读路径未被写入，不能说它们已损坏。
- 最小修正建议：主管也在任何写入前拒绝 LAN/P2P+旧 recovery.json；未来允许恢复时则将配置准备/实例切换纳入明确提交事务。
- 待运行反例：比较调用前后 config.json 的逐字节内容、ready、recovery.json 和 matches；拒绝应在 spawn/配置发布之前完成。

## 已排除的误报与残余信任边界

- 客机自报 gateway_identity 不会经正常 LAN/P2P gateway 保留：`server_gateway.gd:117–133,505–516` 重新构造字段。因此不能把 authority_host 的 pending join 原样缓存认定为远端伪造认证漏洞。
- 对启用认证的 dedicated 链，`lobby_session.gd:254–289` 在恢复票据校验/room.reconnect 前检查 member-key 一致性；`load_recovery_state:1310–1314` 在建立 recovery_state_path 前验证完整绑定。`identity/member_identity_bindings.gd:6–31` 拒绝缺绑定的认证旧档，`:92–124` 继承要求当前认证房主、稳定成员、revision、sequence，并创建审计事实。
- worker 的可信网关字段以“监听 loopback”为来源边界（`lobby_session.gd:257–266`），所读 join 路径没有对内部连接做主管握手。loopback 不是同权限本机进程认证；可访问本机端口的恶意程序仍属于额外威胁边界。未证明跨网客机可直达，也未验证控制目录 ACL，不把这一局部假设写成公网利用。
- 管理请求实际校验 room/PID/instance/mode/action/字段数（`server_room_control.gd:35`），不是只用 PID。心跳则缺 mode 字段（manager `:377`、worker `:211`），但已有 room/PID/instance/version，未找到仅凭缺 mode 导致跨实例接受的反例，故不列为独立漏洞。
- 旧审计 `scratch/remaining-multiplayer-v5/导出前最终联机缺口审计.md` 所称 process_ownership_available 固定 false 已过时：现函数在 `server_room_manager.gd:57–63` 查询 FateProcessOwner.available。本次没有加载/运行引擎，不能进一步宣称本机扩展可用或成功 spawn。

## 文档对账与验证边界

已读 `scratch/authority-recovery-ipc-v5/交接说明.md`，当前恢复阻断与其主体结论一致，但“保留原配置”需要按 AIPC-03 收窄到 worker 自身行为。该文档记载的历史静态结果未在本次重跑，不能借作本次运行结果。

执行过只读 git status：所审计生产路径已有未跟踪源码与既存文档改动，未重置、未覆盖它们。报告不归因这些改动。本次无 Godot、无网络/窗口、无进程退出、无写盘失败注入验收；上述测试均仅为建议。唯一新增文件：`scratch/net-batch-10/authority-ipc.md`。
