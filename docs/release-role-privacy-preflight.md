# 发行角色与隐私前置：声明审计结果

## 结论

**角色声明已补齐，隐私清单可审计，但完整隐私执行门仍 BLOCK。**

- 当前客户端、游戏服务端的精确选择均由缺声明 `exit 2` 转为 `exit 0`。
- 信令声明显式存在，但对开发源工程选择返回 `exit 2: 纯信令工程禁止游戏/其他 autoload`，是正确的职责隔离拒绝，不是缺声明。信令冻结 dry-run 为 `exit 0`；未创建冻结副本，不声称冻结后角色已验收。
- 隐私目录/已知文件名由**原已存在**的冻结白名单排除声明覆盖，**不是本轮新增或接入**；任意后缀/诊断模式、显式依赖绕过、整个包外白名单仍未接线。不能把声明完备或测试程序 `exit 0` 当隐私门通过。
- 本轮无 Godot、无导出、无原生库加载、无 EXE/PCK/ZIP；未操作 PID 17120/28100。只修改本报告与隐私策略的文字状态，新增仓库内审计、合成夹具、证据及未应用的声明候选补丁。**未修改 `freeze_prepare.py`**、`scripts/`、开发 project、源预设或任何 include/exclude/export_filter 语义。
- **data/冻结集合无凭据审批已由用户批准**：引用 `docs/credential-free-evidence.md` §6；批准限 §1–5 只读取证范围，不是内容扫描通过，也不覆盖最终 manifest 或缓存未知项。

## 1. 现有角色检查与声明

工具：`tools/release/release_contract.py`。

- `NAME`（10）：工程根目录 `release_contract.json`。
- `declarations`（22–52）：`version=1`、非空 `targets`；每条 target 的字段集合**必须精确等于** `preset/platform/role/executable/runtime_files`（30）。联合键不得重复（32–35）。目前仅 `platform=windows`、`role=client/server/signaling`（36–37）。
- `executable` 为单层 `.exe`（38–40）；运行依赖逐项精确 `source/target`，相对路径无穿越，来源文件必须存在（43–51）。
- `select`（55–71）只按精确 preset/platform/role 选择；client/server 强制 `data` 目录（60–61）。这是目录前置，**非 data 内容无凭据或非空审批**。
- signaling 必须无有效 autoload（64–67）且 `[network] signaling_only=true`（68–70），不按 data 目录、dedicated_server 或目录名称猜职责。

新声明 `release_contract.json:targets`：

| preset | platform | role | executable | 显式运行依赖 target |
|---|---|---|---|---|
| FateDomination_demo_v1 | windows | client | FateDomination.exe | libfate_server_signals.windows.template_release.x86_64.dll；libwebrtc_native.windows.template_release.x86_64.dll |
| FateServer Windows | windows | server | FateServer.exe | 同客户端两条 |
| FateServer Windows | windows | signaling | FateSignaling.exe | 仅 libfate_server_signals.windows.template_release.x86_64.dll |

来源分别精确声明为 `addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll`、`addons/webrtc_native/lib/libwebrtc_native.windows.template_release.x86_64.dll`，与真实 descriptor 映射一致。没有新增/猜测不存在的信令 preset。同一个服务端 preset 被明确用于两种冻结转换角色，**必须传 role**；省略 role 时真实检查已确认拒绝“不存在或不唯一”。

**信令边界：**本声明只描述现有通用 `freeze_prepare.py --role signaling` 的 descriptor-in-project 布局。另一个 `signaling_prepare.py:25–26,39,46–48,67–69` 使用 `native/fate_server_signals.gdextension` 和 `native/<DLL>` 外置布局，不能把这两条路径混用。其完整 external-native release_contract 仍未声明；选择该路径时需 owner 另行补声明，不得用此通用声明冒充。这里没有为冷加载/发行 READY 背书。

## 2. 冻结与组包逐项清单

“已覆盖”仅指现有冻结消费者对所列路径组件/精确文件名生效，不指实际发行包。“未覆盖”已有真实消费者反例；“unknown”缺实际路径或内容证据。

