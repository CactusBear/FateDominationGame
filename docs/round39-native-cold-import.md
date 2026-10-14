# Round39 native 冷导入：精确根因在宿主 editor 文档析构

## 结论

**ROOT_CAUSE_CONFIRMED / FIX_BLOCKED_OUTSIDE_PLUGIN_SCOPE，不是发行验收。**

本轮不再只重复 import 报告：自建 Windows debugger 已捕获准确自有进程的 second-chance 异常、所属模块、寄存器和调用栈，并用自有进程内的一次性断点证明：

> Godot 4.7.2 的 `EditorHelp::cleanup_doc()` 已销毁文档对象并把 `doc` 置空；随后排队的 `EditorHelp::_gen_extensions_docs()` 仍调用 `doc->generate()`。`DocTools::generate()` 对空对象的 `class_list`（偏移 8）写入，最终在 Godot RVA `0x53fd042` 读取地址 `0x8`，second-chance `0xC0000005`。

四个正式 class 分别单独注册都会触发相同故障；零类注册不触发；不链接 godot-cpp、没有任何方法的直接 C-ABI 空抽象类也触发同一宿主故障。因此它不是 process-owner、atomic、collection 的业务方法触发，不是“缺少 terminator 导致插件未注销”，也没有依据用换 DLL / 删类 / 隐藏能力 / 预造暖缓存修复。

**正式 native 源码、SConstruct、descriptor、Windows DLL、Godot 和 release 工具均未修改。没有新正式 DLL，也就没有新 DLL 哈希、两次 fresh GREEN、export 或核心能力回归通过声明。**

## 1. 准确 second-chance 证据

归档根：`E:/Caches/Hermes/cache/scratch/round39-native-report/`。

`evidence/round39-native-c/debug.log`：

- 自有 PID `23468`，线程 `6812`；`first_chance=0`。
- fault VA `0x7ff65619d042`，模块 `Godot_v4.7.2-stable_win64.exe`，RVA `0x53fd042`。
- exception parameters `[0, 8]`：读取地址 `0x8`。
- `RIP=0x7ff65619d042`，`RBX=8`，`RSP=0x1da4bfee40`；其余通用寄存器及 EFLAGS 均在原日志及 `parsed-events.json`。
- 指令 bytes `48 8b 2b`，即 `mov rbp, qword ptr [rbx]`。
- 精确自有进程退出 `0xc0000005`，未超时。

调用链按本地 PE unwind 信息展开；以下名称来自准确引擎提交源文件及本地反汇编交叉定位，**不是 PDB 已解析符号**：

| 栈中模块 RVA | 对应路径 |
|---|---|
| `0x53fd042` | class 文档 HashMap 操作，接收者为地址 8 |
| `0x178b95c` | `DocTools::generate`，`class_list[name] = DocData::ClassDoc()` |
| `0x1792855` | `EditorHelp::_gen_extensions_docs` 调用 `doc->generate(flags=3)` 后的返回地址 |
| `0x3e0e832` | `CallQueue::_call_function` 的 deferred callable 调用 |
| `0x3e0ea39` | deferred message queue flush |

另外还有宿主主循环及 `BaseThreadInitThunk` / `RtlUserThreadStart` 栈帧。Godot 没有本地完整 PDB；DbgHelp 给出的远距离最近 export `NoHotPatch+...` 不能解释为真实故障函数名。原日志保留它，报告不使用它归因。

## 2. 生命周期顺序直接验证

`evidence/round39-native-lifecycle/debug.log`，自有 PID `27228`：

```text
TRACE rva=0x17aba60 watch_rva=0x66dcc10 value=0x22ff6322c00
TRACE rva=0x1792840 watch_rva=0x66dcc10 value=0x0
EXCEPTION pid=27228 tid=13736 first_chance=0 code=0xc0000005 ... address=0x7ff65619d042
WATCH rva=0x66dcc10 address=0x7ff65747cc10 value=0x0
EXIT pid=27228 code=0xc0000005 timedout=0
```

- `0x17aba60` 为文档 cleanup 路径入口；该函数内 `0x17abc7b` 对同一全局 `doc` 地址显式写入 0。
- `0x1792840` 的指令读取同一全局 `doc`，随后以 flags=3 调用 `DocTools::generate`；入口现场已经为 0。
- `DocTools::generate` 从空 `this` 取 `class_list` 地址，反汇编明确为 `lea rbx,[rax+8]`，随后传给 fault 函数；与现场 `RBX=8` 完全吻合。
- 普通只读 watch 捕获 `round39-native-doc-watch`（PID `4276`）也读到 `doc=0`，并同地址 second-chance；不是软件断点制造了该现象。
- 诊断全类/单类日志显示 entry 成功、CORE/SERVERS/SCENE/EDITOR 初始化完成；每个注册 begin/end 均完成，崩溃前尚未进入扩展 terminate 回调。

