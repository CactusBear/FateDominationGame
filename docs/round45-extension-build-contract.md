# Round45：fate_server_signals 原始构建、ABI 与初始化/清理契约复核

## 结论与边界

本轮只读生产源码、DLL、依赖和引擎文件；**未运行 Godot、未启动 debugger、未编译、未替换正式 DLL、未改引擎**。仅新增本报告和独立静态工具 `tools/diagnostics/extension_build_contract.py`；临时证据写在 `E:/Caches/Hermes/cache/scratch/round45-extension-build-contract/`。没有读取认证/签名密钥。

不能沿用“ABI 已排除 / 最小 C-ABI 控制完全合法 / 插件无问题”的旧结论。本轮得到：

1. 当前正式 descriptor 选中的是 MinGW DLL `92a42b…68cd`，不是本地 MSVC `.lib` 或旁边的 generic DLL。直接解析 PE、COFF 并静态反汇编，确认 x86-64、唯一入口、SCENE 最低等级及四类注册顺序；没有发现这些项目的实际错配。
2. 可核验的 godot-cpp 是 **`godot-4.4-stable` tag，commit `714c9e2c165db2dcb7e6ea57e62a04204d3cfbfa`**，不是今天的 `4.4` branch HEAD。远端 tag、远端 ZIP、本地 ZIP、展开后的 177 个原始文件相互核对一致。然而生产 `.sconsign.dblite` 指向另一份现已缺失的 `FateDomination/test/native-build/godot-cpp`；不能把现存诊断依赖等同于正式 DLL 的完整构建溯源。
3. **确定的静态构建契约冲突**：当前原子替换源码含 `try/catch`，而 godot-cpp 默认 `disable_exceptions=True`；MinGW 路径因此给这些源文件继承 `-fno-exceptions`。这不是“已证明正式 DLL 因异常处理而崩溃”，也不是本轮编译失败记录；本轮禁止编译。
4. **旧 raw C-ABI 控制必须降级使用**：初始化/清理等级守卫正确，也没有临时文档回调，但 `GDExtensionClassCreationInfo4` 全零后只设置 exposed/abstract，留下接口头声明 mandatory 的 `free_instance_func`（以及 ctor）为空。abstract 使实例化路径通常不发生，不等于已经证明完整遵守公共契约。这个控制不能单独承担“godot-cpp/插件 ABI 不可能有问题”的排除证明。
5. 当前 EXE 和已安装 Windows debug/release templates 的 PE 版本均为 4.7.2.0，嵌入同一引擎提交 `ed1daf0bf001b61586d9930840f2f1394092c079`。现存精确宿主 API dump 自报 single，builtin sizes 和 member offsets 与本地 4.4 API 的全套表相同。**这只是这些表的证据，不是完整 ABI 认证；正式 DLL 的全部编译 flags/precision 尚无独立构建清单证明。**

任何生产根因修复仍须由唯一 native 执行者在因果运行中证实；本报告不宣布产品 GREEN，不建议更换/修改引擎，也不把隐藏类、关闭文档、暖缓存当修复。

## 1. 实读二进制与 library 选择

`addons/fate_server_signals/fate_server_signals.gdextension:1-8`：entry=`fate_server_signals_init`，compatibility minimum=`4.4`，reloadable=false；Windows 仅有 `windows.x86_64`，**editor/debug/release 均匹配同一 template_release DLL**。Linux 指向现存 `.so`；本轮未执行或做 ELF ABI 验证。

以下结果由静态工具直接读取文件得到；完整每个 import symbol、exports、section、hash 在 `audit-final.json`。

