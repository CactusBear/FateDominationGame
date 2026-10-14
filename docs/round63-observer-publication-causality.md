# Round63：观测器与 Windows 发布拒绝的受控因果边界

## 结论

- **否定本机、本版 generic `tree_bytes` 的“持有内容读句柄而阻塞发布/替换”分支。** 原函数真实执行 `os.walk/stat/no_links`，暂停在实际 stat 返回边界；原 Godot 目录发布、旧 DLL 文件替换与独立 WinAPI 控制均各 3/3 成功。按观测器 PID/TID 区分后，其 12 个样本只有 138 条 `GetFileInformationByName` 调用，没有内容 read open；不能把控制器预检 `Path.resolve` 的瞬时 metadata open 混成 `tree_bytes` 持锁。
- **原归档 read 能稳定造成拒绝。** 从历史失败归档的 `runner.py` AST 取出原 `archive()`，不重写读实现，真正执行 `r.no_links(p).read_bytes()`；另用原引擎实际递归 `DirAccess` + `FileAccess.READ`。两种原 open 均捕获 `GENERIC_READ=2147483648 / share=3`，目录 `MoveFileW` 返回 0/error **5**，文件替换返回 0/error **32**，每个 actor/operation 各 3/3 拒绝。
- **SHARE_DELETE 不是目录发布的充分修复。** 真正执行当前 Round62 `shared_read()` 原函数，捕获 share=7 的实际 HANDLE；已有文件替换各 3/3 成功，保持旧句柄仍读到完整旧对象、fresh 新读得到完整新对象。但持有发布子文件时，原 Godot 与独立 `MoveFileW` 的目录 rename 仍各 3/3 error 5。不能交付“加 SHARE_DELETE 就不阻塞目录发布”的结论。
- **目录发布子树采用 only-afterexit/Job0 归档是已验证的最小诊断侧方案。** 补充 12 个样本：发布期间没有归档读句柄，所有原操作成功；真实整 Job0 后使用同一个 share=7 原函数读取最终文件，临时归档复制、hash 读回全部一致，不丢本夹具要求的最终完整文件。它不承诺捕获每个瞬态版本。
- **未绑定历史 root cause。** Round62 的 `rename_error=1/files=204/index=204` 没有当次同线程 Win32 错误/观察 HANDLE 配对。本轮证明机制和否定错误替代解释，不宣称历史那次唯一由归档器导致；更不能证明所有旧保存失败都有同一来源。

## 固定范围与真实入口

仅新增：

1. `tools/diagnostics/round63_observer_lock_contract.py`
2. `tools/diagnostics/round63_observer_lock_contract_test.py`
3. 本报告。

生产、现有 tests、generic runner、现有诊断 helper 全部只读；没有改 OS rename、原引擎、正式 DLL、安全门或发布重试。没有启动 204/pipeline/98、没有 attach actor1 或任何已有 PID、没有全机 trace。复制输入仅原引擎、批准旧 DLL、其 extension 描述；夹具内容全部由诊断生成的普通字符串，未读取游戏数据、存档、身份或 records。证据只有路径、HASH、大小、源码和 API/过程日志，不保存夹具 payload。

入口不是 Python 替代 Godot：目录调用实际 `DirAccess.rename_absolute`；文件调用旧 DLL 中实际 `FateAtomicFileReplace.replace_validated_file` binding。**真实捕获显示旧 DLL 用 `SetFileInformationByHandle`，不是 ReplaceFileW**；其文件信息类别参数为 22。独立 controller 则真正调用 `MoveFileW/ReplaceFileW`，不替产品 fallback。

原 Godot SHA256：`ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`。
旧 DLL SHA256：`92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`。
最终工具 SHA256：`04c220442e23d10005ad0e4bf314bdd07a2ee172836a1ba3106d664983576765`。

## 握手与 API 证据

复用现有 assembly capture 的原引擎 HASH/PE/IAT/RVA 绑定、原 scoped memory/path/TEB/breakpoint 函数和 `compile_owned`，复用 `assembly_native_probe.safe/within/process_identity` 与 generic `OwnedJob/execute/delete_owned`，不放宽既有 helper 授权。

