# 恢复认证审计（只读生产代码；禁止启动 Godot）

## 结论

当前源码不能支持“无恢复票据能启动未就绪房间”的结论：`server_join` 的未就绪分支必走 `_valid_room_resume`，缺票据立即返回 false。更可能的解释是：把成功建立网络连接/路由当成恢复成功、房间实际已 ready、没有启用密钥认证，或旧测试把合法的 PID 生命周期变化当成安全失败。下述为静态结论，不是本轮运行复现。

原成员恢复依靠 **有效恢复票据 +（受保护房间）当前获准且与原绑定相同的认证密钥**；昵称、用户名、新连接 peer_id 均不能替代这个条件。新连接在通过验证后映射到旧 member_id，原房主及 player_id → member_id 绑定继续沿用。

## 1. “无凭据”应拆成三个不同问题

| 场景 | 当前行为与证据 |
|---|---|
| 无密钥认证，但身份登记库 path 为空 | 网关没有启用密钥准入策略；`server_gateway.gd:105–110` 不阻止请求。`server_list` 即使启用认证也显式允许匿名查询。不是已经绕过恢复票据。 |
| 无恢复票据，房间未就绪 | `server_gateway.gd:190–198,263–278` 必须验证 `resume={member:int>0,token:64位小写hex}`，缺失/错误票据不会建立 pending，也不会调用 recover_room。认证启用时还校验绑定密钥与当前准入。 |
| 无恢复票据，房间已就绪 | `server_gateway.gd:199–200` 直接 `_attach`；这只是路由附着。其后 `join` 没有 resume 时执行普通加入（`lobby_session.gd:286–290`），允许与否取决于房间密码、phase、容量、观战上限（`room_state.gd:22–35`）。在 lobby 有空位时可成为新成员；selecting/playing/restoring 禁止新增普通玩家，但允许有空位的观战者。没有自动取得旧成员。 |
| 有原密钥但没有恢复票据 | 无按密钥反查并自动认领旧 member_id 的实现；普通 join 仍走新成员分支。 |
| 有原票据但另一获准密钥 | 受保护房间两道检查均拒绝：网关磁盘预检 `:274–276`；worker `_join_identity :278–279` 在票据哈希比对、reconnect 和轮换之前拒绝。 |

因此若需求是“崩溃恢复中的整个房间连新观战者也不得附着”，当前 ready 分支没有这种策略。这属于需要明确的新准入规则，不能把常规加入与盗用旧身份混为一谈。

### 观察口径陷阱

- `join_server()`/`reconnect()` 返回 OK 仅代表开始连接；`server_attached` 仅代表内部路由连上（网关 `:86–88`，客户端 `:563–568`），不证明房间成员身份已获准。要看 worker 返回 `identity` 以及 `_member_by_peer`、原成员 connected、owner、controllers。
- 网关 `_fail :407–410` 发送错误回执，不主动断 TCP/ENet；“连接仍然存在”不等于“请求没被拒”。
- 认证开关不是昵称或 UI 上是否显示账号，而是 `identity_registry.path` 非空；网关在创建配置写入 `_gateway_identity_required`（`:161–164`），worker 读取并于加载 recovery 前赋给 `_identity_binding_required`（`server_room_worker.gd:61–65,155–164`）。

## 2. 已发现一个能制造“无凭据未拒绝”假象的旧断言

`tests/net_server_archive_match_test.gd:47–65`：

1. 先保存 `old_pid`，杀进程，循环 poll 到 `_worker_ready` 为 false。
2. 无票据客户端请求后断言 `intruder.error 非空 AND _worker_pid == old_pid`。
3. 但是生产 `server_room_manager.poll :217–224` 在确认退出并释放可信进程句柄后，会合法把 `room.pid` 改成 **-1**。
4. `_worker_ready` 本身与入口判定没有两个不同口径：`is_ready :299–300` 也是 `binding_matches(instance_binding(id),true)`；`binding_matches :83–98` 要求 ready、正 PID、可信 OS 进程验证。

故即便请求被正确拒绝且没新建进程，该复合断言仍可因 pid=-1 报红。静态确认断言与当前生命周期契约不相容；没有本轮 Godot 输出，不能称已动态复现。

建议改为先单独断言拒绝原因，再比较请求前/后的 instance_id、没有新增 process_token/正 PID、没有 pending/routes 以及没有调用 recover_room；允许 old_pid → -1 的退出登记。有效原票据再恢复时，才检查新实例与可信新 PID。

另一个旧夹具风险：`tests/net_member_identity_binding_test.gd:10–14,58,70,123` 的 TestRooms 只有 poll/is_ready/close，房间字典缺实例/进程字段，pending 还写成字符串；而当前网关依赖 `instance_binding/binding_matches/process_identity_verified` 且 pending 是 Dictionary。该夹具现状不适配生产契约，不应拿它的历史绿灯证明当前真实网关安全；应补完整兼容的调度替身并明确“不是杀进程恢复验收”。

## 3. 原凭据回绑原 member_id 的完整链

