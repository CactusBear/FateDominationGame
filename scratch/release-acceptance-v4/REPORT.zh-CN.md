# 独立服务端发行静态验收 v4

## 结论
**当前 Windows/Linux 旧发行目录不可作为当前源码的发行验收包。源码结构部分通过；发行准入拒绝。所有 Godot/游戏/信号/网络动态验收均为 NOT_RUN。**

仅读取生产、旧导出目录及历史报告；只写 `scratch/release-acceptance-v4/`，未启动 Godot、未执行导出、未修改生产/配置/存档、未操作凭据。其他代理可能继续写入，指纹是扫描快照，非原子冻结。

先读 `hermesWarning.txt`，再读历史 `cache/scratch/release-acceptance-audit/REPORT.zh-CN.md`、`scratch/authority-worker-v2/HANDOFF.md`、`scratch/final-freeze-v3/REPORT.zh-CN.md`、`docs/acceptance-root-authority-identity-audit.md`、`docs/multiplayer-server-progress.md`。历史绿属于旧版本，不计入本轮。

## 实际执行证据
- `python scratch/release-acceptance-v4/static_inventory.py`，退出 0。标准库读取未加密 Godot v4 PCK 目录，检查 magic/版本/文件范围，提取 CFG，逐文件 SHA256 比较外置 data；没有调用引擎。
- 两平台 PCK 各 1404 项；完整索引分别写入 `windows-pck-index.json`、`linux-pck-index.json`。核心源码、原生信号库和发行顶层文件的 SHA256/大小/mtime 在 `static-result.json`。
- 两平台当前 data 各 339 文件；源码非 `.import` 内容 205 项全部存在且 SHA256 一致；额外 134 项全部为 `.import`，**未发现额外规则 JSON**。插件原样递归复制解释这些附加文件，不能将其误称陈旧规则。
- 两平台 PCK 的 `data/` 项为 0；`fate_server_signals` 项为 0。顶层也无信号 DLL/SO，缺少当前启动保护依赖。
- 当前子代理环境无 `FATE_*` 环境变量；这是本进程环境，不推断父代理/桌面/WSL环境也为空。

## 逐项静态结果