| 项目 | 实现证据（文件:行/字段） | 本次覆盖结论 |
|---|---|---|
| 客户端身份目录、私钥、资料 | `scripts/net/ui/lobby_screen.gd:24–25`，`identity_key_path=user://net_identity/private.pem`、`identity_profile_path=user://net_identity/profile.json`；`freeze_prepare.py:13–22 EXCLUDED`、86 路径组件匹配 | **已覆盖** `net_identity`、`private.pem`、`profile.json`；整个身份目录排除，保留合法 `scripts/net/identity/**` |
| 服务端身份登记库 | `assets/config/server.cfg:16 identity_registry=user://server_players.json` | **已覆盖**精确 `server_players.json`；改名/任意 JSON 内容秘密 **unknown** |
| 任意私钥文件 | `freeze_prepare.py:86` 对 `data` 不限扩展名；策略 `package.deny_suffixes=.pem/.key` | **未覆盖执行**：真实夹具 `data/example.pem`、`data/example.key` 仍被选择；新策略已声明但既有消费者未读取 |
| 客户端存档 | `scripts/net/session/lobby_session.gd:141 archive_root=user://match_saves` | **已覆盖** `match_saves`，另明确排除 `saves/savegames`；任意改名存档内容 **unknown** |
| 服务端/authority 存档 | `assets/config/server.cfg:13 storage_root=user://server_rooms`；`scripts/net/session/authority_host_client.gd:32 storage_root=user://authority_rooms` | **已覆盖** `server_rooms/authority_rooms` |
| 日志目录 | `server_gateway.gd:493–495 _log_transport_diagnostic`；`lobby_session.gd:1781–1784 RECOVERY_SAVE_DIAGNOSTIC` 为真实诊断输出；实际日志文件根 **unknown** | **已覆盖** `logs` 路径组件；stdout 诊断源码不是秘密文件，不能删除源码 |
| 任意日志/崩溃输出文件 | 策略 `package.deny_suffixes=.log/.dmp`；现有 inventory 没有对应后缀拒绝 | **未覆盖执行**：真实夹具 `data/example.log` 仍被选择；实际 `.dmp` 位置 **unknown** |
| 诊断/验证输出 | `scripts/net/validation/room_data_validation_worker.gd:14 user://validation-probe-<pid>.json`；`room_validation_task.gd:10 user://room_validation` | **已覆盖** `diagnostics/room_validation` 组件；**未覆盖**独立 `validation-probe-*.json`，真实夹具仍被选择 |
| 运行/缓存/临时房间根 | `content_cache.gd:8 user://net_cache/blobs`；`room_data_preparation.gd:61–63 user://net_session/room_validation`；`lobby_screen.gd:154 user://rooms/<id>/data`；`load_game.gd:212 user://game_data/stored_jsons.dat` | **已覆盖** `runtime/net_cache/net_session/room_validation/rooms/game_data`；不复制用户根，实际 user:// 映射 **unknown/NOTRUN** |
| savedkeys | `tools/release/human_test_candidate.py:29 FORBIDDEN_PARTS` 已有禁止项；生产写入位置 **unknown** | **已覆盖**原已存在的冻结 EXCLUDED 中显式 `savedkeys`；无须按目录存在推断 |
| 开发 autoload | `project.godot:41 _mcp_game_helper`；`freeze_prepare.py:42–67 transform_project`，55–57 精确已知 helper，未知同名值拒绝 | **已有实现+静态已核对**：内存转换移除已知 helper；源 project 未改，实际冻结副本 **NOTRUN** |
| 开发插件/版本控制 | `project.godot:55–60 version_control/plugin_name/autoload_on_startup/editor_plugins.enabled`；`freeze_prepare.py:60–63` 清插件、禁 VCS；9–10/82 白名单不递归普通 addons | **已有实现+静态已核对**；Godot AI/Git 插件不在常规资源白名单，EXCLUDED 也明确声明组件。未知新插件须另审，不按名称自动认定无害 |
| 开发测试/文档/报告/工具 | `freeze_prepare.py:9–22,82–87`；`export_presets.cfg:exclude_filter` 原有规则 | **已覆盖** root 白名单不选普通顶层开发目录，并明确排除嵌套 `test/tests/newtests/tools/newtools/docs/newdocs/reports/runtime_reports/scratch/backups/buildmanifest/__pycache__` |
| 显式依赖绕过 | `freeze_prepare.py:73` 直接加入 runtime_files，88–99 加 descriptor 库，122–125 加暖 import 缓存；这些分支无最终全量 EXCLUDED 门 | **未覆盖执行**：真实夹具将 `data/savedkeys/example.json` 放进 runtime_files 后仍被选择；当前声明没有该项，不能据此保证未来安全 |
| 外置 data | `tools/copy_data_after_export.py:25–26,117–132` 只跳过 `.import`；`freeze_prepare.py:86` data 复制所有类型 | **已由用户批准**（`docs/credential-free-evidence.md` §6）；未读内容/最终集合未固定仍 **unknown**，批准不能被写成内容扫描通过 |
| 包外精确白名单/PCK/ZIP | `package_audit.py:97–104` 仅有限 PCK 开发项；142 记录 package_files，未要求等于整包白名单；新策略 `package.payloads/assembly_extra_files/required_integrity` | **白名单已声明、执行未接线**；真实 PCK/ZIP **NOTRUN**；保持隐私 BLOCK |

