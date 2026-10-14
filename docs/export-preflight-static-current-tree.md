# 当前工作树导出前置静态核对

## 结论与证据边界

- 核对时点：2026-10-10 22:53:29 +08:00；来源 `E:/Projects/Godot/FateDominationGame-master`，分支 `master`，工作树有大量修改/未跟踪文件，**不是已冻结版本**。
- 结论：**BLOCK／STATIC_ONLY**。本机所需 x86_64 Windows/Linux 模板存在且静态版本匹配 `4.7.2.stable`；当前源码具有客户端/游戏服务端入口分离，但工程缺少显式发行契约，隐私排除与生产开发插件隔离也未齐备。
- 本任务没有启动 Godot、导出、复制冻结工程、组包或加载原生库，没有触碰 PID 17120/28100。现有冻结工具只执行了无复制 dry-run；这不代表导入、导出、PCK 审计或发行启动通过。
- 每项证据为本次实际文件读取/静态工具输出；没有读私钥、身份资料、存档或日志内容。不存在本次新 EXE/PCK/ZIP，相关验收一律 `unknown/NOTRUN`。
- 唯一新增文件为本报告；没有修改生产脚本、预设、配置或已有发行工具。

## 1. 预设路径、SHA256 与逐项核对

预设绝对路径：`E:/Projects/Godot/FateDominationGame-master/export_presets.cfg`

SHA256：`f8f6afbbeb520f780deab5d7f7d5a59e9f5b2f33e02db4cb64c6823a428da091`

本次 `git diff -- export_presets.cfg` 无输出。下列行号均指本次读取的文件；后续源码变化必须重算。

| 节/名称（字段原文） | 平台/角色特征原文 | 过滤字段原文 | 输出/架构/控制台原文 | 发布或调试 |
|---|---|---|---|---|
| `[preset.0]`，`name="FateDomination_demo_v1"`（6–15） | `platform="Windows Desktop"`；`dedicated_server=false`；`custom_features=""` | `export_filter="exclude"`；`export_files=PackedStringArray()`；`include_filter=""` | `export_path="../FateDomination.exe"`；`binary_format/architecture="x86_64"`；`debug/export_console_wrapper=0`（16、34、39） | preset 本身不指定 release/debug；最终命令明确 `--export-release`。debug 要另用 `--export-debug`，未执行 |
| `[preset.1]`，`name="Linux"`（78–86） | `platform="Linux"`；`dedicated_server=false`；`custom_features=""` | `export_filter="all_resources"`；`include_filter=""` | `export_path=""`；`binary_format/architecture="x86_64"`；`debug/export_console_wrapper=1`（87、105、110） | 同上；空路径要求显式输出路径 |
| `[preset.2]`，`name="FateServer Linux"`（124–132） | `platform="Linux"`；`dedicated_server=true`；`custom_features="fate_server"` | `export_filter="all_resources"`；`include_filter="assets/config/*.cfg"` | `export_path="../FateDomination/test/server-dist/linux/FateServer.x86_64"`；`binary_format/architecture="x86_64"`；`debug/export_console_wrapper=2`（133、139、141） | 同上；`dedicated_server=true` 不等于 release 或纯信令 |
| `[preset.3]`，`name="FateServer Windows"`（145–153） | `platform="Windows Desktop"`；`dedicated_server=true`；`custom_features="fate_server"` | `export_filter="all_resources"`；`include_filter="assets/config/*.cfg"` | `export_path="../FateDomination/test/server-dist/windows/FateServer.exe"`；`binary_format/architecture="x86_64"`；`debug/export_console_wrapper=2`（154、160、161） | 同上 |

`[runnable_presets]` 原文：`"Windows Desktop"="FateDomination_demo_v1"`、`Linux="Linux"`（1–4）。最终命令不依赖 runnable 选择或 preset 默认 export_path。

四个预设共同的 `exclude_filter` 原文（15、86、132、153）：

```ini
exclude_filter="tools/windows_server_console/*,addons/fate_server_signals/bin/libfate_server_signals.windows.x86_64.dll,data/*,tests/*,reports/*,docs/*,scratch/*,addons/godot-git-plugin/*,*.o,*.os,*.obj,*.a,*.lib,*.exp,*.pdb,*.ilk,*.sconsign.dblite,*.TMP,addons/fate_server_signals/src/*,addons/fate_server_signals/SConstruct,addons/fate_server_signals/build_profile.json,addons/fate_server_signals/bin/libfate_server_signals.windows.x86_64,addons/fate_server_signals/bin/libfate_server_signals.linux.x86_64"
```

其他字段：四个预设均 `script_export_mode=2`、`binary_format/embed_pck=false`（28/35、99/106、134/140、155/159）。客户端显式 `encrypt_pck=false`、`encrypt_directory=false`（26–27、97–98）；两个服务端节没有显式 encryption 字段，值为 **unknown（不能用客户端字段代填）**。客户端的 `custom_template/debug=""`、`custom_template/release=""`（32–33、103–104）；服务端未声明 custom_template 字段，不据缺字段声称模板选择已实测。

