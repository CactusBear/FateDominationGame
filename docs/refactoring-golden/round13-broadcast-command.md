# Round13 — E07b 播报共享命令（RED / 核心接口交接）

## 结果

未放行 `confirm_broadcast`，未修改 dispatcher / LocalBattleCommands。当前 GameProgress 没有公共播报批次身份。仅有 pending、confirmers、confirmed 等查询，不能区分同一轮/阶段内的不同播报，也不能防止旧请求确认新屏障。不能把 round、phase、last_battle_result 内容或私有状态当批次 ID。

新增 `tests/broadcast_command_dispatch_test.gd/.tscn`，使用真实结算入口创建屏障、真实 dispatcher 验证无身份及自报 actor/seat 请求没有执行副作用，并用真实 MatchCommands 逐个确认两名活跃玩家。测试保留公共身份接口缺失的 RED；不是完整的旧批次防重放测试，后者必须等核心身份声明后补齐。

D1 保持真人自行确认；本模块不提供房主代确认、不自动确认真人，不新增 operation，不宣称网络/UI接线。

## 精确接口交接（提案，不是已有接口）

请 GameProgress 唯一写入者公布最终方法名、类型、生命周期契约。建议：

- `battle_broadcast_batch_id() -> String`：无 pending 返回空字符串；每次开启屏障创建新的非空不透明身份。不得因 reset/restart/恢复/检查点回退而与失效旧屏障复用。不能只是会回滚的自增整数。
- 身份与 pending、confirmed 必须同一状态切换；单次检查点回退如使旧确认失效，必须换代。恢复是否延续原身份须明确，且不得误接受恢复前已失效请求。
- RuleState / EffectCheckpoint 如何捕获及失效批次，交由核心写入者处理；不由 dispatcher 添加私有字段或窥探 serial。
- 未来 view 公共投影也必须带同一身份，由其独立写入者接线。

最终命令建议 `confirm_broadcast` 参数仅 `{batch_id: <核心声明类型>}`。严格拒绝额外字段（actor、seat、players 等）及类型不符；不把 String/int 强制转换当验证。可信 seat 来自调用方授权，不来自 args。

分派顺序应在 current_player_id 门之前：参数严格校验 → pending 为真 → 批次身份精确匹配 → seat 属于当前 confirmers → 尚未确认 → 只调用一次既有 `MatchCommands.confirm_battle_broadcast(seat)`。该既有入口返回 void，不能将 null 当失败；命令执行后记录一次 revision_delta。拒绝路径 revision_delta=0、无执行调用。人数和座位规则读取公共查询，不写死。

GREEN 还需真实回归：A 批次本人确认成功、同批重复拒绝、非 confirmer 拒绝、自报 actor/代确认拒绝；全部当前席位确认后释放；创建 B 批次后提交 A 身份，B 的 confirmed 不变；reset/恢复边界旧身份失效。LocalBattleCommands 继续固定可信 _seat，将同一参数原样交共享 dispatcher，不复制规则。

当前 RED 仅探测上述提案方法存在；最终接口名称若不同，按核心明确声明替换测试，不能机械加同名函数使测试绿。

## 真实执行

Godot 4.7.2，命令模板：

`D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . --scene res://tests/<name>.tscn`

- `broadcast_command_dispatch_test`：最终退出 1，RESULT checks=12，仅失败 `RED proposed public battle_broadcast_batch_id contract requires core handoff`。真实两席确认解除屏障成功。第一次夹具未声明活跃玩家，额外产生解除屏障失败，已修正夹具并重跑；不归因于核心。
- `match_command_dispatcher_test`：退出 0，RESULT checks=313 failures=[]，十二 kind 原契约回归通过，包含真实部署/移动。
- `match_commands_test`：退出 0，RESULT checks=17 failures=[]。
- 三套无 SCRIPT ERROR；未运行窗口/网络测试。

## 并行版本记录

上述测试执行前后 SHA-256 相同，未观察到运行期间核心变化：

- GameProgress：`b5b527a248c74c1db4623ec4340f0a10e63fa617846ddbbb81cf4e67f6222f80`
- EffectCheckpoint：`152fa171e4400a69b78469e9a17d647802b4c43e723ba3673b6034af8ba769c0`
- MatchCommandDispatcher：`7cb442532bb1c08684cef118b97bc0b19cf045a39de20fa44ee2e0fe3dce671d`

核心后续并行修改不自动继承此次结果。收到实际公共身份接口后必须重新读取文件、实现并补跑旧批次回归，方可宣称 E07b 模块完成。
