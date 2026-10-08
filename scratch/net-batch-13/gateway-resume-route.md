# 网关恢复路由审计

## 结论与可信边界

- **当前生产实现没有发现普通恢复路径把旧 worker/link 当成新路由使用的漏洞。** `_pending` 固定完整实例绑定，`_attach()` 捕获独立 route/link，回调先比较 link 对象身份，再比较 room、PID、instance_id、authority_host_mode 和可信进程状态。旧回复、旧断线及旧排队清理不能作用于已登记的新 link。
- **客户端仍可能看到房间断开错误，但不能据此认定旧回调污染新实例。** 当前 route 真断线会报“房间连接已断开”；manager 登记退出/更换后，轮询会向仍挂着旧 route 的公网连接报“所选房间已经停止或实例校验失败”。这两条是当前绑定失效通知。
- 找到两个相邻风险：**内部路由断开后公网仍连接，正常重连入口不可用（高优先级疑似缺陷）；恢复时保留旧 view/data revision，会拒绝合法的新恢复快照（条件性风险）。** 后者是客户端恢复基线问题，不是网关转发了旧 worker 的 revision。
- 本次仅静态源码审计，按要求**没有运行 Godot、没有启动/恢复/停止 worker、没有修改生产代码或测试**。以下风险均未做运行复现，不能作为实际 ENet/多机验收结果。

## 拓扑与审计范围

本轮专审独立服务端：客户端 → 公网 ENet gateway → 每客户端独立回环 ENet link → 本机房间 worker（权威规则）。恢复由本机 manager 更换 worker 实例。P2P 信令辅助节点不在此数据链，本报告不证明跨网、打洞或真人掉线行为。

读取了：
- `scripts/net/server/server_gateway.gd`
- `scripts/net/server/server_room_manager.gd`
- `scripts/net/transport/enet_transport.gd`
- `scripts/net/session/lobby_session.gd`
- `scripts/net/ui/lobby_screen.gd` 的重连入口
- `tests/gateway_instance_binding_test.gd`

## 已核实正确的，不要误改

### 1. pending 不会自动漂移到同名新实例

`server_gateway.gd` 下文均以完整路径引用：

- `scripts/net/server/server_gateway.gd:168`：创建后保存 manager 返回的实例绑定。
- `scripts/net/server/server_gateway.gd:195`：恢复请求携带旧 expected PID/instance_id；恢复成功后在 `scripts/net/server/server_gateway.gd:198` 重新读取**新** instance_binding 放入 `_pending`。
- `scripts/net/server/server_gateway.gd:63`：pending 绑定失配或 room.error 非空时失败并删除，不通过 room ID 单独认领新 worker。
- `scripts/net/server/server_gateway.gd:67`、`scripts/net/server/server_gateway.gd:71`：ready 还要求可信 OS 进程验证，才进入 attach。
- `scripts/net/server/server_room_manager.gd:81`、`scripts/net/server/server_room_manager.gd:87`：binding 包含四项完整身份并逐项匹配；require_ready 还要求 ready、正 PID 与 process_identity_verified。
- `scripts/net/server/server_room_manager.gd:341`、`scripts/net/server/server_room_manager.gd:374`：恢复生成新随机 instance_id 并更新房间登记；即使 PID 重用也不能混淆旧 binding。

时序：pending=A → manager 恢复成 B → pending 的 A 校验失败，不会悄悄 attach 到 B。原恢复发起者则在 recover 成功后存 B，正常等待 B ready。

### 2. attach 与旧回调隔离

