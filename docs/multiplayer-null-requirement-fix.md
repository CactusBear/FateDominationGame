# 前置查询空结果运行错误修复

## 根因

全量回归 battle_scroll_full_game_test 在 EffectManager._option_activation_requirements_met 出现 `Invalid call. Nonexistent 'bool' constructor`。随机整局不是每次复现，因此新增 requirement_null_test，使用真实 get_card_by_index_fr_arr 查询空数组产生 null：错误稳定重现，且证明中断后 effect._self_vars 与 activating_eff 未恢复。

## 修复

查询最终结果为 null 时判为不满足，继续原有失败处理和上下文恢复；BaseNumber、数字、布尔原语义不变。未修改卡牌 JSON、出牌或部署规则，未添加新 operation。临时 BOOL_PROBE 输出已移除。

## 验证

- requirement_null_test：修复前 2 项上下文恢复断言失败并报运行错误，修复后 3 checks 通过。
- net_cancel_test：12 checks 通过。
- net_full_game_test：4 checks 通过，完整指令对局到终局。
- battle_scroll_full_game_test：headless 13 checks 通过，无运行错误。
- 同一完整对局非 headless：15 checks 通过，无运行错误；日志位于 scratch/null-requirement-window.log，原生查看 scroll_full_game_end.png，显示第 11 回合对局结束。
- 专项原始结果在 multiplayer-null-requirement-results.json。

未宣称本轮已把所有既存全量失败修复，联机整体未完成范围不变。