新策略的 client/server 载荷精确白名单：对应 EXE/PCK、两条 release DLL、同一审核冻结 `data` 集合（跳过 `.import`、必须非空）。Server console wrapper 只在 exporter 真生成且审批 SHA 后允许。通用信令仅 EXE/PCK/一条 signals DLL，禁止 data。顶层额外项仅审核后的 `Server/server.cfg`、`README-真人测试.md` 和生成的 `SHA256SUMS.json`。当前来源缺 `Start.cmd`，不自动放进白名单。实际额外依赖不得删除凑相等，须补显式声明再审。

## 3. 最小改动及 SHA256

| 文件 | 改动 | SHA256 |
|---|---|---|
| `release_contract.json` | 本任务未改；原角色声明 SHA 为 a9bda785…；并行 owner 后续新增启动依赖，见 §9 | `dd57c638567046b2069f61580eb567edf5564b2ff7a6d1acfc1ca7765b28824f` |
| `tools/release/release_privacy_policy.json` | 既有声明保留；本轮仅纠正用户已批准及 savedkeys 原已覆盖的文字 | `7f9ba2d33a92c7e02bfb5ecf0b6637d27faf962a0c0022b8df0c77fcd17b56c0` |
| `tools/release/freeze_prepare.py` | **本任务未改动**；隐私 EXCLUDED 原已存在；并行 owner 新增 role 过滤行，见 §6/9 | `51f9810536d2a26f35e93d791bf71123ade02dc052052542623f573892ccc6c1` |

本报告为已有报告的纠正版本；报告自身及本轮全部资产 SHA 见 `tools/release/evidence/role-privacy/delivery-sha256.json`，清单不包含自身。源 `export_presets.cfg` SHA 仍为 `f8f6afbbeb520f780deab5d7f7d5a59e9f5b2f33e02db4cb64c6823a428da091`，与原预检相同。

## 4. 真实执行命令与退出码

工作目录 `E:/Projects/Godot/FateDominationGame-master`。改前实际命令：

```bash
python -B -c 'import sys; from pathlib import Path; sys.path.insert(0,"tools/release"); from release_contract import select; root=Path.cwd();
try: print(select(root,"FateDomination_demo_v1","windows","client"))
except (OSError,ValueError) as e: print("BLOCK:",e); sys.exit(2)'
```

实际 `exit 2`：`BLOCK: 缺少项目发行声明: release_contract.json`。

本轮从仓库内重跑的实际命令（已执行）：

```bash
mkdir -p tools/release/evidence/role-privacy
python -B tools/release/role_privacy_audit.py \
  > tools/release/evidence/role-privacy/execution.stdout.txt \
  2> tools/release/evidence/role-privacy/execution.stderr.txt
```

首次仓库内运行真实 **exit 0**，当时 stderr 为空；成功快照见 `tools/release/evidence/role-privacy/baseline-success/audit.json`。**最终复跑因并行声明变更返回 exit 1**，详见 §9；根目录 execution 日志现在保存最后失败，不能把历史成功当当前树通过。成功时状态仍为 `DECLARATIONS_AUDITABLE_PRIVACY_ENFORCEMENT_INCOMPLETE`，不是隐私执行 PASS。

脚本从自身位置定位仓库根，策略/夹具/输出均为仓库相对路径，不读取原仓库外 scratch。TMPDIR/TEMP/TMP 仅在子进程中设为仓库内证据目录（本机 E 盘），不使用 C 盘临时目录。原工具要求 dry-run 目标与 source 互不包含，因此三角色的**未创建目标**仅由仓库相对位置推导为 `../FateDominationGame-master-role-privacy-dry-run-only/freeze-<role>`；不放任何工具/夹具/日志到那里，不依赖其存在。本轮未创建该目录、冻结副本或 manifest。

