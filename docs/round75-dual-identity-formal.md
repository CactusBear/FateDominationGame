# round75：正式身份入口隔离验证（未证实，等待批准）

## 结论
**未证实。按“执行不明就停下”的要求，没有换参数重试，也没有启动 guest。**

本次已经亲读候选说明、launcher、PCK 索引与旧包对应冻结源码，定位了正式身份准备入口；但旧候选 EXE 启动后没有出现外置驱动任何执行回执，45 秒单阶段看门狗触发。两侧身份目录仍不存在。自有 Job 已收尾为 active=0，但所有观察进程退出码为强制停止的 125，**不能称为正常退出通过**。日志没有 SCRIPT ERROR，却也没有身份按钮执行证据，不能用无错误或空集合宣布身份隔离成功。

`old_artifact=true / nonfinal=true`。本报告不宣称当前源码已打包、不宣称最终发行通过。

## 继续需要什么批准
批准改走 **E 盘隔离副本内两个自有非 headless 窗口**，只填写合法用户名/昵称、点击正式「身份资料应用」按钮和正常退出，不建房、不连接、不读取/截图/采集凭据界面。若工具无法避免采集凭据界面，则由用户手动执行这几个按钮步骤，runner 仅观测目录/文件名/SHA 和进程退出。

**不是请求批准游戏数据根或猜测 identity-root 参数。** 本次离线 UI 身份入口不需要这两类参数；用户已授权的 E 盘身份落点无需再猜。批准前不再启动客户端。本轮没有证据断言旧 EXE 必然不支持 `--script`，也不能断言产品身份生成失败：只证实本次外置驱动没有执行回执，无法区分参数入口受限、脚本未进入或启动尚未完成。

## 正式入口及说明差异
- 候选 quickstart:19–40 的两个 APPDATA/LOCALAPPDATA 命令隔离 user://；START-CLIENT.cmd 没有重置这两个变量。
- quickstart:43 写“身份密钥由正常 UI 自动生成”，但**填用户名本身不生成**。旧冻结 `project-client/scripts/net/ui/lobby_screen.gd:42–44` 把身份应用按钮连接到 `_prepare_identity()`；:355–360 调用 `session.configure_identity()`。创建/加入也会准备身份，但本任务不需要走到建房或联机。
- 正式缺省路径 `user://net_identity/private.pem`。离线准备可能只有此文件；profile.json 的不存在不能单独判失败。
- 测试驱动没有直接调用密钥生成、`configure_identity()` 或 `_prepare_identity()`，也没有复制或伪造身份；它计划从 PCK 正式主场景经开场键盘事件、主菜单按钮信号、大厅身份按钮信号走真实处理链。**该计划在本次实际 EXE 中未拿到执行回执，因此不能当成链路已跑通。**
- 最小修正建议（只报告，不改候选包）：quickstart:43 补“填写合法用户名和昵称后，在身份资料处点『应用』，看到『身份资料已准备，连接服务端后登记』。仅填字段、只停主菜单或 --quit-after 启动不会证明身份已生成。”无需据本轮证据修改 launcher。

## 真实命令、环境与 PID
执行前完整范围/命令已写入 `docs/round75-dual-identity-formal-preflight.md`，然后才执行。

终端：
```bash
TMPDIR='E:/Caches/Hermes/cache/scratch' TEMP='E:/Caches/Hermes/cache/scratch' TMP='E:/Caches/Hermes/cache/scratch' PYTHONDONTWRITEBYTECODE=1 python -B newtests/test_round75_dual_identity_metadata.py
TMPDIR='E:/Caches/Hermes/cache/scratch' TEMP='E:/Caches/Hermes/cache/scratch' TMP='E:/Caches/Hermes/cache/scratch' PYTHONDONTWRITEBYTECODE=1 python -B newtests/round75_dual_identity_formal.py --approve-root E:/Caches/Hermes/cache/scratch/round75-dual-identity-formal-20261010-saidentity
```
元数据判据测试：3 项通过，exit 0；不是身份运行通过。runner：exit 1。

实际唯一客户端启动命令（cwd 为本轮 E 根）：
```bat
"C:\Windows\System32\cmd.exe" /d /s /c ""E:\Caches\Hermes\cache\scratch\round75-dual-identity-formal-20261010-saidentity\client\START-CLIENT.cmd" --headless --audio-driver Dummy --rendering-method gl_compatibility --max-fps 30 --script "E:\Caches\Hermes\cache\scratch\round75-dual-identity-formal-20261010-saidentity\identity_formal_driver.gd" --log-file "E:\Caches\Hermes\cache\scratch\round75-dual-identity-formal-20261010-saidentity\host.engine.log""
```

进程级环境（绝不设置永久系统变量）：
```bat
set "APPDATA=E:\Caches\Hermes\cache\scratch\round75-dual-identity-formal-20261010-saidentity\test-users\host\appdata"
set "LOCALAPPDATA=E:\Caches\Hermes\cache\scratch\round75-dual-identity-formal-20261010-saidentity\test-users\host\localappdata"
set "TEMP=E:\Caches\Hermes\cache\scratch\round75-dual-identity-formal-20261010-saidentity\test-users\host\temp"
set "TMP=E:\Caches\Hermes\cache\scratch\round75-dual-identity-formal-20261010-saidentity\test-users\host\temp"
set "TMPDIR=E:\Caches\Hermes\cache\scratch\round75-dual-identity-formal-20261010-saidentity\test-users\host\temp"
set "FD_PROOF_ROLE=host"
set "FD_PROOF_CONTROL=E:\Caches\Hermes\cache\scratch\round75-dual-identity-formal-20261010-saidentity\controls\host"
```
`FD_PROOF_*` 与 Python `--approve-root` 都是测试驱动参数，不是产品身份 CLI。

