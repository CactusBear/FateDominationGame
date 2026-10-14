# Round71：个人弃牌 / 公共局势弃牌共享浏览闭包

## 结果与边界

- 生产入口已统一到 board；presenter 两个同义回调及其接线/断开已退休。没有新增生产组件，没有改规则、source、builder、mirror、卡背、原输入/模态函数或 `_handle_scroll_hover` guard。
- 保留能力差异：**正式 v2 本地没有个人弃牌/局势弃牌点击入口，网络有**。本轮不借统一函数给本地增添入口。本地事件菜单仍 toggle，网络仍只打开。
- 真实 headless 最终四专项：新闭包 **168/0**，原 card_browser **4/0**，原 drawer_dismiss **1/0**，原 match_view_privacy **137/0**；各 exit0。合计310检查仅表示逻辑检查，不是310个GUI检查。
- 新测试使用正式 scene、正式 renderer、真实 LocalBattleSource/NetworkBattleSource 与真实 ViewBuilder；网络投递使用受控会话，**不是 ENet/多机/窗口输入验收**。本地只直接调用共享函数测试 source 合同，不把测试调用冒充新增产品入口。
- 未运行 GUI、原 shared事件55、round69窗口、battle_play_groups 或99全量；不宣称视觉done。所有既有dirty保留，没有commit。

## 修改前真实接线与source合同

1. 正式场景是 `assets/scenes/game_scene/battle_board_v2.tscn`，不是 `tactical_board_ui`。场景中 `Ops/Discard` 与 `Piles/SituationPile` 原始 `mouse_filter=IGNORE`，没有 scene连接；board 本地 `_ready()`没有为其绑定点击。
2. 原 presenter `_init()`在网络初始化时绑定 `discard_input` 与 `situation_discard_input`，设置牌堆STOP、子控件IGNORE；原 `release()`只断开局势回调。
3. 原个人回调读 `_mine.discard`（presenter上次refresh缓存）；原局势回调读 `session.read_match().situation_discard`（当前快照）。二者没有排序/去重；原完整标题分别为“我方弃牌 · N”“公共局势弃牌 · N”。本轮保留标题与source数组顺序，包括重复ID。
4. 既有本地source `read_view()`用同一个builder构造观察者过滤快照并缓存；`invalidate()`开始新的读取周期，不发changed。网络source `read_view()`直接转发当前会话快照，`close()`后返回空字典。本次不修改两source。
5. builder已有 `players[].discard` 与 `situation_discard`，`cards()`按原数组遍历投影；个人牌面权限由 observer/own 和既有 `card_view()`声明，公共局势使用公开过滤。消费端不补名字、图片、说明或效果，不推断卡背类型；另一owner的卡背政策继续由其生产者负责。
6. 个人选择严格以当前 `view.observer` 对应的 `player.id` 为准，不用 `own` 布尔兜底，不取第一个玩家，不使用board本地seat或presenter旧缓存。observer缺失/负值/不在players中均为空。

## 逐函数中文解释与耦合评估

### 生产代码

- **board `_ready()`**：仅在网络组合根、source建立后绑定共享浏览控件；保留本地组合根不绑定这两入口。标题、目标与开放能力是组合根声明，不由网络存在与否在浏览函数中猜测。
- **board `_bind_discard_browsing_controls()`**：把原两套固定牌堆连接搬到一处。每个配置显式给出场景路径、原标题与是否读取个人分区；保留原STOP/IGNORE过滤。两个真实网络节点各只有一个连接。没有新Bus、renderer或adapter。
- **board `_on_discard_browse_input(event,pile,title,personal)`**：只接受左键按下，调用共享浏览并沿用原牌堆 `accept_event()`。松开、右键、滚轮、移动、键盘不读取source，不关闭菜单，不打开浏览器。本次没有修改原 `_input()`、presenter `browse_input()`或任何模态guard。
- **board `_open_discard_browser(title,personal)`**：本地source存在时只调用其 `invalidate()`，确保独立打开不依赖上次整屏refresh缓存；随后仅一次 `read_view()`。个人分支读取当前observer的discard；公共分支读取situation_discard；缺失为空。关闭既有事件菜单后调用原 `_show_card_browser()`。personal描述数据分区，不是本地/联机模式；不查询GameData/MapData、actions、pending、preview，不发命令，不修改牌/阶段/资源。
- **board `_show_card_browser()`**：**未改**。继续用既有模板逐项渲染、显示数量/empty、重置滚动并提升浏览层；字典卡面正反面与放大权限继续由原显式字段决定。
- **presenter `_init()`**：只删个人/局势牌堆连接与过滤配置；其它日志、排行、游戏外、技能、选择器等连接保留。不是创建共享函数后仍保留旧生产双入口。
- **presenter `discard_input()` / `situation_discard_input()`**：接线迁移后删除；最终对scripts扫描两符号零引用。未以兼容别名留下旧缓存路径。
- **presenter `release()`**：删除旧局势信号断开分支。信号现在连接board到自身控件；board退出树先关闭source，再release presenter，节点销毁自行释放连接。没有引入新的跨对象信号所有权。