| 检查 | 真实 exit | 结果 |
|---|---:|---|
| select client / server | 0 / 0 | 原精确角色声明均选择成功 |
| select signaling（开发游戏工程） | 2 | 原职责隔离拒绝：`纯信令工程禁止游戏/其他 autoload`，预期反例 |
| freeze dry-run client / server / signaling | 0 / 0 / 0 | 原默认暖语义，1898 / 1898 / 15 文件，`godot_invoked=false` |
| 三角色冷 inventory | 审计总 exit 0 | 1438 / 1438 / 13；路径组件及敏感后缀命名检查保留 |
| 项目内存转换 | 审计总 exit 0 | 原 helper、plugins、VCS、autoload/signaling-only 断言均保留 |
| 真实 inventory 合成夹具 | 审计总 exit 0 | 原 17 项：11 排除、**4 仍未覆盖**、2 合法源码保留 |
| package 策略模拟 | 审计总 exit 0 | 原 17 项声明匹配保留，不冒充消费者接线 |
| runtime_files 排除绕过 / 省略 role | 审计总 exit 0 | 原绕过反例及角色歧义拒绝保留 |
| 候选声明补丁 | 审计总 exit 0 | 对原 4 项均匹配拒绝；只测候选声明，未应用 |

所有真实 subprocess argv、exit、原始 stdout/stderr 在 `tools/release/evidence/role-privacy/audit.json:commands`；分命令日志在同目录。

### 检查项前后清单对比（不删检查换绿）

- 原脚本 SHA：`335bd0d34f4496c8e432dad22b96899cabdca7b6edf4fbf81ece90d2bbb4d6ab`；原结果 SHA：`84f1e4f5c5d80993711e122b7320fd1468faee57228173bfd34221af9cb4d965`。
- `tools/release/fixtures/role-privacy/original-checklist.json`：从原脚本 AST 和原报告提取的完整原断言（含原行号）、17 夹具路径/期望/结果、6 命令标签/期望 exit 及额外 JSON/AST/角色检查。
- `tools/release/fixtures/role-privacy/inventory-cases.json`：原 17 项合成夹具声明，脚本可在仓库内重建 `inventory-fixture/`，内容均为明确的非秘密测试标记。
- `tools/release/evidence/role-privacy/checklist-comparison.json`：**19 → 19 原断言表达式全部保留；removed=[]；17 → 17 夹具及其结果逐项相同；17 → 17 策略检查；6 → 6 命令标签和期望退出码相同**。不是只比较总数。
- 原 JSON 解析、freeze AST 解析、无 role 必须异常、三角色冷选择/内存转换未删；新增审批证据校验、候选声明覆盖及前后清单比对。`-O`/`PYTHONOPTIMIZE` 明确拒绝，避免原 assert 被关闭；实际 `python -B -O tools/release/role_privacy_audit.py` 返回预期 exit 1，错误明确指向关闭断言，日志保存在同一证据目录。
- “credential-free content approval” 从旧报告的仍缺列表移至 `credential_free_approval=APPROVED_BY_USER`，因为用户已经批准；这不是删除测试，原程序也没有无凭据内容检查。

首次尝试把 stdout 重定向到尚不存在的证据目录，shell exit 1，审计脚本未执行；创建仓库内日志目录后重跑 exit 0。没有改断言预期来消除失败。

## 5. 仍缺什么

1. 在本次唯一写入范围之外，需要 owner 接入现有冻结/组包消费者的**最终全量路径/后缀/诊断模式门**，包括 runtime_files、descriptor/import 依赖绕过的最后核对，以及整个包外精确白名单。单改 EXCLUDED 声明不能做到这些；本任务没有擅自修改函数或生产 scripts。
2. **来源 data/冻结集合无凭据审批已由用户批准**（`docs/credential-free-evidence.md` §6），不是仍缺项。仍缺不可变同一来源/最终 manifest 绑定、真实冻结 copy/转换后的 project 和角色选择验证；未读内容与缓存未知边界仍保留。
3. 信令须明确采用通用冻结布局还是既有 external-native 专用布局；不能拼二者声明。源游戏项目继续拒绝 signaling 正确；实际发行工程的 zero-autoload/signaling_only/真实运行依赖验证尚未做。
4. Linux 不在本轮发行范围（`docs/credential-free-evidence.md` §7），不列为本轮仍缺准入项。
5. 原预检其他阻断不在此次关闭范围：Start.cmd 来源/审批、真实导入/导出、PCK/ZIP与最终 EXE/worker/正常停止/恢复/GUI/跨机跨网均 NOTRUN。

