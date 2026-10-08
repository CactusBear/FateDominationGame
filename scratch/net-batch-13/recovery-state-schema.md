# recovery.json 持久化与失败关闭审计

## 结论与范围

只读审计当前工作树 `scripts/net/**`，只新增本报告；未修改生产代码，未运行 Godot、网络或崩溃恢复测试。仓库已有大量未提交改动，本报告不把其他代理的改动认作本次成果。行号对应审计时源码。

**结论：核心字段已经写入，但不能认定恢复 schema 完整或所有损坏状态都安全拒绝。** 认证模式能拒绝缺失成员—密钥绑定的旧档，上一票据 ACK 退休有写盘失败回滚；仍缺成员凭据覆盖、座位绑定完整性、成员键规范性、选人阶段恢复定义，以及首次票据轮换的持久化失败传播。数据屏障不保存旧 ACK 是合理安全设计，但批准清单/规则状态不是由 recovery.json 完整还原。

## 当前实际落盘 schema

来源：`scripts/net/session/lobby_session.gd:1355-1371`，`scripts/net/session/room_state.gd:123-124`。使用同目录 PID 临时文件、flush/error 检查、rename 替换；失败删临时文件并返回 false。此处不能据此宣称断电 fsync 或 Windows rename 行为已运行验证。

| 字段 | 写入内容 | 读取/拒绝语义 | 判定 |
|---|---|---|---|
| `room.members` | 全体成员字典深复制 | 键可转整数且 1..INT32_MAX；成员须有 String name、bool spectator；恢复强制 connected=false、ready=false | 保存完整原字典，但规范键及字段白名单不足 |
| `room.owner` / `room.revision` | 原房主及修订 | 有限、非负、整值 int/float；非零 owner 必须对应成员 | 已持久化；owner=0 配合非空 playing 成员仍能通过 |
| `room.phase` | lobby/selecting/playing/restoring | 仅接受上述枚举；playing 改为 restoring，其余原样 | playing 安全等待；selecting 缺配套恢复 |
| `room.settings` | 全量设置；runtime_guard 特殊编码 | 只要求 Dictionary；预算专门解码验证 | 没有调用完整 room settings 校验/数值解码 |
| `room_password` | verifier 深复制 | valid_state；缺失默认空 verifier | 正常文件无密码原文；缺字段可降级无密码 |
| `management_paused` | bool | 缺失默认 false；非 bool 拒绝 | 保存正确，缺失与旧档兼容可能解除暂停 |
| `data_revision` | 当前清单版本 | 缺失退回 room.revision；有限非负整值，严格小于 INT32_MAX | 保存并校验；没有证明此版本对应原批准清单 |
| `resume_hashes` | 成员→token.sha256_text() | 必须 Dictionary；普通路径仅校验值为 String；认证模式还要求 64 位小写十六进制及已有身份键 | 无票据原文；缺失整个字典拒绝，但缺成员条目不拒绝 |
| `resume_previous` | 成员→上一可接受票据的哈希 | 同上；字段必须 Dictionary；允许空字典 | 已持久化；未要求 previous 的成员同时有 current |
| `bindings` | match started 时 controllers，否则最近 _recovery_bindings | 必须 Dictionary；键仅 is_valid_int，值有限非负整值；非零值须对应成员 | 不检验座位键非负/规范形式、真人非观战、单席唯一或完整覆盖 |
| `identity_binding_required` | 本房间认证策略 | bool；调用方 required=true 时档案不得降级 false | 本机策略先应用，认证旧档失败关闭 |
| `member_identities` | 成员→已认证公钥指纹，不是私钥/公钥原文 | 认证模式每个成员必须有指纹；指纹键必须规范正整数字符串，值 valid_id；非认证模式要求映射为空 | 已持久化并拒绝缺失认证映射；不同成员同一指纹未禁止 |
| `inheritance_sequences` / `inheritance_audit` | 请求计数、继承事实 | 认证模式验证字典/数组、整值计数及 5 个固定事实键；非认证 valid_state 提前返回 | 已保存；非认证路径未完整校验这两个字段 |

`member_identity_bindings.gd:6-31` 是认证映射验证，`player_registry.gd:10-14` 定义 valid_id；`load_recovery_state():1281-1353` 是完整读取路径。全部主要校验发生在设置 `recovery_state_path` 和修改 session 状态之前；失败不会自动补映射或覆盖原档。

## 数据屏障：重建而非继承旧 ACK

