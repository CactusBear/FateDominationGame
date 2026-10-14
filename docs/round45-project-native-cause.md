# Round45：同引擎项目/原扩展/调用参数冷对照

## 结论与边界

**根因仍未完整定位；未发现可据此提交的生产修复。** 不能把 EditorHelp 的空指针候选路径当最终根因，也不能证明“引擎必然有错/必然没错”。

本轮首先跑真实正式项目的安全冷冻结：加载原 Fate DLL 与原 WebRTC，退出正常。随后无扩展空项目正常；同一空项目加入原 descriptor/DLL，两次独立冷启动均 native AV；第二次只移除冗余显式 `--editor`，仍在同一宿主 RVA 失败。正式冻结单次成功**不是**发行 GREEN，也不能用较多资产加载产生的时序变化掩盖最小工程失败。

- 生命周期总尝试：**4 次**，未暖重跑，未全量 70 套回归，未导出新发行包。
- 同一实际 editor executable、同一 renderer override、同一原 Fate DLL/descriptor；无换引擎、DLL 重建、磁盘或进程内 binary patch、任意 sleep、recovery mode、删类/隐藏能力。
- 每次新物理 E 盘项目及 APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR；无继承 `.godot`。这是冷项目/用户缓存，不声称冷 OS 磁盘缓存。
- 脚本默认预算 30 秒；本次显式 120 秒，实际四次均在 16 秒内结束，无超时。原生产 native 和 release 工具只读。

证据根：`E:/FateDiagnostics/round45-project-native-cause-20261010-1/`。

## 先读的真实配置与代码

### 正式 project.godot

亲读当前文件，而非历史报告：

- `[application]` features 为 `4.7, Mobile`，主场景 `assets/scenes/main_menu/opening_background.tscn`。
- `[autoload]` 有正式游戏单例及开发 `_mcp_game_helper`。
- `[editor]` GitPlugin 自动启动；`[editor_plugins]` 启用 `addons/godot_ai/plugin.cfg`。
- `[rendering]` 默认 `mobile`，worker pool 20。

本次正式冷冻结复用现有 `freeze_prepare.inventory/transform` 的资源选择及安全转换：移除开发 helper、关闭 editor plugin/VCS 启动；保留正式主场景、正式 autoload、游戏资源与两项正式 native 扩展。原 `project.godot` 未修改。

冻结输入 1412 文件，排除原选择清单中 460 个继承 `.godot` cache 文件；`reports/`、`tests/`、`scratch/`、Godot AI/Git 开发插件不在输入清单。所有复制源与目标 SHA 记录在 `C-formal-cold-freeze/input-manifest.json`，复制前后检查源稳定。该副本明确标记 `COLD_DIAGNOSTIC_RELEASE_TRANSFORM_NOT_RELEASE_GATE`，不冒称通过正式 release verify。

### 原扩展及初始化/清理

`addons/fate_server_signals/fate_server_signals.gdextension`：

```ini
[configuration]
entry_symbol = "fate_server_signals_init"
compatibility_minimum = "4.4"
reloadable = false
[libraries]
windows.x86_64 = "res://addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll"
```

`src/server_signals.cpp:97-112`：只在 `SCENE` 注册 FateServerSignals、FateProcessOwner、FateAtomicFileReplace、FateCollectionIdentity；InitObject initializer/minimum level 均为 SCENE。没有项目自定义 terminator；信号对象析构调用 disable。

亲读固定 godot-cpp 依赖 `714c9e2c165db2dcb7e6ea57e62a04204d3cfbfa`：`godot.hpp:225-229` 的 terminator 默认 nullptr；`godot.cpp:494-497` 仍安装 binding 的 deinitialize_level；`:531-544` 判空自定义 terminator后执行 ClassDB/EditorPlugins 清理。因此“没有 register_terminator”**不能单独判为清理漏掉或 AV 根因**。这些源码阅读也不证明当前 DLL 的所有 ABI 项正确，独立只读 ABI 审计应由另一代理单独交付，本报告不代替该结果。

