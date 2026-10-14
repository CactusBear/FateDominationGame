# Round 25 — D18 card declaration / D15 local reply

## 已实现

- `battle_board_v2.gd` 的真人 `card_choice` 只消费 `_source.read_pending()` 声明；raw pending 仅保留给显式 AI driver。
- card candidate、required、选择保留和重复判定统一按稳定整数 ID，不按完整字典相等；声明字段来自 `card_views/required/min/max/secret/verb/confirm_text`。
- 本地 card_choice 复用共同 `_submit_battle_command` attempt/result/adapter epoch；合法空集走 `card_choice`，取消走独立 `cancel_choice`。
- min=0、max=-1、必选、声明变化、同声明刷新与旧闭包/旧 adapter 生命周期隔离已覆盖；拒绝不重放、不重新塞 raw 对象。
- regular 出牌仍保留 `regular` 分支，未迁移到 card_choice；完整卡面继续复用 `native_choice_renderer.choice_card` 与现有 `_render_card_face`，隐藏视图没有本地模板兜底。
- `network_choice_panel.gd` 对 card view 采用稳定 ID 声明比较，card attempt 也等待真实 result；普通刷新/候选视图变化不清理 seq 锁，成功按精确声明关闭面板。

## 新增

- `tests/card_choice_source_command_test.gd`
- `tests/card_choice_source_command_test.tscn`

专项包含真实本地 source、声明字段、stable ID、min=0/max=-1、合法空集、费用不变、独立取消、adapter 退休旧闭包。

## 验证

- `card_choice_source_command_test`: 18 checks, 0 failures。
- `active_choice_source_command_test`: 65 checks, 0 failures；包含真实 ENet RED/GREEN。
- `player_choice_source_command_test`: 65 checks, 0 failures；包含真实 ENet 与生命周期。
- `battle_board_activation_command_test`: 21 checks, 0 failures。

Godot 4.7.2 headless 运行全部退出码 0。尚未新增独立 card ENet fixture；现有 active/player ENet 与本地 card 专项通过，card 网络路径沿同一 NetworkChoicePanel/NetworkBattleCommands 回执链。