| 实际文件 | PE/版本 | SHA-256 |
|---|---|---|
| descriptor 选中的 `bin/libfate_server_signals.windows.template_release.x86_64.dll` | machine 0x8664 / PE32+；3,579,279 bytes；无 PE version resource | `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd` |
| 未被当前 descriptor 选中的 `bin/libfate_server_signals.windows.x86_64.dll` | machine 0x8664 / PE32+；479,744 bytes；无 PE version resource | `a5990f5eeb5023c9f624e505c50cb989e66ab32e4f85b43436bb751aab6d0730` |
| `D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe`，实际 GUI engine 而非 console wrapper | machine 0x8664；FileVersion/ProductVersion 4.7.2.0 | `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424` |
| `C:/Users/Administrator/AppData/Roaming/Godot/export_templates/4.7.2.stable/windows_release_x86_64.exe` | machine 0x8664；4.7.2.0 | `d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562` |
| 同目录 `windows_debug_x86_64.exe` | machine 0x8664；4.7.2.0 | `51498b72b3a237f882ebd7d1787f06a4bc1eaf0572daab93837adcfd3cfdc107` |

正式 DLL 唯一 named export：`fate_server_signals_init`，ordinal=1，RVA=`0x5150`，无转发。直接 imports：

- `bcrypt.dll`：`BCryptGenRandom`；
- `KERNEL32.dll`：80 个导入，包括 `SetConsoleCtrlHandler`、`CreateProcessW`、`TerminateProcess`、`CloseHandle`、`SetFileInformationByHandle`；
- `msvcrt.dll`：95 个导入；
- delay-import 为空；没有依赖外部 `libstdc++-6.dll` / `libgcc_s_*.dll` / `libwinpthread-1.dll` 的直接导入。

COFF 中仍有 godot-cpp、四个正式类和静态初始化器符号；GCC producer 字符串同时有 `13-win32`、`13-posix`，说明产物包含不同 runtime 组件来源，**不据此认定 ABI 错配或线程问题**。静态 C++ runtime 不等于“无 CRT”，因为 msvcrt 仍是直接依赖。`GetProcAddress/LoadLibraryW` 的存在也意味着仅 import 表不能穷尽潜在动态加载路径。

旁边 generic DLL 的导入仅 bcrypt/KERNEL32，含 signals/owner/atomic 类名标记，未检出 collection 类名；它不是同一个 bytes，也没有被选中。文件名不代表实际 debug flags，不得拿它替代当前正式 DLL 解释结果。

`export_presets.cfg` 的已读非秘密字段：Windows Desktop、x86_64、custom_template/debug 和 release 为空；对应默认模板已实读。未声称已存在的某个发行 EXE 与这些模板相同；本轮没有重新 export 或检验任意旧发行包。

## 2. SConstruct、API 来源、precision 与 flags

### 2.1 原始依赖的精确身份

生产 `SConstruct:3-7` 只要求调用者传 `godot_cpp_dir`；错误文字说 godot-4.4-stable，**并不校验 commit/tag/API header**。外部参数可设置 `gdextension_dir`、`custom_api_file`、`profile/custom.py`、precision、target 等。

现存依赖路径：

`scratch/native-process-ownership-v6/deps/godot-cpp-714c9e2c165db2dcb7e6ea57e62a04204d3cfbfa/`

它来自 ZIP，不存在 `.git`，不能报告“本地 checkout branch=4.4”。本轮实际 `git ls-remote` 返回：

```text
b0e3b1e4b78a606f48d162898afb5eeda533d2a9 refs/heads/4.4
714c9e2c165db2dcb7e6ea57e62a04204d3cfbfa refs/tags/godot-4.4-stable
```

重新读取远端 codeload ZIP 的 SHA 与本地 ZIP 完全一致：`6faf8f6318d16368a964c457f529ca40b052eed2c0e11efe53d095c1c74e79e1`。ZIP 原始成员逐个比较：177 个文件，missing=[]，different=[]。生成文件/编译产物不是 ZIP 的原始文件，这个比较不证明它们采用了什么命令。

该依赖 `gdextension/extension_api.json.header` 与生成的 `gen/include/godot_cpp/core/version.hpp:36-40` 均为 **4.4.0 stable official**。`tools/godotcpp.py:519-528` 默认选内置 API JSON/header，但 custom_api_file 优先。`scons_generate_bindings:153-160` 把 arch 字宽和 precision 传入生成器。

**正式产物溯源缺口**：安全地用 `pickletools.genops` 查看生产 SCons 缓存的字符串，而不执行 pickle。缓存出现：

