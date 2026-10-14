# Round47：临时单文件排他原语（不是自动清理完成）

## 交付边界

新增独立 Win32 core 与直接链接它的自有 C++ probe/Python 驱动，不带 Godot binding。
未改 SConstruct、任何既有 native 源码/DLL、manager、ledger、executor 或 policy；未升级引擎。
没有输出或制造 `exclusive_files`、`current_instances_complete` 证明。
现 executor 的 `Policy.record_error` → `DirAccess.remove_absolute` 仍有 TOCTOU，不能继续作为生产安全删除后端。

现 atomic core 的 `no_links` 是私有、只读预检，不抵抗路径竞争；没有导出的 SHA/identity/pin 原语。
新 core 不改共享 API，不复制 SHA 算法：唯一 hash helper 用 BCrypt SHA-256，字节只从排他文件 HANDLE 读取。
receipt 延续 `ok/stage/native_error` 风格，另给 `removed_bytes/recovery_required`。

## API 与授权契约

`TemporaryCleanupRequest` 必须由可信调用方显式提供：

- 物理批准根、精确单文件路径；拒绝原始非规范路径，不先 normalize 修复恶意输入。
- 批准根 identity、直接父目录 identity、目标 identity（卷序列号与 NTFS 64-bit file index）。
- 完整长度、严格 64 字符小写 SHA-256、`CleanupArtifactKind::temporary_file`。

`unspecified/archive` 被拒绝。core 不从文件名、年龄、后缀或目录名推断临时身份，
不扫描目录、枚举系统文件或递归删除；也不能发现被上游恶意误标为临时文件的存档。
正式存档保护路径、可信 producer、消费/保存/退出绑定、期限和预算必须由政策与台账继续拒绝/验证，
不得把 enum 当认证来源。

当前只支持本地固定 NTFS 卷。ReFS 需要另行设计完整 128-bit identity，不能截断后使用本接口；
非 Windows、UNC/设备命名空间、ADS、NUL、点段、尾点/空格、DOS 保留名、根自身与根外路径失败关闭。
身份必须由 producer 在真实文件完成时采集并持久绑定，不能在删除前临时采集再把新身份当旧批准证据。

## 精确 HANDLE 生命周期（给 manager/native owner）

1. 可信部署协调器与完整实例 registry 必须先阻止生命周期/批准声明变化；按统一顺序获得台账事务锁。
   这两种锁不由本 core 提供，进程内 Mutex 不能替代跨进程完整性。
2. `TemporaryCleanupLease::acquire(request, out)` 从卷根到直接父目录逐级持有
   `FILE_READ_ATTRIBUTES / FILE_SHARE_READ / OPEN_REPARSE_POINT | BACKUP_SEMANTICS` 目录 HANDLE。
   每级检查普通目录、无 reparse、真实 HANDLE 路径与请求路径一致；同时核对批准根和直接父身份。
   禁止目录写/删除共享，防止已固定祖先重命名、删除或修改为 reparse；无法固定便拒绝，不强杀持有人。
3. 目标只打开一次：`CreateFileW(GENERIC_READ | DELETE, share_mode=0, OPEN_EXISTING,
   OPEN_REPARSE_POINT | BACKUP_SEMANTICS | SEQUENTIAL_SCAN)`。
   核对 disk 类型、普通非 reparse 文件、单硬链接、identity 与 HANDLE 的真实路径。
   `exclusive_handle_acquired` 仅表示句柄已持有，不表示摘要验证或删除完成。
4. 在 lease 存活期间重新核对可信台账、完整当前实例集合、保存/退出/消费、保护路径和预算，
   持久提交精确删除意图。意图提交失败就析构 lease：不会设置 DELETE_ON_CLOSE，也不会删除。
5. 仅调用该 lease 的 `verify_and_delete()`。它以同一 HANDLE 核对 identity/size，完整读取并计算 SHA，
   再核对 metadata/最后写时刻/真实路径；不关闭重开，不调用 `DeleteFile/DirAccess.remove`。
   成功验证后 `SetFileInformationByHandle(FileDispositionInfo)`，不使用 POSIX unlink、不忽略只读位。
6. 只有 disposition 成功后才关闭目标 HANDLE 以完成删除。祖先 pins 仍存活；按精确路径重新打开，
   只有 `ERROR_FILE_NOT_FOUND` 才返回 `deleted_absence_confirmed` 和实际长度。
   若路径已重新创建，返回不确定而不是再删新文件；absence 是该次读回证据，不保证路径以后永远为空。
7. 保持 lease 的祖先 pins、台账锁与 registry 协调器直到结果持久提交。
   `recovery_required` 或结果落账失败须保留 unresolved intent，停止自动重试，不用缺文件追认成功。
   然后销毁 lease 释放所有 HANDLE。拒绝验证后 lease 仍持有 HANDLE，调用方必须明确销毁；不能泄漏 token。

