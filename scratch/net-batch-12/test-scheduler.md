# 测试调度静态审计

## 范围与结论

只读审计 `tests/net_server_match_test.gd`、程序化枚举出的 22 个直接/间接继承测试，以及 `net_process_full_game_test.gd` 的 agent、会话 poll/reconnect/close、同步器、校验任务和网关关闭实现。仅新增本报告，不改生产或测试源码；按要求没有运行 Godot，以下不是运行复现或测试通过结论。

**基类没有“某客户端这一轮没推进就 break”的循环。** `play_agents()` 的两个提前退出点（85、105 行）均调用全部 agent 的目标谓词；默认要求两端 `game_over`，中局覆盖也要求双方已有提交且 round >= 2。等待期间每轮都 poll 网关和两端会话。主要风险是 agent 把“发送过”当成“已成功推进”而永久阻断同一 seq 的动作，以及部分派生等待/失败路径没有持续 poll 或收束 cleanup。

## 发现

### 1. 高：请求失败/拒绝后，同一快照永久不再行动

- `tests/net_process_full_game_test.gd:11-19`：`send_command()` 在检查发送结果之前写 `sent_seq = view.seq` 并增加 decisions，忽略 `session.request()` 返回值。`act()` 只要 `sent_seq == view.seq` 就立即返回。
- 同文件 67-71 行：group 提交同样先设置 sent_seq / decisions，忽略 `group.confirm()` 的 bool。
- `scripts/net/ui/group_selection.gd:68-76,111-123` 虽会在发送失败或对应拒绝后清除 `_submitted`，却不会清除 agent.sent_seq。会话 `request()` 的网络发送可返回错误（`lobby_session.gd:391-402`）。
- 后果：被拒且权威没有发布新 seq 时，外层仍正常 poll，但 agent 永远无法重新规划；最终只报 90/180 秒目标超时。decisions > 0 也只能证明尝试发送，不能证明权威成功接受。
- 建议：把“本 seq 待回执”与“动作完成”分开；关联请求序号和拒绝信号，发送失败/拒绝后解除等待并排除失败候选或明确失败退出，不无条件重试同一非法命令。group.confirm 成功后才计有效发送；额外记录权威接受/seq 推进数。

### 2. 中：房间清单等待超时后仍进入下一阶段；预检套件必耗一段无效预算

- `net_server_match_test.gd:35-38` 等第二端 room_files 至多 5 秒，退出后没有核验，再调用 hook / sync.begin。空清单失败会变成后续同步错误，而非明确握手/清单超时。
- `net_server_preflight_recovery_test.gd:8-10,18-31` 要求初始双方清单为空，只有 hook 内 prepare/commit 后才发布。因此基类 35-37 行在这一派生路径天然等待满 5 秒，而不是有望收到清单。
- `net_server_match_test.gd:59-63` can_start 超时后只 check，仍调用 play_agents 并花完比赛预算；`check()` 只累计失败、不停止执行（`match_journal_test.gd:10-18`）。直接 `view.can_start` 还可能在字段缺失时形成额外脚本错误。
- 建议：将“第二成员完成握手”与“批准清单发布”作为不同阶段；预检由 hook 驱动清单发布，通用阶段随后验证两端清单。各超时均打印阶段/双方错误/修订号并 cleanup-return，不继续启动未就绪战局。

### 3. 中：Linux 整网关重启等待同步阻塞，完全漏 poll

- `net_server_linux_gateway_restart_test.gd:3-15` 的 `_kill_worker()` 用 `while ...: OS.delay_msec(20)` 等外部响应，最长 45 秒，无 await、无网关/会话 poll。
- 它被 `net_server_archive_match_test.gd:51-56` 的恢复流程同步调用。外部进程可继续，但本测试线程、两端会话、窗口均被阻塞；结果文件出现只代表外部夹具完成，不代表客户端处理了断线和新状态。
- 建议：单独提供可 await 的重启 hook，用 process_frame + 两端 session.poll 驱动；不可简单把 `_kill_worker` 改 coroutine 而不改同步调用方。若必须同步执行，明确将其隔离为不要求客户端进展的外部操作，并随后设置独立客户端恢复屏障。

### 4. 中：恢复退出条件不包含数据 ACK/完整状态，仍可能提前认定“同一局面”

- `net_server_archive_match_test.gd:77-103` 每轮 poll 网关、双方、当前同步器，调度次序本身完整；但 99 行只以 `_recovery_matches()` break。
- 121-130 行仅比较 round/phase/current_player/game_over/observer，不比较玩家资源、手牌、待答效果、权威状态 hash，也不要求 accepted_revisions 对应当前修订、同步器均完成、room.phase 已退出 restoring、双方解除 connection_wait。
- `_prepare_reconnect()` 会清空镜像（`lobby_session.gd:188-202`），因此不能断言它直接读取旧 read_match 假通过。但 view、room_files、data_revision 没在这里清空：等待新会话状态时，恢复循环可能先对保留的旧清单启动同步；新 revision 到来才 cancel/重建。
- 建议：以新恢复实例/本轮认证确认、当前 revision 全部 ACK、playing/可交互状态为屏障，再比较完整权威状态 hash（私有信息用各端许可快照）。即使 coarse position 相同，也不能据此称“崩溃前同一完整局面”。

### 5. 中：外层时间预算不是硬上限，嵌套 await 可越界

