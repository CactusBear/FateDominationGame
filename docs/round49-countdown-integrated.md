# Round49：后续 Session/status inbox 的真实15秒倒计时单冻复验

## 结论与冻结边界

**本次新冻结倒计时链 GREEN，不沿用 Round48 的旧72。** 两套原测试串行执行，同一工程/引擎/source 集：

|真实执行|结果|墙钟|
|---|---|---|
|`server_simulation_default_budget_test`|13 CHECK，唯一 RESULT，failures=[]，exit0；真实 CLI 子链24项、child exit0|34.627s|
|`server_validation_countdown_test`|非 headless，72 CHECK，唯一 RESULT，failures=[]，exit0|77.138s|

- 本次覆盖 Session `89f250…c005`、status inbox `c46b44…f9c3`，即 Round48 GUI 未覆盖的后续版本。全部785项冻结源码执行前后 hash 一致，冻结副本 drift=[]，执行器/helper drift=[]；原生读完9张截图后再次读回源 hash，drift=[]。
- 探针、两次真实导入、两套场景均 exit0，无 SCRIPT ERROR / SHADER ERROR / ERROR；实际服务端、validation 与 CLI worker 全部日志也无这些错误。
- 不覆盖执行结束后 Session/board/validation task 唯一写入者的新修改。主代理已说明正在补终局 receipt、迁 board 威力段和 validation task bootstrap 调用；不等待、不泛跑、不把本次结果扩为未来统一候选。
- **最终交付读回发现执行结束后的两项生产更新**：`server_cli.gd` 从执行hash `d2b54b9f18d4f8c864061397cde3aca2a91386c35a4c9a922fb3e6529a6e4418` 变为 `8ecc943bd496ef2c85e16e66c3495a6b37b63818d56e94e2e398c0a94ddfaf6a`；`room_validation_task.gd` 从 `4162b76f81f22d4549fad66caa9540cc9162413d01a71cf62af8e5b6e9fe81da` 变为 `a96ac36c35bda7310dc85512d0888f00c778dddd639f93567f05671d2c80818b`。执行窗口source_drift=[]仍成立；**当前工作树不是本次冻结，不能称这两个新版本已GUI验收**。遵循主代理指示保留成果，不等待writer、不另开窗口复跑。
- 只新增本报告及 `tools/diagnostics/countdown_final_handoff.py`。生产、正式 board、场景、既有测试和 generic runner 均只读；未跑完整70，也未重复完整 stage timing。

## 可重放命令与原件

```text
python -B tools/diagnostics/countdown_final_handoff.py
```

- 新 manifest：`E:/scratch/isolated-170996eeea134155ba95c0516ba96a28/manifest.json`
- manifest SHA256：`c5abc844ca309d3ad7b7e6876a9640012a9051b666966a14fe1f6e4f1b225c57`
- 原生读图结果：同根 `native-review.json`；manifest 保留自动化通过与“需单独原生看图”的分层记录，不反写旧证据。
- `delivery-readback.json` 已读回 manifest hash、952件原始归档 hash；再次逐项计算 artifact_mismatches=[]。原始归档8,413,337 bytes；生成大副本已回收。
- 外层每个实际进程180s、生成量2,000,000,000 bytes、剩余空间1,000,000,000 bytes监控；没有放大预算重试，没有导入重试。本次一次执行成功。

## 真正跨进程完成链

GUI主 PID **36732**；正式房间 worker **23164**，room=`bc2b0f4bbfe3c001263ed99a81f42636`，instance=`81ccc2917ce5432d67e3fa27cd427e1e`。房间 ready 原件与下面路径、状态、截图均在同一 evidence 根下。