### 隐私/排除核对表

| 项目 | 证据 | 结论 |
|---|---|---|
| data 不打入 PCK | 四个 `exclude_filter` 均有 `data/*` | 配置意图已确认；实际 PCK 排除效果 `unknown/NOTRUN` |
| 文档/测试/报告/scratch | 明确有 `docs/*,tests/*,reports/*,scratch/*` | 有规则；不能代替实际索引检查 |
| savedkeys/身份私钥/身份目录/存档/日志 | 原文没有 `savedkeys`、`net_identity`、`private.pem`、`match_saves`、`server_rooms`、`authority_rooms`、`*.log` 或 `runtime/*` 的显式排除 | **隐私排除未齐备**；不等于已证实泄漏，但不能保证不外泄 |
| 真实客户端身份落点 | `scripts/net/ui/lobby_screen.gd:24–25`：`identity_key_path:String = "user://net_identity/private.pem"`；`identity_profile_path:String = "user://net_identity/profile.json"` | 是用户资料，不是发行资源；不得复制用户根 |
| 真实存档/服务端登记落点 | `scripts/net/session/lobby_session.gd:141`：`archive_root:String = "user://match_saves"`；`assets/config/server.cfg:13,16`：`storage_root = "user://server_rooms"`、`identity_registry = "user://server_players.json"` | 禁入发行包；配置中的路径字符串不是秘密文件本身 |
| 用户目录 | `project.godot:21–22`：`config/use_custom_user_dir=true`、`config/custom_user_dir_name="FateDomination"` | `user://` 实际映射需运行确认；本次没有读取其内容，也没有证明用户资料不会被通用递归组包带入 |
| 开发插件/未覆盖目录 | 过滤原文只排除 `tools/windows_server_console/*`，没有整个 `tools/*,test/*,newtests/*,newtools/*,newdocs/*,backups/*,game_data/*,buildmanifest/*,addons/godot_ai/*` | 工作树中上述目录真实存在；其中哪些会实际入 PCK 为 `unknown`，必须拒绝开发闭包混入而非猜测导出器忽略 |
| 生产 autoload | `project.godot:41`：`_mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"`；60：启用 Godot AI 插件 | 当前开发 project 不能直接作为干净发行 project。`package_audit.py:97–102` 会拒绝开发 helper/插件；仅在未来隔离冻结副本移除，不能改本任务源文件 |
| 编译副产物 | 原文排除 `*.o,*.os,*.obj,*.a,*.lib,*.exp,*.pdb,*.ilk,*.sconsign.dblite,*.TMP` 及两个无最终库后缀文件 | 已有静态规则；小写 `.tmp`、其他产物与实际包情况仍需索引检查，不据此保证全部排除 |
| 原生运行库 | 被排除的是 `libfate_server_signals.windows.x86_64.dll`，正式 descriptor 指向 `libfate_server_signals.windows.template_release.x86_64.dll` | 不是同一文件；不能为瘦身继续排除正式 authority worker 运行库。实际导出拷贝/加载 `unknown` |
| 无凭据 data | 本次只扫文件名/类型：71 `.json`、134 `.png`、134 `.import`，无匹配的私钥/存档/身份敏感文件名 | 命名扫描不是内容级无秘密证明；无凭据审批为 `unknown`，不得自动填 `--credential-free-project` |

不要笼统排除 `scripts/net/identity/*`：这是合法认证源码，不是 `user://net_identity` 私有资料。外置 data 复制器只跳过 `.import`（`tools/copy_data_after_export.py:25–26,117–132`），**没有秘密黑名单且不清理旧目标**；必须用新空目录并先审批来源文件集合。

## 2. 本机引擎与模板（只读静态版本核验）

引擎文件：`D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe`。

- Windows PE `FileVersionInfo` 原文：`FileVersion="4.7.2"`、`ProductVersion="4.7.2.stable.official"`、`ProductName="Godot Engine"`。
- SHA256：`ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`。
- 控制台入口文件也存在：同目录 `Godot_v4.7.2-stable_win64_console.exe`，198152 bytes；本次未运行 `--version`。
- `project.godot:23` 只声明 `config/features=PackedStringArray("4.7", "Mobile")`，不能单独证明 patch 版本。

模板根：`C:/Users/Administrator/AppData/Roaming/Godot/export_templates/4.7.2.stable/`，实际存在；`C:/Users/Administrator/AppData/Local/Godot/export_templates` 不存在。下列均为实际文件，不只是目录名。

