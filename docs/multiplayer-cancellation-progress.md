# 显式取消选择

## 实现

- EffectManager.cancel_pending_choice 只负责取消当前待答：按当前选项 allow_cancel 声明检查权限，清理对应等待与暂存目标，不付款、不记选项次数，再恢复既有管线。
- 合法空选择与取消分开。最低数量为 0 时，点击放弃不会被当成提交空数组而发动效果。
- 网络 cancel_choice 校验连接座位、效果触发者和视图版本，调用 MatchCommands 门面；MatchReplay 白名单同步登记 cancel_pending_choice。
- 选玩家与选地点提示补上由原引擎读取的 allow_cancel；客机组件各类提示的放弃按钮均受该字段控制。

## 已验证

原始批次日志见 multiplayer-cancellation-results.json：net_cancel 12 checks、card_selection_mandatory 39 checks、card_selection_owner 17 checks、net_full_game 4 checks、net_target_window 13 checks、net_opponent_window 11 checks 均通过且无运行错误。

随后存档专项 match_replay_pending_test 先验证未登记取消指令会报红，再补门面与白名单；12 checks 通过。覆盖真实待答恢复、取消、继续写入、再恢复一致性和篡改拒绝。

## 范围

这是新增的显式取消入口，不自动替换全部旧单机 UI 的空数组提交；避免未经专项验证改变既有交互。正式 v2 网络镜像接线、P2P、多房间独立服务端及其他方案未完成项仍未完成。
