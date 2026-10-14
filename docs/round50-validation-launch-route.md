# Round50：validation task 最后一条场景反向依赖退休

## 已修改并验证

- 唯一生产写入：`scripts/net/validation/room_validation_task.gd`。`start()` 原引擎参数拆为 `engine_arguments`，原 data/manifest/report 路径拆为 `role_arguments`，全部保留原 `globalize_path` 调用、顺序和值；可选 simulation.json 仅追加到 payload 末尾。
- 使用现 `server_bootstrap.gd::role_scene_arguments("--room-data-validation-worker", engine_arguments, role_arguments)`。builder 已消费 `process_arguments`；task 不再二次消费。空 argv 设置明确任务错误、返回 false，不调用 create_process；非空直接传给原 executable 的 create_process。
- 未新增接口、预算默认值或规则。progress.json、单调 sequence/remaining 观测、deadline、report/complete 批准、受控 hard_timeout 与提前退出的区别、kill 失败保持 running/PID、cancel 和析构都未修改。与有效 RED 原件比较，`_create_directory()` 起直至文件尾逐字节一致，证据 `evidence/owned-task.patch`。
- worker、simulation、preparation、bootstrap、manager、approval、panel、gate 均只读；未提交或暂存。当前 server.cfg SHA256 仍 `351798e5909021fa472f2206bdc63c1a9271322c5800cbfdffb96e2b491301d5`，声明 enabled=true、budget=15.0，未在 task 写死15。

## TDD 与真实冻结

实际命令（仓库根）：

```text
python -B tests/round50_validation_launch_route_runner.py red
python -B tests/round50_validation_launch_route_runner.py green
python -B tests/round50_validation_launch_route_runner.py core-green
```

- 有效旧场景依赖 RED：`E:/scratch/isolated-2f3c2d2766c34c118721f9d3f9703289/manifest.json`。新 consumer 16 checks / exit1，五项明确失败（旧场景硬引用、未消费 builder、双处理、未拒绝空 argv、模拟配置未拆为 payload）；没有 parser/engine error。同时旧命令契约22 / exit0 / failures=[]。不是用解析失败冒充业务 RED。
- **最终 core-green 同冻结：`E:/scratch/isolated-1c0a435d39d94eceaec88671d197c573/manifest.json`，passed=true、exit0、6套162 checks、failures=[]；源/冻结漂移均空，交付再读回源漂移也空。** manifest SHA256 `6bbf812a7ebfd121ead4b0cfe9c1c32b991511c86479cc969279fabadafc3657`。

|实际套件|checks|exit|场景+observer墙钟秒|
|---|---:|---:|---:|
|round50_validation_launch_route|16|0|4.552|
|round47_worker_launch_route|22|0|5.883|
|validation_countdown_contract|21|0|5.701|
|net_validation_task|31|0|47.665|
|net_validation_simulation|35|0|66.552|
|net_validation_hard_timeout|37|0|37.199|

用户所指当前21项的实际套名是 `validation_countdown_contract_test`；没有把旧 `validation_checkpoint_reader_test` 的10项改名为21。unknown role、engine 第二 `--` 和第二 `--scene` 拒绝在本冻结真实命令契约仍通过。未执行新发行PCK或非editor导出包，不冒称出口发行验收。

## E盘、真实子进程与参数证据

- 保持当前官方 Godot `4.7.2.stable.official.ed1daf0bf`。从 D 原引擎复制本轮独占物理 E 主可执行文件，源/副本 SHA256 均 `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`；源未改。不换引擎或借旧缓存。
- 每进程180秒、生成树监控2.5GB、剩余空间门1GB；APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR 仅对子进程环境指向本轮 E 树，未改全局环境。
- probe 使用同 application user-dir 配置与 threading/pool20：真正 main PID26896 / create_process child PID13772，token `a33adabce73c479795fdf74caa1827cb`，user://写入与JSON读回真实匹配，child真实退出码0，祖先无reparse且物理E。
- 正式 validation user 回执另行实取：PID22856、21472（父37404）；PID21524、32064（父31816）；PID37172、6404（父14016）。这些不是最小probe冒充正式worker。
- `evidence/actual-validation-launches.json` 与 `wmi-observations.json` 保留这6个实际 Win32_Process PID/ParentProcessId/ExecutablePath/CommandLine，用 Windows CommandLineToArgvW 解析；正式父PID均对应本轮Job登记的套件。无模拟和有模拟均覆盖，完整engine argv匹配，唯一 `--`，manifest/report/simulation文件名和位置匹配且落在自有E树。有模拟时最后一个参数仍是分界后的 simulation.json。
- `evidence/actual-validation-output/<pid>/` 保存运行中实际 manifest/options/report/progress/engine.log 采样原件；它们是观测时快照，不把中间 running 检查点当最终批准报告。最终批准、真实对局模拟与硬超时由上述31/35/37真实断言判断。正式 create_process 的OS退出码未另取，不能把probe子进程exit0套用到它；task按原进程已退出+实际报告/日志消费。
- 最终导入两阶段均exit0无ERROR；全部套件无SCRIPT ERROR/SHADER ERROR/ERROR，唯一合法RESULT且checks精确。所有9个自有Job记录 ActiveProcesses=0、log_handles_released=true，再归档/回收 generated。仅回收本轮独占UUID树，从未按名称清扫用户Godot。

