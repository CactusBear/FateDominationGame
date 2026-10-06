# 跨进程验证与成员权限撤销

## 实现与验证

- LobbySession 在所有非 join 请求进入业务前检查成员仍存在且 connected 为真，防止移除成员到物理断线之间仍使用旧座位权限。
- net_pending_test 增加真实 ENet 移除成员反例，15 checks 通过。测试显式登记 remote，防止人工构建的 authority 沿用单机默认 AI 自动答复。
- 新增 net_process_test：由外部测试脚本启动两个独立 Godot 进程。主机先实际监听成功再启动客机，经过入房、双方准备、唯一御主选择、随机从者分配和主机开局，客机收到自己的过滤视图。
- 客机检查 GameStart._started 为 false；主机为 true，证明本次开局没有在客机执行本地游戏引擎。
- 在主机进程创建给客机座位的选择，客机仅根据网络私有提示提交放弃，主机结算并通过视图更新确认结束。两端各 8 checks 通过，无 SCRIPT ERROR 或 ERROR 日志。
- 原始输出见 multiplayer-cross-process-results.json 与 multiplayer-cross-process-choice-results.json。

## 不夸大覆盖

- 这是本机两个真实独立进程，不是两台设备或公网测试。
- 私有选择为验收夹具，主机明确排入；不是宣称任意正式卡牌的完整网络对局都已通过。
- 正式 v2 客机接线、完整房间 data 同步、P2P、独立服务端和死循环保护仍未完成。
- 本批没有新建后台常驻服务，没有修改原始卡牌规则，没有提交 git。
