# Round49：合法 C-ABI 差分与正式产品冷导入

## 交付结论

**当前这一份正式安全 freeze 两次 fresh 冷导入均退出 0；同冻结来源的四项 native 能力专项 23/23 断言通过、退出 0。不能因 minimal 控制失败而将这个已实际通过的正式入口标为 BLOCKED。** 这不是最终发行包、不是 round50 后续新冻结的验收，也不抹掉历史 native AV。

合法 exposed、非 abstract、可实例化 RefCounted 控制仍 AV；同一 DLL、同一项目文件仅关闭注册的控制正常。旧 raw 控制缺 mandatory callbacks 的排除证明已纠正：新控制实际走过 ClassDB 实例化、set_instance、首次引用建立/补偿、末次引用释放及 free callback。根因尚未完全定位；尤其**本次冷场景没有有效取得宿主 cleanup 写入与 deferred callback 的完整动态先后**，不能由相同 RVA 宣告完整引擎因果链。

生产 DLL、源码、descriptor、SConstruct、release 工具及引擎零改动；未隐藏 exposed、删能力、延时或暖重跑四个有效冷场景。所有输出在独占物理 E 盘。

有效证据：`E:/FateDiagnostics/round49-legal-native-control-20261010-4/`。

## 四个有效冷场景

共同命令尾部：`--headless --verbose --rendering-method gl_compatibility --editor --path <独占project> --import`。每个场景无继承 `.godot`，APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR 各有新目录；不声称清空 OS 磁盘缓存。

| 场景 | 实际 engine PID | child exit | wall 秒 | 结果 |
|---|---:|---|---:|---|
| A 合法 registered | 37556 | `0xC0000005` | 4.563 | 真实 second-chance AV |
| B 同 DLL unregistered | 30312 | `0x00000000` | 3.568 | 同框架退出正常 |
| C 正式安全 freeze 冷导入1 | 9396 | `0x00000000` | 19.286 | 原 Fate DLL + WebRTC，正常 |
| D 相同输入 freeze 冷导入2 | 15968 | `0x00000000` | 17.578 | 独立缓存，正常 |

`cold-results.json`、每组 `result.json/debug.log/input-manifest.json` 是原件。C/D 使用同一个未经导入的 `formal-input-snapshot/`，1417 文件且逐文件 SHA 完全相同；D 不复制 C 的导入后文件。正式选择/转换只复用只读 `freeze_prepare.inventory/transform`，排除 reports/tests/scratch/继承 cache，移除开发 helper、禁用 editor/VCS 插件，保留正式场景、autoload、两项原生扩展。没有调用 release verify 冒称发行 READY。

## 合法性与精确接口

亲读 `docs/round45-project-native-cause.md`、`round45-extension-build-contract.md` 全文后构建独立控制；不复用旧缺回调的 raw DLL。

- 精确引擎提交：`ed1daf0bf001b61586d9930840f2f1394092c079`。
- 精确接口头来自该宿主已有 dump，SHA `640b48188708ba0016f8d7ace9e0e1d3279a41fa1226c59ff3193b15538bd254`。官方同提交 `.h` URL 404（接口头为生成物），转取同提交 `gdextension_interface.json` 原文；实际程序核对 CreationInfo4 的 **23 个成员、顺序**一致。来源与失败均保留 `official-fetch.json`，未猜 API。
- `CreationInfo4.create_instance_func` 使用精确 `GDExtensionClassCreateInstance2`；构造原生 RefCounted 后 `object_set_instance` 绑定真实自有实例，按 notify 标志处理 POSTINITIALIZE；free 仅删除自有实例，不递归销毁 owner。`get_virtual_func` 明确返回 null。
- `is_exposed=true,is_abstract=false,is_virtual=false,is_runtime=false`；没有 godot-cpp、方法/XML/临时 doc callback、Godot 静态对象。
- 所需 get_proc 全查空；缺 API 入口返回 false 并输出 INITFAIL；SCENE 才可解析的 destructor/MethodBind 缺失输出 INITFAIL 并用专用非 AV 状态退出，不能假装成功。
- SCENE 才构造 8-byte/8-aligned StringName；同级先 unregister 再逆序析构，重复 init/退场和存活实例明确拒绝。
- RefCounted 公开说明“零引用”在本宿主是**有效未引用**：raw count 初值1，`refcount_init=1`。新自测验证首次 init_ref 后仍1、末次 unreference 返回 true，再 object_destroy，不能把 getter 必须0当合法门槛。精确 `ref_counted.cpp/.h` 已归档。
- A/B 文件集合和每个文件 SHA 一致，同一 DLL SHA `132e819ef8d5d7706dba127c35a2d51d0026ea09a89e771b4a2f0698d072227a`；唯一显式选择 `R49_REGISTER_CLASS=1/0`，注册分支含验证其可实例化的自测，不是只换类名或 abstract 标志。