## 异常保留与默认15边界

以下旧失败都保留真实manifest/log，未拼接成最终 core-green 的成功：

1. `isolated-a20515acb5c34e7dac292cf53868e7fb`：首冷导入因隔离resource-config仍指向未包含的 opening_background 场景失败。只改新runner的隔离副本main场景声明/两阶段资源导入，不改项目，不补造缓存。
2. `isolated-377918ef61ed4537b9a6125c5e7bf85a`：缺批准的 localappdata/hermes/cache/scratch 祖先，三个真实夹具首项拒绝。按现 RecoveryPathSafety 授权根必须存在的契约建立自有批准祖先，未放宽生产路径检查。这次可选默认15契约13项及其子链通过，但它不是最终验证链的同冻结通过。
3. `isolated-cacd3a93d00640a9be03d4c13e5d7c42`：只读 console owner 并发版本在377行有未声明request；task31/simulation35/hardtimeout37虽exit0、failures=[]仍因SCRIPT ERROR正确判红。只读owner随后已改正，最终新冻结无此错误。同时新runner初版漏掉实际 globalize_path 的 project 尾斜线，WMI精确比对也判红；修了新runner预期字节，不改生产argv。
4. `isolated-65d35784905e4dfe92141d430999caa2`：核心6套同冻结均真实通过，**可选 server_simulation_default_budget 真实子链在首次权威worker→网关→客户端settings断言失败，父13项exit1，本次完整green总体false**。worker日志只有engine header，无明确运行错误，room data部分实际落盘；本轮没有足够证据定位失败原因，不归因task argv，也不越权改只读消费者、启动预算或测试断言。并发board/session漂移单独记录。最后core-green明确只验所需6套，不用它覆盖/抹掉这个可选失败。

上述6个本代理owner的generated全部已经按各自Job退出证明回收，`delivery-readback.json` 列出 remaining=[]。当前默认15模板及已有显式配置不覆盖在原实际默认契约中可观察；**本轮不能声称最新源码的完整默认CLI建房子链复验成功**，留给main整合。没有重跑GUI72，也没有重跑204完整默认15性能链。

## 精确gate退休交接（main唯一写入）

本轮实际 `python -B tools/check_layer_deps.py`：exit1；findings50、allowlist62、NEW0、STALE12，实际finding layer4/private46。本人不改gate。

只删下列最后一条layer许可（当前工具171行，历史provenance50）：

```python
ExceptionSite("layer", 'scripts/net/validation/room_validation_task.gd', 'res://assets/scenes/main_menu/room_data_validation_worker.tscn', 'var arguments := PackedStringArray(["--headless", "--audio-driver", "Dummy", "--fixed-fps", "60", "--path", ProjectSettings.globalize_path("res://"), "--log-file", ProjectSettings.globalize_path(directory.path_join("engine.log")), "--scene", "res://assets/scenes/main_menu/room_data_validation_worker.tscn", "--", "--room-data-validation-worker", ProjectSettings.globalize_path(data_directory), ProjectSettings.globalize_path(directory.path_join("manifest.json")), ProjectSettings.globalize_path(directory.path_join("report.json"))])', 50),
```

已用原scan/evaluate在内存模拟精确退休，**许可集合变为Bootstrap4个role声明 + private57 = 61**，NEW仍0。当前另有11个private STALE来自main/其他测试迁移，模拟只删task项后仍STALE11，因此不能把“集合61”宣称gate全绿。全部精确code多重集合在 `evidence/gate-readback.json`；原工具本轮读回 SHA256 `61b3e0caa03c4beabda590270adf851c39f2100c96358bd4f28652d27c83f0f3`。四个Bootstrap声明保留，不扩许可。

## GUI冻结变化：不是当前GUI已验

Round48 GUI72只证明其独立owner `isolated-43d81217387241ed8aa5e9d71e253886` 的执行冻结；当前owner不同。本轮从其实际manifest critical_sources读回，与当前源码比较：

|文件|GUI冻结SHA256|当前SHA256|
|---|---|---|
|room_validation_task.gd|4162b76f81f22d4549fad66caa9540cc9162413d01a71cf62af8e5b6e9fe81da|a96ac36c35bda7310dc85512d0888f00c778dddd639f93567f05671d2c80818b|
|lobby_session.gd|440026e577e3ef601dcf291d15954a7d8bbeee5ab6b03991348d62c4bc411fe8|11b0f98a6cf68a8b441680ba2d24741be39c9a7c470aa6569e9fbe711a0dbf56|
|server_data_status_inbox.gd|17509e5ae96ee294496eb89b281cb8a674d0b2157122ced530719d264f9c5814|c46b44bd9e19ccef1fe408491fb0ce0896941a2714a429509d41294e1785f9c3|

GUI72与当前headless162不相加冒充一个候选整链。当前worker/preparation/simulation、panel/approval/config/project的历史GUI critical hashes未变；**本轮仍只交headless验证，不叫当前GUI已验**。

## 本代理文件

- 修改：`scripts/net/validation/room_validation_task.gd`。
- 新增：`tests/round50_validation_launch_route_test.gd/.tscn`、`tests/round50_validation_launch_route_runner.py`、本文。
- 新tests受仓库 `/tests/` ignore，实际存在且已执行；未改变ignore或暂存。`git diff --check -- scripts/net/validation/room_validation_task.gd` exit0。
