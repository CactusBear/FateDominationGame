# Round40：正常 editor 生命周期不能据首扫/帧数证明文档完成

## 结论与交付边界

**BLOCKED_NO_PUBLIC_DOC_COMPLETION_CONTRACT；没有可发布的 import 替代修复。**

已核对实际 `4.7.2.stable.official.ed1daf0bf` 的 main/editor 实现，并完成真实自有 GUI 宿主反证：

- 旧 `--import` 有效 RED：second-chance `0xC0000005`，读取 `0x8`，宿主 RVA `0x53fd042`。
- `--editor --quit-after 2` 同根因 RED；不是多两帧即可修复。
- 两个不存在的新物理 E 目录分别完成 `sources_changed`、`is_scanning()==false` 后 deferred 正常 `SceneTree.quit(0)`，仍同根因 RED。
- 再对精确 `EditorNode` 定向发送关闭通知，实际走正常 editor 关闭处理并卸载 addon，仍是 cleanup→deferred callback 读到 `doc=0`。

因此，**文件系统完成、editor 关闭处理和文档完成不是同一个契约**。本轮没有发现能覆盖现有文档线程/延期任务各阶段的已公开完成信号或状态；不把固定帧数、单个 deferred sentinel、缓存文件存在或“这次没崩”提升为文档完成证明。此结论限定于已审查的当前提交与下述接口/方案，不声称穷尽所有可能的自定义引擎方案。

正式 native/Godot/release/production 全部只读。没有换 DLL、删注册类、暖缓存重入、安装/升级引擎、下载完整引擎/SDK、磁盘二进制 patch 或 release 内存修改。没有 export/PCK/EXE READY 通过声明。

## 1. 引擎身份与真实 help

实际执行：

```text
D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --version
exit 0: 4.7.2.stable.official.ed1daf0bf

同一实际 GUI EXE --help
exit 0:
--quit-after <int>  Quit after the given number of iterations. Set to 0 to disable.
```

原始 help（含 ANSI）与 version：
`E:/Caches/Hermes/cache/scratch/round40-editor-lifecycle-source/godot-help.txt`、`godot-version.txt`。不是 console wrapper 的输出或哈希。

收尾重新计算，三个正式文件均与 round39 相同：

| 文件 | SHA256 |
|---|---|
| 实际 GUI Godot EXE | `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424` |
| 正式 Windows native DLL | `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd` |
| 正式 gdextension descriptor | `c84056e6c5190cda22ba8a6da080081dbce9d5ac86963e20a8dfe315e953ec4a` |

## 2. 精确提交的退出与导入顺序

