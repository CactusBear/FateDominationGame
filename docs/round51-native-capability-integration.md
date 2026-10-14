# Round 51 native capability integration

## 结论

- 已在唯一现有 `FateProcessOwner` 生产入口内部接入 `WindowsJobLease`；没有新增第二个 ProcessOwner 或 Godot 类。
- Windows spawn 保留 UTF-8 参数编码、Windows quoting、系统随机 token，执行 `CREATE_SUSPENDED -> creation time -> lease.assign -> Entry 登记 -> ResumeThread()==1`。
- assign/resume 失败只处理本次创建且尚未就绪的精确 root，不能 resume、不能裸 PID 接管、不能 root-only 回退。
- `release` 只有新鲜 exact-Job receipt 同时证明 root `EXITED`、`active_processes == 0`，并关闭 lease root/job 与 owner 原 root/thread HANDLE 后才成功。
- 析构只关闭引用，不隐式终止 ready、未保存或 UNKNOWN 进程。
- `tree_observe` 是现 `FateProcessOwner` 的只读结构化 receipt；旧 `state` root 语义保留。
- `FateAtomicFileReplace.remove_verified` 固定调用 `TemporaryCleanupCore` 的 temporary-file 路径；identity、size、SHA-256 和 approved-root/parent 固定句柄验证仍由 core 完成，binding 不授予 archive 或任意删除策略。

## 已修改

- `addons/fate_server_signals/src/process_owner_core.hpp`
- `addons/fate_server_signals/src/process_owner_core.cpp`
- `addons/fate_server_signals/src/process_owner_binding.cpp`
- `addons/fate_server_signals/src/atomic_file_replace_binding.cpp`
- `addons/fate_server_signals/SConstruct`
- `buildmanifest/round51-native-capability-integration.json`

未修改 manager、console、ledger、descriptor、正式 DLL、Godot 引擎或运行时脚本消费者。

## 实际验证

- `python -B tools/tests/test_process_tree_owner_core.py`: **GREEN**, 5 tests, exit 0。
- `python -B tools/tests/test_temporary_cleanup_core.py`: **GREEN**, 19 tests, 1 个无 symlink privilege 的明确 SKIP, exit 0。
- 隔离 MSVC standalone owner probe: **GREEN**, `E:/FateNativeBuild-round51-red/process_owner_probe.exe`, size 340992, SHA-256 `c1a3c44ab109121bea5f0d0b624f9c9fbf4e6de38e40ea1bb34f724ef00afcfe`；真实输出证明 active=1、root exited 仍有 descendant 时 release=false、active=0 后 release=true、释放后 receipt 为 `lease_unknown`。
- 初次隔离 SCons 实际 build 先 **RED**：`process_owner_core.cpp(333) C2577`（错误析构定义）；已做最小修复后，SCons 生成了 core objects，但在完整 checked-in godot-cpp 生成阶段到达工具时间上限，未链接 DLL。
- binding direct compile 使用 MSVC `/nologo /std:c++17 /EHsc /W4 /DGDEXTENSION /D_WIN32_WINNT=0x0A00` 和现 checked-in godot-cpp include/gen/gdextension headers，仍被 `method_bind.hpp` 的 `_gde_UnexistingClass`/`C2440` ABI/header surface 阻塞；原始输出保留在 `E:/FateNativeBuild-round51-red/binding-build.raw.log`。未伪称 binding GREEN。

## 产物与运行边界

- 正式 DLL 未覆盖；本轮没有产生可交付的新 DLL。
- Godot/runtime 未启动，runtime 验证为 **NOTRUN**。
- 生产 manager 尚未消费 `tree_observe` 或 `remove_verified`，因此 source 接线已完成但运行闭环仍 **pending**；自动 cleanup 仍不能标记 complete。
- 完整 SCons DLL link、binding ABI/header 修复以及 main 串行 runtime 接线留给主 agent；不因本轮 standalone GREEN 宣称生产 runtime GREEN。
