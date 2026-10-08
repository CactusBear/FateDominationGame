# 4.7.2 API 与脚本分类迁移只读审计

## 范围与证据

- 项目：`E:/Projects/Godot/FateDominationGame-master`。扫描主项目、tests、scratch 与插件的 1050 个 `.gd`、394 个 `.tscn`、2 个 `.tres`、5 个项目配置；另扫描 Python、shell、C#、JSON、cfg 和 Markdown 的旧路径字符串。
- `.claude/worktrees` 是独立历史工作树，另行识别，不按主项目资源根解析；`.godot`、版本库与虚拟环境不作为源码。插件更新备份与 godot-cpp deps 有 `.gdignore`，重复类和加载引用风险统计剔除这些已隔离目录。
- 检查 1739 处明确 `load/preload/extends/ext_resource` 固定资源引用（排除动态占位符）。核对 autoload 和主场景均存在。
- 权威 API 已实际读取 Godot `4.7.2-stable` 源码文档：
  - https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/@GlobalScope.xml
  - https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/Object.xml
- 全程未启动 Godot，未执行项目测试或导入；本审计只能确认静态问题，不代表整个项目解析/运行通过。唯一写入文件为本报告。

## 结论与可修复项

### P0：测试仍有 bytes_to_var 第二参数

- `tests/net_transfer_boundaries_test.gd:127`：`bytes_to_var(source, false)`。
- 4.7.2 签名是 `bytes_to_var(bytes: PackedByteArray) -> Variant`，只接受一个参数；应改为 `bytes_to_var(source)`。
- 不应改为 `bytes_to_var_with_objects`：官方文档明确不可信对象反序列化可执行代码。`false` 的意图正是禁用 Object，单参数版本保留该安全语义。
- 正式 `scripts/net/transport/enet_transport.gd:104,114` 已使用单参数；catalog transfer 与 journal 也为单参数。此处是尚未同步的测试调用。

### 已修：p2p_invite 与 Object.is_connected 冲突

- 4.7.2 `Object.is_connected(signal: StringName, callable: Callable) -> bool` 是信号连接查询，不是网络 peer 状态。
- 当前 `scripts/net/p2p/p2p_invite.gd:165` 已命名为 `is_peer_connected(id: int)`，`:170` 内部调用和 `scripts/net/p2p/p2p_signal_client.gd:143` 消费方一致。
- 本次扫描未发现主项目/未隔离 scratch 的 `func is_connected(...)` 重定义；不应再次改动已修部分。
- UI 中 `button.pressed.is_connected(callback)` 等为合法 `Signal.is_connected`，与 Object 方法参数不同，不能机械全局替换。

### P0/P1：scratch 重复 class_name 尚未隔离

- 以磁盘上 `.gdignore` 为隔离边界，发现 4 组生产类与 scratch 副本重名；`scratch/.gdignore` 不存在。全量原始重复包括插件备份，剔除其 `.gdignore` 后不计为未隔离风险。
- 这些副本若参与主项目脚本扫描/导入，会争用全局脚本类；未运行 Godot，因此不声称已经复现实际缓存注册报错。

**MatchP2PInvite**
- `scripts/net/p2p/p2p_invite.gd:1`
- `scratch/authority-worker-v2/signaling-project/scripts/net/p2p_invite.gd:1`

**ServerGateway**
- `scripts/net/server/server_gateway.gd:1`
- `scratch/authority-worker-v2/server_gateway.merge_candidate.gd:1`

**ServerRoomManager**
- `scripts/net/server/server_room_manager.gd:1`
- `scratch/native-process-ownership-v6/overlay/scripts/net/server/server_room_manager.gd:1`
- `scratch/native-process-ownership-v6/baseline/scripts/net/server/server_room_manager.gd:1`

**MatchWebRTCLink**
- `scripts/net/transport/webrtc_link.gd:1`
- `scratch/authority-worker-v2/signaling-project/scripts/net/webrtc_link.gd:1`

建议修复顺序：先对历史 scratch 副本建立明确隔离（整个 scratch 忽略或逐归档子目录忽略，取决于哪些探针仍需要主项目导入）；需要继续加载的候选脚本去掉/改掉 `class_name`。`.gitignore` 不能代替 `.gdignore`。不能仅凭嵌套 `project.godot` 推断已从父项目隔离。

### P1：分类迁移漏掉历史 scratch 的旧 preload

- 确認 15 处旧路径，涉及 5 个 scratch 脚本。下表目标均在正式 `scripts` 内实际存在且 basename 唯一。

