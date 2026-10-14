# 真人测试启动器：来源、白名单与未验边界

> **这是模板，尚未随真实包验证。** 本次只提供可审计的启动脚本来源和模拟执行证据；没有启动 Godot、导出、组真实包或认证双实例联机。`HUMAN_TEST_CANDIDATE` 不变，不授予 release PASS / READY。

## 来源与逐脚本行为

路径迁移与接线补记：模板已原字节迁到 `release/human-test/`，不为隐私策略中的 `tools` 禁入组件开例外；角色冻结声明和组包消费者已接入 CMD/helper 的显式映射与哈希校验。下文“尚未接线”“不修改 quickstart”及旧行号是模板首次交付时的历史记录，不代表当前工具状态；当前启动说明以 `human-test-quickstart.md` 为准。真实导出/运行与最终 ZIP 验证仍未进行。

来源放在 `release/human-test/`：这里属于发行模板，不与生产 GD、导出预设耦合。包内必须按下表复制，不能直接从源码模板目录启动游戏。

| 源文件 | 包内目标（相对包根） | 行为 |
| --- | --- | --- |
| `START-CLIENT.cmd` | `client/START-CLIENT.cmd` | 选 client 角色，调用同目录共享脚本，启动同目录 `FateDomination.exe`；不传引擎/业务参数，正式菜单选择协议。拒绝任意 CMD 参数；返回共享脚本退出码。 |
| `START-SERVER.cmd` | `server/START-SERVER.cmd` | 选 server 角色；同目录 `FateServer.exe --headless -- --server-gateway --config "<同目录>/server.cfg"`。配置缺失即拒绝，不让产品自动生成配置后被误认为启动成功。 |
| `START-SIGNALING.cmd` | `signaling/START-SIGNALING.cmd` | 选 signaling 角色；同目录 `FateSignaling.exe --headless -- --server-signaling --config "<同目录>/signaling.json"`。只适用于独立、无游戏 autoload 的纯信令导出；不冒充游戏服务。 |
| `Launch-HumanTest.ps1` | 每个包含角色的目录各一份 | 基于自身 `$PSScriptRoot` 定位 EXE/配置，包根为其父目录；统一校验路径、选身份、创建运行目录、设置环境、打印命令、等待进程、记录并返回真实退出码。不能漏复制这个依赖。 |

CMD 用 `%~dp0` 找共享脚本，关闭 delayed expansion，不猜路径或透传凭据。每个 CMD 都打印 `LAUNCHER_EXIT_CODE`，默认等待按键保留双击证据；自动化可在当前 CMD 设置 `FD_LAUNCH_NO_PAUSE=1` 关闭这一按键等待。不是进程超时，也不改变游戏行为。

共享脚本依赖 Windows PowerShell 5.1；用 `-NoProfile -ExecutionPolicy Bypass` 执行，仅影响本次 PowerShell 进程，不修改系统策略。组织强制策略仍可能阻断，不能据模拟结果承诺所有机器可运行。

### 目录与双客户端

- client 的身份标签只接受 `host` / `guest`：显式 `FD_CLIENT_PROFILE` 优先；否则只接受 quickstart 中两组完整匹配的 APPDATA/LOCALAPPDATA；混用 host/guest 会拒绝；两组都不匹配则交互询问标签。不会沿用任意外部用户目录。
- 两个标签分别落到包根的 `test-users/host/`、`test-users/guest/`。同标签双开仍是同身份，模板不声称自动分配第三个身份或防止误选。
- server、signaling 分别使用 `test-users/server/`、`test-users/signaling/`，不使用客户端身份目录。
- 每个角色/身份都显式设置 APPDATA=`<身份目录>/appdata`、LOCALAPPDATA=`<身份目录>/localappdata`，并把 TEMP/TMP/TMPDIR 指到 `<身份目录>/temp`。设置仅在子 PowerShell 及其产品子进程中生效，不修改系统或调用者永久环境。
- 在创建这些目录前拒绝系统盘（本机 C 盘）、UNC 和现有路径上的重解析点。包应完整解压到可写的 E 盘普通目录；含空格、中文的普通路径已模拟核验。路径含引号、换行或 `% & | < > ^ !` 会拒绝，不承诺支持此类目录名。
- 不删除身份、存档、缓存或已有运行目录；不按 PID/进程名强杀、不打开额外端口。

在两个独立 CMD 窗口分别从包根运行（也可直接双击后分别输入标签）：

```bat
rem 房主窗口
set "FD_CLIENT_PROFILE=host"
client\START-CLIENT.cmd
```

```bat
rem 客机窗口
set "FD_CLIENT_PROFILE=guest"
client\START-CLIENT.cmd
```

也支持 [human-test-quickstart.md](human-test-quickstart.md) 原有两组 APPDATA/LOCALAPPDATA 命令，不需要更改它们。若已经设置 FD_CLIENT_PROFILE，请先确认其标签与当前窗口目的相符，它的优先级更高。

