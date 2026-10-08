# server_cli / shutdown 信号调用路径（只读取证）

- `server_cli.gd:_ready()` 在初始化完成后把 `shutdown.completed` 连接到 `get_tree().quit(0)`，并注册本机控制台 `stop -> shutdown.start`、`stop-status -> shutdown.status`。
- `server_cli.gd:_process()` 每帧先 `take_request()`；非零请求打印 `SERVER_SYSTEM_STOP_REQUEST`，调用 `shutdown.start()`，失败只打印 `SERVER_STOP_FAILED`，随后继续 `gateway.poll()`、`signaling.poll()`、`console.poll()`、`shutdown.poll()`。
- `server_shutdown.gd:start()` 只进入 `pending` 并发出房间 close 请求；重复 start 在 `stage == pending` 时直接返回 status，不递归调用自身。
- `server_shutdown.gd:poll()` 通过 `console._room_result()` 等待回执，再按真实 process binding 查询状态；成功才进入 `complete` 并 emit `completed`，因此正常退出路径是一次性 `completed -> get_tree().quit(0)`。
- `server_cli.gd:_exit_tree()` 才调用 `_system_signals.disable()`，清理信号适配器后关闭 signaling/gateway；未见在 `shutdown.start()` 或 `shutdown.poll()` 中禁用 handler 的路径。
- `server_console_channel.gd:poll()` 会先 `_poll_room_closes()`，但它只处理单房间 close 回执，不调用 `server_shutdown.start()`；没有发现递归退出调用。
- 结论：静态路径未见 shutdown 信号递归退出，也未见关服等待期间禁用 handler；全局退出仅由 `shutdown.completed` 的单个连接触发。该结论是源码静态证据，不替代 Godot 运行验收。
