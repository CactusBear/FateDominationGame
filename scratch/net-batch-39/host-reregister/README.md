# 房主无损重注册：只读审计、最小协议、隔离候选

## 交付状态（不能当作已实现生产功能）
- 生产未修改、Godot 未运行、未读取任何用户凭据。
- `candidate.v4a` 只添加两个协议核心模块：签发能力/挑战证明、客机 locator 校验。没有把半完成认证挂到生产 create 分支；不是可直接合并的端到端修复。
- `candidate/*.gd.txt` 是可审阅源码副本，不声明全局 class_name，也不会被项目当 .gd 扫描。
- `tests/signal_host_registration_draft_test.gd.txt` 是真实 GDScript SceneTree 测试，调用实际生产 client 的 `_fail_signaling` 和候选认证模块。不是 Python 网络模拟测试。
- 已用 gdtoolkit 做三个 .gd.txt 的语法解析，退出码 0；不等于 Godot 类型检查、WebRTC 验收或测试 RESULT。
- `baseline.json` 记录六个生产入口文件内容 SHA256。目录已有大量其他工作树改动，未回退、未覆盖。

## 三个平面
信令面：房主/新客机 -- WSS --> relay（只注册/offer/answer/ICE）。
数据面：客机 -- 已建立 WebRTC data channel --> 房主 gateway -- 本机回环 --> 原权威 worker。
权威面：原房主机器上的原 worker PID/instance_id；relay 禁止加载规则、保存对局、启动 worker、转发游戏包。
重注册只替换 WSS socket、信令 boot/client 索引、locator；不更换 WebRTC peer，不重开数据通道，不改变 worker 或席位。

## 已读生产链及问题
1. `scripts/net/ui/lobby_screen.gd:363-371`：信令创建按钮调用 `_signal.host()`，不是重注册入口。
2. `scripts/net/p2p/p2p_signal_client.gd:63-74`：host 先 session.close/close，再 link.open 和 host_authority_peer。重复点创建一定走权威重建，不能复用此入口。
3. `scripts/net/session/lobby_session.gd:32-42`：host_authority_peer 同样 close 并 client.start；它是新房间入口，不能用于信令恢复。
4. `scripts/net/session/authority_host_client.gd:32-61,63-108`：外部 peer 在 gateway.transport；UI session.transport 是到本机 worker 的回环连接。新码发布必须用 gateway 外部 transport，不能拿 UI session.transport 给所有客机广播。
5. `p2p_signal_client.gd:241-256` 已刻意不调用 close，保留已建立直连，仅取消未完成 offer。可以复用失败收口；但 socket 置空后 poll 返回，房主没有恢复入口。
6. `p2p_signal_client.gd:42-61` 只提供 guest reconnect，且 guest 有 resume identity 才允许；不能拿来恢复房主。
7. `p2p_signal_client.gd:129-133,169-227` 只有 create/join 和 created 等严格字段；新增协议必须同步严格白名单，不能把额外字段塞进旧 created。
8. `p2p_signal_server.gd:139-159` create 未认证；`232-258` host 断线删内存房间并 room_closed，close 清空全部。重启不会保留能力、身份绑定或旧码。旧 room code 是 locator，不是房主权限凭据。
9. `lobby_screen.gd:204-217` 重连按钮按数据面掉线显示，新码只显示到 Room.text、提示人工复制，没有 guest 新码事件。需要独立“重连信令”入口，不借用规则崩溃恢复。
10. `authority_host_client.gd:110-150` recover_worker 是另一个功能，会恢复规则进程和撤销外部路由；信令重注册严禁调用。
11. invite.offer (`p2p_invite.gd:42-51`) 会避让现有真实 peer id；信令 `_joined_clients` 的 client id 却会随 relay 重启从头分配。必须清理旧信令 client→peer 索引或以 boot 分区，不能因 client id 重用拒绝新客机，也不能关闭旧 peer。
12. `server_bootstrap.gd` 有纯信令专用配置白名单；可信根/签发配置必须在那里及 CLI/配置样例显式接入，不能默认依赖 game 角色身份注册库。