| 文件与行号 | 旧路径 | 建议新路径 |
|---|---|---|
| `scratch/authority-worker-v2/server_gateway.merge_candidate.gd:4` | `res://scripts/net/enet_transport.gd` | `res://scripts/net/transport/enet_transport.gd` |
| `scratch/authority-worker-v2/server_gateway.merge_candidate.gd:5` | `res://scripts/net/server_room_manager.gd` | `res://scripts/net/server/server_room_manager.gd` |
| `scratch/authority-worker-v2/server_gateway.merge_candidate.gd:16` | `res://scripts/net/player_registry.gd` | `res://scripts/net/identity/player_registry.gd` |
| `scratch/authority-worker-v2/server_gateway.merge_candidate.gd:185` | `res://scripts/net/member_identity_bindings.gd` | `res://scripts/net/identity/member_identity_bindings.gd` |
| `scratch/authority-worker-v2/server_gateway.merge_candidate.gd:201` | `res://scripts/net/enet_transport.gd` | `res://scripts/net/transport/enet_transport.gd` |
| `scratch/authority-worker-v2/server_gateway.merge_candidate.gd:294` | `res://scripts/net/player_name_rules.gd` | `res://scripts/net/identity/player_name_rules.gd` |
| `scratch/authority-worker-v2/server_gateway.merge_candidate.gd:319` | `res://scripts/net/player_identity.gd` | `res://scripts/net/identity/player_identity.gd` |
| `scratch/gateway-send-diagnostics-v2/gateway_send_diagnostics_test.gd:28` | `res://scripts/net/server_gateway.gd` | `res://scripts/net/server/server_gateway.gd` |
| `scratch/legacy-identity-migration/command_negative_cases.gd:6` | `res://scripts/net/legacy_identity_migration.gd` | `res://scripts/net/identity/legacy_identity_migration.gd` |
| `scratch/legacy-identity-migration/command_negative_cases.gd:7` | `res://scripts/net/server_console_channel.gd` | `res://scripts/net/server/server_console_channel.gd` |
| `scratch/public-view-privacy-v3/negative_cases.gd:5` | `res://scripts/net/server_gateway.gd` | `res://scripts/net/server/server_gateway.gd` |
| `scratch/rejected-correlation-merge/rejected_request_correlation_test.gd:4` | `res://scripts/net/group_selection.gd` | `res://scripts/net/ui/group_selection.gd` |
| `scratch/rejected-correlation-merge/rejected_request_correlation_test.gd:5` | `res://scripts/net/v2_view_presenter.gd` | `res://scripts/net/ui/v2_view_presenter.gd` |
| `scratch/rejected-correlation-merge/rejected_request_correlation_test.gd:6` | `res://scripts/net/lobby_session.gd` | `res://scripts/net/session/lobby_session.gd` |
| `scratch/rejected-correlation-merge/rejected_request_correlation_test.gd:7` | `res://scripts/net/network_choice_panel.gd` | `res://scripts/net/ui/network_choice_panel.gd` |

- 正式 scripts、assets 场景、主 project 配置未发现同类失效分类路径；额外源码/配置扫描的旧路径仅见历史材料，不作为运行依赖缺陷。
- `scratch/authority-worker-v2/signaling-project` 的 5 处引用按主项目根看似缺失，但按该嵌套项目自身根全部存在；不应盲改为主项目分类路径。它的同名 class_name 仍需处理父项目隔离。

### P2：历史 baseline 场景指向已缺失夹具

- `tests/_baseline_probe/baseline_runner.tscn:2` 引用 `res://reports/sentence-editor/fixtures/baseline_runner.gd`，目标不存在。
- 建议恢复对应 runner 或将历史探针显式归档/隔离；没有证据证明其他同名文件可安全替代，因此不提供猜测映射。

## 排除项与边界

- `tests/json_maker_ui_test.gd:545` 的 `JsonProbeOp.gd` 是测试临时创建并删除的文件（`:546–553`），不是迁移漏引用。
- runtime_reports 截图、日志、故意非法路径和动态 `%s` 模板不按缺失资源缺陷统计。
- 旧 Godot 3 API 模式扫描（yield、Pool*Array、File/Directory.new、.instance、str2var/var2str/to_json/parse_json、旧网络方法）未命中未隔离源码；这是模式覆盖，不是对所有 4.7.2 API 的完整类型/参数检查。
- 本地 godot-cpp `extension_api.json` header 为 4.4，不能用它充当 4.7.2 证据；关键签名结论使用实际读取的 4.7.2 官方 XML。
- 未做完整 GDScript 编译、NodePath/AnimationPlayer 轨道解析、UID 注册或运行链路验收。并发生产改动可能让本报告成为瞬时快照；正式实施前应再次核对所列行号。

## 交接建议

1. 修复测试的多余 `false` 参数；保留已修 `is_peer_connected`。
2. 先决定 scratch 导入隔离策略，再更新需要保留运行的 15 处旧路径与 baseline 夹具。
3. 主代理获得运行授权后，串行执行实际 Godot 导入/解析和受影响网络专项；本代理未运行这些命令。
