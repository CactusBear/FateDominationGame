# Round16 — E07b / E07 权威播报确认与严格视图

## 已完成与范围

- 共享 dispatcher 新增 `confirm_broadcast`，参数精确为 `{batch_id: int}`，拒绝 String、float、bool、缺字段、actor/seat/players 等额外字段。可信本人 seat 只来自权威认证映射或 LocalBattleCommands 固定绑定。
- 在 current_player 门之前调用公开 `GameProgress.can_confirm_battle_broadcast(seat, batch_id)`，同步校验并调用既有 `MatchCommands.confirm_battle_broadcast(seat)`；该命令返回 void，不能把 null 当失败。接纳只执行一次、revision_delta=1；旧批次、重复、非 confirmer 拒绝不执行且 revision_delta=0。外层权威继续执行 seq/revision/observer/guard/audit 闸。
- 使用已实际落盘的核心接口 `battle_broadcast_batch_id() -> int`、`battle_broadcast_confirmed() -> Array`，不读取私有 serial、不以回合/阶段替代批次、不改 GameProgress/MatchCommands/检查点核心。
- view 增加 `battle_broadcast: {pending: bool, batch_id: int, confirmers: Array[int], confirmed: Array[int]}`。mirror 必须收到全部四个字段，拒绝额外字段、非整数/重复/未知 confirmer、非 confirmer 的 confirmed、重复 confirmed、pending 与批次不一致。pending 时批次 >0；非 pending 时批次=0 且 confirmed 为空。确认列表只是公开席位，不包含消费者、peer/member、私有对象或隐藏卡数据；返回副本不会反向修改规则。
- 权威每 0.28 秒最多确认一个 `controllers` 明确声明为整数 0 的 AI；真人、未知控制声明不自动确认。本地适配显式声明 AI 列表后复用同一 dispatcher。
- E04 水位已改为实际公开 `EffectManager.latest_allocated_message_serial()`，删除 `_message_serial._next_serial` 跨私有读取。未发=-1、耗尽=MAX_INT64、已经 pop 的旧消息仍被 cutoff 覆盖；通知 builder 过滤逻辑与生命周期保留。
- D20d `finish_match_to_lobby` 保留，专项通过。没有修改 session、board、GameProgress、MatchCommands、EffectManager。

本轮只拥有五个适配/视图文件与播报专项。工作树原有其他重构修改保留；git diff 中历史座位查询、通知投影、D20d 等不能全归为本轮新增。未找到上下文所指 `round13-broadcast-core` 文件；已读取 round13-broadcast-command 和方案 E07–E07d，并以当前实际核心公开代码为准。

## 生产调用方精确交接（已实现接口）

### 权威开局/恢复

```gdscript
var authority = NetworkMatchAuthority.new()
# 由 session/worker/UI 所有者按该次调用实际具备的确认消费能力声明；没有能力保持默认 false。
assert(authority.declare_broadcast_confirmation(true))
assert(authority.start(selection))
# 或同样先声明，再调用 restore_archive；不能启动后临时换声明。
```

`declare_broadcast_confirmation(enabled: bool) -> bool` 仅在 `started == false` 接受。默认 false，不能因为全 AI、headless、录制器存在或窗口存在就隐式 true。启动/重开/恢复后显式应用声明；录制状态复用核心已有 `set_broadcast_enabled` 并复核审计，失败不报告启动成功。调用者仍须只在真实业务能力可用时传 true；这是能力声明入口，不是自动检测能力。

权威按 selection/recovery 的 controllers 接管 AI，不接管真人。旧 controllers 中真人断线仍是正 member ID，不会因为不在线而变成 0。

### 本地开局

```gdscript
# 在 GameStart 的 reset 完成后、第一次规则结算前显式声明，不能依赖构造适配器产生规则副作用。
assert(local_commands.declare_broadcast_confirmation(true, declared_ai_seats))
# 调用方逐帧明确驱动，复用单机 0.28 秒节拍。
local_commands.tick_broadcast_confirmation(delta)
# 真人按当前只读 view 的批次提交，不能自行指定 seat。
local_commands.submit("confirm_broadcast", {"batch_id": view.battle_broadcast.batch_id})
```

本地 `declare_broadcast_confirmation(enabled: bool, ai_seats: Array = []) -> bool` 拒绝屏障正在 pending 时改策略、非整数/负值/重复 AI 和绑定真人本人。新局 reset 后需重新声明/建立适配器；不自动把当前玩家视为 AI。

session、worker、board 文件不属于本写入者，本轮未擅自接线；主代理应将上面的实际接口交给对应所有者。本轮不宣称 E07e 窗口交付。

## E07d 精确剩余接口（提案，未实现，当前命令拒绝）

不能把 `broadcast_confirm_absent` 塞进本人 dispatcher，也不能接收客户端自报房主或断线席位作为授权。现有代码中不存在可绕过 session 的代确认入口；专项证明该 kind 被拒绝且 confirmed 不变。

