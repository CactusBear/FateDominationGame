# Round44：真实 assembly API 捕获；历史首红仍 BLOCKED

**结论：未根治。原 Round43 formal-204 / preparation 的失败 GetLastError 未捕获，历史根因仍 BLOCKED。不得把本次未复现或受控锁错误5当作原错误。未改 production/native/既有 helper、未重跑70套、未添加 retry/sleep/绕 rename/删除目标。**

## 准确引擎源码与 RVA

- 原实际引擎：`4.7.2.stable.official.ed1daf0bf`，SHA256=`ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`。D 源引擎只读，实际运行复制到物理 E。
- 从 `https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf/drivers/windows/dir_access_windows.cpp` 实取源码，与本地原件逐字节相同；SHA256=`5dfc05882fb39e5e8bb10ea89ef97d5fc44299d70811cc13eaacaadb2d6a0730`。
- 源第306–348行：先 fix_path；大小写同路径有目录/文件分支；不同路径先检查目标普通文件，若目标文件存在且 remove 失败可提前 FAILED；否则第346行 `MoveFileW` 返回0折叠为 FAILED。本次正式源/目标不同且目标不存在，现场实际进入 MoveFileW，而不靠 rename_attempted 推断。
- 同 hash PE 导入表 `MoveFileW` IAT RVA=`0xad7f5d8`；代码调用 RVA=`0x134851c`、`0x13486db`，同一 `.pdata` unwind 函数范围 `[0x13481f0,0x13487fc)`。完整反汇编保留 CreateFileW/GetLastError/MoveFileW/DeleteFileW/CloseHandle/ReplaceFileW 分支，匹配上述源码结构。
- 本次正式调用在 `0x134851c`，返回后第一条指令 `0x1348522` 停下，读取低32位 RAX 和该线程 TEB+0x68 的 LastErrorValue。TEB 来自准确线程句柄的 NtQueryInformationThread；在当前 OS 上先以自身 SetLastError(0x4321) 验证布局。调试器自身 API 不会改目标线程的 LastErrorValue。
- 没有完整 Godot PDB。沿用旧只读栈打印器留下的 `symbol=NoHotPatch+远距离偏移` 是最近 export 标签，**不是函数名，全部不采信**；有效栈证据仅 module/原始 PC/RVA。不声称已获得源码级全栈符号。

## 最终真实边界（不是历史系统错误）

最终 capture：`E:/scratch/isolated-6529b0ff0c6b49ebaf75ed63e2a33d3b/evidence/`。
Godot PID=`6532`，debugger PID=`32616`，正式线程 TID=`37368`，TEB=`0xdfb85ae000`。

|边界|真实序号|MoveFileW 返回|当线程 LastErrorValue|引擎 rename|
|---|---:|---:|---:|---:|
|formal-data 正式204|205|1|2（成功时陈旧值，无失败含义）|OK=0|
|formal-204-own-lock 受控204读句柄|206|0|5（该次 ERROR_ACCESS_DENIED）|FAILED=1|
|preparation-work/.../data 真实准备器|410|1|2（成功时陈旧值）|OK=0|

- 正式204与原失败自身 native-input manifest 字段/顺序/JSON原字节一致；204文件全部经过原 catalog/plan/cache.store/assembler，再逐文件摘要读回。准备器也使用原生产 copy/verify/assemble/validate 链；不是 Python 行为替身。
- `RESULT checks=24 failures=[]`，唯一 RESULT，实际 CHECK=24；正式 publication.complete=true、preparation.complete=true。该独立诊断24项**不充抵**原70套或原assembly必需66门。
- formal 源目录 FileId=`6d660b00000025000000000000000000`；成功后同 FileId 出现在目标。formal 父目录前后 FileId=`7c640b0000002d000000000000000000`，volume=`11280545796426856594`。
- preparation 源/成功目标 FileId=`117c0b00000025000000000000000000`；父目录前后 FileId=`107c0b00000023000000000000000000`。完整绝对 Win32 参数、RCX/RDX、身份及栈在原始日志。
- 正式205、准备器410在 API 入口与返回暂停时，自有匹配文件句柄只有 godot.log；source/cache/staging无匹配句柄、不可检查数0。受控206精确看到自有 handle1324、access1179785、`selection_modes.json`，入口/返回均仍活，并捕获该次真实 API error5。**不是 sibling 探针的 error5，不归因历史。**
- 入口/返回快照不是 syscall 整段连续观测，不能证明两暂停点间无瞬态；没有查询外部 PID/全系统句柄。原测试 helper 的 sibling 控制记录原样保留，但完全不纳入原失败归因。
- 调试器捕获了410次引擎 rename（包括真实 cache.store 的临时文件发布）；每次断点、栈/句柄观察与原 helper scan 都改变调度。本次未复现不能排除生产瞬态资源句柄或外部占用。

## 原件、摘要与当前 sourcehash

