# 网关实例绑定审计与安全消费补丁（v6）

## 范围
只读审计 `scripts/net/server/server_gateway.gd`、`server_room_manager.gd`、`server_console_channel.gd` 及 `server_room_control.gd`。未改仓库生产文件；候选补丁仅写入本目录。

## 已确认的安全链

- `routes`、`_pending`、`_creators` 均携带 `room + pid + instance_id + authority_host_mode`；`_same_route()` 比较四元组并额外比较内部 `link` 对象身份。
- 公网路由转发、内部响应和断线回收都重新调用 `_route_is_current()`；旧 link 回调不会向新路由或新实例报告结果。
- `_disconnected_routes` 延迟到独立轮次清理，避免遍历 `routes` 时同步关闭/重建同一路由。
- `_detach_route()` 只关闭内部 link，不清除公网认证；`_detach()` 只有创建者连接的四元组仍匹配且通过 `process_identity_verified()` 时才提交停止。
- `ServerRoomManager.binding_matches(binding, true)` 的 ready 分支同时要求 ready、正 PID、四元组匹配和 `process_identity_verified()`；验证结果必须是严格 `bool true`。
- `process_ownership_available()` 当前固定返回 false。没有真实原生 spawn/verify/exit/terminate/release 句柄能力时，创建、恢复、poll、停止和管理操作应保守拒绝；不能用 `OS.is_process_running()`、ready 文件或可注入 Callable 冒充所有权。

## 发现的缺口

`server_console_channel.gd` 的 `_room_request()` 和 `_room_result()` 没有消费同一绑定契约：

1. `_room_request()` 读取 `ready.json`，只校验 `id/pid/instance`，随后写入 `{pid, instance, action}`；但 `server_room_control.gd` 的消费者要求恰好五个字段：`room、pid、instance、authority_host_mode、action`。因此合法管理请求会被房间进程判为无效，且入口绕过了真实句柄验证。
2. `_room_result()` 在没有回执时用 `OS.is_process_running(pid)` 判断是否继续 pending；这不是所有权证明，也会让 PID 复用/旧登记影响结果消费。
3. `_room_result()` 返回回执前没有校验 `room/pid/instance/authority_host_mode` 四元组，旧实例回执可能被当前房间查询入口消费。

## 最小补丁

`scratch/gateway-binding-v6/server_console_channel.gd.patch`：

- `_room_request()` 改为从 `manager.instance_binding(room_id)` 取得四元组，并以 `binding_matches(binding, true)` 作为唯一提交门槛。
- 请求文件写入完整五字段契约，供 `server_room_control.gd` 严格消费。
- `_room_result()` 删除裸 PID 存活判断；无回执只依据请求文件存在返回 pending，否则返回未确认失败。
- 回执消费前校验完整四元组，实例不匹配即拒绝。

## 有意保留的阻断

补丁不会打开 `process_ownership_available()`，不会实现伪造 OS 句柄，也不会放宽公网/内部连接。真实原生句柄生命周期仍是独立前置工作；在该能力接入前，管理请求、创建、恢复和路由 attach 继续失败关闭。

## 未在本批修改/验证的边界

- `server_room_manager.gd` 的生命周期所有者仍需在真实进程退出时把登记转换为不可运行状态并保留房间目录；本补丁不把 PID 存活当作替代。
- 未运行 Godot、未使用凭证、未提交 commit。仅做源码静态审计和内存变换断言。
