# 正式 v2 私有待答接线

## 已实现并验证

- `battle_board_v2.tscn` 声明 `NetworkChoices/Panel`，复用现有网络选择面板，独立 CanvasLayer，单机默认隐藏。
- `v2_view_presenter.gd` 在网络初始化时绑定当前会话。不查询本地规则，不改变主机权威协议。
- 既有对手窗口测试增加面板工厂入口。新 `net_v2_choice_window_test` 复用同一真实 ENet 测试流程，将面板换为正式 v2 中的实例。
- 新测试先因正式场景缺入口而失败，接线后非 headless 实际鼠标确认通过，13 checks、exit 0、无 ERROR。验证私有询问只给目标、接受询问、主机更新关闭面板、分支次数和数量到达主机。
- 新旧专项使用独立截图前缀，避免相互覆盖。正式 v2 证据为 `tests/runtime_reports/net_v2_opponent_choice.png` 和 `tests/runtime_reports/net_v2_opponent_options.png`；已原生查看后者。分离路径后再次运行新窗口专项，13 checks、exit 0、无 ERROR。
- 兼容专项：`net_v2_view_test` 15 checks、`net_opponent_window_test` 11 checks、`match_driver_v2_test` 20 checks；均 exit 0、无 ERROR。

## 前批回归核对

- 批次 `network-v2-integration-regression/summary.json` 有 39 套，汇总退出非零，不能宣称全绿。
- `net_transport_test` 11 checks 全通过。其 ENet host 创建失败是同端口占用反例预期产生的日志，汇总器仍计为 ERROR；未通过忽略所有 ERROR 来掩盖其他问题。
- `match_replay_test` 在 180 秒批次预算内超时。独立原始 `restore_only user://p1-replay-test-1209650` 恢复成功，到达存档终局，2 checks、exit 0。
- 探针证明前 53 条重放状态哈希与原存档一致；第 54 条也正常完成，不能称其死循环。整个录制加重复恢复套件本批仍未完成，耗时根因未最终确认。
- 临时诊断仅修改测试，已全部移除，没有对规则引擎做猜测性修复。

## 未完成边界

- 正式 v2 网络手持卡、战区交互和完整操作表现尚未接齐，不能称正式客户端已能玩完一局。
- 该专项用同一进程内两份真实 ENet 会话验证 UI 到主机链路，不等同于两个正式独立客户端或异地网络验收。
- 服务端、P2P、数据开局屏障、完整存档菜单和死循环保护仍沿总计划待办。
