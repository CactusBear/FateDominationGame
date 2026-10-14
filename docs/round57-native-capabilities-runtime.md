# Round57：隔离新 DLL 的真实注册与功能验收

## 总结：候选 FAIL，不能替换正式 DLL

新 MSVC DLL 已由原官方 Godot 实际加载，四类可实例化，原 13 方法及新增 `tree_observe`、`remove_verified` 均有真实绑定与调用证据。完整 fresh freeze 的官方冷导入也通过，未重现本次 AV。

但首次功能运行第四次 `spawn` 返回 `pid=-1`、非空 token，因此析构不杀未保存子树的专门案例未完成；不能把其余通过项拼成候选 PASS。控制台 DLL 的一次消费/保护功能实际通过，但安全 sender 的首次广播后自身异常退出，控制台整体验收仍 FAIL。**不建议之后直接采用当前同目录 MSVC DLL**；先修主代理确认的最小原生问题，重建到另一隔离目录，再 fresh 验证。没有覆盖正式 bin、descriptor、Godot、SConstruct、native core 或 manager。

## 固定输入与哈希复核

- 同一官方实际引擎：`D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe`，`4.7.2.stable.official.ed1daf0bf`。
- 引擎 SHA256：`ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`。
- 隔离 DLL：`E:/FateDiagnostics/round55-native-build-20261010-4/libfate_server_signals.windows.template_release.x86_64.dll`，452608 bytes。
- DLL SHA256：`58b49cfc027bb292f7e335128f41a48213834eb84eb9745ed7034bfd063f5ca0`。
- 原正式 release DLL 仍为 `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`；另外两个正式 DLL 同 round55 manifest 前后摘要，均未变。
- GDScript SHA256：`2e4b84f4348d3f95cfd68b1c0326796750984a2c650cb9bc1eae86b0a8714a86`，所有实际功能 scope 使用同一脚本。
- SDK API SHA256：`8a8386e3597083cf4357b3dbf501ede3d38a4e3f7ff75da86dfef0d1d9c3e3a8`；interface SHA256：`355ff4c6254fdd434ea16d9a8ef0f18e3f95aeb3e3f00d98db10769ece3c7fe5`。SDK API 为原 Godot 4.4 官方生成契约，host 仍为已批准 4.7.2，没有换引擎。
- 实际重新读取并匹配 round55 build manifest 的 12 个 native cpp/hpp 加 1 个已有静态库、1061 个 SDK headers、49 个独立重建 headers。不是只照抄 round55 说明。
- 完整核对结果：`E:/FateDiagnostics/round57-native-runtime-audit-20261010-1/audit.json`。每个 scope 的 `metadata.json` 另保存其驱动/CPP/脚本哈希；诊断驱动的修正版本不伪装成同一个输入。

## 真正执行过的命令与范围

各命令前缀均为仓库根下 `python -B tools/diagnostics/round57_native_capabilities_runtime.py`。实际完整 argv、精确引擎 PID/FILETIME、模块路径、退出码、raw log 保存在各根的 `result.json`、`debug.raw.log`、`build-result.json`。

| `--root E:/FateDiagnostics/…` | `--scope` | 执行结果 |
|---|---|---|
| `round57-native-runtime-20261010-1` | runtime | 诊断编译 exit 1；错误函数名 `SetDebugKillOnExit`，Godot **NOTRUN**。原件保留，诊断修正为真实 Win32 `DebugSetProcessKillOnExit`。 |
| `round57-native-runtime-20261010-2` | runtime | 首次实际 runtime，驱动/engine exit 1；158 checks：156 PASS、1 FAIL、1 SKIP；headless errors 0、second-chance engine 异常 0。未重跑此原生失败输入。 |
| `round57-native-cold-20261010-1` | cold | 唯一完整官方 fresh cold import，驱动/engine exit 0；headless errors 0、second-chance 0。 |
| `round57-native-signals-20261010-1` | signals | 新控制台 stdout 未显式传递，日志空；控制器无精确登记证据，拒绝发送；exit 1。 |
| `round57-native-signals-20261010-2` | signals | sender 默认取得自己控制台，AttachConsole 精确 error 5，拒绝发送；exit 1。 |
| `round57-native-signals-20261010-3` | signals | sender 改为 CREATE_NO_WINDOW，但未显式传递其 stdout；sender exit 5，raw 无详细阶段；exit 1，不推断 DLL 或 CRT 故障。 |
| `round57-native-signals-20261010-4` | signals | 修正只涉及诊断句柄传递及 sender 阶段日志；真实广播两次，原 DLL 功能断言通过，但首 sender exit `0xC000013A`，scope exit 1。不再运行。 |

