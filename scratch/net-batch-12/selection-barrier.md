# 两位测试客户端：选人、数据屏障与座位提交链审计

## 结论（只读静态审计，不是运行复现）

当前代码中**没有发现两位客户端被固定映射到同一座位，或已成功提交的 data_ack 必然打不开 ready 屏障的契约错误**。确实存在测试夹具将“请求已发送”提前当成“动作成功”、屏障失败后继续跑整局、无反馈的提交锁和不满足声明的效果答复等缺口；它们足以在特定失败条件下让两位客户端迟迟达不到目标，但**没有本轮失败日志，不能指定其中一个为该次唯一根因**。

尤其要区分：`play_agents()` 的目标通常是**双方权威视图都 game_over**（`net_server_match_test.gd:131–132`），不是“已进入 playing”。`decisions>0` 只是发送尝试计数，不是权威成功操作数。若双方已有 match_view/decisions，失败应定位对局推进，不能再归为选人或初始数据确认。

本轮禁止运行 Godot、禁止生产改动，均遵守。旧批次报告中“新 storage_root 的父目录不存在必然创建失败”的结论**不可直接沿用**：当前 `server_room_manager.gd:137–145` 已向上寻找存在的批准父目录再安全递归创建。

## 1. 实际链与静态对账

|阶段|测试入口|权威契约 / 实际结果|
|---|---|---|
|创建和第二人加入|`net_server_match_test.gd:23–41`|甲空 room_id 创建，乙使用甲的 server_room_id 加入；甲等 view 20s，乙仅等 room_files 5s。这不是 worker 的 ready.json 已发布就算客户端进房。|
|明确数据接受|`:42–58`|每位客户端 RoomDataSync.begin → pump/sync.poll → complete → install_room_assets；只在 accepted 后发 data_ack 和 ready。同步失败直接 cleanup，不能进入 play_agents。|
|数据确认|`lobby_session.gd:759–763,1028–1036`|data_ack 要求 int revision 等于当前 data_revision；每个 connected member（包括观战者）都必须确认。require_room_data 时还要求权威 _rules_revision==data_revision>0。|
|准备屏障|`room_state.gd:65–85`；`lobby_session.gd:847–851,878–880`|ready 独立于 data_ack。人数达 minimum、真人在线且 ready，外加 data_ready，才发布 can_start=true；start 也重新校验两者。|
|座位配置|`lobby_session.gd:1254–1272`|非观战 member 顺次分配座位 0、1…，值是 member_id；AI 值为 0。玩家座位不是公网或内部 ENet peer_id。|
|选人隐私视图|`selection_authority.gd:34–53`|choices 仅含 sender 自己控制座位；choose 重新核验 controllers[seat]==sender。测试原样回传 choice.seat/name，未把网络 peer_id 当玩家座位。|
|完成选人|`class_pool_selection.gd:93–127`|御主不能被另一座位占用；所有座位有御主后随机分配从者并生成初始顺位；complete 要求每个座位已有从者。正常两人、至少两个御主时 first/back 策略不必然冲突。|
|进入权威战局|`lobby_session.gd:774–781`；`match_authority.gd:20–61`|只有房主，phase=selecting，data_ready，通过 selection.complete 和真正 game_start/录制启动及审计 flush，才 phase=playing 并发布 match_bind/match_view。|
|真人座位提交|`match_authority.gd:63–75,95–105`|controllers 映射 member→observer seat；真人全部 REMOTE，非 AI。submit 重新校验 seat、已发视图 seq 和权威 revision。测试 act 使用 view.observer/current_player，不用连接 ID 控制战局。|
|组合暂选与提交|`group_selection.gd:17–35,65–132`|bind 请求当前 seq 的预览；add/remove 更新 request_id；matching preview 才允许 confirm；confirm 发 play_group，记录会话信封 seq；精确匹配 request_rejected 才解锁；新 match seq 清空暂选并重取预览。|

服务端 worker 的 `ready.json` 与玩家 ready 是两个屏障。`server_room_worker.gd:175–202` 在完成启动初始化后写 ready.json；而玩家 can_start 在加入、同步、ack、ready 后才成立。默认基类 fixture 没有 random_sim_enabled，worker 会 set_room_files；若某个派生 fixture 或 manager.data_settings 显式加该键，则初始数据只作为候选，必须另走数据批准，不能仍假定加入后马上有 room_files。

## 2. 已确认的测试缺口与可验证失败预测

### A. 屏障失败没有成为测试前置失败（高优先级）

`net_server_match_test.gd:59–63` 等 can_start 最多 5s，随后只 check，**不 return**，直接 `play_agents()` 发一次 start。start 在权威仍不满足屏障时被拒，测试没有 start 成功确认或重试，再耗费 90/180s 等 game_over。

预测：失败现场 room.phase=lobby，selection_view 空，双方 read_match 空/decisions=0，session.error 为 start 拒绝文案。要先查成员 ready、data_revision/_rules_revision 和逐 member 的 _data_confirmed，不能归因于发牌或 GroupSelection。

数据 ack 后立刻 ready 本身并非已证实的乱序 bug：它们通过同一请求入口发送，权威 ready 不要求 ack 先到；can_start 最终同时检查两者。真正问题是测试只发送一次、等待不足后仍向后执行，且未观察每个请求是否成功。

### B. 选人与 begin_match 的布尔锁在确认前就设置（高优先级）

`net_server_match_test.gd:88–91,102–104` 和 `net_process_full_game_test.gd:114–120` 在 request 后立即 picked=true / began=true；不检查 request Error，不订阅请求级拒绝，不核验 selected 是否含本次 seat/master，也不核验 phase=playing。一次 choose_master 发送失败/权威拒绝后，该人永久不重选；一次 begin_match 拒绝后永久不重启。单独进程 fixture 的 ready_sent 同样先锁再发送（`:107–113`）。

