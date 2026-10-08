# net-batch-32：最终阻断清单

## 范围结论

- 依据 `docs/multiplayer-plan.md` 与当前源码静态复核；本轮未运行 Godot、导出包、LAN/P2P、多机或公网验收。
- 不把历史断言数、同机双 peer、独立服务端恢复或“进程存活时重连”计作房主崩溃恢复完成。
- 当前拓扑仍应保持：P2P 信令只交换握手；游戏 DataChannel 直连；LAN/P2P 权威规则在房主机器；独立服务端规则在 worker。

## P0-1：LAN/P2P 崩溃后自动恢复仍被生产路径显式阻断

**静态证据**

- `scripts/net/server/server_room_worker.gd:93-96`：只要已有 `recovery.json` 且 `authority_host_mode` 为 `lan`/`p2p`，worker 在 `host()`、状态发布和恢复前直接 `_fail(...)`，原配置、恢复状态和存档保留。
- `server_room_worker.gd:_try_restore_match()` 再次在 LAN/P2P 返回拒绝；这不是未验收标签，而是当前正式代码的硬阻断。
- `docs/multiplayer-p2p-progress.md` 与 `docs/cross-network-p2p-test-plan.md` 也只把跨网/崩溃恢复列为未验收；专用服务端恢复不能外推到房主 worker。

**可执行阻断项**

1. 先补 LAN/P2P 的已认证成员绑定：恢复状态固定保存 `member_id → 认证密钥指纹/恢复凭据哈希`；错误密钥先拒绝，旧档缺绑定失败关闭，禁止首个持票者认领。
2. 将恢复接入房主机器的实例绑定控制链：读取旧状态 → 校验固定数据目录与完整日志 → 所有原真人用原绑定重连 → 素材/规则屏障 → 原子提交恢复 → `playing`。不得在恢复前发布空状态覆盖旧档。
3. 恢复失败时保留原档、配置、日志链和连接资格；自动恢复不能改成 `kill + restart`，也不能把正在运行的房间重启通过冒充中局恢复。

**最小修复候选**

- 复用 `member_identity_bindings.gd`、`lan_archive_restore.gd`、`lan_supervisor_identity_bridge.gd`、`lan_worker_identity_bridge.gd` 和现有 `server_room_worker.gd` 数据屏障；只新增 LAN/P2P 的认证恢复事务适配，不另造身份模型。
- 在上述契约和原子提交具备前，保留现有拒绝；不要删除两处阻断以制造“恢复成功”。

**必须转绿的最小反例**：错误密钥、缺绑定旧档、房主进程崩溃、原真人重连、数据屏障失败后原档不变、恢复后同一中局继续。LAN 与 P2P 分开；服务端恢复结果不可复用。

## P0-2：P2P 身份入口有 UI，但缺“身份已认证后才可进入”的端到端闭环证据

**静态事实**

- `scripts/net/ui/lobby_screen.gd:_host()` 与 `_join()` 当前都会调用 `_prepare_identity()`，这是必要接线，不等于认证完成。
- 邀请码路径调用 `session.host_authority_peer()`、`join_peer()`；信令路径调用 `_signal.host/join()`。正式 UI 没有一条可见的“身份认证完成/当前密钥绑定/恢复资格”状态门，且 `p2p_signal_client.gd` 的 `create/join/offer/answer` 协议本身不携带或验证成员身份。
- `authority_host_client.gd` 对 LAN/P2P 使用 `lan_identity_challenge`，而 `server_room_worker.gd` 对带恢复状态的 LAN/P2P 仍拒绝；因此当前最多是入房身份挑战/进程存活重连，不是崩溃恢复身份入口。
- UI 仅显示用户名/昵称和公开候选；这一点应保留，不能把公钥、指纹、恢复票据补到界面或邀请码中。

**可执行阻断项**

1. 为邀请码与信令两条 P2P 入口共用一个“认证后 join/恢复”的会话门：先完成房主/客机密钥挑战，得到当前连接的认证上下文，再提交加入或恢复请求；拒绝载荷自报身份、昵称匹配和旧连接序号。
2. 在 UI 只显示“身份已验证/等待房主指定席位/恢复被拒原因”等状态；公开候选仍仅为稳定 `member_id` 的昵称标签，重名附用户名。
3. 给 P2P 正式入口补回执消费：认证成功、席位绑定、视图修订和恢复成功必须分别确认；信令 WebSocket 关闭不能清除已经建立的直连身份，但未完成握手必须清理。