runtime 使用新批准最小项目、没有 `--editor/--import`、无预装 extension_list，通过 `GDExtensionManager.load_extension` 显式加载。没有重试已知最小 editor/doc AV 输入。cold scope 使用现有正式 freeze 选择/变换，冻结 1424 个输入文件，**仅在该自有项目内**把 descriptor 选中的 DLL 覆盖为隔离新 DLL，descriptor 原字节不改。执行官方支持的 `--headless --verbose --rendering-method gl_compatibility --path <fresh> --editor --import` 一次。

每个 scope 从不存在的物理 E 路径开始，APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR 分别重定向至本轮根。cold 仅指项目/cache/user fresh，不声称 OS 文件缓存冷。没有 warm/import 回放、recovery mode、引擎补丁、进程内写入或升级。

## ClassDB 与真实 DLL 调用

`ClassDB.class_exists/can_instantiate/instantiate` 对四类通过，实际实例 `has_method` 查询 15 个绑定通过：

- FateServerSignals：enable、protect_worker、disable、take_request。
- FateProcessOwner：available、spawn、state、verify、terminate、release、tree_observe。
- FateAtomicFileReplace：replace_validated_file、remove_verified。
- FateCollectionIdentity：is_supported、candidate_key。

所有这些方法均在本轮功能脚本中实际调用；新增方法不是 standalone 5/18 probes、字符串或链接证明的替身。`functional.json` 保存每次检查和 native receipt。

### ProcessOwner

前三次 spawn 的真实 root/child/grandchild 分别登记 HANDLE、PID、完整创建 FILETIME，所有未保存夹具只由本轮专属 named events 自然收尾。相同哈希源的 Windows spawn 路径为 `CREATE_SUSPENDED → creation → Job assign → Entry 注册 → ResumeThread()==1`；helper 执行与 exact Job accounting 证明了实际执行这条路径，但未安装额外函数断点逐步抓取 suspended 时刻。

| 场景 | 真实 receipt / 断言 |
|---|---|
| 正常根退出 | 三代就绪 active=3；根自然 exit 0 后 active=2、total=3、root_state=exited，release=false；child/grandchild 仍活且 saved=false；明确 end event 后自然 exit 0，active=0、release=true，再查询 lease_unknown。 |
| 根 crash | 实际未处理 `RaiseException(0xE0570001)`，root_exit_code=3763798017；根退出但 active=2 时 release=false，子代活且未保存；随后专属 end event 自然退出，active=0、release=true。不是以普通 exit code 伪造 crash。 |
| 旧 terminate | 仅针对自己登记的确切 root/token/PID 调用，root exit 1；子代 active=2 且仍活，release=false；没有使用旧 terminate 杀全树；最后 end event 自然收尾后 release=true。 |
| stale token / PID / UNKNOWN | 无效 token/PID 的 observe/state/terminate/release 拒绝；空 token/-1 为 lease_unknown。证明的是未知 binding，不是通过篡改 Job HANDLE 注入查询权限故障。 |
| 析构未保存证明 | **未完成**：第四 spawn 返回 `pid=-1`，token `8b6db486205e9a6937b8cbcab65417d9`，没有把 ready 文件中的另一个 PID 修补回失败回执后继续声称通过。 |

