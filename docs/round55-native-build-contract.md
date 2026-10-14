# Round55：原生编译契约与隔离交付

## 结论与验收范围

- 已真实重现两个 binding 的 MSVC 编译阻断，并以**同源码、同 include、只补官方必需参数**消除；不需要改 binding API，更未修改 SDK 模板。
- 已复用既有同来源 MSVC 静态库，只编译插件现有全部翻译单元并链接新 DLL。没有下载、升级引擎、重建全量 godot-cpp。
- `laststage=COMPLETE_BUILD_ONLY_RUNTIME_NOTRUN`。**Godot 冷导入、ClassDB 运行时方法查询、正式服务运行、startup/warm 均 NOTRUN**，交主代理串行验证。不能称为生产 GREEN。
- 本轮仓库新增 `tools/diagnostics/round55_native_build.py` 与本说明；没有修改 SConstruct、两个 binding 或任何 core。SConstruct 已从官方 SDK env 继承必要 MSVC 参数，无需再重复追加。
- 正式 bin、descriptor、Godot、manager、console、default15 均未改动。

## 产物与证据

证据根目录：`E:/FateDiagnostics/round55-native-build-20261010-4/`

- DLL：`libfate_server_signals.windows.template_release.x86_64.dll`
- SHA256：`58b49cfc027bb292f7e335128f41a48213834eb84eb9745ed7034bfd063f5ca0`
- 大小：452608 bytes；PE machine x64；导出 `fate_server_signals_init`。
- `tree_observe`、`remove_verified` 的 decorated binding object symbols 及 DLL 方法名字符串均存在。**这不是运行时注册验证**。
- `manifest.json` 保存原始输入/源码/全部 SDK headers/重建 headers/库/对象/DLL 哈希、实际命令及退出码；`command_files` 保存每个 `.cmd` 完整文本，`link_response` 保存完整响应文件文本。不得只照本说明的示例替代实际命令证据。
- `exclusive-job-link.raw.log` 与 `exclusive-job-pe.raw.log`：最终链接和 PE 检查均退出 0，在 gated exclusive Win32 Job 中实际执行，关闭后仅清理自有诊断 Job；保留最终哈希对应的日志。

正式 DLL 前后 SHA256 相同：

| 正式 bin 文件名 | SHA256 |
|---|---|
| `libfate_server_signals.windows.template_release.x86_64.dll` | `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd` |
| `libfate_server_signals.windows.x86_64.dll` | `a5990f5eeb5023c9f624e505c50cb989e66ab32e4f85b43436bb751aab6d0730` |
| `~libfate_server_signals.windows.template_release.x86_64.dll` | `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd` |

## 原始日志及 A/B

亲读 `E:/FateNativeBuild-round51-red/binding-build.raw.log`：read_file 将其识别为 binary；随后保留全部原字节，严格按 GBK 解码至独立 UTF8 副本。原始日志 SHA256：

`5de938c7412efc22afca2981d00aaf597654881f55ba45d20b3cfd8543988f04`

第一类错误是 `method_bind.hpp` 507/591 的 C2440 成员函数指针 reinterpret_cast；后续 C2512/C2672 是同一实例化上下文。代码页 936 的 C4819 另有明确日志，不以乱码推断错误。

A 使用上一 directcl 核心参数（输出路径改为本轮独占目录）：

```text
cl /nologo /std:c++17 /EHsc /W4 /DGDEXTENSION /D_WIN32_WINNT=0x0A00 <原四个 /I> /c <同一源码> /Fo:<独立对象>
```

B **只追加**：

```text
/DTYPED_METHOD_BIND /DNOMINMAX /utf-8 /MT
```

| binding | A | B |
|---|---:|---:|
| process_owner_binding | 2，C2440/C2512/C2672 | 0 |
| atomic_file_replace_binding | 2，C2440/C2512/C2672 | 0 |

A/B 同一源码 SHA256、同四个 include 路径，未更换 API/generated headers。只能据此证明缺官方构建参数足以造成/消除编译阻断；没有把四个参数的独立贡献逐个消融，不能声称 `/utf-8` 单独修复了模板错误，也不能声称头文件 ABI 错配。

## 官方环境与库来源

SDK：`scratch/native-process-ownership-v6/deps/godot-cpp-714c9e2c165db2dcb7e6ea57e62a04204d3cfbfa`

- API header 实读：Godot Engine v4.4.stable.official。
- API JSON SHA256：`8a8386e3597083cf4357b3dbf501ede3d38a4e3f7ff75da86dfef0d1d9c3e3a8`。
- gdextension_interface.h SHA256：`355ff4c6254fdd434ea16d9a8ef0f18e3f95aeb3e3f00d98db10769ece3c7fe5`。
- 已有 `.lib` SHA256：`89e8d3fa11bddfa9f208a91238b0066650e1bec1db5c21bdde60f184b63bd9f2`。
- 实际 compiler：`D:/VS2022/VC/Tools/MSVC/14.44.35207/bin/HostX64/x64/cl.exe`。SCons 报 `MSVC_VERSION=14.3` 是工具家族字段，不替代实际 compiler 路径版本。
- 库实际 COFF archive 的 61 个成员逐一匹配历史 `.sconsign` 对象 MD5；整个库匹配历史 target MD5，所有当前原始 SDK 源码/headers 匹配缓存官方 commit zip。不存在仅凭文件名认定精度/CRT。
- archive 实读 `RuntimeLibrary=MT_StaticRelease`、`LIBCMT`、`libcpmt`。
- 实际官方 SCons dry-run 以 single/template_release/x86_64、同 build profile 构造动作：历史 godot object action signature 精确匹配 `16b07097f8e6b6cf97b5957593e73048`；见 `historical2.cmd`、`historical2.raw.log`、`historical-action-contents.raw`。