session 所有者须先完成：实际 transport 来源 → 认证稳定 member → 当前在线房主 → 对局阶段/生命周期 → 最近签发 view → 当前断线真人席位集合。只能对属于当前 confirmers、当前尚未确认、controllers 声明为真人且当前 session 确认离线的席位执行。不得自动代确认，必须房主显式发出。

建议下一轮由 session 与 authority 所有者共同定义一个管理入口（以下签名是提案，不能调用）：

`confirm_absent_broadcast(actor_member: int, view_seq: int, batch_id: int, authorized_absent_seats: Array) -> Dictionary {ok: bool, code: String, reason: String}`。

- session 先从实际认证连接解析 actor，验证房主资格、在线状态和严格报文类型，计算/交叉核对断线集合，不信客户端的 seat/actor 授权。
- authority 复核 started、seq/revision/observer、guard/archive/audit、当前 batch，以及全部席位 pending/未确认资格；先整批验证后同步执行，拒绝时不部分代确认。
- 每席仍调用既有确认命令并录制；额外写管理事实 `{actor: 房主对应规则席位, member: 已认证成员, seats: [...], batch_id, view_seq}`，不含密钥/恢复票据。审计失败不能回业务成功。
- session 在消费结果与发布 view 前复核生命周期及当前授权，防止旧房主、旧断线集合、复连后或旧批次请求继续代确认。
- 下一轮验收必须包括真实断线维持等待、非房主拒绝、复连后不得代确认、旧房主/旧批次拒绝、房主显式处置留审计。当前仅有拒绝绕权 kind 与真人不自动确认覆盖，不冒称完整断线授权验收。

## 真实 RED / GREEN

固定命令（Godot 4.7.2）：

`D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . --scene res://tests/<name>_test.tscn`

每个子进程 timeout=180 秒，无窗口。日志：`reports/refactoring/round16-broadcast-authority/`。

- dispatcher 接线前的实际 RED：broadcast_command_dispatch，退出 1，checks=20，失败本人同步确认、另一真人仍需确认、重复无副作用、旧批次隔离、两真人解除共五项。未记录为所有网络场景都跑过 RED。
- 同一专项 GREEN：退出 0，checks=20，failures=[]。
- broadcast_authority：退出 0，checks=70；真实规则结算、两本人认证映射确认、重复/未知席位/旧批次、1 真人多 AI、0.28 节奏、默认全 AI/headless 不启用、真实选人/start 能力声明、严格视图/副本、本地能力与真人确认。
- broadcast_authority_enet：退出 0，checks=51；真实 ENet listener 与三客户端，actual get_packet_peer 提供来源，两真人各自报文成功、第三未绑定连接拒绝、float/伪装 seat/重复/旧批次拒绝、混合 AI 后真人报文解除。确认直接进入真实 authority/MatchCommands/规则，不用合成业务结果。测试用预绑定 controllers，不含完整密钥身份握手；回执为专项自己的 ENet 测试协议，不声称生产 session result wire 协议已接线。

最终批次回归（结果文件 results.json）：

| 专项 | 退出码 | checks | failures / SCRIPT ERROR |
|---|---:|---:|---|
| broadcast_authority | 0 | 70 | [] / 无 |
| broadcast_authority_enet | 0 | 51 | [] / 无 |
| broadcast_command_dispatch | 0 | 20 | [] / 无 |
| match_command_dispatcher | 0 | 313 | [] / 无 |
| match_commands | 0 | 17 | [] / 无 |
| match_view | 0 | 226 | [] / 无 |
| match_view_privacy | 0 | 137 | [] / 无 |
| match_finished_authority | 0 | 29 | [] / 无 |
| notification_projection | 0 | 43 | [] / 无 |
| notification_reconnect_baseline | 0 | 22 | [] / 无；包括已 pop 消息边界 |
| net_match_archive | 0 | 20 | [] / 无 |
| match_replay | 1 | 10 | 6 项失败；存档引擎版本不一致，无 SCRIPT ERROR |

match_replay 重试仍退出 1，同样先被引擎版本闸拒绝；已在执行前后真实 SHA-256 扫描 scripts，重试期间发生变化的是 `scripts/net/server/server_gateway.gd`、`scripts/game_scene/battle_board_v2.gd`。该拒绝符合指纹校验，不能修改版本闸或伪称完整 replay 通过；需主代理等其他写入者停止修改后重跑。证据：match_replay_retry.log / match_replay_retry.json。

作用域内 git diff --check 退出 0。全仓库检查退出 2，仅可见多处其他文件 CRLF 警告；没有以它替代作用域核验。未执行窗口、完整身份握手、多机/跨网或 E07d 真实断线房主管理。

## 文件清单

修改：
- scripts/match/match_command_dispatcher.gd
- scripts/net/authority/match_authority.gd
- scripts/match/view_builder.gd
- scripts/match/view_mirror.gd
- scripts/game_scene/battle_io/local_battle_commands.gd
- tests/broadcast_command_dispatch_test.gd

新增：
- tests/broadcast_authority_test.gd/.tscn
- tests/broadcast_authority_enet_test.gd/.tscn
- 本报告与 reports/refactoring/round16-broadcast-authority/*.log、results.json、match_replay_retry.json