原生 owner release 后 engine HANDLE 计数前三轮为 282、282、282；初始 baseline 280，不能从首轮增加 2 就断言泄漏或已全释放。失败 spawn 后为 286；failed owner 最终析构/engine 正常失败退出与外层 Job 归零已确认，但**没有完成该案例的活进程前后 HANDLE/析构安全观察**。不把 outer Job 归零冒充所有 owner HANDLE 的独立完整证明。

### 第一个真实阻断及下一主轮最小修复建议

只读源 `process_owner_core.cpp`：Windows 在 180 行 `entries.erase(slot)`，随后 181 行重新 emplace 到 `inserted`；但 243 行仍 `result.pid = slot->second.pid`。这是已失效迭代器的访问，静态缺陷明确，符合本次错误 PID 回执；尚未以修补 DLL 的 fresh A/B 证明它是唯一运行因果。

建议主代理只在 `inserted.second` 成功后的 Windows 分支、ResumeThread 前增加：

```cpp
slot = inserted.first;
```

或将成功结果 PID 从仍有效的 `inserted.first` 取得。Linux slot 分支不变，不改 token、Job release/析构策略，不制造 root-only fallback。**本轮没有应用该生产补丁、没有重建 DLL、没有用新 PID 修复旧回执重跑。** 修复后需要新隔离 DLL、新摘要及完整 fresh 功能验收。

### remove_verified 与旧 atomic/identity

- 15 次实际 DLL `remove_verified`，15 次独立控制器 readback；唯一允许删除的是 producer 明确声明的自有 ordinary temporary，35 bytes，返回 `deleted_absence_confirmed`、removed_bytes=35、recovery_required=false，独立读回不存在。
- 错 root / parent / file identity、错 size、错完整 SHA：分别返回 approved_root_identity_changed / parent_identity_changed / file_identity_changed / size_changed / sha256_changed，原临时内容独立摘要不变。
- 真实另一个自有进程持有 share_mode=0 文件 HANDLE：exclusive_open、native_error=32，未删；命名事件释放锁后独立重开并核对原摘要。不枚举/终止用户持有人。
- occupied directory、hardlink、leaf junction 被 regular_single_link_required 拒绝；ancestor junction 为 ancestor_not_plain_directory。occupied 内部 `protected.tmp` 仍为 `protected`，独立 SHA256 `9b2bbce6c72dd9bbd9c7a9976d5d76d1fcc2bb9832dec246375bb92006beccc3`。
- 已批准普通 parent/root 真实 rename 后创建新的同路径目录：分别 parent_identity_changed / approved_root_identity_changed，新的普通临时文件原样保留。不是删除前采集新身份自证通过。
- outside、含 `..` 非规范原始路径：outside_approved_root / unsafe_path，未归一化后授权。
- leaf symbolic link：实际 WinError1314 缺权限 **SKIP**；junction/hardlink 通过不能替代该项。没有降低普通单链接及祖先 reparse 拒绝门。
- 原 `replace_validated_file` 实际发布 11-byte `round57-new`，目标内容及源不存在性独立读回，durability_guaranteed=false。
- `is_supported` 真实批准 engine hash 通过、unsupported 拒绝；Array/Dictionary alias/distinct 与内容改变后的 candidate_key 稳定性实际通过。
- 同一 HANDLE 身份/长度/完整 BCrypt SHA/Disposition/absence readback 的实现来自已匹配编译 manifest 的 core；没有 hook 修改 native 实现。以上不授予 records、identities、archive 删除政策，更不是自动清理完成。

### 原 signals：功能通过，安全夹具总门失败

最终 scope 的 `sender-collect.raw.log` 与 `sender-protect.raw.log` 均记录：keeper/engine 完整 FILETIME 匹配、AttachConsole 成功、handler 已装、两次成员枚举均恰为 **keeper、engine、当次 sender**、GenerateConsoleCtrlEvent 返回成功。未知 console 成员不会进入广播。

