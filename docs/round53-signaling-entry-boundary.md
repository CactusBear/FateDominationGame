# Round53：纯信令原生部署资产与运行入口初始化

## 结论与当前产物

**支持在项目侧分离加载职责，已完成同一原 DLL、同一官方引擎下的闭环。** 先做两份逐文件相同的隔离 prototype，首次 cold 不加载 native，runtime 显式加载后四类/13个必要方法齐全；四能力各23/23实测通过。再接最小生产入口，两份 fresh 首次 cold、导出和真实信令 EXE runtime 均正常。没有暖重试、换引擎、删类、隐藏 exposed、sleep 或盲 quit-after。

- 单一当前主清单：`E:/FateCandidates/round53-signaling-runtime-entry-sa1/manifest.json`
- 建议采用的**信令初始化候选**：`E:/FateCandidates/round53-signaling-runtime-entry-sa1/artifacts/signaling/`
- 独立第二份实际包：`E:/FateCandidates/round53-signaling-runtime-entry-sa1/verification/signaling-second/`
- 前置 prototype：`E:/FateDiagnostics/round53-signaling-initialization-sa1/manifest-continuation.json`
- 当前状态：`TWO_FRESH_SIGNALING_CANDIDATE_GREEN`，分类仍为 `CANDIDATE_SOURCE_NOT_LOCKED`；不是三角色完成或最终人测包。

原 Round52 首次 AV 原日志仍在原目录，另逐字节复制到当前 `evidence/round52-first-cold-AV-original.log` 并核对 SHA。其首次 exit `0xC0000005` 没有改写成 GREEN，也没有重跑旧输入。

## 真正的配置退出合同

亲读当前 `server_bootstrap.gd`、ClassDB 包装器、既有测试与发行调用者：`_signal_fail(reason)` 是 `push_error(reason)` 然后 `quit(2)`。没有生产合同要求统一 exit1；Round52 审计的 exit1 是执行器假设，本轮不为迁就它修改正确的2。

真实缺配置负向两包均 exit2，严格允许以下**完整两条** ERROR，并检查 core 调用范围：

1. `ERROR: Parse JSON failed. Error at line 0: Unknown error getting token`，来自 `parse_string (core/io/json.cpp:629)`。
2. `ERROR: 信令配置不可读或包含未知 CFG 段/嵌套覆盖`，来自 `push_error (core/variant/variant_utility.cpp:1023)`；源码运行另核对 `_signal_fail` GDScript backtrace。

诊断原语要求 caller 显式提供 `expected_exit/reason/allowed_errors`。AV、exit1、其他非零、缺 reason、重复 reason、任意未知 ERROR、错误 scope 或 READY 与拒绝同时出现均拒绝。release template 不含源码 backtrace时，采用精确 core scope和已逐文件核对的生产包，不降低 ERROR 集合限制。

另以**仅缺 native 部署资产**的新运行输入实际核验：PID38004，exit2，仅 `ERROR: 信令原生部署资产缺失`，无 native 模块加载、无 READY。不是一个只靠“无 data”过门的空包。

## 可证伪方案及官方支持

### 发现与初始化为什么应分开

旧纯信令裁剪项目把 `.gdextension` 与 DLL 当编辑器资源。精确宿主提交的 `EditorFileSystem::_first_scan_process_scripts` 搜索 GDExtension 资源，随后 `GDExtensionManager::ensure_extensions_loaded` 会在首扫调用 `load_extension`，与是否启动信令 main scene无关。其文档注册工作因此进入 editor生命周期，而纯信令不需要原生资产导入器、自定义 Inspector或 editor类。

当前官方 `GDExtensionManager` API 明确允许 `load_extension(absolute_path)`，返回 `LoadStatus`；`is_extension_loaded/get_loaded_extensions` 可读回。精确提交的 manager在首次加载时调用 `_load_extension_internal(extension,true)` 并初始化至当前 level；原 descriptor入口继续使用，注册类由真实 ClassDB 检查。library loader读取 descriptor，relative library路径相对 descriptor目录解析。

前置假设依次是：editor提前加载带来不必要文档生命周期耦合；runtime加载不受支持；运行接口不完整；外置部署映射无法用于真实包。实际样本否定后三种失败预测，支持把纯信令所需 native服务启动交给运行入口。**这不是 EditorHelp 原生竞态的底层修复或完整宿主时序因果证明**：原 auto-editor/minimal AV及其文档 cleanup/deferred时序问题仍独立保留。

官方 current文档原始 XML和 pinned manager/filesystem/library_loader保存在 prototype `official/`；pinned `main.cpp` 保存在当前 `evidence/main-pinned.cpp`，每份来源URL/SHA登记清单。docs网页抓取被网络工具拒绝后使用官方 GitHub原文，没有凭记忆猜API。

### 部署职责

