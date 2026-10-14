# Round66：fixture-owned 瞬态 report 显式交接

## 结果与范围

本轮已授权 fixture 主动交接诊断字节。无生产文件写入、无新泛化服务、无后台 monitor，原 Round65 Job0 reader 门及 share=7 保留。未重跑84矩阵，未重开已经解决的活体归档持锁风险，也不把本轮绿色结果解释为历史发布失败的完整根因证明。

唯一修改的现有文件：

- `tests/worker_content_environment_test.gd`
- `tests/round62_loader_error_boundary_runner.py`
- `tests/round65_loader_archive_afterexit_unit.py`

新增：`tests/round66_transient_report_handoff_unit.py`、本报告。

## 解耦与确定边界

`_inspect_loaded_content` 在模拟 await 前完成 `_write_report` 的 flush、close、rename；它返回后只改变内存 report，不调用完整入口的 final `_write_report`。因此磁盘原文件是 **running checkpoint**，stdout 的 `WORKER_RANDOM_SIMULATION` 是另外的内存模拟结果，二者不合并、不重建。

runner 为每次调用明确创建 `generated/diagnostics/<显式label>`，传入目录和非秘密 `run_id:label` token，manifest 保存精确 receipt/bytes 路径。这里的 label 是启动契约，不用它搜索生产路径。

fixture 在原一次性 `process_frame` 观察回调中，对自有 `args[2]` 执行一次 `get_buffer(length)`；源 handle close 后，才对内存中的原字节哈希、保存 `report.bytes` 和 `receipt.json`。原 running 断言复用这次读取。receipt 明确声明 schema、fixture、token、真实 PID、running_checkpoint、source_read_closed、源路径、长度、SHA256、bytes_path。没有 data.building/cache/其它 producer 扫描，没有序列化 `simulated` 冒充落盘 finalreport。新增证据完成断言在原 `remove_tree` 前执行。

无参数分支保留原读取与全部原断言，实跑仍45项。传了参数时，目录/token错误、缺报告、读失败、写副本/回执失败都走 `check(false)`；源/目标 handle 均明确 close，不静默缺证。

`check_transient_report` 先验证所属 Job0/log-release，再打开两个显式文件；不 glob、不用 PID 猜源目录。验证声明目录位于本次 diagnostics、精确两个路径、token/PID/schema/kind、正整数长度、SHA256、原 checkpoint roster/status。收据不能重定向 reader。复制到 evidence 后再次精确读回。所有缺证/不匹配写入 `evidence_gaps` 并使整轮失败。

## Python RED → GREEN

真实命令：

```text
python -B tests/round66_transient_report_handoff_unit.py
python -B tests/round65_loader_archive_afterexit_unit.py
```

AST seam 只编译原 runner 函数，不执行启动 Godot 的顶层。Python 输入明确为普通单元诊断字节，不称真实 Godot 报告。

- 首次正例有效 RED：`False is not true: declared matching original checkpoint must close the gap`；补显式读取后 GREEN。
- 补身份/完整性测试后，有效 RED 为6个失败：同长度篡改、错token、旧PID报告、未声明目录、receipt重定向、用complete替换running。补验证后全部 GREEN；缺bytes和live child在既有关闭门下保持失败关闭。
- 最终专项9 tests、Round65原10 tests，全部 exit0。Round65整体缺证测试补充通过的 standalone前置数据，避免新前置门导致测试空洞。
- 实跑冻结证据中的这两份 Python 源再离线执行，分别9/10 tests、exit0，原输出在 owner 根保存。没有为取得 RED 制造 Godot 解析错误。

## 一次同冻结真实验收

真实命令：`python -B tests/round62_loader_error_boundary_runner.py green`，exit0。

owner：`E:/scratch/isolated-d1d01d4f069c4bc7b37b9bd1d3d3ef48`

freeze SHA256：`ec42c576b718cec1785e4700e82b22fe7c8891d7d7de91972cfb9259421021e6`

manifest SHA256：`0ab3a5fba74dd21ee4e8e67854ef36c3ff0e9c6de6116e108ee75005e366b536`

原引擎 SHA256：`ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`。正式 DLL、生产脚本、server模板和原20线程池均在650项 source/frozen 哈希清单内；server原15秒预算不改，loader204单独显式关闭simulation。仅隔离副本原有 VCS/MCP/main_scene 调整，未变更用户进程或28100。

同一副本先执行无参数旧调用45/0，再执行独立诊断调用56/0（原45＋新增11），随后完整原七场景各一次：

| 场景 | checks | exit |
|---|---:|---:|
| loader_error_boundary | 62 | 0 |
| expectednegative | 9 | 0 |
| expectednegative_extra | 9 | 0 |
| worker_content_environment | 56 | 0 |
| content_environment | 30 | 0 |
| room_data_preparation_dependencies | 34 | 0 |
| validation_countdown_contract | 21 | 0 |

七套 RESULT 原输出由程序解析求和为 **221**，不是硬编码210。fixture 的原45行与冻结源声明的11个诊断断言逐项对账；没有削弱原断言。

- expectednegative stdout/stderr及logger精确为6条声明扫描 ERROR，覆盖 load_game/reload_game/direct × masters/servants，路径在所属E独占树内，原调用栈合同保留。
- expectednegative_extra 精确上述6条＋唯一 `ROUND62_UNEXPECTED_EXTRA_ERROR`，真实原 analyzer 拒绝它，控制测试保留；离线再次确认没有其它错误。
- 其它父进程、所有实际子worker logger及导入/probe日志无未知 ERROR/SCRIPT ERROR。不是通过全局99/白名单过滤。
- 12个Owned Job记录全部 exited、active_owned_processes=0、log_handles_released=true，所有退出码0、无看门狗失败；真实主/子user探针及3个正式validation子探针路径都为本次E独占路径，pool=20。
- 3份实际最终worker报告批准数量 `[1,1,204]`，原字节读回且都 verified：两个single-card报告零roster、准确3条拒绝诊断、configured=false；204报告ok、errors空、有效roster、enabled=false。
- source_drift、frozen_drift、diagnostic_source_drift均空。本轮没有导入失败或其它GD浮动，无重复整套导入/试跑。

## 瞬态原字节与清理

两份独立原 checkpoint：

| 调用 | PID | bytes | SHA256 |
|---|---:|---:|---|
| standalone | 24228 | 212 | `4f8f93bfdfa200cf5148b8de874ffd5296b72a768bb3d0bd0a158eb11d1581d2` |
| 七套worker | 37472 | 212 | `a343ba511e43f3a24fcb31b1c4547faf00f195dd76a6b20633075e701bb1c5e2` |

原报告分别位于 `evidence/transient-report-standalone/report.bytes` 与 `evidence/transient-report/report.bytes`，各有相邻receipt。原始status均running。receipt token、PID、精确输出路径、字节长度/hash均与所属manifest契约一致。final模拟只由原45断言及原stdout证明，不声称有未落盘的finalreport或所有历史版本。

748项原artifacts全部按原长度/SHA离线读回，650项冻结源全部读回；三份最终worker原报告及两份checkpoint均额外验证。runner在Job0后完成artifact readback才回收自有generated，现路径不存在。`offline-verification.json` 和两组离线unit stdout/stderr保存在owner根，未改原manifest。

## 验收边界

本轮 transient-report 缺证已闭合，整七套同冻结通过。没有窗口、多机/跨网、发行包验收；没有证明旧目录rename故障的唯一历史根因，也不把它列成重新调查monitor的理由。唯一当前运行产物是上述冻结，未拼接其它轮次的通过证据。