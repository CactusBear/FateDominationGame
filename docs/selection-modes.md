# 选人模式

入口：主菜单的「开始游戏 → 进入选人」。当前界面只要求本地玩家选择自己的御主，其余 AI 通过 `DummyBot.pick_master` 从合法候选中随机选择，不实现网络通信。选择的只是开局阵容，进入对局后仍沿用现有本地玩家与 AI 控制。

## 当前规则

每名玩家选择不重复御主。全部选择完成后，从每个常规职阶的候选中随机取声明数量，再从全部特殊职阶合并的候选中随机取声明数量。整个池打乱，按玩家列表顺序不放回分配。

没有特殊从者时省略特殊槽位。缺少必需的常规职阶时阻止开始，不以其他职阶补位。人数上限是可用的不重复御主数量与从者池大小的较小值。人数小于池大小时，未抽到的从者不进入本局。

抽取结果不公示。共用选人界面只显示完成提示，不显示任何玩家抽到的从者姓名或职阶；完整归属留在选人会话中供开局使用。候选名单展示的是整个可用角色目录，不是本局抽签结果。

## 实时角色目录

选人界面进入时以及每次开始、选牌、进入对局前检查 `data/masters` 与 `data/servants`。停留期间默认每秒检查一次，间隔通过场景脚本导出属性 `roster_refresh_seconds` 配置。比较文件内容而非仅修改时间，支持同秒内编辑与增删文件。

`LoadGame.refresh_roster()` 通过 `scripts/selection/roster_catalog.gd` 复用现有角色加载方法，只重建有变化的角色模板。未变化角色保留对象身份；旧角色及弱归属链下的对象从注册表移除，不重复追加启动 JSON 缓存。已经开局时不热替换角色，避免改变正在结算的对局。

目录变化时同步候选名称、从者职阶及模式容量，并清空已有选人会话、禁用进入对局，要求重新选择。JSON 尚未保存完整或角色名称重复时保留此前有效模板并阻止开始；数据修正后自动恢复。候选区域支持滚动，不靠固定七名或八名列表。

## 扩展接口

- 模式声明：`data/selection_modes.json`，通过 `LoadHelper.get_data_dir` 读取，适配外置数据目录。
- 接口：`scripts/selection/selection_mode.gd`。
- 当前实现：`scripts/selection/class_pool_selection.gd`。
- 界面：`scripts/selection/selection_screen.gd`、`assets/scenes/main_menu/selection_screen.tscn`。

新增规则脚本继承模式接口，并在 JSON 的 `modes` 列表声明 `id`、`name`、`script` 与该规则所需参数。界面从声明构建模式列表，不根据模式名称判断规则。

接口职责：

| 方法 | 职责 |
| --- | --- |
| `capacity(masters, servants, config)` | 查询容量，错误写入 `error` |
| `setup(ids, masters, servants, config)` | 初始化独立选人会话，不修改对局 |
| `available_masters(player_id)` | 查询可选择御主 |
| `choose_master(player_id, master)` | 提交选择，由模式管理分配过程 |
| `is_complete()` | 判断是否可以进入对局 |
| `get_assignments()` | 完成时输出以玩家 ID 为键、含 `master` 与 `servant` 模板的阵容，否则返回空字典 |

不同交互形式可以扩展接口与选人界面，不必改 `GameStart` 的角色绑定流程。当前界面支持按玩家列表顺序选择御主的模式。

`GameStart.game_start(player_ids, assignments)` 验证完整阵容后复用现有归属记录、效果绑定与附带牌发放。不传阵容时保留已有测试与调试场景的默认分配行为；正常菜单入口必须经过选人。

## 验证

`tests/selection_mode_test.tscn` 覆盖真实名单、重复选择、人数边界、重新初始化、非连续玩家 ID、同职阶多候选、多个特殊职阶合并抽取、开局前验证，以及主菜单到选人再到真实战局的按钮链。非 headless 时通过实际鼠标事件点击，并保存 `tests/runtime_reports/selection_screen.png`。

`tests/roster_live_test.tscn` 用独立临时 JSON 验证界面打开期间新增、修改、删除角色、特殊职阶扩展、容量变化、错误文件恢复和抽签隐私；测试退出自动移除临时文件，不修改用户已有角色。

项目业务脚本统一位于根目录 `scripts/`。迁移保留 `.gd.uid` 文件，不修改 `addons/` 的插件脚本位置，也不触碰历史备份与独立 worktree。