耦合判断：已有source投影足够，新增组件没有必要。规则/隐私生产者保持独立，浏览层只承担“选择投影分区→既有浏览器”；组合根继续控制能力差异。本地invalidate是source生命周期适配，不是回查本地规则。没有为消除分支统一本地/网络菜单开合或地图切换行为。

### 新测试与runner

|函数/类|职责及验证边界|
|---|---|
|ReadTrap.actions/pending/preview|记录是否意外读取规则能力；正常浏览计数始终0，不伪造规则行为|
|SourceSession.read_match/publish|模拟投递、深复制当前字典并发changed；权威牌面来自真实builder|
|SourceSession.read_actions/read_pending/request|记录非法规则/命令耦合；计数0|
|check / _ready|记录唯一CHECK与延迟启动，不吞异常|
|rendered|读取真实CardBrowser卡槽metadata，不读待渲染输入冒充结果|
|textures_match|逐槽核对真实Img纹理与source显式正面/卡背路径；空声明允许空纹理，不据此宣称卡背视觉完整|
|expect|检查真实浏览visible、完整顺序及重复ID、贴图、原标题数量、empty与事件菜单关闭|
|state|快照回合/行动者/阶段/终局/日志、公共弃牌及局势、待答状态、每人资源/顺位/全部牌区及弃牌开闭/正反面声明；前后相等证明覆盖项未改变|
|left / open_personal / open_situation|通过正式节点gui_input信号测试真实接线，明确不是窗口鼠标命中|
|close|通过正式Close按钮信号关闭，检查浏览器与两浮层清理|
|run|先正式本地根验证无新增入口与事件toggle，再真实本地source测试刷新、重复ID、同ID字段变更、切observer、empty；随后正式网络根验证唯一连接与过滤/只打开行为，注入真实网络source测试旧mine不参与、同seq同ID变化、同seq换observer、隐藏字段、缺字段/旁观/缺席、非法输入及close清空|
|finish|释放本测试board/fixture、reset对局，输出RESULT及真实退出码|
|runner load / sha|加载既有隔离原语与配置变换，并用SHA256记录证据|
|runner main|显式目标scene递归发现依赖白名单、逐字冻结、E盘环境与真实主/子probe、import及四headless专项；每scene180秒、独占Job；归档日志/输入/manifest，检查ERROR/WARNING、source/freeze drift、证据读回与Job0后清理自有generated|

负例包括：网络旧 `_mine`故意为空但source有三张；同ID重复必须保留三槽；同seq换observer不能留旧列表；hidden字段不能从本地同ID对象恢复；缺observer/负observer/缺players成员/缺discard/缺公共字段全部空；非左键按下不得读source或改变菜单。状态快照证明的是列举覆盖项，不代替对所有规则路径的全量证明。

## 真实执行与冻结证据

从仓库根执行：

```bash
python -B newtests/run_round71_shared_discard.py --label red --red
python -B newtests/run_round71_shared_discard.py --label green1
python -B newtests/run_round71_shared_discard.py --label final
```

