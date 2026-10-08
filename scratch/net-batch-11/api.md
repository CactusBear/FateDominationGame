# 第二轮静态兼容性扫描

## 结论

- `bytes_to_var`：全项目实际调用 16 处（生产 5、测试 11），均为单参数；未发现旧第二布尔参数或 `bytes_to_var_with_objects` 调用。
- `Object.is_connected`：未发现自定义同名方法或零参数 `.is_connected()` 残留；网络状态入口已改为 `is_connected_to_host()`。现有信号 `Signal.is_connected(callable)` 不应批量改名；插件中的 `Object.is_connected(signal_name, callable)` 是合法两参数调用。
- 排除隐藏目录及 `.gdignore` 子树后，重复 `class_name` 为 **0**。物理文件重复类名 182 组，不等于编辑器冲突。
- `.obj` 共 66 个，全部位于 `scratch/`，已有 `scratch/.gdignore` 覆盖；原生插件 `addons/fate_server_signals/src/.gdignore` 也已存在。
- 网络生产脚本、正式场景和 GDScript 测试的旧 `scripts/net/*.gd` 路径已清理；**3 个 Python 审计文件仍有 8 处失效旧引用**。另外有 8 处历史进度文档旧路径。
- 额外发现一个非网络迁移的坏场景依赖：`tests/_baseline_probe/baseline_runner.tscn:2` 指向不存在的 `res://reports/sentence-editor/fixtures/baseline_runner.gd`。

本轮只生成审计交接文件，未改生产文件，未运行任何 Godot 命令、导入、导出、编辑器 MCP 或游戏测试。

## 扫描范围与版本证据

仓库：`E:/Projects/Godot/FateDominationGame-master`；通过 Git 根路径核实。递归扫描包括未跟踪文件、隐藏工作树及 scratch，排除 `.git`、`.godot` 缓存。原始结果见同目录 `api-scan.json`。该 JSON 的 `ignored` 仅表示 `.gdignore` 祖先覆盖，不代表隐藏目录；`gdignore_only_duplicates_not_accounting_for_hidden_dirs` 明确是中间结果，不能作为有效重复类名结论。

Godot 4.7 API 基线遵循仓库任务技能：`bytes_to_var(bytes)`，对象允许反序列化是独立函数而不是第二参数。实际能读取的本地 `scratch/native-process-ownership-v6/deps/godot-cpp-714c9e2c165db2dcb7e6ea57e62a04204d3cfbfa/gdextension/extension_api.json` 自报 **Godot 4.4.stable.official**，其单参数 `bytes_to_var` 和两参数 `Object.is_connected` 与基线一致，但不能冒充 4.7 生成的 API dump。`D:/Godot4` 和插件目录未发现 API JSON；严格的 4.7 引擎解析验证留给主代理，本轮遵守禁止运行 Godot。

## 全项目 GDScript 分类

物理 `.gd` 文件 1325 个；类别互斥，先排隐藏目录，再排 `.gdignore` 子树：

| 类别 | 数量 | 含义 |
|---|---:|---|
| scripts | 366 | 生产与系统脚本 |
| tests | 370 | 测试及探针源码，仍处于项目可扫描目录 |
| json_maker | 4 | 编辑器工具 |
| addons（非隐藏且未忽略） | 145 | 可扫描插件源码 |
| .gdignore 覆盖的非隐藏脚本 | 22 | scratch 候选、夹具和依赖测试 |
| 隐藏目录脚本 | 418 | `.claude` 工作树 275 + 插件更新备份 143 |

生产 `scripts/net` 共 54 个脚本：authority 2、content 7、identity 8、p2p 3、server 14、session 3、transport 5、ui 6、validation 6。`ui` 数量包含 `ui/legacy/`。目录职责见 `docs/net-script-layout.md`。

### bytes_to_var 调用位置

生产：

- `scripts/match/match_journal.gd:525`
- `scripts/net/transport/catalog_message_transfer.gd:42,50`
- `scripts/net/transport/enet_transport.gd:104,114`

测试：

- `tests/net_packet_fragments_test.gd:11,15,17,18,19,21,27,30,31,36`
- `tests/net_transfer_boundaries_test.gd:127`

以上逐条检查均为单实参，邻接的 `receiver.accept` 等外层逗号不能误认为 `bytes_to_var` 参数。此结论只验证调用签名，不证明消息格式、权限或恶意载荷处理正确。

### Object.is_connected 与类名