- 构建项目/PCK：仅信令场景、五个正式 GDScript及必要图标；零 autoload，不发现 native descriptor。
- 部署资产：EXE同目录的 `native/fate_server_signals.gdextension` 与原 DLL，完整SHA显式登记。部署 descriptor只把 Windows库映射改为同目录relative DLL；正式source descriptor原件未动，入口、reloadable、Linux声明和exposed注册均未变。
- 运行入口：只有纯信令包显式声明 `network/signaling_native_descriptor="native/fate_server_signals.gdextension"` 才采用外置路径。路径固定由本机部署者声明，网络配置不能挑选 DLL/类/脚本。
- 原生准入：立即核对 LoadStatus、manager loaded、四类 `class_exists/can_instantiate` 和13个方法，再由原 `server_process_signals.gd.create()` 包装器实例化。原包装器发现ClassDB已注册，不再走旧res descriptor回退。
- 未声明该设置的正式client/server、原项目和原包装器加载行为不变。无 native声明的旧项目不会被本轮暗中改成延后加载；其他角色也不调用此信令入口。

信令面仍只交换建立直连所需的 create/join/offer/answer；数据面实际offer/answer验证为握手消息，不是游戏转发；权威面没有 gateway/worker/规则/autoload实例化。真实WebSocket流量对 game/save/rules/match_command全部返回明确拒绝。没有新增存档协议或服务器游戏数据。

## 前置 prototype 与生产接线顺序

prototype两份输入各14文件，逐文件集合及SHA完全相同，用户缓存目录各自新建、不继承 `.godot`。cold PID30792/PID33668均 exit0且未加载 Fate DLL；runtime PID6280/PID14068均 load_status0、四类/方法全部true、READY、合法CTRL_BREAK exit0。第二份验证完整offer/answer，第一份验证create/join及游戏消息拒绝。各自原生专项 PID33960/PID9224均23/23、exit0。

生产边界测试先 RED：PID26424，原件为 `round53-entry-contract-red-sa1/entry-red-result.json`，缺 `_load_signaling_native` 时明确打印 `missing explicit initialization boundary` 并exit1；新增最小边界后独立GREEN原件在 `round53-entry-contract-green-sa1/`，真实LoadStatus0/四类方法核对/exit0。此测试不是cold重试。

生产项目输入各12文件，完全相同，fingerprint：`63cc0ebf7ae993dcbe4fdf8cca994dc1c6df81bb65f56bc5baa2fc26daf94553`。fingerprint对 `files` 使用 sorted keys、紧凑JSON后SHA256。每次运行前后核对来源，最终 source drift为空。

|生产步骤|fresh1实际PID/exit|fresh2实际PID/exit|加载原DLL|
|---|---|---|---|
|首次 cold import|17776 / 0|20648 / 0|否|
|export-release|31132 / 0|19368 / 0|否|
|真正信令 EXE runtime|38588 / 0|23916 / 0|是|
|缺配置|14964 / 2|17200 / 2|是，先完成原生准入再拒绝配置|

真实runtime均完整 create/join/offer/answer、四种禁入消息拒绝、`SERVER_SIGNALING_NATIVE_READY` 四类/方法、`SERVER_SIGNALING_READY` 本次PID/port/roles=[relay]、`SERVER_SIGNALING_STOP_REQUEST request=2`，最终正常exit0、完整尾日志无未知 ERROR。日志不打印 token、nonce、认证密钥或配置内容。

## 四能力与 release模板的真实边界

原 DLL全功能保留：FateServerSignals、FateProcessOwner、FateAtomicFileReplace、FateCollectionIdentity，13个必要方法。正式包真实运行立即检查全部方法；不是用DLL字符串猜ClassDB注册。

附加能力审计一度被模板拒绝：带 `--path` 的调用exit1明确拒绝 path overrides；只去掉该参数的单变量调用exit2进入了正确的信令argc拒绝。pinned main.cpp确认 `OVERRIDE_PATH_ENABLED` 关闭时会清空 `--script/game_path/main_loop_type`。两次均保留原日志/结果及停止清单，不算能力执行，也没重跑production cold/export/runtime/negative。

改用官方支持的**独立诊断主场景**，不使用入口覆盖参数，另导出独立诊断PCK；其真实 EXE SHA与正式候选完全相同，DLL/外置descriptor也同SHA。诊断cold PID36656和export PID29712均exit0、不加载DLL；真正模板能力进程PID3860实测23/23、exit0：

- signals真实 enable、单owner拒绝、CTRL_BREAK投递读取一次/清空、protect_worker不收集。
- process owner真实available/spawn/state/verify，错误token及活进程release拒绝，terminate→exit→release。
- atomic真实覆盖并读回、源文件消失。
- collection identity实际ABI门、Array/Dictionary alias/distinct、修改后键稳定。

这份诊断PCK**不在正式候选**。报告区分“正式PCK实际入口注册/方法/信令功能”和“相同EXE/DLL的独立主场景四能力实测”，没有拼称其为同一PCK的一次运行。

## 包读回与原件

