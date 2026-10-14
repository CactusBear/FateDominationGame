# Round60：正式 pipeline 发布系统调用与 relay 独占根

## 结论与保留的阻断

- **pipeline fresh 本次成功，原 204 正式发布 FAIL 未复现、未根治、继续保留。** 实际 `MoveFileW` 返回 `1`，同线程 `LastErrorValue=2` 是成功调用残值，不能解释旧 `rename_error=1`。没有使用受控锁的 error5 冒充原错误，也没有新增随机重试。
- **relay 本次 22/22 实际 CHECK 通过、自然 exit0。** 原中断后未到达的“gateway crash does not leave orphan authoritative process”和“real service startup and requests have no engine errors”均真正执行为 true，解除这个单套的产品失败怀疑。
- **完整执行器累计 8 GiB budget 策略未修，不能宣称完整批次 GREEN。** 原 relay 是 `generated.parent` 累计触发 `byte_budget`、父 exit125、20 CHECK/无 RESULT；本次是独占新根的自然产品退出。两种退出不混算。
- 两套各运行一次；pipeline runtime 39.243 秒（上限600），relay 24.754 秒（上限180），正式 template 15 秒预算、20线程未改。当前 source/frozen hashes 在两 scope 完全一致；没有换 Godot/DLL，没有写 production/native/完整执行器。

## 真实命令、产物及 SHA

仓库根实际执行：

```text
python -B newtools/diagnostics/round60_pipeline_publication_capture.py --preflight
python -B newtools/diagnostics/round60_pipeline_publication_capture.py --execute
```

preflight 最初因配置空格的诊断 regex 拒绝，修正只读解析后 exit0；**拒绝发生在启动 Godot 前，不是一次 pipeline 运行**。执行入口自然 exit0，执行器 PID31144 已退出；没有重跑两套。

以下都是物理 E 自有根，原件已保留，不在工程资源树中：

- pipeline：`E:/scratch/isolated-836589b4ae344d55908404d0e447a454/`
- relay：`E:/scratch/isolated-affe012422894b20b4a2b80092d870d5/`
- 每根的 `evidence/capture-manifest.json`：准确 argv、显式环境、2028项 source/frozen SHA、process/Job、实际所有 CHECK、唯一 RESULT、底层捕获、生成树 metadata及 artifact hashes。
- 每根的 `evidence/<suite>.stdout.log`、`.stderr.log`：未过滤原输出；`evidence/runtime/`：批准的全部父/子 log/report/manifest。未读取/归档 records、身份秘密或 control 回执内容。
- pipeline `evidence/capture.cpp`、`capture.exe`、`scope.json`、`build.cmd`、`assembly_native_probe.py`、`runtime/gates/pipeline-plan.json`：真实编译的调试器、准确 ownership scope、204正式计划和门交接原件。
- pipeline 根 `two-scope-readback.json`、`verification-readback.json`：两 scope source/frozen 一致、只读工具摘要未漂移、全部日志错误扫描和归档 SHA 重算。不是追加运行。

|原件|SHA256|
|---|---|
|pipeline capture-manifest|`75f1e8d75e08c2408c4e11948079054ae978e60210fe9b5963ef308f83262587`|
|pipeline stdout|`95388d6a850d1a292c6debc6da33900f7fa39028658fbc9fd3c253e287737baa`|
|relay capture-manifest|`cb196a3c4a69a1dfb33251b41b27b9eff4445f25c8a0ab41a5fcc0b40ae17965`|
|relay stdout|`dad3f6b60778b6e09982f00876034a1fdb971696a3b9e6a4262aa78dab489850`|
|verification-readback|`4b9e9336c958293c4007ba38c779b17a643ef38f14137d8d789bf1460a297926`|
|实际执行/归档的本轮 Python|`eb1af950f51be932e920c50dc809331cb4dc3c9b6bb8a09c27f3c0a0d58f8b7b`|

两套 source hash 字典排序紧凑 JSON 的 SHA 均为 `75997e56d4788c6c1a0ff5b5c7c0da1162027536c956f3a68967997ec688b279`。pipeline测试 SHA `4c8a757983ca369e168c61c5a69092459f74009816b99ed421fa715cbcc27507`；未修改 relay测试 SHA `eae78af3f5ac2b5049909111babd65cad5ef3089d1dd0a1b0fa0132ad87495f1`。

