# P2P 信令 / STUN-only 静态审计

## 范围与结论

- 仓库：`E:/Projects/Godot/FateDominationGame-master`。
- 本批只读生产代码、测试源码与 docs，仅写本文件；没有运行 Godot、没有新增测试或修改生产文件。
- 信令面：H/G ↔ WebSocket 信令 S，只交换完整邀请码封装的 SDP/ICE；STUN 由客户端显式配置，S 本身不是已实现的 STUN 地址反射服务。
- 数据面：H ↔ G 的 WebRTC DataChannel；客机之间不建立游戏网状连接，无 TURN / 游戏转发兜底。
- 权威面：正式大厅调用 `session.host_authority_peer()`，权威应在房主机器；S 声明 `disabled_on_relay`。本批没有启动/观测权威进程，不能据此验收运行机器。
- 源码支持“信令断开不关闭既有直连”，且已有本机测试源码覆盖；公网 STUN 可达、选中候选路径、真人跨网持续业务仍未验收。
- 主要缺口：手动邀请码缺少有界失败；诊断无法定位 STUN/ICE 阶段；单次邀请码导出错误污染后续邀请。不要将这些描述为已复现的运行缺陷。

## 已静态确认的边界

| 项目 | 证据 | 判断 |
|---|---|---|
| STUN-only 配置 | `scripts/net/transport/webrtc_link.gd:33-45` | 仅接受顶层 `iceServers`、server 的 `urls`、`stun:` URL；空列表允许 host-only 尝试。不依据未知 NAT 拒绝连接。 |
| 无 relay 候选 | 同文件 `:84-108`；`p2p/p2p_invite.gd:104-112` | 候选只接受 host/srflx/prflx，邀请码额外扫描 SDP 内嵌候选；不提供 TURN。底层直接调用 `accept_description()` 的检查弱于邀请码入口，正式入口现走邀请码校验。 |
| 信令不接收游戏消息 | `p2p_signal_server.gd:131-197`；`p2p_signal_client.gd:215-225` | 消息 kind/字段白名单，offer/answer 经邀请码结构、nonce、房间与目标连接校验；不能任意转发数据包。 |
| 信令建连有时限 | `p2p_signal_client.gd:85-103,117-124,141-165` | guest 全流程 deadline；host 收到 created 后清全局 deadline，每名 guest 有独立 deadline。候选收集超时也落入同一握手超时。 |
| 半应用 answer 回滚 | `p2p_invite.gd:127-149` | 远端描述/候选应用失败时 host 删除对应连接，拒绝重放，避免半应用连接继续被重用。 |
| 超时仅取消未连通邀请 | `p2p_signal_client.gd:141-149`；`p2p_invite.gd:168-174` | 取消判断是原生连接 `STATE_CONNECTED`，不是“answer 已消费”。这与旧进度文案不同。 |
| 信令丢失保留直连 | `p2p_signal_client.gd:239-254` | 不调用 driver.close()；host 仅取消未连通 pending，guest 仅在 transport 未连接时关闭 invite/transport。 |
| 信令丢失后仍 poll | `p2p_signal_client.gd:105-111`；`session/lobby_session.gd:359-364` | `invite.poll()` 在 socket-null 提前返回之前；会话随后 poll 数据 transport，既有链路不依赖信令 socket 存活。 |
| 恢复失败保留重试能力 | `p2p_signal_client.gd:42-61,249-254`；`lobby_session.gd:168-209` | 新信令握手恢复与旧直连保持是不同流程；原 resume 身份可保留。host 没有信令重登记接口，失去登记后新加入/信令恢复不可用。 |

## 静态发现与建议

### P1：手动邀请码没有应用层 deadline / 自动回收

证据：`p2p_invite.gd:21-34,52-61,162-174` 的 offer/export/poll 没有时限；`ui/lobby_screen.gd:120-127,225-235,427-440` 等待导出或直连只显示状态，不检查超时。重新点击“邀请”覆盖 `_invite_target`，没有取消之前未连通 offer。

影响：STUN/DNS 不可达、gathering 长期不完成、对方不答或答后 ICE 失败时，手动模式没有与信令模式同等的有界失败契约；旧待答连接可能积累至 `max_peers`。底层原生实现可能自行进入 FAILED，但应用当前没有将该状态转为阶段错误或统一回收，不能承诺不会长期等待。

