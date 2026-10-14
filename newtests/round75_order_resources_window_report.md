# 行动顺位与敌方资源：真实窗口单次验收

## 结论

- 最终窗口专项：**exit 1；34 CHECK，31 true / 3 false**，日志无 SCRIPT ERROR / ERROR / WARNING。
- B 已验：快照 seq 101→102 经正式 `LobbySession` 接收、`NetworkBattleSource` 与正常 board `_process` 刷新；敌方魔力 **5→9**、合计威力 **7.5→12.75**、战果 **3→11**、普通令咒 **×2→×1**，实际顶栏 Label 文本与快照一致。已打开抽屉跟随刷新且保持打开，其实际节点文本也记录为新值。
- A 不通过：正式 v2 没有行动顺位表展开/折叠入口；只有顶栏横向卡，不能完成展开/折叠操作。三名玩家的真实序号 1/2/3 正确；本方显示“我方”，不显示快照玩家名“顺位甲”。
- B 缺省字段不通过：允许缺省的 `total_power` 删除后，正式会话接收成功，但顶栏仍显示“合计威力 0”，是假定零值，不满足“缺失不显示占位垃圾值”。没有引擎报错。
- **不是整体验收通过。**只覆盖本次冻结版本与受控会话快照，不是 ENet、OS 硬件输入、多机、真实权威命令结算或整局验收。

## 命令、退出与进程

仓库命令：

```text
python newtests/run_round75_order_resources_window.py --label once
```

最终实际窗口命令（没有 --headless）：

```text
E:\scratch\round75-order-resources-once\isolated-0e85326694f54779874a50f2b841b5d4\generated\Godot.exe --fixed-fps 60 --path E:\scratch\round75-order-resources-once\isolated-0e85326694f54779874a50f2b841b5d4\generated\project --scene res://newtests/round75_order_resources_window_test.tscn -- window
```

- runner exit **1**；窗口引擎 PID **37700** exit **1**，不是超时，看门狗 **600s**。
- 只做隔离物理路径 probe / editor import 的前置进程 exit **0 / 0**，它们不是窗口验收替代品。
- 最终所有三个 OwnedJob 记录 `exited=true`、`active_owned_processes=0`、`log_handles_released=true`，**Job0=true**；generated 已删除，证据与冻结脚本保留；artifact_readback=true。
- 不触碰 PID 17120 / 28100；没有批量结束 Godot。

## 失败项（原文）

1. `A 行动顺位表真实展开折叠入口存在`
2. `A 顺位1显示真实玩家名`
3. `B 缺字段不显示占位垃圾数值`

CHECK 行数与 RESULT.checks 已用 Python 聚合复核，34 一致，不靠手数。

## 输入证据

单路 `Viewport.push_input`，每次 motion 后推进一帧，hovered 命中正式 RivalCard，再 down/frame/up/frame。

```json
{"motion":2,"down":2,"up":2,"gui_down":2,"gui_up":2}
```

真实点击：打开顺位乙的对手抽屉、同一入口再次关闭。没有 `warp_mouse`、`Input.parse_input_event`、`pressed.emit`、直接调用开关回调或直接写 Label。RivalCard 用 `gui_input`，不是 Button，因此不伪造 pressed 计数。A 无入口，未派发冒充折叠的点击。

快照投递是同一正式 transport 信号：先 `match_bind observer=0`，再 `match_view`；保留正式来源门、绑定、严格 mirror 校验、source 与 presenter 正常帧刷新。不直接写 session 镜像或 UI 节点。测试控制的公开投影数值不是权威命令产生的变化，因此只声明“快照更新驱动”分支已验。

## 实际节点文本、尺寸字号

1920×1080 窗口渲染：

| 玩家 | 实际卡尺寸 | 序号 / 字号 | 玩家名字 / 字号 |
|---|---|---|---|
| 0 | 60×150 | `1` / 12 | `我方` / 13；没有 Name 节点 |
| 1 | 184×150 | `2` / 12 | `顺位乙` / 15 |
| 2 | 184×150 | `3` / 12 | `顺位丙` / 15 |

资源标签字号 11，资源数值 14，魔力法阵数字 12。以上是节点 `get_theme_font_size()` 和 `get_global_rect()`，不是估计。并非用户要求的“足够大”的展开表。

夹具保留 `new_player_data()` 的默认 `is_out=true`，所以敌方卡按生产出局规则压暗；**不能据本截图压暗程度推断正常在场卡的对比度缺陷**。因此正常在场、长玩家名、最大人数、伸缩/折叠后的可读性仍未验。未再修夹具或重跑以刷绿。

更新后的抽屉真实文本：

