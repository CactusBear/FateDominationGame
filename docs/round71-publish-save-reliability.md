# Round71：当前初始冻结的有界发布/保存复验

## 结论

**四个原 suite 各执行一次；整体 FAIL，不重跑取绿。** 正式204/15秒性能样本通过；原 shutdown86 在生产 worker READY 门失败，只到7项，未到保存。其余 pending36、failure161 从同一初始源冻结继续各一次，通过。实际227 CHECK，不将原86未执行的后续断言补算通过。

历史目录发布/保存偶发原因仍 **UNKNOWN**。本轮没有重试、延时补丁、改变 DirAccess、替换引擎/DLL、修改生产、原 tests 或原 runners，也没有运行主可变仓库。

## 唯一仓库写入与执行器边界

新增：

- `tools/diagnostics/round71_publish_save_verification.py`
- 本文。

执行器先冻结真实依赖原字节及SHA，再复制工程/原引擎到物理E UUID根。复用原 `run_isolated_godot_test.py` 的路径门、挂起启动→私有Job→恢复、预算/退出/日志释放与原 analyzer。只在隔离副本去掉主场景覆盖、VCS、开发MCP及切换headless兼容渲染；正式autoload、规则、测试、15秒配置和20线程不改。

每次启动先登记label；遍历/打开运行产物前核验精确label清单、有效PID/exit、`exited=true`、整数Job active=0、`log_handles_released=true`。没有后台内容监视器；原执行器的预算检查仅metadata枚举/stat。性能fixture原有16ms观察延时未修改，执行器没有新增产品延时。

最初执行器遇到首红停止并消费generated；为完成另外两套的一次执行，新增显式 `--continue-unrun`。它只读取初始 `evidence/frozen-source`，比对完整source/frozen字典，排除所有已尝试suite，使用独占claim拒绝重复续跑；**没有重跑性能套或失败86套**。两个scope是同一输入冻结，不冒称同一运行进程。初始、续跑及最终离线验证器版本分别留hash；后续执行器增强不改写原日志或manifest。

## 实际命令与原件

在仓库根运行：

```text
python -B tools/diagnostics/round71_publish_save_verification.py --self-test
python -B tools/diagnostics/round71_publish_save_verification.py --execute
python -B tools/diagnostics/round71_publish_save_verification.py --execute --continue-unrun E:/scratch/isolated-b3cc1bfe631149fa94f6a7c789f25491/manifest.json
python -B tools/diagnostics/round71_publish_save_verification.py --verify E:/scratch/isolated-b3cc1bfe631149fa94f6a7c789f25491/manifest.json E:/scratch/isolated-ed9fd487c32d490087e239301371f838/manifest.json
```

两次业务入口均exit1：第一次因真实READY首红；续跑虽两套通过，仍保留整体首红。离线验证exit0只表示归档完整性，不表示业务通过。Python自测9个不安全生命周期/schema输入均拒绝。

|scope|内容|manifest SHA256|
|---|---|---|
|`E:/scratch/isolated-b3cc1bfe631149fa94f6a7c789f25491`|初始probe/import、正式性能、原86首红|`4b76b2d85bef24ec2443f3ae835ca2e0b7117976a92bbba25108dff52a19d4cd`|
|`E:/scratch/isolated-ed9fd487c32d490087e239301371f838`|同冻结probe/import、原36/161|`3fe0e659cee9c97850805779026548d1aa04a193098d772302beb8fc48efb14f`|

各根 `manifest.json` 保留argv/PID/exit/Job、真实RESULT、CHECK统计、报告原件索引、日志哈希、漂移与缺口。初始根 `offline-verification.json` 为终末独立读回，不覆写原manifest。`remaining-claim.json` 绑定初始manifest与唯一未执行集合。

1122项初始依赖两根逐文件hash完全相同；运行冻结字典也完全相同：

- source集合 SHA：`a60d68c1a6d6c75af003869c09501259931a3c13a9fef886d17ecdcfdb931c2b`
- frozen集合 SHA：`620fffb999fd7f4cc06724fe5d86e9de9074197e8594f123155e8c26c11bbaea`
- 原引擎：`ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`
- 原正式DLL：`92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`
- 初始 `lobby_session.gd`：`9541688289a80f59677a396e24ac7e885eb6552558a3edf0ab16baacf72b9e3b`

## 正确性与walltime分别列门

|原场景|实际CHECK|exit|业务结论|实际进程树wall秒 / 外层看门狗|
|---|---:|---:|---|---|
|`validation_stage_timing_test`|23|0|PASS，原正式204＋配置15秒|58.741 / 600|
|`server_shutdown_close_handoff_test`|7|1|FAIL：`生产 worker READY `|44.873 / 180|
|`server_shutdown_close_handoff_pending_test`|36|0|PASS，保留原pending/retired门|18.304 / 180|
|`net_server_shutdown_failure_test`|161|0|PASS，原成功/拒绝/绑定/退出门|40.331 / 180|

四套总外层预算为原600＋3×180；没有扩大为99套或更换性能场景。所有过程 `budget_failure=null`。86首红是原fixture的READY等待门失败，不是180秒外层超时，更不是已经观察到保存失败。