建议：复用现有 `cancel_offer()`，在调用方维护候选收集/等待答复/直连建立的明确阶段与 deadline；替换邀请码目标前取消旧的未连通邀请，绝不关闭已连接客机。补“未答连续换码”“gathering 不完成”“answer 有效但 ICE 失败”专项。

### P1：一次邀请码预算错误永久污染所有后续导出

证据：`p2p_invite.gd:44-60` 超候选或码长写入全局 `error`，`export_code()` 对任何 id 都要求 `error.is_empty()`；`offer()` 和 `cancel_offer()` 不清此错误，只有 `close()` 清除（`:151-160`）。信令 guest 超时会关闭 invite，但 host 的单 peer 超时不会。

影响：host 任一邀请遇到预算错误之后，即使超时回收该 peer、调整预算或新建邀请，后续合法邀请仍返回空码，最终只提示握手超时；已连通对局没有被直接关闭，但新加入能力被全局错误锁死。手动界面同样受影响。

建议：将错误绑定至 peer/握手，不要靠清空全局状态损伤已有链路；失败回收后允许其他 peer 的正常导出。补两个 peer、一个错误一个正常，以及错误后取消重试的反例。

### P2：诊断没有足够阶段信息；host 的 connected 不代表有客机直连

证据：`p2p_signal_client.gd:28-40` 只有 socket-open、transport-connected、pending 数与文本；nat 明确 unknown，selected pair 明确 not_observed，公网明确 unverified。`transport/enet_transport.gd:160-161` 只检查 MultiplayerPeer 总体 CONNECTION_CONNECTED；host server 的总体状态不能当作某个 guest 已连接证据。`webrtc_link.gd:122-127` 不采集连接状态历史、gathering 状态转移、失败原因或每 peer 候选统计。

影响：`direct_transport_connected` 在 host 侧有语义歧义；信令不可达、gathering 卡住、没有 srflx、ICE 失败或业务身份恢复失败难以区分。当前不能断言“双方对称 NAT”或“STUN 不可达”，也不能凭 collected candidates 宣称 selected pair 直连。

建议：增加角色与逐 peer transport/ICE/gathering 状态、阶段开始/截止时间、候选类型/地址族计数和错误码，避免公开完整地址/SDP/恢复票据。保留 unknown/unobservable 的真实语义；只有具备真实 STUN 请求/响应或原生统计才能诊断 STUN、NAT 与选中路径。host 字段改为 server_ready 与 connected_guest_count 等不同含义。

### P2：原生失败未完整向上报告

证据：`webrtc_link.gd:73-77` 本地描述失败只写 link.error；`p2p_invite.gd:52-54` 不读取该 error；driver 只检查是否能导出，最终报泛化超时。`webrtc_link.gd:98-100` 回放提前到达候选时忽略 `add_ice_candidate()` 返回值，`poll():122-124` 也忽略 poll 返回值。

影响：失败没有立即进入可诊断阶段；不能从 driver.error 得知原生握手失败原因。提前候选队列不是当前完整邀请码主要路径，因此该返回值缺口优先级低于正式导出路径。

建议：统一复用现有错误传播机制，将 peer id、阶段、Error 码向上关联；回放候选失败显式回滚。测试本地描述失败、initialize/create_offer 失败与候选回放失败，不伪造成功。

### P2：信令断开后的房间码和警告含义需要明确

证据：`_fail_signaling():239-254` 保留 room_code/url/role；host 无 reconnect 分支。服务端 `_remove():232-251` host 掉线会删除登记并发 room_closed。`_receive():210-211` 对没有 reason 的 room_closed，无论是否已建立直连都给“已建立的直连不受影响”默认文本。

影响：原码仍显示不代表信令登记仍有效；连接未建立的 guest 收到 room_closed 时文本未明确其握手已失败。不是已有数据面断线证据。

建议：分别显示“既有直连仍可用 / 新加入不可用 / 该次握手失败”，保留旧码用于审计但标失效；如需 host 信令恢复，使用独立重登记流程，不以 driver.close() 重建整个游戏连接。

### 文档过时点