```text
VBox/HeaderBar/OrderBadge = 顺位乙 · \n战果 11
VBox/ResourceVisuals/MagicH/Magic = 魔力 9
VBox/ResourceVisuals/Power = 合计威力 12.75
VBox/ResourceVisuals/CommandSpells = 令咒 ×1
```

缺字段测试仅删除协议允许缺省的 `total_power` / `special_command_spells`。魔力/战果/普通令咒是 mirror 必需数值，缺失应被协议拒收；本次未另做这些必需字段拒收窗口测试，不能称全部缺字段场景已验。

## 原生截图亲验

使用 `load_image_native` 把 PNG 直接载入模型上下文，**没有使用 vision_analyze**。以下三张均亲看全图，并对顶栏 / 抽屉做原分辨率裁片亲看：

证据根目录：
`E:/scratch/round75-order-resources-once/isolated-0e85326694f54779874a50f2b841b5d4/evidence/`

1. `screenshots/order-resources-initial.png`：亲见顶栏横排 1“我方”、2“顺位乙”、3“顺位丙”，未见可折叠的逐行顺位表；裁片见乙魔力 5、合计威力 7.5、战果 3、令咒×2。敌方卡压暗，文字偏小；未见常态 HP 文案。
2. `screenshots/order-resources-updated.png`：亲见右侧对手抽屉保持打开，名称顺位乙、战果11、魔力9、合计威力12.75、令咒×1；没有异常白块 / 缺字。此图不是整局视觉完成证明。
3. `screenshots/order-resources-missing.png`：亲见抽屉关闭，乙魔力9、战果11、令咒×1；缺失总威力仍画成“合计威力0”，与失败断言一致。

## 最小生产因果（只报，不修）

- `battle_board_v2.gd::_bind_rival_order` 的 SelfSlot 分支只有顺位与“我方”模板，不绑定玩家名；生产场景的 Rivals 是横向 HBox，正式可见按钮清单只有战果榜、日志、事件牌堆入口、出牌、结束阶段，没有顺位表折叠入口。
- `battle_board_v2.gd::_bind_single_rival` 使用 `player.get("total_power", 0)` 写入 `Stats/PowerStat/V`；因此可缺省字段被渲染为真实零值。`view_mirror.gd` 对 `total_power` 仅在存在时校验，缺省投影合法。

## 初次阻断、修正与冻结边界

- 第一次 runner：隔离 ef6624… exit1；复制中途异常后 finally 把尚未复制的 generated 文件当归档源，`event_journal.gd` 的缺路径异常盖住原始原因。仓库文件存在，**不是生产缺文件**。只修我新增 runner：先完整复制所有清单依赖再校验/归档；未完整复制时显式记录缺项并阻止二次归档；保留原始错误，绝不静默跳过依赖。
- 第二次隔离 c2d569…：复制/import 已完成；夹具漏发 match_bind，导致快照拒收、Rival 为空，并在 gd:138 报 Nil.gui_input。外层 terminal 于420s超时，没有可证明的 runner 退出码；该记录不是产品故障证据。日志保留于该隔离目录。
- **唯一一次夹具修正**：补正式 match_bind、空节点失败退出保护、把缺字段用例限定到协议可缺省字段；最终隔离 0e853… 完成上述真实窗口验收。不再重跑。
- 最终 freeze_copy_complete=true、freeze_drift={}；但运行期间仓库 `scripts/net/ui/v2_view_presenter.gd` 被外部改动，source_drift 非空。冻结 SHA `518dc8391e58c02ee4d84a0c375dc24bf50975e326285dfcb718d781dc47aa90`，收尾仓库 SHA `81285a188f225449e7bdac8f3f955a8a3c196d83c79152e0888afd98d94d55f6`。**本结果只适用于 frozen-inputs，不证明当前漂移后的工作树。**本代理未修改生产文件。

## 产物

新增 / 仅修改本次文件：
- `newtests/round75_order_resources_window_test.gd`
- `newtests/round75_order_resources_window_test.tscn`
- `newtests/run_round75_order_resources_window.py`
- `newtests/round75_order_resources_window_report.md`

完整真实命令、进程、哈希、CHECK/RESULT、GUIINPUT、TRACE 与截图索引：
- 隔离根 `manifest.json`
- `evidence/round75_order_resources_window_test.stdout.log`
- `evidence/round75_order_resources_window_test.stderr.log`（空）
- `evidence/frozen-inputs/`

未验：A 展开/折叠与各状态布局（入口缺失）、正常在场卡对比度、长名/多人极限、必需字段缺失拒收、真实权威命令引起资源变化、ENet/多机、当前外部漂移版本。既有卡浏览、除外/弃牌、战果榜专项均未重跑。
