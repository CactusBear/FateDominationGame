# 原生扩展与 Windows/Linux 导出准入审计

## 结论

**当前源码配置不满足“客户端与服务端包边界清晰”的准入；服务端预设具备纳入原生扩展的条件，但 Linux 当前已落盘 SO 不是包含 ProcessOwner 的构建。**

- `ProcessOwner` 源码已进入 `addons/fate_server_signals/SConstruct` 的 `Glob("src/*.cpp")`，因此从当前源码重建时会参与 Windows/Linux 两平台编译。
- 当前 Windows DLL 的字节中能找到 `FateProcessOwner`、`spawn`、`terminate`、`release` 等绑定字符串；当前 Linux `.so` 中找不到 `FateProcessOwner`、`ProcessOwner` 或 `spawn`。Linux 现有二进制不是当前 ProcessOwner 源码的可发布证据。
- 普通 Windows/Linux 客户端预设没有排除 `addons/fate_server_signals/*`。因此客户端正式导出具备把服务端原生扩展描述、平台库及同目录构建副产物一起带入 PCK/包目录的条件；本轮只做静态审计，未运行 Godot 或实际导出，不把“具备条件”写成已实际入包。
- `scratch/*`、测试、报告、文档和 Git 编辑器插件的客户端排除项已经存在，较上一批的 scratch 污染缺口已补上；但服务端专用扩展/脚本过滤仍不完整。

## 1. 预设逐项检查

证据：`export_presets.cfg:6–165`。

| 预设 | 关键配置 | 静态判断 |
|---|---|---|
| `FateDomination_demo_v1` | Windows Desktop，`dedicated_server=false`，无 `fate_server` feature，`export_filter="exclude"` | 客户端；排除了 `data/*,tests/*,reports/*,docs/*,scratch/*,addons/godot-git-plugin/*`，**未排除 `addons/fate_server_signals/*` 或服务端脚本** |
| `Linux` | Linux，`dedicated_server=false`，无 `fate_server` feature，`export_filter="all_resources"` | 客户端；同样未排除 `addons/fate_server_signals/*`，且 `all_resources` 对未经筛选的服务端资源更宽松 |
| `FateServer Linux` | Linux，`dedicated_server=true`，`custom_features="fate_server"`，`all_resources` | 服务端入口配置正确；显式包含 `assets/config/*.cfg`，保留 signals 扩展是必要的 |
| `FateServer Windows` | Windows Desktop，`dedicated_server=true`，`custom_features="fate_server"`，`all_resources` | 服务端入口配置正确；`debug/export_console_wrapper=2`，保留 signals 扩展是必要的 |

`project.godot` 已声明 `run/main_scene.fate_server` 和 `run/flush_stdout_on_print.fate_server=true`；这只证明 feature 路由/日志配置存在，不证明导出后的 PCK、扩展加载或 ABI 通过。

## 2. ProcessOwner 进入正式包的判断

### 源码与构建链

- `addons/fate_server_signals/SConstruct:4–7` 要求外部传入 godot-cpp 构建依赖；该依赖不应进入发行包。
- `addons/fate_server_signals/SConstruct:13–16` 对 `src/*.cpp` 做统一 `SharedLibrary` 构建。当前 `src/` 包含 `process_owner_binding.cpp`、`process_owner_core.cpp`、`server_signals.cpp`，所以构建输入层面没有漏掉 ProcessOwner。
- `fate_server_signals.gdextension:7–8` 只引用正式的 Windows `.dll` 与 Linux `.so`：
  - Windows：`bin/libfate_server_signals.windows.x86_64.dll`
  - Linux：`bin/libfate_server_signals.linux.x86_64.so`
- `scripts/net/server/server_process_signals.gd:4–7` 由服务端代码按固定路径加载扩展；`server_room_manager.gd` 再通过 `ClassDB.class_exists("FateProcessOwner")` 和 `available/spawn/state/verify/terminate/release` 使用进程所有权。