- `docs/multiplayer-p2p-progress.md:11` 称“已接受应答的连接不能通过取消邀请关闭”；当前 `cancel_offer()` 只保护 ICE STATE_CONNECTED，answer 已消费但未连通仍可取消，应改为“已经连通的链路不能取消”。
- `docs/multiplayer-plan.md:110,117-118,135` 描述增量候选、自带反射、STUN 下发与 NAT 诊断；当前实现批量等 gathering_complete 后传完整码，不能把规划作为已实现事实。历史 STUN 可达声明也不能替代当前现场验证。
- `docs/cross-network-p2p-test-plan.md` 正确区分源码、本机测试与真人跨网，特别 CN07/CN08/CN09/CN10，建议以此为现场验收口径。

## 已有测试源码覆盖（本批未执行，不继承历史通过数）

| 测试 | 源码实际覆盖 | 不覆盖 |
|---|---|---|
| `net_p2p_signal_client_test.gd:12-64` | localhost + 空 iceServers；自动握手；未答 peer 超时；service.close 后 ready 到达；客机断线回收 | 真实 STUN、跨网、反复换邀请码、导出全局错误 |
| `net_p2p_signal_test.gd:32-70` | 本机实际 WebRTC、nonce/跨房间/重复 answer、拒绝游戏信令、信令关闭后 packet 实际接收 | 真人双公网、60 秒连续双向业务 |
| `net_p2p_expiry_direct_test.gd:3-9` | 继承信令核心用例，用真实房间 TTL 到期替代 service.close | 完整 driver 的各失败阶段、公网 |
| `net_p2p_resume_identity_test.gd:47-85` | WebRTC 掉线暂停、不 AI 托管；新直连恢复原席位/待答；关闭信令后完成待答；再次恢复失败保留身份重试 | 房主信令重登记、真人跨网恢复、房主崩溃恢复 |
| `net_p2p_invite_test.gd:11-53` | 空 iceServers、本机手动 offer/answer、非法编码、重复应答、准备指令 | STUN 故障、有界超时、预算错误恢复 |
| `net_p2p_signal_limits_test.gd:4-30` | 配置原子拒绝、真实 WS 闲置超时、速率超限资源回收 | 真实 ICE/STUN 阶段区分 |
| `net_p2p_authority_boundary_test.gd:3-45` | 静态/组件 seam：游戏 kind 拒绝、诊断 unknown/unverified、TURN/relay 拒绝 | 网络运行、权威实际 spawn 机器、实际选中路径 |

## 主代理后续验收建议

### 代码可验收（串行，另批授权后才运行）

1. 针对上述静态缺口补真实入口专项；先证明错误导出影响下一邀请、旧邀请码资源未取消，不用 Python 替代 GDScript 行为测试。
2. 对照已有测试，分别运行手动邀请、信令 client/核心、限流、TTL direct、恢复身份与权威边界；逐套记录退出码、RESULT、SCRIPT ERROR 与原生 warning。
3. 新增建立前停止信令、一个 guest 未连通另一个已连通时停止信令、room_closed/无效回复/发送失败矩阵。既有 guest 必须继续收发，未连通 peer 有界失败并清理。
4. 诊断断言区分 host ready 与 guest connected；断信令保留 driver poll，不能用假 connected 字段替代真实 packet 接收。

### 真人/多机/跨网验收（本批完全未执行）

- 按 `docs/cross-network-p2p-test-plan.md` CN07 验证 STUN 正常、单/双侧 UDP 阻断、DNS 失败；没有 srflx 不等于直连必失败。
- CN08 先达业务就绪，仅停止信令，保留 H/G 网络；持续至少 60 秒，双方各至少三项合法业务并看到权威更新；第三个新握手有界失败。旧局保持与掉线后恢复分开记。
- CN09/CN10 分开记录信令不可达与 ICE 不可达，失败绝不自动 TURN/游戏中继/切 dedicated 冒充成功。
- 记录真实 STUN 请求/响应、对等流量与选中候选；原生 API 不可观测时写 unobservable。不同公网出口、真人两设备、房主/信令进程位置、导出版本与平台均需真实证据。

## 本批交付边界

- 创建文件：仅 `scratch/net-batch-10/p2p.md`。
- 验证方式：只读源码与测试断言交叉核对；报告由文件写入工具确认落盘。
- 未执行：Godot、窗口操作、网络/进程启动、公网测试、生产修复、静态 GDScript 解析。
- 无环境阻塞；运行验证未做是用户明确边界，不应标成通过或失败。
