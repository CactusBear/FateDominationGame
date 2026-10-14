# Round74：战果榜 toggle 有界统一闭包

## 交付

- board 本地真实按钮与 presenter 网络真实按钮现在均直连 board `_toggle_scoreboard()`；presenter 原同义 `toggle_scoreboard()` 已删除，没有兼容壳或未接线新模块。
- 仅改 `scripts/game_scene/battle_board_v2.gd` 和 `scripts/net/ui/v2_view_presenter.gd`；生产最小 diff：`newtests/round74_scoreboard_production.patch`（相对本轮 RED 原件，不包括仓库已有 dirty）。
- 原 source、builder、mirror、scene、日志函数、`_bind_board()`、`_native_modal_visible()`、`_handle_scroll_hover()`、`_input()` 保持原件；无新字段／bus／规则／日志 adapter，没有提交。

## 为什么不统一日志

本地 `_open_game_log()` 读取 `GameLog.query({}, null, -1)`，经现有 `GameLogText` 格式化完整历史，并使用 `GameProgress.last_battle_result` 的完整战斗明细。网络 `open_log()` 只读取 `session.read_match().public_log` 和公开 `battle_result`，胜者名字来自过滤后的 `players`。

builder `public_log()` 在生产端对事件类型做白名单筛选、丢弃 `secret_choice`、清除 object 与来源参数，并只保留获准公开的数据。两入口的数据内容及历史／结算格式不同。当前 local source 也只有公共投影，没有明确的“完整本地日志”能力声明。本轮不能写 source／adapter，所以无法在不改变行为或隐私语义的前提下完成日志闭包；没有猜测能力或把完整日志放入公共快照。选择用户明确允许的已 source 统一战果榜 toggle 一个点。

## 修改前逐函数解释与耦合方案

- board `_ready()`：仅把本地匿名 toggle 改接 board 具名共享入口，保留组合根和初始化顺序。
- 新 board `_toggle_scoreboard()`：只反转 `_board.visible` 并调用原 `_bind_board()`。原 renderer 隐藏时不读 source、不绘制行，仅同步返回控件；保留本地关闭时原行为，网络关闭时也同步隐藏的返回控件。返回控件原逻辑读取网络管理动作投影，未新执行规则或发送命令。
- presenter `_init()`：网络按钮直接连接 board 的同一入口，网络 source 的生命周期与命令适配不变。
- 删除 presenter `toggle_scoreboard()`：修改前全文扫描只有该生产连接一个 caller；修改后旧符号在生产零引用。不清理本闭包以外历史代码。
- `_bind_board()` 未改：只用当前 source `players`，按原 score 降序和原 observer 样式显示，沿用既有 `_sync_items`、头像绑定、`BaseNumber.display_text` 和高度计算；无 seq／ID 缓存 shortcut。

测试函数的解释在修改前已发送：`ReadTrap` 和受控会话规则接口计数；`state()` 对比规则状态，`output()` 读取真实节点；`expect()` 对比排序文本样式高度并记录轨迹；`run()` 使用正式本地／网络组合根；`owner()` 验证唯一真实接线归属；`finish()` 释放专项对象并输出 RESULT。runner 复用原隔离原语与配置变换，只运行一个新 headless scene。

## 短正确性执行

```bash
python -B newtests/run_round74_scoreboard.py --label red
python -B newtests/run_round74_scoreboard.py --label green --compare E:/scratch/round74-scoreboard-red/isolated-b52bd694f3d148d2b4ddb4dc3d92a4da/manifest.json
```

- RED exit1，64检查，仅预期3失败：本地／网络caller尚未归属board，以及presenter旧函数尚未退休。无解析错误；61行为检查通过，原接线节点输出保留。
- GREEN exit0，64检查／0失败；13条真实renderer输出轨迹与原接线逐项完全一致，含排序／小数、打开／关闭、同seq同ID刷新、observer变化、空视图、缺字段／过滤姓名不回补和source关闭。
- 使用真实 LocalBattleSource、NetworkBattleSource、ViewBuilder、正式 board scene／renderer；网络投递由受控会话提供，**不是ENet／多机／窗口验收**。
- source actions／pending／preview、受控会话请求计数0；所列阶段、资源、牌区、日志与等待状态前后相同。原返回控件读取真实 lobby 的管理投影，不把该读取误称规则执行，也不声称覆盖所有规则路径。
- GREEN专项PID31204，8.191秒，仅是执行证据，未测优化效果。probe主26172／真实派生worker22104，user://均在本次E独占generated目录。probe／import／专项各独占Job退出，ActiveProcesses=0，日志句柄释放。
- 无 SCRIPT ERROR／SHADER ERROR／ERROR／WARNING；artifact_readback=true；source_drift={}／freeze_drift={}；generated已清理，归档证据保留。
- 原引擎hash `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`，原signal release DLL `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`。未替换DLL、未启动GUI、未操作其它PID。

GREEN manifest：`E:/scratch/round74-scoreboard-green/isolated-b17d0e01c25548bfaf44c7895b8d8d8b/manifest.json`；SHA256 `fa730cab70f08dccf65fc53a979a441a0192780e2ec41c3cb1c8d96e0db58799`。

## 源hash

- board：`6b3b47815db65c11dffd9c3655f14bacd238751066c6d0c2a51fc20242647d08`
- presenter：`93c9c254540feaa2f346ac745b1f498212cd3cc3e83deac895db36360ac2e5a9`
- builder未改：`9a7ed25688ded565bce41b0a8b7473f8067553b55629fbb7d7ce88a276ec831e`
- mirror未改：`8007a3cc6e2e1ed0bb319ba3e1b3bd21fb825e7b9bc24f3f212a724c514eef20`
- 其余专项／scene完整hash：`newtests/round74_scoreboard_evidence.json`。生产两文件与专项两文件live和GREEN冻结hash一致。
- `git diff --check`（两生产文件）exit0；新专项、runner、patch、evidence `git check-ignore` exit1，无忽略。

## 给唯一GUI owner的一个验收命令（此处未执行）

在owner自己的新E独占冻结、已有180秒Job／环境封装中，包含旧窗口scene与其精确依赖，并运行：

```bash
"$OWNED_GODOT" --fixed-fps 60 --path "$FREEZE" --scene res://tests/net_v2_browsing_window_test.tscn -- window
```

已有该专项286–290行通过真实鼠标输入打开榜单、对照players行数并再次点击关闭。需owner检查网络正式入口唯一命中、榜单不残留、原排序／样式／文本；本地具名入口仍需真实窗口人工打开／关闭对照。非headless截图由owner原生查看；本轮不宣称视觉完成。

注意此旧窗口专项含本闭包之外的终局断言（只改传给show_game_over的局部game_view，但正式board读source），且证据路径硬编码到历史E目录。owner若遇这些历史失败需独立归因并按自己的隔离能力整合，不能据此恢复旧客户端推断，也不能将本轮64逻辑检查冒称窗口通过。本子代理没有修改任何既有GUI专项。

## 未覆盖

未跑99全量、性能、原battle_play_groups、round69模态或任何GUI；未完成日志统一；未验证真实ENet战果榜传输。这些不是本轮完成项。
