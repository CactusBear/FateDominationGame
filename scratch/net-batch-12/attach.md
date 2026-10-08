# 内部回环 ENet attach / peer / channel / room 绑定审计

## 结论与验证边界

- **静态确认：正常链路没有发现把公网 peer 当作 worker peer、错误目标 ID、join/state 频道越界，或 server_room_id 未提前赋值导致 join 被过滤的必现故障。** 外网连接成功、内部连接成功、附着通知入队、业务 join 成功是四个不同阶段，不能互相替代。
- **存在明确的“连接已建立但首条 join 没有送出且不再重试”分支**：客户端先置 `_hello_sent=true`，不检查 `request("join")` 的返回值；同类问题存在于 `_server_sent` 与 `_identity_sent`。传输入队失败会被客户端静默忽略，导致连着但大厅空白。此为静态确认的失败处理缺口，**不是本次已复现的实际根因**。
- 网关正常转发的请求未发现无条件静默丢弃；未附着、白名单/身份失败、send 失败会发 error。worker 有协议/序号/身份拒绝；state 消费有静默过滤条件，见下文。
- 本次严格未运行 Godot、服务端、worker 或测试；没有本次连接日志/抓包可证明实际 join/state 已到达。因此不能声称当前实际会话发生了丢包，也不能给运行 PASS。
- 只写本报告，不修改生产脚本。仓库 HEAD 为 `8b46af0`；三份核心脚本在本次 git status 中均为未跟踪文件，结论基于现有磁盘源码，不基于 HEAD 内容。行号为本次读取快照。

## 拓扑与身份契约

信令面：本段不涉及 P2P 信令，不经信令服务器转发对局。
数据面：客户端 → 网关公网 ENet → 每公网连接独立的 `127.0.0.1:worker_port` ENet 客户端 → worker；回复沿同一路由返回。
权威面：worker 所在房主/独立服务端机器执行规则，网关只路由。

| 标识 | 来源与用途 | 不可混用 |
|---|---|---|
| 公网 connection | 网关 transport 的消息 sender，作为 `routes[peer]` 键 | 不传作 worker 目标/新成员 ID |
| 内部 connection | `route.link.peer_id()`，独立 ENet 客户端 unique ID，必须 >1 | 与公网 unique ID 可不同 |
| 服务器目标 | 两跳的请求都 send 到各自 ENet server `1` | worker 回复 sender 为 `1`，不是内部客户端 ID |
| 稳定 member | 初次 join 等于内部 connection；恢复时来自已验证 resume ticket | 重连后可能不等于新内部 connection |
| server_room_id | manager 的 room ID，经 server_attached 返回客户端 | 是房间 ID，不是 peer/member ID；并非 worker snapshot revision |

源码依据：`enet_transport.gd:49–62,157–161`；`server_gateway.gd:128–136,280–321`；`lobby_session.gd:159–163,244–289`。

## 正常 attach → join → state 链路

1. `join_server()` 先 `join()` 清理旧会话并建立公网 ENet，再保存 server_join/server_create 请求（`lobby_session.gd:352–357`）。
2. session poll 完成公网 transport poll，认证通过后发 server_list 与建房/加入；此时不会发业务 join，因为 `_server_peer_id==0`（`359–389`）。
3. 网关 `_attach()` 检查权限及 room/PID/instance/mode/ready/OS 所有权，创建独立 link，先挂回调，连接回环，再次校验绑定，最后登记 `routes[公网peer]`（`server_gateway.gd:280–306`）。`connect_to()==OK` 只表示创建连接请求成功，不代表连接已建立。
4. 网关 poll 对 link.poll 后再次校验路由，等 `is_connected_to_host()` 才发 server_attached；通知成功入队才置 `route.attached=true`（`75–94`）。
5. 客户端只从公网 server sender==1 接受附着；保存 `server_room_id` 与内部 `_server_peer_id` 后，同一次 session poll 后段即可发 join（`503–521,563–568,386–389`）。changed 信号不是发送 join 的必要条件。
6. 网关只向 attached 且实例仍匹配的 route 转发；重建 join 的 gateway_identity，上游目标固定 `1`（`117–139,505–517`）。
7. worker 验证请求/seq，join 创建连接↔成员映射并发送 identity；首次成员 ID 使用内部 connection，恢复成员使用票据 member（`lobby_session.gd:254–289,680–694,824–840`）。
8. 成功 join 调 `_publish()`，对 `_peers` 成员经 `_peer_by_member` 转回内部 connection；网关只接纳 sender==1 且当前实例的回复，再转公网 peer。客户端收到 room 且 revision 更新后保存 view（`lobby_session.gd:227–228,870–895,646–656`；`server_gateway.gd:316–322`）。