### 配置与期限：不猜数值

部署者必须提供与这次导出匹配且已确认的 `server/server.cfg`、`signaling/signaling.json`；本次不创建、读取或打印这些文件的内容，也不携带任何身份密钥、票据或登记库。

- server 使用显式 `--config`；地址、端口、角色、启动/关服期限及 worker 预算只由该配置提供。部署清单须显式确认 `startup_seconds`、`shutdown_seconds`、`room_runtime`、`heartbeat_publication` 等当前源码实际消费字段，不把产品已有缺省值当作部署者声明。脚本没有私设 watchdog、启动秒数或 `--quit-after`。
- signaling 使用独立 JSON 配置，必须显式 `roles=["relay"]`；不能照搬游戏配置，也不能向纯信令加入不接受的游戏启动期限字段。需要的信令期限在该版本实际支持的 `relay` 配置中声明。
- 路径写入行为还可能由产品配置（storage_root、console_dir、status_file 等）独立控制。部署者须审核这些落点都在 E 盘/包的隔离目录；环境变量不能覆盖配置内写死的 C 盘绝对路径。模板只检查配置存在，不宣称已审计其内容或防止产品任意文件写入。
- client 的局域网 authority 子进程期限来自正式产品入口的本机声明，不向客户端强塞未经源码支持的启动 CLI 参数；该传递链未做真实包验证。

### 取证与隐私

启动前打印 ROLE/PROFILE、工作目录、隔离目录、完整命令；正常进程结束后打印 PROCESS_ID / EXIT_CODE，并返回该退出码。启动器失败返回 2，只打印失败阶段，不输出异常文本或调用者输入。

相同条目写入 `test-users/<标签>/launcher-evidence/<随机标识>.log`；每次新建，不用旧日志证明本次启动。共享脚本显式 `Start-Process -Wait -PassThru -NoNewWindow`，包括 GUI EXE 也等待，不用异步 `start` 丢失退出码。没有就绪判断或超时强杀；进程退出码不是联机成功证据。

启动器不读取/复制/摘要/打印密钥和恢复票据，不采集产品 stdout/stderr 到自己的日志。产品输出仍可出现在窗口，须另行脱敏，不能承诺产品自身永不输出私密内容。身份目录、完整配置、存档和运行日志不得放入包或默认上传；启动器日志虽不含密钥，也含本机路径，反馈前要脱敏。独立服务正常 stop / Ctrl+Break 路由、保存收尾和端口释放须按正式产品说明另验，不能关闭窗口/强杀替代。

## 组包白名单清单（仅说明，未改工具）

按发行声明的精确 preset/platform/role 决定包含角色；client-only 包不加入 server/signaling 启动器。EXE 名称必须与上表一致；若目标声明不同，先报告并更新模板，不能静默猜测。

新增外置文件集合：

```text
client/START-CLIENT.cmd                  <- release/human-test/START-CLIENT.cmd
client/Launch-HumanTest.ps1              <- release/human-test/Launch-HumanTest.ps1
server/START-SERVER.cmd                  <- release/human-test/START-SERVER.cmd
server/Launch-HumanTest.ps1              <- release/human-test/Launch-HumanTest.ps1
signaling/START-SIGNALING.cmd            <- release/human-test/START-SIGNALING.cmd
signaling/Launch-HumanTest.ps1           <- release/human-test/Launch-HumanTest.ps1
docs/human-test-launcher-source.md       <- docs/human-test-launcher-source.md
```

部署者审核后的 server.cfg / signaling.json 是另外的配置白名单条目，本次没有提供它们或其哈希。继续保留已有二进制/PCK/data/native 白名单，不能用这个启动文件清单替代它。

对支持 `runtime_files` 的角色冻结，现有 `release_contract.py` 和 `freeze_prepare.py` 可用下面的显式映射形状（例为 client，追加到该角色既有依赖，不能覆写整个依赖数组）：

```json
[
  {"source":"release/human-test/START-CLIENT.cmd","target":"START-CLIENT.cmd"},
  {"source":"release/human-test/Launch-HumanTest.ps1","target":"Launch-HumanTest.ps1"}
]
```

server/signaling 按角色换 CMD 源/目标，辅助脚本保持同名。source 必须真实存在于该角色冻结输入；独立信令工程不能用越界相对路径指回游戏仓库，需在独立发行输入中显式暂存同哈希的模板。目标在**角色包根**，不是 PCK；不复制整个 `tools/`、tests、reports 或开发源码。

组包消费者必须：