### 已有 release argv 与 supported flags

亲读 `tools/release/release_prepare.py:18-40,75-81`：

- import：`editor_exe --headless [renderer override] --editor --path freeze --import`。
- export：相同 executable/renderer，独立 `--export-release preset output` 命令；不是同一命令叠加 import/export。
- 没有追加 `--quit` 或 `--quit-after`，失败后拒绝继续导出。

实际 `--help` 原件 `help.log` 明确 `this build = editor`；每个使用 flag 均查该输出，脚本拒绝重复 option、虚构 option、quit/export/recovery 混用。匹配实际 revision 的 `official/main.cpp:1683-1687` 说明 `--import` 本身令 `editor=true, cmdline_tool=true, wait_for_import=true, quit_after=1`。显式 `--editor` 冗余但不是另一次 editor 启动；`--import` 的内部 quit_after 不是调用方另塞了冲突参数。B/D 冷对照直接否定了“删冗余 editor 即修复”。

## 三项可证伪假设与结果

| 假设 | 实际预测 | 本轮结果 |
|---|---|---|
| H1 项目 editor 插件或调用方冲突参数触发 | 空工程+原扩展应正常而正式项目失败；或仅移除冗余 editor 即恢复 | B/D 都失败，安全正式 C 正常。插件/正式主场景不是最小复现必要条件；显式 editor 非该 AV 的必要条件。原开发工程未运行，不能宣称其所有插件问题不存在 |
| H2 DLL ABI 或初始化等级不正确 | 同一原 DLL 移到空工程仍失败；若确定性基础 ABI/入口错误，正式 C 同一 DLL 应同样失败 | 空工程失败支持继续审计，C 正常加载并退出反驳“每次必失败”。SCENE/入口静态符合现状；没有足够证据完全排除 ABI/初始化/清理路径，不能拿 C 一次成功验收 ABI |
| H3 扩展文档注册配置/生命周期 | 能找到官方支持且保留类能力的 doc-off 配置；单变量切换后两次冷启动及 native 功能均通过，才可作修复候选 | 未找到 descriptor/CLI 的这种配置，未编造或尝试。源码存在异步 doc callback 与 cleanup 的候选交错，但本轮没有测 doc 全局指针/生命周期顺序，因此不能升级为最终因果结论 |

A/B 是“只增加原扩展”的对照；B/D 是“只移除显式 editor”的对照。C 与 B 不止一个变量（正式 autoload/场景/资产/WebRTC/工作量均不同），所以 C 正常**不能归功于某个单独配置或 reports 排除**，也不是可接受的靠负载延迟修复。

## 精确 binary / template 身份

实际版本：editor、debug/release Windows 主模板的真实 `--version` 均为 `4.7.2.stable.official.ed1daf0bf`；各自退出 0。只用 editor 主 executable 做四次 lifecycle，未用 console wrapper 或 export template 做 import。

| 对象 | SHA256 |
|---|---|
| editor `D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe` | `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424` |
| editor console wrapper（未运行） | `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643` |
| windows_debug_x86_64.exe 模板 | `51498b72b3a237f882ebd7d1787f06a4bc1eaf0572daab93837adcfd3cfdc107` |
| windows_release_x86_64.exe 模板 | `d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562` |
| debug 模板 wrapper | `5514c7645ee897a01f540d3cf22ede5badf92394521a08bfab66a54d7369e6e6` |
| release 模板 wrapper | `52bdcae9068e8d23b840e5c63b0c1798ffe2cb66144e5c4bc7af11fb8c8600df` |
| 原 Fate descriptor | `c84056e6c5190cda22ba8a6da080081dbce9d5ac86963e20a8dfe315e953ec4a` |
| 原 Fate DLL | `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd` |

模板位于本机 `C:/Users/Administrator/AppData/Roaming/Godot/export_templates/4.7.2.stable/`；没有自定义模板覆盖。哈希相互不相等是不同产物的正常情况；身份匹配以各独立 hash 和实际版本输出为依据，不把 wrapper hash 当宿主 hash。没有与官方下载签名/完整发布清单另做校验。