## 6. freeze_prepare.py 原声明对账与更正说明

先前报告第 9/10 行及 SHA 表把 EXCLUDED/相邻注释列为“本轮新增/修改”，**该表述不属实，现明确纠正为原已存在**；不是只删除错误文字。

`docs/credential-free-evidence.md` §5 已记录同一 SHA，本任务开始与首次成功审计时读取均为：

`b9f1cc2a38f9738e0899a0ae3ccee399e755b7584b2217b4986159081ffc083d`

该初始版本与先前取证逐字节相同，原有集合无需再新增；本任务没有向 freeze_prepare.py 打补丁。最终发现并行 owner 只在当前第 77 行新增 `if role is not None and target['role'] != role: continue`，整文件 SHA 变为 `51f9810536d2a26f35e93d791bf71123ade02dc052052542623f573892ccc6c1`。只在内存去掉该新增行再哈希，精确恢复上述 b9f1cc2a…；**EXCLUDED 与注释仍未变**，故“本轮新增隐私声明”依然不属实。未覆写并行 owner 文件。实际内容和行号如下（直接读取最终当前文件）：

```text
11 # 仅按显式路径组件排除；不按目录存在猜发行角色，不改导出过滤器。
12 # 任意 *.pem/*.key/*.log 与无凭据内容审批仍需独立发行门，见 release_privacy_policy.json。
13 EXCLUDED = {
14     'test', 'tests', 'newtests', 'reports', 'scratch', 'runtime_reports',
15     'game_data', '__pycache__', 'tools', 'newtools', 'docs', 'newdocs',
16     'backups', 'buildmanifest', 'savedkeys', 'net_identity',
17     'identities', 'match_saves', 'server_rooms', 'authority_rooms', 'saves',
18     'savegames', 'logs', 'runtime', 'diagnostics', 'net_cache', 'net_session',
19     'room_validation', 'rooms', 'private.pem', 'profile.json',
20     'server_players.json', 'identity.json', 'resume_ticket.json',
21     'resume_tickets', 'recovery_tickets', 'godot_ai', 'godot-git-plugin',
22 }
```

初始第 86 行、最终第 87 行的消费者用小写**完整路径组件**与集合求交：`directory == 'data'` 分支不限制后缀。因此 private.pem 精确文件名已覆盖，但任意 example.pem 未覆盖；增加 `'.pem'` 或 `'*.pem'` 到 EXCLUDED 不会生效。最终第 73/89–100/123–126 行显式依赖加入仍无最终全量排除门。这是已有实现的真实缺口，不得写成新增声明已修复。

## 7. 原四项未覆盖隐私项与最小候选补丁

“已覆盖”只按层说明；当前真实消费者均仍选择下列四个负向夹具。

| 原检查项 | 已覆盖 | 缺什么 | unknown |
|---|---|---|---|
| `data/example.pem` | package 策略已有 `.pem`；`net_identity/private.pem` 等原精确路径已排除 | freeze 最终全量 suffix 门（含显式依赖），当前夹具仍入选 | 真实任意 pem 的位置/内容未检查 |
| `data/example.key` | package 策略已有 `.key`；已知身份目录原已排除 | 同上，不能用 EXCLUDED 后缀字符串代替消费者 | 真实任意 key 的位置/内容未检查 |
| `data/example.log` | package 策略已有 `.log/.dmp`；`logs` 组件原已排除 | 任意位置日志/崩溃后缀最终拒绝门，当前 log 仍入选；`.dmp` 未做真实 inventory 夹具 | 实际日志根、dmp 位置/内容未知 |
| `data/validation-probe-1.json` | package 策略已有 `validation-probe-*.json`；`room_validation/diagnostics` 组件原已排除 | 独立文件名模式最终拒绝门，当前夹具仍入选 | 实际 user:// 映射与运行输出 NOTRUN |

候选：`tools/release/candidates/role-privacy-final-inventory-declaration.patch`，**未应用**。只给已有 policy 的 freeze 段增补 `final_inventory_candidate` 声明：`.pem/.key/.log/.dmp`、`validation-probe-*.json`、覆盖 runtime_files/descriptor/import 完整闭包的要求，以及 `DECLARED_NOT_WIRED` 状态。合法 `scripts/net/identity/**`、`recovery_save_diagnostic.gd` 必须保留；遇到必需依赖命中应拒绝，不静默删除依赖。

