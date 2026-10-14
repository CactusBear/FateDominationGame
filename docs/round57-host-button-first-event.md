# Round57：宿主按钮首事件分歧与同冻结收尾

## 结论

宿主首分歧已定位到**窗口夹具的输入事件排序**，不是 accepted 协议、权限/view_seq 或嵌入窗口坐标。原 `Input.parse_input_event` 连续派发 motion/down 时，motion 尚未建立 hovered，down 未形成有效按钮按下；下一帧 hovered 才到目标，up 不产生 pressed。仅把 motion 与 down 分帧，真实按钮/生命周期/回执/移交链恢复。

最终同冻结：host headless **14/0**、host GUI **19/0**、net **44/22**、countdown **72/0**。整链 **RED，runner 退出 1**；不得拼接 round55 net57 的旧绿结果。没有越权修改生产或其它 GUI 测试。

## 精确证据根与命令

- 首探针（先观察到绿色，明确不是原顺序基线）：`E:/HermesScratch/round57-host-button-first-event/probe-13d7b69ca2cb498aa6ad2c084bc54fff/`
- 第二探针（恢复原顺序，真实 RED）：`E:/HermesScratch/round57-host-button-first-event/probe-85350a2d979c412bb22d6858f6ce2bee/`
- 唯一 final：`E:/HermesScratch/round57-host-button-first-event/final-b93f0a1f33414f6780c3edb846e5e944/`

真实命令：`python tests/round57_host_button_runner.py probe` 两次，分别退出 0/1；`python tests/round57_host_button_runner.py final` 一次，退出 1。各 manifest 保留完整 engine 命令、Job 根 PID、退出码、RESULT、错误列表。没有第三探针、第二 final 或其它泛跑。

原基线索引仍为 `docs/round55-gui-first-divergence.md:118-124` 与 `E:/HermesScratch/round55-gui-first-divergence/final-ef684b20cc224fc3a049d90caac1209e/`；本轮结论从新原始日志重建，不把旧报告当因果证明。

## 修改前耦合/V4A 审查

生产组合根 `battle_board_v2.gd:484-503` 已把正式 ReturnToLobby.pressed 接到 `_request_finished_lobby`，生命周期通过注入的 `_read_finished_lobby_request` 检查 playing/owner/game_over/int seq/management pause。`battle_host_lifecycle.gd:60-103` 在发送前登记 attempt，经 Session 注册 sequence，只消费匹配的真实 completed；大厅/空镜像与 accepted 缺一不可。不存在需要复制的终局处理或回执兜底。

夹具原先把派发标签当作点击，没有 pressed/hovered/request 证据。改动只在夹具拆出只读观察函数：viewport、根 screen transform、Window.is_embedded/position/id、事件坐标、button rect/disabled/mouse_filter、祖先及目标点可见控件/Window、真实 gui_input down/up 和 pressed、lifecycle pending/unknown/attempt、Session seq/真实 receipt/phase/view_seq。诊断既不派发命令，也不写关联字段。修改前已中文说明，使用 V4A 局部补丁。

窗口输入修复保留原 `Input.parse_input_event`，motion 后等待一次 `process_frame`，按下前检查实际 hovered == button；不增加秒数 delay、不吞事件、不改变 accepted 条件、不制造 lobby 成功。headless 改走公开 `lifecycle.request_lobby()`，移除旧 `button.pressed.emit()`，仍完整保留 14 项且明确不属于 GUI 点击。

## 两个探针的真实对照

第一探针新增观察时不慎已插入 motion 后的一帧，实际 GUI 18 项全绿、自然终局 279 步。已明确披露它不是原顺序 RED，没有假称先红后绿。

第二探针唯一行为变量是撤掉该帧，恢复 motion/down 同帧。自然终局 276 步；按钮 rect `[P: (1472,345), S: (194,31)]`，point `(1569,360.5)`，viewport/window 均 1920×1080，screen transform 单位，window position `(320,150)`，`embedded=false`，按钮可见且 enabled。

第二探针 `engine.stdout.log:18-21`：

|阶段|hovered|真实 pressed|Session seq|lifecycle attempt|receipt|phase/view_seq|
|---|---|---:|---:|---|---|---|
|before_motion|空|0|5|{}|[]|playing/277|
|after_motion，同帧|空|0|5|{}|[]|playing/277|
|after_down，下一帧|目标 ReturnToLobby|0|5|{}|[]|playing/277|
|after_up|目标 ReturnToLobby|0|5|{}|[]|playing/277|

结果 17 checks/4 failures；首个新增失败是 `root_gui_input_reaches_real_button_pressed_exactly_once`，随后保留原失败 `real_correlated_finish_accepted_receipt`、authority lobby/reset、transfer；保留终局页断言成功。不把后续三项当独立生产故障。

两探针 source hashes 的差异只有 `tests/round47_host_lifecycle_board_test.gd`；没有生产变量变化。哈希分别：
- 首探针：`42d9bd769740542049bb4de7c14ede3973f5dfa41b8715ca906fa240394d6014`
- RED：`09a969e163d0b7387d38834c145943edbb10449c40b015fa0e98be50d3752d01`
- final：`88ac7a8aa8926ebe9c51303f35c016f5a3f4204de9c8c9cbf54e403268d4ab0b`

## 唯一 final：真实结果与 current UI chain

|顺序|场景|Job根PID|秒|exit|checks/failures|
|---|---|---:|---:|---:|---|
|1|host headless|14964|67.096|0|14/0|
|2|host GUI|33592|90.117|0|19/0|
|3|net GUI（目标57，本次未达到）|20112|88.020|1|44/22|
|4|countdown GUI|21388|79.589|0|72/0|