| 模板文件（相对于模板根） | bytes | SHA256 | 静态版本证据 |
|---|---:|---|---|
| `windows_release_x86_64.exe` | 109268480 | `d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562` | PE FileVersion `4.7.2`；ASCII NUL 终止版本串 `4.7.2.stable.official` |
| `windows_debug_x86_64.exe` | 103176704 | `51498b72b3a237f882ebd7d1787f06a4bc1eaf0572daab93837adcfd3cfdc107` | 同上 |
| `windows_release_x86_64_console.exe` | 188928 | `52bdcae9068e8d23b840e5c63b0c1798ffe2cb66144e5c4bc7af11fb8c8600df` | 标准名称/同目录；wrapper 自身 stable 标记 `unknown` |
| `windows_debug_x86_64_console.exe` | 188928 | `5514c7645ee897a01f540d3cf22ede5badf92394521a08bfab66a54d7369e6e6` | 同上 |
| `linux_release.x86_64` | 73519416 | `d9f79ab89b5ae369aeed11c6052d402e8218cd503bf85b4a235f9c30c46a7c63` | 实际二进制版本串 `4.7.2.stable.official` |
| `linux_debug.x86_64` | 73703800 | `1a291d3d15e4180b60b0af96cf6458f11fe143636d76575ddf1e23d1a3f24f2e` | 同上 |

**匹配结论**：四个 x86_64 主模板与引擎静态版本匹配。模板安装来源/官方发布摘要比对、实际导出器查找/使用、目标机可运行性均 `unknown`；没有把二进制版本串当运行成功。

工具实际环境初始 `APPDATA/LOCALAPPDATA/TMPDIR/TEMP/TMP` 指向 C 盘，`GODOT_USER_HOME` 未设置。只读核查不建临时文件；后续命令必须显式将运行/临时目录转 E。不能照抄旧文档把 APPDATA=C 用于 editor/import；下面方案只从 C 读取模板并复制必要模板到未来 E 隔离用户根。

## 3. 客户端/独立游戏服务端角色与 data 契约

| 核对项 | 证据路径/字段原文 | 状态 |
|---|---|---|
| 客户端入口 | `project.godot:20`：`run/main_scene="res://assets/scenes/main_menu/opening_background.tscn"`；客户端预设 `dedicated_server=false, custom_features=""` | 明确默认游戏入口；发行 role 仍须单独声明，不能靠 false 推断完整发行职责 |
| 独立游戏服务端入口 | `project.godot:25`：`run/main_scene.fate_server="res://assets/scenes/main_menu/server_bootstrap.tscn"`；两服务端 preset `custom_features="fate_server"` | feature/主场景接线明确 |
| 游戏服务角色 | `assets/config/server.cfg:27–37`：`authority_host_mode = "dedicated"`、`transaction_log = true`、`roles = ["game"]` | 已声明是游戏权威，不是纯信令 |
| 运行参数路由 | `scripts/net/server/server_bootstrap.gd:10–16` 的 `PROCESS_ROUTES`；`--server-gateway` 路由 `server_cli.tscn`；110–130 检查唯一职责，未声明时选择 gateway | 运行角色与发行角色是不同契约，不能把 CLI 路由当 release_contract |
| 纯信令隔离 | `server_bootstrap.gd:140–142` 拒绝有 autoload 的纯信令；`server_cli.gd:52–54` 拒绝游戏项目承担纯 relay；`project.godot:28–41` 有游戏 autoload | 当前树不能按目录或 `dedicated_server=true` 称为 signaling-only；本报告不组信令包 |
| 客户端外置 data | `scripts/system/global/load_helper.gd:11–13,20–30,41–44`：`DATA_DIR_NAME := "data"`；导出根为 `OS.get_executable_path().get_base_dir()`；可用显式 `session_data_dir` | 客户端必须 EXE 同级外置 data，不能省略 |
| 游戏服务端外置 data | `assets/config/server.cfg:12`：`data_root = "data"`；`server_cli.gd:56–57,90–93` 强制字符串 data_root/storage_root 并验证本机批准数据根 | 服务端也必须 data；配置根与客户端默认根可分别部署，不按目录存在猜角色 |
| 发行层显式声明 | 根目录 `release_contract.json` 实测不存在；`tools/release/release_contract.py:22–25,55–70` 要求精确 preset/platform/role，client/server 强制 data | **BLOCK：当前工作树发行声明不齐备** |
| 可用声明构造入口 | `freeze_prepare.py:190–200,223–228,235–239` 可由明确 `--preset/--role/--executable/--runtime-files` 在未来冻结副本生成声明 | 仅候选方案，不是本次已存在的源声明；需 owner 批准具体联合键及依赖映射 |
| Linux 自动发行门 | `release_contract.py:36–37` 仅支持 `platform="windows"`；`release_prepare.py:19–20`、`package_audit.py:55` 拒绝 Linux | **BLOCK：Linux 不能用 Windows 审计结果冒充组包门通过** |

### 本次 data 与运行依赖静态摘要

外置运行 data（仅按 copier 跳过 `.import`）：**205 文件**；完整原目录339文件。哈希集合规范化为 `json.dumps(relative_path_to_sha256, sort_keys=True, separators=(",",":"), ensure_ascii=False).encode("utf-8")`，SHA256：

