# Round37 冷信令 import 根因定位

## 结论

本轮完成了**一次性、全新冷目录**的 14-file signaling freeze 对照。故障边界已经缩到：

> 只要冷导入候选中存在 `fate_server_signals.gdextension` 及其现有 Windows native DLL，Godot 4.7.2 在 editor `--import` 阶段退出 `3221225477 = 0xC0000005`；移除 GDExtension 后同一脚本/同一 14-file 冻结通过。

默认 worker 设置、`worker_pool/max_threads=20` 和命令行 `--rendering-method gl_compatibility` 都没有改变结果。因此当前可证实的是 **Godot 冷扫描/原生扩展加载边界的 native 崩溃**，不是 GDScript Parse Error、线程设置或渲染器选择。

这不是发行通过，也没有修改 Godot、DLL、生产 `project.godot` 或 release 工具；没有尝试第四次生产冷导入猜修。

## 1. Windows Application Error 与准确 PID

### 本轮 probe 的准确自有 PID/退出码

所有 PID 均由本轮 probe 创建并在 `Popen.wait()` 后关闭；收尾 `tasklist` 未找到这五个 PID。时间为中国标准时间（UTC+08:00）：

| 候选 | 进程 PID | 创建 FILETIME | 启动时刻 | 结束时刻 | 退出码 |
|---|---:|---:|---|---|---|
| `empty-default` | 5868 | 134360409727053537 | 2026-10-10 01:36:12.703849 | 01:36:15.982876 | `0x00000000` |
| `script-no-extension-default` | 30960 | 134360409760525842 | 01:36:16.050775 | 01:36:19.998486 | `0x00000000` |
| `extension-default` | 35784 | 134360409800768393 | 01:36:20.075065 | 01:36:23.323235 | `3221225477 / 0xC0000005` |
| `extension-thread20` | 26652 | 134360409834197837 | 01:36:23.417777 | 01:36:26.754352 | `3221225477 / 0xC0000005` |
| `extension-gl-compatibility` | 22344 | 134360409868794798 | 01:36:26.877314 | 01:36:30.161828 | `3221225477 / 0xC0000005` |

五个候选 stdout/stderr 摘要已逐候选落盘；三次扩展崩溃的 stdout SHA256 相同：

```text
stdout: 1708a4599e370980d18dce8493f06d125f2872132b68cd5bb9c65eed8bd309ad
stderr: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
```

输出均停在正常 `first_scan_filesystem` / `update_scripts_classes` / `loading_editor_layout` 进度，stderr 为空。

### Windows Application Error 读取结果

本轮 probe 在每个自有 PID 退出后读取 `Application` 日志 `Application Error` Event ID 1000，并以 **PID + creation FILETIME** 精确匹配；五个本轮 PID 均没有对应事件。故不能把 Windows 事件里的模块名冒充为这三个当前 PID 的已证实模块。

系统日志中存在同一 Godot 可执行文件、同一异常的最近匹配记录：

```text
EventRecordID: 14107
TimeCreated: 2026-10-10 00:24:32.136055 +08:00
AppName: Godot_v4.7.2-stable_win64.exe
ProcessId: 0x552c = 21804
ProcessCreationTime: 0x1dd580aa815c36e
ExceptionCode: c0000005
ModuleName: Godot_v4.7.2-stable_win64.exe
ModulePath: D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe
FaultingOffset: 00000000053fd042
```

该记录**不是**本轮 35784/26652/22344，不能作为当前 PID 的逐一事件证明；它只能确认同一 Godot 版本/路径曾以 `0xC0000005` 在 Godot 自身模块、相同 fault offset 崩溃。Round35 三次候选的归档退出码和本轮三次最小候选退出码相互一致，但 Application Error 没有为本轮 PID 生成可关联记录，这是当前证据缺口，已如实保留。

## 2. 单变量最小化结果

所有扩展候选均来自同一次 `freeze_prepare.py --prepare` 的 14 个 source file；每个候选都有新目录和新 APPDATA/TEMP/TMP/TMPDIR，未复用导入缓存。没有 warm re-entry。

| 顺序 | 候选 | 相对上项的变量 | 结果 |
|---:|---|---|---|
| 1 | 纯空项目 | 无生产脚本、无 GDExtension | exit 0 |
| 2 | 同一 14-file 冻结，保留 `server_process_signals.gd`，移除 GDExtension descriptor/DLL | 加回相同脚本但不加载 native 扩展 | exit 0 |
| 3 | `extension-default` | 加回现有 GDExtension descriptor/DLL；默认线程 | `0xC0000005` |
| 4 | `extension-thread20` | 仅改为 `worker_pool/max_threads=20` | `0xC0000005` |
| 5 | `extension-gl-compatibility` | 新冷目录，仅命令增加 `--rendering-method gl_compatibility` | `0xC0000005` |

故障最小边界是 GDExtension 的冷发现/加载/初始化，不是脚本本身、20 线程或 headless renderer 参数。仅凭这组证据还不能进一步区分 Godot ABI、DLL 初始化、GDExtension 扫描或宿主自身 fault offset；不能安全指定 DLL 内部函数。

