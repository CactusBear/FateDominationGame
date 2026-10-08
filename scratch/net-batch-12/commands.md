# net-batch-12：两位测试客户端 gameplay command 审计

## 结论

- **最近一次留存测试（server_match/5042475）两位客户端均没有走到 gameplay 提交入口**：`decisions=0,0`，权威恢复状态仍为 `selecting`，`match.log` 只有 8 字节 `FATEJNL1`，没有头记录或动作帧。不能把它描述为“实际 gameplay commands 被权威拒绝”；失败发生在开局之前/开局事务中。
- **更早三次测试确实有权威执行证据，但没有完成对局**：两座位的部署与结束行动进入了真实 worker 的录制日志，并改变状态哈希；随后客户端收到“事务审计不可用，操作未确认”。大量 `decisions` 是提交尝试计数，不是接受计数。
- **现有夹具无法逐条完整分辨接受、拒绝、未发送**：普通命令没有检查 `request()` 返回值、登记信封 seq 或消费逐请求拒绝；组牌路径也在 `confirm()` 之前增加计数。没有带请求 seq 的肯定接受回执。必须保留“未确认”类别，不能强分为成功/无变化失败。
- 本审计仅读取源码与既有产物、使用 Python 校验日志帧；**没有运行 Godot、客户端、服务端或测试，没有修改生产代码**。

## 1. 客户端与权威路径

信令面与本次 dedicated 测试无关；数据面为测试进程内两份客户端 session → 公共 ENet 网关 → 各自回环路由 → 独立 `server_room_worker`；权威面只在 worker 的 session/match_authority。两位 `甲/乙` 是自动测试代理，不是本次真人实际鼠标键盘验收，也不是两台机器。

1. `tests/net_server_match_test.gd:15–20,23,34` 创建两份 `net_process_full_game_test.gd` 代理，两份独立 session，甲建房、乙加入。
2. `play_agents():75–104` 发 `start`、各自 `choose_master`，选人完成后只发一次 `begin_match`；`began=true` 不检查发送或权威接受结果。只有收到非空 `read_match()` 才绑定 group。
3. `tests/net_process_full_game_test.gd:16–76` 的 `act()`：空视图/game_over/同 seq 已尝试直接返回；优先答复自己的 pending；非当前座位且无 pending 不发送；部署 → 每窗口每效果一次 activate → group 预览/确认 → end_action。
4. 普通命令 `send_command():11–14` **先**设置 `sent_seq`、增加 `decisions`，再 `session.request("match_command", {view_seq, command, params})`，忽略 Error。组牌 `act():67–70` 同样在 `group.confirm()` 前计数。
5. `scripts/net/session/lobby_session.gd:391–402` 分配独立信封 `seq`，可用 registered 回调提前登记；客户端返回的是 `transport.send()` Error，不是权威判决。同步房主路径返回 OK 也不代表业务成功。
6. 网关 `server_gateway.gd:204–244` 只转发白名单信封与 `match_command` 的 `view_seq/command/params`，客户端自报的 sender/身份不透传。
7. worker `server_room_worker.gd:5,155–159,205–220` 持有并 host `lobby_session`，在 `_process` 调用 `session.poll()`；worker 不是另外一套 gameplay handler。
8. session `lobby_session.gd:782–795` 先拒绝管理暂停/玩家掉线，再校验 playing 与字段类型，调用 `match_authority.submit(sender, view_seq, command, params)`；调用后即使失败也 `_publish_match()`，失败发送绑定信封 seq 的 error。
9. `match_authority.gd:84–105` 前后 flush 审计、校验实际座位、已签发视图 seq+revision、归档推进/规则暂停。待答按 effect 的 `_trigger_player_id` 校验；常规 deploy/move/play/end 再按当前行动者校验。
10. `match_authority.gd:420–448` → `MatchCommands` 或录制器 `perform()` → 现有规则操作；`scripts/match/match_commands.gd` 只是组合 RegularPlay/EffectManager/DeployRules/Move/GameProgress，不在客户端替代算规则。

## 2. 已有测试证据：不要混用历史运行

日志根：`E:/Projects/Godot/FateDomination/test/logs/`。产物根：仓库 `tests/runtime_reports/server_match/<run>/workers/<room>/matches/<archive>/`。

| run / 对应客户端日志 | 两客户端 attempts | 权威事实 | 本次可下的判定 |
|---|---:|---|---|
| 5042475 / `godot.log:11–16,32–33` | 0,0 | room `c2f87eed81d7313a6e61ec1bade4e90b` recovery.phase=selecting；archive `2026-10-07T23-20-47_24c020455ad5364743fb88aa` 的 match.log=8 bytes，0 frames；transactions.log=10936 bytes | **两方未发送 gameplay**。开局未闭合；最终 errors 是关闭后“所选房间已经停止或实例校验失败”，不能拿它倒推 gameplay 被拒绝的原因。 |
| 4245097 / `godot2026-10-07T23.20.07.log:23–24` | 0,0 | room `0b61bf053c0211cf88950896b1c6659d` recovery.phase=selecting；match.log=8 bytes，0 frames | **两方未发送 gameplay**。甲最终 error=请求无效；未保留 begin_match 原始关联回执，不能精确认定是哪项开局校验。 |
| 3185955 / `godot2026-10-07T23.14.11.log:23–25` | 4105,3 | room `666f82a78629e11a87a4bb31520b18ad` phase=playing；match.log=51916 bytes，头+6动作；甲 error=事务审计不可用，操作未确认 | 有实际部署/结束行动；后续至少出现审计拒绝。4105 不是接受数；日志不保存逐请求清单，拒绝数量未知。 |
| 3165755 / `godot2026-10-07T23.09.58.log:23–25` | 4164,3 | room `fe8ca46e348a50c1994bcab576a70c65` phase=playing；match.log=51920 bytes，头+6动作；甲同样审计不可用 | 同上，不能称完整对局通过。 |
| 3058736 / `godot2026-10-07T23.05.56.log:23–25` | 3,3555 | room `9d43e69de4909a96da800a49c4c6fade` phase=playing；match.log=52336 bytes，头+7动作；乙同样审计不可用 | 两方实际部署；另有一次 cancel_pending_choice 生效；后续审计拒绝数量未知。 |