源文件固定到 [`ed1daf0bf`](https://github.com/godotengine/godot/tree/ed1daf0bf)，仅取定位所需的小文件，存于上述 source 证据目录。

### 2.1 不套用另一版本的 `import_force_quit`

在本次读取的 `main/main.cpp`、`editor/editor_node.cpp`、`editor/file_system/editor_file_system.cpp` 中搜索 **没有 `import_force_quit` 标识符**。当前实现是：

1. [`main/main.cpp`](https://github.com/godotengine/godot/blob/ed1daf0bf/main/main.cpp#L1683) `1683–1687`：`--import` 设置 `editor=true`、`cmdline_tool=true`、`wait_for_import=true`、`quit_after=1`。
2. `1787–1795`：`--quit` 也设置 `wait_for_import`；`--quit-after N` 只设置迭代阈值，没有新增 doc 等待。参数顺序可覆盖帧阈值，但不能改变这一语义。
3. `5062–5065`：process 后 flush MessageQueue。
4. `5118–5119`、`5157–5167`：累计 process frames 达阈值就退出；`wait_for_import` 仅在 `doing_first_scan()` 时阻止退出。
5. `5198–5200`：阈值退出前卸载 editor addons，没有文档屏障。

`--editor --quit-after 2` 自身没有 `wait_for_import`；即使使用 `--import --quit-after N`，阈值仍是从启动累计，而非“首扫后再执行 N 次”，更不是文档完成状态。

### 2.2 首扫信号的确切含义

[`editor/file_system/editor_file_system.cpp`](https://github.com/godotengine/godot/blob/ed1daf0bf/editor/file_system/editor_file_system.cpp#L1771) `1771–1833`：join 文件系统扫描线程、执行 scan actions、设 `first_scan=false` 后发出 `filesystem_changed` / `sources_changed`。`1838–1839` 的 `is_scanning()` 为 `scanning || scanning_changes || first_scan`。

这里不 join `EditorHelp` 文档线程，不验证 `_gen_extensions_docs` 已执行。`EditorNode::_sources_changed`（`1502–1543`）完成首扫布局/场景/preview 处理，也没有建立 doc-ready 契约。

### 2.3 官方关闭处理也没有 doc-ready 屏障

[`editor/editor_node.cpp`](https://github.com/godotengine/godot/blob/ed1daf0bf/editor/editor_node.cpp#L1080)：

- `1080–1082`：`NOTIFICATION_WM_CLOSE_REQUEST` → `_menu_option_confirm(SCENE_QUIT,false)`。
- `3777–3815`：未修改场景/资源/插件的关闭路径进入 `_discard_changes()`。
- `4192–4204`：`_exit_editor` 停 preview、保存布局、卸载 addons、调用 `get_tree()->quit()`，没有等待完整文档 generation。
- `9633–9640`：EditorNode 析构调用 `EditorHelp::cleanup_doc()`。

因此“官方正常关闭”本身不补充所需的文档完成判断。定向关闭实验只是走真实处理链的诊断；定位 EditorNode 用到了该提交的内部 GUI 父子拓扑，不把它当成公开、稳定的生产退出 API。

### 2.4 为什么 cleanup 的 join 仍会留下危险 callback

[`editor/doc/editor_help.cpp`](https://github.com/godotengine/godot/blob/ed1daf0bf/editor/doc/editor_help.cpp#L3029)：

- `3029–3044`：缓存加载线程在退出前排队 `load_script_doc_cache` 和 `_gen_extensions_docs`；缓存失效时改为排队 `generate_doc(false,use_script_cache)`。
- `3083–3088`：`_gen_extensions_docs` 无空检查调用 `doc->generate(flags=3)`。
- `3254–3275`：`generate_doc` 可能创建 doc、同步生成，再启动 worker。
- `3365–3368`：cleanup 只 `_wait_for_thread()`，然后删除 doc 并置空；join 只保证线程结束，**不执行它已入队的 deferred callback**。

[`main/main.cpp`](https://github.com/godotengine/godot/blob/ed1daf0bf/main/main.cpp#L5256) `5256–5259` 先 flush 再删除 main loop；删除 editor 时 cleanup 的 join 可以等到线程刚好把回调排入队列。`5380–5382` 随后又 flush，静态回调于是访问已清空的 doc。

[`core/object/message_queue.cpp`](https://github.com/godotengine/godot/blob/ed1daf0bf/core/object/message_queue.cpp#L224) `224–299` 只是逐项消费当时入队的消息，不是对其他线程未来入队的全局完成屏障；`264` 的 `FLAG_NULL_IS_OK` 允许无 Object 接收者的静态 callable 执行。销毁 EditorNode 不能自动使这一静态文档任务失效。

## 3. 对“public 帮助导航 + sentinel”的审查

不以“未看到 ready API”代替候选分析：已追踪公开 `ScriptEditor.goto_help`。

- `doc/classes/ScriptEditor.xml` `65–91` 公开的是帮助导航，不是 import/doc completion API。
- `editor/script/script_editor_plugin.h:446` 直接调用 `_help_class_goto`；其 `.cpp:3395–3407` 创建/导航 EditorHelp。
- `editor_help.cpp:3348–3350` 的 `go_to_help` 会 `_wait_for_thread()`；`2946–2949` 默认只等当前 `worker_thread`。
- 但 `3038–3044` 的任务仍可延期启动下一阶段；`3169–3207` 的脚本文档 regeneration 另有 `loader_thread`，由 loader 完成后才启动 finish worker。
- `editor_help.h:190–207` 的 `worker_thread`、`loader_thread`、`_script_docs_loaded` 是内部状态；`editor_help.cpp:3421–3428` 没有把这些状态或 generation-complete 信号绑定给脚本。
- header `236–238` 还明确警告 startup 期间直接 DocData 访问可能死锁。

因此，一次导航返回后排一个 sentinel，最多建立部分当前 worker/队列消息的先后关系，不能证明后续生成线程、失效缓存 fallback、文档更新及延期写入均已完成。等待 RichTextLabel 文本排版、缓存 `.res` 存在、EditorPlugin `_ready` 或首扫信号，也不能替代上述内部阶段的完成。**未把导航绕行写入发行工具，未声称其全阶段修复。**

## 4. 真实 fresh 反证与准确进程

新增 `tools/diagnostics/editor_import_lifecycle_probe.py` 复用 round39 的 debugger 源码、哈希和日志 parser，唯一扩展是支持不同 editor 命令尾部/诊断 plugin。每次 `require_fresh_e()` 拒绝存在目录，物理复制正式 descriptor/DLL，创建空工程；project `.godot` 与重定向用户目录此前均不存在。

实际 child 命令共同前缀：

```text
"D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe"
--headless --editor --verbose --path <对应新 project>
```

| 新独占 root（均在 E scratch） | 尾部/退出触发 | PID | child 真退出 | 结论 |
|---|---|---:|---|---|
| `round40-editor-import-red` | `--import` | 15520 | `0xc0000005` | 旧有效 RED |
| `round40-editor-two-iterations` | `--quit-after 2` | 17568 | `0xc0000005` | 帧数不构成屏障 |
| `round40-editor-fs-quit-a` | 首扫信号→deferred `SceneTree.quit(0)` | 35120 | `0xc0000005` | fresh 反证 A |
| `round40-editor-fs-quit-b` | 同上，另一不存在的新目录 | 8048 | `0xc0000005` | fresh 反证 B |
| `round40-official-targeted-close` | 首扫→定向 deferred EditorNode 关闭通知 | 4700 | `0xc0000005` | 正常 editor 退出处理也不保证文档完成 |

这五个有效宿主反证均记录 `timedout=0`、second-chance `[0,8]`、相同 fault RVA `0x53fd042`、`RBX=8`；debugger 的返回值均为 `1`，不能将 debugger exit 与 child native exit 混为一谈。

官方定向关闭原日志摘录：

```text
OWNED pid=4700 creation_filetime=134360462605706382 ...
[R40] SOURCES_CHANGED scanning=false
[R40] FS_COMPLETE doc_ready=UNKNOWN
[R40] NORMAL_QUIT_REQUEST
[R40] OFFICIAL_EDITOR_CLOSE_NOTIFICATION
[R40] CLOSE_TARGET class=EditorNode
Unloading addon: res://addons/round40_lifecycle/plugin.cfg
Script docs haven't been properly loaded or regenerated, so don't save them to disk.
TRACE rva=0x17aba60 watch_rva=0x66dcc10 value=0x19d15b69310
TRACE rva=0x1792840 watch_rva=0x66dcc10 value=0x0
EXCEPTION pid=4700 tid=30256 first_chance=0 code=0xc0000005 ... address=0x7ff65619d042
EXIT pid=4700 code=0xc0000005 timedout=0
```

这里只证明 **cleanup 在前，真正 doc callback 到达时为 null**；没有捏造 callback 完成在 cleanup 前的 GREEN。RVA 严格绑定上述 GUI EXE SHA。断点只改自有 debug child 的单字节并恢复指令，不改 doc 指针、不加空检查、不改磁盘 EXE。`_NO_DEBUG_HEAP=1` 沿用 round39 的 child-local 环境，不改注册表/安全策略。

### 冷缓存边界

日志显示先 `Regenerating editor help cache`，随后 GDExtension 首扫校验触发新一轮 doc 加载，读的是同次运行新建的 `.../<owned-root>/user/LOCALAPPDATA/Godot/editor_doc_cache-4.7.res`。不是从旧用户缓存复制或重入暖目录。探针字段仍不把“环境变量重定向”单独当作缓存隔离证明；这里以实际加载路径及不存在的新目录为证。

### 单独保留的无效诊断实验

`round40-official-editor-close`（PID 33460）最初使用递归 `root.propagate_notification`。关闭期间 addon 删除会改变被递归遍历的树；现场在另一 RVA `0x3e162be` 读取 `0x39`，未到 doc cleanup 断点。这个试验 **不算文档根因反证，更不是修复 RED/GREEN**；原证据保留为 `INVALID_RECURSIVE_NOTIFICATION_HARNESS`。

随后修改的只是诊断发信方式：确认 `get_base_control()` 的父对象为 EditorNode，把单个 `notification` 排队后返回，再由官方处理链卸载 addon。最终探针不再递归遍历。六个宿主试验只计五个有效同根因反证，没有覆盖或抹掉原失败。

## 5. 可复验命令、测试与证据

每个 `--root` 必须换成不存在的新 E 目录；已运行项目/用户缓存已回收，不能拿旧 root 重跑当 fresh。

```text
python -B tools/diagnostics/editor_import_lifecycle_probe.py --root E:/Caches/Hermes/cache/scratch/<NEW> --godot D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --source E:/Projects/Godot/FateDominationGame-master --mode import --timeout 60

可替换 --mode iterations --iterations 2
或 --mode fs-quit
或 --mode editor-close
```

诊断 probe 故意对这些未经证明的退出策略报告 `completion_contract_proven=false`，包括 exit 0 或 callback-entry 在前的情况；这是 source-level gate，不是观察到零退出就自动授予 GREEN。

独占新测试：`tools/tests/test_editor_import_lifecycle_probe.py` 与实际日志选行 fixture `tools/tests/fixtures/round40_editor_fs_quit_capture.txt`。最初运行由于缺少新模块 exit 1；完成实现后专项 3 项 exit 0。最终连同只读复用的原 debugger 4 项共 **7 项 exit 0**，含真实受控 AV 子进程，记录：

```text
python -B -m unittest tools.tests.test_editor_import_lifecycle_probe tools.tests.test_native_cold_import_debug -v
```

测试证据：`round40-editor-lifecycle-source/tests-final.log`。受控 AV 的准确 PID 4092/creation FILETIME `134360464187464113`，日志保存在 `source/controlled-av-test/`；这是 debugger 行为验证，不是 Godot GREEN。

六个原 root 各保留 `debug.log`、`result.json`、build log/C++、`manifest-before-cleanup.json` 和 `cleanup.json`；有 plugin 的还保留实际执行的 `captured-plugin.gd`。聚合：`round40-editor-lifecycle-source/summary.json`，按代码统计 `run_count=6`、有效反证 `5`。

收尾准确 PID/creation FILETIME 查询未发现自有实例存活；没有按名称或通配符杀进程。已仅回收登记的六个 root 的 project/user/debugger 编译产物 `66558796` bytes，以及本次受控 AV 测试独占 root `4358211` bytes；保留原始证据，不清理 round39、既有依赖或其他任务目录。

取源时遇到目录迁移导致的 HTTP 404 和 GitHub API 限流 403；改用当前提交实际路径的 raw 小文件成功读取。未因此猜测源代码或下载 SDK。

## 6. 精确阻断与可选引擎方案（均未实施）

生产流程缺少的不是额外帧数，而是以下可观察契约：

1. 文件系统首扫/导入完成且无后续待导入变更。
2. 对同一 generation，doc worker 与 loader 都结束，延期 native/script 文档任务全部完成应用。
3. 不会再由旧 generation/fallback/扩展更新启动新文档工作。
4. 获得这一完成确认后才发正常 quit；cleanup 使旧延期任务失效，不能重建已销毁 doc。

**选项 A：获得明确授权后修改并构建宿主源码。** 在 EditorHelp 引入 shutting-down/generation token；所有延期文档入口验证生命周期，不只给 `_gen_extensions_docs` 加 null return（失效缓存的 `generate_doc` 也可能重建 doc）。正确协调 loader/worker 的资源加载与主线程 dispatch，避免盲 join 引入死锁；在最终文档应用完成后暴露同一 generation 的 ready 状态/信号，让 cmdline 导入和正常退出消费它。保护 teardown 防崩与声明“导入文档已完成”是两项不同要求，不能只实现第一项就验收第二项。

**选项 B：使用经源码与复现共同确认修复此问题的官方宿主版本。** 当前没有验证、下载或指定任何更高/更低版本为兼容 GREEN；只有候选版本包含明确生命周期修复、保留全部 native 能力且完成下面门禁后才可替换。不能靠版本号推定已修复，也不能擅自升级本机引擎。

本轮不输出伪 patch 产物，不把 debugger 断点或私有内存状态轮询放进 release；这两项是待授权的宿主方案，不是已交付修复。

## 7. 发行门禁状态

| 门禁 | 当前结果 |
|---|---|
| 精确引擎提交 / 真实 help / main与doc顺序 | 已验证 |
| 旧 `--import` 有效 RED | 已验证 |
| 新退出契约的源码证明 | **阻断：未形成** |
| 两次新 fresh GREEN | 未完成；本轮两次 fresh 是失败反证，不能记作 GREEN |
| callback 完成先于 cleanup | 未证明；真实反证为 cleanup 先于 callback |
| 候选 export / PCK 禁入及 native 映射审计 | **未执行，前置契约未过** |
| 导出 EXE READY 与合法退出 | **未执行** |
| signals/owner/atomic/identity 新候选核心回归 | 未执行；无新正式 DLL/候选 |

未来宿主方案应按同一冻结版本执行：旧有效 RED → 新完成契约源码证明 → 两个真正 fresh 目录及文档 callback 完成先于 cleanup 的证据 → export/PCK 审计 → EXE READY 与合法退出 → native 核心回归。不能拼接旧包记录或用任意多次帧数试跑替代这些门禁。