新的 debugger 只 `DEBUG_PROCESS` 创建自有 Python actor及其自有 Godot 后代。每个 CREATE_PROCESS 验证继承 Job、记录 PID/创建时间；没有 `DebugActiveProcess`。只输出独占 fixture 下的 API。API 入口记录真实参数；返回第一条指令记录 RAX 和同线程 TEB.LastErrorValue，核对 PID/TID/TEB/return PC；成功 LastError 保留 raw 值但 `failure_error=null`。目录返回 RVA 实际 `0x1348522`，对应批准引擎 `0x134851c` IAT call 后第一条指令。

Python archive：透明 Path.open 钩子在原 `read_bytes` 真 open 后、读之前暂停，`msvcrt.get_osfhandle(fileno)` 得到实际 HANDLE；事件 ready/release 握手，按实际 HANDLE+PID+TID匹配捕获的 CreateFileW。新 shared_read 同样只在其原 CreateFileW 返回后暂停，未替换原读逻辑。FileAccess：真正 open 后 stdout READY 由读取线程触发 Event，控制器操作完成才 stdin release；不存在 sleep 猜 race。普通 share=3 受控锁仅为附加对照，不当作旧 archive 重演。

原 archive 源：`E:/scratch/isolated-eaec18432e9e4e6cb0ec49d82f0d8ffc/evidence/runner.py` 的 `archive` 函数。新 share-delete 读函数源：当前 `tests/round62_loader_error_boundary_runner.py:81-103`。只编译指定函数 AST；不执行原 runner 顶层、不会启动原套件。

## 最终矩阵

每格是 **3 个预先声明独占普通夹具**；Godot 与 controller 结果一致。总数 7 variants × 2 actors × 2 operations × 3 = **84**，不是概率试跑。

| 实际观察输入 | 实际分享模式 | 目录 rename（每 actor） | 已有文件 atomic replace（每 actor） |
|---|---|---|---|
| none 对照 | 无观察句柄 | 3/3 成功 | 3/3 成功 |
| 原 generic tree_bytes | 无内容 open；metadata API | 3/3 成功 | 3/3 成功 |
| 原 Python 递归 archive/read_bytes | READ\|WRITE = 3 | 0/3，error 5 | 0/3，error 32 |
| 原引擎递归 FileAccess.READ | READ\|WRITE = 3 | 0/3，error 5 | 0/3，error 32 |
| 新原 shared_read 活体读取操作子文件 | READ\|WRITE\|DELETE = 7 | 0/3，error 5 | 3/3 成功 |
| 额外普通锁对照 | READ\|WRITE = 3 | 0/3，error 5 | 0/3，error 32 |
| 新原 shared_read，仅整 Job0 后归档 | 活体不打开；退出后 7 | 3/3 成功 | 3/3 成功 |

全部 84 行独立文件 hash/内容检查通过；负例原目标/临时文件仍完整且未换身份；正例目录子文件身份保持；文件替换后 fresh target 身份等于原完整临时文件、区别于旧对象。share=7 替换组的持有旧读者读回原 hash，fresh target 得到新 hash，未混合内容。父目录身份和同 volume 校验保持；身份整数以字符串保存。

例：`archive_python-godot-rename-0`，observer PID37136/TID28708/HANDLE772/share3；真实 Godot PID32320/TID34280，MoveFileW return0/LastError5。`archive_sharedelete-godot-rename-0` HANDLE772/share7，Godot PID14896仍 return0/LastError5。`archive_sharedelete-godot-replace-0` HANDLE764/share7，旧 DLL SetFileInformationByHandle return1，stage=published；旧 reader hash和新 fresh hash分别一致。完整配对见报告，不从最终 success 反推失败 LastError。

## 给 main 的唯一最小修改建议（本轮未实施）

**只调整活体归档范围/时机，不调整产品发布。**