| 项目 | 历史库实际匹配官方 env | 当前插件官方 env |
|---|---|---|
| CCFLAGS | `/nologo /utf-8 /MT /O2` | 同左 |
| CXXFLAGS | `/TP /std:c++17`，禁用 exceptions | `/TP /std:c++17 /EHsc`，项目 SConstruct 显式开启 |
| CPPDEFINES | TYPED_METHOD_BIND、NOMINMAX、WINDOWS_ENABLED、THREADS_ENABLED、NDEBUG、GDEXTENSION、`_HAS_EXCEPTIONS=0` | 同样六个主宏，不声明 `_HAS_EXCEPTIONS=0` |
| precision / target / arch | single / template_release / x86_64 | 同左 |
| HOT_RELOAD_ENABLED | 未声明 | **不得手加** |
| LINKFLAGS | `/nologo /WX /OPT:REF` | 同左；实际隔离 link 另显式 `/MACHINE:X64`、map/importlib/output |

库不抛异常的构建策略与插件显式 /EHsc 分开记录，不伪装成相同 exception policy。

### 历史 generated headers 的恢复证据

当前 SDK gen 与库历史依赖大多只是 CRLF/LF 不同；此外 resource header 比历史 trimmed profile 多了 Node forward declaration/get_local_scene。不能因此跳过来源门。

使用同一官方 generator、API 和仓库 `build_profile.json`（enabled_classes RefCounted/OS）在本轮 scratch `official-profile-reconstruction/` 重建；重建资源头及涉及依赖的 LF 字节 MD5 精确匹配历史签名。最终插件使用该独立重建 gen/include 与原 SDK include/gdextension；SDK 原 headers、模板和源码没有编辑。A/B 仍始终使用原 include，不混淆两个实验。

## 全部翻译单元与链接

当前目录实际只有八个 cpp，而非“六 core＋四 bindings”：四个专门 core、三个独立 binding、一个 signals class binding/entry。全部均已链接，没有制造缺失的两个 core：

```text
atomic_file_replace_core.cpp
process_owner_core.cpp
process_tree_owner_core.cpp
temporary_cleanup_core.cpp
atomic_file_replace_binding.cpp
collection_identity_binding.cpp
process_owner_binding.cpp
server_signals.cpp
```

manifest 保存每个 cpp/hpp 完整哈希及全部命令。最终四个 class binding 编译参数为：

```text
/nologo /std:c++17 /EHsc /W4 /DGDEXTENSION /D_WIN32_WINNT=0x0A00
<SDK include、独立重建 gen/include、SDK gdextension、插件 src 四个 /I>
/DTYPED_METHOD_BIND /DNOMINMAX /utf-8 /MT /O2
/DTHREADS_ENABLED /DNDEBUG /DWINDOWS_ENABLED
```

第一链接策略手加 HOT_RELOAD_ENABLED 导致 Wrapped::_constructing_recreate_owner 缺符号；对照已捕获官方 env 后只去掉此非官方宏、重编译四个 binding，第二策略链接退出 0。没有第三次编译策略，也未重建 godot-cpp。

另一个真实诊断包装问题：初版名为 link.cmd，cmd.exe 优先命中当前目录批处理，递归至“输入行太长”。已换 `plugin-link.cmd` 与绝对 link.exe，并使用响应文件。此项不是 SDK、ABI 或 native core 问题；全部失败日志保留。

## Standalone 与未运行门

实际执行：

```text
python tools/tests/test_process_tree_owner_core.py
python tools/tests/test_temporary_cleanup_core.py
```

- tree：5 tests，5 passed，exit 0；证据 `E:/FateProcessTreeProof-b384a2d0ed004b49b6007230f4dbdc2a`。
- cleanup：19 tests，18 passed、1 skipped，exit 0；证据 `E:/FateCleanupCoreScratch-f2d91d68c5e24a8bb47251026741f3a9`。leaf symlink 因 WinError1314 缺权限 SKIP；hardlink、leaf/ancestor junction 正负测试实际通过，未放宽断言。
- 核心/绑定源、SDK headers、已有 .lib 和正式 DLL 前后哈希均未变。
- 待主代理：保持原 default15 引擎，以新 DLL 的独立项目串行冷导入，查询四类及 `tree_observe/remove_verified` 真实 ClassDB methods，再验证原生能力和正式调用链。绝不能用字符串存在替代注册或功能测试。

## 后续重现入口与边界

```text
python tools/diagnostics/round55_native_build.py --output E:/FateDiagnostics/<new-exclusive-directory> --stage build
```

脚本拒绝已存在输出和 reparse E 路径，以唯一文件锁序列化，gated CompileJob 覆盖后续子命令，600 秒单轮总截止；失败即停止，不自动重试，不启动 Godot。初次编译实际为串行 bounded subprocess；最终交付链接/PE 已真实放入 exclusive Job。修正后的 Job runner/绝对链接器路径均实跑过；修正后没有再次全量编译重放，以遵守本轮最多两个编译策略。
