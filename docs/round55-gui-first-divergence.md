# Round55：GUI 首分歧、夹具修正与冻结交付

## 结论（不拼绿）

最后同一冻结：`E:/HermesScratch/round55-gui-first-divergence/final-ef684b20cc224fc3a049d90caac1209e/`。

| 链 | 最后真实非 headless 结果 | 退出码 | SCRIPT/ERROR | 判定 |
|---|---:|---:|---|---|
| host lifecycle | 16 checks / 3 failures | 1 | [] | 未通过，按钮之后无 accepted |
| net v2 | 57 checks / 0 failures | 0 | [] | 原46项全部保留，恢复11项此前因分支不入而未执行的检查 |
| countdown | 72 checks / 0 failures | 0 | [] | 完整15秒、真实风险确认、ZERO、取消，九图原生检查 |

因此 **不是 currentUIchainGREEN**。不拿前次 host17 的成功补本次 host16 的红；不把源端漂移当作冻结内行为根因。

`source-hashes.json` 有3472项，文件 SHA256：`ffa8ba83dd516a0534e9ebd78e9fbac344922a5340328161c345c8cdc71c5c20`。复制前源端、复制后源端、冻结端的非配置资源三方一致，`source_freeze_mismatch={}`；运行后 `freeze_drift={}`。只有副本 project.godot 按原 runner 去掉 editor MCP helper。Godot console SHA256 保持 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`。

运行期间源端三项漂移已在 manifest 原样登记：
- `scripts/net/server/server_room_manager.gd`
- `scripts/net/server/server_shutdown.gd`
- `tests/server_shutdown_close_handoff_test.gd`

它们不是本 actor 修改；本次不能声称当前完整源码无漂移或三链全绿。两次完整冻结在启动时的生产 scripts 哈希对比无差异，因此不能根据运行期间漂移解释 host 这次失败。

## 原始红证据先保存

原根：`E:/HermesScratch/round51-final-window-82fc85d0e6fd47e6acbba26e4c3f77c9/`。
完整现存21个文件已复制到 `E:/HermesScratch/round55-gui-first-divergence/baseline/`，逐文件 SHA256 在 `baseline-sha256.json`；原 countdown stdout 巨型 `COUNTDOWN_OBSERVATIONS` 解析保存在 `baseline-countdown-observations.json`。原46/13和71/3以及 stderr 均未覆盖。

原 runner 已回收 generated，因此原运行独立 request/worker finalreport/ready/checkpoint 文件不再存在，不能伪称已恢复。保存的是原始日志里实际传回的 report/serverstate/observations；新一轮另保存真实 raw 文件及首分歧 checkpoint。

纠正旧报告：原 `cancelled.png` **存在**，大小78862字节，SHA256 `1239504256c8768f1bf9c2e37b9d6dd6d564f1eefb6c848c95b2943104767b35`。它在原 manifest.images 中，原 stdout 同次 observations 是 request3/cancelled，目录4916与 `SERVER_GATEWAY_READY.pid=4916` 相符。原 wrapper3280的历史父子记录不存在，不能因它与4916不同就认串图，也不能伪造历史父子证明。最后运行已实际补录父子链。

## net：只追第一因果分歧，不按13个失败逐补

### 原因证据

短探针 `probe-37f7d7927ee84a5da28017487dabec01`：8 checks，唯一红为原第一个 activation pending；11.665秒，无错误。`ROUND55_REAL_PRESSED effect` 证明按钮真的命中，after_click hovered 是 `.../Hand/HandCard/EffectButton`。

- actions 实际批准 effect19、令咒22；按钮可用。
- board adapter 不存在、observer=-1、candidate_ids=[]、command_available=false。
- guest.seq 点击前后均为5，无 match_command 输入、无拒绝回执、双方 pending 空。
- 因此第一失败发生在 **权威前**，并非权威拒绝或规则没生成 pending。

第三短探针 `probe-4f8dde1c75c14376b9d13b676cd16a88` 明确记录 host.phase=playing、guest.phase=lobby。单独 `_publish()` 后 guest 仍是 lobby：夹具未增 room revision，正式 Session 仅接收更高 revision 的 room snapshot。生产 board 对 lobby 不构造战斗 adapter 是正确权限闸门。

### 合法夹具修正

`net_v2_ui_input_parity_window_test.gd` 在已建立真实RSA身份及ENet连接后，对其既有测试转场按正式链执行：
1. host.room.phase=playing；room.revision += 1；
2. `_bind_match()`、`_publish()`、`_publish_match()`；
3. 有界 poll 等 guest 实际 phase=playing 且 match 不空，才入正式 board。

没有给 guest 注入 phase、pending、authenticated 或 pressed；未添加生产 compat 字段。

第一完整冻结 `final-508239747db04a39b78ee68c1d25a2a2` 已把首分歧修正：activate seq6 accepted，权威/guest pending 同为 effect19、kind=active_choice。但出现一个新的精确夹具时序红：第二次翻面在 seq10 accepted 之前点击，快照到达不等于请求结算。日志中第二次 GUI hit 在 `ROUND55_RECEIPT seq10` 之前，无第二个权威命令。生产单请求锁正确拦截；只加 `wait_for(...board._battle_command_input_available("set_concealed"))` 后再点第二次，没有延时盲睡或放宽锁。

### 最后验证

原46项标签与最后57项程序化比对：`MISSING=[]`。额外11项来自原有 battlefield 分支实际进入，非删除失败项或放宽断言。真命中→activate→accepted→active_choice→option_choice→翻面→group preview→play_group→战场主动→令咒→end_action 均通过。首分歧 JSON/PNG 与真实请求/回执在 `evidence/net_v2_input/`，原生读图确认费用4、剩余魔力6与威力6。

原13个失败仅当作前置分歧之后的症状，未分别修改生产代码。

## countdown：原71/3是错误强求风险分支，不制造生产风险

### 原运行实际报告

原 request1 ready：loop_analysis.warnings=[]、无high循环；random_simulation.ok=true、budget=15.0、elapsed=16.121、simulation.warnings=[]。

原 completed 和 risk-confirmation observations 的实际后台字符串是“校验完成，正在请求应用所选数据”；随后同次 request1/applied、panel“房间数据已应用。等待成员同步。”。生产 `_poll_server()` 的无风险分支正式 `_apply_validated()` 请求 commit，符合既有策略。

原三个精确失败来自夹具要求“确认”文字、风险弹窗和隐藏RiskConfirmation的OK按钮可点，并不证明生产还在模拟。只改夹具按真实报告分支，保留风险确认分支原输入检查。没有改 approval、panel、Session、worker、规则、timer或config默认15。

### 最后同次真实链

`request1/catalog_revision1`：
- 面板15→12秒；后台12→9秒。
- report.json.ok=true；random_simulation预算15.0、实际elapsed15.484。
- 本次真实warning：“随机模拟时间已用尽，当前对局未结束”。这次因此合法进入risk，不是人造warning。
- completed：stage=ready、pending=true、awaiting_risk=true、confirmed_request=0、RiskConfirmation.visible=false（面板收起），后台“后台校验完成，等待确认，请打开本局内容”。
- Data真实按钮重开后：风险窗visible=true；原生画面有运行风险说明及“确认使用所选数据”。
- 正式OK按钮真实pressed后 request1/applied；pending=false、awaiting=false、confirmed_request=1，完成信号对应真实applied；后台空，无残留倒计时。

`request2/catalog_revision2`：真实配置改为合法ZERO；report.ok=true、simulation budget0、cases=[]、warnings=[]、无伪倒计时。后台正式登记confirmed_request2自动请求应用；没有强求不存在的风险窗。

`request3/catalog_revision3`：真实15秒任务后按正式CancelCheck，回执cancelled，panel.pending=false、awaiting=false、background为空。

完整72检查无删分支。根据本次reports走risk分支；代码仍支持无风险autoapply。原无风险15秒路径保留原始证据，但不并入最后冻结的风险路径成功计数。

### 原始 worker/ready/checkpoint

最后运行 `evidence/countdown/raw/APPDATA/FateDomination/countdown-34620/`：
- `test-checkpoint.json`（原检查与observations）；
- `rooms/bbd185961851ef21192bc76bb9655e18/ready.json`：ok=true、pid32116、authority_host_mode=dedicated；
- `.../preflight/room_validation/32116-14459025/report.json`：完整15秒真实报告，SHA256 `c3d37b9f88cb6c186af33f46ba6cc2d83e9b4b527f4a933b48ab9aded52bdb85`；
- `.../32116-44020951/report.json`：ZERO真实报告，SHA256 `982a347d29d4168cb5d8fca6c0a00046cccc8e4533b27c59e939da66f034f736`；
- `.../32116-62066785/report.json` 与progress：第三任务取消现场，不拿其中未完成simulation称完整通过；
- 各任务engine.log与worker engine实例log保存；程序扫描全部raw日志 SCRIPT ERROR/ERROR结果=[]。

worker日志 `SERVER_DATA_VALIDATION_COMPLETE` 对request1明确 task_complete=true、task_running=false、task_pid=-1；request2亦如此。它和完整report/readback一起证明最终report已接收且任务已结束，不拿UI计时到0当批准。

## 九图原生检查与自有进程

最后 `evidence/countdown/images/APPDATA/FateDomination/countdown-34620/` 的九图已全部使用 load_image_native 实际查看：
1. panel-early：剩余15秒；
2. panel-later：剩余12秒；
3. lobby-background-early：后台剩余12秒；
4. lobby-background-later：后台剩余9秒；
5. completed：后台完成等待确认；
6. risk-confirmation：真实风险文案、确认按钮；
7. applied：房间数据已应用，等待成员同步；
8. zero-budget：完成态，无伪倒计时；
9. cancelled：本次服务端数据批准已取消。

manifest 中 Toolhelp32 实际观察链：wrapper34224→GUI34620→room worker32116→validation children36616/23148/14128。最后三个suite所有owned_processes_still_alive=[]；每scene180秒上限，仅超时对本次PID树taskkill，未按名字杀进程。物理数据副本、缓存及APPDATA等均位于本次E独占generated树，证据先复制再回收generated。

net首分歧实测root viewport=1920×1080、DisplayServer.window_get_size=1920×1080。未采集HWND客户区/DPI，不主张DPI解释或系统缩放改变。

## 最后 host 红与准确停止边界

同冻结原host夹具未修改：自然终局285steps，真实终局镜像/board/按钮可见均通过。派发 `Input.parse_input_event()` 后没有accepted，准确首失败 `real_correlated_finish_accepted_receipt`；之后authority返回lobby、board转场两项是连锁症状，最后确认没有伪成功而保留终局页。

该夹具只输出 `WINDOW_INPUT return_to_lobby_real_mouse_event`，没有真实pressed观察、hovered、request登记/回执快照，所以尚无法区分命中未到按钮还是正式入口拒绝。原生终局图确认按钮存在，不能据截图认已点击；不归因为并发source drift，也未改生产生命周期/回执兜底。

下一准确scope：由host夹具唯一所有者在终局按钮记录root viewport命中/pressed→lifecycle登记request→权威accepted/rejected及phase；补齐短有界真实输入反馈，再在上游写入停止后冻结三链。本 actor 已用完三次小probe（首个探针自身缺helper解析错误/180秒自有回收已保留），不再泛跑或继续猜补。

## 本 actor 文件改动

- 修改 `tests/net_v2_ui_input_parity_window_test.gd`：合法room revision发布、accepted闸门等待、只读checkpoint与真实回执观察。
- 修改 `tests/server_validation_countdown_test.gd`：按同次报告风险分支、更多真实UI事务观测；ZERO/取消/风险路径不删。
- 新建 `tests/round55_gui_first_divergence_runner.py`：复制前后三方哈希、单冻结顺序非headless、180秒自有PID树、raw证据先存后回收、Toolhelp父子观测。
- 新建本报告；项目外保存baseline、3短probe、2完整冻结证据。
- 生产 `battle_board_v2.gd`、`v2_view_presenter.gd`、`room_data_panel.gd`、`server_data_approval.gd` **本 actor 未改**，更未写只读Session/规则/native/source/worker。
- 已把room revision、snapshot先于accepted与真实风险分支教训补入既有 `godot-window-fixture-handoff` skill。

实际运行命令：`python tests/round55_gui_first_divergence_runner.py probe` 三次、`python tests/round55_gui_first_divergence_runner.py final` 两次；各manifest保留精确engine命令、PID、退出码、唯一RESULT及错误列表。第二final是最后交付基线，退出1，不对外宣称整链绿。