**时序判断**：正常客户端等 server_attached 才发 join；该通知由网关本轮入队并马上置 attached，网关下一轮才读客户端请求。没有找到正常轮询中 join 先于 route.attached 的必现窗口。worker 的 identity 和 room 都用可靠 channel 0；初次加入不存在因为两个 peer ID 不同而必然丢 state 的路径。

## 频道审计

- 两侧 ENet `create_server/create_client(...,3)`；收发都限制逻辑频道 `0..2`，send 固定可靠传输（`enet_transport.gd:42,54,95–101,123–155`）。
- server_attached、join、identity、room 为 channel 0；文件/目录/素材相关网关转发为 channel 2（`server_gateway.gd:87,132–133,321,430–431`）。无 join/state 频道越界。
- worker 的 match_bind/match_view 使用 channel 1，但网关 `_channel()` 将它们重发为 channel 0。这会失去公网 match 专用频道隔离、增加队头阻塞，但接收端不按频道分派业务，**不是直接丢弃理由**。原始频道未进入 message_received 信号，网关目前只能按 kind 重选频道。
- 超过 128 包的单次 poll 预算只推迟后续读取，没有主动清空剩余包（`enet_transport.gd:30,91–121`）。
- 真正传输拒包：频道非法、空包、超预算、非基础 Dictionary、分帧校验/超时；会触发 packet_rejected。网关上下游均接线，生成固定 NET_DIAGNOSTIC 与 error（`server_gateway.gd:31–35,294–295,392–405`）。这不是无日志的正常 join 丢弃分支。

## 有条件丢弃 / 不发送 / 状态不刷新

### P1-A：一次性发送标记先置，未检查入队结果（已静态确认）

`lobby_session.gd:371–377,386–389` 先写 `_identity_sent/_server_sent/_hello_sent=true`，然后调用 request；request 返回 transport.send 的 Error（`391–402`），这些调用处未消费。

`enet_transport.gd:124–133` 即使 get_connection_status 已 CONNECTED，仍要求 `_connected_peers.has(target)` 和底层远端 STATE_CONNECTED；缺少对应 peer_connected 记录、断线时序或 put_packet 失败都可能返回非 OK。不能仅凭 CONNECTED 推断入队成功，也不能仅凭源码断言这些异常已经发生。

后果：公网连接仍可显示已连接；若 join 没入队，worker 不会生成成员/identity/room，客户端又不再发 join。本路径没有业务 error，因为网关根本没收到请求。安全修复应记录提交结果、结束 pending、明确“提交未确认”，**不要自动重发 join/create/修改命令**。附着时也应显式确认内部 peer `1` 的可发送状态，不能把 attached 当 join 已完成。

### P1-B：附着 room 绑定只做类型检查（已静态确认）

`lobby_session.gd:563–568` 仅要求正在 server 模式、`_server_peer_id==0`、room 为 String、peer_id 为 int>1；没有验证 room 格式、显式 server_join 的预期 room、请求 seq、PID/instance/mode。网关也不在 server_attached 中携带原请求/实例字段。

正常可信网关按 route.room 发送，不是常规绑定必错；但错误/晚到的同连接附着可以覆盖 server_room_id，并使 hello 去往非预期房间。重复 attached 在 `_server_peer_id>0` 时被忽略。恢复入口清零内部 peer 并使用原 server_room_id 请求新 route（`204–215`）；稳定 member 优先于内部 peer 返回，符合重连契约。建议沿用 manager 绑定扩展关联，不通过删除校验绕过恢复安全边界。