实际 DLL 断言：enable=true，竞争 enable=false；首次 request=2，下一次 take_request=0；disable 后 protect_worker=true，第二次真实 CTRL_BREAK 后 take_request=0。engine 原始日志有两次 first-chance `0x40010008`，未发生 second-chance；退出后 keeper 枚举只余自身才结束，stdout 未提前关闭。没有触碰用户 editor、console 或 _console.exe 包装器。

但首次 sender 返回 `0xC000013A`（STATUS_CONTROL_C_EXIT），第二 sender exit 0，故整体不能 GREEN。夹具在 GenerateConsoleCtrlEvent 之后立即 FreeConsole，排队事件与 handler 重置有竞态。建议下一主轮最小**夹具**修正：handler 设置专属确认 event，sender 保持附着和 handler，等待真实确认后才脱离/退出；记录精确阶段，不用 Sleep 或忽略 exit code 放宽断言。该因果未以修正版再次执行证明，本轮停止。

## Job/PID、证据与清理

- 外层诊断 Job 无 kill-on-close、无 TerminateJobObject；门控子进程先 assign，才 GO 执行。每个引擎最多 180 秒预算；调试器仅自己 CreateProcess 的引擎，超时 detach，不 kill 未保存夹具。实际无引擎超时。
- 六个执行 Godot 的 scope 都读回 exact Job active=0、terminated=0、handles_released=true；登记 HANDLE 全关闭。初始失败编译未执行 Godot，其单次 raw 编译原件保留；不把该未记录 Job readback 补造为已验证。
- 运行后独立复核 12 个 fixture ready 身份（包括失败回执没有交出的真实三代 PID），精确原进程均不存活；没有裸 PID kill 或按进程名扫描/操作用户进程。
- 首次 runtime 失败的项目、CPP、ready、所有 rpc 请求/响应、native receipts 和原始日志完整留在 `round57-native-runtime-20261010-2`；全部 console 拒绝/失败也保留。
- 成功 cold 的 `.godot`、user cache、变换项目和候选 DLL 原件保存在 `generated-and-transformed-originals.zip`；479 项逐字节 SHA 验证。1421 个只读正式源副本逐项核对当前正式源相同后省略，完整 cold input manifest 保留。`archive-manifest.json` 记录最初完整归档，`archive-compaction.json` 记录后续经验证压缩/回收，不再使用已删除的完整 ZIP。
- 自有 cold `project`、`user` 实际已删除；保留 compact ZIP 146113629 bytes；相对删除前这两树净回收 411707991 bytes。未清理失败原件、其他任务或正式数据。

## 生产与发行边界

实际当前 `server_room_manager.gd` 274–326 行继续用 available/state/verify/terminate/release 旧 root 合同；scripts 中没有 `tree_observe`、`remove_verified` 消费。bootstrap/console 的 capability 合同也仍是原 13 方法。新 native 能力未接入当前观察/status/自动 cleanup；不得称 automaticcleanup GREEN。

当前新 DLL **不能直接采用**。必须先修 invalid iterator，完成未保存析构/全部 HANDLE 和安全 sender 收尾，再验证生产 manager/status 的实际接线。之后即便批准同目录 MSVC DLL，也只称新的源候选；**prod package 必须重新导出并复验**，旧导出包不因此成为发行通过。仍无多机、断电持久性、未知 Job 查询故障或完整自动回收政策的运行证明。

本轮只新增：`tools/diagnostics/round57_native_capabilities_runtime.py`、`round57_native_capabilities.gd`、`round57_native_fixture.cpp` 和本报告。工具 CLI help、Python lint、尾随空白检查实际 exit 0；新增文件的 `git diff --no-index --check` exit 1（有新文件差异），无空白错误输出。GDScript 已由实际同引擎运行，不是 Python 替身。