1. 在冻结前显式声明上述来源和 source SHA256；仅复制列出的精确文件，不 glob 整个模板目录。
2. 在角色 manifest 的 package_files、最终成员白名单与逐文件 SHA256 中纳入 CMD 和 PS1；共享 PS1 三份必须同 SHA256。按原始字节复制，不自动换行规范化。
3. 把本说明作为最终包 docs 的显式成员；复制文档的现有检查不能代表新增文档已加入白名单。
4. 排除 `test-users/**`、launcher-evidence、net_identity、savedkeys、票据、身份登记库、认证元数据、缓存、完整存档和诊断运行输出；在独立测试副本运行，不污染干净组包目录。
5. 组包后读回精确文件集合、哈希和 ZIP 成员；没有消费这份清单不能称“来源已接线”。

**现有工具冲突，尚未接线：** `human_test_candidate.py:274-275` 仍自行生成透传 `%*` 的启动器；`:361-367` 会覆盖包内同名 CMD，并禁止其文本含 APPDATA/LOCALAPPDATA；`:538-544` 只自动加入现有 CMD 名称，不自动加入新增 helper/docs。本模板的 APPDATA 设置在 PS1 中，并不因此与其来源/哈希契约兼容；旧工具覆盖 CMD 后会使 helper 无人调用，声明映射不足以完成接线。必须后续由工具所有者处理明确白名单/来源绑定、禁止覆盖和最终哈希比对；**本次只报告，不修改工具，也不靠组包后手工替换绕过 manifest。**

## 与 quickstart 的一致性核对（不修改 quickstart）

| 项目 | 结果 |
| --- | --- |
| client/START-CLIENT.cmd 与三角色 EXE 名称 | 一致；包内目标名称按 quickstart 第 11–13 行。没有额外创建历史 `Start.cmd` 别名。 |
| 两个客户端各自 APPDATA/LOCALAPPDATA | 一致；quickstart 第 25–26、36–37 行映射为 host/guest，同组匹配可无交互启动。模拟程序观察到两个不同目录，不证明已经生成两个正式身份。 |
| 同机局域网无需手动 server/signaling | 一致；本模板不会从 client 入口自动启动这两个独立角色。 |
| quickstart 第 11、53 行允许直接双击 EXE，落当前 Windows APPDATA | **不一致/仍有污染系统盘风险**；只有启动 CMD 才执行隔离。模板不能改变用户绕开脚本直接双击 EXE 的行为。 |
| quickstart 第 64–65 行直接 EXE + 任意已确认配置路径 | **用法不一致**；原命令绕过隔离。模板固定用角色目录里的 server.cfg / signaling.json，不接受任意 CLI 路径。角色参数本身一致。 |
| 普通“双击启动”存档位置 | **需区分**：双击 EXE 仍是原用户目录；双击新 CMD 选择 host/guest 后是 test-users 下的隔离目录。原 quickstart 未区分这两个入口，本次只报告。 |
| 完整 GUI 双客户端/真实包恢复未通过声明 | 一致；仍 NOTRUN/UNKNOWN，不升级。 |

## 本次核验与待验

实际命令（只运行模拟 EXE，不是 Godot）：

```text
python -B E:/Projects/Godot/FateDomination/test/launcher-source-audit/verify.py
```

回执：`E:/Projects/Godot/FateDomination/test/launcher-source-audit/verification.json`，命令退出 0，14 个模拟用例全部满足预期。模拟程序退出 7，三种 CMD 均返回 7；失败场景返回 2。覆盖显式 host/guest、quickstart 两组环境、交互标签、角色 argv/配置路径、中文空格路径、临时目录继承、缺二进制/配置、非法/混合身份、额外参数、junction 拒绝与系统盘拒绝（后者只模拟 SystemDrive=E，不在 C 盘建测试目录）。非法输入用非秘密标记确认未被回显。模拟配置故意不可解析，证明启动器不读取它，不代表有效产品配置。

**仍未验证：真实包内 EXE/PCK/native 依赖启动；直接资源/配置兼容；GUI EXE 自然退出及退出码；双实例正式身份生成、认证、创建/加入与完整联机；authority worker 配置传递/就绪；保存恢复；服务 stop/Ctrl+Break 及树级退出/端口释放；组包工具消费这些模板和最终 ZIP 哈希；组织策略环境、多机与跨网。**

## 启动来源 SHA256

路径相对仓库根；哈希为本次核验原始字节（不是生成包的哈希）：

```text
aa7a79999c65ace26a1c773aa4dc7938fd7dc1258cf7149ffa64c5c0b46cf074  release/human-test/START-CLIENT.cmd
ee818ccd8626d3381591487190b5b634e7c097f54f72a43cba8b402682542338  release/human-test/START-SERVER.cmd
efb47b65d23b777bd4183ae671185085f629cc6e2b2322fb3053324573bc19e9  release/human-test/START-SIGNALING.cmd
90165efeb8a38e149c9078fc4b7ae58ce3ae84b8e3e6b7010453bcc67a980b21  release/human-test/Launch-HumanTest.ps1
```

本说明自身哈希在交付回执中单列，不把文件自身哈希写入本文件形成循环。