- **实际未写入**：`require_room_data`、`_rules_revision`、`_data_confirmed`、`room_files`、安装的 `_assets`。静态脚本提取落盘顶层字段得到 11 项，与上表一致。
- `load_recovery_state` 恢复 data_revision，但不恢复上述字段，也不主动清理一个已使用 session 的旧 `_data_confirmed` / `_rules_revision`。正式 worker 使用新 session，因此其默认空 ACK 可避免这个复用问题；公共加载函数本身不具备这个保证。
- worker 对已有 `data/` 按当前 plan.files 逐文件验证（`server_room_worker.gd:133-144`），加载固定数据后 host；认证策略在 `load_recovery_state` 前设置（155-164），恢复文件路径也在读取成功后才建立，初始 host 不会先覆盖旧恢复档。
- worker 由当前批准源重建 plan；有 `random_sim_enabled` 声明时跳过初始 set_room_files/install_room_assets（175-183），该路径不能声称原批准清单已经持久化恢复。没有该声明时重新提交文件并增加 data_revision。
- 真正存档恢复成功后，`restore_local_match:1397-1424` 按存档初始数据重新发布、验证、安装清单，显式设置 require_room_data=true、_rules_revision=data_revision+1，随后 `_commit_room_files:1016-1030` 增版本、清 ACK，仅设置本机确认。
- `data_ack:759-763` 只接受当前版本；`data_ready:1032-1040` 在要求数据时检查规则版本一致且所有**当前在线成员（包含观战）**确认。`poll:380-385` 仅在 match_authority.started 且屏障通过后 restoring→playing。
- worker `_try_restore_match:231-235` 仅等待 bindings 中声明的非零成员连接。因此 **bindings 必须完整且不能丢失** 才能保证“所有原真人重连”。屏障本身只要求在线成员，不能补救丢失绑定。

建议区分：旧 ACK 应清空并重新确认，不应要求其永久继承；原批准数据清单及规则版本来源必须有可验证、持久化的恢复契约。当前 recovery.json 仅持久化 data_revision，不满足后者的独立完整 schema。

## 静态确认缺口（待修，未运行复现）

### 高：票据下发在可靠落盘之前，保存失败被忽略

`_accept_identity:244-252` 先更新映射/哈希、发送新票据，再调用 `_persist_recovery_state()`，不检查返回值；`_join_identity:283-285` 已 room.reconnect 后直接返回 true。`_publish:894` 同样忽略保存失败。磁盘写失败且旧进程退出时，客户端可能只剩已接受的新票据，而磁盘仍是旧哈希，恢复被拒；新成员也可能整个未落盘。这不等同于身份越权，但不满足“确认成功即可靠恢复”的事务边界。

对比已正确实现的路径：`identity_ack:736-743` 清 previous 后保存失败会恢复 previous 并发送失败；`_inherit_identity:329` 起也有事务回滚。应把首次/重连轮换改成保存成功后发票据，失败则完整回滚成员连接、revision、哈希及路由映射。

### 高：缺失/部分 bindings 没有失败关闭，空绑定触发重新推导席位

`load_recovery_state:1305-1313` 接受 `bindings:{}`；`_try_restore_match` 等待循环对空字典不等待；`restore_local_match:1385` 会回退 `_room_seats()`，按当前成员迭代顺序重新构造 player→member。

`match_authority.restore_archive:475-481` 能拒绝数量、player_id 或 AI/真人类型不符，但不核对原 member_id 归属；同人数真人绑定可能通过这些检查。这是实际恢复身份继承风险，而非单纯字段漏记。修复应对 playing/restoring 强制完整原 bindings，禁止恢复时回退推导；读档前/调用 replay 前核对座位集合、非观战真人、唯一真人 controller、原席位契约。

### 中高：认证哈希覆盖未强制完整

`member_identity_bindings.valid_state:18-23` 强制每个 member 都有身份，却只遍历已经存在的 resume 字典条目；所有 identities 完整但 `resume_hashes:{}` 仍可通过加载。原玩家无法恢复，worker 等待可能永不结束。previous-only 同样被加载，但 `_join_identity:281` 要求 current 存在，previous 本身救不了该成员。要求所有需重连的成员有合法 current；previous 的键必须是 current 的子集。

### 中：非认证键规范性与哈希约束薄弱

非认证成员/绑定/哈希键只调用 is_valid_int；负座位 key 未禁止，整数别名也未统一拒绝，转 int 后可能覆盖同一成员/席位。认证 identities 会阻断非规范成员键，但 bindings 键仍不受这层保护。非认证 resume 哈希只须 String，甚至孤儿键也能读入。建议所有标识使用规范十进制串并在转换前验证范围/去重，所有哈希均遵守 sha256 形态，所有凭据引用已有成员。

### 中：selecting phase 保存但选人状态未保存/重建

文件没有 selection.rules 状态、controllers、选人分配/随机结果或进度；load 恢复 selecting，而 `configure_selection:1203-1209` 仅接受 lobby，worker:170 在 selecting/restoring 时调用会返回 false 且未检查返回值，连规则配置也不会建立；`_try_restore_match` 只处理 restoring。不能把 phase 字段存在称为 selecting 阶段完整恢复。应明确安全回到 lobby 重新开始选人，或持久化完整选人快照；禁止保留一个与空 selection authority 不一致的 selecting。