- `tests/round62_loader_error_boundary_runner.py:105-127,162-164` 是已确认活体归档入口。保留 `shared_read` share=7，但将 publication subtree 的读取移到真实整 Job0 后；活体只读显式批准的诊断目录/日志，不能递归读取待发布 data/source/cache/staging 子树。现有 `dirs[:]` 排除 `data/cache/...`、名字含 `staging` 等，**没有排除实际 assembler 的 `data.building-<ticks>`**（生产源 `room_data_assembler.gd:63` 是 destination + `.building-`）。因此当前过滤不能证明发布子树不被碰触。若必须活体归档，基于声明的 destination/staging scope 排除整子树及其父遍历，不能只搜字串 `staging`。
- 旧 archive 的 `read_bytes/read_text/shutil.copyfile` 若用于已有文件替换目标的活体观察，至少改为 share=7 的真正 open；本轮只对普通目标文件验证其不阻塞。涉及目录发布子文件，share=7 仍不足，必须上述 scope/afterexit 方案。
- generic `tools/run_isolated_godot_test.py:167-179` 不改。本机实测该观察没有 read HANDLE；不要把归档读机制移植为其 root cause，或要求给 stat 加分享模式。
- `tools/diagnostics/round60_save_restore_first_failure.py:320-324`、`round61_restart_agent_runner.py:372-377` 已在明确 Job0/log release 后归档；`newtools/diagnostics/round60_pipeline_publication_capture.py:269` 也是所属 execute 收尾后的归档，不是本轮确认的 livearchive。维持其 afterexit 门，不泛改。

## 验证与保留证据

真实命令：

```text
python -B tools/diagnostics/round63_observer_lock_contract.py --execute
python -B tools/diagnostics/round63_observer_lock_contract_test.py
```

最终命令 exit0；**passed=true 表示这份正负机制矩阵证据完整，不表示所有观察 variant 都允许发布，更不表示历史 bug 根治。**

最终 owner：`E:/scratch/isolated-ea791a9a1e144159af3a72b376b4135e`。
证据：`evidence/report.json`、`observer-matrix.stdout.log`、`observer-matrix.stderr.log`、`capture.cpp`、`scope.json`、工具源码和编译日志。
manifest SHA256：`c9a2f2ff061fa694063fd03d26f68fa697cb0a96621d704e3984923cfc81c906`。

- 实际配对 API **4381**；原 wrapper 文件操作 **21** 条 SetFileInformationByHandle，独立 ReplaceFileW **21** 条；目录调用另独立配对。
- build root PID14808/exit0/Job0，4.246秒；matrix root PID25368/exit0/Job0，49.26秒，均 log handles released。
- 7 个证据 artifact SHA 逐项独立读回一致，source_drift=[]、frozen_drift=[]。整生成树已精确 cleanup，当前 `generated` 不存在；保留证据。
- Python 单元 **3/3**：declared scope/token/路径拒绝且不误 open、未知观察文件在 reader 前拒绝、API同线程/完整配对与成功陈旧 LastError处理。真实 matrix 又按 observer HANDLE/PID/TID 排除控制器验证读者；tree content open=0。

开发中的失败不拼接最终 PASS：`267c...` 导出解析把 MoveFileW 当 kernelbase 导出；`2c9...` FileAccess 比较路径斜杠错误；`c212...` OS.execute 命名事件握手未及时 ready，改为原 reader stdin/stdout事件交接；`1feb...` 尝试在 stat native open 后握手，但原 tree_bytes 的实际 stat根本没有该 CreateFileW事件，拒绝用人工锁补造它；`89ad...` thread-global open guard误拦控制器临时文件校验，限定观察线程后修正。`9d039...` 是早期72格完整矩阵，不作为最终冻结替代。以上及最终共7个 owned scope都核验 Job0/生成树不存在；每次只是有界普通夹具，不跑正式204。

## 未覆盖与未宣称

没有历史失败自身的 API/HANDLE关联，所以历史 causality/root仍未证实。stat负结论限定当前 Python/Windows 的实际无链接普通输入；不推论所有 OS版本、reparse/fallback syscall或外部进程。没有突然断电/崩溃持久性、目录敌对改写、产品保存/恢复事务或完整 pipeline 认证。未实现生产修复、未加 retry、未重建DLL；原有历史阻断不被本轮机制实验冲销。