1. 客户端首次 join 后收私有 `identity={member,token}` 存 `_resume_ticket`，ACK 当前新 token（`lobby_session.gd:555–561`）。
2. 重连 `_prepare_reconnect :188–202` 清当前认证会话、保留票据，写 `_hello.resume`，序号从新连接重置。dedicated 再把票据放入 `server_join.args.resume`（`:204–216`）。密钥认证重新完成，不继承旧连接的认证结果。
3. 未就绪时网关查该 room 的 `recovery.json`，验证格式、绑定策略、成员密钥和当前/previous 哈希（`server_gateway.gd:263–278`）。通过后才可能调用 recover_room，并记录当前实例 pending；附着前再次验证当前准入（`:280–288`）。
4. 客户端正式 join 经 `_public_room_request :204–244` 白名单过滤，客户端自报 `gateway_identity` 被丢弃；网关 `_room_join_message :505–517` 根据真实认证连接重建 `{required,key}`，认证开启时也用登记昵称覆盖名字。
5. worker dedicated join 检查可信上下文与不可降级策略（`lobby_session.gd:254–270`），先比对 `_member_identities[ticket.member]`，再验证当前或 previous token hash。`room.reconnect(member)` 只恢复已存在且离线的成员（`room_state.gd:108–114`），不按昵称新建身份。
6. `_accept_identity(connection,member,new_token,proof) :244–252` 设置 `_member_by_peer[new_connection]=old_member`、`_peer_by_member[old_member]=new_connection`；业务收包用此映射计算 sender（`:505`），发送也反向映射（`:227–228`）。客户端 `peer_id :160–163` 优先返回 ticket.member；网关 server_attached.peer_id 只是新的内部连接地址。
7. recovery 加载把 JSON 字符串成员键转换成内存 int，保留 owner，全部成员标 offline，playing 转 restoring，并加载 `_recovery_bindings`（`:1317–1351`）。worker 自动恢复在所有正 member_id 的席位成员 connected 后才尝试存档恢复（`server_room_worker.gd:225–235`）；`restore_local_match :1385–1386` 使用保存的绑定，不按新连接重新分配 player_id。
8. 新 token 轮换暂存 proof 到 previous，ACK 仅在当前 hash 匹配时清除 previous；清除落盘失败则回滚（`:736–742`）。旧 token 不是无条件永久有效。

## 4. recovery.json 的认证边界与现存样本

- `member_identity_bindings.valid_state :6–31`：required=true 必须 protected=true；保护档每个 saved member 都必须有有效指纹绑定，哈希成员必须属于绑定。无保护档必须无身份映射。legacy 无绑定档可在认证关闭时兼容，但不能在认证要求下认领。
- `load_recovery_state :1314–1317` 先验证后设 recovery_state_path；worker 若已有文件加载失败直接失败，不把旧目录作为空房间覆盖（`:160–164`）。
- 恢复文件保存成员、owner、bindings、票据哈希、previous、密钥指纹、继承审计，不保存 token 原文和私钥（`lobby_session.gd:1355–1371`）。
- 本轮用 Python 只输出元数据读取了现存 `tests/runtime_reports/server_match/5042475/workers/*/recovery.json` 两份：`253b3a0d887192e4dbe212d953844f87` 是 lobby、1 member、0 bindings；`c2f87eed81d7313a6e61ec1bade4e90b` 是 selecting、2 members、0 bindings。两份均 `identity_binding_required=false`、0 个身份映射。它们不能作为“已启用认证/已保存完整对局席位”的样本，也不能支持两名真人崩溃前 playing 已落盘的结论。未在报告记录任何票据、私钥或哈希值。

### 次要完整性缺口（静态；未修）

`_accept_identity :251–252` 先发送新身份再保存，而且没有消费发送/保存结果；随后主业务可继续成功。这不等于无票据恢复漏洞，但保存失败后可能出现“客户端拿到票据，磁盘没更新”的耐久性缺口。ACK 的 previous 撤销有回滚，不代表首次接纳与轮换整体事务也已经可靠。需在故障注入中分别验新身份发送失败、恢复文件写失败、ACK 写失败，不能只验证内存映射。

worker dedicated 的 `gateway_identity` 信任依据是只监听 `127.0.0.1`（`server_room_worker.gd:155`），不是每条消息的密码学内部认证。公网经网关不能自报该字段；同机可直接连接 loopback 的进程仍属于受信边界，不应把“仅回环监听”宣传为抵御恶意本机进程。

## 5. 主代理下一步验收（本代理未执行）

- 分开断言匿名连接、server_list、路由附着、join 获准、旧成员恢复，记录明确阶段。
- 真实退出后无票据/伪造票据不能触发新实例；允许 PID 合法退休，不用 PID 必须保持原值判断。
- 原票据+原获准密钥恢复到同 member_id/owner/player_id；同昵称另一密钥+盗票拒绝且状态不变；原密钥被禁用后同样拒绝。
- 验证 ready 房间中新成员与观战行为是明确策略，而不是恢复身份继承。
- 保护旧档缺绑定失败关闭且字节保留；显式管理员迁移与房主指定继承另验，不能让首持票者自动认领。
- 修旧 TestRooms 后再运行相关夹具；需要真实可信进程所有权路径的崩溃验收，不以替身冒充。

## 交付范围

仅新增本报告；未改生产脚本、测试源或恢复数据；未启动 Godot，未运行网络、杀进程、恢复或迁移操作。已完成源码逐入口静态核对和现存恢复样本的过滤元数据读取。运行行为、跨网与真实崩溃恢复仍待主代理串行验收。
