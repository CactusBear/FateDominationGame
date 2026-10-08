# 发行包准入审计（只读；未启动 Godot）

## 结论

**现有 Windows/Linux 服务端发行目录不准入。** 包内首次配置模板落后于当前源码，两平台均缺少当前强制依赖的 `fate_server_signals` 描述文件及二进制。源码预设中服务端隔离配置基本齐备；普通客户端预设仍有 scratch 污染风险。以下是静态证据，不是导出、引擎解析、ABI 或真实联机通过。

审计根：`E:/Projects/Godot/FateDominationGame-master`。只写本报告；未改生产文件、未导出、未启动引擎/发行程序。读取现有发行目录：`E:/Projects/Godot/FateDomination/test/server-dist/{windows,linux}`。源码可能由其他任务继续变更，本报告记录读取时状态，发布前应冻结并重做清单。

## 1. Windows/Linux 预设

| 预设 | 关键事实 | 准入判断 |
|---|---|---|
| FateDomination_demo_v1 | Windows x86_64；非 dedicated；无 feature；`export_filter="exclude"`、空 export_files；只排 `data/*`；`../FateDomination.exe`；非嵌入 PCK；console wrapper=0 | 未声明 scratch、tests、reports、docs、Git 编辑器插件排除；发布前整改/实查 PCK |
| Linux | Linux x86_64；非 dedicated；无 feature；all_resources；只排 `data/*`；export_path 为空；非嵌入 PCK | 需显式指定产物路径；同样缺 scratch 排除 |
| FateServer Linux | dedicated=true；feature=fate_server；all_resources；include=`assets/config/*.cfg`；排 data/tests/reports/docs/scratch/Git 插件；非嵌入 PCK | 配置层具备服务端入口与模板纳入条件；运行未验 |
| FateServer Windows | 同上；console wrapper=2；禁用签名及资源改写 | 配置层具备控制台包装；存在 wrapper 不证明 stdin/启动成功 |

证据：`export_presets.cfg:6–165`。`project.godot:25–26` 有专用 bootstrap 与 stdout flush；`:41` 仍声明 MCP autoload，导出插件 `_strip_mcp_autoload()` 在导出快照移除，不改磁盘项目设置。发布应检查最终 project.binary 的实际 autoload，不能仅凭插件源码认定剥离成功。

scratch 根无 `.gdignore`，当前有 **5 个 .tscn**、**2 个嵌套 project.godot**，还含重复 GDExtension 与 godot-cpp 示例；客户端预设漏排是具体配置风险，不是仅有文档/脚本的无害目录。服务端已有 `scratch/*` 排除。

本机 `C:/Users/Administrator/AppData/Roaming/Godot/export_templates/4.7.2.stable/` 已发现 Windows/Linux x86_64 debug/release 模板（含 Windows console 模板）。只确认存在，未执行模板。

## 2. GDExtension 与运行时依赖

路径解析：`res://` 相对仓库根；普通路径相对各 `.gdextension` 所在目录。当前源码中的 Windows/Linux x86_64 WebRTC debug/release、signals 两平台库、Git editor 两平台库均存在；PE machine=0x8664、ELF64 machine=62。**头部正确不等于可加载。**

| 运行时库 | 字节数 | SHA-256 |
|---|---:|---|
| signals Windows | 370176 | a0b6456f9b88cccb43ae3477e8d4ca909aa6cce3d6652cca42ebfb0caf219a73 |
| signals Linux | 469560 | 9edf007f0e2327226e8a31f601bf8ad68a4f13b5beeb9f963a936d8154ad78fe |
| WebRTC Windows release | 4058112 | 3a8053d325a874493f596630b0f165f3a83e265c61d9fd87d82da6cb4c2a81fd |
| WebRTC Linux release | 4338296 | 88c927c551592f526fdb13fab28536629fae026f8d738d7d83ce2cf2493db9e3 |