```text
/mnt/e/Projects/Godot/FateDomination/test/native-build/godot-cpp/...
E:/Projects/Godot/FateDomination/test/native-build/godot-cpp/...
/usr/bin/x86_64-w64-mingw32-g++
```

该 native-build 目录目前不存在。缓存还混有 Linux release、Windows release 和旧 MSVC template_debug 记录；只有签名/模板动作，未恢复出完整实际 expanded compile command。因此缓存不是当前 DLL 的签名构建清单。

### 2.2 当前声明的默认 flags，不冒充正式 DLL 已证 flags

- 生产 `SConstruct:8-17` 将 godot-cpp 返回的同一个 env 用于全部 `src/*.cpp`，Windows 追加 bcrypt；MinGW 追加 `_WIN32_WINNT=0x0A000002` 和 `-static-libgcc -static-libstdc++ -static`。没有单独的“业务核心异常配置”。
- godot-cpp `tools/godotcpp.py:237-245,285-303,340-342,427-484`：默认 target=template_debug、precision=single、threads=true、disable_exceptions=true。template_release 默认无 HOT_RELOAD_ENABLED/DEBUG_ENABLED/DEBUG_METHODS_ENABLED/TOOLS_ENABLED，有 NDEBUG/THREADS_ENABLED/GDEXTENSION；double 会加 REAL_T_IS_DOUBLE。
- `tools/windows.py:113-128`：MSVC TYPED_METHOD_BIND/NOMINMAX、`/utf-8`、默认 `/MT`；`common_compiler_flags.py` C++17、release `/O2`。MinGW C++17、hidden visibility、release `-O3`，缺省无 debug symbols；lto 默认 none，只有显式 auto/full 才改变。
- `common_compiler_flags.py:35-43`：disable_exceptions=true 时 MinGW `-fno-exceptions`；MSVC `_HAS_EXCEPTIONS=0` 且不自动 `/EHsc`。
- `build_profile.json` 仅 enabled_classes=[RefCounted,OS]；**生产 SConstruct 不自动启用它**。现存旧 `build_windows.cmd` 显式传 build_profile，target=template_release，arch=x86_64，use_mingw=no；该命令是 overlay 的 MSVC 构建，不是正式 MinGW DLL 的证明。其原始 log 输出 generic DLL，反映当时 overlay SConstruct 的名字，与当前 target-aware SConstruct 也不同。

现存 MSVC godot-cpp `.lib` SHA=`89e8d3fa11bddfa9f208a91238b0066650e1bec1db5c21bdde60f184b63bd9f2`。直接读 archive bytes 的 COFF directives 得到 `RuntimeLibrary=MT_StaticRelease`、`_ITERATOR_DEBUG_LEVEL=0`、DEFAULTLIB LIBCMT/libcpmt/OLDNAMES；这支持它是静态 release CRT，而不是把正式 MinGW DLL 说成 `/MT`。

### 2.3 已有 ABI 证据与不能证明的内容

- 正式 DLL 静态反汇编 `GDExtensionBinding::init`：主版本比较 4；同主版本分支在 RVA `0x68d6` 比较 minor 与 3，`ja` 接受，即 minor>=4；错误路径填入编译版本 4.4.0。这是正式二进制采用 4.4.0 版本门的直接证据，而非仅依赖目录名。
- 精确宿主现存 API dump `round39-native-report/evidence/round39-native-build/abi/extension_api.json` SHA=`d0e4c08c03b165156dabe6bfb6a906baf0069189f62035341230a246c86d6986`，本轮亲读 header 为 4.7.2/single，并用 Python 比较 **builtin_class_sizes 和 builtin_class_member_offsets 全数组均相同**。原 dump.log 亦含精确 engine hash；本轮未重新运行 dump。
- 这是 API 4.4→4.7 的前向兼容意图和尺寸表证据。minor 不同本身不是已证错配；“表相同”也不能替代 methods/hash/结构体调用约定/实际编译宏与运行时交互验证。
- 正式 DLL 没有版本资源或随包 build manifest；**没有独立取证出完整 precision、DEBUG_METHODS、HOT_RELOAD 等宏清单**。默认 single 不能升格为正式 DLL 确证 single；没有 `REAL_T_IS_DOUBLE` 字符串也不是反证，因为预处理宏可以不留字符串。

