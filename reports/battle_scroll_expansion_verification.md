# 卷轴内席位、出牌组与事件弃牌验证

## 修改文件
- assets/scripts/game_scene/battle_board_v2.gd：五人可见头像排、卷轴内席位插值、持久玩家牌组与悬浮展开、合计威力绑定、事件弃牌分类浏览、高清背景路径。
- assets/scenes/game_scene/battle_board_v2.tscn：席位裁切、令咒尺寸、卡面外职介标签、事件弃牌二级菜单与只读浏览器、卷轴半透明背景与氛围粒子。
- tests/battle_scroll_test.gd、tests/battle_board_v2_test.gd：更新对应布局与显示断言。
- tests/battle_play_groups_test.gd / .tscn：实际出牌后出现牌组、节点保留、悬浮展开及威力等专项。
- tests/battle_event_discard_test.gd / .tscn：事件来源分类、真实输入点击、重新打开读取当前数组、空列表及高清半透明背景专项。
- assets/images/game_scene/v2/background_candidates/：高清候选图及 sources.json 来源清单。实际接入远坂工房、远坂宅、冬木大桥、FGO 冬木四图。

## 实际验证
- 全量回归：59 套、2682 项，失败和错误均为零，进程退出码 0。
- 回归汇总：tests/runtime_reports/scroll_expansion_final_regression/summary.json。
- 非 headless 1600×900 窗口运行：battle_event_discard_test 25 项、battle_play_groups_test 16 项、battle_scroll_test 52 项、battle_scroll_full_game_test 15 项，均通过。日志为 tests/runtime_reports/*_window_final.log。
- 完整对局驱动已实际运行至结束，未修改游戏规则。
- 七张下载素材已逐一解码并核对清单尺寸及 SHA-256；运行时断言验证四张背景宽度至少 1920 且透明度在 0 与 1 之间。
- git diff --check 通过，场景节点路径无重复。

## 验收边界
- 当前工具图片投递未让主模型原生看到画面，未使用 vision_analyze。因此截图保存和窗口断言不代表人工视觉验收；构图、实际遮挡观感、粒子美术效果仍待原生读图复核。
- Fate 原作相关网络素材仅用于当前内部参考。Fandom 可下载不等于可再发行，正式发布前须确认授权或替换。
- 上限五人指上排头像可见容量，不限制实际参战人数。