## 认证不能靠“重启后再提交同一公钥”
必要部署前置：信令注册服务具有跨重启的可信能力签发根。推荐持久签发私钥在仅注册服务可读的配置存储，可信公钥在每次启动固定加载；或可信外部签发服务 + relay 固定可信公钥。本轮只设计依赖，不生成/读取部署钥。
- 首次会话随机产生 session_id；房主以已有 player_identity 的持有证明认证。签发能力绑定 session_id、host_public_key、authority_instance（房主 worker instance_id）、audience（稳定服务标识）、expires。
- 能力由持久可信 issuer 签名，房主内存保留完整票据。不能从客户端票据里取 issuer 并信任它；不能由 client 自签 capability 当成注册授权。
- 重启时 relay 生成全新随机 boot_id，并提供随机一次性 nonce/request。房主用能力绑定的身份钥签名新挑战；proof 绑定能力正文及签名、服务 audience、boot 和 request。
- 只存内存的旧随机 token/hash 在重启后无从验证。若不能部署可信根，则失败关闭并明确“重注册认证未配置”；不能退回匿名 create、旧码查找、用户名、IP 或首个提交公钥者认领。
- 自带 capability 能证明签发授权与身份持有，不证明物理 worker 活着；房主本机必须校验当前 authority_host.room_id/instance_id/ready、会话对象、已确认 owner 和 capability 相同。relay 不应启动/探测规则进程。
- 能力过期或签发根丢失不关闭仍活的数据面；明确提示无法恢复信令，显式重新授权。短期能力续签也要证明现有 host key；撤销/账户封禁若要求跨重启有效，需持久撤销记录或外部签发权威，纯自含签名无法提供即时撤销。
- 管理员旋转根需显式 trusted key ring/有效期，不能把新实例随机 key 自动当旧票据可信根。

## 最小消息（独立 kind，不复活旧码）
所有 WSS 入站有严格 keys/类型/长度/预算；二进制能力字段在线上编码为固定长度 base64，解码后送核心。expires JSON 数值仅有限整数且安全范围内归一化，不接受小数/溢出；能力签名 canonical context 必须按固定数组序列，不能依赖 Dictionary 顺序。
1. `host_register_begin {kind, capability}`：没有 old_room 参数。当前 socket 必须未加入房间；新建与恢复均用同一授权注册路径。首次签发接口另走认证 bootstrap，不沿用匿名 create。
2. `host_register_challenge {kind, boot, request, challenge}`：32-byte nonce、32-hex boot/request，绑定当前连接和 deadline。要求 WSS；仅显式本机测试允许 ws。
3. `host_register_proof {kind, boot, request, signature}`：验证信任根、有效期、audience、host key proof 和一次性挑战，验证前不分配房间、不删其他 host。
4. `host_registered {kind, boot, request, session, room}`：成功之后生成全新随机 room。服务器回复必须对应正在等待的请求；失败发送普通 error。
5. `signal_room_update {kind, session, authority_instance, boot, revision, room, url}`：房主→客机，走现有可靠直连。每次成功 registration 房主本地 locator_revision++，不能用 boot 随机字典序，也不能用 server 重置计数。guest 接收后只更新 driver url/room 与 UI，不触发 join/reconnect，不清票据或重新初始化数据。
6. `signal_room_ack {kind, session, revision}`：客机确认；房主保留最新更新，按已认证路由重试，晚加入的客机也收到最新 locator。ACK 的发送者取真实 connection，不信任自报 member/username。只是控制消息，不进入规则意图/事务。

## 服务端原子提交与安全约束
- boot 为服务实例标识，不是权限票据。challenge 在 close/remove/过期时清除；每个连接最多一个挑战。候选 core 自身不做定时清理，server 集成必须 forget/expire。
- 同一 (audience, session) 只能一个当前 host binding；第二个已认证 socket 采用显式 compare-and-swap request generation，不能让无证据连接抢占。当前实例幂等重试返回同一此次注册结果；不同成功登记另分配新码。
- room/code/capability 三者分离，不能把新码当 game resume token。旧码不登记、不转发跳转、不自动认领；旧码即使不存在也不提供身份结论。
- max_clients/max_rooms/rooms_per_ip、频率限制、packet budget、accepting_rooms=false 同样适用于 begin/proof；验证后提交前再检查容量，失败不影响旧数据面。
- capability 不含旧 room code。因此重启后“新码恰巧等于历史码”的随机碰撞无法凭内存绝对排除；若要求数学上绝不复用，room namespace 要含 boot 前缀或持久 used-code 集合。推荐 boot 前缀，仍禁止旧码恢复，不以查询旧码作认证。
- 不跨 boot 接受 offer/answer，handshake 关联当前登记/target 和 nonce；旧半握手全部取消。现有建立的 peer 和 server peer_ids 的内存数据不需要复原；新 offer 使用 invite 避让真实连接 id。