正式性能报告来自原catalog→plan→cache/store→assembler→RoomDataPreparation→真实child loader/simulation，不用关闭simulation的loader204替代：

- 原manifest原字节读回204项；与父内存接受的report完全相等。
- `enabled=true / budget_seconds=15 / elapsed_seconds=15.649 / ok=true / errors=[]`。
- 原报告保留“随机模拟时间已用尽，当前对局未结束”风险警告；不称已完成一局或无风险批准。
- 静态checkpoint从child launch为12.401257秒，原静态门30秒。
- launch到最终报告28.891548秒；原Task时限30＋15=45秒。
- 包含启动前准备的整条preparation为44.659567秒，不与child45秒deadline直接比较。初始manifest的 `original_task_total_seconds` 实际包含准备，本字段命名歧义已在终末offline `walltime_correction` 分开，不改原manifest。
- worker原分段：initial validation 108931µs、assembly 4943068µs、load 947582µs、simulation 15966323µs；组件分拆不相加冒充同一次worker。
- 原report SHA：`f013ba6d0aa6f5166f8f9930d5e809dca045f52dc93a30267918ae2380e4819c`；原manifest SHA：`98469b47c4526f17a50633b3279567d17339fa61ed3895954e7ba9b3de58d568`。

## 首次失败与实际错误边界

原86 stdout完整保留于初始根 `evidence/server_shutdown_close_handoff_test.stdout.log`：创建生产worker为true，READY为false，最后原manager清理断言true；唯一RESULT为7项/一失败/exit1。其worker engine日志只有引擎banner，没有ERROR，也没有保存诊断或close回执。

本次已明确失败阶段 **worker READY**；尚未到保存/关闭交接。没有捕获该worker的底层系统失败返回，故 **native_error=null / 原因unknown**；不能猜error5、端口占用、杀毒、原子替换或观察句柄故障。原manager清理与Job0不能补成自然关闭/保存成功证明。本轮没有重启该worker或重跑86套。

## 保存证明、退出证明、Job0三层

1. **保存证明层**：pending套2份、failure套6份实际control响应在Job0后原字节归档；8份均核对request文件名及room/PID/instance/mode与同目录原ready报告。6份成功只证明空大厅 `saved=false / room_state_saved=true / closing=true`；2份为真实拒绝。pending中迟到历史回执仍不冒当前closed proof，原断言继续验证这一拒绝。
2. **退出层**：原36/161断言验证真实原生持有句柄running→EXITED→release，保存回执单独不能代替退出。执行器不虚构未直接取得的各child自然exit_code。86首红没有走成功保存→退出链。
3. **Job0层**：两根共10条监督进程记录均明确退出、active_owned_processes=0、日志释放；这是本次树收尾证据，不是房间saved proof。

failure套实际保存拒绝事件在PID23684的原worker.log：

```json
{"version":1,"stage":"write","native_stage":null,"native_error":null,"godot_error":12,"pid":23684}
```

该PID与同实例拒绝control响应匹配。12来自本次原FileAccess.open失败后的Godot Error；不是WinAPI errno。此次临时路径目录冲突是原fixture的受控拒绝，不是历史偶发保存失败归因。成功路径没有伪造失败事件；未捕获atomic native返回仍为空。

## 安全缺口与消费核验

- 不设置 `FATE_R60_ARTIFACT_ROOT`：已亲读旧86 fixture，其可选诊断分支会完整读取recovery并解码bindings，不符合本次授权。没有改旧fixture授权或把它当safeAPI。原fixture固有业务恢复/摘要断言保持不变，runner不额外读取/hash/复制任何recovery/temp payload或key/ticket。
- 现有原生发布capture依赖其它fixture的显式gate和固定formal/preparation路径标签，还会暂停成功路径；不覆盖原stage_timing场景。本轮不扩授权、不改原工具、不装入该观察器。**缺失败同线程WinAPI返回和现场句柄证据仍是缺口**，没有用后续GetLastError猜原系统错误。
- 原套并未为每个瞬态失败提供安全独立handoff，86又在READY前失败；所以 `evidence_complete=false`，不宣称已完成所有保存阶段的动态闭环。实时新增产物只有fixture自身原诊断日志；归档统一在Job0之后。
- 全部40份父/子/import/probe原日志重新离线扫描，ERROR集合为空；这不冲抵86的业务CHECK false。41项运行artifact原长度/SHA、两份1122项初始源码逐项读回，无坏hash；两份frozen_drift均空。
- 只有完成Job0/log-release及归档读回后才消费精确自有generated；两根generated现均不存在。未碰用户28100、其它会话树或旧失败证据。
- 可变主仓库期间发生其它拥有者改动：初始结尾2项源码漂移，续跑结尾8项（其中包括本执行器增强）；完整清单留manifest。续跑实际始终使用初始原字节。终末另核对 `_persist_recovery_state` 原函数仍与初始相同，函数SHA `40ab1c32d8cdcb5380dff322e18794a2aab67c10ac85fd256b202bfd63e34aeb`。**不据此宣称当前已经再次变化的整仓通过。**

本轮交付是有首红的当前初始freeze样本和真实证据，不是根治、发行包、窗口、多机或全部保存出口验收。