## 3. minimum、初始化等级、四类注册顺序

生产 `server_signals.cpp:97-112`：initializer 只在 SCENE 注册，minimum=SCENE，没有自定义 terminator。四类都继承 RefCounted，不存在彼此派生所要求的先后依赖。

本轮使用已安装 dumpbin **静态 disasm 文件**，不加载/执行目标：

- export RVA `0x5150` 的入口：注册 initializer 地址 RVA `0x5590`；RVA `0x517a` 的 `mov edx,2` 传给 minimum setter；setter RVA `0x8810` 将 2 写入 InitData.minimum。入口没有 register_terminator 调用。
- initializer RVA `0x5590`：`cmp ecx,2`，不等则立即返回。
- SCENE 分支：先 FateServerSignals 的模板注册；随后 call RVA `0x3ad0`（register_fate_process_owner）、call `0x1a00`（register_fate_atomic_file_replace）、tail-jmp `0x3300`（register_fate_collection_identity）。这些地址由真实 COFF 符号交叉核对。

因此 minimum、guard、顺序在**当前源码和正式二进制**之间有一致证据，不是推定正确。min-level 描述和 descriptor compatibility_minimum 是不同概念：前者为 SCENE=2，后者为 Godot 4.4。

不能仅凭旧 raw.log 出现 level=0/1 就指控提前注册：正常启动管理器可能调用所有等级，而 callback 在非 SCENE 仅记录后返回。等级违规要看该级执行的具体接口，而不是收到 callback 本身。

## 4. 文档生成 / custom class flags / 无需临时回调

本地 godot-cpp `include/godot_cpp/core/class_db.hpp:254-280` 的 `GDREGISTER_CLASS` 最终填 `GDExtensionClassCreationInfo4` 并调用 v4：普通类 exposed=true、runtime=false、abstract=false、virtual=false；生产四类没有自定义 property getter/setter 列表或文档注册源码。

- 临时 `class_info` 位于调用栈是该接口正常用法：精确宿主 `gdextension.cpp:362-399,447-574` 的 v4 adapter 把参数转换并拷入宿主 Extension。不能把 stack lifetime 本身判为悬空。
- godot-cpp `src/godot.cpp:523-527,595-603` 只在 EDITOR 且 DocData valid 时加载可选压缩 XML；生产 SConstruct 未调用 GodotCPPDocData，`src` 无生成文档 `.cpp`。**可选 XML 和宿主从 ClassDB 生成扩展文档是不同路径。**不需要补临时 documentation callback 来让 exposed 类合法。
- 已从精确引擎 commit 原始文件重新校验：`editor/doc/editor_help.cpp` SHA=`52ec5bc7720d7f35d61d99a35354bddae8eb23963c8da06abc4f449e5571725e`；`doc_tools.cpp` SHA=`fea7f42d2fd591104c374777f2c69ff91ab65c78fc5a02b6618000420279bae5`；`core/extension/gdextension.cpp` SHA=`a7f2f64bd1b05461f430ab499a5d2e4d87913179b2cbca223b9aa90a9c7a1d8b`。远端 raw bytes 与归档源码完全一致，不是以旧报告替代原文。
- `EditorHelp::_gen_extensions_docs:3083-3089` 传 `SKIP_BASIC_TYPES | EXTENSION_CLASSES_ONLY`；亲读同 commit doc_tools.h，分别是 bit0/bit1，因此值=3。这里的 custom 指扩展类来源，不是“必须有 custom doc callback”。
- `DocTools::generate:430-452` 取扩展类列表、跳过 not exposed 类，然后写 class_list。缺少插件 XML 不妨碍该路径。把 exposed=false 隐藏类确实改变覆盖范围，不是保能力修复。
- 同源码 `cleanup_doc:3365-3368` 删除 doc 并置空，`_gen_extensions_docs` 未检查空。这个静态危险点成立，但**本轮没有新的因果运行**；历史生命周期 trace 必须与合法控制/实际生产 frozen binary 的运行分开审查。

