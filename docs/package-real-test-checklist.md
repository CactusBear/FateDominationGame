# 导出前静态预检与真实包交付清单（v5）

## 范围与发布门槛

本轮**不导出、不启动 Godot、不运行服务端、不接触凭证、不提交 commit、不改生产代码**。仅交付检查工具、当前静态证据及用户后续实测步骤。以下启动命令是导出获得授权之后使用的说明，不是本轮执行记录。

- [ ] 所有生产写入者退出；主代理核对实际工作树、专项证据及未完成项。
- [ ] 冻结源码、公开配置模板、数据、扩展库与导出预设；给包一个独立 release_id，不把文档 v5 当项目版本。
- [ ] 运行预检，无 BLOCK；REVIEW 逐项解释/处理并附证据。工作树 dirty 本身不禁止打包，但必须与冻结逐文件哈希对应。
- [ ] 用户明确授权导出后才能执行导出；不得用旧包冒充当前源码成果。
- [ ] 实际 PCK、原生库、外置数据核验后再交给用户实测；静态检查不替代引擎解析或真实包验收。

## 可重复静态预检

在项目根执行（只调用 Python 标准库与只读 git 命令）：

```bash
python scratch/package-preflight-v5/preflight.py
```

产物均在 `scratch/package-preflight-v5/`：

| 文件 | 用途 |
|---|---|
| `preflight.py` | 只读生产树；扫描引用、导出配置、原生库架构、策略模板；不调用引擎 |
| `static-report.json` | PASS/BLOCK/REVIEW、版本、git HEAD、dirty 标志、聚合哈希与边界 |
| `source-manifest.json` | 受检生产树逐文件路径、大小、SHA-256；含 data 与公开配置模板 |
| `resource-references.json` | 字面量资源引用的文件、行号和目标 |
| `package-manifest.template.json` | 待真实导出后填写的交付清单，不是已有包的证明 |

退出码：0=静态无阻断/复核项；1=有 REVIEW；2=有 BLOCK。禁止把 shell 中后续命令的 0 当作预检退出码。哈希读取范围为 `scripts/assets/addons/data/json_maker`、`project.godot/export_presets.cfg/icon.svg`，排除 `.gdignore` 子树；不包含测试/审计文档、scratch 或运行用户目录，不是 Git 提交哈希，也不是 PCK 哈希。并发写入时报告仅是瞬时扫描，冻结后必须复跑。CFG 提取不是 Godot Variant 解析，引用扫描含注释/示例，不覆盖动态拼接和 `uid://`。

### 本次快照结论

以 JSON 的生成时间和哈希为准：项目声明版本 `0.0.1`，工作树有未提交改动。

- 新 `scripts/net/{authority,content,identity,p2p,server,session,transport,ui,validation}` 均存在；受检生产树没有旧平铺 `res://scripts/net/<name>.gd` 引用。
- 两个 dedicated server 预设均声明 `fate_server`、配置模板 include、外置 data exclude、Git 编辑器扩展 exclude；Windows release wrapper 为 2；服务端 feature 主场景与即时 stdout 配置存在。
- 信号保护扩展 Windows DLL 与 Linux SO 均存在，头部是 x86_64 PE/ELF；WebRTC x86_64 release 双平台库静态定位/头部检查通过。**不证明 ABI、依赖库、实际装载、信号处理或网络功能通过。**
- **阻断：两个服务端预设未排除 scratch 资源**，且 scratch 没有根 `.gdignore`；扫描发现真实 `.tscn`（包含独立信令项目），`all_resources` 存在误带测试场景/额外扩展的风险。应由主代理另行获准后给导出过滤添加 `scratch/*`，同时审查根目录测试结果、临时工具与备份；本轮不代改。
- REVIEW：Godot AI 编辑器插件示例/错误提示字符串存在不可定位资源路径，清单有精确位置；人工区分示例与实际加载，不直接当运行故障。不得为了清零删除正常插件。
- 外置复制插件会覆盖同名文件，但不清理目标中源已删除的文件；**必须导出到新的空版本目录**，不得复用旧 data 目录。