- `scripts/net/server/server_gateway.gd:286`：连接前校验完整 binding。
- `scripts/net/server/server_gateway.gd:290`、`scripts/net/server/server_gateway.gd:292`：route 从 binding 深复制，回调闭包捕获该 route，而不是回调执行时临时拿 routes[peer] 代替旧 route。
- `scripts/net/server/server_gateway.gd:302`：connect_to 后再次校验，再登记 routes[peer]。
- `scripts/net/server/server_gateway.gd:311`：`_same_route()` 要求 link **对象同一性**，不只比较房间/PID。因此同实例重建新 link 也能挡住旧 link 回调。
- `scripts/net/server/server_gateway.gd:314`、`scripts/net/server/server_gateway.gd:317`、`scripts/net/server/server_gateway.gd:325`、`scripts/net/server/server_gateway.gd:397`：回复、断线、拒包均走 `_route_is_current()`，旧 route 不会给新路由转发 room/revision 或断线错误。
- `scripts/net/server/server_gateway.gd:85`：link.poll 可能同步触发清理，后续 attach_notice 前再检查 current，避免继续操作失效 route。

### 3. 延迟清理不关闭新 link、不杀恢复后的 worker

- `scripts/net/server/server_gateway.gd:95`：内部断线回收在 link 遍历后处理。
- `scripts/net/server/server_gateway.gd:333`：队列保留旧 route 的 link/绑定。
- `scripts/net/server/server_gateway.gd:343`：执行旧回收前再次 `_same_route()`；若 routes[peer] 已换新 link，直接返回。
- `scripts/net/server/server_gateway.gd:344`：先 erase 再 close，close 的同步回调无法再认领当前 route。
- `scripts/net/server/server_gateway.gd:341`：内部 `_detach_route()` 不清公网认证，不调用 stop_room。
- `scripts/net/server/server_gateway.gd:362`：公网 `_detach()` 对未完成创建者的停止操作也要求原 binding 仍匹配及可信进程身份；旧创建者不能停掉恢复后的 worker。

普通 server_join 在 `scripts/net/server/server_gateway.gd:151` 拒绝已有 route/pending 的同一公网 peer，不存在通过普通加入请求直接覆盖 routes[peer] 的入口。`_attach()` 本身没有重复路由守卫，直接内部调用可覆盖旧 link，但当前已审公网调用链有上述前置条件，不把这个防御性缺口报成已可达漏洞。

## 静态风险（未复现）

### R1：只断内部 link，不断公网，用户正常重连入口被锁住

**优先级：高；静态链路成立，尚缺实际 worker 崩溃/恢复交互证据。**

证据：
1. `scripts/net/server/server_gateway.gd:326` 真内部断线只发送 error 并排队 `_detach_route()`；失效 binding 的 `scripts/net/server/server_gateway.gd:80` 同样只发 error 并清内部 route。
2. `scripts/net/server/server_gateway.gd:346` 关闭的是 route.link，没有关闭公网 transport，也没有通知客户端一种可识别的“路由已失效”状态。
3. `scripts/net/session/lobby_session.gd:657` 收 error 只更新错误；仅 `_resume_inflight` 为 true 时在 `scripts/net/session/lobby_session.gd:660` 关闭公网 transport。已稳定加入客户端通常已在收到 identity 时清除 `_resume_inflight`（`scripts/net/session/lobby_session.gd:558`）。
4. `scripts/net/session/lobby_session.gd:169`：公网仍 connected 时 `can_reconnect()` 为 false；`scripts/net/session/lobby_session.gd:205` 的 reconnect() 也被这个条件拒绝。
5. `scripts/net/ui/lobby_screen.gd:203`：只有公网 disconnected 才显示正常重连按钮。内部路由失效时不显示。
6. 即使外部手工在同一公网连接重新 server_join，客户端 `_server_peer_id` 未重置，新 server_attached 也会被 `scripts/net/session/lobby_session.gd:563` 的 `_server_peer_id == 0` 条件拒绝；正常 reconnect() 才在 `scripts/net/session/lobby_session.gd:213` 清它。

可观测后果：用户收到真实房间断开错误，gateway 已清 route，公网仍“连接着”，UI 没有可用的正常重连入口；后续操作返回“尚未加入服务器房间”。这不是旧回调关掉新 worker，而是公网连接状态与房间路由状态没有分离。

建议：优先让当前公网会话进入已有的可重连流程，或增加固定的路由失效控制消息，让客户端在安全的下一轮统一清连接并走现有 reconnect()。不要在当前 ENet poll 回调里直接关闭并重建同一 transport，也不要从错误文案猜是否该重连；管理员断开、封禁与房间可恢复失效应有不同语义。