原 Round58 manifest 重新读取 SHA 仍为 `d439e06fd4a92592211d306dfa292ba2af90c04c699bdd3fb52ee19b5bcc85b4`，原 RED/exit125 未覆盖。当前与 Round58 的10项 source 差异是本轮 pipeline诊断和其他拥有者测试迁移，明列在 two-scope preflight；production、正式DLL和引擎保持原指纹，不能把本次整个测试树称为原冻结。

## 原204失败与本次真实系统调用

原件位于 `E:/scratch/isolated-1105873e41cd4f6a94a999e65ac6af50/evidence/complete-validation_pipeline_performance_test.stdout.log`：

```text
ROOM_DATA_ASSEMBLY_REJECT {"destination_directory_exists":false,"destination_file_exists":false,"destination_length":181,"files":204,"index":204,"phase":"write","reason":"无法发布完整会话目录","rename_attempted":true,"rename_error":1,"staging_exists":true,"staging_length":199}
CHECK complete production preparation includes real isolated loading false
PIPELINE_PREPARATION_ERROR 无法发布完整会话目录
RESULT checks=259 failures=["complete production preparation includes real isolated loading"]
```

本次仍走 catalog→plan→真实cache/publish→RoomDataPreparation→真实 assembler；计划实际204、write index204。原断言没有删除；本次成功多出的第260条是原本已有但旧失败未进入的 adoption/dataACK readiness 断言。没有新增诊断 CHECK 来改计数。

在这个准确目录对进入引擎 IAT 调用时捕获，同线程返回下一条指令读取：

```text
API_BEGIN seq=1 tid=1200 target=preparation-204 rva=0x134851c teb=0x23b84e8000
API_END seq=1 tid=1200 return=1 last_error=2 teb=0x23b84e8000 return_rva=0x1348522
ENGINE_EXIT pid=31636 code=0 timedout=0
DEBUGGER_EXIT engine_exited=1 engine_code=0 timedout=0
RESULT checks=260 failures=[]
```