## 导出前逐项检查

### 1. 目录迁移和启动入口

- [ ] `.gd/.tscn/.tres/project.godot` 中旧路径归零；测试、工具和历史文档单独区分，真正会运行的测试必须更新。
- [ ] UID 与实际场景/脚本引用在允许运行引擎后解析；静态路径存在不代表 class_name 注册无冲突。
- [ ] `run/main_scene.fate_server` 指向 bootstrap，普通客户端仍保留正式主菜单入口。
- [ ] bootstrap 覆盖网关、房间 worker、数据校验 worker、控制台；职责冲突拒绝。
- [ ] release 子进程参数移除 `--` 前的 `--path/--scene` 及值，保留日志参数与 `--` 后业务参数；新建、恢复、隔离预检分别验证。
- [ ] 游戏包含规则 autoload，因此不得用 `roles=["relay"]` 冒充纯信令隔离。纯信令如交付，必须独立无 autoload 项目、独立预设/哈希/清单，禁止直接打包 scratch 原型。

### 2. 原生扩展与导出模板

- [ ] `addons/fate_server_signals/fate_server_signals.gdextension` 与平台库一起冻结；记录 Windows/Linux x86_64 库 SHA-256。
- [ ] WebRTC release 库保留；Git 编辑器专用扩展从服务端包排除。审查 scratch 中重复扩展和插件更新备份。
- [ ] Godot 版本、release 模板版本、平台、CPU 架构明确一致；静态库头部不能验证 Godot ABI、Linux glibc 或系统依赖。
- [ ] 后续包中实际包含/携带对应运行库；Linux 主机再用 `ldd` 确认无 `not found`，Windows 真启动检查加载错误。
- [ ] 所有原生库哈希与冻结清单一致；不要只检查 `.gdextension` 文本存在。

### 3. 外置 data 与 E 盘测试路径

- [ ] 每个目标预设 `data/*` 排除；实际 PCK 目录确认没有规则 `data/`；严禁回退包内旧数据。
- [ ] 插件启用且导出日志确实出现外置复制完成；逐文件比对 source-manifest 中 `data/` 条目，`.import` 元数据单列，不冒充规则文件。
- [ ] 专属空测试根建议 `E:/Projects/Godot/FateDomination/test/package-real-v5/<release_id>/`；Windows 包、候选数据、房间存储、临时控制目录、日志分别子目录；本轮未创建测试数据或迁移存档。
- [ ] 默认 `data_root="data"` 由 LoadHelper 解析到 exe 同级，不依赖 cwd；不复制用户现有凭据库/缓存/旧恢复文件到发布包。
- [ ] 需要强制 Windows 测试写 E 盘时，在**测试配置副本**设置 data_root、storage_root、console_dir、status_file 的绝对 E 盘路径；identity_registry 仅指定新的本机测试文件路径，内容不读取/不上传。
- [ ] Linux 独立配置使用本机原生文件系统路径（如 `$HOME/fate-real-test/<release_id>/`），不用 Windows `E:/` 字符串；WSL 主程序/房间目录不要放 UNC 或跨文件系统写热点。
- [ ] 从与包不同的 cwd 启动，检查实际扫到每类规则数量；缺 data、坏 JSON、卡图缺失均须明确失败，不自动采用旧缓存。

### 4. server.cfg 与策略

- [ ] PCK 内 `assets/config/server.cfg` 的 SHA-256 与冻结源码模板一致。
- [ ] 首次不存在配置：只复制带注释模板，退出并提示 `SERVER_CONFIG_CREATED`，**没有开始监听**；再审查配置并第二次启动。
- [ ] 既有配置不覆盖；损坏配置/未知字段/职责冲突失败。不得把自动生成模板称为服务端 ready。
- [ ] `authority_host_mode="dedicated"`、`transaction_log=true`、`recovery_key_mismatch="reject"`、`recovery_inheritance="host_select"` 已接线，不只写在模板。
- [ ] `roles=["game"]` 默认；game+relay 仅附加信令，不转发 P2P 对局，不在信令节点执行规则。
- [ ] random_sim_enabled 与 random_sim_budget_sec 分开：关开关和开关开启但预算 0 分别测；候选数据不会自动批准。
- [ ] console_dir 仅可信本机可写；identity_registry 保持认证默认开启，不为测试方便默默置空。
- [ ] 配置重载、权限、管理命令、关服预算分别验收；敏感字段不进截图或公开标签。