## 5. uninitialize 与资源生命周期

### godot-cpp 管理的资源

`src/godot.cpp:494-497` 始终给引擎设置 `deinitialize_level`，与有没有插件 terminator 不是一回事。`deinitialize_level:531-544` 先执行可选用户 terminator，再按每级引用计数调用 EditorPlugins/ClassDB deinitialize。

`src/core/class_db.cpp:405-447` 逆 `class_register_order`，仅注销当前级 class、删除 MethodBind、移除 order；CORE 还有 singleton instance-binding 释放。按源码顺序，SCENE 清理是 identity→atomic→owner→signals。**没有用户 terminator 不等于没有类注销；额外手工注销可能造成重复注销。**但这里仍是已核对依赖实现，不是已完全追踪正式 DLL 所有 teardown 指令。

### 插件自己的资源

- signals：文件静态仅 lock-free atomic pending_signal/collect_requests 和 owner 指针；handler 仅 atomic 操作。`enable/protect_worker` 才注册 Windows handler；构造不注册。`disable` 与析构注销 handler/清 pending；POSIX 还恢复旧 sigaction。Windows 的 `SetConsoleCtrlHandler(nullptr,FALSE)` 清忽略标志后没有保存/恢复旧忽略策略，这是行为差异，不是本次 cold-import 根因证据。插件没有全局终止回调主动收尾仍存活 owner，故正常 RefCounted 销毁仍是必要生命周期条件。
- owner：`ProcessOwner` 为类实例成员，mutex/map 默认为空；没有静态 ProcessOwner 或注册时 spawn。`available` 才调用 BCrypt；`spawn` 才创建进程和保存 handle。`~ProcessOwner:259-262` 遍历 stop/dispose；stop 等待最多 5 秒且可失败，析构不汇总失败。未销毁实例/存活子进程的真实退场边界需单独运行核验，不能由注册完成推定。
- atomic：没有文件静态资源实例；Handle/Fd 是方法局部 RAII，只在实际 replace 调用中打开/关闭。注册/默认构造不应触发 rename。此结论来自原始源码，不是行为验收。
- identity：注册不调用 is_supported/candidate_key；只有方法里创建 Array/Dictionary。opaque 存储复制受 sizeof=8 编译门、engine hash 前缀 `ed1daf0bf` 和 is_same 实测门约束；运行门是否实际被调用/通过本轮未验。
- godot-cpp 自身有静态 ClassDB maps、注册 order、mutex、InitDataList，以及 GDCLASS 的 name/bind cache。正式 COFF 确有 `_GLOBAL__sub_I…` 初始化器，不能说“DLL 没有静态对象”。这些 empty containers/CRT 初始化与已登记 Godot StringName 的最终析构必须按进程卸载顺序验证；本轮没有发现能由源码单独证明的越级引擎调用，也不把“没发现”写作无副作用证明。

## 6. 亲读独立 C-ABI control：哪些有效，哪些不能拿来排除

原始文件：`E:/Caches/Hermes/cache/scratch/round39-native-report/evidence/round39-native-build/raw-class.cpp`，SHA=`53659d9fb61cd59c19c16c8ffa10e244533cd286b81b2ac2e8998107cd697d20`。

逐项结果：