## 四次真实结果（执行顺序 C → A → B → D）

共同尾参数：`--headless --verbose --rendering-method gl_compatibility [--editor] --path <各自独占project> --import`。覆盖 renderer 是现有 release 支持的显式调用方参数；未改工程默认 renderer。

| 试验 | 引擎 PID | debugger PID / exit | child exit | wall 秒 | 第二次机会异常 |
|---|---:|---|---|---:|---|
| C 正式安全冷冻结（原两扩展） | 33440 | 34476 / 0 | `0x00000000` | 15.515 | 无 |
| A 无扩展空工程 | 13484 | 5460 / 0 | `0x00000000` | 3.261 | 无 |
| B 同空工程+原 Fate 扩展 | 33828 | 35964 / 1 | `0xC0000005` | 3.823 | TID 28284，read `0x8` |
| D 同 B，仅省略显式 editor | 34040 | 27104 / 1 | `0xC0000005` | 5.182 | TID 32844，read `0x8` |

B/D 实际 exception address 均 `0x7ff65619d042`，属于上述 editor image，**RVA `0x53fd042`**，参数 `[0,8]`。共同后续栈 RVA 包括 `0x178b95c → 0x1792855 → 0x3e0e832 → 0x3e0ea39`。原件有 first-chance 与 `first_chance=0` 的第二次机会、寄存器、字节、模块清单和 EXIT；不是 watchdog snapshot。无完整局部符号，日志里的远距离 `NoHotPatch+...` **不当函数名**。本轮不擅自给 RVA 标最终 C++ 源码行，亦没有证明那个 read `0x8` 的指针就是 EditorHelp::doc。

C/debug.log:493-494 确认实际加载原 Fate DLL shadow 和 WebRTC debug DLL；不是关闭 GDExtension 的假 GREEN。B 的实际加载 shadow DLL hash 也与原 DLL 完全相等。四份日志无 `SCRIPT ERROR:`/`ERROR:`，但均有 `Failed to bind socket. Error: 3.` 和 script docs 未保存提示；这些共同环境现象不忽略，也不能解释为何仅 B/D native AV。已有用户 editor 未关闭，占用端口是可能干扰项，四次预算用尽后没有私加第五次换端口试验。

## 官方文档与源码核验：不虚构 doc-off

已保存匹配实际 engine revision 的完整源码及 SHA，见 `official-fetch.json`：