1. 第一个输入是正式大厅 Data，`INPUT_TARGET Data point=(84.0,1024.5)`；再点正式 Apply。使用现有 `Viewport.push_input` 鼠标移动、按下、抬起并观察真实 pressed；不是 `pressed.emit`、OS硬件输入或多机真人验收。
2. request_id=**1** 经实际 CLI/网关/独立房间 `server_data_approval`、preparation、独立 validation 子进程。`preflight/room_validation/23164-13381339/report.json` 最终 ok=true、simulation.ok=true、budget=15、elapsed=**15.776s**；本次1个 case，status=time_budget、completed=false，不把预算耗尽说成自然对局结束或全部风险已排除。
3. worker engine log 原文：`SERVER_DATA_VALIDATION_COMPLETE {"request_id":1,"simulation_budget_seconds":15.0,"simulation_elapsed_seconds":15.776,"stage":"ready","task_complete":true,"task_pid":-1,"task_running":false}`。真实 final report 返回才 ready，不靠timer归零批准。
4. 原 ENet `server_data_status` → 新 status inbox → 正式面板：15秒→12秒；关闭面板后大厅背景12秒→9秒。ready后面板“校验完成，等待确认”，背景“后台校验完成，等待确认，请打开本局内容”，均无旧倒计时。
5. 重新点 Data 后真实风险确认窗口明确“内容有效性检查已通过”、运行时间耗尽不等于文件错误/风险已排除；正式“确认使用所选数据”可见。确认输入中心 `(976.0,736.5)`，嵌入Popup坐标按现有测试换算至根viewport，实际pressed命中。
6. 随后 request1 stage=**applied**、`_server_pending=false`；唯一采样 `check_finished` 事件带 `{request_id:1,stage:"applied"}`。画面显示“房间数据已应用。等待成员同步。”；此时大厅同步0/204，**不宣称成员下载完整完成**。
7. request_id=**2**：公开settings设置enabled=true/budget0，完整真实准备，report.ok=true、simulation.ok=true、budget0、cases=[]，全过程采样无伪秒数；画面明确完成待确认。`23164-42316948/report.json`与第二条 worker completion 原件保留。
8. request_id=**3**：公开settings恢复15，独立任务真实出现倒计时后点击正式 CancelCheck；经服务端/ENet返回 cancelled，面板/后台无旧秒数，图示“本次服务端数据批准已取消”。`23164-61590657/report.json`仍是simulation.status=running、ok=false的中间检查点，**是取消、未批准，不冒充第三份完成报告**。
9. 开关关闭的有效budget0观测器拒绝伪进度由原72项覆盖；未另外执行enabled=false的整条准备链。负向progress契约是附加检查，未替代上述独立服务端传输。

原始定位入口：`evidence/server_validation_countdown.stdout.log` 的 INPUT_TARGET/CHECK/RESULT，`evidence/countdown-observations.json`，`actual-user-output/FateDomination/countdown-36732/test-checkpoint.json`，以及对应rooms下的engine log、ready与preflight report。若后续版本失败，保留这些同类first-input/request/worker-report/UI-state原件，不使用本次通过覆盖它。

## 原生画面已验

9张 PNG 均用 `load_image_native` 实际载入模型原生查看，未使用 vision_analyze：panel-early、panel-later、lobby-background-early、lobby-background-later、completed、risk-confirmation、applied、zero-budget、cancelled。

图片根：`E:/scratch/isolated-170996eeea134155ba95c0516ba96a28/evidence/actual-user-output/FateDomination/countdown-36732/`。实际显示驱动：Vulkan 1.4.351 / Forward Mobile / NVIDIA GeForce RTX 5070 Ti，不是headless替代画面。

## 物理E与进程回收

- 原application与threading配置复制到真实主/派生探针，随机token文件与JSON逐项读回，派生probe实际exit0。
- 仅隔离配置关闭VCS自动启动、显式设置测试main、加一个只读路径/PID/token/pool的诊断autoload；原生产/测试字节不变，application user目录与pool不变。两段真实导入避免PNG import前Cursor preload，未补造缓存。
- 实际 main/CLI、房间worker、validation-worker均落盘runtime user回执，路径物理无链接、严格包含本次generated，pool20。10份真实runtime回执：主33796/GUI36732/CLI5820；房间16072、19388、4268、23164；validation28008、3576、5736。另保留生产validation自身user探针。
- 未把最小派生probe当正式worker：正式4个房间均有ready/instance/PID，GUI三个validation任务有原报告/日志/回执。
- Job Object挂起加入后恢复；所有自有job ActiveProcesses=0、日志DELETE-access释放通过后才回收唯一UUID generated树。generated_exists_after_cleanup=false。没有按进程名清扫，没有操作用户editor、身份、存档或服务器。
- validation生产任务没有单独提供每个OS.create_process child的exit-code回执；不虚称取得其各自exit0。其完成链依据真实finalreport、task_running=false与整体job清空；最小child probe、真实CLI child和外层场景exit0有独立证据。

