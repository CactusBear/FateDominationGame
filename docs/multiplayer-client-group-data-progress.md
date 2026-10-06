# 客机暂选、跨进程整局与数据组装

## 本批实际完成

- `group_selection.gd` 只维护客机暂选：调用主机组合预览，按请求 ID 丢弃迟到回复，预览返回前不允许确认，重复确认被抑制，权威视图变化后清除旧暂选。无本地规则查询。
- `network_hand_strip.tscn/.gd` 将该控制器接成独立验收组件，牌边显示允许的明置/暗置和撤回按钮，不弹二级选牌窗口。真实 ENet 与鼠标验证确认前不扣费、确认后主机一次性扣费入场。当前只是文字功能组件，未替代 v2 的卡图手牌布局。
- `net_process_full_game_test` 在两个独立 Godot 进程运行。两端决策只读会话视图、操作提示和主机预览，不用本地 RegularPlay.find_group；客机 GameStart 始终未启动。主机记录真实 game_end，整局检查未收到其他玩家手牌。
- 固定种子 1977 连续三局通过；42、1978、2026 分别通过。日志分别见 multiplayer-process-full-game-results.json 与 multiplayer-process-seed-results.json。它们不是公网/跨设备验收，也不是人工 UI 整局。
- `room_data_assembler.gd` 将已批准清单从缓存组装到新会话目录，检查文件哈希、大小、路径、跨平台大小写冲突和总预算，成功后重命名发布，不覆盖已有目录、不切换全局数据根、不修改原始 data。
- `room_data_sync.gd` 串联缺失文件下载、缓存固定引用、进度超时和完整组装；下载失败不发布半成品目录。当前由调用方显式提供批准清单，尚未接大厅条目勾选与全员开局屏障。

## 已运行专项

- net_group_selection：13 checks，通过。
- net_play：22 checks，通过，含真实 ENet 组合预览和两张牌的客户端暂选。
- net_hand_window：9 checks，通过，无运行错误；已原生查看 net_hand_strip.png。
- net_assembly：15 checks，通过，使用真实急行 JSON，覆盖路径穿越、大小写冲突、缺失缓存和已有目录拒绝。
- net_data_sync：8 checks，通过，真实 ENet 下载真实急行 JSON 后组装，缺失内容失败不发布目录。

## 仍未完成

正式 v2 网络显示与交互接线、卡图和临时可见牌面的授权、大厅数据选择/清单发布/全员同步屏障、P2P、Windows/Linux 多房间单入口服务端、死循环预检及保护、恢复菜单仍未完成。当前文本手牌验收组件不是最终视觉设计，也没有宣称正式客户端可交付。
