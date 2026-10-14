# Round65：Loader runner 仅在所属 Job0 后归档

## 交付与边界

- 已取消 Round62 后台 `monitor` 和线程；没有给 `data.building-*` 加名字黑名单，没有改生产发布、DLL、generic runner、任何 GDScript 测试或原测试断言。
- `shared_read` 保留 share=7；注释纠正为“支持文件替换，但不保证 Windows 目录 rename”。Round63 真实报告中的 share=7 活体目录 rename：Godot/WinAPI 各 3/3 error5；only-afterexit 各 3/3 成功。本轮只读该报告，没有重跑84矩阵。
- 本轮证明的是 **runner 归档时序和失败关闭**，不是完整 loader/204 或七套验收，更不是历史 rename 根因已绑定或根治。

## 修改说明

唯一现有写入文件：`tests/round62_loader_error_boundary_runner.py`。

1. `require_owned_exit(label)`：要求启动 label 清单与进程回执数量、顺序及唯一性一致；每条必须明确 `exited=true`、整数 `active_owned_processes=0`、`log_handles_released=true`，且有有效 PID/退出码。当前 label 必须对应最近启动。缺失、未知额外回执、live child、未证退出均在遍历/open前拒绝。
2. `execute_owned`：在调用原 `r.execute` **之前**登记 label，因此无回执的启动异常不能被空清单误判为退出；返回后核验原进程回执，不改 stdout/stderr/exit。
3. suite 执行改为 `execute_owned -> archive(suite)`；无后台读取。归档函数自身也有同一前置门，不能由其他调用方绕过。
4. `finally` 先核验全部 owned，再归档、冻结摘要、证据读回、cleanup；任何未知生命周期都保存 manifest、保留 generated，不遍历/读取该树，也不尝试清理。
5. 为真实观察到的最终字节建立 `runtime-versions` 父目录。原代码没有建父目录，写版本失败被 `FileNotFoundError` 吞掉；现在保留原字节及其 hash。这里的“版本”仅是实际读到的字节，不重建已删除的瞬态内容。
6. `check_transient_report` 将已删除的必要原报告记为 `evidence_gaps`，最终 passed 增加缺口拒绝。原 worker/probe/错误门均保留。

新增：`tests/round65_loader_archive_afterexit_unit.py` 与本报告。

## 必须保留的瞬态证据阻断

已实际阅读：`loader_error_boundary_test.gd`、`room_validation_task.gd`、`room_data_preparation_dependencies_test.gd`、`room_data_preparation.gd`、`worker_content_environment_test.gd`、`content_environment_test.gd`、`validation_countdown_contract_test.gd`。

- `RoomValidationTask.cancel()` 只终止/清状态，不删除任务目录或报告；loader 的两次真实子任务、preparation 的任务报告可在退出后归档。
- **`worker_content_environment_test.gd:59-60,77,130` 会在退出前 `remove_tree(directory)`，删除其原始 report.json。** 该目录还位于原 archive 的 `cache` 排除范围，不能宣称旧 monitor 已完整保留它。
- 其原 stdout `WORKER_RANDOM_SIMULATION` 仅含模拟字段，保留原 stdout 不能冒充完整报告、原报告 hash 或所有旧瞬态版本。
- 当前七套 `green` 模式遇到该报告缺失必须留下 `evidence_gaps` 并 fail，不因其他 CHECK 通过而拼接全套 PASS。缺口判断只在 Job0 后检查 evidence，按上面已读的明确 producer/PID契约匹配，不读取或猜测发布子树。
- **待批准**：若仍要求这份原报告，需批准该夹具主动向独立 diagnostic 目录写出原字节/回执；本轮无权改 GDScript，未自行新增活体读取、目录推断或旁路。尚未批准，缺口未消除。

## Python RED → GREEN

真实命令：

```text
python -B tests/round65_loader_archive_afterexit_unit.py
python -B tests/round65_loader_archive_afterexit_unit.py ArchiveExitContract.test_missing_required_transient_blocks_overall_pass
python -B tests/round65_loader_archive_afterexit_unit.py ArchiveExitContract.test_deleted_worker_report_records_gap_without_reconstruction
```

- 先从原 runner AST 提函数，绝不执行其顶层，故单元 import/AST编译不启动 Godot。初次测试 seam 错误覆盖了 reader，出现 NameError；修正后才取得有效 RED：live/unknown/未证退出情况下原 archive 真正调用 reader，断言“绝不open”失败；另发现版本父目录缺失。
- 补门后该组 GREEN。随后瞬态缺口测试真实 RED：`True is not false: missing transient bytes must not be green`；缺口记录函数缺失也取得独立 RED，再实施缺口门。
- 最终当前源码与证据冻结源码均 **10 tests / exit0**。覆盖 live child、退出/log-release未知、缺回执、未知额外 label、启动异常、finally不读不删、Job0原字节/hash、原返回对象不改、真实 generic analyzer拒绝额外unknown ERROR、缺报告及缺瞬态不能判绿。生命周期单元数据明确只是 Python 夹具，不冒称 Godot报告。

## 最小真实 Godot 集成

```text
python -B tests/round65_loader_archive_afterexit_unit.py --integration
```

只从 Round63 AST 复用原 `GDSCRIPT` 的 `rename` 分支：真实 `DirAccess.rename_absolute`，普通生成字符串夹具，不加载游戏数据/存档/身份，不启动204、不模拟、不接触用户进程或28100。原引擎严格绑定 Round63 SHA：`ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`。

最终唯一冻结的这次操作：

- owner：`E:/scratch/isolated-9a29cbc0e7084827b6674b04848b03dc`。
- 真 Godot PID5792，exit0，Job0，logs released，0.685秒。
- 原 response：`GODOT_OPERATION {"godot_error":0,"ok":true,"pid":5792}`；原 stdout/stderr 完整保留且编码字节逐项一致。
- `execute_owned` 返回前归档读次数为0；返回后使用当前原 `archive` 与原 share=7 `shared_read`，读最终普通 report 与该夹具 Godot 日志。
- 生成原报告、归档、观察字节版本 SHA 均为 `10ce6cafa8269143ed08a9da7c90e5311d60917c111e9d68ca89f02adebc334b`。
- source/frozen drift 都为空；manifest 11项 artifacts离线全部读回一致；精确 generated已删除。
- manifest SHA：`8cce869ede0770e6bd02f41d4dbdd585e9e835fcab1ce8c9167d33c8e0f357ba`。
- `offline-verification.json`、`offline-unit.stdout.log`、`offline-unit.stderr.log` 在 owner 根保存再次执行冻结单元的原输出及独立读回结果；没有修改原 manifest 或原 Godot response。

开发中较早普通夹具 `8bf1f18921db424e8207af41194a99f1` 也真实退出/Job0/清理，但源码早于瞬态缺口门；不作为最终冻结的验收替代。最终仅上面9a29实例作为当前时序集成证据。

## 未覆盖与不确定性

没有重跑84矩阵、整七suite、loader204或任何生产场景。当前没有完整七套绿色交付：worker-content原瞬态报告独立落盘仍待批准。并行生产改动不在本普通fixture source manifest内，不宣称当前整树稳定或通过。历史204目录拒绝仍缺当次同线程Win32错误/观察HANDLE绑定；本修正排除已证诊断持锁机制，**不贴历史根治标签**，没有 retry/换发布目录/改断言/过滤unknown错误。