| 实际观察进程 | PID | 退出码 | 说明 |
|---|---:|---:|---|
| CMD launcher | 27348 | 125 | suspended 创建、加入自有 Job 后 resume |
| 自有 Job 进程，未保存角色映射 | 38304 | 125 | 持有进程句柄读取真实退出码；不猜角色 |
| 自有 Job 进程，未保存角色映射 | 33964 | 125 | 持有进程句柄读取真实退出码；不猜角色 |
| guest | N/A | N/A | 未启动 |

EXE PID 的直接驱动回执缺失，不把未知辅助进程猜成 EXE。运行时间最终 45.407s；45s 是本轮驱动就绪看门狗，不是用户产品性能门槛，更不能据此宣称产品超时故障。原计划的 180s 整体墙钟预算未到。

## 目录、文件和 SHA 对比
本轮根：`E:/Caches/Hermes/cache/scratch/round75-dual-identity-formal-20261010-saidentity`。以下路径相对该根。

| 角色 | 身份目录 | 存在 | 文件数 | 文件名 / SHA |
|---|---|---|---:|---|
| host | `test-users/host/appdata/FateDomination/net_identity` | False | 0 | N/A / N/A |
| guest | `test-users/guest/appdata/FateDomination/net_identity` | False | 0 | N/A / N/A |

两条路径字符串不同，但不是“两份已生成身份”的证据。同名 SHA 不同、先后/并发不覆盖、重开仍保留 SHA 都**未证实**；绝不将空集合算为通过。

## Job0、残留与日志关键行
- 自有 Job 最终 `total=3, active=0, terminated=0, pids=[]`，Job0=true。
- **forced_termination=true，normal_exit=false。** accounting 的 terminated=0 不代表没有强制停止；本轮明确调用了 TerminateJobObject(125)。
- 自有 Job 枚举始终排除 PID 17120/28100；从未对它们发出终止或输入。没有按进程名杀 Godot。
- 额外只读 CIM 精确扫描本轮目录的 ExecutablePath：exit 0，残留 `[]`。首次临时命令含错误转义，已排除；第二次通过 Python Path 构造原生路径并断言无 CR 后扫描，才作为此证据。

正确的只读查询：
```powershell
Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -like "E:\Caches\Hermes\cache\scratch\round75-dual-identity-formal-20261010-saidentity\*" } | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath | ConvertTo-Json -Depth 3
```

| 日志 | 行数 | SCRIPT ERROR | Parse Error | ERROR: |
|---|---:|---:|---:|---:|
| host.engine.log | 0 | 0 | 0 | 0 |
| host.stdout.log | 2 | 0 | 0 | 0 |
| host.stderr.log | 0 | 0 | 0 | 0 |

唯一公开关键行，host.stdout.log:L1：
```text
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org
```
无 `IDENTITY_PROOF ENV/MAIN_SCENE/LOBBY_SCENE/APPLY_OK/ready` 标记。空引擎日志和无脚本错误不构成入口成功证据。

## 包完整性及证据
原候选所有文件运行前后 SHA 相同；本轮副本 EXE/PCK/DLL/launcher 运行前后 SHA 相同。仅副本运行数据允许变化，源素材只读。

| 文件 | SHA-256 |
|---|---|
| FateDomination.exe | `8b30b9e04970272ed3d70a4c530838570922550208ae1e1817ccb30cc0458730` |
| FateDomination.pck | `bce3390ad25a54d71b5362f1f74d85e02be9b788d1c86493bc3ce1075478a7d6` |
| START-CLIENT.cmd | `379e5ae6f9ea58dc745291edef07de0289ca9316e9da5ce73b6b6f2b1ef798ea` |
| signals DLL | `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd` |
| WebRTC DLL | `3a8053d325a874493f596630b0f165f3a83e265c61d9fd87d82da6cb4c2a81fd` |

候选 PCK 已读取非加密 v4 索引并验证 1103 条资源 MD5/SHA，确认含正式大厅场景及编译 lobby_screen/player_identity 等资源；并未把当前未打包源码行为冒充本次 EXE 执行。

原始回执：`E:/Caches/Hermes/cache/scratch/round75-dual-identity-formal-20261010-saidentity/evidence.json`，SHA `e96134cc6f384abbaf596a0b8304d6a465d230b04d869e6f6435288084b44e91`。
精简回执：`docs/round75-dual-identity-formal-evidence.json`。

新增文件：
- `newtests/round75_identity_formal_driver.gd`（外置按钮信号驱动，实际 EXE 执行未证实）。
- `newtests/round75_dual_identity_formal.py`（E 隔离、副本 SHA、元数据快照、自有 Job、失败回执）。
- `newtests/test_round75_dual_identity_metadata.py`（防空集/同 SHA/文件名不匹配误判）。
- `docs/round75-dual-identity-formal-preflight.md`、本报告及精简 JSON。

未改生产源码、原候选包、前任报告或技能。只保留本轮 E 根现场，未清理任何他人目录；全程没有读取、打印或输出身份凭据明文。任务仍有明确阻断，不能写“身份隔离已证实”。
