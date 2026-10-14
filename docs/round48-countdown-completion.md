# Round48：默认15秒、倒计时完成/确认与取消

## 验收结论与版本边界

- **本轮执行的GUI冻结通过：72 CHECK、唯一RESULT、failures=[]、exit0、68.824s；所有实际worker日志无SCRIPT ERROR/ERROR。** 真实显示为Vulkan Mobile/NVIDIA，非headless；9张原生viewport图已逐张原生查看。
- 默认15秒的CLI契约13项/exit0，CLI内部真实子链24项通过。未改既有`validation_stage_timing_test`，完整正式68条目/204文件单次23项/exit0，场景墙钟49.785s，准备墙钟40.329s，实际模拟budget=15、elapsed=15.389s，满足180s门。
- GUI另一个冻结实际模拟budget=15、elapsed=15.581s；**不同冻结不拼成一次整链/统一候选PASS**。
- GUI运行中并行写入者更新Session和status inbox；下表保留准确前/后hash。本人6个生产文件在该次前后和交付读回均一致。GUI只证明其执行冻结，**未覆盖表中后来的Session/status inbox版本**，须由主代理串行整合。冻结本身drift=[]，不把生产树并发修改当随机业务失败。

## 症状、tight RED与修复范围

1. 原先“倒计时结束似乎不成功”未复现为worker卡死：修复前15秒冻结`3bc4c2c5254141e0a7db95e52eed19f8`已实际完成finalreport、ready、风险弹窗，点击“确认使用所选数据”后applied；51项通过。其顶层source候选false仅因并行board漂移，不能称业务失败。
2. 真实RED冻结`98366e19db7c4b39883180a62773c5a9`：60项中唯一失败“取消后正式面板及背景无旧倒计时”。服务端已返回cancelled，但面板状态仍显示上一秒。原日志/图原件保留，不改红证据。
3. 同一真实完成路径还显示待风险确认时后台前缀仍为“本局内容正在后台检查”，把已完成与待确认混在一起。修复后明确“后台校验完成，等待确认，请打开本局内容”。计时归零本身仍不能批准。
4. 只改`room_data_panel.gd`和`server_data_approval.gd`：取消清理旧文字；闲置面板接受本请求terminal回执文字；server ready明确完成等待确认；待风险确认/请求应用的背景文字不再称运行中。复用既有`_awaiting_risk_confirmation`，不新增批准状态或复制规则。另加无路径/身份载荷的单次完成诊断，记录task.complete/running/pid与模拟预算/实耗。
5. **未改验证器、assembler、四个validation源的规则/时限/批准条件**；本轮四源倒计时实现来自主代理。没有timer0自动批准，没有跳过风险确认，没有修改用户身份、存档或已部署服务器。

## 真实完成证据链（最新GUI冻结）

独占主PID27572；真正房间worker37712；真正validation PID34716、38740、7384均落盘user探针，物理E同根且pool20。

- request1：正式按钮Data→Apply，经CLI/网关/权威房间`server_data_approval`、preparation、validation子进程执行；`report.json`最终ok=true，simulation.ok=true，budget15、elapsed15.581、2个case。
- worker房间引擎日志：`SERVER_DATA_VALIDATION_COMPLETE {"request_id":1,"simulation_budget_seconds":15.0,"simulation_elapsed_seconds":15.581,"stage":"ready","task_complete":true,"task_pid":-1,"task_running":false}`。它在task检测子进程已不再运行并读到finalreport后才发出；未单独取得OS.create_process child退出码，不伪称已获该码。
- 原ENet `server_data_status`到达正式面板，stage=ready，显示“校验完成，等待确认”；原生风险报告解释预算用尽不等于文件损坏/已排除运行风险。
- 用Viewport真实鼠标移动/按下/抬起命中正式“确认使用所选数据”；实际pressed被观察，未emit代替输入；随后stage=applied、`_server_pending=false`、真实`check_finished`发出，面板显示“房间数据已应用。等待成员同步。”
- request2：通过公开settings设置enabled=true/budget0，完整实际准备完成，simulation.ok=true、budget0、cases=[]；采样全过程无伪倒计时。
- request3：公开settings恢复15，真实进入倒计时后点击正式取消；ENet终态cancelled，面板显示“本次服务端数据批准已取消”，无旧秒数。此任务保留静态检查点status=running，是**被取消、未批准**，不冒充finalreport成功。
- 独立observer负向覆盖预算错配、NaN/Inf、越界/负remaining、旧/小数/bool sequence、错误phase、半写JSON、只读当前task目录、取消清空、不改report/complete；开关关闭有效预算0的observer契约通过，未另跑enabled=false的完整准备。