标准库静态解析 PE import / ELF DT_NEEDED：
- signals Windows：bcrypt.dll、KERNEL32.dll；WebRTC Windows：bcrypt.dll、IPHLPAPI.DLL、KERNEL32.dll、msvcrt.dll、WS2_32.dll。未发现对 VC++ redistributable DLL 的直接导入，但尚未验证目标机器/间接加载依赖。
- signals Linux：libstdc++.so.6、libm.so.6、libc.so.6、ld-linux-x86-64.so.2；版本字符串包括 GLIBCXX_3.4.32、CXXABI_1.3.9、GLIBC_2.14。需在最低支持发行版验证对应符号可用，不能以“有 libstdc++ 文件”替代。
- WebRTC Linux：libpthread.so.0、libm.so.6、libc.so.6、ld-linux-x86-64.so.2；版本字符串最高观察到 GLIBC_2.25。这里只给库的静态下界线索，**不是整个 Godot 发行包最低系统版本声明**。
- WebRTC minimum=4.3；signals minimum=4.4；Git 插件仅 editor feature 库项。服务端已排除 Git 插件，客户端未明确排除，需最终包复核。
- `addons/fate_server_signals/SConstruct` 明确 godot-cpp 构建依赖由构建者传入；不是运行时 Python/SCons 依赖。signals 两平台共享输出名不区分 debug/release，需保留实际构建版本和 ABI 证据。

`server_process_signals.gd:5–7` 显式加载 signals 并实例化 FateServerSignals；`server_cli.gd:162–168` 无适配器/enable 失败则退出。当前源码已将其视为强制依赖，不能仅打包 WebRTC。

## 3. 现有发行包的直接证据

用 Python 标准库读取未加密 PCK v4，不调用 Godot：magic=GDPC，engine=4.7.2，file_base=112，directory_offset=305293248。Windows/Linux PCK 均为 305419900 字节、1404 项，范围检查无越界；路径规范化后未发现 scratch/tests/data/reports/docs/Git 插件条目。

两包 SHA-256 相同：`db0b302a13852361803ff941e630675c715c916052283dbaf83172e36fc6cbcf`。

**产物阻断：**
1. 两包只发现 WebRTC 的 `.gdextension`，未发现 signals 描述文件；递归检查各发行目录也无 signals DLL/SO。这是当前依赖闭包不完整的确定证据，现有包不能代表当前源码。
2. 包内 `assets/config/server.cfg` 可读且目录 MD5 校验通过，但 SHA-256=`1d46a174ccc0c7e03424db2d0d18a1935416add34284c00db03681a1656bab74`；源码模板为 `9002b3f6f8085e1d60fffa1236b9a77a5a16d6cce5a7bfe504de33932c2b1fb1`，不一致。包内模板缺源码新增的 identity_attempts_per_second、identity_profile_max_bytes、authority_host_mode、transaction_log、recovery_key_mismatch、recovery_inheritance 等声明。不能将旧包内模板作为当前版本冻结证据。
3. Windows 目录还有 `FateServer.pck151348380.tmp`（112 字节），发布清单应剔除；未删除。
4. 包中仍有 MCP game_helper.gdc/remap 文件。文件存在不证明 autoload 仍启用，需另解析导出设置/真实启动；此项不直接断言插件剥离失败。

**外置数据静态检查通过：**排除 `.import` 后，源码及每个平台外置 data 各205文件，全量 SHA-256 对比缺失0、额外0、内容不同0。每平台另有134个 `.import`，单列为导入元数据，不误报为额外规则。文件一致不证明加载器成功。

## 4. 配置、数据及子进程入口

