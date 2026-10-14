# Round36 validation feedback

## 结论与范围

- **两套自有 feedback 修复并真实 GREEN**：background 25 checks；I/O 23 checks；均唯一规范 RESULT、failures=[]、exit 0，无 SCRIPT ERROR/ERROR。
- 两套最终源码的前置错误注入均 **checks=1、failures 长度=1、exit 1**，唯一 RESULT、无 SCRIPT ERROR/ERROR，快速收尾。
- 当前相关七套专项为 **6 通过 / 1 生产红项**；通过专项共 131 checks。消费者专项为 39 checks / 1 failure，不能称全部专项已绿，也不借 round33 的 50-check 历史记录抵充。
- 仅修改 `tests/net_background_validation_feedback_test.gd` 与 `tests/net_validation_io_feedback_test.gd`；对应 `.tscn` 不变。production、性能 tests、validation worker、通用 runner 均未修改；未 add/commit。这些测试被 `.gitignore:47 /tests/` 忽略，不能用空 `git diff` 冒充无改动；归档中保留 RED 源码、最终源码及真实 unified diff。

报告证据根：
`reports/refactoring/round36-validation-feedback-3b2add3d74164efc9650e2db6a313222/`

完整命令、每次退出码、源码摘要、自有 PID/退出/句柄释放回执见 `manifest.json`；原始 stdout/stderr、导入和主/child 探针、worker 原始诊断见 `evidence/`。

## 根因与测试实现

### Background

旧测试给已解耦 preparation 赋 `session`，随后直接伪造 `preparing=true`。真实 RED 为 Invalid assignment of property or key 'session'，没有 RESULT，180 秒看门狗由自有 Job 收尾（实际进程总耗时含释放约 182.201 秒，exit 125）。

新测试沿公开组合入口 `panel.configure → panel._apply → session.create_data_preparation`，不填空 session、不伪造准备完成、不绕过内容身份门：

1. 已存在物理 E 独占根及真实 user 根先过正式无链接安全门；前置失败立即 finish，不继续索引。
2. 正式 `selection_modes.json` 中选人声明唯一；真实 ENet host 与安全端口探针统一绑定 `127.0.0.1`。最初默认 `*` 监听真实失败且已被保留；回环探测不等同 wildcard ENet 可绑定，没有忽略引擎错误。
3. 面板扫描完整正式条目，以原有每帧预算异步准备并真实发布字节。Close 按钮及 popup_hide 信号不取消，隐藏后台状态继续有效。
4. 隐藏面板经真实独立 validation 子进程校验，再走正式批准/采用门；批准清单、room_files、data_revision/data_ready 真实回读非空。
5. 第二轮真的启动独立校验 PID，CancelCheck 按钮仅取消其真实任务；PID 不存活、process_id=-1、别名恢复空闲且批准 revision 不增加。
6. 以正式 surveil 的原始字节与哈希，仅改变上报 name/key；计划可启动，真实内容身份检查拒绝，不开启校验子进程、不批准新版本。
7. 构造注入能力的准备器，发布回调仍调用真实 session.publish_blob；发布中真实 cancel。旧 generation 不能推进已取消事务，也不能推进随后新事务；当前 generation 仍正常发布相同正式字节。主 JSON 的唯一性先检查，再索引，避免前置红项级联越界。

这属于 headless 场景/信号处理器与真实网络/进程验证，**不是窗口点击验收**。

### I/O

原输出 `RESULT validation_io failures=0 []` 缺正整数 checks 且有非法尾部；RED 的实际 exit 0 不算通过。

新测试复用 match_journal_test 的实际 check 计数与 finish，唯一输出 `RESULT checks=23 failures=[]`。目录改为明确批准的物理 E scratch 子树；真实夹具写入失败先记录 false check、快速统一回收并 finish，不再继续解引用无效夹具。

原有 no path reopen 结构预算、有效操作、错 hash/size、缺文件、未知操作、JSON 格式/深度、重复路径、遍历、非 JSON、同长度修改重新哈希断言全部保留。no path reopen 是源码结构预算，**不是实际系统调用计数测量**；不宣称 OS I/O 次数被此断言直接统计。原并发/非主线程、错误顺序等价和性能专项未修改，未新增/调整性能阈值。

## 真实 RED / GREEN / 故障注入

|证据 label|exit|checks|结果 / 实际秒数|
|---|---:|---:|---|
|red_io|0|无合法 RESULT|严格解析 RED，3.117s|
|red_background|125|无 RESULT|旧 session SCRIPT ERROR，180s 看门狗|
|green_background|1|5|ENet wildcard 前置真实拒绝，3.047s，已规范收尾|
|green_background_loopback|0|25|GREEN，22.417s|
|green_io_final|0|23|GREEN，3.837s|
|fail1_background_final|1|1|恰好 1 failure，唯一 RESULT、无脚本/引擎错误，6.208s|
|fail1_io_final|1|1|恰好 1 failure，唯一 RESULT、无脚本/引擎错误，3.868s|

最终测试字节：
- background SHA256：`14eebd6feb646e21b2bfc013c2de2d5f6464f331354020310aab9d295af4d47d`
- I/O SHA256：`6890cd8372160f06198a9057fc60f5370383ccaef2ebcae9abe2e4f467cb6751`

命令形态（全部实际 argv 在 manifest，不替换成假日志）：