## 原生截图读回

根：`E:/scratch/isolated-43d81217387241ed8aa5e9d71e253886/evidence/actual-user-output/FateDomination/countdown-27572/`

|图|实际观察|
|---|---|
|panel-early / panel-later|正式面板15秒→12秒|
|lobby-background-early / later|隐藏面板，正式大厅12秒→9秒|
|completed|后台校验完成，等待确认；无倒计时|
|risk-confirmation|内容有效性检查通过、运行风险提示、正式确认使用按钮|
|applied|房间数据已应用，等待成员同步|
|zero-budget|校验完成等待确认，无伪计时|
|cancelled|本次服务端数据批准已取消，无旧秒数|

## 当前15默认与完整204安全门

当前模板仅影响新建配置。`CLI.create_configuration`逐字节复制模板；已有61.25秒配置返回ERR_ALREADY_EXISTS且字节hash不变。实际CLI._ready将data交给manager；真实权威worker经网关/客户端读回15、显式0、显式7.5，preparation与room_options/guard逐项原样消费。并未将所有预算写死15。

**已有运行server不会因模板变化更新。现有CLI reload只允许名称/公告/relay，data变化明确拒绝；修改自己实例的实际配置后须重启自己的实例。** 本测试已验证拒绝reload时运行中预算不变；不操作用户服务器。

完整stage15：95,949,242 bytes、203不同hash；初检204个真实成功hash；组件来源注册+组装612次源重验、store0；准备store204、fetch668精确一致；重复源探针5次重验。批准根/无链接、定长读取、SHA256、JSON/引用、条目身份、assembler双遍、目标读回、隔离角色加载、静态图未截断、simulation完整预算、独立进程退出均通过。未缩短静态30s门、未seed提前结束、未关guard，pool实际20。文件初检0.104s、真实worker模拟段15.505s；各组件探针不相加冒充整链。当前stage数据详见独立timings.json。

## 运行命令、原件与异常保留

```text
python -B E:/scratch/round45-default-budget/run.py --countdown
python -B E:/scratch/round45-default-budget/run.py --countdown --integrated15
```

- 最终独立GUImanifest：`E:/scratch/isolated-43d81217387241ed8aa5e9d71e253886/manifest.json`，SHA256=`92aeb7e0da7c3a897550d710c043b09e06899fee97d4a3fd44631d43e6a5bf73`。
- stage15/default15原manifest：`E:/scratch/isolated-d87c182f27ea4558b1e5699b36c6c42b/manifest.json`，SHA256=`fcb5e128999af32c92057e5a272fe3d022f7de64362adabdcd864f1c402265cf`。这次前两套通过，随后GUI累计生成量触发2GB监控停止（exit125、byte_budget），**整轮false保留**；没有扩大预算冒绿。stage15本身仅执行一次，后续只独立跑GUI。
- 最终GUI单独执行，生成树控制在原2GB预算内；此前9baf冻结也是72项通过，但status inbox并发变化，未拿它充当前版本。
- 初次GUI夹具错误：嵌入Popup的button局部坐标直接送Popup会漏输入；现按`Window.is_embedded()`换算到root viewport，并逐次观察真实pressed。旧e06/685红日志保留，不归咎生产。
- 首次新freeze导入在PNG资源初导入前启用autoload，产生cursor preload错误；b64原manifest保留。改执行器为真实资源导入后再正式autoload导入，不换Godot、不补造缓存。本轮未遇到assembly发布失败；Round43历史发布FAILED未因此根治，也未重试该历史业务测试。
- 原generic runner和既有stage测试只读。外部runner每次自有UUID、同版本引擎拷贝；源码/执行器/关键源hash和原JSON/log/图已归档。最终delivery-readback.json读回全部artifact摘要；全Job ActiveProcesses=0、日志句柄释放，generated已不存在。集成预算停止场景当时执行器未在异常分支归档部分GUI sidecar，缺口如实保留；已修外部runner在finally归档，最终独立GUI原件完整。