- `assets/config/server.cfg` 当前声明 dedicated 权威、审计、密钥不匹配拒绝与房主选择继承、身份登记及预算；随机模拟显式开关与60秒独立声明；只允许 game/relay 角色。纯 relay 不能借游戏项目伪装规则隔离。
- `server_cli.gd:20–27,217–233` 缺 CFG 时复制包内模板并退出；已有配置不覆盖，未知/坏配置拒绝。配置路径由 CLI 原样使用，相对 `--config` 仍依赖调用工作目录；部署手册应使用绝对路径。
- `LoadHelper:20–30,41–48` editor 走项目根，发行版外置 data 走可执行文件同级，不回退包内 data。user:// 身份、房间存储与本机控制目录需可写；独立进程须有执行权限、目录读写权和明确的资源/端口预算。
- 导出插件 `mcp_export_plugin.gd:43–45,63–105` 同时复制外置 data 与剥离 MCP autoload；依赖插件参与真实导出。复制仅替换同名文件，不清除旧目录多余文件；失败只 push_error 后返回，不能仅凭导出退出码推断 data 完整。必须使用新的空版本目录并核对逐文件清单。
- 服务端 bootstrap 按业务参数路由网关/房间/校验/console，拒绝多个职责；`process_arguments:56–69` 在 fate_server 时移除 --path/--scene，保留日志及 -- 后业务参数；新建/恢复房间与验证进程均走此函数。
- **客户端发行风险（静态确认，未复现）：**RoomValidationTask:50,76 构造 --path/--scene 后调用同一函数，但普通客户端无 fate_server，函数原样返回；客户端主入口是 opening_background，未见针对校验业务参数的 bootstrap 路由。这条 release 房主数据预检路径需专测并补适合客户端导出版的入口，不能以专用服务端预检通过替代。
- 纯信令 bootstrap 明确拒绝存在 autoload；独立信令项目目前位于 scratch，服务端预设排除它。本次四个预设不构成纯信令独立发行物；若要求单独信令发行，需要独立正式项目/冻结产物，不应靠取消 scratch 排除混入游戏包。

## 5. 分开记录阻断与待验收

### 代码/配置/产物阻断（不归咎环境）
- 现有 Windows/Linux 服务端产物缺强制原生依赖、模板落后：重建且核对包内容前不准入。
- 客户端 scratch 排除缺失；Linux 客户端默认输出路径未定。
- 普通客户端 release 隔离数据预检入口/参数适配存在缺口，需验证并处理。
- 复制插件旧文件残留及失败不构成硬发布门禁；发布流程必须增加空目录和全量清单检查。

### 环境/执行限制（不能冒充代码已通过）
- 本任务明确禁止启动 Godot，因此真实导出、ABI、启动、stdin、加载、子进程管理与实际网络均未执行。
- 最低 Linux 目标系统的 GLIBCXX_3.4.32 等符号支持、图形/音频依赖以及本机/远端权限未实测；没有运行证据不能声明兼容。
- 未建立真人、多机、跨 NAT 的发行验收环境。本机/WSL 测试即使另批通过，也不证明这些项目。

### 发布前保留的验收清单（均未由本审计执行）
- [ ] 冻结源码/模板/原生库 SHA；空版本目录真实 Windows/Linux release 导出；回读 PCK、project.binary、配置与平台依赖；拒绝临时文件与 scratch/测试泄漏。
- [ ] 从非项目工作目录首次生成 CFG 后退出且不监听；第二次启动、损坏配置拒绝、外置 data 数量与字节验证；最低 Linux 系统加载全部库。
- [ ] Windows console wrapper 的 stdin/EOF、空闲网络响应；Linux 控制台及安全信号退出；网关/新建房间/恢复房间/隔离预检均使用真实发行进程，日志和 ready 绑定本次 PID。
- [ ] 两个真人客户端在不同机器完整建房、预检、数据选择/同步/哈希、选人、隐私、真实提交及终局；客户端不得运行权威规则；真人掉线不得 AI 接管。
- [ ] 物理 Linux 与 Windows 客机互联；不同网络及 NAT 的 P2P 直连、失败提示/超时；信令仅交换握手，不承载对局流量；公网防火墙 TCP/UDP 与内部端口边界检查。
- [ ] 独立服务端跨网多人完整局；认证密钥不匹配拒绝、房主显式继承、子进程崩溃保留恢复目标；先保存→重启→凭据重连→恢复对局；安全关服与子进程清理。

未执行命令：所有 Godot import/export/headless/窗口命令、发行 exe/ELF 启动、WSL 网络验收及真人输入。本报告没有修复上述生产问题，也不将任何静态检查标为运行通过。