## 3. 固定命令与哈希

Godot：`4.7.2.stable.official.ed1daf0bf`，SHA256：

```text
c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643
```

本轮执行入口（只执行一次）：

```text
python -B E:/Projects/Godot/FateDominationGame-master/tools/diagnostics/signal_cold_import_probe.py --source E:/Projects/Godot/FateDominationGame-master --godot D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe --freeze-python E:/Projects/Godot/FateDominationGame-master/tools/release/freeze_prepare.py --root E:/Caches/Hermes/cache/scratch/round37-cold-import-rootcause-20261010-a --timeout 180
```

探针内部的单次 import 命令为：

```text
<D:/Godot.../Godot_v4.7.2-stable_win64_console.exe> --headless [--rendering-method gl_compatibility] --editor --path <fresh-candidate> --import
```

14 个 source file 的完整 SHA256：

```text
.godot/imported/icon.svg-218a8f2b3041327d8a5756f3a245f83b.ctex  5065348df8b1d7fa8484298b54140bd0cdae1c53b35a8bca37f7ffde71b45d2b
.godot/imported/icon.svg-218a8f2b3041327d8a5756f3a245f83b.md5   1a0f744815037df6dea53f4c8d95e6aec65e7ed1b47ff57af94bf7704808bb44
addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll  92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd
addons/fate_server_signals/fate_server_signals.gdextension  c84056e6c5190cda22ba8a6da080081dbce9d5ac86963e20a8dfe315e953ec4a
assets/scenes/main_menu/server_bootstrap.tscn  99cddf9a542b33d7fbc3f399226dbac99c720a26a63317b439137a9868ccefbb
export_presets.cfg  f8f6afbbeb520f780deab5d7f7d5a59e9f5b2f33e02db4cb64c6823a428da091
icon.svg  7d4b4f4cf1c28d3587be682415bd2acc56ff987eb1fc48b0441f00e18db19913
icon.svg.import  4a1d2e463754c48799dd69457a955da802230ec906a5d2cd7d1af4cd088b5fdc
project.godot  986a066adc6f0d1346d19612538780abaf2ce4d3cdfef4342db653a0b53d8c8a
scripts/net/p2p/p2p_invite.gd  ffe9b1e2e430b1e9752aebb988f22866dcc8492bbbecaf2c238d996bee1349cf
scripts/net/p2p/p2p_signal_server.gd  6d9fdea6d76aa963ebbba78c24353294503da4b909d9feb4990e470b1309f2b2
scripts/net/server/server_bootstrap.gd  bc20ffaff77b5306d8743c2ce2c5d6c2f171c1b0920b2ac835268dcab0e6c4bd
scripts/net/server/server_process_signals.gd  354918be4b757882fe2f671e1a2bb02f1d32bad6b80cfac763c3dd6f192a373f
scripts/net/transport/webrtc_link.gd  0dda042895351e334eb8e4b14543a3eb08cbd1e22790885e64d4f7eef59682ad
```

> 完整清单和逐项 hash 以归档 `manifest.json` 为准；本段只保留相同的 14-file source manifest 摘要。

Native DLL SHA256：

```text
92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd
```

`dumpbin /headers`：x64、Windows CUI、entry point `0x2E19D1340`；`dumpbin /dependents`：`bcrypt.dll`、`KERNEL32.dll`、`msvcrt.dll`。本机已有 `dumpbin.exe`；未找到 `cdb.exe`、`windbg.exe`、`procdump.exe`，没有下载依赖，也没有开启系统 dump/安全策略修改。

## 4. 产物与完整性

- 新增：`tools/diagnostics/signal_cold_import_probe.py`，SHA256 `fec9c1066eefc6a439b930735b15739d4e3e76d83e86a50fb035750329d28863`。
- 新增：本报告。
- 诊断归档：`E:/Caches/Hermes/cache/scratch/round37-cold-import-rootcause-20261010-a/`
  - `manifest.json`：命令、14-file source hash、DLL/GDExtension hash、PID/creation FILETIME/退出码。
  - `evidence/*.json`、`*.stdout.log`、`*.stderr.log`：逐候选原始证据。
  - `base-14-files.json`：冻结清单及实际 hash。
  - `cleanup-summary.json`：只回收本轮自有候选项目、用户缓存和 base 副本，共回收 41,722,643 bytes；证据文件仍在。
- 归档后重新核对 14 个源文件：`round37 source drift []`；生产源、Godot、DLL 未修改。
- `git diff --check -- tools/diagnostics/signal_cold_import_probe.py`：exit 0。
- 已按自有边界回收大副本；保留本轮 E 盘证据文件给 native 构建/符号/dump 交接，没有删除不属于本轮的目录。

## 5. 后续交接边界

当前最安全结论是“冷 GDExtension 触发 native 崩溃”，不是“已找到 DLL 内部根因”，也不是“发行安全修复”。下一步若要继续，只应由 native 构建/宿主调试线程在相同 Godot 版本、DLL hash、14-file manifest 和 exact cold command 上接入现有符号或 dump 工具；不得先换 DLL、改 Godot、改线程或把暖导入当成功。