诊断控制真实构建：`build.cmd/build.log/build-result.json`，MSVC `/utf-8 /EHsc /std:c++17 /W4 /O2 /MT /LD`，只 include 精确接口头，**exit 0**。生产 DLL 没有重建。

## A 当次异常与确切生命周期范围

当次 PID37556/TID2780：`first_chance=0, code=0xC0000005, PC=0x7ff65619d042`，实际 editor RVA `0x53fd042`，参数 `[0,8]`（读8）。寄存器 `R12=0,RBX=8`；对准确宿主 `doc` storage RVA `0x66dcc10` 的当次读取为0。栈包括 `0x178b95c → 0x1792855 → 0x3e0e832 → 0x3e0ea39`。完整寄存器、指令字节、模块与 stack 在 A 原始日志；不把远距离 NoHotPatch export 标签当函数名。

A 的真实控制回调顺序：entry → init0 → init1 → init2 → 创建 StringName/解析 MethodBind → register返回 → CREATE_ENTER/RETURN → FREE_ENTER/RETURN → INSTANTIATE_FREE_PASS（creates=1,frees=1）→ init3 → native AV。**AV 前没有任何 deinitialize、unregister 或 StringName 析构回调。** 因此不能归因为该控制提前析构了注册名或其 free 未实现。B 真实退场为 deinit3 → deinit2 → STRINGNAMES_DESTROYED → deinit1 → deinit0 → exit0。

A 不依赖 godot-cpp，且补齐 mandatory callbacks 后仍出现同形 native 失败；这收紧了旧 raw 控制的证据，但不证明原 DLL 全 ABI 无问题。单次合法 registered RED/单次 unregistered GREEN 的复现范围必须保留。C/D 与 A 资产/脚本/扩展工作量不同，不得归因某一资产“修好”或拿加载时间当修复。

**重要缺口：**冷场景 hardware trace 为空。诊断 debugger 的旧构建日志出现 C4819/C4715；因此不采信其宿主执行断点/数据写断点生命周期观测。原有被动异常采集确有 second-chance AV，控制本身 `/utf-8` 编译且真实实例化自测已通过；但这不补足 cleanup→callback 的动态顺序。最终诊断构建已添加 `/utf-8 /WX`，同源码 build-only 对照实际 RED exit2 / GREEN exit0（`E:/FateDiagnostics/round49-final-diagnostic-build-check/`），**未用新 debugger 再启动 Godot**。不把这个诊断器编码问题提成生产 SConstruct 修复。

## 正式四能力：独立于冷导入的 runtime 检查

最终有效专项：`G-capabilities-verified-owned-console/functional-result.json`，engine PID33120，child exit0、23项全部 true、无 SCRIPT ERROR/ERROR 或 second-chance。仍使用同一正式 Fate DLL；没有修改正式 freeze 输入。

- signals：实际 enable、单 owner 拒绝、CtrlBreak 投递一次后读取清空、disable/protect_worker 后真实投递但不收集。
- owner：available、真实 spawn、token/PID verify/state、错误 token 和活进程 release 拒绝、terminate→exit→release。
- atomic：真实覆盖临时文件并读回新内容、确认源文件消失。
- identity：精确 engine hash 运行门、Array/Dictionary alias 与 distinct、修改后键稳定。

