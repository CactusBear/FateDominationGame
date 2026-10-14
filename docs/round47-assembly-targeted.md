# Round47：仅两个真实目录调用；原失败仍未知

**未根治、未重试、未提交生产释放补丁。** 一次继承原 `assembly_publish_lifecycle_test` 的真实执行，保留原66门：`RESULT checks=66 failures=[]`、Godot exit0，70.295s（预算180s）。本次 formal204 / preparation 均成功；不冲抵 Round43 原65项两项失败，也不能证明历史瞬态问题消失。未再次运行Godot，不跑新24项替代原66项。

## 范围与实现

仅修改 `tools/diagnostics/assembly_publish_failure_capture.py`；新增 `tests/round47_assembly_targeted_capture_test.{gd,tscn,py}` 与本报告。production、旧测试、原native helper、引擎均只读。

新GDScript继承原场景完整 `run()`，仅重写 `_scan()`：原探针执行后，formal-204 / preparation-204 交接准确 `_staging → _destination`；两个一次性、5s上限握手不添加CHECK、不改变原rename结果。除握手之外，原测试的受控锁、取消、冲突及真实准备链仍保留。没有生产sleep/retry/替代发布。

调试器不再给rename函数入口或全部cache调用设置持久断点。只在收到准确目录对后临时启用两个已绑定MoveFileW调用点；命中后验证参数完全相等，撤掉另一调用点，捕获返回后第一条指令。**实际API_BEGIN=2、API_END=2；cache临时文件和 formal-204-own-lock 均未被API捕获。** 入口/返回各暂停一次，共四次正式API断点事件；另有两次诊断握手及原场景探针，仍会改变调度，不称无扰动。

失败分支在同线程API返回点先读RAX低32位和TEB.LastErrorValue，再采当前自有File类句柄、pathidentity/raw模块RVA；终止自有引擎阻止 `_abort/cancel` 清理，归档fixture/cache/staging/source并核对hash后回收generated。不覆写RAX或API返回，不改磁盘引擎或生产逻辑。**本次没有正式失败，此原生失败保全分支未获得真实故障运行验收；静态检查不能替代它。** 原受控锁的原场景检查执行成功，保留的sibling控制error5不纳入正式错误证据。

## 静态预检与真实捕获

先执行 `--preflight`，核验原输入、原场景hash、物理E根及固定argv契约；实际Godot创建前还核验已存在的approved根、全新规范candidate、无链接/越界、冻结文件hash及实际argv。

- 引擎SHA256：`ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`；原实际4.7.2/ed1daf0bf，未升级。
- MoveFileW IAT调用RVA：`0x134851c` / `0x13486db`；PE导入/`.pdata`及运行时完整6字节再次绑定。实际两次均在 `0x134851c`，返回 `0x1348522`。
- TEB通过准确线程句柄的NtQueryInformationThread取得；当前OS自身SetLastError(0x4321)验证`+0x68`布局。捕获Godot PID2236、TID33316、TEB=`0x38bd9fa000`。
- 两次真实API均 `return=1,last_error=2`；成功时2是陈旧值，`failure_error=null`，不能解释为原失败错误。
- formal source FileId=`70120c00000004000000000000000000`，同FileId成功出现在destination；parent前后=`450e0c00000007000000000000000000`。
- preparation source FileId=`49250c00000006000000000000000000`，成功目标相同；parent前后=`48250c00000004000000000000000000`；volume=`11280545796426856594`。
- 原场景两个发布前自身快照均 `matching_handles=[]/blocked_files=[]/duplicate_failures=[]`。新调试器成功返回不加额外句柄快照；失败才扫描，进一步减少暂停。没有外部PID或系统handles查询。
- 实际重建204清单与原native-input的52,029字节逐字节相等，SHA256=`98469b47c4526f17a50633b3279567d17339fa61ed3895954e7ba9b3de58d568`。原场景GD hash仍为`df499eff188d781c57b90a5ded679b9c0cc732f7ace9d8ca87e0cb607c14792b`。

