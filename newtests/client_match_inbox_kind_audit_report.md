# ClientMatchInbox 五 kind 实际接线契约核实

## 结论：已核实 / 仍缺

**已核实**：`match_bind / match_reset / match_view / selection / group_preview` 五种均已覆盖；普通客户端收到这五种包时，全部在 `lobby_session.gd:849–850` 经 `_match_inbox.receive(message)` 统一消费。该客户端分支没有这五种消息的内联形状判断；Session 不再读取/声明 `_mirror / _pending_view / _action_view / _match_bound`，也没有 `_match_inbox` 私有字段直读。来源、生命周期禁入仍在 Session，属于外层职责，不是 Inbox 形状校验残留。

**仍缺**：不是少 kind，而是外层信封 `kind` 非 String 的安全拒绝；`{"kind":17}`、`{"kind":["match_reset"]}` 在到达收件器以前，于 Session 第 774 行实际触发 SCRIPT ERROR。仅报 anchor+payload，未修改 Session。

## 冻结源码 SHA256

两次最终实跑前后均一致，最终复核工作树也相同：

| 文件 | SHA256 |
|---|---|
| `scripts/net/session/client_match_inbox.gd` | `cf9a54204cfc5f5b68ff17742deac4a60882b7b51d1a057a6e5d9d2c2aaf95c2` |
| `scripts/net/session/lobby_session.gd` | `ed2684bc83e7236912e08b801fd1fa2b2ff82c6b147760a91fc1fae19c099f0c` |

初次定位时 Session SHA 为 `f50835e933514b9a24e1571d86d4fbdfcdf6f0fa8d073dc163a2f4579d0a31ff`，准备测试期间其他并行写入者改变了一行；**本报告所有调用行号与最终测试只对应上表冻结 SHA**，不拼接初始版本的证据。本人对两生产文件只读。

## 五 kind 逐个对照

表内 Inbox 行号来自 `client_match_inbox.gd`，Session 行号来自上表最终 SHA。

| kind | Inbox 分支/形状门 | Session 客户端接收点 | Session 生产发送点 | 输出与判断 |
|---|---|---|---|---|
| `match_bind` | 19–21：`observer is int` 且未绑定；调用公开 `bind_local` | 849–850 | 1121（加入进行中对局）、2118（常规绑定） | 无 changed；重复 bind 不更换观察者；无内联形状校验/私有读取 |
| `match_reset` | 22–25：无必需 payload 字段；`reset`→`selection_reset`→`changed` | 849–850 | 956（回大厅）、1104（完成对局回大厅） | 每包一次 changed，清镜像/待答/动作/选择；无内联形状校验/私有读取 |
| `match_view` | 26–29：已绑定；state/pending/actions 均 Dictionary；复用 Mirror 验 pending、state | 849–850 | 2132 | 成功后发布 pending/actions、一次 changed；非法包无部分提交；无内联形状校验/私有读取 |
| `selection` | 30–33：state Dictionary；深拷贝发 selection_received，再 changed | 849–850 | 2036 | Session 196–197 保存公开 selection_view；无内联形状校验/私有读取 |
| `group_preview` | 16–18：request_id int、result Dictionary；深拷贝发信号 | 849–850 | 1028（远端预览） | Session 193–194 原样转发；不发 changed；无内联形状校验/私有读取 |

外层调用与守卫：

- 764：`_receive` 入口；765：请求重置禁入；766：restore/begin 禁入。
- 787：普通客户端分支；788–789：只接受 sender=1。
- 90：创建 Inbox；182–185：changed/preview/selection/reset 四信号连接；186：公开 transport.message_received 连接 Session 接收入口。
- 190–200：四信号适配；191 changed、194 preview、197 selection_view 赋值、200 selection_view.clear。
- 294：公开 reconnect 链接到 Inbox 的局部 reconnect_reset；665：close 链完整 reset；2040：_clear_match_views 完整 reset。
- 2044/2048/2081：read_match/read_pending/read_actions 调公开 Inbox getter；资源映射仍由 Session 处理。
- 2115：房主本地 bind_local；2124：房主本地 accept_local_state；2127：房主本地 publish_local_details。

**边界说明**：房主本地预览在 1026 直接 emit；房主本地选择在 2033 直接赋值；房主本地镜像走上述公开本地入口而不是 receive。这些是生产者/本地发布，不是客户端消息漏走 Inbox。上述零私有残留结论仅针对 Inbox 四个迁出状态；并不宣称 Session 里所有其他对象的私有访问均已消除。

## 真实 Godot 契约测试

新增 `newtests/client_match_inbox_kind_audit.gd`、`.tscn`、`run_client_match_inbox_kind_audit.py`。无生产修改。

两层均使用真实 GDScript：

1. 直接实例化真实 Inbox，通过公开 receive 与信号验证；
2. 实例化真实 Session，经其公开 `transport.message_received.emit(sender,payload)` 进入已登记生产入口，读公开投影和公开信号；不调用 Session 私有函数、不读取其私有字段。