host headless/GUI 分别自然终局 279/277 步，沿旧公开 host/configure_selection/ready/start/choose_master/begin_match 与 AI controller 夹具；没有新 seed、注入 game_over 或硬编码终局步数。复用既有 `seed(20261005)`，不宣称覆盖无种子随机稳定性、真人、多机或 OS 硬件输入。

host GUI 日志与 `raw/APPDATA/FateDomination/round57-host-state.json`：motion 后真实 hovered=目标，gui_input down/up serial=1/2，随后 lifecycle.pending=true，attempt 从 sequence=0 到 **6、settled=true、accepted=true**；真实 Session receipt `{sequence:6,ok:true,reason:""}`，最终 phase=lobby、match 空、pressed=1、transferred 一次。回执可同步早于后连接的 pressed 观察回调，这是信号订阅顺序，不是无点击自行 accepted。

原生查看 final 的 12 图（host2、net1、countdown9）：
- host terminal：真实“对局结束”和右上“返回房间大厅”；host after：正式联机大厅，保留生命周期房主和 AI1-6，未准备。
- net 当前图：行动阶段棋盘，中央明确“与房主连接中断”，不能验收完整 net UI chain。
- countdown：panel 15→12 秒，大厅后台 12→9 秒，完成等待确认；风险弹窗明确模拟时间耗尽及静态未覆盖11，不是损坏报告；点击正式确认后已应用/等待同步；ZERO 完成等待确认、取消态真实显示取消。此轮实际风险分支，不宣称本轮动态覆盖无风险自动应用；已有无风险分支代码只读保留。

countdown 的 `raw/APPDATA/FateDomination/countdown-31440/` 保留完整 test-checkpoint、room worker ready、任务报告和日志。15秒 report SHA256 `31b08dfd1a933047cfe21adb06219b321cc07a9bed6ce510c9f7e351aa49c8e5`；ZERO report `70537341017e261e5648353152ecf1ca4e291bcc1170b5adea74c0cbf0ef4fa7`；第三取消任务不能当完整模拟通过。

## net 新阻断：准确停止，不猜生产补丁

`evidence/net57/engine.stdout.log:10-11` 首 checkpoint：room/host revision=4、phase=playing、view_seq=2、registered_seq=5、candidate_ids=[22,19]、command_available=true、adapter_present=true、attempt/pending={}；hovered 为 HandCard，button rect `(832.7762,991.9425)/(110,28)`。紧接 `native card exposes authority-approved activation button=false`，该分支没有点击主动按钮、没有 ROUND55_REAL_PRESSED/RECEIPT/authority input。随后翻面/选牌/确认等失败与截图连接中断全部保存；不能以 hovered=HandCard 推断 EffectButton 命中，更不能把22项串联失败推成22个生产问题。

只读 net 夹具已有 before checkpoint 未记录 button.visible/disabled、断线发生时点及原因，因此**尚未定位**为何主动按钮不可用、何时断线、二者因果。runner 本次只保留 net runtime PNG，未另复制 res://tests/runtime_reports/round55-net-before_activation.json/PNG；相同 JSON 原文在 stdout 完整保存，不虚构遗失文件存在。应由 main/其唯一测试写入者在该首分歧补证据；本 actor 已用完预算且无 net 写入权限，不继续试探或把旧 net57 结果补账。

## 冻结、scope、生产变化与清理

runner 从三场景追踪实际 res://tests 依赖，仅复制三套 gd/tscn 与实际加载的辅助 gd；不把整个 tests 纳入哈希。manifest.source_scope 精确列14个测试资源（含 setup 依赖，非14套执行）；其它 worker 未运行 tests 不参与漂移门槛。生产 scripts/assets/data/game_data/addons 全部实际字节（含 native binary）分别复制前/后/冻结哈希；每套后复核同一 freeze。MCP autoload 只在冻结 project.godot 明确移除。

两探针及 final 各自 `source_freeze_mismatch={}`、`source_drift={}`、`freeze_drift={}`。final 后当前源码再比哈希亦无变化。

与 round55 旧冻结相比，真实生产变化有：
- server_room_manager.gd：`65a19312d7e3afbeed6dd238d03bf4437613ad9e915555c4316a58f8091cdddb` → `fadbeb892cfce741d62b95ff1c452d86b883d9a39c811851318d4a97f3799d53`
- server_shutdown.gd：`620b9c7ff62f02cbb25a45f18a6db626f23d720ea987baf277e9a78018efaa76` → `7526d0b8fd7d427a04a67085f462425f845e883a3210ee8017a0a30963b60227`

它们在本轮三个冻结间未变化；不是运行中 drift，也不因此认定 net 红由 shutdown worker 导致。

每 scene 180秒、8GiB监控预算、2GiB最低余量，E物理路径；APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR 仅子进程环境隔离。复用 OwnedJob 以 suspended root 先绑定 Job 后 resume；不是按名字杀进程。所有运行 active_owned_processes=0、exited=true、log_handles_released=true，无超时。证据先复制、仅本轮 generated 子树回收，generated_removed=true。程序扫描 final全部16日志，SCRIPT/Parse/ERROR/泄漏项={}。

## 本 actor 文件与边界

- 修改：`tests/round47_host_lifecycle_board_test.gd`。
- 新建：`tests/round57_host_button_runner.py`、本报告。
- 更新既有 `godot-windows-input-verification` 技能的输入缓冲/同步回调观察教训。
- 未写：board/lifecycle/Session/规则/manager/shutdown、其它 GUI tests、引擎或系统缩放。
- `/tests/` 被 `.gitignore:47` 整目录忽略，交付文件仍真实存在；没有擅自 git add/commit。

**剩余门槛：net57 整链当前失败；无风险自动应用本轮未动态走到；OS硬件/多机/跨网不在本轮证据范围。宿主修复不等于总体交付全绿。**