本次使用当前冻结2238源依赖，不是假称Round43同冻结：执行前已有5项差异（server.cfg及preparation/validation_worker/validation_task/random_simulation），逐项新旧hash在原manifest.preflight中。重解析时又发现当前工作树的 `battle_board_v2.gd`、`server_bootstrap.gd`、`server_room_manager.gd` 与执行冻结不同；因此重解析总门`passed=false`、exit2，不能宣称当前整仓GREEN。冻结场景本身analysis通过、66个CHECK、无ERROR，二者分开报告。

## 原件、解析器问题及清理缺口

原件根：`E:/scratch/isolated-89c969452a604b4d9d9c67bf7817ec34/evidence/`。

|原件|SHA256|
|---|---|
|original-assembly66.stdout.log（75,396 bytes）|a961799141d6be115cc543da2be18d1dadc29c9b5a56a74d0fbf33e259420270|
|original-assembly66.stderr.log（0 bytes）|e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855|
|capture-manifest.json（首次解析阻断保留）|c41e2997618b286f1998771f8e578acec64d972043d8bb79c328b0e51ee0ed71|
|reparse-manifest.json（仅原日志重解析）|b4c0051957b4af3765be827b9d223d976e7fd32e015d000e6d3faf8a78257fd1|
|capture.cpp|6e29172e63cfa092736eb32a7386148c74b8f26ea8ca730dc61089dde122e049|
|capture.exe|bdf33c92a10dacc72964516aef5f9412e413cc1f2d8ddd8d84a21e1502b486eb|
|执行时assembly_publish_failure_capture.py|d0cc64ba59efab00c25e3e084c2927e129e5c8dc692fa8c9853e98d928e51313|

首次真实执行后，Python解析器未支持Win32实际`\\?\E:\...`前缀，外层exit1；真实Godot/debugger已exit0。修复只涉及命名空间校验解释，保留API路径原字节；新增单元后只读重解析原日志，没有重跑。当前C++文本与执行归档一致（WindowsCRLF按文本比较），最终Python解析/归档代码不同于执行时原件。

**归档缺口：首次解析异常跳过了正常路径的scope.json/native-audit/gates复制；清理只保留了原stdout/stderr、编译原件、manifest、owned-runtime等10个原件文件，这三个独立原生回执目录/文件已随generated回收，不能补造。** stdout仍保留实际API参数/TEB/identity、原探针JSON及引擎退出；本报告不称完整原生审计归档通过。最终代码已把这些文件及实际测试/config/helper/input复制放入无条件finally归档路径，失败source也归档；此归档修正未另起Godot验收，以遵守不反复试跑要求。

编译Job：root37292 exit0、7.955s；其自有vctip PID20472按持有Job收尾。运行Job：debugger21748、Godot2236，70.295s、exit0、无超时；所有记录exited=true/ActiveProcesses=0、日志句柄释放。未按名字杀进程、未attach已有PID。归档hash读回后仅回收唯一generated，1,153,357,232 bytes；generated读回不存在。

## 实际命令与验收边界

```text
python -B tests/round47_assembly_targeted_capture_test.py
python -B tests/round44_assembly_failure_capture_test.py
python -B tools/diagnostics/assembly_publish_failure_capture.py --preflight
python -B tools/diagnostics/assembly_publish_failure_capture.py --execute
python -B tools/diagnostics/assembly_publish_failure_capture.py --reparse E:/scratch/isolated-89c969452a604b4d9d9c67bf7817ec34/evidence
```

新单元先观察目录对校验缺失RED，再GREEN；准确线程/TEB/RVA/路径配对与Win32前缀负向也已实跑。最后3项新单元及1项旧解析单元PASS；最终诊断器SHA256=`24c876625aa76c8aca08d44b2ef44478bd5c37cc36a5ea2f3af056eb2a38d3fc`，已通过作用域内diff/尾随空白检查。原始执行外层exit1、Godotexit0/66项；重解析exit2仅保留当前源漂移总门，不降低原66门。没有第二个正式场景，没有受控锁API错误冒充历史错误。

没有真实正式失败关联自有生产句柄的证据，**不提供猜测资源释放补丁，不归因杀毒，不修改production**。历史formal204/preparation仍UNKNOWN/BLOCKED；自有句柄关联若未来获得真实证据，才交main最小作用域释放候选，本轮不重试至green。