`378aff179067103eaa26e721391dfe29f541f287f5bb425ac9354b62c88a5893`

该摘要是本时点辅助指纹，不是清单审批或规则校验结论；未来冻结必须保存逐文件 manifest，复核来源集合及 SHA，而不是只比数量。

| descriptor 字段原文/解析规则 | 实际来源文件 | 存在/SHA256 |
|---|---|---|
| `addons/fate_server_signals/fate_server_signals.gdextension:7`：`windows.x86_64 = "res://addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll"` | 该绝对 res 路径对应文件 | 有；`92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd` |
| 同 descriptor:8：`linux.x86_64 = "res://addons/fate_server_signals/bin/libfate_server_signals.linux.x86_64.so"` | 该文件 | 有；`c7a42aeba7c11fb897a4b68694c6f1499f3e0db5b4bb7d6d5fa284176ca1aaff` |
| `addons/webrtc_native/webrtc_native.gdextension:28`：`windows.release.x86_64 = "lib/libwebrtc_native.windows.template_release.x86_64.dll"` | **相对 descriptor 目录**的 `addons/webrtc_native/lib/libwebrtc_native.windows.template_release.x86_64.dll` | 有；`3a8053d325a874493f596630b0f165f3a83e265c61d9fd87d82da6cb4c2a81fd` |
| 同 descriptor:15：`windows.debug.x86_64 = "lib/libwebrtc_native.windows.template_debug.x86_64.dll"` | 同目录的 debug 库 | 有；`0faff9c71966de25c09b6959d2b436c62452c661498de8f0bf85f5ece0cb32cd` |
| 同 descriptor:23：`linux.release.x86_64 = "lib/libwebrtc_native.linux.template_release.x86_64.so"` | 同目录的 Linux release 库 | 有；`88c927c551592f526fdb13fab28536629fae026f8d738d7d83ce2cf2493db9e3` |

DLL/SO存在和摘要不证明 ABI、原生加载、依赖解析、源码对应重编译或 worker 能力。上述均 `unknown`。客户端也需要 authority worker 库，不能只给服务端保留它。

## 4. 真实执行的静态检查结果

| 检查 | 实际结果 | 不证明什么 |
|---|---|---|
| `python -B tools/release/freeze_prepare.py`，明确 client preset/role/executable/两个 DLL映射/`--allowed-root E:/Projects/Godot/.scratch`，**没有 `--prepare`** | exit 0，`{"mode":"DRY_RUN_NO_COPY","files":1898,"godot_invoked":false}` | 未复制、未生成声明/manifest、未导入/导出/组包 |
| 同工具，明确 `FateServer Windows`/server/`FateServer.exe`，同一映射，同样无 `--prepare` | exit 0，同样1898文件、`godot_invoked=false` | 同上；不构成同一不可变快照绑定 |
| 对当前树实际调用 `release_contract.select(root,"FateDomination_demo_v1","windows","client")` | exit 2，`BLOCK: 缺少项目发行声明: release_contract.json` | 是明确前置拒绝，不是导出失败 |
| 读取 dry-run目标/manifest 路径 | client/server 四个目标均不存在 | 确认无复制 dry-run未悄悄创建产物 |
| 文件名检查 `Start.cmd` | 本工作树（不进 .git/.godot/.claude/.agent、不跟随链接）未找到 | 当前版本启动脚本来源 `unknown`；不能从旧包取用冒充当前匹配版本 |

只读 dry-run用的候选映射为下节 `RUNTIME` 原文。两个 dry-run均使用 `TMPDIR/TEMP/TMP=E:/Projects/Godot/.scratch/export-preflight`，`python -B` 禁止生成 pycache。源树与 `E:/Projects/Godot/.scratch` 当前没有 symlink/junction标记。工具代码证据：`freeze_prepare.py:209–211` 在复制之前返回 dry-run结果。

报告内命令另做纯语法复核：5个bash代码块全部 `bash -n` exit0；嵌入Python通过 `ast.parse`；只抽取无写入的命名函数做10个字符串路径正/负向检查，10/10符合预期（含合法认证源码、PCK导入/编译路径与savedkeys/身份/日志/穿越拒绝）。这些是合成路径单元检查，不是实际包内容证据。最初从Python调用裸`bash`命中了Windows不同入口而失败，改用实查的Git Bash绝对路径后完成核验；没有执行任何报告内构建或组包命令。

## 5. 组包白名单、黑名单与 SHA 门

这些是**拟批准执行边界**，不是声称现有 preset已经满足。

### 白名单