- entry 只保存 get_proc/library，写 initialization 的 minimum=SCENE、userdata=null、initialize/deinitialize 指针；不在 entry 造 StringName 或注册类。
- initialize:9 先 SCENE guard；之后才查构造/注册接口、创建持久存储的 StringName 并注册唯一 exposed abstract RefCounted 子类。parent 已在 SCENE 存在，flags.is_runtime 缺省0，不需要 Godot-cpp。
- terminate:19 同级 guard，先 unregister，再对两个 StringName 调用正确 Variant destructor。uint64_t 存储在 x86_64 下为8字节/8字节对齐，已核对的 API sizes 表里 StringName=8。这个实现不是跨32位保证。
- `build-raw.cmd` 实读为 MSVC `/utf-8 /EHsc /O2 /MT /LD`，只 include interface header，没有链接 godot-cpp `.lib`。因此“未链接 godot-cpp”有源码/构建命令证据。
- **契约不严密点**：`info{}` 后只设 exposed/abstract；interface.h:385-386 明示 ctor/destructor mandatory；它没有 free_instance_func。抽象标志意味着无需真实创建实例，ctor-null 的文字存在解释空间，但 destructor mandatory 没有同样写明豁免。精确宿主 adapter 接受这些空值并保存，不做 mandatory guard，并不能替代契约合规证明。`get_virtual_func`/alternative 也为空，头文件写 should supply；严谨控制应显式提供“不覆盖任何 virtual”的返回-null 回调。
- 未查空的 get_proc 返回值也降低控制健壮性；当前宿主注册 log 能说明相关构造/注册接口实际可用，不能推导所有 teardown 接口一定可用。
- **没有 custom docs callback / compressed XML 并非违规**。注册信息里根本没有必须由 raw 控制提供的文档生成函数。

历史 raw `debug.log:64-68` 记录 level=0/1/2/3，注册只在2；125-148 记录 second-chance `0xc0000005`、doc=0、读取8、宿主RVA `0x53fd042`、进程退出。原始现象是真实记录，但**不能用仍欠 mandatory callbacks 的最小控制作为完整合法反证**。本轮不篡改旧报告；它的强归因应由新合法控制收紧后再评估。该瑕疵本身也尚未证明导致 doc=null。

## 7. 确定错配 / 可修位置 / 不是根因的缺口

| 分类 | 原始来源 | 具体可修位置与限制 |
|---|---|---|
| 确定的当前源码默认构建冲突，未证明是运行崩溃根因 | atomic_file_replace_core.cpp:33,108-109 的 try/catch；godotcpp.py:340-342；common_compiler_flags.py:35-43；生产 SConstruct 共用 env | 若 native 执行者证明受影响构建路径真实 RED，再在 SConstruct 的业务核心编译 env 显式安排异常策略，或在源码采用 error_code-only API；不改神秘 CRT/不随意重建正式 DLL。本轮不选生产修法。 |
| 确定的旧 raw 控制契约缺口，不是已证崩溃因果 | raw-class.cpp:13-14 对 info 零初始化；公共 header:385-395 | 仅在独立控制副本补精确签名 ctor/free/get_virtual 回调、接口返回值与单次初始化/反初始化守卫；按下面最短对照串行重跑。不能改生产 DLL来替控制补缺。 |
| 确定的构建来源缺失 | 生产 .sconsign 指向现已缺失 native-build/godot-cpp；现存依赖是另一 MSVC overlay 来源 | 未来获准构建时由构建入口显式记录实际 tag/hash、API/header hash、展开后的编译/链接命令、precision/target/arch 与产物 hash；当前只能标记无法完整溯源。 |
| 确定的声明不足，尚无已部署 precision 错配证据 | SConstruct:14-15 名称不包含 precision；内部 godot-cpp suffix 却含 .double | double 构建会与 single 共用插件输出文件名；如将来允许 double，须隔离名字/descriptor feature或显式拒绝；目前不能凭此断言正式 DLL 是 double。 |
| 非确定错配：debug/editor 加载 release DLL | descriptor windows.x86_64 统一选择 release；godot-cpp 注释区分 targets | 只有捕获实际 macro-sensitive 调用问题后才能改选择策略。不得仅因名字不同定罪；当前没有 template_debug DLL匹配不等于必然崩溃。 |
| 已核实相同项，不等于全 ABI 正确 | machine、entry、minimum/guard/order、当前 engine/template versions、builtin sizes/offsets | 不需要为了“排查”改这些项；后续合法运行检查实际回调/对象析构/文档队列才有根因信息增益。 |

## 8. 给唯一 native 执行者的最短对照建议（本轮没有执行）

保持同一精确 `ab1824…22424` 宿主、同一启动参数、fresh 目录、相同文档缓存状态与 descriptor 特征，**串行**执行以下最小三组；不要并发运行或修改生产 DLL：

