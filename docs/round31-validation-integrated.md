# Round31 validation：13 场景独立整合

**13/13 套件真实通过，1903 条 CHECK；整体冻结仍 passed=false，命令 exit=1。**
import 有两条真实引擎错误，未忽略，不能宣布 freeze 全 PASS；也不拼旧39套。

## 本轮证据
`E:/scratch/isolated-030dff2d8abf42259232e5b9bb874162/manifest.json`
manifest SHA256：`9791bc90efb7a0f3cb2f3ea44b406334d5844e8806cb70da2cf68f2f7e155b52`
明确选择的13套同一新快照，单套180s，只有 headless，没有窗口。每套命令、PID、exit、source/frozen 前后hash、并行漂移均保留。最终源码、每套源码和冻结漂移全部为空。
真实主/child user://探针、Windows Job自有所有权已核验；各进程 active_owned_processes=0、日志句柄释放；generated 已回收并读回不存在，D源引擎hash未变。

|套件|exit|真实CHECK|判定|
|---|---:|---:|---|
|net_validation_task_test|0|31|PASS|
|net_validation_simulation_test|0|35|PASS|
|net_validation_hard_timeout_test|0|37|PASS|
|net_parallel_validation_feedback_test|0|9|PASS|
|room_data_preparation_consumer_test|0|50|PASS|
|room_data_preparation_dependencies_test|0|34|PASS|
|lobby_content_environment_restore_test|0|1544|PASS|
|net_data_sync_test|0|14|PASS|
|net_blob_test|0|42|PASS|
|net_blob_authorization_test|0|58|PASS|
|net_blob_send_authorization_test|0|14|PASS|
|net_blob_concurrent_test|0|20|PASS|
|net_worker_startup_contract_test|0|15|PASS|

## 引擎错误保持拒绝
- `ERROR: Cannot get class 'GitPlugin'.`
- `ERROR: Received a nullptr VCS extension instance during construction.`
import exit0 不覆盖错误；上表专项 PASS 不等于完整冻结 PASS。

## 聚合器 RED/GREEN 与历史只读重解析
- 先加入同文案两次调用应通过、计数仍为2的测试；旧 duplicate_check 规则真实 exit1（AssertionError）。去除标签去重后 parser-only exit0。
- false、错计数、引擎错误、重复 stdout/stderr RESULT、重复字段、非法布尔/计数和 failed>0 负向检查保持拒绝。
- 额外真实RED重放/GREEN记录：`E:/scratch/round31-reparse-5683f2ce6075419c973c357c5b97d5ab/parser-red-green.json`。
- 旧13套 manifest及原始日志按严格UTF-8重解析：`E:/scratch/round31-reparse-5683f2ce6075419c973c357c5b97d5ab/reparsed.json`，8/13严格通过，命令exit1；旧纯duplicate_check误判纠正，不改历史日志/manifest。全部输入前后字节hash相等。
- 旧13套的5项功能/timeout失败仍保留；旧最终漂移为 lobby_session.gd、v2_view_presenter.gd，不用本轮结果覆盖旧判定。

## 两个专项根因与边界
### hard-timeout
旧日志在 explicit chosen data assembly 即fail-fast退出，未保留assembler.error，因此历史该次组装失败根因仍未确认，不能声称已修复生产。assembler/cache/基类测试hash与旧冻结一致；本轮诊断及后续重复专项组装均成功。新增测试失败诊断在自有安全目录重放并输出assembler/cache错误，不放宽路径安全门。
随后真实专项暴露8秒静态准备截止早于report.json产生；该记录保留为RED。测试改为基类同样声明120秒静态准备上限；只有真实ok且 random_simulation.status=running 的检查点出现后，暂停实际自有PID，并将本测试任务截止收紧为1秒。真实父任务终止已暂停子进程、hard_timeout未通过、警告汇入风险报告；同一真实检查点作为提前退出负向读取仍拒绝。这个测试相位分离不是生产功能修复或20线程性能达标声明。
### preparation consumer
旧真实子进程入房失败首先明确报“批准数据根必须由本机部署入口显式提供”。仅测试补显式批准根/独占存储/上传路径和原生所有权fail-fast前置，去掉继承的120秒等待扩长。第二次诊断明确“身份认证配置或请求无效”，网关rooms为空；根因是合法RSA资料虽存在，但网关身份登记库未配置。显式在独占根 open身份库后真实child ready、入房、上传、准备/取消/旧提交拒绝、新版本应用与下载字节对照全部通过（50 checks）。
保留服务端自报房主拒绝、目录版本拒绝、取消后的旧确认拒绝、旧请求号拒绝，以及面板取消只杀自有校验进程且独立兄弟任务存活等真实正负断言。只在本消费者子夹具保留原协议流程；Session/manager/authority/validator与generic runner均未由本子代理修改。

## 每次尝试保留
- `E:/scratch/isolated-536016822ba34dd394de09e79d2441ba/manifest.json`：hard-timeout 静态截止RED。
- `E:/scratch/isolated-f62db9f7bb5c413b9c5b62a7e5a31c04/manifest.json`：hard-timeout 37 PASS，consumer身份前置RED。
- `E:/scratch/isolated-83809cbef8a548a1a106844e412b7352/manifest.json`：consumer身份根因诊断RED。
- `E:/scratch/isolated-ac27fce475c14b35b5cb0ddcf51b5bfe/manifest.json`：consumer 50 PASS，仍因import错误整体false。
这些独立运行的源码/冻结前后hash、日志hash与漂移均留在各自manifest，不充抵本轮13套。四次源码/冻结漂移均空；生成副本均已回收。

## 关键冻结hash（SHA256）
- `tests/net_validation_hard_timeout_test.gd`：`d38ba74c74f28e9a14b3a99a8f8235c78db336f0eed84f443938e2cd30ee7f9e`
- `tests/room_data_preparation_consumer_test.gd`：`bfa2a37c311cecf797454f1a005aa3d519025b097506a16618de9b25c7b56475`
- `scripts/net/validation/room_data_validator.gd`：`95f0c09f1eac7ab6540f36841b0b999c3cce88d863486d98f54a6e96b9b9d49f`
validator `file_worker_count:int = 20`保留；两份validation生产文件本子代理未修改。
修改文件仅tools/tests/test_round29_integrated_evidence.py、tests/net_validation_hard_timeout_test.gd、tests/room_data_preparation_consumer_test.gd；新增本报告。测试/tools可能被gitignore，未add/提交。
尚未解决：旧历史单次组装失败无错误对象证据，import GitPlugin两条错误；没有窗口验证。

## 顶层独立汇总复核（不改旧manifest）
全局拒绝唯一原因为 `current_import_engine_errors`，不是historical混入。project.godot第55–56行声明GitPlugin自动启动；两条本次import错误保留为真实RED，不按expected error忽略。
顶层新增有效负向单测先RED：原汇总错误接受 import exit1但errors为空；修正为同时拒绝import非零/缺失、明确输出原因，且历史RED不污染当前。parser-only修后exit0。
真实只读重汇总命令：`python -B tools/tests/test_round29_integrated_evidence.py --summarize-from E:/scratch/isolated-030dff2d8abf42259232e5b9bb874162/manifest.json`。
修后真实输出：`passed=false; reasons=[current_import_engine_errors]; current_suite_count=13; current_suite_pass_count=13; historical_manifest_unchanged=true`，exit1。
新证据：`E:/scratch/round31-summary-5c2ba3a9de2e401aab581a083c0e59fe/summary.json`。未改历史证据冒通过，未改生产project.godot禁用插件。
