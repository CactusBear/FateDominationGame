# 第二客户端“所选房间已经停止或实例校验失败”定性

## 结论与范围

**分类 (a)：同进程网络夹具的调度前提不成立。** 客户端最终完整组装占住夹具线程，主管未及时 poll/发布新心跳；真实 worker 按显式 5 秒失监督策略保存房间状态并自行退出，原内部路由随之失效。不是 600 秒 startup 期限回收，也不是端口/instance_id 错配，亦不是第二客户端首次连到了另一实例。

只改夹具；生产文件未由本任务修改。目标原断言在无节流、受控慢组装和去除临时观测的运行中，两个客户端均 true，双客户端 ACK 屏障也 true。**整套仍 exit 1，不宣称全绿。** clean 样本唯一失败为“中局崩溃恢复后真人继续提交操作直至终局”；用户缓存提醒后的最新重建缓存复跑为42/4，后续恢复/关闭失败。本次均未扩大追查。

运行基于此前失败的同一生产冻结 `E:/scratch/gateway-approved-triage/fixed/project`。结尾比较发现该冻结与当前仓库的 419 个脚本中有 13 个不同（非本任务写入），详见证据摘要；这些结果不能冒称当前整个生产工作树的集成验收。相关路由/心跳判据未变。冻结源文和 SHA 均归档，避免混用行号。

## 1. 文案与真实判据

` scripts/net/server/server_gateway.gd:97–100 `（冻结与当前相同）：

```gdscript
if not _route_is_current(peer,route):
    _fail(peer, "所选房间已经停止或实例校验失败")
    _detach_route(peer,route)
    continue
```

`:391–392`：

```gdscript
func _route_is_current(peer:int,route:Dictionary) -> bool:
    return _same_route(peer,route) and manager.binding_matches(route,true)
```

这不是两个独立的“房间停止 / 实例校验失败”文案分支，而是聚合通知：

- `_same_route`（`:386–389`）：当前登记仍是同一个 link 对象，room/PID/instance_id/authority_host_mode 相同。
- `server_room_manager.gd:304–310`（冻结与当前相同）：房间仍登记、类型/room ID 有效、完整实例绑定相同；require_ready 时，还要求 ready、不是 supervision_unknown、心跳监督有效、PID>0、原生句柄 verify 成功。
- `server_room_manager.gd:251–252`：
  `return room.get("pid") == pid and room.get("instance_id") == instance_id and valid_instance_id(instance_id)`。
- “房间停止”可由进程已退出、ready 被撤销、登记被退役等造成；“实例校验失败”还覆盖绑定更换、旧 link 回调、UNKNOWN 或可信句柄无法验证。**本判据不比较端口。** 内部端口来自 `_attach` 的 `manager.rooms[id].port`；不是根据这句文案便能推断端口冲突。

`server_gateway.gd:78` 先调用 manager.poll，再在 `:97` 检查路由。manager 在原生状态为 EXITED 时撤 ready，确认 release 后把 PID 改为 -1、token 清空（冻结 `:524–540`；当前 `:533–549`）。已建立的旧 link 因而不能继续获得转发权限。

## 2. 原现场首因、原文与序号

归档原现场：`gateway_supervisor_wait_evidence/historical.engine.log:55–56`：

```text
SERVER_ROOM_READY d19619ca9705a50fa36cb15d809332f0
SERVER_ROOM_SUPERVISOR_LOST d19619ca9705a50fa36cb15d809332f0
```

原 `supervisor-loss.json` 白名单实读字段（完整文件 SHA `5ea6bd8ee90bb23c7de86e9a4843f7a901d8daa58ce8cea4ab8bce72b243b907`）：

```json
{"ok":true,"pid":24300,"instance":"e9b5e7d0e23628fd08a06fd5f2788b5a","reason":"supervisor_timeout","result":{"closing":true,"saved":false,"room_state_saved":true}}
```

这里 saved=false 来自 `server_room_control.gd:98–107` 的当前对局尚未 started 分支，成功保存的是房间状态，不否认真实保存。`server_console_channel.gd` 冻结 `:291–295` / 当前 `:293–297` 明确接受 closing=true 且 saved=true **或** room_state_saved=true 的成功关闭回执。worker 据此 `quit(0)`，不是 supervisor 粗暴强杀。

