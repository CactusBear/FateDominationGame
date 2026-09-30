# 对局地图卷轴修改与验证

## 当前实现

- 每个战区使用持久卷轴节点，地图背景复用 `assets/images/game_scene/v2/area_*.jpg`。四张图片已与 `docs/battle_ui_concept_v2/assets` 对应文件逐一 SHA-256 比对，一致。
- 同步插值所有卷轴矩形，从当前动画进度接续切换；周期数据刷新不重建席位与事件卡图标。
- 默认展开本方已部署战场；未部署时直接读取 `MapData.magic_workshop`。悬浮其他地图可临时展开，离开后返回默认战场。
- 展开态固定席位位于左下角数据上方；无固定席位玩家位于更上一排。上排显示四人宽度，超出可滚轮横向浏览，没有可见滚动条。刷新保留滚动位置。
- 左侧折叠地图避让双排席位区。两种状态均隐藏空事件和零战果，不创建占位卡背或空标题。
- 不修改游戏规则、operations 或正式游戏数据。

## 修改文件

- `assets/scripts/game_scene/battle_board_v2.gd`
- `assets/scenes/game_scene/battle_board_v2.tscn`
- `tests/battle_board_v2_test.gd`
- `tests/battle_scroll_test.gd`
- `tests/battle_scroll_test.tscn`
- `tests/battle_scroll_full_game_test.gd`
- `tests/battle_scroll_full_game_test.tscn`

新增完整对局测试复用 `full_game_test.gd` 的真实引擎推进逻辑，隐藏旧控制器界面，显示 v2 场景。它不代表为 v2 新增了旧版完整交互功能。

## 实际验证

1. 首轮失败测试证明原实现不满足持久节点和默认折叠要求；后续根据用户修订再次确认未部署默认工房与双排复用测试在修复前失败。日志：`tests/runtime_reports/battle_scroll_red.log`、`battle_scroll_default_red.log`。
2. 最终窗口专项：48 个检查通过，退出码 0，没有 SCRIPT ERROR。覆盖中间帧、双向展开、反向切换、图标身份、数据刷新、空事件/零战果、边缘避让、五人滚动与部署前后默认地图。日志：`tests/runtime_reports/battle_scroll_window.log`。
3. 非 headless 完整对局：15 个检查通过，退出码 0，没有 SCRIPT ERROR。真实发生部署、战斗、高潮回合淘汰并到达游戏结束。日志：`tests/runtime_reports/battle_scroll_full_game_window.log`。
4. 最终全量回归：扫描到的 57 个测试场景全部运行，汇总计数 2639 个检查，失败 0，错误 0，缺失场景 0。少数旧套件不输出可解析检查总数，因此 2639 为跑批器可识别的检查数。证据：`tests/runtime_reports/scroll_final_regression/summary.json`。
5. `git diff --check` 退出码 0。

## 画面验收尚未完成

已生成 1600×900 窗口截图，包括展开中、展开后、切换中、空数据、双排五人滚动、完整对局行动和结束。主要文件：

- `tests/runtime_reports/battle_scroll_deployed_rows.png`
- `tests/runtime_reports/battle_scroll_opening.png`
- `tests/runtime_reports/battle_scroll_switching.png`
- `tests/runtime_reports/battle_scroll_empty_open.png`
- `tests/runtime_reports/battle_scroll_empty_closed.png`
- `tests/runtime_reports/scroll_full_game_action.png`
- `tests/runtime_reports/scroll_full_game_end.png`

当前会话未收到这些截图的原生图像内容，因此没有宣称已肉眼确认画面美观、无闪烁或无异常色块。最初桌面截图工具曾自动转入辅助视觉；发现后已停止该路径，未将其视为原生验收。

用户已授权永久切换 Hermes 原生视觉：配置已备份，通过 CLI 设置 `agent.image_input_mode=native`、清除辅助视觉的显式 provider/model/base_url，并设置 `model.supports_vision=true`。新进程路由检查返回 `capture_routes_to_aux=False`。旧进程缓存及仅返回 MEDIA 文件路径的截图结果不能证明图像已送入当前主模型。需要原生图片附件或可直接投递原图的新会话完成最后的视觉复核。