两包各18项PCK索引，逐项内容MD5/SHA检查；含bootstrap场景及五个正式脚本的 `.gd.remap/.gdc`，无data/规则/存档/测试/诊断场景/native descriptor/native DLL。native库不是被删除，而是明确的外置部署资产。

|对象|当前建议候选SHA256|
|---|---|
|官方editor EXE|`ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`|
|实际导出EXE/相同能力控制EXE|`d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562`|
|正式信令PCK|`c0d37d2e400db1ae0c23b6bc29bc37047f8a01721d2d236d1ae2551cd34c2119`|
|原DLL|`92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`|
|source descriptor未修改原件|`c84056e6c5190cda22ba8a6da080081dbce9d5ac86963e20a8dfe315e953ec4a`|
|仅部署relative映射descriptor|`441a1d645d3728105e7f7cf20303146d3e630d57a43a741cee67031d1fa91b62`|

第二个PCK SHA是 `d303394b208a6dd181d915d0c41d7b95433a984d11fd9bfe984d8b29dadffa0e`；不声称两次导出bit-for-bit可复现。两份源码输入一致、两份各自实际执行和静态核对事实分列。

## 安全执行、诊断器失效与回收

全部在物理独占E根，单child上限180秒；无GUI抢占。keeper创建独占console、持有自身及child精确创建FILETIME/handle。sender附着keeper前查身份/存活，发送前两次枚举只允许登记keeper/engine及sender三个成员；未知成员拒绝，不操作用户editor或按名称杀进程。保留Windows枚举至广播间非原子TOCTOU边界，不把console窗口X当合法CTRL_BREAK。

48个本轮登记keeper/engine PID最终精确身份检查均不存活，结果在 `evidence/owned-pid-postcheck.json`。native owner专项另外实际观察owned helper退出/release；不是只靠“engine退出”猜子进程归零。生成`.godot`和独占user缓存均先ZIP、CRC及逐文件SHA核验再回收；包、源码冻结、失败原件、原DLL和控制产物不删除。

prototype最初负向审计预期错成文件打开ERROR，停止为BLOCKED；对同一原日志离线查清是JSON parse明确scope后纠正，没有重新启动first negative或cold。该旧BLOCKED主件、离线核对回执均保留。release模板两个附加夹具失败也明确保留，不以最终成功覆盖它们。

最终9项Python准入/反例单测通过；生产边界RED/GREEN与缺READY反例RED/GREEN有真实退出/测试输出。最终离线再次核对实际READY PID/roles/port、CTRL_BREAK、精确负向scope、完整包哈希，未重跑Godot。

## 修改范围与未验边界

实际使用的执行入口（每个native child的完整argv/PID/exit见主清单；以下代码不是重跑已失败cold的授权）：

```text
python -B tools/diagnostics/round53_signaling_initialization.py --root E:/FateDiagnostics/round53-signaling-initialization-sa1 --godot D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe
python -B tools/diagnostics/round53_signaling_initialization.py --continue-audit-only --root E:/FateDiagnostics/round53-signaling-initialization-sa1 --godot D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe
python -B tools/release/signaling_prepare.py --root E:/FateCandidates/round53-signaling-runtime-entry-sa1 --godot D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --templates E:/FateCandidates/round52-current-roles-20261010-sa1/user/APPDATA/Godot/export_templates/4.7.2.stable --prototype-manifest E:/FateDiagnostics/round53-signaling-initialization-sa1/manifest-continuation.json
python -B tools/tests/round53_signaling_receipts.py
python -B tools/tests/round53_signaling_receipts.py --offline-finalize
python -B -m unittest tools.tests.test_round53_signaling_initialization -v
```

当次主构建先因附加审计argv范围停止，后用 `--continue-package-capability-audit` 单变量调用仍被官方模板入口范围拒绝，再用 `--continue-template-supported-control` 只补supported独立主场景控制及尚未执行的fresh2；原停止清单与全部argv保留。现在新构建的默认流程已采用supported能力主场景，不再把禁止的 `--path/--script` 传给正式EXE。

本轮修改生产文件仅 `scripts/net/server/server_bootstrap.gd`；`p2p_signal_server.gd`已存在的监听错误文本修改保留，本轮未改。新增 `tools/release/signaling_prepare.py`（此前不存在，先查实际定义）、`tools/diagnostics/round53_signaling_initialization.py`、三份自有测试/回执文件及本报告。原release工具、client/server源码行为、native源/DLL/descriptor/既有bin均未修改；未提交。

建议采用的是**纯信令初始化职责方案和此候选**。官方console wrapper已真实生成并核对hash，但wrapper路由自身退出/窗口关闭未跑；本次实际EXE是在独占keeper console中运行。GUI、窗口X、多机跨网、真正WebRTC数据直连、client/server本轮完整验收和最终三角色整合仍开放。不能拿这个信令GREEN替代游戏安全保存/worker/默认15房间整链验收，也不宣称新C++ Job/Cleanup core已发行。