- [main.cpp @ ed1daf0bf](https://github.com/godotengine/godot/blob/ed1daf0bf/main/main.cpp)：help/parser；`--no-docbase` 用于 doctool，不是 editor doc shutdown barrier。
- [gdextension_library_loader.cpp @ ed1daf0bf](https://github.com/godotengine/godot/blob/ed1daf0bf/core/extension/gdextension_library_loader.cpp)：配置读取包含 entry、compatibility、reloadable 等；未提供此处需要的 doc-off。
- [editor_help.cpp @ ed1daf0bf](https://github.com/godotengine/godot/blob/ed1daf0bf/editor/doc/editor_help.cpp)：3029-3044 缓存加载线程可 defer 扩展 doc generation；3083-3089 生成路径用 doc；3365-3369 cleanup 等线程后删除并置 nullptr。**这些只是候选机制，缺本轮生命周期观测，不当最终根因。**
- [doc_tools.cpp @ ed1daf0bf](https://github.com/godotengine/godot/blob/ed1daf0bf/editor/doc/doc_tools.cpp)：430-446 遍历 extension classes，按 `is_class_exposed` 筛选。`is_exposed=false` 是类暴露语义改变，不是已验收的“只关文档且能力不变”配置，本轮不改注册标志/DLL。
- [官方 descriptor 文档源码](https://github.com/godotengine/godot-docs/blob/master/engine_details/engine_api/gdextension/gdextension_file.rst)：configuration 表无 doc-off 属性，库 feature tags 是选择二进制，不是文档开关。该文档来自当前 master，不假装是 pinned engine commit；loader/source 才约束本机支持范围。

原官网文档 fetch 403，旧 raw 文档路径 404，GitHub tree API rate-limit 403；搜索找出文档已移动到 `engine_details/engine_api/gdextension/` 后，成功取回官方 raw 原文及 SHA，记录 `official-doc-recovery.json`。没有以网络失败伪造 flag，也没有用通用代理。

## MCP 只读证据与限制

准确 target：`fatedominationgame-master@ecc0ba7efcb336f7`。

真实 `editor_state`：4.7.2-stable official、ready、stopped、未播放，当前主场景仍为原 opening_background。未关闭用户 editor，未变更 main scene，未通过 MCP 启动额外 lifecycle。

`api_manage(get_class, methods, include_inherited=false)` 只读结果：四类均 `can_instantiate=true`；FateServerSignals 4 方法（enable/protect_worker/disable/take_request），FateProcessOwner 6 方法，FateAtomicFileReplace 1 方法，FateCollectionIdentity 2 方法。**这是已有运行 editor 的注册证据，不是本轮新 cold freeze 的功能执行验收，也不代替信号/进程所有权/原子替换/identity 专项测试。**

主代理报告的归档 reports/*.gd 全局类重名、bitmap 导入和旧 tests parse errors 应独立修；本轮正式冻结明确不包含这些路径且没有相应 parse error。没有把 `.gdignore` 或归档排除冒称 native crash 修复。

## 保留、回收及最小生产建议

- 原始失败 B 的完整 project、`.godot`、原 DLL、实际加载 shadow DLL、独立用户缓存、debug.log/result/input manifest **全部保留**。
- C/A/D 的自有生成 `.godot` 已回收；追加回收其自有 user cache 和 D shadow DLL，`cleanup.json` 记录。不删任何生产或归档日志/bitmap。
- 四个 child EXIT 后复核：OpenProcess 返回 invalid PID（87），无存活自有 engine PID；见 `pid-postcheck.json`。未按进程名批量杀进程。
- 本轮无法建立“原项目/调用方错误修复”的有效 RED/GREEN。删扩展可令 A 正常，但这删除原生能力，**不算修复**。B/D 证明仅删 editor 参数无效；不能建议以此生产 patch 交差。
- 未证明初始化/清理有项目级因果错误，所以不建议增加空 terminator、改 initialization level、隐藏类或延时等生产补丁。生产与 native 文件零改动。
- 后续若继续定位，需要在同一负载/缓存与原 DLL 下获得注册、doc callback、cleanup 的精确时序或独立 ABI 反证；不能再把一次完整工程正常或历史空类实验当最终结论。本轮四次预算已用尽，没有扩展成无界实验。

## 新脚本与真实执行

新增：`tools/diagnostics/project_extension_lifecycle_probe.py`；本报告是另一新增文件。脚本与既有 debugger/release 原语解耦：只在独占输出根组合它们，不 import 执行生产 release main、不写依赖文件、不重建 DLL。

```bash
PYTHONDONTWRITEBYTECODE=1 python tools/diagnostics/project_extension_lifecycle_probe.py \
  --root E:/FateDiagnostics/round45-project-native-cause-20261010-1 \
  --godot D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe \
  --templates C:/Users/Administrator/AppData/Roaming/Godot/export_templates/4.7.2.stable \
  --timeout 120
```

执行器退出 0 表示收集完成，**不表示四个 child 全通过**；results.json 明确 B/D native failure。重复执行必须使用另一个全新 root，现有 root 拒绝覆盖。

最终脚本的精确 help token 校验、重复/未知/冲突 flag 三项拒绝测试及生成物回收逻辑已实际执行通过；文档移动路径已真实 fetch 成功。四次 Godot 证据来自本轮初版执行，随后仅改进 token 校验、正确文档 URL、回收逻辑与移除 unused import，没有重新启动 Godot或把不同 native 版本结果拼接。
