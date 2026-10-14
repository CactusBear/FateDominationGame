# Round 27 — D18 location / card ENet

## 结果

- location 真人界面、提示和战区点击消费 source 的 `kind/effect/areas/label/allow_cancel`；候选身份使用稳定 area ID，不从 raw spec 重新推可用地点。
- location 本地确认与取消走共同 `_submit_battle_command` attempt/result；同步结果后重新查询 source。取消是 `cancel_choice`，空候选不提交 null 地点、不自动取消。
- AI 独立保留 raw pending → driver 身份适配；观察者无声明不显示待答。
- 同声明保持取消闭包；变化声明或 adapter epoch 重绑，单调 UI 代际阻止 A→B→A 旧闭包复活。地点取消预置按钮在重绑前显式断旧连接。
- 网络地点仍由 NetworkChoicePanel 唯一发送；确认/取消回执按精确 seq 消费。声明重绘、普通刷新及无关拒绝不解锁原请求，不自动重发。
- card 新增独立真实 ENet 夹具，不用 active/player 网络通过作为 card 证明。修复 card 网络旧确认/取消闭包未绑定声明代际的问题。

## RED → GREEN

- location 旧实现：真实规则进入 location pending，source 有稳定候选，但 board 无 source location prompt；`location_choice_source_command` 首次有效 RED：5 checks / 1 failed，退出 1。
- card 旧实现：真实 ENet card declaration 改变后，保存的旧确认闭包仍发送；`card_choice_enet` RED：33 checks / 1 failed，退出 1。其它 card 真实权威分支当次已执行。
- GREEN：location 37 checks / 0 failed；card ENet 38 checks / 0 failed；退出均 0，无 SCRIPT ERROR。
- 夹具修正：候选变化必须排除当前实际候选，不能再次排除原已禁区域；魔力以发送前真实余额为基准；重置玩家同时清空测试地图席位，避免重复部署累积占用。这些只改新测试，不改共享规则。
- 开发中一次初始测试参数解析失败触发 180 秒超时，之后修正为动态调用并获得上述有效 RED；该次不计验收。

## 真实执行覆盖

card：实际 card pending 经 ENet 抵达原生面板；min=0/max=-1；空 card_choice 接受并只支付一次；mandatory_source 必选声明与自动勾选；缺必选、重复稳定 ID、旧 view_seq 权威拒绝；隐藏外人牌无 name/description、稳定 ID 在权威解析为真实牌对象；独立取消不支付；重复确认唯一发送；声明改变保原 seq 锁，真实关联拒绝后解锁；旧闭包/A-B-A 退休。

location：真实 source 声明、board 战区点击、无效 ID 拒绝、取消独立、禁止取消、空候选、observer 与 AI 分开；同声明保持/变化退休/adapter 退休；真实 ENet 唯一发送、候选重绘保锁、旧 seq 权威拒绝后人工重试、真实选中地点与一次效果费用。

## 同轮 headless 回归

所有下列套件退出 0，RESULT 无失败，最终日志无 SCRIPT ERROR：

| 套件 | checks |
|---|---:|
| location_choice_source_command | 37 |
| card_choice_enet | 38 |
| card_choice_source_command | 18 |
| active_choice_source_command | 65 |
| player_choice_source_command | 65 |
| battle_board_activation_command | 21 |
| battle_board_end_command | 38 |
| battle_command_adapter | 29 |
| net_locations | 7 |
| net_cancel | 12 |
| match_command_dispatcher | 313 |
| match_command_result_protocol | 39 |
| broadcast_board_source | 31 |
| broadcast_command_dispatch | 20 |
| broadcast_authority_enet | 51 |
| card_selection_mandatory | 39 |
| rule_guard_choice | 24 |
| regular_play | 54 |
| rule_guard_regular_group | 9 |
| rule_guard_regular_add | 18 |

命令模板：

`D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path E:/Projects/Godot/FateDominationGame-master --scene res://tests/<suite>_test.tscn`

每套 180 秒上限，串行进程；原始日志及 final-results.json：`C:/Users/Administrator/AppData/Local/hermes/cache/scratch/round27-D18-location-card/`。

## 文件范围

修改：`scripts/game_scene/battle_board_v2.gd`、`scripts/net/ui/network_choice_panel.gd`。

新增：`tests/card_choice_enet_test.gd/.tscn`、`tests/location_choice_source_command_test.gd/.tscn`、本报告。

Session、authority、source、query、dispatcher、既有测试保持只读；regular/active/player/card/broadcast/end/activation 回归保留。

## 边界及交接

- 按委托仅 headless，无窗口、截图、真人/多机/跨网验收；ENet 在同进程真实回环端点，使用既有测试模式建立 playing/controller，未覆盖完整认证恢复握手。
- 委托 renderer 路径 `scripts/net/ui/native_choice_renderer.gd` 不存在；真实共用 renderer 是 `scripts/game_scene/native_choice_renderer.gd`，未越权修改。
- 新测试被仓库 ignore 规则忽略：文件实际存在且真实运行，但 git status 不显示；整合者如需纳入版本必须显式处理，不在本轮擅自 git add/commit。
- `git diff --check` 对两生产文件退出 0。仓库已有大批未提交变更，整体 diff 非本轮独占变更统计。

最终脚本 SHA-256：

- board：`e49de05371084a1a5fcffa151c713ce0c86db538027d88921932d43fd375b83a`
- network panel：`a48412ca6c0738bbf4bf4222a42dfaa3e557137124cca3d1d020a77720c0aa2a`
- card ENet test：`21ade5e15a24c72fa630d0a839f7f65dd17a490bbeda32bf395b61b621e84c03`
- location test：`9bc6fe25acdf4236ac1c812c9bebfd4c30b691a1b30ea21b663ec7a61639dcee`
