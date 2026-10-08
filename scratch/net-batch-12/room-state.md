# room state／成员／选人／对局消息只读审计

## 结论与验收边界

- **正常路径的生产与消费契约是接通的**：worker 使用 `MatchLobbySession` 作为权威；网关原样转发 `room`、`selection`、`match_bind`、`match_view`；客户端存在对应接受分支，并由 `changed` 驱动大厅和对局展示。
- **没有发现正常首入大厅必然因 `members` 类型或 room revision 字段不一致而丢弃快照。** 权威原始 `members` 是 Dictionary，但发送前明确转成带 `id` 的 Array，正好符合客户端检查；线上是 Variant 二进制序列化，不是 JSON，因此不能把 JSON 的整数变 float 问题套到正常网络消息上。
- 静态确认的停滞缺口：**网关拒绝回执字段 `request_seq` 与客户端读取 `seq` 不一致；首入请求在发送失败时仍消耗一次性发送标记；worker 快照发送失败没有闭环；镜像拒绝原因不向 UI 报告；部分实际状态改变没有推进 room revision。** 其中初始“没有成员列表”优先检查 attach／join 单次发送链，对局“已开始但仍停大厅”优先检查 bind／mirror 接受链。
- 本轮遵守“禁止运行 Godot”：没有启动编辑器、headless、套件或游戏，也没有修改生产代码。**本报告只能证明源码链路和条件缺陷，不能证明某次真实客户端已经收到并接受了权威快照。** 未取得本次连接逐阶段收包日志，未声称复现真人／多机结果。

路径以下均相对仓库根目录。

## 1. 实际消息链路与字段契约

### 独立服务端拓扑

客户端 ENet → `ServerGateway.transport` → 每客户端独立 `route.link` 回环 ENet → `server_room_worker` 的 `session.transport`。规则与权威状态在 worker；这里是独立服务端数据面，不是 P2P 信令中继。

| 阶段 | 生产／转发证据 | 客户端接受／展示条件 |
| --- | --- | --- |
| 申请房间 | `lobby_session.gd:352-357, 371-377` 发 `server_list` 和 `server_create/server_join`；网关等待可信 worker 后建立 route | 身份认证完成（配置身份时），`_server_sent == false`，传输连接有效 |
| 内部路由就绪 | `server_gateway.gd:83-91` 发 `{kind:server_attached, room:String, peer_id:int}`，入队成功才置 `route.attached` | `lobby_session.gd:563-568` 要求 server request 非空、旧内部 ID 为 0、`peer_id > 1`，随后设置 `server_room_id/_server_peer_id` |
| 加入权威房间 | `lobby_session.gd:386-389` 发 `{v:1,seq:int,kind:join,args:{name,spectator,password,…}}`；`server_gateway.gd:118-136,204-244` 重建公开信封，join 的认证上下文由网关补入 | worker `lobby_session.gd:683-694,824-840` 检查字段／递增请求序号，加入成功后记录稳定成员；不能用外部网关连接 ID 代替房间内部 ID |
| 私有成员身份 | `lobby_session.gd:244-251` 发 `identity {member,token,data_revision}`，`_peers` 已登记 | `:555-561` 接受后 `peer_id()` 优先返回稳定 member，`identity_ack` 回权威；`:160-163` 不再依赖重连后的临时连接 ID |
| room state／成员 | `lobby_session.gd:875-895` 生成 `owner,phase,revision,settings,members[]`，附 `can_start,data_ready,data_revision,dedicated,password_required`；`server_gateway.gd:316-322` 原样转发 | `lobby_session.gd:646-656` 只接受 sender=1、state Dictionary、revision int、members Array，且 `revision > view.revision`；复制后 `changed.emit()` |
| 选人状态 | `lobby_session.gd:847-856,1428-1433` 发 `selection {state:view_for(member)}`；`selection_authority.gd:41-53` 输出 `seats,choices,selected,complete` | `lobby_session.gd:631-634` state Dictionary 即接受，无 room revision 检查；大厅 `lobby_screen.gd:540-554` 展示 choices／complete，开始对局还要求自己为 owner、phase=selecting、data_ready |
| 对局身份与视图 | `lobby_session.gd:775-780,1511-1529` 先 `match_bind {observer:int}`，后 `match_view {state,pending,actions}` | `:617-630` 首个 bind reset mirror，view 必须已绑定且 pending/actions Dictionary、`_mirror.accept(state)` 返回 true；只有接受后才更新待答与动作并发 changed |
| 进入真实战局 | 权威 phase=playing 本身并不触发场景切换 | `lobby_screen.gd:556-575` 以 `session.read_match()` 非空为条件进入 `battle_board_v2`；room 已显示 playing 而 mirror 未接受时，仍停大厅是代码明确结果 |

