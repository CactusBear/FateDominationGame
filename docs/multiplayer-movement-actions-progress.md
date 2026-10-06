# 普通移动与客机操作提示

## 实现

- NetworkMatchAuthority 支持 move，参数仅目标战区 ID，不接收客户端步数、费用或忽略限制开关。权限、阶段、等待状态先验；移动判据复用现有 TacticalBoardUI.area_action_block_reason_for，执行复用 MatchCommands.move。
- 新增 actions_for，按连接座位给出当前可部署战区、可移动战区、出牌候选的明暗方式、可主动发动效果。未分配座位的观战者无操作提示；提示不替代提交时的重新校验。
- LobbySession 将 actions 与视图、私有等待提示同包发送，客机通过 read_actions 获得深拷贝，不在客机执行规则。

## 验证

原始日志见 multiplayer-movement-actions-results.json：net_move 11 checks、net_lobby 32 checks、net_pending 15 checks、net_full_game 4 checks、net_target_window 13 checks 均通过，无运行错误。

移动测试覆盖目标费用、拒绝代操作、拒绝费用覆盖、逆向拒绝和拒绝不改变资源。测试初始魔力曾设为超出正常上限的 20，实际扣费操作触发原有资源限额，因此将夹具改为正常范围 10；没有修改引擎费用或资源上限。

## 未完成

- 操作提示已到达客机，但尚未接正式 v2 的战区点击和手牌按钮；不可称为正式客户端可玩。
- 组合选牌中的动态明暗资格仍需单独预览请求；当前 cards.modes 仅用于空暂存组合，不可拿来替代含已选牌的 pending_modes 判据。
- 规则合法性查询仍引用旧 UI 文件中的静态共用函数，尚未进一步抽成纯规则查询模块；保留现有单一判据，避免复制规则。
- P2P、独立服务端及完整方案其余未完成项保持原状态。