## 用户实测时需要收到的包

每个平台一个独立、完整的新版本目录（下列为预期清单，不代表已生成）：

| 包 | 必需文件/附属证据 |
|---|---|
| Windows 游戏服务端 | `FateServer.exe`、`FateServer.console.exe`、`FateServer.pck`（当前 embed_pck=false）、导出实际附带的信号/WebRTC DLL、外置 `data/`、首次配置说明 |
| Linux 游戏服务端 | `FateServer.x86_64`、`FateServer.pck`、对应信号/WebRTC SO、外置 `data/`、可执行权限/依赖说明 |
| Windows 客户端（联机实测所需） | 正式 exe、对应 PCK、运行扩展与完整外置 data；至少两名真人/两个独立身份环境；不以源码客户端冒充已验证客户端包 |
| 纯信令（只有明确要求时） | 独立无 autoload 包、专用精简 CFG；不可复用游戏包声称完成隔离 |
| 每包共同附属 | `package-manifest.json`、`source-manifest.json`、`data-manifest.json`、逐包 `SHA256SUMS`、本清单、已执行与未执行验收表 |

`package-manifest.json` 从本任务模板填写：release_id、项目版本、git HEAD+dirty、冻结源码树 SHA-256、模板 SHA-256、引擎/模板版本、预设/平台架构、实际导出时间，以及每个分发文件的相对路径/大小/SHA-256。哈希空字段必须在交付前填实，不编造导出结果。已存在包也必须核对当前冻结模板与源码，不能只凭 exe 日期认版本。

## 后续启动命令（本轮未执行）

先为每次启动创建新的日志目录；配置路径是**外置实例配置**，不是包内模板。以下示例要求用实际 release_id 替换目录名并预先创建 `logs/`；不要携带编辑器 `--path`、`--scene`。

Windows PowerShell（在任意不同 cwd 使用绝对路径；需 stdin 时必须 console wrapper）：

```powershell
& 'E:/Projects/Godot/FateDomination/test/package-real-v5/RELEASE/windows/FateServer.console.exe' --headless --audio-driver Dummy --log-file 'E:/Projects/Godot/FateDomination/test/package-real-v5/RELEASE/logs/gateway.engine.log' -- --server-gateway --config 'E:/Projects/Godot/FateDomination/test/package-real-v5/RELEASE/windows/server.cfg'
```

记录输出与退出码可用 `Tee-Object`，但 stdin 专项应直接运行 console wrapper，单独测试管道输入与输入端退出后服务端存活；不要把输出转存管线误当交互输入已验收。使用外部控制端时是另一进程：`FateServer.console.exe --headless -- --server-console <可信本机console_dir>`；控制目录为空默认关闭。

Linux bash（首次同命令仅生成配置；正常运行不可把 ready 旧日志重用）：

```bash
pkg="$HOME/fate-real-test/RELEASE/linux"
mkdir -p "$pkg/logs"
chmod u+x "$pkg/FateServer.x86_64"
cd "$HOME"
"$pkg/FateServer.x86_64" --headless --audio-driver Dummy --log-file "$pkg/logs/gateway.engine.log" -- --server-gateway --config "$pkg/server.cfg" >"$pkg/logs/gateway.stdout.log" 2>"$pkg/logs/gateway.stderr.log"
rc=$?
printf '%s\n' "$rc" >"$pkg/logs/gateway.exit-code.txt"
```