room、selection 默认 channel 0；worker 的 bind/view 为 channel 1。网关 `_channel()`（`server_gateway.gd:430-431`）把 bind/view 重映射成外部 channel 0，所以不能声称网关把 bind/view 分到不同通道导致互相乱序。直接 LAN/P2P 的 bind/view 本来同为 channel 1。数据／目录用 channel 2，不保证与 room 跨通道先后。

## 2. 静态确认的缺陷与具体停滞条件

### A. P1：网关拒绝序号字段不兼容，客户端提交锁不能解除

- **生产端**：`server_gateway.gd:407-410` 的 `_fail()` 发 `error {reason,request_seq,diagnostic}`；发送失败和格式／路由拒绝走这条路径。`:400-405` 无可信序号的拒包明确发 `request_seq:-1`。
- **消费端**：`lobby_session.gd:657-665` 仅检查 `message.seq`，不读取 `request_seq`，所以可关联的网关拒绝也不触发 `request_rejected`。
- **停滞链**：`network_choice_panel.gd:110-114` 提交后锁住按钮，`:124-130` 只在收到匹配序号的 `request_rejected` 时解锁；`:33-36` 也可被新视图序号解锁，但网关拒绝尚未转到 worker 时不会自动发布新 match view。
- 因而可出现“已收到错误／changed，但仍等待主机确认、同一待答不能再提交”。这不是 room revision 回退，而是**拒绝回执信封不一致**。`group_selection.gd` 与 `v2_view_presenter.gd` 也订阅了 `request_rejected`，需要主代理一并核对对应锁。
- 建议统一可信业务拒绝的序号字段或做显式兼容；未知序号保持未知，禁止借用上一条请求或自动重放操作。

### B. P1：attach／join 阶段一次性标记在发送前推进，发送失败无恢复

- `lobby_session.gd:371-377` 在 identity／server request 的 `request()` 返回前分别置 `_identity_sent/_server_sent`；`:386-389` 同样先置 `_hello_sent` 再发 join，均忽略返回值。
- `request()`（`:391-402`）会返回 `transport.send()` 的真实错误；`enet_transport.gd:123-145` 可因连接映射未就绪、远端状态无效、包预算等返回非 OK。因此“整体连接已连接”不等于该请求成功入队。
- 特别是 join 没有成功入队时：标记已经 true → 后续 poll 不再发 join → worker 无成员、无 `_peers` 登记 → 没有 identity 和 room 回复。**这是一条源码可确定的永久等待条件，但本轮没有运行证据证明实际命中了此条件。**
- `server_attached` 的字段生产/消费本身对齐；网关发通知失败会报错并清理 route（`server_gateway.gd:87-91`），不要先怀疑 peer_id int 类型。
- 建议仅在成功入队后标记发送；失败显式报错并允许用户重新连接。涉及业务请求时不能把重试默认解释为重放已可能执行的操作。

### C. P1/P2：权威快照发送失败缺少可恢复状态，bind 失败可永远阻断战局

- `lobby_session.gd:892-894,1428-1433,1511-1529` 对 room、selection、match_bind、match_view 的 `_send()` 返回值均未处理。
- 客户端 bind 没接受就忽略所有 view（`:617-630`）。如果 bind 入队失败，后续 view 即使成功到达仍被丢弃；没有 bind 请求／重发闭环，当前会话可能一直 `read_match()=={}`。
- 同理，最终 `selection.complete=true` 或 phase=playing 的 room 快照入队失败后，若没有后续状态变化，就没有周期快照或明确刷新消息修补 UI。网关只处理“worker 已收到消息后”的外部转发失败（`server_gateway.gd:321-322`），无法诊断 worker 根本未成功发送的消息。
- 单包默认 1 MiB（`enet_transport.gd:16,143-145`）；超预算属于永远失败，可靠 ENet 不会补救应用层拒绝入队。这里不能把 send=OK 当成客户端已接受。

### D. P2：mirror 拒绝静默，room playing 并不保证 match 被接受

- `view_mirror.gd:19-26` 要求白名单字段、基础类型、v=1、seq 严格递增、observer 等于 bind；后续 `:28-115` 还验证玩家控制关系、牌区、位置与隐私声明。
- `lobby_session.gd:625-630` 只有成功分支，没有转发 `_mirror.error` 到 session.error/rejected，也没有诊断 `not _match_bound`。因此“收到 match_view 后停大厅”不能只看网络收包：必须记录 accept 结果。
- 当前 `view_builder.gd:64` 的 root 字段与镜像 `ROOT` 白名单静态集合一致，本轮未发现 root 字段新增／漏项导致必拒。**未运行完整真实快照，不能推定所有深层牌区／控制关系均通过。**
- `match_bind` 在 `_match_bound=true` 后被忽略，这是既有只绑定一次的契约；正常 reconnect 会先 reset（`lobby_session.gd:188-201`），不能将它误报成普通重连必失败。
- 建议在不记录私有牌面／票据的前提下输出固定阶段、绑定 observer、收到 seq、已接受 seq、拒绝固定原因码；绑定身份不得从未知视图猜测。

