# console save 测试失败审计

## 结论

- `SERVER_JOIN_FAILURE` 不是 `console save` 断言产生的生产信号；它只在共享基类 `tests/net_server_match_test.gd:27-29` 打印，内容来自 `agents[0].session.error`。
- 失败发生在保存测试自己的 `_after_baseline()` 之前。继承链为：
  `net_server_console_save_test.gd` → `net_server_recovery_midmatch_test.gd` → `net_server_recovery_match_test.gd` → `net_server_archive_match_test.gd` → `net_server_match_test.gd`。
  因此本次 `SERVER_JOIN_FAILURE` 尚未执行 `server_console_channel.configure()`、`room <id> save`、回执读取或日志哈希断言；不能把它归因于保存夹具字段、保存路径或 `match.log` 校验。
- 现有证据更像**共享服务端建房/工作进程启动路径失败**，不是“旧 save 夹具”导致；但当前错误被 `ServerGateway` 折叠成通用文案，且本轮禁止运行 Godot，所以不能仅凭该输出定性为已确认的生产回归。应标为：**保存测试未进入，生产路径候选回归/运行环境失败，根因未定位**。

## `SERVER_JOIN_FAILURE` 来源链

1. `tests/net_server_match_test.gd:23` 创建首位客户端并调用：
   `join_server(address, port, "甲", "", "服务端完整对局", settings)`。
2. `scripts/net/session/lobby_session.gd:352-357` 先调用 `join()`，再设置 `_server_request` 为 `server_create`，携带 `name` 与 `settings`。
3. `lobby_session.gd:371-377` 在连接建立后发送 `server_list` 和 `server_create`。
4. `scripts/net/server/server_gateway.gd:154-172` 校验建房参数，并调用 `manager.create_room(args.name, settings, data_root)`。返回空 ID 时，网关发送：
   `服务端房间操作失败，请联系管理员检查房间状态`。
5. 若建房返回 ID，则还要经过 manager/worker ready、内部路由 attach，客户端收到 `server_attached` 后才能继续普通 `join`；任一阶段失败也会让 `view` 保持为空或设置 `session.error`。
6. 测试在 `tests/net_server_match_test.gd:25-32` 等待最多 20 秒；`view` 仍为空时打印 `SERVER_JOIN_FAILURE <session.error>`，随后只断言 `room worker starts`。

所以这条标识的直接来源是测试打印语句，间接来源是会话收到的网关/房间错误；它不是 worker 日志中的稳定事件名，也不能单独区分 `create_room` 空 ID、ready 超时、路由 attach 失败或客户端 error。

## 保存测试是否使用旧夹具

`tests/net_server_console_save_test.gd` 的保存专用代码从第 3 行开始，只有基线完成后才运行：

- 创建 `server_console_channel` 和 `p2p_signal_server`；
- 使用 `E:/Projects/Godot/FateDomination/test/save-console-<ticks>` 作为控制台存储根；
- 执行 `room <room_id> save`，等待 response JSON；
- 读取 `matches/<dir>/match.log`，核对 `saved`、记录数、状态哈希和种子；
- 验证路径穿越查询被拒绝。

这些字段均位于共享首位客户端加入和完整对局之后。当前失败点早于它们，故不能说 save 专用夹具触发了失败，也没有证据证明旧存档目录污染了本次首位建房。

需要注意：该测试的 `root` 是硬编码绝对路径，而父类 `_start_gateway()` 使用本轮独立的 `res://tests/runtime_reports/server_match/<ticks>/workers`；这是**后续控制台通道的独立存储根**，可能造成后续路径/清理问题，但不会解释当前最早的 `SERVER_JOIN_FAILURE`。

## 最小复现字段

### 共享基类最小输入（复现当前失败点）

```gdscript
var directory := "res://tests/runtime_reports/server_match/%s" % str(Time.get_ticks_usec())
var gateway = preload("res://scripts/net/server/server_gateway.gd").new()
gateway.manager.storage_root = directory.path_join("workers")
gateway.manager.internal_port_base = 60000 + int(OS.get_process_id() % 1000)
var port := preload("res://tests/net_port_fixture.gd").available_range(42000, 44000, 1)
gateway.listen(port, "127.0.0.1", LoadHelper.get_data_dir())

var settings := {
    "capacity": 2,
    "minimum": 2,
    "selection_mode": "unique_master_class_pool",
    "ai_count": 0,
    "spectator_limit": 2,
    "runtime_guard": {"enabled": true, "steps": 9223372036854775807, "seconds": 0.0}
}
var client = preload("res://scripts/net/session/lobby_session.gd").new()
client.join_server("127.0.0.1", port, "甲", "", "服务端完整对局", settings)
```

最小必要字段分组：

| 位置 | 字段 |
|---|---|
| gateway | `storage_root`, `internal_port_base`, `listen(port, "127.0.0.1", data_root)` |
| server_create | `name`（字符串）、`settings`（字典） |
| settings | `capacity=2`, `minimum=2`, `selection_mode`, `ai_count=0`, `spectator_limit=2` |
| client | 地址、端口、玩家名 `甲`、空 `room_id`、房间名、上述 settings |
| 可复现完整对局预算 | `runtime_guard.enabled`, `steps`, `seconds` |

若只验证建房/worker，不需要第二个客户端、选人、`server_console_channel`、`save` 命令、恢复票据或 match journal。若要验证 save，必须在该最小建房基础上再补第二客户端、真实中局、`channel.configure(root,gateway,signal_service)` 和 `room <id> save`，不能把 save 命令当成当前失败的最小原因。

## 判断与缺口

- **不是旧 save 断言失败**：失败发生在 save 代码之前。
- **不能确认是生产回归**：`session.error` 是网关通用错误，测试没有记录 `manager.error`、room binding、worker PID/instance、ready 校验结果或内部 engine 日志。
- **应优先补诊断而非改夹具**：在允许运行时，为同一轮记录 `room id`、`manager.rooms[id].error`、binding 的 `pid/instance_id/authority_host_mode`、ready 文件校验结果、worker 专属日志和网关端口；按 room/PID/instance/time 分账，不能只扫共享 `godot.log`。
- 本次未运行 Godot，未修改生产文件；只新增本审计文档。
