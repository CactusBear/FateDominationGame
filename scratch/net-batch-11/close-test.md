# close 测试失败路径与回执生命周期审计

## 结论

- `tests/net_server_console_close_test.gd` 已覆盖真实的本机控制入口：`server_console_channel.execute("room <id> close")` → 写入房间 `control/<request_id>.request.json` → 房间子进程 `server_room_control.poll()` 消费 → `prepare_close()` 先保存 → 写入 response → 删除 request → `shutdown_ready` 触发子进程退出。
- 本轮“request 可删除后消费”修复覆盖了 close 的实际消费点：`server_room_control.gd:48-52` 只有 `Channel.write_json(response_path,response) == OK` 后才删除 request；写回执失败时 request 保留，且不会发出 `shutdown_ready`。这不是只在测试替身里删除。
- close 测试当前验证了最终回执能在房间进程退出后读取，但**没有断言 request 已被删除，也没有验证 `room forget` 清理 response 后的终态**。因此不能仅凭该套件证明 request/response 生命周期完整收口。
- 未运行 Godot，以下结论来自源码、调用链和测试静态审计。

## 真实入口调用链

1. `server_console_channel._room_close()` → `_room_request(room_id, "close")`。
2. `_room_request()` 校验 `rooms`、ready 报告、`id/pid/instance/authority_host_mode`，写入 `control/<id>.request.json`，仅返回 `status=pending`。
3. `server_room_worker._process()` 调用 `_control.poll()`；`server_room_control.poll()` 校验五字段请求和当前实例。
4. close 请求调用 `prepare_close()`：运行中调用 `save()`，先 flush journal、持久化 recovery；未运行则仅持久化 recovery。失败直接生成失败 response，不发关闭信号。
5. 成功 response 写盘后才删除 request；随后 `shutdown_ready.emit()`，worker 退出。
6. `server_console_channel._room_result()` 读取并校验 response；即使 request 已删除，只要 response 仍在且实例字段匹配，仍可消费最终回执。
7. `room forget` 才删除 response；它拒绝仍存在 request 的情况，并不删除 matches/recovery 存档。

## close 测试已覆盖

- 关闭命令只返回 pending，不把提交当作完成。
- 运行中房间先保存，再确认 `closing=true`。
- 房间子进程真实退出。
- `recovery.json` 与 `matches/` 保留。
- 公共网关、另一房间及另一房间客户端仍在线。
- 目标房间退出后仍可读取最终 response。
- 失败语义由父套件/相关套件覆盖：未就绪拒绝、未启用录制拒绝安全关闭、异步归档期间 request 保持待处理、无回执超时不强杀进程。

## 未覆盖与失败路径风险

### P1：close 专项漏掉 request 删除断言

`net_server_console_close_test.gd` 在拿到最终 response 后直接结束，没有检查：

- `control/<request_id>.request.json` 不存在；
- `control/<request_id>.response.json` 仍存在，直到显式 `room forget`；
- `room <id> forget <request_id>` 成功后 response 消失，而 recovery/matches 仍存在；
- 再次 `room result` / `room forget` 返回明确失败。

因此“request 删除后仍能消费 response”只由实现代码及间接调用表现支撑，不是 close 测试的显式验收条件。

### P1：回执写入失败未被 close 测试覆盖

`server_room_control.poll()` 的安全顺序是正确的，但专项没有注入 `Channel.write_json(response_path, ...)` 失败。需要静态/夹具验证：request 保留、不会 emit `shutdown_ready`、不会让 supervisor 将关闭视为成功。当前 `server_shutdown.poll()` 只有拿到 `closing=true` 且 PID 已退出才完成，方向正确。

### P2：控制通道客户端超时会留下孤儿 response

`server_console.gd` 超时分支删除 request；若服务端恰好已经消费 request、随后写出 response，response 会无人删除。该入口不是房间管理 `room result/forget`，目前没有通用 TTL/回收路径。它不影响 close 测试的 room control response，但属于同一回执生命周期的未收口分支。

### P2：已存在 response 时直接删除 request

`server_room_control.poll()` 发现同名 response 后直接删除 request，不校验旧 response 的 request_id、room、pid、instance 和 action。随机 128-bit ID 使正常碰撞极低，但本机目录中残留/伪造同名 response 时，request 会被静默丢弃。至少应让测试锁定“已有 response 不得误确认新 request”，或在消费前校验回执归属。

## 失败路径结论

- 子进程拒绝请求：会写失败 response，再删除 request；不会触发 close 信号。请求失败本身可通过 `room result` 读取，之后需 `room forget` 清理回执。
- 归档/持久化失败：`prepare_close()` 返回失败，request 删除、失败 response 保留；不会退出进程。此时不能把 request 是否删除解释为动作成功，消费者必须看 `response.ok`。
- response 写入失败：request 保留，进程继续运行；close 不发 `shutdown_ready`。这是当前实现最关键的失败保护，但尚无专项断言。
- 房间退出后 response 缺失：`_room_result()` 返回“房间进程已退出，未确认操作成功”，不会把进程退出当保存成功。
- `server_shutdown` 超时：保留进程，不强杀；stage=failed，并保留停止接纳状态。已有失败测试覆盖这一语义。

## 建议的最小补强（本轮未修改生产代码）

1. 在 close 测试中，response 返回后断言 request 不存在、response 存在。
2. 调用 `room <id> forget <request_id>`，断言 response 删除且 recovery/matches 仍在；再次 result/forget 均失败。
3. 增加 response 写入失败夹具，断言 request 保留、shutdown_ready 未发出、进程未被标记为成功关闭。
4. 对 `server_room_control` 的“已有 response”分支增加归属校验或明确记录冲突，不要静默删除 request。
5. 单独记录 `server_console.gd` 顶层命令超时后的孤儿 response 回收策略；不要把 `room forget` 误当成该入口已有的自动清理。

## 文件范围

- 只创建：`scratch/net-batch-11/close-test.md`
- 未修改生产代码和测试代码。