### 显式拒绝，不应称作静默丢包

- 网关非 attached 或实例失效：`server_gateway.gd:128–139` 返回“尚未加入服务器房间”。
- worker 未 join 的连接发其他业务：`lobby_session.gd:680–685`；旧 seq：`687–690`；join 上下文/口令/恢复凭据错误：`254–289,824–829`。均有拒绝返回。
- 网关 error 关联字段是 request_seq，客户端 request_rejected 只读 seq（`server_gateway.gd:407–410`；`lobby_session.gd:657–664`）。rejected/error 仍可显示，但指定 pending 无法按序号完成。不要将“UI pending 没结束”误判为没收到任何回复。

### 真正静默过滤 state / 回调

- 网关 worker 回复 sender!=1 或旧 route/实例：直接 return（`server_gateway.gd:316–317`）；旧路由校验用于隔离新 worker，是合理安全过滤。现有源码缺少该过滤阶段的结构化诊断，实际是否命中需日志。
- 客户端 sender!=1：return（`lobby_session.gd:519–521`）；公网 worker 回复经网关发出，正常 sender 就是1，不该改为 `_server_peer_id`。
- room state 非 Dictionary、revision 非 int、members 非 Array 或 revision<=当前 view：忽略（`646–656`）。初次 close 清空 view，正常 worker revision 更新能够通过；不能据此假定首次 state 必丢。
- match_view 在未 match_bind、pending/actions 类型错误或 mirror 拒绝时忽略（`617–630`）。这是 match 状态条件，不是 lobby join/state 必丢；实际要分别记录 bind/view 顺序和 revision。

## 实例绑定审计

manager.instance_binding 返回 room/PID/instance_id/authority_host_mode；binding_matches(true) 要求当前 room.id、实例、mode、ready、正 PID 及原生进程所有权验证（`server_room_manager.gd:77–98`）。网关在 attach 前后、link poll 前后及回复回调重复检查，旧实例不会自动继承新路由（`server_gateway.gd:280–317`）。这条安全链已存在；阻断时应查绑定/OS 所有权而不是放宽检查。

worker 监听回环，启动后 dedicated 去掉虚拟服务端成员1并把 owner 置0；首次真人 join 再获得 owner（`server_room_worker.gd:155–169`；`lobby_session.gd:831–833`）。worker 的 server ID1不应该冒充玩家成员，当前逻辑没有该混用。

## 主代理最小取证/验收项（本次 NOT_RUN）

1. 复用 `net_server_gateway_test.gd` 正常用例：两玩家同 room、内部 IDs 不同、owner==稳定 member、双方 room.members==2；测试源码存在不代表本次通过。
2. 每跳只记固定阶段、连接号、room/PID/instance/mode、seq、channel、Error；禁止记录 join args、认证 key、resume token、密码或牌面。
3. 依次对账：公网 CONNECTED与 peer_connected(1) → 管理请求入队 → worker ready/绑定通过 → 内部 CONNECTED与 peer_connected(1) → attach notice入队/消费 → join入队/网关接收/内部转发 → worker join结果 → identity/room入队 → 网关回复 → 客户端state接受或固定拒绝原因。
4. 补失败夹具：CONNECTED但缺peer记录、join返回非OK、attach通知发送失败、错误预期room、旧请求/旧实例回调、重复/旧revision、两房间隔离。失败时确认不会假报成员已加入或自动重复业务动作。
5. 若实际日志只有 CONNECTED 而没有 join 入队结果，首先补客户端一次性发送结果诊断；若已有 worker join 成功但客户端空 view，则按回程 sender/route/拒包/revision链排查，不再把问题定位在 ENet 握手。

交付范围：新增本报告；未创建测试、未编辑生产文件、未安装依赖、未启动任何 Godot 进程。当前结论为 STATIC_CONFIRMED / RUNTIME_NOT_RUN。
