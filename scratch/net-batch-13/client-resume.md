# 客户端恢复消息与修订号审计

## 结论与边界

- **静态确认：`view.data_ready` 可以在恢复后由 true 变 false，具体源头是权威重新标记成员在线但 ACK 尚未恢复，以及存档恢复再次提交文件清单清空所有 ACK。不是客户端 `match_view` 把它写成 false。**
- **未发现同一客户端正常 reconnect 流程接受更低 room revision 或 files revision 的入口。** `room` 和完整/分片 `room_files` 都有严格递增门槛；accepted_revisions 是恢复测试的局部数组，不是客户端协议字段。
- **match seq 可以跨恢复重置后降低**：`_prepare_reconnect()` 清空 mirror，`match_bind` 再次 reset；之后只对新 mirror 的 seq 做严格递增校验，没有跨实例高水位。它与 room/data revision 必须分开解释。
- 本报告只读源码追踪，未运行 Godot、未建立网络连接、未修改生产/测试源码；不能把下面的可达时序称为现场复现。

## 1. 正式恢复入口到 join

位置均相对仓库根目录。

1. `scripts/net/session/lobby_session.gd:188-215`：`reconnect()` 调 `_prepare_reconnect()`，关闭旧 transport，清除 manifest 分片、blob 接收和发送队列，`_seq=0`、`_match_bound=false`、`_mirror.reset(-1)`；**保留 view、room_files、data_revision、_assets、旧 pending/actions**。专服随后重建 `server_join` 请求（带 resume），清零 `_server_peer_id`。
2. `lobby_session.gd:371-389`：完成认证（如启用）后发 server_list/server_join；只有收到 server_attached 后才发携带 resume 的正式 `join`。
3. `scripts/net/server/server_gateway.gd:173-200`：server_join 选路由，未就绪实例要求原成员凭据，必要时 recover_room，实际 attach 当前绑定实例。`server_attached` 在内部 link 已连接后发送（86-88）；它本身不恢复 room/match/files。
4. `lobby_session.gd:563-568` 接受 server_attached 仅写 server_room_id/_server_peer_id，不检查请求 room 是否相同、不携带 PID/instance_id/revision，也不清除旧 room/files 高水位。网关路由本身用绑定实例校验旧响应（`server_gateway.gd:308-321`），但客户端消息没有独立实例世代。
5. 权威 `lobby_session.gd:273-285,828-844`：凭据校验 → room.reconnect → identity → files；playing 时 bind + publish_match，selecting 时 selection；成功后统一 `_publish()`（877）。`room_state.gd:108-114` 将成员 connected=true 并使 room.revision 增一。

## 2. room/match/files 接收与写入表

| 消息/事件 | 客户端处理 | 是否能降低/清空 |
|---|---|---|
| identity | `lobby_session.gd:555-562` 轮换票据、identity_ack；仅当收到的 data_revision 与保留的本地 revision 相等且 assets 已安装时自动 data_ack | 不写 room/data revision；旧 assets 未安装或服务端已升版则不会自动 ACK |
| room | `646-656`：revision 为 int、members 为 Array，且严格大于 view.revision 才整体替换 view | 不能降低 room revision；**可以把 view.data_ready 替换为 false**，未对该字段做单独单调约束 |
| room_files | `600-613`：revision 严格大于本地 data_revision，不能低于 pending_revision；预算/清单验证通过才提交 | 相等/更低清单直接忽略，不清空已安装 assets |
| room_files_part | `579-586`，`room_manifest_transfer.gd:50-83`：排除 <= current revision 或 < pending revision，按 offset 累计验证 | 更低/重复不提交；完整后才更新 |
| files 提交 | `_accept_room_files()`，`1055-1060`：写 room_files/data_revision，清 _assets，changed | 仅收到更高版本时清安装映射；该函数本身无 guard，当前两处网络调用方均有 guard |
| match_bind | `617-620`：observer 为 int 且尚未 bound 时 mirror.reset(observer)，bound=true | 清掉镜像旧 seq；重复 bind 在已 bound 时不再 reset |
| match_view | `625-630`：已 bound，pending/actions 均为 Dictionary，mirror.accept(state) 成功才更新 | 不写 view.data_ready、data_revision；失败不更新 pending/actions，当前分支也不向 rejected 转发 mirror.error |
| match_reset | `621-624,1439-1444`：清镜像、bound、pending/actions、selection | 允许下一次重新 bind，旧 match seq 门槛消失 |