- `net_server_match_test.gd:81-84` 用 wall-clock 截止，但只在每轮开始检查；`pump()` 派生实现可以长时间 await。
- `net_server_resume_identity_test.gd:6-13,33-56` 会在 pump 内执行 6 秒断线、10 秒重连、6 秒私有视角等待；这些时间全部占用同一个比赛 deadline。恢复返回时已过期限，基类仍会完成当前轮处理，下一轮才结束。
- `net_server_linux_save_recovery_test.gd:9-12,25-28,39-40` 的 10 秒回执循环嵌套单次 5 秒请求等待，也可能超过外层截止点。
- P2P 隔离校验（`net_p2p_match_test.gd:79-81`）没有测试级 deadline，但任务自身 poll 有 deadline/cancel（`room_validation_task.gd:83-94,128-134`）；若 OS.kill 持续失败，running 保持 true，测试循环可长期不退出。
- 建议：明确分别使用总耗时预算/无进展预算/单阶段预算；共享剩余截止点传入嵌套等待。超时之后不得再执行 gameplay act；无法终止隔离进程应明确失败收束，不能把任务内部预算视为必然硬退出。

### 6. 中：超时/局部早退未取消同步器，cleanup 失败未验收

- `net_server_match_test.gd:46-56` 45 秒总预算耗尽时 sync 可能仍 running；没有 `sync.cancel()` 就关闭会话。P2P 同步 100-108 行同样如此。
- `room_data_sync.gd:35-38,85-97` pin 由 cancel / 成功完成释放，没有此文件内的 PREDELETE 释放兜底。关闭会话虽取消 blob，但没有替调用方 unpin；不能仅靠局部变量离开作用域证明清理完成。
- `net_server_archive_match_test.gd:85-93` 只在 revision 更换时取消旧同步器；begin 失败立即 return、恢复总超时及目标达成时，没有统一取消 synchronizers。hook 返回 void，后继中局测试仍会继续 act，可能掩盖原恢复阶段失败。
- `net_server_console_close_test.gd:9,18,31` 创建 other 后，submitted 失败直接 return 会跳过 other.close；other 也不在基类 agents 清单。关闭目标房间/等待回执期间 other 不在 pump 中，只在最后 poll 一次，不能证明整个关闭过程它持续在线。
- 基类 cleanup（136-144 行）顺序正确：先销毁 board、解绑 group、close session、free agent、close gateway。但 `server_room_manager.gd:418-420` 忽略 stop_room 返回值；stop_room 失败保留登记（410-415 行）。测试没有读回确认所有本轮子进程退出/登记为空。远端套件的本地 gateway 不拥有远端进程，不能用本地 gateway.close 声称远端已清理。
- 建议：显式保存任务/同步器/额外会话所有权，在所有失败、超时和成功尾部统一 cancel/close；本地只验收本轮拥有的 PID/登记，远端通过明确控制接口和回执单独清理。

## 没发现的风险 / 正常链路

- `net_server_match_test.gd:112-116` 的 pump 包含 gateway.poll、全部 session.poll、process_frame；按固定顺序单轮发送暂时要等下一轮接收是正常异步行为，不属于漏 poll。
- 默认终局谓词要求两端都收到终局，不能只因权威本机结束就关闭连接。中局目标谓词也使用 all，不因某一端先到 round 2 退出。
- 同步循环 pump 后显式 sync.poll；P2P pump 由 session.poll 驱动 connection_driver，信令驱动不需要另在测试手工重复 poll（`lobby_session.gd:359-364`）。
- 恢复阶段 `_worker_ready` 等待本来只验证 worker；随后另有双方恢复同步循环，不应把前一等待返回单独判作客户端恢复完成。
- `net_server_recovery_midmatch_test.gd:16-20` 续局循环没有“这一帧没决策就 break”，一直 poll/act 到两端 game_over 或预算耗尽。
- `net_server_shutdown_test.gd:18-20` 同时 pump 与 stopper.poll，关服状态机没有被遗漏。

## 建议最小回归断言（本轮未执行）

1. 同一 view.seq 的命令发送失败/权威拒绝后，agent 必须能退出待回执状态或明确失败，而非持续空 act 到比赛总超时。
2. 一端终局晚数轮送达时，另一端已结束不能触发 cleanup；延迟动作/预览消息不应被“没进展”误判。
3. 恢复先送粗粒度 match、延迟 room_files/ACK/connection_wait 解除：必须等全部恢复屏障且状态 hash 正确。
4. sync 在总预算边缘仍 running：统一收尾后 cache pin、blob 接收、同步器 running 和本轮拥有进程均清零/退出。
5. 嵌套恢复消耗预算后，不再发送新的 gameplay 命令；外部整网关重启时客户端仍按允许的策略 poll。

## 文件枚举

程序化追溯 extends 链得出 22 个后代：net_p2p_match、net_p2p_signal_match、net_server_archive_match、net_server_console_close、net_server_console_save、net_server_gateway_restart、net_server_linux_create、net_server_linux_gateway_restart、net_server_linux_match、net_server_linux_paused_recovery、net_server_linux_pause、net_server_linux_recovery、net_server_linux_save_recovery、net_server_notice_match、net_server_pause、net_server_preflight_recovery、net_server_recovery_match、net_server_recovery_midmatch、net_server_resume_identity、net_server_shutdown、net_server_signal_window，以及 server_signal_acceptance_v3/signal_window（均为 tests 下 *_test.gd）。审核覆盖这些源码；没有启动服务、运行 Godot、连接远端或杀任何进程。