- 来源：同一审核后不可变快照的客户端/游戏服务端冻结工程；记录原 source SHA、冻结前后逐文件SHA、转换后 project/preset SHA、freeze_manifest SHA。
- Client：`FateDomination.exe`、独立 `FateDomination.pck`、上表两条 Windows release DLL的精确 basename 映射、与冻结 manifest一致的 `data/**`（跳过 `.import`）。
- Server：`FateServer.exe`、独立 `FateServer.pck`、同两 DLL、同一冻结 data集合；`FateServer.console.exe` 仅在真实 exporter生成且经记录哈希时允许；审批后的 `server.cfg`，不得带已有身份登记或存档。
- 顶层说明：审批后的 `README-真人测试.md`；`SHA256SUMS.json`（逐文件清单，不列自身）；ZIP之外再给 manifest SHA与ZIP SHA。
- `Start.cmd` 当前无来源，**不在自动白名单**；确需真人一键启动包时，补当前版本脚本及其审查/哈希证据后才能扩白名单。
- 不用 `cp -r` 打包整个 build 根，build根含 step日志/audit/manifest；只从精确 `windows/client`、`windows/server`载荷目录选取经白名单核验的文件。

### 黑名单/拒绝规则

- 包外及PCK内均拒绝 `savedkeys`、`net_identity`、运行身份目录/身份登记/恢复票据、`private.pem`、`*.pem/*.key`、`match_saves/server_rooms/authority_rooms`、存档、`logs/*.log`、runtime用户根、诊断输出、临时目录、旧发行包。
- 包外拒绝整个 `.git/.godot` 开发缓存；PCK中只可保留已审查的 `.godot/imported/**`、`.godot/exported/**` 与运行类缓存，继续沿真实 `.import/.gd.remap` 目标核对，未知缓存路径拒绝。两层均拒绝test/tests/newtests、tools/newtools、reports/runtime_reports、docs/newdocs、scratch、backups、buildmanifest、开发插件/MCP helper、源代码构建产物及替换库TMP。
- 不把外置 `data/**`排除规则当外置数据安全检查；审查精确来源/冻结data清单。文件名未命中也不能证明JSON内容无身份/秘密。
- 已有 `package_audit.py:99–125` 检查PCK中的开发目录/descriptor/声明映射；**没有完整 savedkeys/net_identity/私钥/日志黑名单，也未强制整个包外白名单**。因此单靠其 `STATIC_PASS_RUNTIME_PENDING` 不足以关闭隐私门，必须追加下节命名与精确集合核验。
- 链接/junction/硬链接、路径穿越、重复项、大小写冲突拒绝；仅对精确声明的运行库建立唯一映射，不用任意basename搜索补依赖。

### SHA核验顺序

1. 冻结前后来源集合/SHA完全一致，client/server的 `source_files`完全一致；保存原preset SHA与冻结转换后preset SHA，不能混淆。
2. 外置data按copier实际文件集合与freeze_manifest逐文件比对，无 missing/extra/changed；实际原生DLL SHA与声明来源一致。
3. 从真实独立PCK读取索引：现有 `package_audit.pck_index` 支持v3/v4，验边界/flags/重复项/每条MD5/SHA256，并保存PCK总SHA；引擎头应为 `[4,7,2]`。不支持/加密/嵌入必须拒绝，不当成空资源通过。
4. 整个组包暂存文件集合严格等于白名单+批准data清单；每文件SHA256，目录清单本身也给SHA256。
5. ZIP逐项验证CRC、无重复/大小写冲突/非法路径，ZIP载荷集合严格等于manifest集合+manifest自身，逐项SHA与manifest相同；最后给ZIP SHA256。
6. 以上仍只是静态完整性；真正导入/导出日志、正式EXE启动/worker/身份恢复/GUI/跨机跨网另外验收。本任务全部 `NOTRUN`。

## 6. 最终命令清单（未执行；先解除阻断/取得批准）

以下是Git Bash语法。**不得整体直接执行**：本任务禁止Godot/导出/组包；ROLE和无凭据确认尚待owner批准。`<new-exclusive-id>`必须替换为新独占ID，不复用旧目录；不得把旧EXE/PCK补进新包。此清单只给Windows已有工具的完整路径；Linux见末段限制。

### A. 环境/模板/角色明确声明