安全信号夹具的最终控制台归 console-subsystem debugger 独占，sender 两次枚举必须仅有登记的 debugger/engine/sender 才广播。两次真实成员数各3；两个当次 engine `0x40010008 first=1` 事件均存在。只操作自有进程，没有 attach 外部进程。runtime 的正式 binding 数据写观察另外得到 initialize0/1/2/3（DLL RVA0x88fb）→deinitialize3/2/1/0（RVA0x5655）；这只是 runtime，不冒充四个 cold 场景的宿主文档时序。

## 必须披露的诊断失效尝试

四个有效场景之前另有 **9 次失效诊断尝试**：证据根后缀1有4次（误把 raw refcount1 判失败；硬件执行断点反复触发/超时）；后缀2有4次 debugger-induced second-chance SINGLE_STEP；后缀3只有1次执行断点 runaway，随后停止。它们不是产品 RED/GREEN，也不是“只运行四次”的记录。当前执行器遇到 INITFAIL、硬件错误、超时或 second-chance single-step立即停止。

正式能力检查另有 E/F 两次失效夹具：E 的 OS.execute sender 未向 engine 控制台投递；F 的继承控制台夹具未隔离 debugger console，父执行器被控制台事件中断（`0xC000013A`），不能宣称无外部影响已证明，不能算信号功能失败或成功。最终 G 加独占 console 与成员 fail-closed 校验后才通过。不隐瞒上述错误，不追加冷场景补样本。

全部16个 Godot 尝试的准确自有 PID 均最终确认不存活，见 `all-attempts-pid-postcheck.json`。所有缓存/加载 shadow DLL 已无损 ZIP 归档、逐文件 SHA/ZIP 校验后回收；失效巨大日志另存后缀1的 `invalid-raw-originals.zip` 和索引，不删原始失败证据。源码快照、build、日志原件保留。

## 给正式发行者的最短重做命令与指纹

只有下面这份 freeze 获得“两次正常”的事实；新 round50 freeze 必须重新算 fingerprint 并实际导入，不借用本报告。命令本身不是最终发行包验收。

```bash
# NEW_FREEZE 必须来自 formal-input-snapshot 的新独占复制；不能复用 C/D 的 cache。
APPDATA="$R/user/APPDATA" LOCALAPPDATA="$R/user/LOCALAPPDATA" \
TEMP="$R/user/TEMP" TMP="$R/user/TMP" TMPDIR="$R/user/TMPDIR" \
"D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe" \
  --headless --verbose --rendering-method gl_compatibility --editor \
  --path "$R/project" --import
```

`R` 必须是非现存物理 E 子目录；预先新建五个 user 目录并复制 snapshot 到 project，确认无 `.godot`。仅自有 PID、最多180秒、首次非零保留并拒绝导出；不要暖重跑盖掉冷失败。正式 release 工具已有相同 import argv 构造，不建议删冗余 editor 来“修复”。

| 对象 | SHA256 |
|---|---|
| 实际 editor EXE | `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424` |
| 原 Fate DLL | `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd` |
| 原 descriptor | `c84056e6c5190cda22ba8a6da080081dbce9d5ac86963e20a8dfe315e953ec4a` |
| 冻结 project.godot | `7386c817a47a2d1ae2876e30c4f338d8b9d3781ab26be64626808da52da22edb` |
| 1417文件完整映射 fingerprint | `a906e34805204d2a180825b0c49f0303cf42cd2ae3a00b28c3e9831dfa631479` |

fingerprint算法：对 `input-manifest.json.files` 用 `json.dumps(files,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode("utf-8")` 后 SHA256。完整 native/WebRTC/资源逐文件值保留 manifest；`verified-fingerprint-summary.json` 是实际程序断言结果。

## 文件与剩余项

新增仓库文件仅：`tools/diagnostics/legal_extension_control.py`、`legal_extension_control.cpp`、本报告。未修生产 native，未提出未经 RED 验证的 flags patch。根因剩余：合法 exposed 注册触发的最小工程退场故障及精确宿主文档时序；它不能被两次正式成功抹掉，也不能自动阻断已经实测合法的正式入口。下一份 production headless 冻结由主代理重新锁定后再验；本轮停止进一步 native 启动。
