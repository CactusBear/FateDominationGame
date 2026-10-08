# lobby → playing 权威状态与两位真人席位审计

## 范围与证据边界

仅静态读取当前工作树；未运行 Godot、未启动子进程、未改生产脚本。行号以本次读取为准。

拓扑：信令面只负责发现/握手；数据面通过房间 transport/网关路由传输房间与过滤后的对局消息；权威面在 `server_room_worker.gd` 的独立进程中执行规则。LAN/P2P 权威在房主本机，dedicated 在服务端本机。UI/测试持有的回环客机会话不是该进程内的权威。

## 核心结论

1. **客机 `session.match_authority.started` 永远为 false 是设计行为，不是开局失败。** 客机只接收 `room`、`selection`、`match_bind`、`match_view`，更新 `view`、`selection_view` 和 mirror；不会调用 `match_authority.start()`。改为 worker 架构后，旧验收若仍等待 UI 会话的 authority.started 或本地 GameProgress.is_game_over，就会永久等待。应检查 `session.view.phase == "playing"`、`read_match()` 非空及 `read_match().game_over`；worker 内 started 另用真实服务端诊断/日志验证，不在客户端伪造它。
2. **`start` 只进入 selecting；选人 complete 也不会自动开局。** 必须由当前房主发送第二条 `begin_match`。没有这条请求，worker 内 started 同样不会成立。
3. **playing 不意味着两位真人会自动跑到终局。** 所有正 member_id 的控制席都标记 REMOTE，推进器不会替真人行动或答复。只轮询会话、没有两席真实指令，game_over 不会自行变 true；这是“不做 AI 托管”的正确边界。
4. 当前没有一个“无条件永远不能开局”的静态证明。下面列出已经确认的卡住条件与失败报告缺陷；具体失败运行还需要主代理核对日志，不能把静态路径当作动态复现。

## 状态推进与发布链

| 步骤 | 必要条件/动作 | 状态与发布 | 证据 |
|---|---|---|---|
| worker 初始化 | 批准数据校验、加载；host 成功 | dedicated=true，移除伪服务端成员 1，owner=0；首个非观战 join 成为 owner | server_room_worker.gd:145–183；lobby_session.gd:824–840 |
| lobby 可开始 | owner 在线；非观战席全部在线且 ready；真人数+AI数≥minimum；数据屏障通过 | `_publish()` 的 can_start=room.can_start() AND data_ready() | room_state.gd:72–85；lobby_session.gd:875–895 |
| start | 当前 owner 发请求；can_start；data_ready；选人 setup 成功 | room.start 设置 selecting；发布 selection，随后通用 `_publish()` 发布 room | lobby_session.gd:847–873、1254–1272 |
| choose_master | seat 对应 sender；选择在当前候选中 | 更新 assignment，发布 selection；不启动 match | selection_authority.gd:34–53；lobby_session.gd:852–856 |
| 完成选人 | 所有 player_ids 都有 master，随后分配 servant/initial_order | complete=true；仍为 selecting | class_pool_selection.gd:106–127 |
| begin_match | sender==owner；phase==selecting；data_ready；authority.start 成功 | started=true，然后 room.phase=playing、revision++；bind、room、match_view 发布 | lobby_session.gd:774–781；match_authority.gd:20–61 |
| playing 推进 | 未管理暂停、无未出局真人掉线；authority.step | 有变化才 `_publish_match()`；真人动作提交后也发布实际 match | lobby_session.gd:378–385、782–795 |
| 终局 | GameProgress.end_game 被规则实际调用 | is_game_over=true；builder 将它写入 match_view.game_over | game_progress.gd:200–216；view_builder.gd:12–64 |

**两个 phase 不能混用：** `session.view.phase` 是 lobby/selecting/playing/restoring；`read_match().phase` 是 prepare/outpost/action/battle。room_state.snapshot 没有 game_over 字段，终局也不会自动把 room.phase 改成 game_over；等待这些值是永不满足的错误断言。

客户端证据：lobby_session.gd:617–634 只 bind/mirror.accept；646–665 只接收 room/error。`read_match()` 在 1442–1443 读取 mirror。worker 真正泵送在 server_room_worker.gd:205–223 的 session.poll(delta)。

## 两位真人条件：什么有检查，什么没有

- `room_state.can_start()` 检查的是 **非观战人数 + ai_count ≥ minimum**，不是“至少两位真人”。minimum=2、一个真人+一个AI也满足人数门槛；两个观战成员不算真人。
- `_room_seats()` 将非观战成员依加入顺序映射为 `{player_id: member_id}`，再追加 `{player_id: 0}` 的AI。两位真人应验证 controllers 恰有两条非零且对应各自稳定 member_id，observer 分别绑定这两个 player_id。不能拿 transport peer id 或昵称替代稳定 member_id；公开身份应使用 `session.peer_id()`。
- worker 会用选人模式 `capacity(...)` 覆盖传入的 settings.capacity（server_room_worker.gd:153–154）。因此传入 capacity=2 并不保证最终只允许两人入房。只证明本次恰好两席需要显式数非观战成员和最终 controllers，且 ai_count=0；若产品要求硬锁两人，应另定配置契约，不能在此次只读审计顺手硬编码。
- dedicated worker 的伪 host 成员 1 被移除，不是第三位真人。UI 宿主也不是服务端席，首个真实非观战 join 才拿管理权。
- join、settings/configure_rules、文件清单提交会清掉 ready；两席应在最终成员和最终 data_revision 稳定后重新 ready。提前发一次 ready 后永不重试，会卡在 lobby。
- `data_ready()` 对 **所有在线成员，包括观战者** 检查当前 revision 的 data_ack（lobby_session.gd:1028–1036）。require_room_data 时还要求 revision>0 且 rules_revision==data_revision。新增观战者未 ack 也能阻挡 start/begin_match；不能只验证两个真人的 ready。
- `_room_seats()` 本身不排除断线成员，但正常 start 前 can_start 已拒绝任何断线真人；不要绕过正式 start 在夹具中直接调用 setup 来声称已满足真人条件。