## 关键源码前后hash

|文件|执行前SHA256|执行后|
|---|---|---|
|`scripts/net/ui/room_data_panel.gd`|`a77ca33b165a9f9c0f60754c133f5f8140fe70b7da0410392ccbff05b33cd3af`|一致|
|`scripts/net/server/server_data_approval.gd`|`5283d3f338ed01d12a760b07be12bf79a766bbc2abc0f10be803797136e48387`|一致|
|`scripts/net/validation/room_validation_task.gd`|`4162b76f81f22d4549fad66caa9540cc9162413d01a71cf62af8e5b6e9fe81da`|一致|
|`scripts/net/validation/room_data_validation_worker.gd`|`afbcbb5d94cffd60db27d74ba7a2a27ea5b0db052481ab201b35a32e9e93631b`|一致|
|`scripts/net/validation/room_data_preparation.gd`|`12918b213f39bd88ae4f8cfbb9e949f75359e91e7ac999d7177b95b5c2b7b16a`|一致|
|`scripts/net/validation/rule_random_simulation.gd`|`5375d41a0e89e1992a30211c01b91078f3e61a1f747394f3d2b4ac5cc485a228`|一致|
|`scripts/net/session/lobby_session.gd`|`440026e577e3ef601dcf291d15954a7d8bbeee5ab6b03991348d62c4bc411fe8`|`89f250bc71372ea70e4a8d011e4334b931f78537aea1165d5f0a0a002d26c005`|
|`scripts/net/session/server_data_status_inbox.gd`|`17509e5ae96ee294496eb89b281cb8a674d0b2157122ced530719d264f9c5814`|`c46b44bd9e19ccef1fe408491fb0ce0896941a2714a429509d41294e1785f9c3`|
|`assets/config/server.cfg`|`351798e5909021fa472f2206bdc63c1a9271322c5800cbfdffb96e2b491301d5`|一致|
|`project.godot`|`986a066adc6f0d1346d19612538780abaf2ce4d3cdfef4342db653a0b53d8c8a`|一致|
|`tests/server_simulation_default_budget_test.gd`|`73e842f9b75a9836f5324cba8cd2319aec99480992975e2f4bddd6708fdd427b`|一致|
|`tests/server_validation_countdown_test.gd`|`d6a23d038dc26fdeb142b2d2294c2d262b2594fbe0fca71dcc8e123b11667c1f`|一致|
|`tests/validation_stage_timing_test.gd`|`ba2049018699690c48b9e9aed42b74422c4c2cb9cb50b68d0bec8c1b84ede97e`|一致|

引擎仍为4.7.2.stable.official.ed1daf0bf，源D文件与E副本SHA256=ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424，未更换/修改。

本代理新增：两套新测试gd/tscn、round45/round48报告、E scratch独立证据runner；生产仅修改上述面板与approval两文件。未关闭用户editor、未提交、未清理用户身份/存档部署。

收尾复核：10个本代理独占owner全部generated不存在、全部Job退出及日志句柄释放，逐项读回在`E:/scratch/round45-default-budget/all-owned-cleanup.json`。`git diff --check`本代理两生产文件通过。新测试4文件实际存在且已执行，但仓库`.gitignore:47 /tests/`隐藏其git status；未擅改ignore或暂存，后续提交者须显式纳入这些测试。
