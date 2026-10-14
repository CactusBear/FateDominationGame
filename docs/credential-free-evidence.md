# 冻结集合"无凭据"取证据要（只读，非审批）

本文件只登记一次**只读取证**的结果与边界，**不构成 `--credential-free-project` 批准**；该项批准必须由用户显式给出。
来源：2026-10-10 只读审计任务（未启动 Godot、未导出、未创建/修改/删除任何文件）。

## 1. 范围与规模（按 `tools/release/freeze_prepare.py` 规则）

扫描目录：`scripts/`、`operations/`（不存在）、`assets/`、`data/`、`json_maker/`。

| 目录 | 文件数 | 扩展名分布 |
|---|---:|---|
| `scripts/` | 835 | `.gd=419, .uid=416` |
| `operations/` | 0 | 目录不存在，按工具规则跳过 |
| `assets/` | 232 | `.cfg=1, .gdshader=8, .gdshaderinc=1, .import=90, .jpg=9, .json=3, .ogv=4, .png=48, .svg=14, .tscn=22, .ttf=5, .txt=1, .uid=12, .webp=14` |
| `data/` | 339 | `.import=134, .json=71, .png=134` |
| `json_maker/` | 23 | `.gd=4, .import=5, .json=2, .png=5, .tres=1, .tscn=2, .uid=4` |

- 默认严格冻结集合（含根文件、原生依赖、`.godot/imported/**` 460 缓存）：**1899 个文件**。
- `cold=True` 集合：**1439 个文件**（不含那 460 缓存）。
- 显式 client/server 模式：各 **1898 个源文件** + 生成 `release_contract.json` → 冻结目标仍 1899。
- 外置 data 复制工具只跳过 `.import`，当前复制候选 **205 个**（71 JSON + 134 PNG）。
- **冻结集合 ≠ 最终 PCK 条目集合**；外置 data 数量与清单内 data 文件数不可混用。

## 2. 高风险模式筛查（只看路径/名称，绝不开读内容）

模式：`key / secret / token / credential / password / identity / savedkeys / ticket` 及密钥类扩展名。

- **未发现** `.pem / .pk / .pfx / .key` 等凭据文件；`data/**` 高风险路径命中 **0**。
- 宽匹配命中 **40 个文件 + 1 个目录**（`scripts/net/identity/`），其中目录下 13 `.gd` + 11 `.uid` 全数列明。命中项**全部为源码/场景及其 `.uid` 旁车**（如 `player_identity.gd`、`room_password.gd`、`identity_inheritance_panel.gd`、`AskPlayersSecretOption.gd`、`worker_identity_ipc.gd`、`supervisor_identity_ipc.gd` 等），**未以内容检查证明其无凭据**。
- 完整 40 项清单（路径 / 字节数 / SHA-256）见该任务的回执表。

## 3. 运行时产物检查（五个扫描目录内，命中均为 0）

`savedkeys、net_identity、identities、match_saves、saves、savegames、logs、runtime、diagnostics、net_cache、net_session、server_rooms、authority_rooms、rooms、room_validation、resume_tickets、recovery_tickets、private.pem、profile.json、server_players.json、identity.json、resume_ticket.json`，以及 `.log/.sav/.save/.dump/.dmp/.sqlite/.db/.cache/.tmp/.bak` 等扩展名。

## 4. 未覆盖 / 未知

- **未检查文件内容**，不能排除普通 JSON / CFG / 脚本 / 二进制内嵌凭据。
- 最终冻结 manifest 未固定，不能证明成品包与本次集合一致。
- `.godot/imported/**` 的 460 个文件是构建缓存，未被证明为非身份/存档产物，也未证明其中不含路径信息。
- 脚本侧：`tools/release/release_prepare.py:68` **只检查显式开关，不实施内容扫描**。

## 5. 本次固定指纹

- `tools/release/freeze_prepare.py` SHA-256：改前 `b9f1cc2a38f9738e0899a0ae3ccee399e755b7584b2217b4986159081ffc083d`；并行任务**新增第 77 行 role 过滤声明**后为 `51f98105…`（内存中去掉该行可精确恢复旧 SHA）。其 `13–22` 的 `EXCLUDED` 声明**原本就已存在**，本轮未改——因此本文件第 1–5 节的取证依据不变，仅指纹需要随行号变动更新。**注意：本文件的推荐值（批准状态 §6）与该行号变更无关。**
- 默认集合**路径摘要**（排序相对路径、每行一个、末尾换行、UTF-8）：`4552bd50e7c02453d919b45ebd41f5ff6d1a85817abef498a3d6896af6866b74`——**这是路径摘要，不是内容摘要**。

## 6. 审批状态

**已批准（2026-10-10，用户在本会话中显式批准）**：

> "批准：按本次只读取证认定冻结集合无凭据（40 项均为源码/场景及其 .uid；data/** 高风险命中 0；无 .pem/.key 类；无运行时产物）"

据此，封包记录中 `--credential-free-project` 一项可写为"已由用户显式批准"，**批准依据限定为本文件的第 1–5 节取证范围**。批准不覆盖第 4 节列出的未知项（未读内容、最终 manifest 未固定、470 个导入缓存未逐项证明），这些项在包记录中仍需保持各自原有状态，不得因本次批准而被写成"已验证无凭据"。

## 7. 本轮发行范围（用户已定）

**仅 Windows 三角色（client / server / signaling）+ 含一键启动脚本**；**不做 Linux 发行**（现有冻结链只选择 Windows preset，`release_prepare.py:19–20`、`package_audit.py:55` 明确拒绝非 Windows，Linux 需另开通道）。