- RED：`E:/scratch/round71-shared-discard-red/isolated-7e099486fc10407d9d3a9d5fc2e825a0/manifest.json`；1检查，失败“共享弃牌浏览入口存在”，exit1；不是解析错误。此冻结也保留本轮生产补丁前原件。
- green1：新闭包146/0及原4/0、1/0、137/0，exit0。补强source纹理逐槽断言和实际zoom_disabled/zoom_desc元数据后，完整重跑最终冻结，不拼接旧结果。
- FINAL：`E:/scratch/round71-shared-discard-final/isolated-c393362114d145dfb5a0905361f7d97d/manifest.json`。
- 最终manifest SHA256：`6ffff6084bfb60e45e317d9749fcc64fc35112d64b3cb14e16403f91ef77ce37`。
- 新闭包PID21632、15.642秒；card_browser PID11684、14.319秒；drawer_dismiss PID27384、10.710秒；privacy PID8240、5.167秒，全部exit0。原两个浏览专项headless分别只有4和1检查，其真实点击分支**没有执行**，不可冒称窗口回归。
- probe PID28388，真实派生worker13464，主/子user://均实测并读回在同一generated/appdata/FateDomination物理E目录；worker_pool20。
- probe/import/四专项共六个Job阶段均exited=true、ActiveProcesses=0、log_handles_released=true；全部stdout/stderr及归档Godot logger零SCRIPT ERROR/SHADER ERROR/ERROR/WARNING；artifact_readback=true，source_drift={}，freeze_drift={}，generated_removed。
- RED与FINAL之间其它owner更新了view_builder、view_mirror、temporary_cleanup_ledger、temporary_cleanup_proof_collector、lobby_session及match_view_privacy_test。本子代理未写这些文件；FINAL整体冻结包含其当时版本，四专项使用同一FINAL，不把RED当作这些依赖的固定基线。最终冻结期间无漂移。
- 原输入/模态/卡背绘制函数逐函数对RED原件核对：`_handle_scroll_hover`、`_input`、`_native_modal_visible`、`_show_card_browser`、`bind_zoom_for_card`均字节等价；正式scene也保持同hash。
- 原Godot SHA256 `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`；正式signal release DLL保持 `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`。未替换引擎/DLL，未操作用户PID28100。
- 初始runner准备曾因缺所有权receipt、误把整个tests作为白名单根而失败；均发生在启动Godot前，已修复为先写receipt和显式scene依赖闭包。它们不计RED/GREEN。首次准备留下的空目录不是生产改动。

## 源hash与窗口owner交接

|文件|最终SHA256|
|---|---|
|scripts/game_scene/battle_board_v2.gd|6a6cecf4f5eb4672f5af77f4d9ac28d62543a0260e3d786f0bcd7781db52bc5d|
|scripts/net/ui/v2_view_presenter.gd|dd409f9d35d6be0078fc83c6198dd1c1deed9c7f35e4a98be34812e39bf464b6|
|newtests/round71_shared_discard_browsing_test.gd|52f798b7bddb9bcc80535b69ba144bc45552fff37e16f7551b94ad5e53bf4c5b|
|newtests/round71_shared_discard_browsing_test.tscn|361ab12e01562ef0ab9f977f886cc88422f5a44c4a7eb50afa2fa1e41b990cf4|
|newtests/run_round71_shared_discard.py|ce5ba05d741d93bb699a2ed5aec48a6ef4160ed81f59775304ab90f64d075e57|

只读依赖的FINAL版本（由其它owner写入，本轮只冻结/验证）：

|文件|SHA256|
|---|---|
|scripts/match/view_builder.gd|9a7ed25688ded565bce41b0a8b7473f8067553b55629fbb7d7ce88a276ec831e|
|scripts/match/view_mirror.gd|8007a3cc6e2e1ed0bb319ba3e1b3bd21fb825e7b9bc24f3f212a724c514eef20|
|scripts/net/session/lobby_session.gd|8b02621c55f94746e41780ddd77025e85a7ccb88e4aa0ab2ec5f8c10d1ed88dd|
|tests/match_view_privacy_test.gd|291b62fdd3d311da0849634c287c1780dfddf5580fce3be296e3724f0d3e4766|

最终冻结生产/测试四文件hash与live读回一致；board 6640→6676，presenter679→657。针对本轮文件 `git diff --check` exit0；新测试/runner `git check-ignore` exit1，无忽略。

交给原窗口owner `sa-0-fe9d35a3`，在其**独占E冻结、既有180秒Job/env封装**内运行以下真实非headless命令；这里不执行：

```bash
"$OWNED_GODOT" --fixed-fps 60 --path "$FREEZE" --scene res://tests/net_v2_browsing_window_test.tscn -- window
"$OWNED_GODOT" --fixed-fps 60 --path "$FREEZE" --scene res://tests/card_browser_test.tscn -- window
"$OWNED_GODOT" --fixed-fps 60 --path "$FREEZE" --scene res://tests/drawer_dismiss_test.tscn -- window
```

原shared事件55由main沿现有runner串行运行（会一并运行其原分组专项，本子代理未启动）：

```bash
python -B tools/tests/round64_shared_browsing.py --label round71-gui --window
```

需要owner确认：两牌堆真实点击、原标题/数量/顺序、个人与局势empty、菜单关闭、浏览器内不穿透/外部关闭、滚轮和Esc/关闭按钮、隐藏牌不泄露正面/说明、浏览时地图不误切，以及原local-toggle/network-open差异。最终非headless截图须原生查看全屏与必要裁片，不能以本文件168检查或headless信号代替。