lease 是 move-only；已持有对象不能重新 acquire，一次 verify/delete 后不能重试；移交后源 lease 无效。
对象不提供内部线程串行保证，binding owner 必须保证 token 不被并发调用/销毁，不能把 HANDLE 退化为布尔许可。
`delete_approved_temporary(request)` 是不需要跨审计保留 lease 的便捷入口；生产台账事务应使用显式 lease。

`recovery_required=true` 表示 disposition 已成功提交，但关闭/删除读回或后续异常未确认结果。
它不是“文件一定保留”的拒绝。成功只反映原生命名空间操作和即时读回，不声称断电持久性。
`native_error` 在 BCrypt 阶段是 NTSTATUS，Win32 阶段是 Win32 error，按 stage 解码。
共享模式排斥普通 I/O/删除持有人；不宣称抵抗内核、驱动、管理员篡改或未验证文件系统行为。

## 实测与证据

命令（180 秒短测上限，未请求用户确认）：

```text
python tools/tests/test_temporary_cleanup_core.py
```

- RED：真实链接 probe 后，正确删除测试返回 `exclusive_cleanup_not_implemented`，进程退出 1。
  证据：`E:/FateCleanupCoreScratch-9b0b9557f5794c818b4e6ca4b0fd1117/evidence.json`。
- 最后 GREEN：19 tests，18 通过、1 SKIP，0 failures/errors，10.590 秒，真实进程退出 0。
  证据根：`E:/FateCleanupCoreScratch-bb68852cb84444f4a5e725d401f68e7a/`。
  `run-summary.json` 绑定当前 header/core/probe/runner SHA；`evidence.json` 保存真实响应与拒绝文件独立摘要；
  `build.raw.log` 保留 native 编译原始字节，`build.cmd` 可读回构建命令。
- MSVC `/std:c++17 /W4 /WX /MT`，直接链接当前 core，依赖 `bcrypt.lib`，无 Godot DLL 替身。
- 两个同时存活的自有 native 进程争同一 artifact：第二个删除请求及独立读/写/DELETE open 均 error 32；
  路径删除和父目录重命名被拒绝。第一个正常 CLOSE 后可删除；未枚举或强杀外部进程。
- 自有持有人 CRASH 以自身 `TerminateProcess(GetCurrentProcess(),73)` 退出；文件字节保留，锁释放，再删除读回不存在。
- 已打开读者，以及关闭原始文件 HANDLE 后仍存在的 writable mapping，均导致 `exclusive_open/error 32`，
  持有人仍存活，主动正常关闭后可删除。mapping 夹具实际在 acquire 阶段拒绝，不能假称 disposition 阶段才拒绝。
- 错误 SHA/长度/目标身份/父身份/批准根身份、真实父目录和目标替换、硬链接、祖先 junction、leaf junction、目录、
  存档/缺临时声明、非规范路径/ADS/设备路径/同盘越界/C 根外输入和只读文件均拒绝。
  拒绝的普通文件逐项独立读回字节与 SHA；目录夹具子文件保留，不递归。
- 正确删除含空文件和多 chunk 内容；额外验证 move ctor/assignment、无效源 lease、禁止 reacquire 和单次调用。
- SKIP：普通 file symlink 创建缺权限（WinError 1314）；真实 junction 与硬链接拒绝通过，但不冒充普通 symlink 运行验收。
- 删除 disposition 成功后 CloseHandle/readback 故障分支尚未做 native 故障注入；不能声称崩溃审计整链已验收。

所有生成源码外的 build/fixture/log 都在新建且祖先无 reparse 的物理 E 根；子进程 TMP/TEMP/TMPDIR 同样指向该根。
自有 Job 先登记精确子进程，再 GO 握手授权工作，带 KILL_ON_JOB_CLOSE；只回收本驱动生成的进程树。
测试结束回收自有 exe/obj，保留小型诊断及拒绝字节作为证据，不把它们或整个 E 盘叫“清理完成”。

## 生产仍 blocked

- `missing_native_binding`：未接 GDExtension token/API、未改构建入口/DLL；现 executor 不能安全回落到按路径 remove。
- `missing_native_identity_producer`：旧临时台账记录缺批准根/父/文件 native identity，需要可信 producer 合约与持久字段。
- `incomplete_current_instance_registry`：完整当前实例集合是另一独立能力，observed bindings 不足；不能由文件排他证明。
- `missing_ledger_cross_process_transaction`：本 lease 不独占 ledger/config/registry，也不提供完整持久化审计事务。
- `symlink_privilege_unverified` 与 `post_disposition_fault_injection_unverified`：上面的实测缺口不得隐藏。

主/manager owner 完成这些门槛前，只能只读 preview，保持生产自动删除关闭。