原现场 config 声明 `supervisor_timeout_seconds=5.0`；最终实例回执仍是同一 room/instance_id，但登记 PID=-1，native_verified=false。它是原 worker 退出/退役，不是另一个实例冒用端口。该退役状态的来源文件 SHA `ce518ec69e5f04f8e33fef8039b484d13b9f6e55ae478ba6f9c1ed5096a3d3ed`。

`historical.scene.stdout.log` 中：

- `:15` 是第 1 条 R60_CLIENT_EVENT，client0 首个可见错误“尚未加入服务器房间”；不能把后来 client1 文案称为整条执行链的第一个可见错误。
- `:27` 是第 **7** 条事件：`client=1`、`signal="rejected"`、`error="所选房间已经停止或实例校验失败"`、`ticks_msec=89364`。
- `:29` 是第 **8** 条事件：client1 原网络消息 `kind="error"`、相同 reason、`request_seq=-1`、diagnostic PID=24300 / 同一 instance_id；这是未关联业务请求序号的路由通知，不应杜撰一个有效命令 seq。
- `:30`：client1 仅 1/204、complete=false、session_error 为原文案、**deadline_reached=false**；`:31` 原完整安装断言 false。这不是此前“错误为空、整清单 45 秒截断”的分支。
- `:11` 在 client0 install 前记录 no_progress_msec=5048、complete=true；后续事件记录 max_poll_gap_msec=5700，超过原 5000ms worker 失监督期限。原现场未保存每个同步子阶段的独立耗时，不能把这个值冒称精准 assembler 耗时。

历史缺少 `_route_is_current` 失效瞬间的逐项采样，不能事后捏造某一微观门的即时值。它已有 worker 自报 `supervisor_timeout` 和同实例退役实物，足以区分本次“worker 停止”与实例 ID/端口错配；本轮受控回退进一步取得实际失效出口逐项值，见第4节。

## 3. 分类依据：生产明确声明与夹具耦合

- `server_room_manager.gd` 冻结 `:412` / 当前 `:421`：`var supervisor_timeout_seconds: float = 5.0`。
- manager.poll 每 1000ms 发起正常心跳维护（冻结 `:518–521` / 当前 `:527–530`）；`_write_supervisor` 发布当前 room/PID/instance_id 绑定及递增 version（冻结 `:831–842` / 当前 `:840–851`）。
- `server_room_worker.gd:343–345` 只接受同 room/PID/instance_id 且 version 递增的 pulse；`:350–351` 原文：

```gdscript
if Time.get_ticks_msec() - _supervisor_seen_msec > _supervisor_timeout_msec or preload("res://scripts/net/server/server_console_channel.gd").saved_close_receipt(_supervisor_loss_result):
    _close_after_supervisor_loss()
```

- worker `:369–382` 经真实 `prepare_close()` 保存，发布 `reason="supervisor_timeout"`，有有效 saved-close 回执后自行退出。对恢复/开局/归档忙状态仍有原门禁。
- manager 已 ever_ready 的同一 binding 不再消费历史 startup deadline（冻结 `:559–562` / 当前 `:568–571`）。原现场早已 READY，不能把 600s startup 预算解释成这个错误。
- 正式独立主管由 `server_cli.gd:277–284` 的 `_process` 驱动 gateway.poll；客户端内容组装属于另一客户端进程。夹具则在 `net_server_match_test.gd` 的同一个 run/pump 中同时驱动网关与双方客户端。
- `room_data_sync.gd:78–85` 同步调用 assembler.assemble；`room_data_assembler.gd:24–28` 虽有 start/poll 分批原语，同步兼容入口仍 `while running: poll(2)`，整个最终组装不返回夹具主循环。随后 public install 还要完整哈希复读。

因此环境性能会决定何时撞线，但它不是根本分类：夹具错误地假定客户端整清单同步计算始终短于主管失监督期限。本轮固定修正后，即使组装总调用实测 14.6/14.0 秒，真实 worker 仍存活且原断言通过；移除维护就真实退出。**不需要改变生产 5 秒策略，也没有借用 startup 秒数扩大它。**

## 4. 唯一夹具修正与回退红证明

修改 `tests/net_server_match_test.gd:70–74`：创建一个只 poll 网关和双方 session 的维护 Callable，绑定测试专用、兼容原类型的内容组件。它不会递归 poll 当前 sync。