上述旧日志保存失败同时显示事务审计整数身份校验错误；3185955 包含 `card_id:int:-9223371112111405033`。这能支持审计故障导致操作“未确认”，不能证明最近零命令运行也是同一错误。最新 worker engine 日志只有 `SERVER_ROOM_READY`，没有 begin_match 的具体失败诊断。

### 权威动作帧的逐项校验

使用 stdlib 只读解析 `FATEJNL1` 后的 `[u32长度][32字节digest][Variant body]`，对应 `match_journal.gd:398–409`；每帧校验 SHA256(previous_digest+body)、解析终点及前后状态哈希。不调用 Godot，不把这项当规则重放验证。

- 3185955 / 3165755：动作帧1–2 `end_current_player_action`；帧3 `deploy_to_area(..., seat 0)`；帧4 end；帧5 `deploy_to_area(..., seat 1)`；帧6 end。
- 3058736：动作帧1–2 end；帧3 `deploy_to_area(..., seat 1)`；帧4 end；帧5 `deploy_to_area(..., seat 0)`；帧6 end；帧7 `cancel_pending_choice`。
- 三份日志的全部动作帧 `before != after`，外层帧链及长度均完整；header 玩家均为 `[0,1]`，seat_kinds 均为 remote。两座位部署因此有真实权威执行且改变状态的证据。
- 日志帧不存原始客户端信封 seq、sender 或返回 result；end 也可能由 driver 自动推进，**不能把每个 end 帧都算作某位客户端接受回执**。部署含 seat 参数，但没有本次原始 controller→甲/乙绑定快照，报告不猜座位顺序。
- 最新两份空 match.log 外层无帧，不能凭 transactions.log 非空称“客户端已发动”：事务审计也会记录开局引发的规则效果。

## 3. 发送、拒绝、接受与未确认的准确边界

| 层/分支 | 目前事实 | 不能声称 |
|---|---|---|
| `act()` 没有 view、没有候选位置、非自己回合、组牌 waiting/submitted | 直接 return，未发 gameplay；`group.add` 只发 preview | 有 decisions/预览即已出牌 |
| `request()` 返回非 OK | 普通代理丢弃结果，仍 decisions++、sent_seq 锁定该视图 | transport 成功或权威拒绝 |
| group.confirm 返回 false | group 自己解除 submitted；测试代理仍提前 decisions++ | 这次 play_group 已发/已接受 |
| session/authority 明确 `_fail` | 客户端收到 error.seq，session 发 request_rejected；权威业务拒绝 | 一定没有任何规则变化 |
| 审计 post-flush 失败 | 规则可能已改变，revision 作废旧视图，返回“未确认”且不重做 | 可安全自动重发 / 规则绝对未执行 |
| 成功 submit | session 发布真实 match 与 lobby state；没有绑定该命令 seq 的肯定 ack | 任何 changed/new view 都证明该命令接受 |
| decisions>0 | 只证明代理尝试到了提交函数/confirm 前 | “both human seats submit actual gameplay commands” 的断言已证明权威接受 |

`NetworkGroupSelection` 有 registered seq 与 request_rejected 消费（`group_selection.gd:68–76,104–123`），但 `_state_changed():78–93` 会在新视图到达时清掉提交关联。worker 是先发 match 再发拒绝，故 UI 回到可操作状态不等于接受；普通测试代理完全不记拒绝原因或单次结果。

另外 `sent_seq` 只防同一视图重复尝试：worker 对拒绝也发布新视图，因此审计故障会触发成千次下一视图尝试；`attempted` 在 activate 发送前置位，发送失败也会使该窗口效果不再尝试。两者解释计数虚高/遗漏风险，不用于推断每一条历史命令内容。

## 4. 主代理后续最小验收门槛（本轮未实施）

1. 复用 `request` registered 回调记录每位代理的 request_seq/view_seq/command/transport Error；分别统计 attempted、send_failed、sent、rejected、accepted、unconfirmed，不要重用 decisions 做接受计数。
2. start/choose_master/begin_match 也登记并消费拒绝；开局失败必须输出当次 authority.error/recorder.error，而非到清理后仅剩 session.error。
3. 权威按真实 member/seat、信封 seq、view revision 记录判决；需要肯定回执时显式关联该请求，并区分操作已生效但审计未确认，不用 changed 代 ack。
4. 在关房前保存客户端拒绝/实际 match 状态；不能把 cleanup 引发的 stale-room error 当对局卡住原因。
5. 验收至少覆盖两座位实际 deploy/play_group/end_action、非当前行动者自己的 pending 答复、非法/过期拒绝、传输失败，以及审计失败后的不重放。技能+攻击扣费入场须权威事实核验，不以 can_submit 预览代替。

交接：仅新增本文件；静态范围为上述客户端代理、group_selection、lobby_session、server_gateway、server_room_worker、match_authority、match_commands、match_replay/match_journal 相关入口及五次既有运行产物。未执行 Godot、完整规则重放、真人窗口或跨机验收；缺少逐请求运行日志是最终计数/拒绝数量不可恢复的边界，不编造补齐。