## 本批其它迁移：明确未执行

亲读当前公开源码定义，而非依据旧报告认绿：

- `BattleHostLifecycle.request_lobby/pending/outcome_unknown/lobby_available/poll/close`已存在且board接了组件；但本冻 `LobbySession.request()`仅登记match_command/broadcast_confirm_absent，match_finished_lobby成功分支 `_publish()` 后直接return，未发accepted。故不执行已知红的 `tests/round47_host_lifecycle_runner.py --board --window`，不注入accepted、不靠lobbyview转绿。
- `SharedViewSections.render_self_power/power_lines`已存在且presenter调用；本冻board `_bind_self()`仍 `_set_text(stats,"PowerRow/Power",...)` 并画构成，没有调用共享render，网络重复段尚未迁。因此不运行 `net_v2_ui_input_parity_window_test -- window` 来冒称迁移验收。
- 上述两项等待主代理取得各唯一writer真实headless GREEN和exacthash后，下次由唯一窗口执行者统一验。主代理通知的gate“实际stale=62/62 PASS、18unit PASS”仅作安全约束背景，不拼入本轮执行数字。

## 精确源码SHA256（执行前后、原生读图后相同）

|文件|SHA256|
|---|---|
|lobby_session.gd|`89f250bc71372ea70e4a8d011e4334b931f78537aea1165d5f0a0a002d26c005`|
|server_data_status_inbox.gd|`c46b44bd9e19ccef1fe408491fb0ce0896941a2714a429509d41294e1785f9c3`|
|room_data_panel.gd|`a77ca33b165a9f9c0f60754c133f5f8140fe70b7da0410392ccbff05b33cd3af`|
|server_data_approval.gd|`5283d3f338ed01d12a760b07be12bf79a766bbc2abc0f10be803797136e48387`|
|room_validation_task.gd|`4162b76f81f22d4549fad66caa9540cc9162413d01a71cf62af8e5b6e9fe81da`|
|room_data_validation_worker.gd|`afbcbb5d94cffd60db27d74ba7a2a27ea5b0db052481ab201b35a32e9e93631b`|
|room_data_preparation.gd|`12918b213f39bd88ae4f8cfbb9e949f75359e91e7ac999d7177b95b5c2b7b16a`|
|rule_random_simulation.gd|`5375d41a0e89e1992a30211c01b91078f3e61a1f747394f3d2b4ac5cc485a228`|
|server.cfg|`351798e5909021fa472f2206bdc63c1a9271322c5800cbfdffb96e2b491301d5`|
|project.godot（原始）|`986a066adc6f0d1346d19612538780abaf2ce4d3cdfef4342db653a0b53d8c8a`|
|server_validation_countdown_test.gd|`d6a23d038dc26fdeb142b2d2294c2d262b2594fbe0fca71dcc8e123b11667c1f`|
|server_simulation_default_budget_test.gd|`73e842f9b75a9836f5324cba8cd2319aec99480992975e2f4bddd6708fdd427b`|
|新diagnostic runner|`cdd5b6ad6361b3091a1e9a6eb2e52f31b4b29e4852667d9fb13fb832b0e7316b`|
|只读generic runner|`87df79c87c2ad0f60e184c4c7dbbf057102377e716fb613ea7ac11dd0e54e5b3`|

引擎源与独占E副本均SHA256=`ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`，Godot4.7.2未变。全部785项完整source hash及转换后的freeze hash在manifest；test_scope严格只有两个现有专项的4文件，未包含无关tests，避免其它测试owner修改造成假漂移。