```text
python -B E:/scratch/round36-feedback-run.py setup
python -B E:/scratch/round36-feedback-run.py run red_io net_validation_io_feedback_test
python -B E:/scratch/round36-feedback-run.py run red_background net_background_validation_feedback_test
python -B E:/scratch/round36-feedback-run.py sync
python -B E:/scratch/round36-feedback-run.py run green_background_loopback net_background_validation_feedback_test
python -B E:/scratch/round36-feedback-run.py run green_io_final net_validation_io_feedback_test
python -B E:/scratch/round36-feedback-run.py run fail1_background_final net_background_validation_feedback_test --inject-failure
python -B E:/scratch/round36-feedback-run.py run fail1_io_final net_validation_io_feedback_test --inject-failure
```

内部实际 Godot 命令统一为独占 E 引擎 `--headless --fixed-fps 60 --path <generated/project> --scene res://tests/<suite>.tscn -- <generated/fixtures>`，错误注入附 `--inject-failure`。每套独立 180 秒看门狗。

## 相关专项（只读原脚本）

|suite|exit|checks|failures|
|---|---:|---:|---|
|net_background_validation_feedback_test|0|25|[]|
|net_validation_io_feedback_test|0|23|[]|
|net_parallel_validation_feedback_test|0|9|[]|
|net_validation_io_measure_test|0|9|[]|
|room_data_preparation_dependencies_test|0|34|[]|
|net_validation_task_test|0|31|[]|
|room_data_preparation_consumer_test|1|39|["权威子进程自行下载并完成实际隔离加载"]|

并发专项保留并通过：默认 file_worker_count=20、真实共享池=20、文件任务不在调用线程、并/串行拒绝相同坏文件且错误顺序一致、无效预算拒绝。

I/O 测量原样跑 205 文件、三次交替 1/4/8 workers，无新增阈值；原始 usec 数据为：
- workers=1：367427、431552、376694；
- workers=4：131116、139634、115515；
- workers=8：96043、101295、92091。

以上仅初始文件校验、暖缓存且 OS cache 未控制，不证明端到端性能已改善或未回退；完整性能门仍由性能 owner 决定。

## 给性能 / validation owner 的生产根因证据

消费者测试的面板采用/真实取消/独立 sibling PID 不受影响、factory 注入/重复配置/信号解绑段全部通过。随后真实服务端 room worker 完成连接、catalog、上传条目与旧目录拒绝；在请求新数据准备时变为：

```text
stage=error request_id=1 catalog_revision=2 text="无法发布完整会话目录"
```

真实正式 validation worker 的 engine.log 给出：

```json
{"destination_directory_exists":false,"destination_file_exists":false,"destination_length":190,"files":206,"index":206,"phase":"write","reason":"无法发布完整会话目录","rename_attempted":true,"rename_error":1,"staging_exists":true,"staging_length":207}
```

该红项不是旧 prep.session，也不是未提供批准根：已实际写完 206 文件，最终 staging→destination 的目录 rename 返回 1。建议 owner 检查 Windows 目录发布/长路径或实际 rename 条件；路径长度只是可检验线索，**未在本任务中确认唯一根因**，不能调阈值或缩短规则预算掩盖。

归档原始正式 worker 日志：
`evidence/worker-artifacts/fixtures/consumers-35508-5163404/rooms/af747bcd9377e5378e2447e7dac8916c/preflight/room_validation/3156-18360440/engine.log`

同时保留正式 report.json、房间 engine log，以及只读冻结 preparation/worker/task/validator/assembler/catalog/panel 源码。

**worker 本次冻结 SHA256**：`34ebd82f8292cdd8ff61f9b9997a031127d40bd27bd48e29c9794aa47158d294`。运行期间另一 owner 修改源树 `scripts/net/validation/room_data_validation_worker.gd`；这些改动未回灌本副本。本证据只代表上述生产冻结，不宣称最新源树整链已通过。除两套授权测试迁移及副本 editor VCS 两字段变换，副本生产不变。

## 隔离、回收与交付复核

- 主 Godot PID 4196、真实 child PID 27012，随机 token `3b2add3d74164efc9650e2db6a313222`；两者 user 根均实读 `E:/scratch/isolated-3b2add3d74164efc9650e2db6a313222/generated/appdata/FateDomination`，祖先无 reparse，physical E；child 退出 0；实际 worker_pool_max_threads=20。
- 实际 import exit 0、ERROR=[]。仅副本 `[editor]` 两项 VCS 自动加载声明最小转换，threading 与规则配置不调。
- Windows Job Object 管理全部自有 PID，不按程序名终止，不触碰其他代理任务；所有回执 exited=true、active_owned_processes=0、log_handles_released=true。
- 先保留原始日志、失败/最终测试源码、diff、正式 worker 原始报告和摘要，再消费 UUID 自有 generated 树。最终 `cleanup=generated_removed`、生成树不存在、顶层 archive 日志摘要读回一致；9 个 worker artifacts 复制时逐项哈希一致。
- 隔离范围例外如实记录：旧 I/O RED 为复现原症状，仍短暂使用原硬编码目录；旧脚本自己删除本次 `3576-` 叶子夹具，收尾精确检查该 PID 前缀不存在。没有顺带删除未知父目录或别人的历史夹具；新版本所有 I/O 夹具已迁入 generated。
- `git diff --check -- <两自有测试>` exit 0；另用真实 RED 归档与最终文件生成 unified diff、逐行检查无尾空格。全仓 git diff --check 含他人改动返回 2，不拿它代替自有文件检查。
- 已将“端口探针与真实监听必须匹配绑定地址”的可复用教训补入 `godot-isolated-test-runner` 技能。

剩余：由 validation/性能 owner 根据上述正式 worker rename 诊断修复生产红项，再在新 freeze 验证消费者完整服务端链；本任务不改其代码，也不宣称最终 freeze 或窗口验收。