新增 `newtests/gateway_client_content_maintenance.gd`：

- CooperativeAssembler 复用原 start/poll(2)/complete，在原批次间执行维护，不跳下载、缓存验证、长度/哈希校验或原子发布。
- CooperativeAssets 复用原 install 的可选 maintenance 检查点。夹具在安装前为 session._assets 放入兼容测试子类；public `session.install_room_assets(root)` 入口仍按原样调用，错误/完整安装判据不变。这个替换是测试组件接线，不是生产 API 改动。
- 保留原所有 check 语句，accepted 的四项布尔表达式逐字未改；ACK/ready 仍在完整安装通过后发送。机器校验见 `assertion-preservation.json`。

受控故障在两版本相同的每个 assembler.poll 批次施加 35ms 墙钟延迟（不改生产），fixed 仍维护主管；回退则恢复本次修正前完整夹具字节，只保留同一延迟与只读 route 观察器。

- paced-fixed：两客户端组装耗时 14599 / 14037ms，原断言 true/true，双 ACK 屏障 true。
- **同副本回退**：client0 组装 10380ms，期间不发布心跳；`:13` 首客户端原断言仍 true，随后第二客户端原文案重现，`:36` 原断言 false。目标红在第二客户端，不是另一个预算断言。
- `rollback.stdout.log:18` 失效出口原采样：`same_route=true`、`binding_matches=false`、`require_ready=false`、route_pid=29932、current_pid=-1、ready=false、ever_ready=true、supervision_unknown=false，route/current instance 都是 `627799542a6c6dee6bf647192c7f3ed6`。**此处实际是 manager.matches_instance 的 PID 退役失配，不是 instance_id 错配、UNKNOWN 或端口判据。**
- `:32` client1 rejected 原文案；`:34` 原网络 error/request_seq=-1；`supervisor-loss` 回执再次 reason=supervisor_timeout，room_state_saved=true。`:15–16` 更早的 client0 回调已见“绑定相同但 require_ready=false”，说明原生存活校验在登记释放前也会先失效；不应把这两个时刻混成一个固定顺序的状态。
- `finally` 立即恢复：回退前/恢复后 SHA 都为 `fc014f485c38e317a1915e47ce03070e189cfad49927d14b8cee8cf09351a353`；临时回退 SHA `eda8e53fd255c6af840d83a01556a3ebe31fe7cf7bf4db5ac29575953157d571`。见 `rollback-restoration.json`。
- 全部自有 Job 结束后移除慢组装与只读 route 观察器，并将隔离副本夹具恢复到仓库基准；摘要逐文件记录 SHA 相等。最终另做 clean，无临时采样、无延迟，输入夹具 SHA 与当前仓库一致。

仅原夹具修正和测试子类留在仓库；生产源码没有改动。

## 5. 实际套件结果

CHECK 按真实输出条数计，不按标签去重；ERROR 只统计 `ERROR:` / `SCRIPT ERROR:`，不把 `SYNC_ERROR` 标签算引擎错误。早期 runner 的 rollback receipt.error_count=1 是该宽匹配字段，保留原回执；摘要按原始 stdout/stderr 精确重算为0。

| 样本 | CHECK true/false | 原目标两客户端 | exit | 引擎 ERROR | Job ActiveProcesses |
|---|---:|---|---:|---:|---:|
| fixed 无节流，有耗时采样 | 42/4 | true / true | 1 | 0 | 0 |
| paced-fixed | 42/4 | true / true | 1 | 0 | 0 |
| 同副本回退 | 11/3 | true / false | 1 | 0 | 0 |
| clean，无临时观测/节流 | 54/1 | true / true | 1 | 0 | 0 |
| **最新 cache-verified，独立 import 后无临时观测/节流** | **42/4** | **true / true** | **1** | **0** | **0** |

clean `stdout:11,13` 两原断言 true，`:14` 双 ACK 屏障 true；`:294` 唯一红“中局崩溃恢复后真人继续提交操作直至终局”；`:308` RESULT checks=55。真实保存关闭及 release 在该样本通过。

### 用户提醒后的全局类遮蔽自查

源冻结及 diagnostic/fixed/paced-fixed/paced-fixed-v2/clean 五份自有副本，**全部不包含** `newtests/join_shape_session_wiring_evidence/`，缓存的唯一 `MatchLobbySession` 条目均指向 `res://scripts/net/session/lobby_session.gd`。因此没有需要删除的归档，也没有为该不存在的目录伪造加 `.gdignore` 操作；本任务自身证据目录另有 `.gdignore`。