**最小修复候选**

- 复用 `player_identity.gd`、`lan_identity_challenge.gd`、`member_identity_bindings.gd` 与 `LobbySession._accept_identity()`；把 `p2p_invite.gd`/`p2p_signal_client.gd` 只作为传输建立层，不在其中复制身份规则。
- 增加一个 `P2PIdentityGate`（或等价会话门）而不是把 fingerprint/token 塞进公开 invite code；UI 只接门的状态与脱敏错误。

**必须转绿的最小反例**：无身份先 join、错误密钥、同昵称冒认、信令断开后已建立直连继续、未完成握手清理、恢复票据不出公开快照/邀请码。没有真实入口和回执证据时仍标 blocked。

## P0-3：日志隐私与事务审计失败返回值仍未形成安全闭环

**静态证据**

- `scripts/net/server/server_console_channel.gd:87` 只打印命令名和 `ok`，目前较安全；但 `scripts/net/server/server_console.gd:53` 会把完整 response JSON 打到控制台，且 `server_gateway.gd` 多处把 manager 错误和迁移成员列表直接打印。必须逐字段确认响应/错误不会带密码、恢复票据、fingerprint、公钥、SDP/ICE、完整身份库或牌面参数。
- `server_gateway.gd:_players()` 直接返回 `record.identity` 及完整身份记录；这是管理结果边界，不能被普通诊断、公开房间列表或日志复用。`server_gateway.gd:576/598` 的 legacy migration 日志虽只打印成员编号，仍需统一脱敏审计入口，禁止未来把 selected/approved 直接打印。
- `MatchJournal.audit_event()`、`flush_audit()`、`consume_tail()` 返回 `bool`，`EffectCheckpoint.audit()` 也返回 `bool`；当前有少数调用点消费拒绝，但尚未有一条“任何审计追加/flush 失败即阻断成功提交、恢复或管理回执”的总闸。计划和 open questions 明确要求审计写入失败不得报告可追溯成功。
- `server_room_worker.gd` 仅在 `begin_audit()` 建立失败时停止；后续规则事务的 `audit_event`/flush 失败需要沿权威动作、恢复、close/save 回执继续传播，不能只留 `MatchJournal.audit_error`。

**可执行阻断项**

1. 先定义并复用日志白名单/脱敏写入器：控制台输出、服务端日志、恢复诊断、管理回执分别只允许房间/实例/请求序号/状态码等字段；禁止原始 command、password、token、fingerprint、public key、SDP/ICE、隐藏牌面和完整 identity record。
2. 将事务审计 `append/flush/consume_tail` 的失败结果接回权威事务边界：失败时停止推进或进入明确 paused/failed 状态，不发 `saved=true`、`restored=true`、`closing` 完成回执；恢复与续写必须携带实际审计 revision/hash。
3. 为 `EffectCheckpoint.audit()` 的失败建立唯一处理策略，扫描全部调用点，禁止“调用了 bool API 但忽略结果”。

**最小修复候选**

- 不改审计格式：复用 `MatchJournal.audit_error`、`audit_event()`、`flush_audit()` 和现有回执结构；新增一个权威 `require_audit_ok()`/事务提交闸，统一消费 bool。
- 将 `_players()` 改为显式公开投影（身份键只在已认证管理员私有响应中返回），将控制台 response 与错误改为字段白名单摘要；保留可追溯 request_id，不记录敏感参数。

**必须转绿的最小反例**：模拟 append 失败、flush 失败、tail 二次消费、管理 save/close 在审计失败时不得报成功；日志扫描确认无密码/票据/fingerprint/公钥/SDP/ICE/隐藏牌面；私有管理员查询与公开快照字段隔离。

## 交付边界

- 本文件只新增于 `scratch/net-batch-32/final-gap-check/final-gap-check.md`；未修改生产源码、测试或原计划。
- 在上述三项任一项未完成真实反例和正式入口验收前，不应把计划顶部“本机跑通”或任何通过数改写为整案完成。