```bash
set -euo pipefail
SOURCE='E:/Projects/Godot/FateDominationGame-master'
ALLOWED='E:/Projects/Godot/.scratch'
RUN="$ALLOWED/export-<new-exclusive-id>"
GODOT='D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
TEMPLATES='C:/Users/Administrator/AppData/Roaming/Godot/export_templates/4.7.2.stable'
mkdir -p "$ALLOWED"
mkdir "$RUN"                       # 已存在必须失败
export APPDATA="$RUN/runtime/roaming"
export LOCALAPPDATA="$RUN/runtime/local"
export TMPDIR="$RUN/tmp" TEMP="$RUN/tmp" TMP="$RUN/tmp"
export PYTHONDONTWRITEBYTECODE=1
mkdir -p "$APPDATA/Godot/export_templates/4.7.2.stable" "$LOCALAPPDATA" "$TMPDIR"
# 只从C读取现成模板；editor/import与游戏用户资料全部落E。
for f in windows_release_x86_64.exe windows_debug_x86_64.exe \
         windows_release_x86_64_console.exe windows_debug_x86_64_console.exe; do
  cp "$TEMPLATES/$f" "$APPDATA/Godot/export_templates/4.7.2.stable/$f"
  cmp "$TEMPLATES/$f" "$APPDATA/Godot/export_templates/4.7.2.stable/$f"
done
sha256sum "$SOURCE/export_presets.cfg"
# 审批后精确声明，不按data目录/dedicated_server推角色。
RUNTIME='[{"source":"addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll","target":"libfate_server_signals.windows.template_release.x86_64.dll"},{"source":"addons/webrtc_native/lib/libwebrtc_native.windows.template_release.x86_64.dll","target":"libwebrtc_native.windows.template_release.x86_64.dll"}]'
```

需先暂停并行源写入/审批来源data无凭据，或先建立自足不可变快照后以该快照替代SOURCE。下面已有冻结器默认携带import元信息引用的暖cache，不声称冷导入；本任务没有验证冷快照导出。隔离副本的project/preset转换规则见 `freeze_prepare.py:31–56,122–161`，不是修改源preset。

### B. 冻结/最终导出/外置data/审计

```bash
python -B "$SOURCE/tools/release/freeze_prepare.py" \
  --source "$SOURCE" --target "$RUN/freeze-client" --manifest "$RUN/freeze-client.json" \
  --preset 'FateDomination_demo_v1' --role client --executable FateDomination.exe \
  --runtime-files "$RUNTIME" --allowed-root "$ALLOWED" --prepare
python -B "$SOURCE/tools/release/freeze_prepare.py" \
  --source "$SOURCE" --target "$RUN/freeze-server" --manifest "$RUN/freeze-server.json" \
  --preset 'FateServer Windows' --role server --executable FateServer.exe \
  --runtime-files "$RUNTIME" --allowed-root "$ALLOWED" --prepare
python -B -c 'import json,sys; a,b=[json.load(open(p,encoding="utf-8")) for p in sys.argv[1:]]; assert a["source_files"]==b["source_files"],"SOURCE_FREEZE_MISMATCH"' \
  "$RUN/freeze-client.json" "$RUN/freeze-server.json"
sha256sum "$RUN/freeze-client.json" "$RUN/freeze-server.json" \
  "$RUN/freeze-client/export_presets.cfg" "$RUN/freeze-server/export_presets.cfg"
# 以下参数声明无凭据必须有真实审核，不能为了运行工具自动确认。
python -B "$SOURCE/tools/release/release_prepare.py" \
  --project "$RUN/freeze-client" --output "$RUN/build-client" --godot "$GODOT" \
  --preset 'FateDomination_demo_v1' --platform windows --role client \
  --manifest "$RUN/client-build.json" --freeze-manifest "$RUN/freeze-client.json" \
  --allowed-root "$ALLOWED" --credential-free-project --execute
python -B "$SOURCE/tools/release/release_prepare.py" \
  --project "$RUN/freeze-server" --output "$RUN/build-server" --godot "$GODOT" \
  --preset 'FateServer Windows' --platform windows --role server \
  --manifest "$RUN/server-build.json" --freeze-manifest "$RUN/freeze-server.json" \
  --allowed-root "$ALLOWED" --credential-free-project --execute
```

`release_prepare.py:32–40,75–81`实际编排：headless editor import → `--export-release` → `copy_data_after_export.py --project <freeze> --output-dir <新载荷目录>` → `release_contract.py`复制/比对声明DLL → `package_audit.py`。不是只导出EXE。未给渲染器覆盖时保留 `project.godot:87 renderer/rendering_method="mobile"`；如决定覆盖，须在两个命令都显式加同一批准的 `--rendering-method`，并记录，不按角色猜渲染器。

为核对精确最终导出调用，工具将生成下列Godot命令（**不要在编排成功后再重复导出覆盖产物**）：

```bash
"$GODOT" --headless --editor --path "$RUN/freeze-client" --import
"$GODOT" --headless --path "$RUN/freeze-client" --export-release \
  'FateDomination_demo_v1' "$RUN/build-client/windows/client/FateDomination.exe"
"$GODOT" --headless --editor --path "$RUN/freeze-server" --import
"$GODOT" --headless --path "$RUN/freeze-server" --export-release \
  'FateServer Windows' "$RUN/build-server/windows/server/FateServer.exe"
```

每步保留真实exit_code与step日志；非零立即停。exit0也须扫描 `SCRIPT ERROR`、`Parse Error`、`ERROR:`、`Export failed`。编排器现有 `check_export_log`只检查前两类固定byte标记（`SCRIPT ERROR:`、`ERROR:`），还需人工/独立补查其余标记；不允许重跑暖副本覆盖首次失败证据。