`MatchViewMirror.accept()`（`scripts/match/view_mirror.gd:19-26,115`）只允许 seq > 当前镜像 seq（空镜像基线 0），并校验 observer/完整视图格式。**已绑定且未 reset 的镜像不会接受回退 seq。** 恢复后新 authority 的较低 seq 可以通过；reset 的作用是合法跨恢复接续，不应当用旧局 seq 直接判协议回退。

传输上不能把源代码发送顺序理解为统一收包屏障：权威 room/identity 默认 channel 0，match channel 1，files channel 2；网关 `_room_response()` 根据 `_channel()` 重选外发通道，match 实际落到 channel 0，files 仍 channel 2（`server_gateway.gd:316-322,430-431`）。内部 match 与 room 仍可能跨 channel 到达不同顺序，客户端没有按文件 revision 拦住 match_view。

## 3. data_ready 变 false 的两条具体路径

### A. 同一 worker 的断线/恢复（数据版本不变）

```
_host._disconnected(member)
  → _data_confirmed.erase(member)                 lobby_session:479-487
  → room.mark_disconnected(member)               :490-494
  → data_ready 暂时忽略离线成员                  :1037-1039
客户端 reconnect → join.resume
  → room.reconnect(member): connected=true       room_state:108-114
  → _accept_identity() → identity                lobby_session:244-252
  → files + playing 时 bind/match                :838-842
  → _publish(): data_ready() 为 false             :879-898
客户端 identity 分支满足同版且 assets 安装条件
  → data_ack(revision)                           :560
权威 data_ack → _data_confirmed[member]=revision
  → room.revision += 1 → _publish()              :759-763,877
  → 全部在线成员同版 ACK 后 data_ready 才恢复 true
```

因此 true → false → true 是可达的确认窗口；重连握手/identity 到达不等于权威已收到 data_ack。identity 自动 ACK 的发送返回值未被使用；安装映射若不存在则根本不自动 ACK，需要同步调用方重新安装/确认。playing 分支重连立即发 match，并没有先等 ACK；主 poll 的 playing 推进条件（378）也没有 data_ready 条件，故 match 已收到与 room.data_ready=false 可以同时出现。

### B. worker 崩溃后恢复存档：同一恢复过程会再升数据版本

1. `load_recovery_state()`（`lobby_session.gd:1288-1329`）读回 data_revision 与 room.revision，不把它们归零；所有成员先置离线，playing 转 restoring（1330-1339）。旧档缺 data_revision 时回退使用 saved room.revision，这是兼容读取，不是客户端接受低版。
2. `server_room_worker.gd:175-182` 无 random_sim_enabled 声明时启动 set_room_files，`_commit_room_files()` 增 data revision、清确认、增 room revision。带预检声明时这一步跳过，不能假设每种恢复都必有此第一次升版。
3. 原成员重新在线之后 `_try_restore_match()` 才恢复 archive（worker:225-235,260）。它要求原真人重连，但没有在这里等待其数据 ACK。
4. `restore_local_match()` 开始发布 restoring（lobby_session:1382-1386）；成功后 `_clear_match_views()`，设 require_room_data=true、`_rules_revision=data_revision+1`，再 `_commit_room_files()`（1421-1424）。
5. `_commit_room_files()`（1016-1030）**即使内容相同也增 data_revision、清全部 _data_confirmed，只确认 member 1、置所有 ready=false、增 room revision、发送 files、发布 room**。在线远端因此重新缺 ACK，data_ready=false。已 ACK 上一版的客户端必须再同步/安装/ACK 新版，旧 accepted revision 只是过期，不是被网络消息降低。
6. 全部当前在线成员 ACK 当前 revision 且规则版一致后，host poll 才 restoring→playing、bind、publish room/match（380-385）。