### R2：客户端保留旧 revision 基线，恢复快照可能被当成过期

**优先级：中；条件性风险，不能断言正常落盘恢复一定触发。**

证据：
- `scripts/net/session/lobby_session.gd:188` 到 `_prepare_reconnect()` 结束只清 transport/传输片段/镜像绑定等，不清 room `view` 或 `data_revision`。
- `scripts/net/session/lobby_session.gd:1326`、`scripts/net/session/lobby_session.gd:1329`：worker 从落盘文件恢复 data_revision 与 room.revision，没有新的客户端 epoch。
- `scripts/net/session/lobby_session.gd:650`：只接受 `state.revision > view.revision` 的 room。
- `scripts/net/session/lobby_session.gd:601`：只接受 `message.revision > data_revision` 的完整 room_files。
- `scripts/net/server/server_gateway.gd:87`：server_attached 只有 room/peer_id，没有实例 epoch，客户端不能按新 worker 实例切换 revision 比较域。

触发条件：客户端曾看见高于最终可用 recovery.json 的状态（例如保存落盘失败或恢复使用较旧快照）；新 worker 的后续 join/reconnect 增量仍没有超过客户端旧 view revision。此时合法的新 room 快照被忽略，客户端继续显示崩溃前旧 view。若恢复的数据目录/版本也回到更低基线，room_files 门禁同样需要单独验证。

对照：保存最新、恢复后 revision 因成员重连正常增加并超过旧 view 时，不触发该风险；相同 data_revision 且原缓存仍正确安装也不应无条件清缓存。因此不能简单“接受所有小 revision”或“重连一律清全部数据”。

建议：把新 route/worker 身份与客户端恢复比较基线显式关联，复用现有重连准备入口，在可信新实例/首次恢复快照到达后有序切换 view 基线；数据版本继续校验清单与已安装内容。禁止为修复直接取消同一实例内的 revision 单调性。

## 测试覆盖问题

`tests/gateway_instance_binding_test.gd:49` 到 `tests/gateway_instance_binding_test.gd:62` 已包含旧 link 回复/断线/排队清理不得影响新 link、内部清理保留公网认证的反例。这些是**源码中的断言，不是本轮运行通过的证据**。

另外该测试在 `tests/gateway_instance_binding_test.gd:24`、`tests/gateway_instance_binding_test.gd:27` 向 manager 设置 `process_identity_verifier`，但当前 `server_room_manager.gd` 已无此属性，验证改为私有 `_process_owner` 的原生调用（`scripts/net/server/server_room_manager.gd:91`）。测试夹具存在静态接口漂移，不能拿旧 RESULT 日志替代当前验收；主代理需先适配现有可信进程所有权接口再运行。

待补真实 Godot 验收（本代理禁止运行，交主代理串行执行）：
- 当前已加入且 `_resume_inflight=false` 的客户端，worker 崩溃后公网仍存活：确认重连按钮和 reconnect() 行为。
- worker A → B，旧 A 回调后到：精确记录客户端未收到旧断线/旧 room revision，新 B link 没被关闭；保留同 PID、不同 instance_id 反例。
- pending=A 遇 manager=B：确认失败清 pending，不接 B；恢复发起者 pending=B 则正常 attach。
- 同一实例换 link：旧 queue 不关闭新 link；模拟 link.poll 同步清理，验证不发旧 attach_notice。
- 恢复使用最新快照与较旧快照两组：分别记录客户端 view revision、worker 恢复 revision、数据 revision 与实际 room_files 接受结果，区分旧实例消息和旧 UI 缓存。

## 交付与检查

只创建本报告：`scratch/net-batch-13/gateway-resume-route.md`。未修改生产文件、测试、配置、恢复文件或目录结构。选定生产文件的 git diff --check 无输出；它们当前为未跟踪文件，因此该命令不构成这些源码的语法验证。未运行 Godot、gdtoolkit 或多机验收，无运行通过声明。