1. 已获准的现正式 DLL 冻结副本重现，记录 descriptor/DLL hash、SCENE/EDITOR 初始化与 SCENE 退场、cleanup_doc 与 deferred docs 的真实先后。
2. 合法的 direct C-ABI exposed abstract 类控制：minimum=SCENE；所有 StringName 构造/注册在SCENE，注销后再析构；给 CreationInfo4 填精确签名 mandatory ctor/free（抽象类 ctor 返回nullptr，free为不拥有实例的no-op），并给 get_virtual 返回nullptr；API返回值检查失败则 init明确失败。无方法、无XML/文档回调、无 godot-cpp、无全局 Godot对象。不要只追加日志而继续用旧全零callbacks控制。
3. 与2相同，唯一差异为不注册类；保留同级初始化/清理框架。解释结果时区分“未产生扩展文档工作”和“某能力正常”。

控制2仍须先用源码/官方契约确认抽象类 callback 选择合法。若要求完全消除抽象解释歧义，可改用小型真实可实例化类，正确实现 construct_object/object_set_instance/free，绝不能返回伪造对象指针。严禁为了避免文档故障给引擎补临时 callback 或把 exposed 改false后宣称等价。

若2与1同样在 cleanup后触发 docs/doc=null，而3不触发，可提升“独立于godot-cpp业务实现、与exposed类文档队列有关”的证据强度；若2不崩，则旧 raw 对照无效，继续分离 mandatory callbacks、flags和初始化/析构顺序。即使同RVA，也须读取真实寄存器/对象生命周期，不能由RVA相同直接宣布生产修复点。

异常 flags 的 build-only 对照应等到该执行者获准编译诊断副本再做；本轮不启动它。任何候选生产修复必须准确 RED → 单变量改变 → 同版本fresh GREEN → 完整能力回归，才能进入修改。用户明确拒绝改/换引擎，本轮遵守。

## 9. 工具、实际命令与验收缺口

独立工具只用 Python stdlib；`--pe` 重复指定文件，直接读 PE machine/export/import/delay import/resource 固定版本/COFF标记；`--godot-cpp --archive` 核对 API header/hash 和ZIP成员。没有 ctypes.LoadLibrary、subprocess、Godot入口或编译入口。输出必须是E盘新文件，已有输出拒绝覆盖。

实际运行（exit 0）：

```text
python -B tools/diagnostics/extension_build_contract.py --godot-cpp scratch/native-process-ownership-v6/deps/godot-cpp-714c9e2c165db2dcb7e6ea57e62a04204d3cfbfa --archive scratch/native-process-ownership-v6/godot-cpp.zip --pe addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll --pe addons/fate_server_signals/bin/libfate_server_signals.windows.x86_64.dll --pe D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --pe C:/Users/Administrator/AppData/Roaming/Godot/export_templates/4.7.2.stable/windows_release_x86_64.exe --pe C:/Users/Administrator/AppData/Roaming/Godot/export_templates/4.7.2.stable/windows_debug_x86_64.exe --output E:/Caches/Hermes/cache/scratch/round45-extension-build-contract/audit-final.json
```

另实际用 Python assertions 校验已读PE机器、唯一入口、imports、无delay、COFF initializer RVA、SCENE immediate机器码、模板resource版本，并拒绝三种 malformed 输入，exit0；复用已有output执行实际 exit2（外层断言该预期退出，exit0）。这些是工具静态读验收，不是 native runtime GREEN。

静态 disasm工具：`D:/VS2022/VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/dumpbin.exe /nologo /disasm:bytes /range:<VA_START>,<VA_END> <formal DLL>`。证据 `production-disasm.txt` 保存入口、SCENE guard/顺序、4.4版本门和minimum setter，均针对表中正式DLL的image_base `0x2e19d0000`，不得直接挪用到另一hash。

最后门禁：**静态审计已完成；新的合法 C-ABI运行、完整正式构建溯源、生产异常因果与修复验证仍未完成。** 没有借用旧报告结论掩盖这些缺口。