## started 无法成立的可定位条件

### A. 观测错误（确定）

客机 authority.started、本地 GameStart._started、本地 GameProgress.is_game_over 均不代表 worker 当前状态。跨进程服务端测试已明确要求客户端 **不能** 启动规则引擎：tests/net_server_match_test.gd:64；其目标判定在 131–132 使用每个客机 read_match().game_over。

### B. selecting 卡住（确定路径）

- 只发 start，或选人 complete 后没发 begin_match。
- 两真人选择同一御主时，后到者可能被规则拒绝；测试若把“已发送 choose”当“选择成功”并永久 picked=true，将永远缺一个 assignment。class_pool_selection.gd:93–109 排除他席占用御主。现有服务端夹具 tests/net_server_match_test.gd:88–91 发送后立即置 picked，未根据拒绝回执恢复重选；这属于验收驱动器脆弱点，不是本次已复现的竞态。
- begin_match 非当前 owner，或数据屏障未完成，短路使 authority.start 根本没执行。
- authority.start 实际拒绝：rules 空/不完整；runtime_guard 无效；GameStart.game_start 拒绝；录制 begin 拒绝；事务审计 flush 失败（match_authority.gd:20–56）。GameStart 已经 _started、阵容模板/顺位不合法等会拒绝引擎开局（scripts/main_menu/game_start.gd:13–47、95–116）。

**确认的诊断缺陷：** begin_match 失败最后进入通用 `_fail(sender, room.error 或 "请求无效")`（lobby_session.gd:870–872），没有使用 match_authority.error；有可能丢掉真实的“引擎拒绝启动/审计失败”原因，甚至显示旧 room.error。start 的短路条件失败也没有逐门槛原因。

**确认的失败原子性缺口：** 非录制 start 先调用 GameStart.game_start，再 flush_audit，最后才 started=true（match_authority.gd:40–56）。若该次 flush 失败，引擎可能已 _started=true 而 authority.started=false；没有显式 end_session 回滚。后续 begin_match 又会被 GameStart._started 拒绝。该缺口需用审计失败夹具验证，不能在本次声称已发生。

## game_over 永不成立的可定位条件

- `MatchDriver.prepare_step()` 在 current_player 为 REMOTE 时直接 return（match_driver.gd:31–36），真人 pending 也仅由真人提交。prepare/battle 即使没主动效果，REMOTE 也不会自动 end；两席必须走 end_action 等真实入口。
- 未出局真人掉线：lobby_session.gd:1480–1492 检出，poll 不调用 step，match_command 直接拒绝；不会托管AI。观战掉线、AI席、已出局真人不应阻挡推进。
- management_paused、runtime_guard.paused 或等待真人效果答复，均能停住规则；恢复/跳过需真实管理请求及其当前 view_seq，不可通过放宽测试绕过。
- 正确终局事实只在 GameProgress.end_game 设置；不能要求 authority.started 在终局变 false，也不能要求 room.phase 离开 playing。
- **验收驱动器拒绝后的死等风险：** tests/net_process_full_game_test.gd:11–18 在发送前写 sent_seq，同 seq 不再行动；75–76 无条件尝试 end_action。若管理/连接暂停在提交入口直接拒绝而未发布新 match_view，或组牌/效果操作被拒绝后驱动器未处理 request_rejected，就可能永不重试。该策略需要按请求回执/暂停状态驱动，不应把 decisions++ 视为接受操作数量。
- `_publish_match()` 与客户端接收也有独立门槛：必须先 match_bind，mirror.accept 接受完整 view（lobby_session.gd:625–629）。服务器已结束而客户端 game_over 尚假，需要分别核对服务端终局事实、发出的 seq 与客户端 mirror，而不是再启动本地规则。

## 建议主代理采用的验收断言/诊断

1. 在最后一次成员/数据修改后确认两位非观战成员均在线，ai_count=0；不要把 members.size()==2 当成人数证据（观战也占 members）。
2. 记录每席 stable member_id、owner、ready、data_confirmed revision，以及 data_revision/rules_revision。
3. start 后以公开 room.phase==selecting 为确认，不以发送返回 OK 为确认。
4. 逐席验证 selection_view.seats/choices，选择拒绝时重新取候选；两席选定后检查 complete。
5. 当前 owner 发 begin_match；接入 request_rejected，记录 worker 内 authority.error/GameStart._started/flush 结果；只有 room.phase==playing 且每席 match view 非空才标 began。
6. 验证两席 observer 不同、对应两个非零控制席，提交成功的 gameplay 指令分别计数，不用发送计数或 AI 动作冒充真人操作。
7. stall 时按顺序记录：room phase → authority 内 started（仅worker）→ data屏障 → guard/management/connection_wait → 当前玩家与pending归属 → 本次请求拒绝 → 服务端/客户端最新 view_seq。
8. 最终要求两席 `read_match().game_over==true`，并关联 worker 的真实 game_end 历史事实；不要求客户端 GameProgress 或 authority.started 改变。

## 本次交付

只新增本审计文件。已通过静态读取交叉核对状态写入者、消息接收者与已有服务端真人驱动夹具。未运行 Godot，因此不提供运行通过、两机/跨网通过或具体失败日志归因。生产修复候选：保留 authority.start 的真实失败原因、为审计启动确认失败建立明确清理/失败关闭语义、改验收驱动器按状态/回执确认而非一次性发送标记；由主代理决定实施边界。