### C. 最小双角色组包与SHA/ZIP复核

前置：B已真实完成、PCK追加隐私黑名单审查已通过、来源data无凭据已批准。此处不自动生成或复制未知 `Start.cmd`，不是声称一键真人包已齐备。`docs/human-test-quickstart.md`当前版本需审核后作为说明；服务端只复制当前冻结副本的配置。以下组包程序根据真实audit清单选文件，不复制step日志/用户根。

```bash
python -B - "$SOURCE" "$RUN" <<'PY'
import hashlib, json, pathlib, sys, zipfile
source, run = map(pathlib.Path, sys.argv[1:])
sys.path.insert(0, str(source / 'tools/release'))
from package_audit import pck_index
stage = run / 'package'
assert not stage.exists(), 'NEW_STAGE_REQUIRED'
# 私有运行资料名；不误伤合法 scripts/net/identity 认证源码。
forbidden = {'savedkeys','net_identity','match_saves','server_rooms','authority_rooms',
             'runtime','runtime_reports','logs','test','tests','newtests','tools','newtools',
             'docs','newdocs','reports','scratch','backups','buildmanifest','.git','.godot'}
def check_name(name, packed=False):
    p = pathlib.PurePosixPath(name)
    assert not p.is_absolute() and '..' not in p.parts and ':' not in name and '\\' not in name
    denied = set(x.lower() for x in p.parts) & forbidden
    # PCK的导入/编译资源不是开发缓存；仅允许已知运行期路径形态。
    if packed and p.parts[0] == '.godot':
        assert ((len(p.parts) >= 3 and p.parts[1] in {'imported','exported'})
                or name == '.godot/global_script_class_cache.cfg'), 'UNKNOWN_PACKED_CACHE'
        denied.discard('.godot')
    assert not denied, 'FORBIDDEN_PATH: ' + name
    assert p.name.lower() not in {'server_players.json','private.pem','identity.json','profile.json'}, name
    assert p.suffix.lower() not in {'.log','.pem','.key','.tmp','.obj','.os','.o','.lib','.exp','.pdb','.ilk','.a'}, name
    return p.as_posix()
def sha_file(p):
    h = hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda: f.read(1048576), b''): h.update(b)
    return h.hexdigest()
plan = {}
for role, label, exe in [('client','Client','FateDomination.exe'),('server','Server','FateServer.exe')]:
    build = run / ('build-' + role)
    audit = json.loads((build / ('windows-' + role + '-audit.json')).read_text(encoding='utf-8'))
    assert audit['status'] == 'STATIC_PASS_RUNTIME_PENDING' and audit['role'] == role
    payload = build / 'windows' / role
    pck = pathlib.Path(exe).with_suffix('.pck').name
    allowed = {exe, pck, 'libfate_server_signals.windows.template_release.x86_64.dll',
               'libwebrtc_native.windows.template_release.x86_64.dll'}
    if role == 'server' and (payload / 'FateServer.console.exe').is_file():
        allowed.add('FateServer.console.exe')
    frozen = json.loads((run / ('freeze-' + role + '.json')).read_text(encoding='utf-8'))
    data = {k: v for k,v in frozen['source_files'].items() if k.startswith('data/') and not k.endswith('.import')}
    assert data, 'DATA_REQUIRED'
    allowed.update(data)
    actual = {p.relative_to(payload).as_posix() for p in payload.rglob('*') if p.is_file()}
    assert actual == allowed, 'PACKAGE_WHITELIST_MISMATCH: ' + role
    assert set(audit['package_files']) == allowed
    idx = pck_index(payload / pck)
    assert idx['engine'] == [4,7,2]
    for entry in idx['files']: check_name(entry.removeprefix('res://'), packed=True)
    for rel in sorted(allowed):
        check_name(rel)
        p = payload / rel
        for q in (p, *p.parents):
            assert not q.is_symlink() and not q.is_junction(), 'REDIRECT_PATH'
        assert p.stat().st_nlink == 1, 'HARDLINK'
        digest = sha_file(p)
        assert digest == audit['package_files'][rel]
        if rel.startswith('data/'): assert digest == data[rel]
        plan[label + '/' + rel] = (p, digest)
config = run / 'freeze-server/assets/config/server.cfg'
readme = source / 'docs/human-test-quickstart.md'
assert config.is_file() and readme.is_file(), 'APPROVED_CONFIG_README_REQUIRED'
# 若批准的部署配置/说明不同，应显式替换来源并记录SHA，不从旧包选择。
plan['Server/server.cfg'] = (config, sha_file(config))
plan['README-真人测试.md'] = (readme, sha_file(readme))
assert len({x.lower() for x in plan}) == len(plan), 'CASE_COLLISION'
# 全量预检完成后才创建新暂存目录，不清理/覆盖既有目标。
stage.mkdir()
manifest = {}
for rel,(src,digest) in sorted(plan.items()):
    dst = stage / check_name(rel)
    dst.parent.mkdir(parents=True, exist_ok=True)
    with src.open('rb') as r, dst.open('xb') as w:
        for b in iter(lambda: r.read(1048576), b''): w.write(b)
    assert sha_file(dst) == digest == sha_file(src), 'COPY_SHA_CHANGED'
    manifest[rel] = digest
mf = stage / 'SHA256SUMS.json'
with mf.open('x', encoding='utf-8', newline='\n') as f:
    f.write(json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + '\n')
expected = {**manifest, 'SHA256SUMS.json': sha_file(mf)}
archive = run / 'Windows-client-server-candidate.zip'
with zipfile.ZipFile(archive, 'x', compression=zipfile.ZIP_DEFLATED) as z:
    for rel in sorted(expected): z.write(stage / rel, rel)
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None, 'ZIP_CRC_FAILED'
    names = z.namelist()
    assert len(names) == len(set(names)) == len({n.lower() for n in names}), 'ZIP_DUPLICATE'
    assert set(names) == set(expected), 'ZIP_MANIFEST_SET_MISMATCH'
    for rel in names:
        check_name(rel)
        h = hashlib.sha256()
        with z.open(rel) as f:
            for b in iter(lambda: f.read(1048576), b''): h.update(b)
        assert h.hexdigest() == expected[rel], 'ZIP_SHA_MISMATCH'
print(json.dumps({'status':'STATIC_INTEGRITY_ONLY_RUNTIME_NOTRUN',
                  'manifest':str(mf),'manifest_sha256':sha_file(mf),
                  'zip':str(archive),'zip_sha256':sha_file(archive)}, ensure_ascii=False))
PY
sha256sum "$RUN/package/SHA256SUMS.json" "$RUN/Windows-client-server-candidate.zip"
```