### 当前落盘二进制静态证据

| 文件 | 字节数 | SHA-256 | ProcessOwner 字符串扫描 |
|---|---:|---|---|
| `bin/libfate_server_signals.windows.x86_64.dll` | 370176 | `a0b6456f9b88cccb43ae3477e8d4ca909aa6cce3d6652cca42ebfb0caf219a73` | `FateProcessOwner`、`spawn` 均存在 |
| `bin/libfate_server_signals.linux.x86_64.so` | 469560 | `9edf007f0e2327226e8a31f601bf8ad68a4f13b5beeb9f963a936d8154ad78fe` | `FateProcessOwner`、`ProcessOwner`、`spawn` 均不存在 |

结论：

- **Windows 当前 DLL：**若被相应 Windows 服务端预设实际导出，静态上具备把 ProcessOwner 带入正式包的证据。
- **Linux 当前 SO：**不能准入。即使 Linux 预设会带入这个 `.so`，当前字节也没有新增绑定；必须用当前 `src/*.cpp` 重建并重新做字符串/符号/运行时检查。
- Windows 目录还存在无 `.dll` 后缀的 `libfate_server_signals.windows.x86_64`、`.exp`、`.lib`；Linux 目录存在无 `.so` 后缀的 `libfate_server_signals.linux.x86_64`。它们不是 `.gdextension` 当前引用目标，疑似构建副产物/旧产物。由于服务端和客户端都使用 `all_resources` 或宽泛资源导出，不能把它们留在冻结目录后再假设不会被打包；应在发布前清理并用空目录实际导出核对 PCK。

## 3. 客户端过滤完整性

**结论：不完整。** 已完成的是通用污染过滤，不是服务端边界过滤：

- 已有：客户端排除 `data/*`、`tests/*`、`reports/*`、`docs/*`、`scratch/*`、`addons/godot-git-plugin/*`。
- 缺少：客户端排除 `addons/fate_server_signals/*`（至少应排除整个服务端专用扩展；若客户端未来需要共享信号库，应改为只纳入明确的客户端库，而不是整目录）。
- 缺少：客户端对服务端专用脚本/场景/配置的明确筛选。无 `fate_server` feature 不等于资源不会进入 PCK；它只影响 feature 条件配置和启动入口。当前 `server_bootstrap`、`server_cli`、worker 场景及服务端脚本仍在项目资源树中，客户端预设没有对应排除规则。
- 客户端普通入口没有静态调用 `server_process_signals.gd`；该脚本由服务端 bootstrap/CLI/worker 路径加载。因此当前风险主要是包污染与错误平台库/副产物进入包，不是已经证明客户端启动必然实例化 ProcessOwner。

## 4. 未执行与准入边界

本审计严格未启动 Godot、未执行 Godot export、未启动 Windows/Linux 导出程序，也未加载 GDExtension。上述判断仅来自配置、源码和二进制静态扫描；PE/ELF 头部或字符串存在不能证明 ABI、Godot 解析、扩展加载、ProcessOwner `spawn/verify/terminate` 或 stdin/信号行为成功。

发布前必须：

1. 用当前源码和固定 godot-cpp 重新构建 Windows DLL 与 Linux SO；两平台分别确认绑定与架构/ABI。
2. 清理无后缀库、`.exp`、`.lib` 等构建副产物，重新冻结二进制 SHA-256。
3. 在全新空输出目录分别导出四个预设；静态读取 PCK，确认服务端包含两个正式目标库，客户端不含服务端扩展及服务端专用资源。
4. 从非项目工作目录运行真实服务端发行程序，分别验证 Windows/Linux 的 signals、ProcessOwner 建房/子进程身份校验/终止和安全退出。

## 修改记录

- 仅创建本报告：`scratch/net-batch-11/export.md`。
- 未修改生产源码、`export_presets.cfg`、`SConstruct` 或原生二进制。