```bash
git apply --check tools/release/candidates/role-privacy-final-inventory-declaration.patch
```

真实 **exit 0**。候选只改声明，不改任何 export_filter/include_filter/exclude_filter，也不改冻结选择函数。审计新增验证候选声明匹配全部原四项；**没有把四项 NOT_COVERED 改成消费者已覆盖**。现有 package 精确白名单保留；仍缺消费者接线及真实 PCK/ZIP/整包核对，声明候选不自动关闭这些缺口。

## 8. 仓库内交付资产与摘要

| 文件 | SHA256 |
|---|---|
| `tools/release/role_privacy_audit.py` | `4cd2d304b340fdc6e5feea3e529d8900e130749219d68b542c7bbb021222c091` |
| `tools/release/fixtures/role-privacy/original-checklist.json` | `f2ff2365e8ad652f5aa26f75fcf7f633fa61420edc5d858dd16c102cb459d1d2` |
| `tools/release/fixtures/role-privacy/inventory-cases.json` | `803d0a7ec93e11cdf4b44ff9ebedd0e1f5a150b98677a2074355d37a494f283e` |
| `tools/release/candidates/role-privacy-final-inventory-declaration.patch` | `cc1b232f1d5867bf9c3f8a45ccb1d99f1689ee0cfa1c45df511268e841574df2` |
| `tools/release/evidence/role-privacy/audit.json` | `9645b7baf1803711bc20c6b20076e424680d3b89fbbb217ce3c5bc118e3d2c33` |
| `tools/release/evidence/role-privacy/checklist-comparison.json` | `769f0b5f87a474d7b2cce32a9aad4a4540fe90bcfd3e83da92207eca9820f756` |

合成夹具实体与全部分角色 stdout/stderr/执行日志的相对路径和 SHA256 也纳入 `tools/release/evidence/role-privacy/delivery-sha256.json`。历史仓库外原件仅作为原结果来源保留，本轮工具/夹具/策略/证据不依赖原件，重跑无需读取它。

## 9. 最终复跑的并行来源漂移阻断（不得用历史成功冒充当前通过）

同一命令 `python -B tools/release/role_privacy_audit.py` 最后真实 **exit 1**，原第 77 行 `assert not forbidden` 报：

```text
['tools/release/templates/human-test/Launch-HumanTest.ps1',
 'tools/release/templates/human-test/START-CLIENT.cmd']
```

并行 owner 的新 `release_contract.json` 已把 tools 下启动器作为显式 runtime_files 加入三个角色（当前 SHA `dd57c638567046b2069f61580eb567edf5564b2ff7a6d1acfc1ca7765b28824f`）。这触发原已存在的禁止 tools 组件检查；没有删除该断言，没有自动批准 launcher 例外，也没有回滚别人修改。需 owner 明确决定启动器是否应是包外组装资产，或补精确路径+SHA 白名单及其审核消费；不可笼统解除 tools 禁入。

- 历史成功：`baseline-success/audit.json` 及从该报告内**真实原始捕获**保存的分命令 stdout/stderr。其 `files_sha256.release_contract.json=3fd93d4b945eb04d8a0261158ccf427e03ac0fb8652884f8a550b1f0fb9b8a43` 为成功报告写入时观察值；选择命令仍仅列原 DLL。没有不可变同一来源锁，不能证明这次运行全过程处于相同契约版本。
- 当前失败：`current-source-drift/` 和根 execution 日志；`validation-receipt.json` 分列历史成功与最后失败，不覆盖失败证据。
- 合成夹具实体：仓库外原夹具与仓库内重建夹具 **21 → 21**，逐文件 SHA 完全一致；结果记录在 `validation-receipt.json`，未来重跑不读取仓库外原夹具。
- 候选 `git apply --check` 最新 exit 0；本任务路径 scoped `git diff --check` exit 0。全树 check 曾因其他既有 CRLF 改动返回 2，未修改那些文件。

本轮可复现资产与不实表述已修正；**当前树 exit 0 验收仍被并行新增依赖阻断**，不能列成已完成。四项隐私执行缺口以及来源锁/整包核对继续保留。所有路径以 `tools/release/evidence/role-privacy/` 为相对证据根。