源码对应实际引擎提交 `ed1daf0bf`，仅下载定位所需的少量源文件，未下载完整引擎/SDK：

- [`editor/doc/editor_help.cpp`](https://github.com/godotengine/godot/blob/ed1daf0bf/editor/doc/editor_help.cpp)：`3031–3044` 从文档缓存加载线程排队 deferred 文档任务；`3083–3088` 无空检查调用 `doc->generate`；`3365–3368` cleanup 等待线程、删除对象、清空 `doc`。
- [`editor/doc/doc_tools.cpp`](https://github.com/godotengine/godot/blob/ed1daf0bf/editor/doc/doc_tools.cpp)：`422–453` 枚举扩展类并写入 `class_list[name]`。
- [`editor/editor_node.cpp`](https://github.com/godotengine/godot/blob/ed1daf0bf/editor/editor_node.cpp)：`629–634` 扩展变化重建文档，`9640` editor 析构调用 cleanup。

本轮直接测量了 cleanup 与 deferred 执行的先后和指针值；没有给文档缓存线程的每次入队时间另设断点，不捏造更细的调度时刻。

## 3. 注册单变量实验

全部构建使用同一本地 godot-cpp 4.4 template_release `.lib`、相同四类源码和日志 instrumentation，仅注册掩码不同；构建产物只写 E 盘诊断副本。每个候选只有一次全新目录冷导入。

| 掩码 / 注册 | 自有 PID | 真实退出 |
|---|---:|---|
| 15：全部四类 | 26772 | `0xc0000005`，同 RVA |
| 0：不注册类 | 25844 | `0x00000000`，完整 terminate 3→0 |
| 1：FateServerSignals | 3184 | `0xc0000005`，同 RVA |
| 2：FateProcessOwner | 15092 | `0xc0000005`，同 RVA |
| 4：FateAtomicFileReplace | 19008 | `0xc0000005`，同 RVA |
| 8：FateCollectionIdentity | 31680 | `0xc0000005`，同 RVA |

零类结果仅是最小化对照，**不是可以发布的 DLL，也不是能力回归 GREEN**。

独立反证 `round39-native-raw`：仅包含一个 exposed abstract `RefCounted` 子类，直接调用公共 C ABI `classdb_register_extension_class4`；无 godot-cpp 链接、无方法、无 owner/atomic/identity/signal 实现。entry / class registration / EDITOR 初始化均完成，此后同一 `0x53fd042` 读取 8、`doc=0`、second-chance，真实退出 `0xc0000005`。原始源码为归档 `evidence/round39-native-build/raw-class.cpp`，完整原始 log 和 parsed events 保留。

## 4. godot-cpp / 引擎 ABI 与构建特征

- 复用原有依赖：`scratch/native-process-ownership-v6/deps/godot-cpp-714c9e2c165db2dcb7e6ea57e62a04204d3cfbfa/`；API header 自报 4.4.0 stable official。
- 实际引擎运行 dump：4.7.2 stable official，`precision=single`；`--dump-extension-api --dump-gdextension-interface` exit 0。所有 builtin size 配置表与本地 4.4 JSON 相同，包括 Array/Dictionary opaque 存储。**尺寸一致不是全 ABI 的无限版本承诺**。
- 4.4 bindings 使用 class registration v4；4.7 引擎当前实现保留公共兼容入口，直接 C-ABI v4 也能注册完成后重现此故障。godot-cpp 版本差异并非本故障必要条件。
- 本地 godot-cpp build 配置：template_release 默认无 `DEBUG_ENABLED` / `DEBUG_METHODS_ENABLED` / `HOT_RELOAD_ENABLED`，启用 `NDEBUG`、`THREADS_ENABLED`、`GDEXTENSION`；template_debug/editor 才有相应 debug features。诊断按现有 release 库匹配，不用“文件名叫 debug”猜实际 ABI。
- 诊断工具链为已安装 MSVC 14.44 / Windows SDK；现有 `.lib` 为 `/MT`。早期手工构建少了 `/utf-8` / `TYPED_METHOD_BIND`，随后 `/MD` 与 `/MT` 不匹配，均真实失败并归档；按依赖的实际标志修正后六个诊断 DLL 均构建 exit 0。
- 正式旧 DLL 是已有 MinGW 静态 runtime 产物（导入 bcrypt/kernel32/msvcrt）；MSVC 全注册对照仍相同 RVA RED，不能据此给编译器或 static CRT 定罪。
- 未重建/修改现有依赖树；未安装新大型 SDK。仅独占分析目录临时使用 capstone/pefile（capstone 下载约 1.2 MiB），归档完成后已回收。

## 5. 诊断器、命令与测试

新增 `tools/diagnostics/native_cold_import_debug.py`：使用已有 MSVC 编译内嵌小型 C++ debugger，通过 `DEBUG_ONLY_THIS_PROCESS` 创建实际 GUI 引擎，不 attach 已有 PID、不调试 console wrapper 的未登记后代。持有准确进程句柄及 creation FILETIME；模块范围由 PE headers 读取；DbgHelp 仅本地符号。可选 watch 为只读，trace 是仅自有 child 内存的一次性断点，恢复原指令后回退 RIP，不写磁盘 EXE。

可复验命令（`--root` 必须换成不存在的新 E 目录，原运行目录已按自有边界归档回收）：

```text
python -B tools/diagnostics/native_cold_import_debug.py --root E:/Caches/Hermes/cache/scratch/<NEW-OWNED-ROOT> --godot D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --source E:/Projects/Godot/FateDominationGame-master --timeout 60 --watch-rva 0x66dcc10 --trace-rva 0x17aba60 --trace-rva 0x1792840
```

上述 RVA 仅适用于本报告的精确 GUI EXE hash，不得挪到另一引擎上。探针内部 Godot 命令为 `--headless --editor --path <fresh-project> --import`，项目仅保留 descriptor/DLL；每次隔离所有用户缓存与临时路径。并非重新运行生产 release CLI。

最初两个 debugger 运行因 Windows 默认 debug heap 验证停顿而自有超时；原始失败未覆盖。线程快照识别 `RtlValidateHeap` 后，对 debugger 的自有子进程显式设置 `_NO_DEBUG_HEAP=1`，无需注册表或安全策略更改。StackWalk 地址 `Mode` 必须显式赋值，避免误填 `Segment`。超时快照与 second-chance 分开，不将前者当 crash 栈。

新增独占测试及实际捕获的 `.txt` fixture：

```text
python -B -m unittest tools.tests.test_native_cold_import_debug -v
```

- parser RED：缺少 `parse_debug_log`，真实 exit 1，两个缺失入口错误。
- 最终 GREEN：4 项，exit 0；包括实际编译/运行受控 AV 子进程，验证 second-chance、异常参数、准确模块与退出码；校验真实宿主捕获 fixture、拒绝 C 盘和已存在暖目录。
- `tests-final-fixture.log` 是当前最终版本记录。**这是诊断器 GREEN，不是 Godot/发行 GREEN。**

## 6. 正式哈希、归档与清理

```text
正式 Windows DLL（原值未变）
92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd
descriptor（原值未变）
c84056e6c5190cda22ba8a6da080081dbce9d5ac86963e20a8dfe315e953ec4a
实际 GUI Godot EXE
ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424
console wrapper（不能混作实际宿主 hash）
c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643
现有 godot-cpp template_release MSVC lib
89e8d3fa11bddfa9f208a91238b0066650e1bec1db5c21bdde60f184b63bd9f2
```

- 旧 DLL 原始 bytes 已单独备份到 E 归档 `original/`，备份与当前正式 DLL SHA 校验相同。
- `summary.json` 保存原始证据文件 SHA/大小、逐候选 parsed second-chance、trace 与准确自有 PID/creation FILETIME；归档 164 个原始证据文件。
- 只回收本轮明确登记的候选、用户缓存、诊断构建产物和受控测试副本，共 `463986284` bytes；`cleanup.json` 逐根确认不存在。没有清旧 round35/37、现有 godot-cpp 或其他用户/代理目录。
- 收尾逐准确 PID/creation FILETIME 读取未发现本轮自有实例存活，`owned_live=[]`；未按通配符杀进程。
- production native 目录 `git diff` 为空；诊断/测试 diff whitespace 检查 exit 0。没有 commit/push。

## 7. 可修复点与本轮门禁

已定位的修复点是宿主 `EditorHelp`：cleanup 时取消/失效尚未执行的文档任务，或者 `_gen_extensions_docs` 明确拒绝已 cleanup 的 `doc==nullptr`，并保证不会在 teardown 期间重新创建文档对象。该修复还须在正确的 generation/lifecycle 边界验证；本轮没有修改、构建或测试这一引擎补丁。

本轮唯一生产写权是插件 native 源码/SConstruct；修复上述宿主生命周期超出该范围，且没有可复用的完整本地引擎构建依赖。**如实停在“精确宿主根因已证实，插件范围内无不牺牲能力的修复”**，而不是把删注册或隐藏 class 当作完成。

后续合法修复/经验证兼容宿主就绪后，仍须旧有效 RED → 新版本真正 fresh 目录冷 import 至少两次 → export → server signals / owner / atomic / identity 核心回归 → 精确新 DLL hash → release 工具后验收。当前全部新正式版本门禁为未执行，不能拼接历史通过记录或标记 final。