注意旧 `net_v2_browsing_window_test`还包含本闭包以外的终局断言：它只修改传给 `show_game_over` 的局部game_view，而当前show_game_over已转调board source。这些历史断言是否符合当前合同需owner独立归因；不改此旧测试、不因其无关失败恢复客户端终局推断。其旧证据输出路径也须owner按自身隔离封装处理。没有为这次改动伪造该窗口专项通过。

## 本轮生产V4A（相对本轮RED冻结，不包含仓库既有dirty）

以下已经应用，只作为审阅/交接，不应在当前tree重复应用。新测试与runner内容见对应新文件。

```diff
*** Begin Patch
*** Update File: scripts/game_scene/battle_board_v2.gd
@@
 		_bind_event_discard_controls("公共事件弃牌 · %s", false)
+		_bind_discard_browsing_controls()
 		_network_presenter = preload("res://scripts/net/ui/v2_view_presenter.gd").new(self, network_session)
@@
-## 只读查看与效果选牌分离；复用现有事件卡模板和贴图绑定，不提交任何规则动作。
+## 当前只有网络组合根开放这两个入口；不改变本地牌堆的既有能力。
+func _bind_discard_browsing_controls() -> void:
+	for entry in [["Ops/Discard", "我方弃牌", true], ["Piles/SituationPile", "公共局势弃牌", false]]:
+		var pile: Control = get_node(entry[0])
+		pile.mouse_filter = Control.MOUSE_FILTER_STOP
+		pile.gui_input.connect(_on_discard_browse_input.bind(pile, entry[1], entry[2]))
+		for child in pile.find_children("*", "Control", true, false):
+			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
+
+
+func _on_discard_browse_input(event: InputEvent, pile: Control, title: String, personal: bool) -> void:
+	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
+		_open_discard_browser(title, personal)
+		pile.accept_event()
+
+
+## 只消费当前 source：本人按 observer 精确选择；不缓存、不排序、不合并相同 ID。
+func _open_discard_browser(title: String, personal: bool) -> void:
+	if _source_is_local and _source != null:
+		_source.invalidate()
+	var view: Dictionary = _source.read_view() if _source != null else {}
+	var cards: Array = []
+	if personal:
+		var observer: int = int(view.get("observer", -1))
+		if observer >= 0:
+			for player in view.get("players", []):
+				if int(player.get("id", -1)) == observer:
+					cards = player.get("discard", [])
+					break
+	else:
+		cards = view.get("situation_discard", [])
+	$EventDiscardMenu.hide()
+	_show_card_browser(title, cards)
+
+
+## 只读查看与效果选牌分离；复用现有事件卡模板和贴图绑定，不提交任何规则动作。
 func _show_card_browser(title: String, cards: Array) -> void:
*** Update File: scripts/net/ui/v2_view_presenter.gd
@@
 	out_button.pressed.connect(open_out_of_game)
-	board.get_node("Ops/Discard").gui_input.connect(discard_input)
-	board.get_node("Ops/Discard").mouse_filter = Control.MOUSE_FILTER_STOP
-	var situation_pile: Control = board.get_node("Piles/SituationPile")
-	situation_pile.mouse_filter = Control.MOUSE_FILTER_STOP
-	situation_pile.gui_input.connect(situation_discard_input)
-	for child in situation_pile.find_children("*", "Control", true, false):
-		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
-	for child in board.get_node("Ops/Discard").find_children("*", "Control", true, false):
-		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
@@
-func situation_discard_input(event: InputEvent) -> void:
-	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
-		# 列表由权威公开过滤；无字段时展示空列表，不查本机 MapData。
-		board._show_card_browser("公共局势弃牌", session.read_match().get("situation_discard", []))
-		board.get_node("Piles/SituationPile").accept_event()
-
-func discard_input(event: InputEvent) -> void:
-	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
-		board._show_card_browser("我方弃牌", _mine.get("discard", []))
-		board.get_node("Ops/Discard").accept_event()
@@
 func release() -> void:
-	var situation_pile: Control = board.get_node("Piles/SituationPile")
-	if situation_pile.gui_input.is_connected(situation_discard_input):
-		situation_pile.gui_input.disconnect(situation_discard_input)
 	board.get_node("IdentityInheritancePanel").close_panel()
*** End Patch
```

## 尚未覆盖

新闭包未跑真实ENet投递和GUI；原窗口套件的历史终局断言、输出目录及完整视觉结果未验证；未证明所有规则内部状态绝不变化，仅覆盖列举快照项与禁止的query/request。main整合别人的builder/mirror后需重新冻结并核对新hash再验窗口，不能把本次冻结结果混称最终合并视觉验收。