最终原件：
- `real-204.stdout.log`：3,693,808 bytes，SHA256=`1aa8d2644202301b1cf0cc99aa8012cb3af6a28b7924ff02504a9eab445aea9a`；stderr空，SHA256=`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`。
- seq205原日志行9449–9493；seq206行9505–9551；seq410行20122–20172。`focus-call-blocks.raw.log`仅按这些完整原行提取，未改结果或符号标签。
- `capture.cpp` SHA256=`4fa4b68ddac0196033f399d4feacfd7245aa8f8f31517b9fa67b41a59c5368c1`；`capture.exe`=`ceb820eb5df7bab50186a9319e9d482929dcc2dfb1d64d93bb4ce308989c77c4`；准确源码在 `dir_access_windows.cpp`。
- `rename-function-disassembly.txt` SHA256=`6a3fe365bec61376e2b3c9d841ff3ad99df1a191a47205c27ea4f1073ddba828`；`capture-manifest.json`保留执行时 source_files、暖缓存hash、命令、API pairs、结果及Job回执；`scope.json`和native-audit保留原授权和实际 helper PID。
- 四个独占 owner 的完整hash与退出清理读回汇总：`delivery-evidence-index.json`，SHA256=`18417e6e7960ab65533db0b7f381064300857ad9cc7944b334a1e56d33048fcb`。
- 原2238依赖逐文件当前hash与Round43完全一致，前后 drift=[]。该清单按 `json.dumps(source_files,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()` 编码的集合hash=`3b4aafbf08a476f27be7a9df24287f3ea621c68a6d434944a30a341c409a3421`，不是Git提交hash。

当前关键源hash：
|文件|SHA256|
|---|---|
|room_data_assembler.gd|f39d01f8b8a48a3298c461a69fdcee986e68559066b29e69957e0899f76d282e|
|content_cache.gd|eb7b3d1dfec6cf017e64ea15eecdfa60d7d9ea44087bd4e527453c2853f5b9de|
|room_data_preparation.gd|540e65ed90bbc4ce245fbf737fd85dcae87beb505139003a5415bd4bdeaf7f21|
|原assembly_native_probe.py|ace59ea3704270aab0bc66f0fbfedd385621b192944242c16867be80cc6ca689|
|新assembly_publish_failure_capture.py（实际执行同hash）|8a5b41333ef414e38697a7762d9db9dcc641165835374ec05a2ff58d2caf71d4|

## 有界次数、执行器问题与整树清理

实际Godot最多3小次，无再次冷native import，每次真实场景预算180s：
1. `5c9dd29d599a4b07b182cf1bc8867559`：3.894s，engine12036 exit1；candidate反斜杠导致既有规范路径门拒绝。只捕获启动 stored_jsons.dat rename，不是assembly。
2. `e639a9b3ae6a450f9dd018a15286da7f`：4.155s，engine26352 exit1；批准根尚未建立，被既有根存在门拒绝。仍未进入assembly。
3. `6529b0ff0c6b49ebaf75ed63e2a33d3b`：30.871s，engine6532/debugger32616 exit0，24 checks；本轮唯一进入完整真实204/preparation的场景，含原测试一项受控204自有锁对照。

另有编译前置 owner=`682ba7dfcdd142dfa330cdb6644bf8a0`，无Godot启动；两次根编译均exit0，通用执行器因Job持久后代在61.201/180.953s误归预算停止。后续仅从自有Job PID表核验残留是MSVC `vctip.exe`，编译阶段改为先收根退出，再终止其持有Job内后代；不是放宽Godot完整子树规则。首次清理曾因漏写ownership receipt拒绝，原日志保留；已补当前自有receipt并回收该树。

所有4 owner的全部进程记录均 exited=true、ActiveProcesses=0、日志句柄已释放。全部generated现在不存在；最终回收939,806,668 bytes。每次只停止自己持有Job/进程句柄，无按进程名杀进程、无attach已有PID、无提权。

实际执行命令：
```text
python -B tools/diagnostics/assembly_publish_failure_capture.py --execute
python -B tests/round44_assembly_failure_capture_test.py
```
单元先RED（实现缺失）再GREEN，最终1项PASS，拒绝API入口/返回线程错配，未配对入口不产生错误证据。原执行中编译恢复脚本已归档前置owner的 `resume-executed.py`，不留下已回收路径的可执行测试入口。

## 根因边界与下一步（本轮不再实测）

- 原 Round43日志/manifest/native-input保留FAILED=1；当时是否实际到MoveFileW、准确系统错误以及锁主体仍不可从历史快照还原。当前仅确认准确引擎源码有错误折叠、本次两个正式成功调用实际进入API。
- 未获得生产资源句柄作用域的失败证据，因此**不提出猜测生产修复**，更不越权修改生产。只有未来实际正式失败同时看见准确自有源/staging句柄，才可提出局部资源释放作用域的独立补丁及“保持原读句柄故意仍失败”的负向验收。
- 如后续获授权，下一步是将观察缩到 formal/preparation 两个正式 API 边界，降低410次暂停对调度的影响；或使用严格自有PID/批准E路径的被动文件调用跟踪捕获原失败。同样禁止扩大scope、外部PID读取、retry/sleep/绕rename/删目标。外部瞬态或引擎折叠无法精确归因时继续保留业务红。

新建项目文件只有新capture helper、三个round44测试文件与本报告；production/native/原helper/原测试只读，未commit。