### E. P2：状态改变但 room revision 不增，严格大于检查会保留过期 phase

- `restore_local_match()` 在进入恢复时 `room.revision += 1` 后发布（`lobby_session.gd:1377-1380`）；恢复失败时改回 phase=lobby 并 `_publish()`（`:1386-1392`），另一失败出口 `:1401-1409` 同样改 phase 而没有加 revision。
- 已接受恢复快照的客户端再收到相同 revision 的 lobby 快照，会被 `:650` 严格大于条件丢弃，继续显示 restoring；直到后续别的 room 操作增加 revision 才能修正。
- **范围说明**：这是共享 session 的本机恢复入口，当前普通 LAN/P2P UI 已不走旧 in-process 房主入口，不能把它直接当成本次独立服务端首入故障。仍是可定位的 revision 不变量缺口。
- `_prepare_reconnect()` 保留旧 room view 的 revision（`:188-202`），恢复文件读回 `room.revision`（`:1325`）；如果 worker 的持久化落后已发给客户端的 revision，新实例的低／相同 revision 也会被拒，直到超过旧值。正常断线／重连都增 revision（`room_state.gd:101-113`），因此**不能声称正常重连必然触发**；该风险依赖崩溃／保存失败／旧恢复状态。`_publish()` 也忽略 `_persist_recovery_state()` 的失败（`lobby_session.gd:890`），所以持久化落后不是被源码完全排除的状态。
- 建议确保每次公开 room 状态改变都推进 revision，并为恢复实例定义可信 epoch／版本连续性；不要直接放宽接受所有回退快照。

## 3. 排除项与相关屏障

1. `room_state.gd` 的普通 join、ready、settings、start、transfer、disconnect、reconnect 都推进 revision（`:33-35,65-69,80-91,101-113,138-141`）。选人选择可以不推进 room revision，因为另发 selection 且客户端不对 selection 做 revision 检查；这本身不造成选人结果被丢。
2. `data_revision` 与 `room.revision` 是不同域。客户端接受 room 不会直接更改 `session.data_revision`；后者只在清单接受链更新（`lobby_session.gd:579-613`）。不能把房间快照的 data_revision 出现误当作文件同步完成。
3. `begin_match` 必须 `data_ready()`（`lobby_session.gd:775`），大厅按钮也检查快照的 data_ready（`lobby_screen.gd:554`）。成员/选人已更新但不能进入对局，可能是批准数据未应用或成员未 ack，不是 room 消息未收。
4. `server_room_worker.gd:175-182` 明确声明随机模拟配置时，初始目录只作候选，不自动 set_room_files。此时初始无清单／data_revision=0 是批准屏障，不是消息字段 bug。
5. Worker 初始化 `host()` 早期 publish 还没有远端 `_peers`，后续 join 末尾会 `_publish()`（`lobby_session.gd:873`）；不能因为 worker 在设 dedicated/owner=0 前调用 host 就断言客户端先接受了错误初始化快照。

## 4. 已执行的静态验证与待主代理验收

- 实际读取三个重点文件，并追踪 `room_state.gd`、`enet_transport.gd`、`selection_authority.gd`、`match_authority.gd`、`view_builder.gd`、`view_mirror.gd`、大厅和提交锁消费者。
- Python 对真实源码执行 **10 项契约检查，10 项为 true**：成员发送/接受 Array、Variant wire、网关 request_seq、客户端 seq、bind 忽略发送返回值、严格 room revision、reconnect 保留 view、mirror 错误未上报，以及 builder root 字段与 mirror ROOT 集合相等。此结果证明源文本事实，**不是 Godot 解析、执行或网络测试通过**。
- Git 查询显示三个重点生产文件当前为 untracked；本代理未改这些文件，不把现有工作树内容算作自己的新增实现。
- 本代理仅新增 `scratch/net-batch-12/room-state.md`；未创建 `.gd` 探针，未启动 Godot。

主代理下一步最小验证（需另行获得运行授权）：

- 初次连接按阶段确认 server_attached 接受 → join send 返回值 → identity 接受 → room received/accepted 的 revision/member_count → selection received/complete → match_bind 接受 → match_view mirror.accept/reject。诊断不输出 token、认证 key、隐藏牌或任意载荷。
- 对网关“请求未转发到 worker”的可信序号拒绝，用真实待答 UI 验证请求锁可解除；未知序号不得解除不相关锁。
- 分别注入 bind／最终 selection／room 发送失败，确认显式错误和可恢复路径，不只检查 transport=connected。
- 注入格式有效但 observer 错误、seq 回退、深层白名单违例的视图，确认 mirror 不污染旧快照并且拒绝理由可诊断。
- 对“恢复失败回大厅”以及“崩溃恢复版本落后”单独验证版本/epoch策略；不与普通首入或正常 reconnect 混为同一结论。