预测：phase=selecting 且 complete=false、一座位 selected 缺失 → 查 choose 回执；complete=true 但 match_view 仍空 → 查 begin_match 回执/权威启动 error。不能仅凭本地 picked/began=true 判断成功。两个正常 first/back 候选不存在必然抢同一个御主的静态证据。

### C. 测试客户端的效果决策不满足通用声明（进入 playing 后的失败候选）

`net_process_full_game_test.gd:22–35` 优先取消任何 allow_cancel 提示；否则 active_choice 永远选择第一个 available option、count=1。权威 `match_authority.gd:177–208` 会 validate_selection 全部选择次数/要求；声明需要多项、不同次数或别的组合时，这个单项答复被拒。它不是一个保证所有数据都能跑完的策略。

预测：双方已有 match_view，停在同一个 pending effect/kind；view.seq 继续变大，某一方 decisions 继续增大，同一种答复持续被拒。检查该 prompt 的 options 和权威 validate_selection 原因，不能把“持续发包”当成真人决策成功。

`act():76` 无条件尝试 end_action，未用 actions.can_end（权威已在 `actions_for:577` 提供）。没有可提交牌组不等于当前可结束行动；被拒会重新发布视图，客户端可反复发送同样无效动作。

### D. sent_seq 是本地尝试锁，不是确认成功锁

`net_process_full_game_test.gd:11–19,67–70` 在 request/confirm 结果之前记录 sent_seq、增加 decisions。若客户端本地 transport.send 返回非 OK，没有权威新视图，act 在同 seq 永久 return。group.confirm 若同步返回 false，也没有将 agent.sent_seq 撤销。

**不要误诊成所有权威拒绝都会卡死 sent_seq**：`lobby_session.gd:789–794` 在权威 match_command 被拒时仍 _publish_match；`view_builder.gd:12–13` 每次 build 都递增 seq，所以收到新视图通常解除 agent 的 sent_seq 门槛。真正的永久锁预测是“本地发送失败 / 没有新的可接受 match_view”。

### E. GroupSelection 等待与回执：当前接口本身对齐，但没有超时恢复

当前真实 session.request 接受 registered 回调（`lobby_session.gd:391–402`），真实 session 有 request_rejected(seq,reason)，worker `_fail:1062–1070` 发 seq，当前 group 按 _preview_sequence/_submit_sequence 匹配解锁。**不能把工作进程的普通拒绝误认为网关 request_seq 文案不兼容**：后者只影响网关自身产生的拒绝，需要区分来源。

但是 group._waiting / _submitted 没有超时；若相应预览或拒绝没有到、且没有新 seq，act `:64–66` 永久等待。`_received:128–129` 遇到 ok=true 但 view_seq 错误只 return，仍等待。新视图一般可以恢复；无新视图时需要请求生命周期诊断，不能靠轮询 snapshot 解决。

现有 `tests/net_group_selection_test.gd:3–14,46` 的 SessionProbe **已过时**：只有 rejected(reason)，没有 request_rejected；request 只有两个参数，也不调用 registered。它不能验证当前 group 的三参 request 和精确序号拒绝语义；旧日志中的通过不能证明当前回执链通过。没有修改此测试。

### F. 常见零决策并非“同席抢操作”

`match_authority.gd:71–75` 真人设 REMOTE；`match_driver.gd:31–36` 不自动推进 REMOTE。这是既定“真人不 AI 托管”边界。客户端若未绑定 observer>=0、或不提交，权威不会替真人补动作；不应通过改成 AI 掩盖测试请求链失败。

## 3. 一轮失败所需的最小定位证据

父代理获得运行授权后应在**现有测试 seam** 收集这些事实，不另用 Python 重写 GDScript 规则：

1. 房间 phase/owner、两位客户端 peer_id() 与 members.id、settings.minimum/ai_count、每个 ready/connected/spectator、view.can_start/data_ready。
2. 两侧 data_revision，同步开始所使用的 revision 和 manifest；权威 _rules_revision/_data_confirmed。revision 更新会清空确认、ready 和客户端 assets（`lobby_session:1017–1022,1051–1056`），夹具未把同步绑定成不可变 revision。
3. start / choose_master / begin_match 各自会话 seq、返回 Error、对应拒绝 seq/reason，以及权威 phase/selection.selected/complete；不要只输出 picked/began。
4. playing 后每位 observer、current_player、view.seq、sent_seq、pending.kind/effect、actions.can_end、group waiting/submitted/cards、预览 request_id/view_seq、提交信封 seq 和实际权威结果。
5. 将最终失败分为：进房失败 / 数据屏障没开 / start 被拒 / 选人没完成 / begin_match 被拒 / 已进入 playing 但真人等待或规则答复被拒 / 已推进但 game_over 时间预算不足。

## 4. 核验范围与交付

已读取三份指定文件全文，并追读 room_state、selection_authority、class_pool_selection、lobby_session 关键生产/消费入口、match_authority 提交/预览/actions、match_driver REMOTE 调度、view_builder seq、room_data_sync、worker 数据发布和 manager 当前父目录安全创建逻辑。

只读搜索：仓库 docs 的历史日志显示旧版有两位真人 decisions>0 的记录；tests/runtime_reports、仓库 scratch、Hermes cache/scratch 的 `.log` 全文扫描未找到本轮 SERVER_MATCH / SERVER_JOIN_FAILURE / PROCESS_FULL_GAME 对应失败记录。没有把历史通过当成当前通过。

只创建本文件；无生产文件或测试源码改动；未运行 Godot、未运行游戏测试、未声称运行验收通过。以上确定项为静态契约事实，现场唯一根因仍待同轮阶段状态和回执关联。