## 房主状态机及最小接线位置
ACTIVE → SIGNAL_LOST（仅 socket/未完成 offer 清理）→ REGISTER_CONNECTING → CHALLENGE → REGISTERED。
CONNECT/认证/ACK 失败回 SIGNAL_LOST，允许带抖动的有界重试或按钮重试，不回 NEW_HOST。保持原 room_code 可供显示但标“失效”；只在验证 registered 后替换可用 locator。
- client 新增 reregister_host(session)；先本机检查原 authority/session/peer/binding，再只新建 socket。严禁 session.close、self.close、invite.close、invite.link.open、host_authority_peer、recover_worker、session._prepare_reconnect。
- poll 的 host 分支改成已授权 register_begin，而非旧 create。保留旧字段 `_sent_request` 的握手重置；新增等待挑战状态与 request/boot 绑定，不能无限重复 begin。
- 不再使用 `_open` 的默认 room_code=空副作用直接发布；可复用它的 URL、buffer、deadline 检查，locator 只在 ACK 原子更新。
- `_pending` 取消后清空；旧 `_joined_clients` 索引重置但真实 `_connections` 不动。_sent_answer/_received_offer 的 guest 状态不要误共享给房主重注册。
- authority_host_client 加本机 publish_locator(message) 和重发缓存，用 gateway.routes 中已认证 attached 路由及 gateway.transport.send；不广播到未完成 join/proof 的连接。它不执行规则，不修改 worker snapshot。
- session `_receive` 的 guest 分支在 sender==1 后拦截 locator/anchor 控制消息，调用 driver.accept_locator，再 changed.emit；消息在 host supervisor 消费，禁止进入 worker 的规则路由。
- Room code UI 经独立 room_code_changed 事件更新（或兼容 room_created），创建按钮在已有 authority 的信令模式改“重连信令”；不能调用 `_host` 并 _reset_data_sync。战局中的 reconnect presenter 也应依赖 driver locator，而非大厅控件文本。
- UI 只显示新码、信令状态，绝不显示 capability、public key、fingerprint、signature。

## 客机信任锚与发布边界
候选 Locator.accept 的 sender==1 仅在已建立、未替换的原房主数据通道成立；它不是完整跨网络公钥认证。当前 LAN identity 流程主要认证客机给房主，不能宣称已具有客机对房主双向密钥认证。
初次加入需从可信注册服务获取经 issuer 签署的 session/host_key/authority_instance 锚，并验证 host 对 SDP/DTLS fingerprint、offer nonce 与 session 的签名；原连接保留此锚。恢复连接也必须核对同一锚，不能盲信新码对应的第一个 offer。locator 若离开原可靠通道（人工分享/离线转发）则还要 host 签名，receiver 用已固定 host_key 验证。
已经完全掉线、未收到新码的客机，不可能从已丢失的内存信令状态或断开的 data channel 获得通知。提供人工分享最新码/签名 locator，或另行设计可信持久 rendezvous；这不是“旧码自动复活”。本方案保证已建立通道的客机自动收到新码；持续掉线者需安全外部通知。
URL 必须与服务 audience/部署允许列表绑定；候选 locator 只校验 wss 语法，集成还必须校验允许 endpoint、长度及 packet budget，不能把随意 WSS URL 当作受信任服务。

## 候选和测试边界
能力 core 可跨 server 内存丢失验证旧签发能力，但不含网络 wire codec、issuer 配置、首次签发服务、server 房间原子提交或容量闸。Locator core 提供单调更新和 session/instance 固定，但 bind 输入必须从上述可信锚取得。
测试草稿包含真实临时 RSA 签名、换钥冒认、跨服务、过期、错 socket、重放、复制能力无钥、新实例旧 proof 拒绝、新实例新 proof 允许、可信根缺失失败关闭、客机伪发布、过期 locator 和 authority instance 变更拒绝；直接调用真实 client 的失败清理断言 worker/link 对象身份不变，只取消未完成 offer。
它不启动真实 worker，没有证明 PID、房间 revision、规则执行量不变；未包含 register_server 的线上实现，也没有宣称无损重注册功能已跑通。

## 合并后必须做的真实 GDScript 集成验收（本轮禁止执行）
1. 隔离主机启动 worker、两个客机建立真实 WebRTC；记录 PID/instance_id、gateway/link/peer 对象、peer ids、match journal revision、恢复 token、data_revision。
2. 只停止 relay，持续发合法游戏意图并断言 worker 继续响应、未进入 AI 托管；失败收口不关闭 peer。
3. 重启全新 relay 对象（全部 rooms/keys/challenges 内存丢失，仅固定配置可信根），房主经真实 begin/proof 重注册；断言新码、新 boot、原 PID/instance/peer 不变，没有新规则初始化事件。
4. 客机不重新 join 即 ACK 新码，data_revision/席位/token 不变；战局 UI、大厅 UI 都可见状态。
5. 一个客机收到新码后真掉线，用新的 code 及原 seat identity/key 重新握手，验证同一稳定 member 回来。
6. 第三个新客机加入，强制 server client id 与旧 id 冲突，断言旧 peer 不断开、新握手不被 `_joined_clients` 误拒绝。
7. 窃取 capability 但换 host key、旧 boot proof、重放 proof、错 socket、错 audience、过期、容量满、停止接纳、恶意游戏消息均拒绝；对局数据面仍工作。
8. delayed old registered/update/ack 不覆盖新 revision；close/leave 取消重试，真正主动离开才关闭所有资源。
9. 整个过程检查 relay diagnostics authority disabled/game_forwarding=false，不生成规则 save，不转发 intent/snapshot/blob。
10. 多机/公网 NAT、持续 ICE 可用性、信令 WS/WSS 与浏览器插件能力是独立实测，不由静态解析或本机 fixture 推断。

未执行命令：Godot --headless/--import/--script/--scene、任何生产 patch、任何部署钥配置/读取。