为独立确认，创建 cache-verified 干净副本并真实执行 `--headless --fixed-fps 60 --path ... --import`：exit0、ERROR0、Job0；重建后与关键场景运行后再次核缓存映射，仍为生产文件。关键场景无临时观测/节流，两个原断言与双ACK屏障 true（stdout:11/13/14），RESULT checks=46、42/4、exit1、ERROR0、Job0，后续恢复失败而非本任务目标。完整检查与复跑回执见 `cache-verified.class-cache-verification.json`。

本轮没有出现 Session 解析失败、lobby_screen 编译失败或 MatchLobbySession 找不到。前述诊断不完整样本的无 RESULT 未推断为产品缺陷；非法故障脚本的 parse error 属于已定位的测试类型表达式，不作为产品证据。其他代理使用受遮蔽工作树的结论不在本轮证据链内。

所有有效运行都是 `--headless --fixed-fps 60`，自有 E scratch，TMPDIR/TEMP/TMP/APPDATA/LOCALAPPDATA 均在 E，Windows Job Object、外层业务看门狗1200s。未对 PID17120/28100操作。

另保留但**不作定性或回退证明**的失败：首次诊断在 sync 期间 exit1、无 RESULT、ERROR0，原因未定；第一版慢组装诊断脚本有类型表达式 parse error（ERROR2），外层工具420s中断其后续回退。确认自有进程已不存活后，已立即恢复源字节并验证 SHA；后来改用显式后台 Job 管理，修正诊断脚本并 check-only=0 后取得上述有效对照。归档器曾碰到重复 READY 目录的相同日志，已按 SHA 去重并完成归档。

## 6. 文件与 SHA256

本次唯一修改的既有仓库夹具：

- `tests/net_server_match_test.gd`
  - 修前（包含前一轮 approved-sync 预算修正）：`a3dedfd5e6d886d1df47fb0478956f132173d58c770b4e480a3bc66959ec020c`
  - 修后：`57346fad455f46f44d13845919f29bfb635f963b7e19d3868d3a02ec88ff7b7f`
- 新增 `newtests/gateway_client_content_maintenance.gd`：`a785bf7274d8513d5b9b0f0c993ac502d4ba46caec79713f0f755938b253080c`
- 新增本报告、`newtests/gateway_supervisor_wait_evidence/`（runner、只读观察器源码、原始日志/回执、冻结源文、恢复/完整断言校验及摘要）。全部新增文件 SHA 见该目录 `sha256.json`；`.gdignore` 防止证据代码参与资源发现。

未提交、未推送。既有其他工作树改动未接管。

## 7. 命令与未验收

```text
TMPDIR=E:/scratch TEMP=E:/scratch TMP=E:/scratch python -B newtests/gateway_supervisor_wait_evidence/run_supervisor_triage.py fixed
TMPDIR=E:/scratch TEMP=E:/scratch TMP=E:/scratch python -B newtests/gateway_supervisor_wait_evidence/run_supervisor_triage.py paced-fixed-v2
TMPDIR=E:/scratch TEMP=E:/scratch TMP=E:/scratch python -B newtests/gateway_supervisor_wait_evidence/run_supervisor_triage.py rollback
TMPDIR=E:/scratch TEMP=E:/scratch TMP=E:/scratch python -B newtests/gateway_supervisor_wait_evidence/run_supervisor_triage.py clean
```

实际 paced-fixed-v2 先 prepare+check-only 通过，再调用 runner.execute；回执保存真实引擎命令，而不是假冒整套成功。runner 拒绝覆盖运行目录。输出归档在 `newtests/gateway_supervisor_wait_evidence/`，原自有运行目录 `E:/scratch/gateway-supervisor-triage/`。

未验：原历史失败每个同步子阶段的独立耗时、当前13个不同生产脚本的整链集成、单文件单批次本身耗时超过5秒的极端负载、其他继承此夹具的套件、非 headless / 真人多机 / 跨网。恢复到终局的新剩余阻断未追查；诊断无 RESULT 的那次异常退出未追查。本次只闭环第二客户端在批准文件同步阶段遇到 worker 失监督退出这一条原因。