准确 API source/destination 完整原字节在 stdout 的 `API_PATH` 行及 manifest `api_calls`；限定当前 token 的 `generated/f/complete-0/localappdata/hermes/cache/scratch/pipeline-<token>/full-preparation/31636-24271219/data[.building-27817418]`。API路径保留原 `\\?\` 扩展前缀，长度192/210（不含前缀188/206）；**不冒称与原181/199相同长度**。fresh路径和调试器暂停改变调度，成功不能排除原短暂故障。

### 实际 identities 与本进程句柄

volume=`11280545796426856594`（十进制字符串），目录 attributes16，无reparse：

|对象|before|after|
|---|---|---|
|staging/source|fileid `1c2e0d00000011000000000000000000`|不存在，error2|
|published/destination|不存在，error2|同一 fileid `1c2e0d00000011000000000000000000`|
|二者直接parent|`1b2e0d0000000a000000000000000000`|身份不变|
|full-preparation parent|`192e0d0000000a000000000000000000`|身份不变|

仅 `NtQueryInformationProcess(ProcessHandleInformation=51)` 查询 debugger 创建的 Godot PID31636；按真实 File 对象类型复制其句柄，不查全系统句柄表，不 attach editor/用户PID。前后各 `matching=1 / uninspectable=0`：唯一匹配句柄1164，是自有 `appdata/FateDomination/logs/godot.log`，`directory=0`。没有观测到 source/cache/staging/published 的 FileAccess 或目录枚举残留；**这是当次快照，不是旧失败无自有句柄的证明，也不提供 GDScript 对象归属栈**。

TEB.LastErrorValue布局先在实际OS当前线程用哨兵值验证，目标TEB由 NtQueryInformationThread 获取。对成功返回保留原 LastError但 `failure_error=null`，不把残值2当失败原因。

### 引擎与DLL绑定

- 原引擎 SHA `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`；匹配PE x64导入表、两个真实 MoveFileW IAT callsite、unwind函数边界和内存指令字节，不凭未知RVA猜函数。无PDB，只报告模块/PC/RVA。
- 已审阅官方 Windows DirAccess 源 SHA `5dfc05882fb39e5e8bb10ea89ef97d5fc44299d70811cc13eaacaadb2d6a0730`；MoveFileW失败折叠FAILED，不能从FAILED=1还原系统原因。
- 正式DLL SHA `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`，PE实际唯一export `fate_server_signals_init`；并已阅读生产绑定方法定义，不杜撰直接原生API符号。
- 实际 `LOAD_DLL` 日志路径为本轮 `generated/project/addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll`，base `0x7ff84ac30000`。不是替换DLL、热重载克隆或用户editor加载路径。

## relay、退出分型和收尾

relay独占owner之前套件累计字节 `parentbudget0=0`，**不表示整个owner占用为0**。真实runtime前/后 owner字节1116594265/1310072506，低于原阈值8589934592；没有扩大阈值、缩产品limit或修全批执行器策略。

```text
CHECK 配置预检的房间初始不得绕过批准直接开局 true
CHECK gateway crash does not leave orphan authoritative process true
CHECK real service startup and requests have no engine errors true
RESULT checks=22 failures=[]
```

- pipeline归档30项artifact、12份完整日志；relay归档13项artifact、10份完整日志。终末重新读回全部43项artifact SHA，`bad_hashes=[]`；22份完整日志中的 ERROR/SCRIPT ERROR/SHADER ERROR/CAPTURE_BLOCK/second-chance events 均为[]。两份stderr都是原空字节，不省略子日志审查。
- 所有过程回执 `exited=true / active_owned_processes=0 / log_handles_released=true`；两scope Job0均true。pipeline ownership链：执行器31144→Job内 debugger5260（creation `134360828396778360`）→调试器自行 CreateProcess 的 Godot31636（creation `134360828397257023`），scope/token/引擎hash匹配。不是用 Job0虚构各子进程自然退出码。
- 编译器根37792 exit0；其Job中实际vctip23620已记录自身parent/creation/image并仅收尾该编译Job，不按进程名全局清理。该规则没有用于Godot runtime。
- 主/真实child的user://和APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR均实测物理E，worker_pool20；无权限拒绝事件，本次无SKIP。权限/前置阻断不算PASS。
- 在日志句柄释放、归档读取及SHA验证后仅回收两个自有generated，分别1599282670与1308465732字节；目前两generated均不存在。没有回收旧FAIL、正式资源、records、用户editor或其它PID。
- 离线解析器使用本次真实stdout做5个损坏对照：错误return-RVA、错误label、不同tid、越界source、不完整API对；5/5拒绝。没有新增Godot运行。

## 下一唯一可证伪假设与缺失观测点

**假设：旧正式发布偶发失败时，本进程仍持有与该 staging树相关、未共享删除的短生命周期读/枚举句柄。** 下一故障样本的必要观测点只有真实 MoveFileW return下一条指令：`RAX==0` 的同线程 TEB.LastErrorValue，及生产 `_abort→cancel→cleanup` 之前同一时刻的自有File句柄/目录身份快照。若底层是共享删除拒绝且对应自有句柄真实存在，才进入该句柄取得/释放调用链定位；若真实失败时该PID完整快照仍仅logger、父身份稳定，或底层错误不支持这一机制，就否定该假设，不能继续宣称自有泄漏。

这次没有取得上述**失败返回**观测点，仅取得成功对照；原FAIL没有Win32原错误和原时刻句柄快照。当前不足以给main生产 `DirAccess.rename` 生命周期修复建议；不添加猜测close、Sleep、warmretry、换engine或rename回退。停止追加pipeline重试，等待主代理决定如何获得下一次实际故障样本。

## 唯一写入边界

本轮仓库仅修改 `tests/validation_pipeline_performance_test.gd`，新增 `newtools/diagnostics/round60_pipeline_publication_capture.py` 和本文 `docs/round60-publication-system-error.md`。relay测试无需改写。`/tests/` 被仓库 `.gitignore:47` 忽略，普通git diff不展示这次测试变更；已经用Round58冻结源字节做实际unified diff并核对本次执行hash，仅新增诊断门，原断言不变。入口准确位于授权的 **newtools/diagnostics/**，没有另建tools下duplicate。既有assembly capture/helper/完整执行器均只读且摘要未变。