合法组覆盖：五 kind 识别/发布、一次合法包一次对应发布、bind 重复不重绑、深拷贝、reset 撤销绑定。这里的“唯一触发”指**每个输入包只触发一次对应发布**，不偷换成 request_id 去重；现有预览重放没有幂等协议。

非法组覆盖：bind observer 缺失/String/float/bool；preview request_id String/float、result Array/缺失；selection state Array/String/缺失；view state/pending/actions 错类型或缺失，非法 pending、观察者不匹配、旧 seq。识别但无效消息 direct receive 仍返回 true，不发布、不部分提交。五 kind 非房主来源全部拒绝。直接 Inbox 对非 String kind 返回 false；Session 的两个非 String kind 缺口另跑留证。

能力拒绝：通过真实 `MatchAuthority.preview_group(1,0,[],[])` 取得未绑定能力拒绝 `{"ok":false}`，经 Inbox 和 Session 的 group_preview 各验证一次原样输出；另验证 actions 中 `guard.can_continue=false`、`guard.paused=true`、`management_paused=true` 等声明不被过滤/升级。Inbox 没有能力判定回调，不宣称测试了真实对局规则禁令的生成链。

`match_reset` 的契约只有 kind，本来没有需检验的 payload 类型；不能把额外字段错类型人为定义为无效 reset。外层 kind 错类型及错误来源已分别留证。

### 实际命令

仓库根执行：

```bash
python -B newtests/run_client_match_inbox_kind_audit.py
python -B newtests/run_client_match_inbox_kind_audit.py --envelope-defect
```

各自 E 盘冻结工程 cwd 内启动的真实命令：

```bash
'D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --fixed-fps 60 --path . --scene res://tests/client_match_inbox_kind_audit.tscn
```

测试场景从 newtests 原样复制至**隔离工程** tests/，原仓库 tests/ 未写。冻结保留真实 scripts、正式 JSON、必要 preload/import 资源及全局类缓存；只移除开发 MCP autoload、禁用开发编辑插件。APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR 显式位于本轮 E 盘独占目录，Godot 实际 AUDIT_USER_DIR 已核实位于同根。360s 看门狗，无测速/全量/窗口/进程名清理；17120、28100 未操作。Job0 指本轮 Windows Job 活动子进程为零，不是全机 Godot 数量。

### CHECK / exit / ERROR / Job0

| 实跑 | CHECK true/false | RESULT failures | Godot exit / Python exit | ERROR | Job0 | 结论 |
|---|---|---|---|---|---|---|
| 最终五 kind 核心契约 | 116 / 0 | [] | 0 / 0 | 0 | true，active_owned_processes=0 | PASS |
| 外层坏信封缺陷复现 | 118 / 0 | [] | 0 / 1 | 2 个 SCRIPT ERROR | true，active_owned_processes=0 | FAIL，不能因 RESULT/exit=0 当通过 |
| 初跑（修正夹具前） | 118 / 0 | [] | 0 / 1 | 2 个漏角色目录 ERROR + 上述 2 个 SCRIPT ERROR | true | FAIL；漏带 JSON 为夹具问题，已补齐并复跑 |

最终核心 PID 27368；缺陷复现 PID 3948。所有日志与完整哈希/命令/环境/Job 回执已归档：

- `newtests/client_inbox_kind_audit_evidence/core.receipt.json`、`core.stdout.log`、`core.stderr.log`
- `newtests/client_inbox_kind_audit_evidence/envelope_defect.receipt.json`、`envelope_defect.stdout.log`、`envelope_defect.stderr.log`
- `newtests/client_inbox_kind_audit_evidence/initial.receipt.json`、`initial.stdout.log`、`initial.stderr.log`

## 仍缺：精确 anchor + payload

文件 `scripts/net/session/lobby_session.gd:774`，函数 `_receive(sender:int,message:Dictionary)`：

```gdscript
if message.get("kind") == "catalog_part" or (_host and message.get("kind") == "server_data_catalog_part"):
```

通过公开生产 transport 信号、sender=1，各注入：

```json
{"kind":17}
{"kind":["match_reset"]}
```

分别实际返回引擎诊断：

```text
SCRIPT ERROR: Invalid operands 'int' and 'String' in operator '=='.
SCRIPT ERROR: Invalid operands 'Array' and 'String' in operator '=='.
at: MatchLobbySession._receive (res://scripts/net/session/lobby_session.gd:774)
```

直接 Inbox 对相同信封可返回 false；但 Session 在 774 先异常，尚未到 788 的来源门或 849 收件器。Transport 静态 `enet_transport.gd:123–140` 只验 Dictionary/基础类型，不要求 kind 为 String；本专项没有真实 ENet 编解码，因此线上可达性的动态验证仍为 **unknown**，不冒称已完成 wire 验收。

## 验收边界

- 五 kind 没有缺分支、没有客户端内联形状检查或四状态私有直读残留。
- 非 String 外层信封仍缺安全拒绝，已真实复现，未修。
- selection/result/actions 内嵌内容仍遵守现有宽松 Dictionary 契约，没有偷偷增加业务 schema 或去重政策。
- 未跑窗口、真实 ENet 编解码、恢复/重连全链、房主开局全链或全量；这些不在本轮已核实范围。