- 状态辅助方法定义：`scripts/net/transport/enet_transport.gd:160`，名称 `is_connected_to_host`。
- 合法原生对象调用：`addons/godot_ai/handlers/signal_handler.gd:157,180`、`addons/godot_ai/debugger/mcp_debugger_plugin.gd:438`，均是两参数。
- 182 组物理重复来自隐藏 `.claude/worktrees/...`、隐藏且忽略的 `addons/.godot_ai_update/backup/...`。隐藏目录不能当成编辑器有效脚本树。
- `scratch/authority-worker-v2/server_gateway.merge_candidate.gd` 等候选已被 scratch 根 `.gdignore` 隔离。导出 `exclude_filter` 本身不能代替编辑器扫描隔离；以后新增候选仍需保留 `.gdignore`。

### .obj / .gdignore

66 个 `.obj` 全被 `scratch/.gdignore` 祖先覆盖，无未隔离 `.obj`。项目内 `.gdignore` 共 10 个：scratch 根、scratch 的 godot-cpp 依赖根、6 个 docs 概念稿目录、插件更新目录、原生插件 src 目录。Windows/Linux 导出预设的 `exclude_filter` 都含 `scratch/*`（`export_presets.cfg:15,86`），作为导出层补充而非编辑器隔离证据。不建议把整个 `addons/fate_server_signals` 忽略，否则可能遮蔽正式扩展资源；只隔离其构建源码子树。

## 尚未迁移的旧引用（静态确认未修）

### 会阻断 Python 审计的 8 处

| 文件:行 | 旧路径 | 已存在的新路径 |
|---|---|---|
| `tests/server_signal_fixture_static_test.py:93` | `scripts/net/server_cli.gd` | `scripts/net/server/server_cli.gd` |
| `tests/server_signal_acceptance_v3/test_orchestrator.py:38` | `scripts/net/server_cli.gd` | `scripts/net/server/server_cli.gd` |
| `tests/p2p_acceptance_audit_v3/audit.py:17` | `scripts/net/p2p_signal_client.gd` | `scripts/net/p2p/p2p_signal_client.gd` |
| 同上:18 | `scripts/net/p2p_signal_server.gd` | `scripts/net/p2p/p2p_signal_server.gd` |
| 同上:19 | `scripts/net/p2p_invite.gd` | `scripts/net/p2p/p2p_invite.gd` |
| 同上:20 | `scripts/net/webrtc_link.gd` | `scripts/net/transport/webrtc_link.gd` |
| 同上:21 | `scripts/net/lobby_session.gd` | `scripts/net/session/lobby_session.gd` |
| 同上:24 | `scripts/net/server_gateway.gd` | `scripts/net/server/server_gateway.gd` |

已通过只读 Python 对旧 `scripts/net/server_cli.gd` 执行 `read_text()`，实际返回 `FileNotFoundError`；未运行完整审计套件，避免其中可能启动 Godot 的流程。新路径均在磁盘唯一存在。

### 历史文档的 8 处

- `docs/multiplayer-guard-progress.md:5`：rule_loop_analysis → validation/rule_loop_analysis。
- `docs/multiplayer-match-integration-progress.md:5`：match_authority → authority/match_authority。
- `docs/multiplayer-network-core-progress.md:5-10`：enet_transport → transport；room_state/lobby_session → session；lobby_screen → ui；data_catalog/content_cache → content。

是否更新历史快照由主代理决定；若保留，应标明迁移前路径，不能当作当前文件入口。

### scratch 与其他缺失引用

原始旧路径命中 473 条：scratch 457、tests 8、docs 8。scratch 多为基线、merge 候选、历史输出或独立 signaling 子项目，不建议机械全量替换；修改基线会破坏审计溯源。`.gdignore` 不会自动修复 Python 读取路径或直接装载夹具。

原始 `res://...gd/.tscn/.tres` 缺失候选 86 条含隐藏工作树、模板 `%s`、注释、临时生成脚本及示例，不宜直接报 86 个缺陷。明确可复核的非网络问题是上文 baseline 场景缺失 ext_resource。`tests/json_maker_ui_test.gd:545` 的 `JsonProbeOp.gd` 在紧接的 546-548 行动态创建、553 行删除，不是静态缺失缺陷。

## 主代理收口建议

1. 更新上表 3 个 Python 审计文件的 8 处路径，然后只读检查所有新目标存在。
2. 对历史 docs 标注或迁移路径；不要全量改 scratch 基线。
3. 保留现有两处关键 `.gdignore`（scratch 根、插件 src）；不要把物理隐藏工作树重复误报成全局类冲突。
4. baseline 探针如继续保留，单独修复其缺失脚本依赖；不属于本次网络目录迁移。
5. 本报告不代表 Godot 4.7 解析、运行或导出验收通过。