### 中：完整成员/设置字典复制会绕过公共视图字段白名单

常规成员字段不包含密钥，正常公开快照不会带私有恢复顶层字段。但 load 接受 name/spectator 之外任意成员字段，room.snapshot 深复制这些字段，`_publish:887-898` 原样广播；settings 也全量复制。若本机恢复档错误嵌入 `member_identities`、`token`、`public_key` 等成员/设置额外字段，会被广播。此项是损坏/误写恢复档导致的隐私防御缺口，**不是已经证实远端能修改文件或注入这些字段**。建议加载/输出使用公开字段白名单，拒绝敏感额外字段；不把正常路径“未泄露顶层字段”的测试等同于完整白名单安全。

### 中：settings 与兼容默认值的失败语义未显式版本化

loader 只专门解码 runtime_guard，不调用 `RoomState.decode_json_settings` / `_valid_settings`。人数配置、selection_mode 等损坏数据可读入后才在下游失效；JSON 整值 float 人数未规范化。缺 room_password、management_paused、data_revision 走默认/回退，是明确的旧档兼容，不能称所有缺字段都拒绝。建议加 schema_version；新 schema 强制字段，旧 schema 通过显式迁移，认证恢复仍保持先失败关闭。

## 已确认的安全边界

1. 公钥指纹映射、current/previous 哈希保存在私有顶层，不在常规 `_publish()` 的 room.snapshot 输出中；服务器未在上述落盘函数保存 token 原文或私钥。
2. `_join_identity:278-282` 先拒绝认证指纹不匹配，再验 current/previous hash；不能凭偷到的票据和另一获准密钥继承成员。
3. 网关 `_room_join_message:504-517` 覆盖客户端 gateway_identity，重查 can_access；不能在普通客户端字段里直接指定认证身份。
4. worker 在加载前设置本机 identity_required；旧认证档缺映射会在 `recovery_state_path` 建立前失败并保留原文件（`server_room_worker:159-164`；`load:1314-1317`）。
5. playing 恢复为 restoring；成员 ready/connected 不继承；读取整数允许合法 JSON int/float，但转换前验证有限、范围、整数性。
6. LAN/P2P worker 的现有恢复路径被显式阻断（worker:86-90、227-230），不能把 dedicated 认证恢复能力外推为 LAN/P2P 已完成。
7. 原存档先复制到本实例 restore 目录再恢复（worker:251-261）；恢复前对路径/链接/逐文件复制预算和哈希做校验。数据 schema 缺口不意味着这些文件保护不存在。

## 现有测试源码与应补的拒绝矩阵

已读取/定位但本次**全部未执行**：
- `tests/net_recovery_state_test.gd`：JSON 整值身份、data_revision 写读、暂停字段、playing→restoring、断线/ready 清空、非法浮点 owner/binding 原子拒绝。
- `tests/net_member_identity_binding_test.gd`：两密钥身份、私有落盘映射、公开快照不含顶层映射/哈希、缺映射认证旧档拒绝、非认证兼容。
- `tests/net_identity_security_regression_test.gd:74-86`：ACK 清 previous 后重载不复活；写失败回滚。
- `tests/identity_inheritance_test.gd`：继承重新绑定和撤销 previous、旧档显式审批、私有身份展示边界。

主代理建议补充运行用例：
- playing/restoring 的空、缺一项、负键、别名键 bindings；相同数量但换位绑定；真人绑定到观战/重复 controller。
- authenticated members 完整 identities 但缺 current hash、previous-only、previous 孤儿、非法 hash；断言读档失败且 recovery_state_path/原文件/内存不变。
- 新加入及重连轮换注入 open/flush/rename 失败，断言不下发可被客户端确认为成功的新票据，旧凭据/成员/路由/revision 完整回滚。
- selecting 文件恢复的明确策略；JSON 整值浮点 settings 和损坏设置。
- 重启丢弃旧 ACK、规则版本不匹配拒绝、旧版本 ACK 拒绝、存档清单重建后所有原真人重新确认。
- 复用 session 加载恢复档时清理旧屏障状态；成员/settings 敏感额外字段不能出现在公开视图。

## 本次验证记录

使用 Python 从实际 `_persist_recovery_state` 写入行提取顶层字段，并验证上述四个屏障字段不在写入 payload；读取 git status 确认共享工作树既有改动。本报告是源码审计和字段提取结果，**不是 GDScript parser、实际读写故障注入、网络双密钥或崩溃恢复验收**。没有启动 Godot，未新增运行夹具或修改生产文件。