说明：上述脚本/命令只写在报告，**未执行、未宣称真实ZIP验证成功**。其命名黑名单不能替代无凭据内容审核；README/配置仍需批准，实际exporter若生成额外运行依赖必须先明确声明并审查后扩白名单，不能删除陌生文件凑相等。包内 README 应明确尚未完成的启动、Ctrl+Break正常关服、身份恢复、GUI、跨网验收边界。

### D. Linux 精确预设调用（仅语法清单；没有已实现的完整发行门）

在另行取得**Linux审核冻结工程、原生依赖与组包审计方案**后，最终导出形态是：

```bash
# LINUX_CLIENT_FREEZE / LINUX_SERVER_FREEZE / LINUX_OUT 必须来自获批新E根。
"$GODOT" --headless --path "$LINUX_CLIENT_FREEZE" --export-release \
  'Linux' "$LINUX_OUT/Client/FateDomination.x86_64"
"$GODOT" --headless --path "$LINUX_SERVER_FREEZE" --export-release \
  'FateServer Linux' "$LINUX_OUT/Server/FateServer.x86_64"
python -B "$SOURCE/tools/copy_data_after_export.py" \
  --project "$LINUX_CLIENT_FREEZE" --output-dir "$LINUX_OUT/Client"
python -B "$SOURCE/tools/copy_data_after_export.py" \
  --project "$LINUX_SERVER_FREEZE" --output-dir "$LINUX_OUT/Server"
```

这些变量/冻结声明/审计门当前 **unknown**，不得赋成Windows freeze或现有工作树直接执行；现有Windows专用prepare/audit拒绝Linux。Linux debug模板存在只解决模板前置，不解决角色/依赖/组包门。

## 7. 阻断与尚未证实项

1. **当前源树缺 `release_contract.json`**：精确preset/platform/role/executable/runtime_files发行声明未齐备。未来CLI显式声明可在冻结副本解决，但需批准，不能说当前已有。
2. **隐私资源排除缺口**：savedkeys、私有身份资料、存档、日志及运行根缺显式源preset排除；现有audit也缺完整隐私/包外白名单门。实际泄漏情况unknown，不能以未发现同名目录关闭。
3. **开发helper在production project autoload中**：直接导出当前project不满足干净发行门。隔离转换已存在，尚未真实准备/导入/验证。
4. **无凭据/data内容审批unknown**；copier只排除`.import`，不是秘密净化器。
5. **来源未锁定**：本次两个dry-run不是不可变冻结；后续并行源码变化使摘要/本报告失效，需重核对。已修改的copier等发行工具也应纳入执行证据SHA。
6. **Linux完整发行门未实现**，不得把Windows静态结果外推。
7. **当前Start.cmd来源缺失**；如果交付要求一键启动真人包则是组包前置缺口。本清单只能在审批后生成明确标记的最小候选包。
8. **模板运行查找、导入、首次原生加载、真正export、PCK实际资源、最终ZIP、EXE启动、独立worker/自然停止/身份恢复/GUI/跨机跨网全部unknown/NOTRUN**。静态模板匹配、dry-run exit0、未来ZIP完整性都不等于导出已通过或发布READY。