`data_ready()`（1032-1040）只有两个 false 判据：require_room_data 时 revision 为 0 或 rules_revision 不匹配；任一在线成员 ACK 不等当前版。客户端 UI 读的是权威快照 `view.data_ready`（`lobby_screen.gd:554`），不要把客户端本地 `data_ready()`（其 room 并未由 room 消息重建）当成同一指标。

## 4. accepted revision 的具体来源：当前代码不支持“正常接收后回退”结论

- `tests/net_server_archive_match_test.gd:74` 每次 `_recover_match()` 新建 `accepted_revisions=[-1,-1]`。若比较不同恢复轮次或上一次同步记录，新一轮 -1 是**局部计账重置**，不是 room/files 回包回退。
- 同函数唯一逐端赋值在 95-97：sync.complete 且 install_room_assets 成功后，发 data_ack，然后 `accepted_revisions[index]=session.data_revision`。忽略 request 返回值，所以 accepted 表示“本地安装并尝试发 ACK”，**不表示权威已确认**。
- 83-90 发现 session.data_revision 改变会 cancel 旧 synchronizer、改 syncing_revisions；accepted 保留上一版，直到新同步完成。因此 data_revision 升版时可以出现 accepted < current，不能称 accepted 自己降低。
- `_prepare_reconnect()` 保留旧 room/files，83 行没有等待本轮 identity/新 files：可能先同步旧清单；新文件版到来后切换。这是“旧版先接受、随后新版待接受”的具体路径，不是倒序接受更低文件版。
- 同一正常 reconnect 中 session.data_revision 网络赋值只能增加。能归零的是 `close()`（448）；join/join_peer/join_server 的初次连接入口调用 close（146-157,352-357），**不是 reconnect**。若误用 join_server 替代 reconnect，view/data/ticket 会整体重置，不再是原会话恢复。
- 能直接覆盖为任意合法恢复版的是 authority 的 load_recovery_state（1326），它不由客户端 room/files 收包调用。
- `_recovery_matches()`（测试:121-130）只比较 round/phase/current_player/game_over/observer，99 行可提前 break；不要求 accepted==current、所有 sync 已完成、room.phase=playing 或 data_ready=true。这会让恢复测试漏掉末尾数据屏障，但不构成 accepted 回退证据。

## 5. 建议父任务的定位/验收点（未实施）

- 分别记录 room accepted revision、files accepted revision、match accepted seq 与 reset 原因，不用统称 accepted revision。每条记录加本轮 reconnect 世代；不输出恢复票据、认证密钥和私有牌内容。
- 权威每次 publish 记录 room/data/rules revision、phase、在线成员数量、缺 ACK 成员编号；客户端记录本地安装状态、identity data_revision、data_ack send 返回值。这样能区分 A 的短暂 ACK 窗口与 B 的再次提交清单。
- 恢复测试等待当前版所有客户端完成安装、权威 room.data_ready=true/playing、connection_wait 解除，再验完整局面；不能用 accepted_revisions 的本地赋值替代权威 ACK。
- 若现场确有同一世代 room/data accepted 数字下降，应先核对是否 close/新建 session、重复进入 `_recover_match()` 或其实记录的是 match seq；当前网络入口不提供这种下降路径。若新实例给出不高于保留高水位的 room/files，现代码会忽略而卡住，并不会接受回退，需要实例世代/恢复协议解决。

## 检查记录

已用 Python 对 lobby_session.gd、view_mirror.gd、net_server_archive_match_test.gd 枚举 data_revision/view/mirror reset/accepted_revisions 的写入点，命令退出码 0；与上述行号和接收调用链相符。仅新建本报告，Godot 及所有运行测试均按限制未执行。