长时间运行时不要为了取退出码强杀；按正式安全关服流程结束后记录。Linux 控制台测试另开独立进程，主网关与输入端 PID 分开。Windows wrapper PID、真实主进程 PID、Linux PID 和 WSL 宿主 PID 不可混用。

## 实测矩阵与日志采集

每行独立记录：release_id、平台/系统、配置摘要（脱敏）、时间、期望、实际、RESULT/退出码、日志路径、结论。未执行写「未测」，不能填 PASS。

| 项目 | 通过标准/需要证据 |
|---|---|
| 首次配置/坏配置/已有配置 | 首次仅生成并退出无监听；已存在不覆盖；坏配置明确失败 |
| 无关 cwd / 外置数据 | 日志给出真实数据路径与类别数量，编辑器和游戏数据入口均验证；缺 data 不回退 |
| 主进程 ready | 本次 `SERVER_GATEWAY_READY` 或原子状态报告；核对 pid、roles、端口；不能只检查 file_exists |
| Windows stdin / Linux 控制台 | wrapper 实际输入可用；网络在等待输入时响应；输入端退出网关仍存活；无遗留子进程 |
| 两客户端建房/加入/直连 | Windows 与 Linux 网关分别测；用户名/昵称/身份正确；P2P 信令仅协调，规则在房主或独立 worker |
| 数据批准与传输 | prepare→校验 worker→ready→按 request_id commit→applied→批准清单；接收真实字节与 SHA-256，未批准不发布 |
| 完整对局/隐私/待答 | 真实选人、开局顺位、技能+攻击提交、扣费/入场、目标答复、旁观与隐藏信息；客机未执行规则；终局截图另行审阅 |
| 网络异常/预算 | 真人掉线不 AI 托管；开关和零预算语义；疑似异常暂停；跳过必须完整根事务回滚，无可验证检查点不伪造成功 |
| 崩溃恢复 | 先保存→崩溃→重启→旧目录逐文件校验→全部原真人认证重连→恢复完整对局；playing→restoring→playing；不能仅验子进程重启 |
| 恢复反例 | 错密钥先拒绝、旧票据/修订号拒绝、房主选择已认证成员继承、昵称重复不自动认领；旧缺绑定记录失败关闭且保留原文件 |
| 安全关服/原生信号 | 保存完成后网关/worker 清理；失败/超时网关保持运行；SIGTERM 后进程消失不等于保存成功 |

### 每次实测收集

1. 一个新的 run_id 目录；保存 package-manifest、SHA256SUMS 与冻结报告，避免旧 ready/engine 日志污染。
2. 主进程 stdout/stderr/engine.log、本次状态报告和 PID/命令行（只保留无秘密启动参数）；房间每个 instance_id 的 `engine.<instance_id>.log`、`ready.json`（成功最终文件与失败临时文件分开）。
3. 每套验收独立 RESULT、退出码、SCRIPT ERROR、原生扩展错误；截图写明平台/阶段/run_id。只保存截图不证明查看通过。
4. 存储根、room_id、instance_id、authority_host_mode 与批准数据清单/字节哈希、恢复前后状态/审计事实；不要公开原始恢复票据或身份库内容。
5. 失败保留目录和日志，不删除或覆盖旧存档来制造通过；包、客户端版本、OS、网络地址/端口、复现步骤和精确报错随问题交付。公网地址可脱敏。
6. **不采集密码、私钥、认证票据原文、公钥/指纹公开标签或完整 identity_registry**；恢复配置/存档/审计可能有敏感字段，原件仅留本机，发给协作者前人工脱敏。
7. 关服后核对主/子进程都已退出；若仍运行，仅处理本次经命令行与报告确认的 PID，不做全局 kill。记录未覆盖范围：WSL 本机跨系统不代表公网或异地 NAT。

## 当前交付状态

本轮只完成静态预检工具及清单。**未导出、未启动引擎、未实测 Windows wrapper/Linux 包/完整联机/崩溃恢复。** 当前阻断保持可见，必须由主代理在生产写入全部结束后按本清单复跑、处理并等待导出授权。