| 项目 | 静态结论 | 证据与限制 |
|---|---|---|
| Windows dedicated 预设 | STATIC_PASS | `export_presets.cfg:145–165`，dedicated_server=true、fate_server、x86_64、外置PCK、wrapper=2、包含 CFG、排除 data/tests/docs/reports/Git 插件。不证明导出成功。 |
| Linux dedicated 预设 | STATIC_PASS | 同文件 124–143，dedicated_server=true、fate_server、x86_64、外置PCK；普通 Linux 客户端目前也已排除 data，历史缺口已消除。 |
| release 启动与 stdout | STATIC_PASS | `project.godot:25–26` feature 主场景与 stdout flush；bootstrap:71–93 按职责分支，重复/冲突拒绝。 |
| 子进程 release 参数 | STATIC_PASS | bootstrap:56–69 移除分隔符前 --path/--scene，保留业务参数；manager、room_validation_task 调用同一函数。新建/恢复/预检的真实进程启动 NOT_RUN。 |
| 四策略声明/管理器消费者 | STATIC_PASS（结构） | CFG:28–33；policy.validate:11–25；CLI:89–100→manager.configure_server_policy:29–42。历史“方法不存在导致默认服务必失败”已经不成立。manager 配置持久化包含四字段，worker 读取并验证。 |
| transaction_log=false 语义 | STATIC_GAP | worker:55、179 仅决定未录制时独立审计；开启 record_matches 时由 MatchReplay 持久化审计，ready:314 使用 record_matches or audit_journal。故 false+record_matches=true 仍会持久化事务审计；CFG“审计开关”不等于严格全局禁用。需明确录制必带审计还是禁用应覆盖录制，不能伪称四组合已验。 |
| Windows 旧包结构 | STATIC_FAIL（当前发行准入） | exe、console.exe、PCK、WebRTC DLL、data 存在；另有 `FateServer.pck151348380.tmp`，应隔离旧目录而非覆盖。无信号扩展；外置 server.cfg 缺四策略、roles、identity_registry 和管理配置。 |
| Linux 旧包结构 | STATIC_FAIL（当前发行准入） | ELF、PCK、WebRTC SO、data 存在；无顶层 CFG 不必单独判失败（首次启动可生成），但无信号扩展，PCK 模板旧。 |
| 旧包内 CFG 与当前源码一致 | STATIC_FAIL | 两包内 CFG 同 SHA256 `1d46a174ccc0c7e03424db2d0d18a1935416add34284c00db03681a1656bab74`，缺 authority_host_mode/transaction_log/recovery_key_mismatch/recovery_inheritance、identity budget 字段；当前源码已含。新文件存在不证明旧PCK更新。 |
| 源码信号依赖 | STATIC_PASS（存在） | gdextension 固定 Windows/Linux x86_64 DLL/SO；两文件实际存在，magic 为 PE/ELF，指纹记录。目录还含无后缀构建文件与 `~` DLL，应采用显式发布白名单。ABI/系统动态库/加载成功 NOT_RUN。 |
| 系统信号边界 | STATIC_PASS（源码声明） | C++:20 仅 Ctrl+C/Ctrl+Break；62–65 为 SIGINT/SIGTERM；CLI:162–168 要求适配器成功、238–244 走保存关服。窗口关闭/LOGOFF/系统关机不受此白名单保护。worker protect_worker 不是保存，孤儿退出不是安全关服。 |
| Windows console wrapper | STATIC_PASS（文件/预设） | 旧目录有 console.exe；当前 wrapper=2。stdin 真可用 NOT_RUN，不据旧文件认定新包生成。 |
| stdin 进程职责 | STATIC_PASS | server_console:29–58 阻塞读 stdin；网关经本机文件通道处理管理命令。必须单独 `--server-console <控制目录>`，向网关本体管道输入不是该入口。EOF/exit 只退出输入端。 |
| 纯信令隔离 | STATIC_PASS（候选结构）/NOT_RELEASED | staged signaling-project 没有 [autoload]；5 个网络脚本、场景和信号扩展候选独立于规则。当前根项目有规则 autoload；bootstrap:103–105 与 CLI:47–49 拒绝冒充纯信令。正式预设没有独立信令发行目标。 |
| 纯信令候选同步 | STATIC_GAP | stage 中 server_bootstrap.gd SHA 与当前源码不同（其他共享脚本/信号库一致），需重暂存再核对依赖闭包。不能以旧候选证明当前配置校验已一致。没有发布信令 EXE/ELF/PCK。 |
| data 路径 | STATIC_PASS | LoadHelper global/load_helper.gd:20–30：导出相对路径锚定 executable 目录；CLI:123 调 resolve_path(data_root)。异 cwd 实际读取 NOT_RUN。 |
| storage/identity/control/status 路径 | STATIC_CAUTION | CLI 直接赋 storage_root，默认 user://server_rooms；identity 和 console 经 resolve_path，status_file 原样使用。storage/status 若写裸相对路径不能假定与 data 一样锚定 exe；动态清单要求各自绝对隔离路径。默认 user://可能命中已有用户数据，禁止本轮用默认做恢复。 |
| 外置复制失败门槛 | STATIC_GAP | mcp_export_plugin:68–75 只 push_error 后返回；不会清除目标多余文件。必须空目录导出并独立核验全日志、产物、data manifest，不能只看 exit=0。 |
| 旧包误测环境变量 | STATIC_CAUTION | export_test/identity 使用 FATE_TEST_SERVER_EXECUTABLE；roles 用 FATE_TEST_SERVER_BINARY（不同变量）。reload 硬编码旧 Windows exe，create 继承它；信号协调器硬编码旧 console.exe，缺 --windows-exe/--output-root。见动态清单阻断项。 |
| 版本化/冻结 | NOT_RUN | 本次无干净克隆、源码冻结、构建来源签名或二进制来源证明。禁止将历史报告 checks 汇总成当前 release 通过。 |

## 动态验收准入与交接
所有命令及必须串行的顺序在 `DYNAMIC_COMMANDS.zh-CN.md`；每项状态 **NOT_RUN**。主代理须先结束写入者、完成冻结/干净副本，使用全新构建与存储根，核对本次产物 SHA，再执行。不得把本审计发现的旧包缺依赖解释为当前源码启动一定失败；当前源码从未运行。

验收结束至少同时核对实际 OS 进程身份/退出、完整 RESULT 和 checks、SCRIPT/SHADER/引擎错误、当批次日志与 ready/实例、真正落盘的保存及审计文件；新PID、字段存在或 has_method 都不能替代中局恢复与根事务回滚。
