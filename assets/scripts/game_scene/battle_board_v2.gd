extends Control

## 对局界面 v2 控制器。节点树、样式（Theme 变体）、静态文案、固定坐标全部在
## battle_board_v2.tscn 里；数量随数据变化的元素从场景的 Templates 节点 duplicate。
## 本脚本只做：读引擎数据 → 填文本/贴图/显隐/变体名，以及少量随数据变化的坐标计算
## （主圆位置、竖条位置、手牌扇形、席位角度、出牌组网格）。
##
## 本批范围：布局 + 数据绑定 + 悬浮切主图 + 结束阶段 + 日志。出牌/令咒/移动/放大留下一批。
## 规则数字全部读引擎（GameData / GameProgress / MapData / RegularPlay），界面不写死。

## ---------- 声明：数据到装饰文案的映射 ----------
## 战区底图按现有 MapData.areas 顺序声明；来源及替代说明见 board_alternatives/selected_sources.json。
## 这些原作相关图仅用于内部参考，正式发布前需确认授权。
const AREA_IMAGES: Array = [
	"res://assets/images/game_scene/v2/board_alternatives/summoning.webp",
	"res://assets/images/game_scene/v2/board_alternatives/bridge.webp",
	"res://assets/images/game_scene/v2/board_alternatives/shinto.webp",
	"res://assets/images/game_scene/v2/board_alternatives/castle.webp",
]
const AREA_LATIN := {"魔术工房": "MAGIC WORKSHOP", "深山町": "MIYAMA", "新都": "SHINTO", "侦察": "SCOUT"}
const PHASE_NAMES := {"prepare": "准备", "outpost": "前哨", "action": "行动", "battle": "战斗"}

## ---------- 声明：随数据变化的坐标公式用到的常量（静态坐标都在 tscn） ----------
const SCROLL_MARGIN := 16.0
const STRIP_STEP := 82.0
const SCROLL_SECONDS := 0.48
const SCROLL_LEAVE_SECONDS := 0.22
const STRIP_TOP := 236.0
## 席位横排：滚轮一格滚动的像素数；排内可见 4 席时自动出现（无滚动条，只用滚轮/拖动）
const SEAT_SCROLL_STEP := 86.0
## 手牌同组牌的错位比例（相对卡宽）：只让玩家看出是叠着的两张，不再几乎重合
const HELD_STACK_GAP_RATIO := 0.62
const HELD_VISIBLE_HEIGHT := 64.0
const HELD_GAP := 24.0
const HELD_HOVER_SCALE := 1.75
const HELD_HOVER_SPEED := 14.0
## 悬浮放大的纵向跟随比例与上升上限：横向不跟随，纵向只向上
const HELD_HOVER_FOLLOW := 0.35
const HELD_HOVER_MAX_SHIFT := Vector2(70, 46)
## 牌面翻转（明置↔暗置等换面）的总时长：折到最窄换贴图，再展开，两段各占一半。
## 时长是表现参数，与规则无关；换面越频繁的入口越应该短。
const CARD_FLIP_SECONDS := 0.26

## 在途飞牌的尺寸跟随速度（越大越快贴上目标尺寸）
const FLY_RESIZE_SPEED := 14.0
const REFRESH_INTERVAL := 0.5
const TOAST_SECONDS := 1.6
## 未公开（暗置）遮罩：半透明灰 + 闭眼图标。语义是"这张牌已有，但对观看者隐藏"，
## 与旧控制器（tactical_board_ui.gd）同一套视觉，改动时两边要一起看。
const CONCEAL_ICON := "assets/images/ui/icons/icon_eye_closed.png"
const CONCEAL_COLOR := Color(0.32, 0.32, 0.36, 0.55)
## 未激活遮罩：半透明深红，不带图标。语义是"这张卡还没生效"，与未公开是两回事，可以同时盖
const INACTIVE_COLOR := Color(0.45, 0.06, 0.10, 0.45)
const RIVAL_SHIFT_SECONDS := 0.6
const TURN_ENTRY_SECONDS := 0.5
const TURN_READ_SECONDS := 0.45
## 中央回合横幅：淡入/淡出单段与完全显示的基准时长，实际时长再乘以节奏缩放 _banner_pace。
## 节奏由"上一次横幅是否已演完"判断——没演完就又换人说明切得快，本次动画相应缩短，
## 避免"实际已轮到下一名玩家、横幅还停在上一名玩家"；不依赖绝对时间，固定帧率跑测试也不会脱节。
const BANNER_FADE_BASE := 0.22
const BANNER_HOLD_BASE := TURN_ENTRY_SECONDS + TURN_READ_SECONDS
## 节奏缩放上下限：切得越快缩得越小（但不至于几乎看不见），节奏慢下来后逐步回到 1.0
const BANNER_PACE_MIN := 0.35
const BANNER_PACE_MAX := 1.0
## 阶段更迭横幅：淡入/淡出与保持时长（阶段切换节奏固定，不像行动者横幅那样随切人速度）
const PHASE_BANNER_FADE := 0.28
const PHASE_BANNER_HOLD := 0.70
## 战斗胜利播报：全屏遮罩的入场/确认节奏（UI 表现节奏，非规则数字）
const BROADCAST_BACKDROP_FADE := 0.30   # 遮罩淡入
const BROADCAST_TITLE_SECONDS := 0.55   # 标题缩放回弹入场
const BROADCAST_CARD_STEP := 0.18       # 每个战场块淡入单段时长
const BROADCAST_AI_CONFIRM_STEP := 0.28 # AI 玩家逐人确认间隔（让 n/7 可见地累加）
## 换人时金框从旧行动者脱离、平移到新行动者的飞行时长（顿挫：金框先飞，卡片后移）
## 加上传送带 HANDOFF_SLIDE_SECONDS 就是一次换人的总时长；两者一起调，比例保持不变（约 0.65 : 1）。
const GOLD_FRAME_FLY_SECONDS := 0.15
## 换人传送带：整排卡片左移补位的时长（wrap 卡按 0.4 / 0.6 拆成左出与右进两段）。
## 与读条用的 TURN_ENTRY_SECONDS 分开，换人动画可以单独调速而不动行动窗口。
const HANDOFF_SLIDE_SECONDS := 0.23
## 轮次变更：首位下抽/右移/上移的单段时长（下抽、右移、上移各一段）
const ROUND_DROP_SECONDS := 0.30
## 轮次变更：其余玩家向左补位的左移时长
const ROUND_SLIDE_SECONDS := 0.55
## 轮次变更：首位下抽离开顺位横列的纵向下沉量（相对卡高）
const ROUND_DROP_RATIO := 1.15
## 轮次变更：被抽出的首位卡会越过顶栏叠进战区卷轴范围，用这个图层抬到卷轴之上（落位后归零）
const ROUND_LIFTED_Z := 100
## 提示横幅的图层：要压过被抽出的卡片，避免卡片平移经过时盖住"XX 的行动"
const BANNER_Z := 120


## 卷轴出牌区：所有比例都相对"卡高"，随可用区域与牌数动态求解，不写死某个牌数
const PLAYED_CARD_MIN_H := 46.0     ## 最小可读卡高，低于此值改用局部滚动
## 装箱不可行的哨兵行数：单组超宽时返回它，二分据此继续缩小卡尺寸
const PACKED_ROWS_IMPOSSIBLE := 1 << 20
const PLAYED_AVATAR_W_RATIO := 0.66 ## 头像宽 / 卡高
## 一排同时显示的最大牌数：更长的排靠横向滚动查看
const PLAYED_ROW_CARD_CAP := 5
## 出牌区在卷轴内的右侧/底部留白（推导可用矩形用）
const PLAYED_AREA_RIGHT_PAD := 8.0
## 出牌区内容的内边距：别贴着面板/卷轴边缘
const PLAYED_AREA_PADDING := 20.0
const PLAYED_AREA_BOTTOM_PAD := 8.0
## 头像与牌之间的间距 / 卡高（威力图标叠在头像角落，不靠加间距让位）
const PLAYED_SIDE_GAP_RATIO := 0.14
## 牌与头像/徽章之间的间距下限（像素）：卡缩小时比例值只剩几像素，看着像牌压住了头像
const PLAYED_SIDE_GAP_MIN := 26.0

## 威力徽章在头像右下角的内收位移比例（相对徽章直径）：
## 取 1.0 表示徽章右/下缘与头像右/下缘齐平，不再向外探出
const POWER_BADGE_INSET_RATIO := 0.98
const PLAYED_CARD_GAP_RATIO := 0.10 ## 牌与牌之间的间距 / 卡高
## 淡入/完全显示时序 + 帧率耗时诊断日志。定位问题时改 true 即可拿到
## [FADE]/[GAP]/[PERF] 三类日志；平时保持 false，省掉每帧累加与打印
var _fade_debug := false
var _groups_cache: Array = []
var _groups_frame := -1
var _fps_t := 0.0
var _fps_frames := 0
var _proc_us_sum := 0
var _proc_n := 0
const PLAYED_ROW_GAP_RATIO := 0.14  ## 排与排之间的间距 / 卡高
const PLAYED_DECO_H_RATIO := 0.42   ## 装饰承接条高度 / 卡高
const FLY_SECONDS := 0.42        ## 单张牌的入场飞行时长
const FLY_INTERVAL := 0.08       ## 相邻两张之间的间隔
## 组/头像的淡入时长：比飞行慢一些，太短会像"瞬间出现"
const FADE_SECONDS := 1.2
const FLY_START_SCALE := 0.62    ## 起飞时的缩放
const PLAYED_AREA_MARGIN := 14.0    ## 出牌区四周设计边距
const PLAYED_AREA_TOP := 96.0       ## 标题带下缘（避免压住战区标题）
const BREATH_PERIOD := 1.8
const BREATH_MIN_ALPHA := 0.6

var _local_player_id: int = -1
var _main_area_index: int = -1
## 本地玩家本局是否已【真名解放】：技能区牌的卡面是否已向其他玩家公开，由它决定未公开遮罩。
## 每次绑定手牌/技能区时刷新一次，避免每张牌各自去查一遍事实日志。
var _local_true_name_released := false
## 当前放大卡图对应的展示位：鼠标移到卡图上时用它调出右键说明
var _hover_zoom_source: Control = null
var _zoom_hide_remaining := -1.0
## 悬浮停留计时：记录当前停留的展示位与已累计时长
var _zoom_hover_candidate_id := 0
var _zoom_hover_elapsed := 0.0
var _desc_source_id := 0
var _scroll_tween: Tween
var _scroll_leave_time := 0.0
var _refresh_accum: float = 0.0
## 正在呼吸的描边节点；每次整屏刷新会随克隆体一起释放，所以刷新时清空重收集
var _breathing: Array = []
var _selected_cards: Array = []
var _submitting := false
var _portrait_textures: Dictionary = {}
var _hand_drawer_open := 0.0

@onready var _tpl: Control = $Templates
@onready var _top: Control = $Top
@onready var _rivals: HBoxContainer = $Rivals
@onready var _situation: Control = $Situation
@onready var _piles: Control = $Piles
@onready var _route: Control = $Route
@onready var _events: Control = $Events
@onready var _main: Control = $Main
@onready var _seats: Control = $Seats
@onready var _strips: Control = $Strips
@onready var _hint: Control = $Hint
@onready var _banner: Control = $Banner
@onready var _self: Control = $Self
@onready var _master: Control = $Master
@onready var _hand: Control = $Hand
@onready var _ops: Control = $Ops
@onready var _board: Control = $Board
@onready var _toast: Control = $Toast
## 模块集中开关：以下功能默认关闭，需要打开时手动置 true
var enable_old_features := false
var _ai_cooldown := 0.0
var _ai_acting := false
var _ai_acting_for_id: int = -1
var _ui_refresh_accum: float = 0.0
var _ai_play_prompt_player_id: int = -1
var _ai_play_prompt_card = null
var _ai_play_prompt_round: int = -1
var _ai_play_prompt_node: Button = null
var _current_waiting_effect: BaseEffect = null
var _game_over_shown := false
## 打牌入场动画：逐张从来源飞向卷轴出牌区
var _fly_layer: Control = null
## 出牌区当前统一卡尺寸：在途飞牌每帧跟随它，飞行途中尺寸再变也有过渡
var _play_card_target_size := Vector2.ZERO
var _fly_armed := false          ## 首次刷新只登记不飞，避免进界面时已有牌乱飞
## 飞行队列按战场分组：每个战场一条队列、一个飞行泵，互不阻塞、并行计时。
## 其他战场的牌也照常推进（飞牌不可见但 tween 实时跑），切过去时时间到的牌已落位。
var _fly_queues: Dictionary = {}  ## strip_idx(int) -> Array[Dictionary{slot,card,pid}]
var _fly_busy: Dictionary = {}    ## strip_idx(int) -> bool（该战场的飞行泵是否在跑）
var _takeoff_done: Dictionary = {}
var _debug_console = null
var _debug_console_enabled_on_start := false
var _hovered_event_card: Control = null
var _modal_blockers: Array[Control] = []
var _dragging_modal: Control = null
var _selected_opponent: Control = null
var _selected_opponent_id: int = -1
var _rival_order_snapshot: Array = []
var _rival_shift_tween: Tween
var _rival_wrap_tweens: Array[Tween] = []
## 上次刷新时的回合号：回合号变化即"轮次变更"，不变而行动者变化即"换人交接"
var _last_round: int = -1
## 换人时独立飞行的金框覆盖层（不附着在任何玩家卡上，飞行结束即隐藏）
var _gold_frame_node: Panel = null
## 金框飞行 tween：快速换人时新飞行先 kill 掉上一次，避免两个 tween 抢改同一覆盖层
var _gold_frame_tween: Tween = null
## 顺位动画代际：每次换人/轮次变更递增，过期的异步动画在 await 后自行中止，避免并发污染
var _rival_anim_generation: int = 0
## 顺位动画（金框飞行/传送带/轮次更迭）是否仍在播放：播放期间冻结行动读条。
## 否则 TURN_ENTRY_SECONDS+TURN_READ_SECONDS（0.95s）会先于约 2 秒的轮次动画走完，
## AI 在动画中途就行动、新的换人动画把轮次动画顶掉，卡片停在中间态。
var _rival_anim_busy: bool = false
## 换人金框尚未落位时，刷新不能提前亮起该玩家的卡片
var _pending_rival_highlight_id: int = -1
var _banner_actor_id: int = -1
var _banner_initialized := false
var _banner_tween: Tween
## 横幅节奏缩放：上一次横幅没演完就又切人了就调小（动画缩短），演完了慢慢回到 1.0
var _banner_pace: float = 1.0
## 上一次绑定的阶段下标：变了就播阶段更迭横幅（首次进入第 0 阶段不播）
var _last_phase_index: int = -1
## 阶段更迭横幅播放期间冻结行动
var _phase_anim_busy: bool = false
## 阶段横幅独立素材（不复用行动者 Banner），懒创建
var _phase_banner: Control = null
var _phase_banner_label: Label = null
var _phase_line_left: ColorRect = null
var _phase_line_right: ColorRect = null
var _phase_tween: Tween = null
var _turn_presentation_key: Array = []
var _turn_read_remaining := 0.0
## 战斗胜利播报：结算后弹出的全屏遮罩层状态
var _broadcast_registered := false
var _broadcast_node: Control = null
var _broadcast_active := false
var _broadcast_reveal_done := false
var _broadcast_ai_queue: Array = []
var _broadcast_ai_timer := 0.0
var _broadcast_avatar_mat: ShaderMaterial = null
var _broadcast_font_regular: Font = null
var _broadcast_font_bold: Font = null
var _broadcast_reveal_tween: Tween = null





const EVENT_STACK_TOP := 28.0           ## 事件牌堆展开态上缘距战区上边缘的留白（事件多时按混战区位置回推）
const EVENT_STACK_STEP := 6.0           ## 相邻事件牌的纵向错位
const EVENT_STACK_SCALE := 3.5          ## 事件牌展开态的放大倍数
const EVENT_STACK_GAP := 16.0           ## 事件牌堆与混战区之间保留的空隙
const ZOOM_PREVIEW_HEIGHT := 460.0
const ZOOM_PREVIEW_MAX_WIDTH := 760.0
const ZOOM_KEEPALIVE_SECONDS := 0.18       ## 从源卡移向预览时跨过间隙的保活时间
const ZOOM_HOVER_DELAY_SECONDS := 0.45     ## 悬浮停留多久才弹放大图，短暂划过不触发
const TacticalBoardUI = preload("res://assets/scripts/game_scene/tactical_board_ui.gd")

@onready var _tactical_confirm: Control = $ModalLayer/TacticalConfirm
@onready var _effect_modal: Control = $ModalLayer/EffectChoice
@onready var _effect_result_modal: Control = $ModalLayer/EffectResult
@onready var _hover_zoom: Control = $ModalLayer/HoverZoom
@onready var _hover_desc: Control = $ModalLayer/HoverDesc
@onready var _card_select_panel: Control = $ModalLayer/CardSelect
@onready var _player_select_panel: Control = $ModalLayer/PlayerSelect
@onready var _opponent_drawer: Control = $ModalLayer/OpponentDrawer
@onready var _power_tooltip: Control = $ModalLayer/PowerTooltip


func _ready() -> void:
	_local_player_id = GameData.player_id
	if !GameStart._started:
		GameStart.game_start([0, 1, 2, 3, 4, 5, 6])
	# 原主图作为各卷轴的内容模板；所有地图初始收起。
	_main.hide()
	_events.hide()
	_seats.hide()
	_top.get_node("BoardButton").pressed.connect(func() -> void:
		_board.visible = not _board.visible
		_bind_board()
	)
	# 行动横幅是提示层：它排在卷轴之前会被卷轴里的出牌区盖住（牌压住横幅头像）。
	# 提到最后一位保证横幅在上，同时忽略鼠标，避免它吃掉底下的地图点击
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	move_child(_banner, get_child_count() - 1)
	# 轮次变更时被抽出的卡会抬到卷轴之上，横幅要再高一层才不会被它平移时盖住
	_banner.z_index = BANNER_Z
	_ops.get_node("EndButton").pressed.connect(_on_end_phase_pressed)
	_ops.get_node("PlayButton").pressed.connect(_confirm_held_cards)
	_top.get_node("LogButton").pressed.connect(_open_game_log)
	$LogBrowser/Panel/Close.pressed.connect(func() -> void: $LogBrowser.hide())
	_piles.get_node("EventPile/Open").pressed.connect(func() -> void:
		$EventDiscardMenu.visible = not $EventDiscardMenu.visible
	)
	for entry in [["Shinto", "新都", MapData.shinto], ["Miyama", "深山町", MapData.miyama], ["Other", "其他", null]]:
		$EventDiscardMenu.get_node("Choices/" + entry[0]).pressed.connect(_open_event_discard.bind(entry[1], entry[2]))
	$CardBrowser/Panel/Close.pressed.connect(func() -> void: $CardBrowser.hide())
	# ModalLayer 弹窗接线（用旧控制器的同源判据，规则不变）
	if _tactical_confirm != null:
		var btn_ok := _tactical_confirm.get_node_or_null("Box/ButtonsRow/BtnConfirmAction") as Button
		if btn_ok and not btn_ok.pressed.is_connected(_on_tactical_confirm_execute):
			btn_ok.pressed.connect(_on_tactical_confirm_execute)
		var btn_cancel := _tactical_confirm.get_node_or_null("Box/ButtonsRow/BtnCancelAction") as Button
		if btn_cancel and not btn_cancel.pressed.is_connected(_on_tactical_confirm_cancel):
			btn_cancel.pressed.connect(_on_tactical_confirm_cancel)
	if _effect_modal != null:
		var btn_conf := _effect_modal.get_node_or_null("Box/ButtonsRow/BtnConfirm") as Button
		if btn_conf and not btn_conf.pressed.is_connected(_on_effect_modal_confirm):
			btn_conf.pressed.connect(_on_effect_modal_confirm)
		var btn_x := _effect_modal.get_node_or_null("Box/ButtonsRow/BtnCancel") as Button
		if btn_x and not btn_x.pressed.is_connected(_on_effect_modal_cancel):
			btn_x.pressed.connect(_on_effect_modal_cancel)
	if _effect_result_modal != null:
		var btn_close := _effect_result_modal.get_node_or_null("Box/BtnClose") as Button
		if btn_close and not btn_close.pressed.is_connected(_on_effect_result_closed):
			btn_close.pressed.connect(_on_effect_result_closed)
	if _card_select_panel != null:
		var btn_cs_ok := _card_select_panel.get_node_or_null("Box/ButtonsRow/BtnConfirmSelect") as Button
		if btn_cs_ok and not btn_cs_ok.pressed.is_connected(_on_card_select_confirmed):
			btn_cs_ok.pressed.connect(_on_card_select_confirmed)
		var btn_cs_cancel := _card_select_panel.get_node_or_null("Box/ButtonsRow/BtnCancelSelect") as Button
		if btn_cs_cancel and not btn_cs_cancel.pressed.is_connected(_on_card_select_cancelled):
			btn_cs_cancel.pressed.connect(_on_card_select_cancelled)
	if _opponent_drawer != null:
		var btn_od := _opponent_drawer.get_node_or_null("VBox/HeaderBar/BtnCloseOppDrawer") as Button
		if btn_od and not btn_od.pressed.is_connected(_on_close_opponent_drawer_pressed):
			btn_od.pressed.connect(_on_close_opponent_drawer_pressed)
	if _hover_zoom != null:
		# 放大卡图自身接收右键显示说明，并按保活窗口决定何时收起
		_hover_zoom.gui_input.connect(_on_hover_zoom_gui_input)
	_hover_desc.get_node("Close").pressed.connect(_close_card_desc)
	if _board != null:
		_board.visible = false
	# 打牌动画层：满屏、不吃鼠标，压在手牌之上、弹窗之下
	_fly_layer = Control.new()
	_fly_layer.name = "FlyLayer"
	_fly_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fly_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fly_layer)
	move_child(_fly_layer, _hand.get_index() + 1)
	set_debug_console_enabled(_debug_console_enabled_on_start)
	refresh_all_ui()
	_select_scroll(_default_area_index())


func _exit_tree() -> void:
	if _broadcast_registered:
		GameProgress.unregister_battle_broadcast_consumer(self)
		_broadcast_registered = false


func _open_game_log() -> void:
	var lines := PackedStringArray()
	var battle_res: Dictionary = GameProgress.last_battle_result if GameProgress else {}
	lines.append_array(_battle_result_lines(battle_res, "══ 本次战斗结算 ══"))
	if not lines.is_empty():
		lines.append("")
	lines.append("══ 对局历史日志 ══")
	var logs: Array = GameLog.query({}, null, -1)
	for i in range(logs.size() - 1, -1, -1):
		var line: String = _format_game_log_line(logs[i])
		if not line.is_empty():
			lines.append(line)
	$LogBrowser/Panel/Entries.text = "\n\n".join(lines)
	$LogBrowser/Panel/Entries.scroll_to_line(0)
	$EventDiscardMenu.hide()
	$LogBrowser.show()


func _default_area_index() -> int:
	var area := _player_area(_local_player_id)
	return MapData.areas.find(area if area != null else MapData.magic_workshop)


func _process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_update_fly_sizes(delta)
	#首次运行本帧循环即登记为胜利播报消费者：被动实例化（测试里 set_process(false)）不走到这里，
	#也就不会在战斗结算后阻塞推进。
	if not _broadcast_registered:
		_broadcast_registered = true
		GameProgress.register_battle_broadcast_consumer(self)
	# 帧率/耗时诊断（定位完可关）：_fade_debug 为假时整段不累加、不打印
	if _fade_debug:
		_fps_t += delta
		_fps_frames += 1
	if _fade_debug and _fps_t >= 2.0:
		print("[PERF] fps=", snappedf(float(_fps_frames) / _fps_t, 0.1),
			" groups=", _play_group_nodes().size(),
			" process_us=", _proc_us_sum / maxi(1, _proc_n),
			" t=", snappedf(Time.get_ticks_msec() / 1000.0, 0.01))
		_fps_t = 0.0
		_fps_frames = 0
		_proc_us_sum = 0
		_proc_n = 0
	_update_power_badges()
	_update_hover_zoom_keepalive(delta)
	if _main_area_index >= 0:
		var scroll := _strips.get_child(_main_area_index) as Control
		var over_seats := false
		for row_name in ["MeleeScroll", "SeatScroll"]:
			var row := scroll.get_node("Seats/" + row_name) as Control
			over_seats = over_seats or (row.visible and row.get_global_rect().has_point(get_global_mouse_position()))
		if scroll.get_global_rect().has_point(get_global_mouse_position()) or over_seats:
			_scroll_leave_time = 0.0
		else:
			_scroll_leave_time += delta
			if _scroll_leave_time >= SCROLL_LEAVE_SECONDS and not _scroll_is_animating():
				_select_scroll(_default_area_index())
	elif not _scroll_is_animating():
		_select_scroll(_default_area_index())
	_refresh_accum += delta
	if _refresh_accum >= REFRESH_INTERVAL:
		_refresh_accum = 0.0
		refresh_all_ui()
	_update_held_cards(delta)
	# 呼吸相位取全局时间，重建节点也不会跳变
	# 等待输入 / AI 推进 / 消息 / 战报 / 终局都在这里跑
	_process_waiting_inputs(delta)
	_update_turn_presentation(delta)
	_update_battle_broadcast(delta)
	if _turn_read_remaining <= 0.0 and not _rival_anim_busy and not _phase_anim_busy:
		_check_and_step_ai(delta)
	_check_game_over()
	_update_ai_play_prompt_geometry()
	if _board.visible:
		_refresh_opponent_resource_icons()
	
	var alpha := BREATH_MIN_ALPHA + (1.0 - BREATH_MIN_ALPHA) * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU / BREATH_PERIOD))
	for frame in _breathing:
		if is_instance_valid(frame):
			frame.modulate.a = alpha
	# 测完整 _process 耗时（之前只在 _update_fly_sizes 后累加，测到的几乎为空，
	# 后半段重活全漏掉了，导致误判"逻辑不耗时"）
	if _fade_debug:
		_proc_us_sum += Time.get_ticks_usec() - _t0
		_proc_n += 1


func refresh_all_ui() -> void:
	if !GameData.player_data_library.has(_local_player_id):
		return
	var key := [GameProgress.current_round, GameProgress.current_phase_index, GameProgress.current_player_id]
	if key != _turn_presentation_key:
		_turn_read_remaining = TURN_ENTRY_SECONDS + TURN_READ_SECONDS if GameProgress.current_player_id >= 0 else 0.0
		_turn_presentation_key = key
	_main_area_index = clampi(_main_area_index, -1, MapData.areas.size() - 1)
	_breathing.clear()
	# 阶段更迭：先播提示横幅，动画期间冻结行动（首次进入第 0 阶段不播）
	if GameProgress.current_phase_index != _last_phase_index:
		var first_phase := _last_phase_index < 0
		_last_phase_index = GameProgress.current_phase_index
		if not first_phase and GameProgress.current_phase_index >= 0:
			_show_phase_banner(GameProgress.current_phase_index)
	_bind_top()
	_bind_rivals()
	_bind_situation_and_piles()
	_bind_strips()
	_bind_hint()
	_bind_self()
	_bind_master()
	_bind_hand()
	_bind_ops()
	_bind_board()


## ---------- 数据读取（全部走引擎，界面不自己判规则） ----------

func _pl(id: int) -> Dictionary:
	return GameDataManager.get_player_data(id) if GameData.player_data_library.has(id) else {}


func _num(v) -> int:
	if v is BaseNumber:
		return int(v.number)
	if v is int or v is float:
		return int(v)
	return 0


func _shown(obj) -> String:
	if obj == null:
		return ""
	if obj.has_method("get_shown_name"):
		var s := str(obj.get_shown_name())
		if s != "":
			return s
	var n = obj.get("_name")
	return str(n) if n != null else ""


func _player_name(id: int) -> String:
	var shown := _shown(_pl(id).get("master"))
	return shown if shown != "" else "玩家 %d" % id


func _player_location(id: int) -> BaseLocation:
	var loc = _pl(id).get("location")
	return loc if loc is BaseLocation else null


func _player_area(id: int) -> BaseMapArea:
	var loc := _player_location(id)
	return loc.get_from() as BaseMapArea if loc != null else null


func _ordered_ids() -> Array:
	var ids: Array = []
	for id in EffectManager.get_player_order_ids():
		ids.append(int(id))
	return ids


func _score_sorted_ids() -> Array:
	var ids := _ordered_ids()
	ids.sort_custom(func(a, b): return _num(_pl(a).get("score")) > _num(_pl(b).get("score")))
	return ids


func _players_in_area(area: BaseMapArea) -> Array:
	return _ordered_ids().filter(func(id): return _player_area(id) == area)


func _area_score(area: BaseMapArea) -> int:
	var total := _num(area._score)
	for ev in area._events:
		if ev is BaseEvent and not bool(ev.get("_is_concealed")):
			total += _num(ev._score)
	return total


func _area_events(area: BaseMapArea) -> Array:
	return area._events.filter(func(e): return e is BaseEvent)


func _servant_class(id: int) -> String:
	var servant = _pl(id).get("servant")
	return str(servant.get("_servant_class")).capitalize() if servant != null else ""


func _class_shown(id: int) -> String:
	return (_servant_class(id) if ReleaseTrueName.is_released(id) else "???").to_upper()


func _header_img(id: int) -> String:
	var master = _pl(id).get("master")
	return str(master.get("_header_img")) if master != null else ""


func _is_acting(id: int) -> bool:
	return GameProgress.current_player_id == id


func _phase_name() -> String:
	return str(GameProgress.get_current_phase().get("name", ""))


func _phase_cn(key: String) -> String:
	return str(PHASE_NAMES.get(key, key))


func _climax_rounds() -> Array:
	return LoadSituation.climax_situations.keys()


func _area_image(index: int) -> String:
	return str(AREA_IMAGES[index]) if index >= 0 and index < AREA_IMAGES.size() else ""


func _back(type_name: String) -> String:
	return LoadHelper.resolve_card_back("", "", type_name)


## 玩家所在战区与席位：战区名 + 地利/魔力席/混战区
func _seat_summary(id: int, sep := " · ") -> String:
	var area := _player_area(id)
	if area == null:
		return "未部署"
	var loc := _player_location(id)
	var parts := [str(area._area_name)]
	if loc != null:
		parts.append(_seat_kind(loc, true))
	return sep.join(parts)


## 席位类别文案：混战区 / 魔力席(+N) / 地利 N / 席位
func _seat_kind(loc: BaseLocation, with_magic_value: bool) -> String:
	if loc._pl_num_limit < 0:
		return "混战区"
	if _num(loc._magic) > 0:
		return "魔力席 +%d" % _num(loc._magic) if with_magic_value else "魔力席"
	if _num(loc._benefit) > 0:
		return "地利 %d" % _num(loc._benefit)
	return "席位"


## 左侧手牌（技能区 + 御主牌 + 附带物 + 升华技）按类别分组，同名附带物合并成叠数
func _zone_hand_entries(pl: Dictionary) -> Array:
	var entries: Array = []
	var seen: Array = []
	var push := func(cards, kind: String, merge: bool):
		if not cards is Array:
			return
		var merged: Dictionary = {}
		for card in cards:
			if card == null or seen.has(card) or not (card is BaseHandCard or card is BaseCard):
				continue
			seen.append(card)
			if merge:
				var key := str(card.get("_name"))
				if merged.has(key):
					merged[key]["count"] += 1
					continue
				merged[key] = {"card": card, "kind": kind, "count": 1}
				entries.append(merged[key])
			else:
				entries.append({"card": card, "kind": kind, "count": 1})
	push.call(pl.get("servant_skills", []), "从者技能", false)
	var side_skills = pl.get("side", {}).get("skills", [])
	for card in side_skills:
		if not card is BaseCard:
			continue
		var source = card.get_from()
		var kind := "从者技能" if source == pl.get("servant") else "御主牌" if source == pl.get("master") else "技能牌"
		push.call([card], kind, false)
	push.call(pl.get("master_skills", []), "御主牌", false)
	var master = pl.get("master")
	if master != null:
		var sp = master.get("_specials")
		if sp is Dictionary:
			push.call(sp.get("SKILLS", []), "御主牌", false)
			push.call(sp.get("ATTACKS", []), "御主牌", false)
		push.call(master.get("_other_things"), "御主附加", false)
		push.call(master.get("_upgrade_skill"), "升华技", false)
	var removed: Array = []
	var zone: Dictionary = pl.get("out_of_game", {})
	for key in ["attacks", "skills", "others"]:
		for card in zone.get(key, []):
			removed.append(card)
	for key in ["hand_cards", "deck", "discard", "played_cards"]:
		removed.append_array(pl.get(key, []))
	return entries.filter(func(e): return not removed.has(e["card"]))


## ---------- 通用绑定原语 ----------

## 从 Templates 复制一份模板并挂到 parent；复制体可见
func _spawn(template: String, parent: Node) -> Control:
	var node := _tpl.get_node(template).duplicate() as Control
	node.visible = true
	parent.add_child(node)
	return node


## 清空容器（保留名字在 keep 里的常驻子节点）。
## 先摘下再 queue_free：刷新可能由被清理节点自己的信号（如竖条 mouse_entered）触发，立即 free 会出错
func _clear(parent: Node, keep: Array = []) -> void:
	for child in parent.get_children():
		if keep.has(child.name):
			continue
		parent.remove_child(child)
		child.queue_free()


## 取 meta 的安全写法：`get_meta(key, null)` 在键不存在时照样报错
## （null 会被当成"没传默认值"），所以统一用 has_meta 兜一层
func _meta_or(obj: Object, key: String, fallback):
	return obj.get_meta(key) if obj.has_meta(key) else fallback


func _set_text(root: Node, path: String, text: String) -> void:
	(root.get_node(path) as Label).text = text


func _set_img(root: Node, path: String, img: String) -> void:
	var tex := root.get_node(path) as TextureRect
	tex.texture = LoadHelper.load_texture(img) if img != "" and LoadHelper.texture_exists(img) else null


func _set_variation(node: Control, variation: String) -> void:
	node.theme_type_variation = variation


## 流动提示框：把控件矩形尺寸转给着色器。着色器按本地像素算周长，拿不到节点尺寸，
## 布局变化（战区展开/收起）后必须重设；rect 传 ZERO 时用节点自身尺寸。
func _bind_flow_border(node: Control, rect := Vector2.ZERO) -> void:
	var mat := node.material as ShaderMaterial
	if mat == null:
		return
	# 模板复制出的多个提示框共享同一个材质资源，必须各自持有实例，
	# 否则后写入的尺寸会覆盖其它控件（实测：展开的战区会按收起竖条的尺寸算周长）
	if not node.has_meta("flow_border_own_mat"):
		node.set_meta("flow_border_own_mat", true)
		mat = mat.duplicate() as ShaderMaterial
		node.material = mat
	mat.set_shader_parameter("rect_size", rect if rect != Vector2.ZERO else node.size)
	if not node.has_meta("flow_border_bound"):
		node.set_meta("flow_border_bound", true)
		node.resized.connect(_bind_flow_border.bind(node))


## 头像模板节点：填图 + 切环色变体
func _bind_avatar(node: Control, img: String, variation := "") -> void:
	_set_img(node, "Img", img)
	if variation != "":
		_set_variation(node, variation)


## 卡片模板节点：填图，可压暗
func _bind_card(node: Control, img: String, dim := 1.0) -> void:
	_set_img(node, "Img", img)
	(node.get_node("Img") as Control).modulate = Color(dim, dim, dim)


func _bind_badge(node: Control, text: String, variation := "") -> void:
	_set_text(node, "Label", text)
	if variation != "":
		_set_variation(node, variation)
	node.visible = true


## 魔力条：Fill 按比例拉宽，Threshold 可选门槛位置
func _bind_bar(bar: Control, ratio: float, threshold := -1.0) -> void:
	var fill := bar.get_node("Fill") as Control
	fill.anchor_right = clampf(ratio, 0.0, 1.0)
	if bar.has_node("Threshold") and threshold >= 0.0:
		var th := bar.get_node("Threshold") as Control
		th.anchor_left = clampf(threshold, 0.0, 1.0)
		th.anchor_right = th.anchor_left


## 令咒纹一排：已持有的亮、用掉的暗
func _bind_sigils(row: HBoxContainer, count: int, limit: int) -> void:
	_clear(row)
	for i in range(maxi(limit, count)):
		var icon := _spawn("Sigil", row)
		icon.modulate.a = 1.0 if i < count else 0.3


## 呼吸描边：登记到 _breathing，由 _process 统一按全局相位设透明度
func _breathe(frame: Control) -> void:
	frame.visible = true
	_breathing.append(frame)


## 席位模板（Seat / StripSeat 内的 Seat）：环色、空席数值或占位头像与角标
func _bind_seat(seat: Control, loc: BaseLocation, with_label: bool) -> void:
	var is_mana := _num(loc._magic) > 0
	var benefit := _num(loc._benefit)
	seat.get_node("Ring").mana = is_mana
	var occupants: Array = loc._players
	var val := seat.get_node("ValueNum") as Label
	var empty := seat.get_node("ValueEmpty") as Label
	var avatar := seat.get_node("Avatar") as Control
	var badge := seat.get_node("Badge") as Control
	val.visible = false
	empty.visible = false
	avatar.visible = false
	badge.visible = false
	if occupants.is_empty():
		if is_mana:
			val.text = "+%d" % _num(loc._magic)
			val.theme_type_variation = "Mana"
			val.visible = true
		elif benefit > 0:
			val.text = str(benefit)
			val.theme_type_variation = "Gold2"
			val.visible = true
		else:
			empty.visible = true
	else:
		var pid := int(occupants[0])
		avatar.visible = true
		_bind_avatar(avatar, _header_img(pid), "AvatarMana" if pid == _local_player_id else "AvatarGold2")
		if is_mana:
			_bind_badge(badge, "+%d" % _num(loc._magic), "BadgeMana")
		elif benefit > 0:
			_bind_badge(badge, "地利%d" % benefit, "BadgeGold")
	if with_label:
		_set_text(seat, "Label", _seat_kind(loc, false))


func _say(text: String) -> void:
	_set_text(_toast, "Label", text)
	_toast.visible = true
	var tween := _toast.create_tween()
	tween.tween_interval(TOAST_SECONDS)
	tween.tween_callback(func() -> void: _toast.visible = false)


## ---------- 0 顶栏 ----------

func _bind_top() -> void:
	var center := _top.get_node("Center")
	_set_text(center, "RoundLabel", "第 %d 回合" % GameProgress.current_round)
	var climax := _climax_rounds()
	var total := _num(GameProgress.total_rounds)
	var cur := GameProgress.current_round
	_set_text(center, "NightLabel", "高潮回合" if climax.has(cur) else "夜 %d / %d" % [cur, total])
	# 四阶段标签：来自 GameProgress.phases，当前金底，已过灰亮，未到灰暗
	var phases := center.get_node("Phases")
	_clear(phases)
	var passed := true
	var current := _phase_name()
	for phase in GameProgress.phases:
		var key := str(phase.get("name", ""))
		var on := key == current
		if on:
			passed = false
		var tag := _spawn("PhaseOn" if on else ("PhasePassed" if passed else "PhasePending"), phases)
		_set_text(tag, "Label", "%s阶段" % _phase_cn(key))
	# 夜点阵：总数与高潮回合读数据
	var dots := center.get_node("Dots")
	_clear(dots)
	for i in range(1, total + 1):
		var dot := _spawn("Dot", dots)
		var is_climax: bool = climax.has(i)
		if i < cur:
			_set_variation(dot, "DotClimaxPassed" if is_climax else "DotPassed")
		elif i == cur:
			_set_variation(dot, "DotCurrent")
		else:
			_set_variation(dot, "DotClimaxPending" if is_climax else "DotPending")


## ---------- 1 顺位横列 ----------

func _bind_rivals() -> void:
	var actual_ids := _ordered_ids()
	var ids := actual_ids.duplicate()
	# 从行动者起循环展示真实顺位：已行动者回到队尾，不改规则顺位和编号。
	var actor := GameProgress.current_player_id
	var actor_index := ids.find(actor)
	if actor_index > 0:
		ids = ids.slice(actor_index) + ids.slice(0, actor_index)
	var old_positions: Dictionary = {}
	var order_changed := not _rival_order_snapshot.is_empty() and ids != _rival_order_snapshot
	# 轮次变更：回合号变化。换人交接：回合号不变、仅行动者变化。首次绑定两者都不触发。
	var round_changed := _last_round != -1 and GameProgress.current_round != _last_round
	if order_changed:
		_rival_anim_generation += 1
		_pending_rival_highlight_id = -1 if round_changed else actor
		if _gold_frame_node != null:
			_gold_frame_node.visible = false
		if _rival_shift_tween != null:
			_rival_shift_tween.kill()
		if _gold_frame_tween != null and _gold_frame_tween.is_running():
			_gold_frame_tween.kill()
		for tween in _rival_wrap_tweens:
			if tween.is_running():
				tween.kill()
		_rival_wrap_tweens.clear()
		for child in _rivals.get_children():
			old_positions[int(child.get_meta("turn_order_player_id", -1))] = (child as Control).global_position
	var previous_ids := _rival_order_snapshot.duplicate()
	var existing: Dictionary = {}
	for child in _rivals.get_children():
		var id: int = int(child.get_meta("turn_order_player_id", -1))
		var is_self: bool = bool(child.get_meta("self_slot", false))
		if ids.has(id) and is_self == (id == _local_player_id):
			existing[id] = child
		else:
			_rivals.remove_child(child)
			child.queue_free()
	var order := 0
	for id in ids:
		order += 1
		if id == _local_player_id:
			var slot: Control = existing.get(id)
			if slot == null:
				slot = _spawn("SelfSlot", _rivals)
				slot.set_meta("turn_order_player_id", id)
				slot.set_meta("self_slot", true)
			if slot.get_index() != order - 1:
				_rivals.move_child(slot, order - 1)
			_set_text(slot, "Order/Label", str(actual_ids.find(id) + 1))
			# 轮到自己时与其它玩家用同一套高亮；换人交接期间先不亮，等金框飞到再亮
			_set_acting_highlight(slot, _is_acting(id) and id != _pending_rival_highlight_id)
			continue
		var pl := _pl(id)
		var acting := _is_acting(id)
		var card: Control = existing.get(id)
		if card == null:
			card = _spawn("RivalCard", _rivals)
			card.set_meta("turn_order_player_id", id)
			card.mouse_filter = Control.MOUSE_FILTER_STOP
			for sub in card.find_children("*", "Control", true, false):
				(sub as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.gui_input.connect(_on_opponent_gui_input.bind(card))
		if card.get_index() != order - 1:
			_rivals.move_child(card, order - 1)
		card.modulate = Color(0.6, 0.6, 0.6, 0.45) if bool(pl.get("is_out", false)) else Color.WHITE
		# 飞行阶段（包括周期刷新）目标玩家保持未亮
		_set_acting_highlight(card, acting and id != _pending_rival_highlight_id)
		_set_text(card, "Order/Label", str(actual_ids.find(id) + 1))
		_bind_avatar(card.get_node("Avatar"), _header_img(id))
		_set_text(card, "Name", _player_name(id))
		_set_text(card, "Class", _class_shown(id))
		_set_text(card, "Loc", _seat_summary(id))
		var magic := _num(pl.get("magic"))
		var limit := _num(GameData.player_magic_limit(id))
		_set_text(card, "MagicNum", "%d/%d" % [magic, limit])
		_bind_bar(card.get_node("MagicBar"), float(magic) / maxf(1.0, float(limit)))
		_set_text(card, "Stats/PowerStat/V", str(int(GetPlayerTotalPower.breakdown(id).get("total", 0))))
		_set_text(card, "Stats/ScoreStat/V", str(_num(pl.get("score"))))
		_bind_sigils(card.get_node("Stats/Spells"), _num(pl.get("command_spell_count")), _num(pl.get("command_spell_limit")))
	_rival_order_snapshot = ids.duplicate()
	# move_child 会让 HBoxContainer 在本次布局里立刻把卡片排到新顺序的位置，而动画的 _pin_cards_to
	# 要等下一帧才执行——中间那一帧整排卡片提前跳到位，就是"所有玩家信息一瞬间的错位"。
	# HBoxContainer 的排序走 MessageQueue（idle flush），这里用 call_deferred 把钉位置排在排序之后。
	if order_changed:
		call_deferred("_pin_cards_to", old_positions)
	if round_changed:
		_rival_anim_busy = true
		_animate_round_change(old_positions, ids.duplicate(), previous_ids)
	elif order_changed:
		_rival_anim_busy = true
		_animate_actor_handoff(old_positions, ids.duplicate(), previous_ids)
	_last_round = GameProgress.current_round

## 按玩家 id 找顺位横列里的卡片节点
func _rival_card(id: int) -> Control:
	for child in _rivals.get_children():
		if int(child.get_meta("turn_order_player_id", -1)) == id:
			return child as Control
	return null


## 顺位卡的金框（Breath 呼吸框）显隐
func _set_breath_visible(card: Control, visible: bool) -> void:
	if card == null:
		return
	var breath := card.get_node_or_null("Breath") as Control
	if breath != null:
		breath.visible = visible


## 行动高亮：换高亮变体 + 亮/灭呼吸框（我方与对手同一套）。acting=false 时按卡片类型回到静态变体
func _set_acting_highlight(card: Control, acting: bool) -> void:
	if card == null:
		return
	var is_self := bool(card.get_meta("self_slot", false))
	var variation := "RivalActing" if acting else ("SelfSlot" if is_self else "RivalCard")
	if card.theme_type_variation != variation:
		_set_variation(card, variation)
	var breath := card.get_node_or_null("Breath") as Control
	if breath != null:
		breath.visible = acting
		if acting:
			_breathe(breath)


## 换人时独立飞行的金框覆盖层（懒创建，只描边不填充，不附着在任何玩家卡上）
func _gold_frame_overlay() -> Panel:
	if _gold_frame_node == null or not is_instance_valid(_gold_frame_node):
		_gold_frame_node = Panel.new()
		_gold_frame_node.theme_type_variation = "Breath"
		_gold_frame_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_gold_frame_node.visible = false
		add_child(_gold_frame_node)
		# Breath 变体带"阴影色填充"，套在卡片上会把整张牌染成淡金（飞行途中看起来像另一张亮卡在滑动、盖住沿途卡片）。
		# 金框要的是"脱离开的一张空框"：复制它的边框样式，只去掉背景填充与阴影。
		var base := _gold_frame_node.get_theme_stylebox("panel")
		if base is StyleBoxFlat:
			var outline := (base as StyleBoxFlat).duplicate() as StyleBoxFlat
			outline.bg_color = Color(0, 0, 0, 0)
			outline.shadow_size = 0
			_gold_frame_node.add_theme_stylebox_override("panel", outline)
	return _gold_frame_node


## 把旧位置（全局坐标）换算回顺位容器本地坐标并钉到卡片上
func _pin_cards_to(old_positions: Dictionary) -> void:
	var inv := _rivals.get_global_transform().affine_inverse()
	for child in _rivals.get_children():
		var card := child as Control
		var id := int(card.get_meta("turn_order_player_id", -1))
		if old_positions.has(id):
			card.position = inv * (old_positions[id] as Vector2)


## 目标位置：按卡序累加实际宽度与容器间距自行推算（HBoxContainer 默认 BEGIN，与容器排版一致）。
## 不能直接读 child.position：换人那一帧整排卡片已被钉回旧位置（见 _bind_rivals 里的 call_deferred），
## 读到的会是旧位置，传送带就原地不动；且 HBoxContainer 的排版结果也只在排序帧短暂存在。
func _collect_targets(expected_ids: Array) -> Dictionary:
	return _layout_positions(expected_ids)


## 按给定 id 顺序累加卡片实际宽度与容器间距，算出该排列下每张卡的布局 x。
## 动画的中间态卡序与最终态不同，同一序号位置的前置卡宽度也就不同（如末位前面可能是
## 6 张宽卡、也可能夹着一张窄卡），直接把最终态位置套到中间态会把卡放到错误宽度上并互相重叠。
func _layout_positions(ids: Array) -> Dictionary:
	var result: Dictionary = {}
	var sep := float(_rivals.get_theme_constant("separation"))
	var x := 0.0
	for id in ids:
		var card := _rival_card(int(id))
		if card == null:
			continue
		result[int(id)] = Vector2(x, 0.0)
		x += card.size.x + sep
	return result


## 传送带：从当前视觉位置并排左移到目标位置，队首卡左出右进绕到队尾。
## 调用前卡片已钉在旧位置；await 到所有平移完成，供调用方串行。
func _shift_cards(targets: Dictionary, expected_ids: Array, previous_ids: Array, seconds: float) -> void:
	var wrap_count := previous_ids.find(expected_ids[0])
	var cyclic := wrap_count > 0 and previous_ids.size() == expected_ids.size() and targets.size() == expected_ids.size()
	if cyclic:
		cyclic = previous_ids.slice(wrap_count) + previous_ids.slice(0, wrap_count) == expected_ids
	var wrapped: Array = previous_ids.slice(0, wrap_count) if cyclic else []
	var pending: Array = []
	for child in _rivals.get_children():
		var card := child as Control
		var id := int(card.get_meta("turn_order_player_id", -1))
		if not targets.has(id):
			continue
		var target: Vector2 = targets[id]
		if card.position.is_equal_approx(target):
			continue
		if wrapped.has(id):
			# 越过边界的卡单独排队，不从其他玩家信息卡上方穿过。
			var wrap_tween := card.create_tween()
			_rival_wrap_tweens.append(wrap_tween)
			pending.append(wrap_tween)
			wrap_tween.tween_property(card, "position:x", -card.size.x, seconds * 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			wrap_tween.tween_callback(func() -> void: card.position = Vector2(_rivals.size.x, target.y))
			wrap_tween.tween_property(card, "position", target, seconds * 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		else:
			if _rival_shift_tween == null:
				_rival_shift_tween = create_tween().set_parallel(true)
				pending.append(_rival_shift_tween)
			_rival_shift_tween.tween_property(card, "position", target, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	for t in pending:
		if t.is_running():
			await t.finished


## 换人交接：金框先从旧行动者脱离、平移到新行动者原位（顿挫），再播传送带左移。
func _animate_actor_handoff(old_positions: Dictionary, expected_ids: Array, previous_ids: Array) -> void:
	var gen := _rival_anim_generation
	await get_tree().process_frame
	if not is_inside_tree() or _rival_order_snapshot != expected_ids or gen != _rival_anim_generation:
		return
	_rivals.clip_contents = true
	_rival_shift_tween = null
	var targets := _collect_targets(expected_ids)
	_pin_cards_to(old_positions)
	var prev_actor := int(previous_ids[0])
	var next_actor := int(expected_ids[0])
	var prev_card := _rival_card(prev_actor)
	var next_card := _rival_card(next_actor)
	if prev_card != null and next_card != null and prev_card != next_card:
		# 金框飞行期间新行动者先不亮高亮，落位后再亮（顿挫：先金框后高亮）
		_set_acting_highlight(next_card, false)
		var overlay := _gold_frame_overlay()
		overlay.global_position = prev_card.global_position
		overlay.size = prev_card.size
		overlay.visible = true
		_breathe(overlay)
		_gold_frame_tween = overlay.create_tween()
		var fly := _gold_frame_tween
		fly.set_parallel(true)
		fly.tween_property(overlay, "global_position", next_card.global_position, GOLD_FRAME_FLY_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		fly.tween_property(overlay, "size", next_card.size, GOLD_FRAME_FLY_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		await fly.finished
		if gen != _rival_anim_generation or not is_inside_tree():
			return
		overlay.visible = false
		_breathing.erase(overlay)
	# 金框落位（或本就没有跨卡飞行）后，新行动者亮起高亮，并解除刷新对它的压制
	_pending_rival_highlight_id = -1
	_set_acting_highlight(next_card, true)
	await _shift_cards(targets, expected_ids, previous_ids, HANDOFF_SLIDE_SECONDS)
	if gen == _rival_anim_generation:
		_rival_anim_busy = false


## 轮次变更：最后行动者先整体左移回到规则顺位，再由上一回合首位下抽绕到末位。
func _animate_round_change(old_positions: Dictionary, expected_ids: Array, previous_ids: Array) -> void:
	var gen := _rival_anim_generation
	await get_tree().process_frame
	if not is_inside_tree() or _rival_order_snapshot != expected_ids or gen != _rival_anim_generation:
		return
	_rivals.clip_contents = true
	_rival_shift_tween = null
	var targets := _collect_targets(expected_ids)
	_pin_cards_to(old_positions)
	# expected_ids = [B,C,D,A]；上一回合首位 A 落在末位 expected_ids.back()
	var first_of_round := int(expected_ids.back())
	# 阶段1：整体左移补位，最后行动者（previous_ids[0]）绕到队尾 → 回到规则顺位 [A,B,C,D]
	# 中间态卡序与最终态不同，位置要按中间态自身累加宽度算，不能套用最终态的 targets
	var mid_ids: Array = [int(expected_ids.back())] + expected_ids.slice(0, -1)
	var stage1_target := _layout_positions(mid_ids)
	await _shift_cards(stage1_target, mid_ids, previous_ids, TURN_ENTRY_SECONDS)
	if gen != _rival_anim_generation or not is_inside_tree():
		return
	# 阶段2：上一回合首位下抽，其余左移补位，首位从下方绕到末位再上移
	await _drop_first_to_tail(first_of_round, targets)
	if gen == _rival_anim_generation:
		_rival_anim_busy = false


## 轮次变更第二阶段：首位下抽离开横列，其余左移补位，首位从下方绕到末位再上移。
func _drop_first_to_tail(first_id: int, targets: Dictionary) -> void:
	var first_card := _rival_card(first_id)
	if first_card == null or not targets.has(first_id):
		return
	# 下抽/绕到末位的过程中首位要离开顺位横列，先关掉容器裁剪，否则抽出的卡会被裁掉看不见
	_rivals.clip_contents = false
	# 抽出的卡会向下越过顶栏、叠进战区卷轴范围，必须抬到卷轴之上，否则会被战区盖住
	first_card.z_index = ROUND_LIFTED_Z
	var tail: Vector2 = targets[first_id]
	var drop_y := first_card.size.y * ROUND_DROP_RATIO
	# 1) 首位向下抽出，留出空位
	var drop := first_card.create_tween()
	drop.tween_property(first_card, "position:y", drop_y, ROUND_DROP_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await drop.finished
	# 2) 其余玩家向左补位
	var slide: Tween = null
	for child in _rivals.get_children():
		var card := child as Control
		var id := int(card.get_meta("turn_order_player_id", -1))
		if id == first_id or not targets.has(id):
			continue
		if slide == null:
			slide = create_tween().set_parallel(true)
		slide.tween_property(card, "position:x", (targets[id] as Vector2).x, ROUND_SLIDE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if slide != null:
		await slide.finished
	# 3) 首位向右平移到末位下方
	var move_right := first_card.create_tween()
	move_right.tween_property(first_card, "position:x", tail.x, ROUND_DROP_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await move_right.finished
	# 4) 首位平移上去，完成轮次变更
	var move_up := first_card.create_tween()
	move_up.tween_property(first_card, "position:y", 0.0, ROUND_DROP_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await move_up.finished
	# 回到顶栏后撤销图层提升（测试会校验不留高图层）
	first_card.z_index = 0

## 自动推进前逐帧捕获行动窗口，不依赖半秒一次的全屏刷新。
func _update_turn_presentation(delta: float) -> void:
	var key := [GameProgress.current_round, GameProgress.current_phase_index, GameProgress.current_player_id]
	if key != _turn_presentation_key:
		refresh_all_ui()
	elif not _rival_anim_busy and not _phase_anim_busy:
		# 顺位动画 / 阶段横幅播放期间冻结行动读条：动画演完才开始行动
		_turn_read_remaining = maxf(0.0, _turn_read_remaining - delta)

func _set_banner_actor(id: int) -> void:
	_bind_avatar(_banner.get_node("Avatar"), _header_img(id))
	_set_text(_banner, "Text", "%s 的行动" % ("我方" if id == _local_player_id else _player_name(id)))

## 按"上一次横幅是否已演完"调整节奏缩放：没演完就切换说明切得快，缩短本次动画；
## 演完了才切换说明节奏从容，缩放逐步回到 1.0。
func _banner_tick_pace(previous_still_running: bool) -> void:
	_banner_pace = BANNER_PACE_MIN if previous_still_running else BANNER_PACE_MAX


## 横幅淡入/淡出单段时长
func _banner_fade_seconds() -> float:
	return BANNER_FADE_BASE * _banner_pace


## 横幅完全显示的保持时长
func _banner_hold_seconds() -> float:
	return BANNER_HOLD_BASE * _banner_pace


## 横幅原位淡入淡出；交接动作由顶部整张玩家卡承担。
## 行动者一切换就重设内容并从透明淡入，淡出时长按本次切人节奏伸缩：
## 这样实际已经轮到下一名玩家时，屏幕上不会还挂着上一名玩家的横幅。
func _show_banner_actor(id: int) -> void:
	# 上一次横幅还没演完就又切人 → 说明切得快，本次动画相应缩短
	_banner_tick_pace(_banner_tween != null and _banner_tween.is_running())
	if _banner_tween != null:
		_banner_tween.kill()
	_set_banner_actor(id)
	var fade := _banner_fade_seconds()
	var hold := _banner_hold_seconds()
	_banner.show()
	_banner.modulate.a = 0.0
	_banner_tween = _banner.create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, fade)
	_banner_tween.tween_interval(hold)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, fade)
	_banner_tween.tween_callback(_banner.hide)


## 阶段更迭横幅：独立素材——金色描边大字 + 两侧向中间展开的金线，透明背景，懒创建。
func _phase_banner_node() -> Control:
	if _phase_banner != null and is_instance_valid(_phase_banner):
		return _phase_banner
	_phase_banner = Control.new()
	_phase_banner.name = "PhaseBanner"
	_phase_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phase_banner.visible = false
	_phase_banner.z_index = BANNER_Z
	_phase_banner.set_anchors_preset(Control.PRESET_CENTER)
	_phase_banner.position = Vector2(-330, -72)
	_phase_banner.size = Vector2(660, 144)
	var font := (_banner.get_node("Text") as Label).get_theme_font("font")

	_phase_banner_label = Label.new()
	_phase_banner_label.name = "Label"
	_phase_banner_label.position = Vector2(210, 42)
	_phase_banner_label.size = Vector2(240, 60)
	_phase_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_phase_banner_label.add_theme_font_override("font", font)
	_phase_banner_label.add_theme_font_size_override("font_size", 36)
	_phase_banner_label.add_theme_color_override("font_color", Color(0.97, 0.84, 0.46, 1.0))
	_phase_banner_label.add_theme_color_override("font_outline_color", Color(0.28, 0.16, 0.05, 1.0))
	_phase_banner_label.add_theme_constant_override("outline_size", 8)
	_phase_banner_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	_phase_banner_label.add_theme_constant_override("shadow_offset_x", 3)
	_phase_banner_label.add_theme_constant_override("shadow_offset_y", 3)
	_phase_banner.add_child(_phase_banner_label)

	_phase_line_left = ColorRect.new()
	_phase_line_left.name = "LineLeft"
	_phase_line_left.color = Color(0.90, 0.72, 0.30, 0.95)
	_phase_line_left.position = Vector2(16, 71)
	_phase_line_left.size = Vector2(194, 2)
	_phase_line_left.pivot_offset = Vector2(194, 1)
	_phase_line_left.scale.x = 0.0
	_phase_banner.add_child(_phase_line_left)

	_phase_line_right = ColorRect.new()
	_phase_line_right.name = "LineRight"
	_phase_line_right.color = Color(0.90, 0.72, 0.30, 0.95)
	_phase_line_right.position = Vector2(450, 71)
	_phase_line_right.size = Vector2(194, 2)
	_phase_line_right.pivot_offset = Vector2(0, 1)
	_phase_line_right.scale.x = 0.0
	_phase_banner.add_child(_phase_line_right)

	add_child(_phase_banner)
	return _phase_banner


## 阶段更迭提示：金线向中间展开、大字过冲回弹，随后淡出；期间冻结行动。
## 动画结束后补上行动者提示（当前阶段的首位玩家）。
func _show_phase_banner(phase_index: int) -> void:
	var phase_name := str(GameProgress.phases[phase_index].get("name", ""))
	if phase_name == "":
		return
	var pb := _phase_banner_node()
	_phase_banner_label.text = "%s阶段" % _phase_cn(phase_name)
	_phase_anim_busy = true
	if _phase_tween != null:
		_phase_tween.kill()
	pb.visible = true
	pb.modulate.a = 0.0
	_phase_banner_label.pivot_offset = _phase_banner_label.size * 0.5
	_phase_banner_label.scale = Vector2(0.82, 0.82)
	_phase_line_left.scale.x = 0.0
	_phase_line_right.scale.x = 0.0
	_phase_tween = pb.create_tween()
	_phase_tween.set_parallel(true)
	_phase_tween.tween_property(pb, "modulate:a", 1.0, PHASE_BANNER_FADE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_phase_tween.tween_property(_phase_banner_label, "scale", Vector2.ONE, PHASE_BANNER_FADE * 1.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_phase_tween.tween_property(_phase_line_left, "scale:x", 1.0, PHASE_BANNER_FADE * 1.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_phase_tween.tween_property(_phase_line_right, "scale:x", 1.0, PHASE_BANNER_FADE * 1.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_phase_tween.set_parallel(false)
	_phase_tween.tween_interval(PHASE_BANNER_HOLD)
	_phase_tween.tween_property(pb, "modulate:a", 0.0, PHASE_BANNER_FADE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_phase_tween.tween_callback(func() -> void:
		pb.visible = false
		_phase_banner_label.scale = Vector2.ONE
		_phase_anim_busy = false
		# 阶段动画演完后补上行动者提示（当前阶段的首位玩家）
		var curr := GameProgress.current_player_id
		if curr >= 0:
			_show_banner_actor(curr)
	)


## ---------- 12 局势 / 弃牌 / 17 路线 ----------

func _bind_situation_and_piles() -> void:
	var situ = MapData.active_situation
	var situ_card := _situation.get_node("SituCard") as Control
	situ_card.visible = situ != null
	_situation.get_node("Empty").visible = situ == null
	if situ != null:
		_bind_card(situ_card, str(situ.get("_card_img")))
		bind_zoom_for_card(situ_card, situ)
	_bind_pile(_piles.get_node("EventPile"), _back("event"), MapData.event_discard.size())
	_bind_pile(_piles.get_node("SituationPile"), _back("situation"), MapData.situation_discard.size())
	var row := _route.get_node("Row")
	var count := MapData.areas.size()
	# 路线按节点、箭头交替排列；刷新只增减数量，保留已有控件。
	var needed := maxi(0, count * 2 - 1)
	while row.get_child_count() > needed:
		var last := row.get_child(row.get_child_count() - 1)
		row.remove_child(last)
		last.queue_free()
	while row.get_child_count() < needed:
		_spawn("RouteNode" if row.get_child_count() % 2 == 0 else "RouteArrow", row)
	for i in range(count):
		var area: BaseMapArea = MapData.areas[i]
		var on := i == _main_area_index
		var node := row.get_child(i * 2) as Control
		_bind_avatar(node.get_node("Circle"), _area_image(i), "AvatarGold2" if on else "AvatarThin")
		var name_lbl := node.get_node("Name") as Label
		name_lbl.text = str(area._area_name)
		name_lbl.theme_type_variation = "Gold2" if on else "Text"
		if i < count - 1:
			var arrow := row.get_child(i * 2 + 1) as Control
			_set_text(arrow, "Cost", "魔力 %d" % _num(area._move_cost))


func _bind_pile(pile: Control, back: String, count: int) -> void:
	_bind_card(pile.get_node("Back1"), back)
	_bind_card(pile.get_node("Back2"), back)
	_set_text(pile, "Count/Label", str(count))


## 每次打开都读取共享弃牌区，来源对象由引擎在事件入场时记录并在弃牌后保留。
func _open_event_discard(category: String, area: BaseMapArea) -> void:
	var cards: Array = MapData.event_discard.filter(func(card):
		if not card is BaseEvent:
			return false
		var source = card.get_from()
		return source == area if area != null else source != MapData.shinto and source != MapData.miyama
	)
	$EventDiscardMenu.hide()
	_show_card_browser(category + " · 事件弃牌", cards)


## 只读查看与效果选牌分离；复用现有事件卡模板和贴图绑定，不提交任何规则动作。
func _show_card_browser(title: String, cards: Array) -> void:
	var panel := $CardBrowser/Panel
	_set_text(panel, "Title", "%s · %d" % [title, cards.size()])
	panel.get_node("Empty").visible = cards.is_empty()
	var row := panel.get_node("CardScroll/Row")
	_clear(row)
	for card in cards:
		var slot := _spawn("EventCard", row)
		slot.custom_minimum_size = (_tpl.get_node("EventCard") as Control).size
		slot.set_meta("card", card)
		_bind_card(slot, str(card.get("_card_img")))
		bind_zoom_for_card(slot, card)
		_set_text(slot, "Caption", _shown(card))
		var score := _num(card.get("_score"))
		slot.get_node("Score").visible = score != 0
		_set_text(slot, "Score/Label", str(score))
	panel.get_node("CardScroll").scroll_horizontal = 0
	$CardBrowser.show()


## ---------- 2 事件牌（当前主图战区） ----------

func _bind_events() -> void:
	var area: BaseMapArea = MapData.areas[_main_area_index]
	var events := _area_events(area)
	_events.visible = not events.is_empty()
	_set_text(_events, "Title/Label", "%s · 事件 %d" % [area._area_name, events.size()])
	var stack := _events.get_node("Stack")
	_clear(stack)
	for i in range(events.size()):
		var ev: BaseEvent = events[i]
		var concealed := bool(ev.get("_is_concealed"))
		var card := _spawn("EventCard", stack)
		card.position = Vector2(i * 10, -i * 8)
		card.rotation_degrees = -3.0 * i
		_bind_card(card, _back("event") if concealed else str(ev.get("_card_img")), 0.6 if concealed else 1.0)
		card.get_node("CapBg").visible = not concealed
		card.get_node("Caption").visible = not concealed
		card.get_node("Score").visible = not concealed
		if not concealed:
			_set_text(card, "Caption", _shown(ev))
			_set_text(card, "Score/Label", str(_num(ev._score)))


## ---------- 3 主战区内容，复用同一场景模板 ----------

func _bind_main(area: BaseMapArea, content: Control) -> void:
	_set_text(content, "Latin", str(AREA_LATIN.get(str(area._area_name), "")))
	_set_text(content, "Name", str(area._area_name))
	_bind_groups(area, content)


## 席位两排：下排 = 战区固定席位（含空席），上排 = 无固定席位（混战区）玩家头像。
## 两排都放在 ScrollContainer 里，内容超宽时用滚轮横向滚动；滚动位置在刷新间保留
func _bind_seat_rows(area: BaseMapArea, seats: Control) -> void:
	var seat_sc := seats.get_node("SeatScroll") as ScrollContainer
	var melee_sc := seats.get_node("MeleeScroll") as ScrollContainer
	var seat_row := seat_sc.get_node("Row")
	var melee_row := melee_sc.get_node("Row")
	var fixed: Array = area._locations.filter(func(loc): return loc._pl_num_limit >= 0)
	var unseated: Array = []
	for loc: BaseLocation in area._locations:
		if loc._pl_num_limit < 0:
			for pid in loc._players:
				unseated.append({"pid": int(pid), "loc": loc})
	_sync_items(seat_row, "SeatSlot", fixed.size())
	_sync_items(melee_row, "MeleeSeat", unseated.size())
	for i in range(fixed.size()):
		var loc: BaseLocation = fixed[i]
		var slot := seat_row.get_child(i) as Control
		_bind_seat(slot.get_node("Seat"), loc, true)
		slot.set_meta("compact", Vector2(13, 148 + area._locations.find(loc) * 64))
	for i in range(unseated.size()):
		var entry: Dictionary = unseated[i]
		var loc: BaseLocation = entry.loc
		var seat := melee_row.get_child(i) as Control
		_bind_avatar(seat.get_node("Avatar"), _header_img(entry.pid), "AvatarMana" if entry.pid == _local_player_id else "AvatarGold2")
		_set_text(seat, "Label", _seat_kind(loc, false))
		var slot: int = loc._players.find(entry.pid)
		seat.set_meta("compact", Vector2(4 + (slot % 3) * 22, 148 + area._locations.find(loc) * 64 + (slot / 3) * 24))
	melee_sc.visible = not unseated.is_empty()
	seat_sc.visible = not fixed.is_empty()


## 卷轴本体（战区）点击。点击落在这里时消费等待中的位置选择，或走部署/移动
## 入口。复用 _on_battlefield_clicked 已写好的判据链：等位置 → 部署 → 移动
func _on_strip_gui_input(event: InputEvent, strip: Control) -> void:
	if _is_progress_blocked():
		return
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	var idx := int(strip.get_meta("area_idx", -1))
	if idx < 0:
		return
	# v2 已定交互：左键选牌、本面手牌右键暗置、部署/移动按"点战区"确认。
	# 直接复用 _on_battlefield_clicked：它已统一处理"等待选位置 / 前哨部署 / 行动移动"，
	# 并共用 area_action_block_reason_for 判据
	_on_battlefield_clicked(idx)


## 席位排滚轮：无滚动条，滚轮上下即横向滚动
func _on_seat_row_input(event: InputEvent, sc: ScrollContainer) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var dir := 0
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
		dir = 1
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_LEFT:
		dir = -1
	if dir != 0:
		sc.scroll_horizontal += int(dir * SEAT_SCROLL_STEP)
		sc.set_meta("scroll", sc.scroll_horizontal)
		sc.accept_event()


## 取出 PlayGroup 里"卡位行"控件；模板改成 ScrollContainer 后，这里动态创建
## 并复用唯一的 Row 控件。卡位增长/收缩都不重建容器，只增减 PlayedCard 实例
func _playgroup_cards_row(group: Control) -> Control:
	var sc := group.get_node("Cards") as Control
	var row := sc.get_node_or_null("Row") as Control
	if row == null:
		row = Control.new()
		row.name = "Row"
		row.custom_minimum_size = Vector2(60, 60)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sc.add_child(row)
	return row


## 出牌组按玩家持久绑定（一人一排）；头像在左、卡牌在右，卷轴宽度撑不下时
## PlayedCard 保持原始等比，按 Row 实际宽度横向铺开；放不下时 ScrollContainer 出现
## 局部横向滚动条，绝不重排、绝不丢牌、绝不把暗置牌翻成明面
func _set_group_spread(group: Control, expanded: bool) -> void:
	pass


## 一玩家一排的版式：每个 PlayGroup 是 HBoxContainer（Who + Cards），其 Cards 是
## ScrollContainer 内含唯一 Row + 多张 PlayedCard。按真实卡对象数等比平铺；
## 卡组过宽时 ScrollContainer 自动出现横向滚动条，鼠标悬浮扇形效果由 Row 内
## 邻居间距体现。新卡入场由 _bind_groups 的 tween 负责淡入，旧牌位置不动
func _scroll_is_animating() -> bool:
	return _scroll_tween != null and _scroll_tween.is_running()


func _input(event: InputEvent) -> void:
	# 物理波浪号键：调试控制台的随时入口（与旧控制器同一约定）
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_QUOTELEFT:
		if not is_debug_console_enabled():
			set_debug_console_enabled(true)
		if is_debug_console_enabled():
			_debug_console.toggle_panel()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		$EventDiscardMenu.hide()
		$CardBrowser.hide()
		$LogBrowser.hide()
		_hide_event_zoom()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not $EventDiscardMenu.get_global_rect().has_point(event.position) and not _piles.get_node("EventPile/Open").get_global_rect().has_point(event.position):
			$EventDiscardMenu.hide()
	if $CardBrowser.visible or $EventDiscardMenu.visible or $LogBrowser.visible:
		return
	if (_hover_zoom.visible and _hover_zoom.get_global_rect().has_point(get_global_mouse_position())) or (_hover_desc.visible and _hover_desc.get_global_rect().has_point(get_global_mouse_position())):
		return
	# 只响应真实鼠标移动，不响应布局移动引发的 mouse_entered，避免静止连环切图。
	if not event is InputEventMouseMotion or event.relative.is_zero_approx():
		return
	if _board.visible:
		return
	var point: Vector2 = get_global_transform().affine_inverse() * event.position
	if _main_area_index >= 0:
		var active := _strips.get_child(_main_area_index)
		for row_name in ["MeleeScroll", "SeatScroll"]:
			var sc := active.get_node("Seats/" + row_name) as Control
			if sc.visible and sc.get_global_rect().has_point(event.position):
				return
	for i in range(_strips.get_child_count()):
		var strip := _strips.get_child(i) as Control
		if strip.get_rect().has_point(point):
			_select_scroll(i)
			return


func _scroll_target(index: int) -> Rect2:
	var count := MapData.areas.size()
	var narrow := (_tpl.get_node("Strip") as Control).size.x
	var width := maxf(narrow, size.x - SCROLL_MARGIN * 2 - (count - 1) * STRIP_STEP)
	var x := (size.x - (count - 1) * STRIP_STEP - narrow) * 0.5 + index * STRIP_STEP
	if _main_area_index >= 0:
		x = SCROLL_MARGIN + index * STRIP_STEP
		if index > _main_area_index:
			x += width - narrow
	return Rect2(Vector2(x, STRIP_TOP), Vector2(width if index == _main_area_index else narrow, 540))


func _select_scroll(index: int) -> void:
	if index == _main_area_index or index < -1 or index >= MapData.areas.size():
		return
	_main_area_index = index
	$AreaTitle.visible = index >= 0
	if index >= 0:
		_set_text($AreaTitle, "Name", str(MapData.areas[index]._area_name))
		_set_text($AreaTitle, "Latin", str(AREA_LATIN.get(str(MapData.areas[index]._area_name), "")))
	_scroll_leave_time = 0.0
	if _scroll_tween != null:
		_scroll_tween.kill()
	_scroll_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	# 各边界使用同一插值曲线：起点和终点有序且不相交，中间态也不会相交。
	for i in range(_strips.get_child_count()):
		var strip := _strips.get_child(i) as Control
		var start := strip.get_rect()
		var target := _scroll_target(i)
		# 背景与卷轴共用缓动；中途改选时保留每层当前的位置、尺寸和透明度。
		if index >= 0:
			var backdrop := $Background.get_child(i) as TextureRect
			if is_zero_approx(backdrop.modulate.a):
				backdrop.position = start.position
				backdrop.size = start.size
			if i == index:
				_scroll_tween.tween_property(backdrop, "position", Vector2.ZERO, SCROLL_SECONDS)
				_scroll_tween.tween_property(backdrop, "size", size, SCROLL_SECONDS)
			_scroll_tween.tween_property(backdrop, "modulate:a", 1.0 if i == index else 0.0, SCROLL_SECONDS)
		var start_open := float(strip.get_meta("open", 0.0))
		var target_open := 1.0 if i == index else 0.0
		if start.is_equal_approx(target) and is_equal_approx(start_open, target_open):
			continue
		_scroll_tween.tween_method(func(t: float) -> void:
			strip.position = start.position.lerp(target.position, t)
			strip.size = start.size.lerp(target.size, t)
			_layout_scroll(strip, lerpf(start_open, target_open, t))
		, 0.0, 1.0, SCROLL_SECONDS)
	_bind_situation_and_piles()


## 保留已有子节点，只按真实数据数量增减，不在刷新时重建图标。
func _sync_items(parent: Node, template: String, count: int) -> void:
	while parent.get_child_count() > count:
		var last := parent.get_child(parent.get_child_count() - 1)
		parent.remove_child(last)
		last.queue_free()
	while parent.get_child_count() < count:
		_spawn(template, parent)

func _bind_strips() -> void:
	_sync_items($Background, "AreaBackdrop", MapData.areas.size())
	var previous_count := _strips.get_child_count()
	_sync_items(_strips, "Strip", MapData.areas.size())
	for i in range(MapData.areas.size()):
		var area: BaseMapArea = MapData.areas[i]
		var strip := _strips.get_child(i) as Control
		if not strip.has_node("Main"):
			var content := _main.duplicate() as Control
			strip.add_child(content)
			content.show()
			strip.move_child(content, 2)
			strip.position = _scroll_target(i).position
			strip.size = _scroll_target(i).size
			var seats := _seats.duplicate() as Control
			strip.add_child(seats)
			seats.position = Vector2.ZERO
			seats.show()
			for row_name in ["MeleeScroll", "SeatScroll"]:
				var sc := seats.get_node(row_name) as ScrollContainer
				sc.gui_input.connect(_on_seat_row_input.bind(sc))
		_set_img(strip, "Background", _area_image(i))
		($Background.get_child(i) as TextureRect).texture = (strip.get_node("Background") as TextureRect).texture
		_bind_main(area, strip.get_node("Main"))
		_bind_seat_rows(area, strip.get_node("Seats"))
		var chars := PackedStringArray()
		for ch in str(area._area_name):
			chars.append(ch)
		_set_text(strip, "Col/Vertical", "\n".join(chars))
		_set_text(strip, "Col/Latin", str(AREA_LATIN.get(str(area._area_name), "")).left(6))

		var ev_items := strip.get_node("EventIcons")
		var events := _area_events(area)
		_sync_items(ev_items, "MiniEventCard", events.size())
		ev_items.visible = not events.is_empty()
		var event_slots := ev_items.get_children()
		event_slots.sort_custom(func(a, b): return int(a.get_meta("event_index", events.size())) < int(b.get_meta("event_index", events.size())))
		for k in range(events.size()):
			var ev: BaseEvent = events[k]
			var event_slot := event_slots[k] as Control
			event_slot.set_meta("event_index", k)
			# 左牌画在右牌之上，场景树逆序命中也必须一致。
			ev_items.move_child(event_slot, 0)
			_bind_card(event_slot, _back("event") if bool(ev.get("_is_concealed")) else str(ev.get("_card_img")))
			if ev._is_concealed:
				_disable_card_zoom(event_slot)
			else:
				bind_zoom_for_card(event_slot, ev)
		strip.get_node("Score").visible = _area_score(area) != 0
		_set_text(strip, "Score/Num", str(_area_score(area)))
		# 地图战区点击：战区本体接收 gui_input；命中后消费等待中的位置选择 / 部署 / 移动
		if not strip.has_meta("area_idx"):
			strip.set_meta("area_idx", i)
			strip.gui_input.connect(_on_strip_gui_input.bind(strip))
		else:
			strip.set_meta("area_idx", i)
		# 当前战区是否可操作，就能沿卷轴外缘亮一圈流动金框（判据与点击入口共用）
		var blocked: String = TacticalBoardUI.area_action_block_reason_for(_local_player_id, i)
		var flow := strip.get_node_or_null("FlowBorder") as Control
		if flow != null:
			flow.visible = blocked == ""
			_bind_flow_border(flow)
		_layout_scroll(strip, float(strip.get_meta("open", 0.0)))
	if previous_count != _strips.get_child_count() and previous_count > 0:
		# 区域由引擎增删时重算端点；不影响游戏规则。
		var selected := _main_area_index
		_main_area_index = -2
		_select_scroll(selected)


func _layout_scroll_refs(strip: Control) -> Dictionary:
	var refs: Dictionary = _meta_or(strip, "layout_refs", {})
	if not refs.is_empty():
		return refs
	refs = {
		"background": strip.get_node("Background") as Control,
		"atmosphere": strip.get_node("Atmosphere") as CPUParticles2D,
		"content": strip.get_node("Main") as Control,
		"groups": strip.get_node("Main/Groups") as Control,
		"col": strip.get_node("Col") as Control,
		"events": strip.get_node("EventIcons") as Control,
		"score": strip.get_node("Score") as Control,
		"seat": strip.get_node("Seats/SeatScroll") as ScrollContainer,
		"melee": strip.get_node("Seats/MeleeScroll") as ScrollContainer,
	}
	strip.set_meta("layout_refs", refs)
	return refs

func _layout_scroll(strip: Control, openness: float) -> void:
	var refs := _layout_scroll_refs(strip)
	strip.set_meta("open", openness)
	var background := refs["background"] as Control
	background.modulate.a = lerpf(_tpl.get_node("Strip/Background").modulate.a, 0.0, openness)
	var atmosphere := refs["atmosphere"] as CPUParticles2D
	atmosphere.position = strip.size * 0.5
	atmosphere.emission_rect_extents = strip.size * 0.5
	atmosphere.modulate.a = lerpf(0.15, 1.0, openness)
	var content := refs["content"] as Control
	content.position = Vector2.ZERO
	content.size = strip.size
	content.modulate.a = openness
	for name in ["TitleBg", "Latin", "Name", "More"]:
		var child := content.get_node(name) as Control
		child.position.x = (strip.size.x - child.size.x) * 0.5
	var groups := refs["groups"] as Control
	var play_rect := _play_area_rect(strip)
	groups.position = play_rect.position
	groups.size = play_rect.size
	_layout_play_groups(groups)
	# 布局缓存命中或空间过小时也要按本帧卷轴边界更新，避免裁切先画出一帧。
	if _scroll_is_animating():
		for grp in groups.get_node("List").get_children():
			var who := grp.get_node("Who") as Control
			_update_avatar_scroll_reveal(who, who.get_node("Avatar") as Control)
	refs["col"].modulate.a = 1.0 - openness
	var count: int = MapData.areas[strip.get_index()]._locations.size()
	var events := refs["events"] as Control
	var score := refs["score"] as Control
	var compact_step := minf(64, (strip.size.y - 144 - (64 if events.visible else 0) - (52 if score.visible else 0)) / maxf(1, count))
	for row_name in ["SeatScroll", "MeleeScroll"]:
		var sc: ScrollContainer = refs["seat"] if row_name == "SeatScroll" else refs["melee"]
		var target := _seats.get_node(row_name) as ScrollContainer
		var row := sc.get_node("Row") as Control
		# 目标始终使用卷轴局部坐标，不再越过卷轴边界遮住相邻竖条。
		var expanded := Vector2(24, strip.size.y - 108 if row_name == "SeatScroll" else strip.size.y - 208)
		sc.position = Vector2.ZERO.lerp(expanded, openness)
		var target_size := Vector2(minf(target.size.x, maxf(72, strip.size.x - 48)), target.size.y)
		sc.size = Vector2(72, strip.size.y).lerp(target_size, openness)
		var row_width := maxf(sc.size.x, row.get_child_count() * SEAT_SCROLL_STEP - 12)
		row.custom_minimum_size = Vector2(lerpf(sc.size.x, row_width, openness), 0)
		for j in range(row.get_child_count()):
			var item := row.get_child(j) as Control
			var compact: Vector2 = item.get_meta("compact", Vector2.ZERO)
			compact.y = 132 + (compact.y - 148) * compact_step / 64.0
			item.position = compact.lerp(Vector2(j * SEAT_SCROLL_STEP, 0), openness)
			var compact_scale := minf(46.0 / 74.0, (compact_step - 4) / 92.0) if row_name == "SeatScroll" else 22.0 / 64.0
			item.scale = Vector2.ONE * lerpf(compact_scale, 1.0, openness)
		if openness < 1.0:
			sc.scroll_horizontal = int(float(sc.get_meta("scroll", 0)) * openness)
	events.size = strip.size
	var event_count := events.get_child_count()
	# 事件牌堆的上缘按“最后一张的底边不压到混战区”回推：事件多时整堆上移，
	# 位置由席位实际展开位置与模板牌高算出，不写死行数或位置
	var event_top := EVENT_STACK_TOP
	var event_step := EVENT_STACK_STEP
	if event_count > 0:
		var event_h: float = (_tpl.get_node("MiniEventCard") as Control).size.y * EVENT_STACK_SCALE
		var seat_top: float = (refs["melee"] as Control).position.y
		var lowest := event_top + float(event_count - 1) * event_step + event_h
		if lowest > seat_top - EVENT_STACK_GAP:
			event_top = maxf(0.0, seat_top - EVENT_STACK_GAP - float(event_count - 1) * event_step - event_h)
	for card: Control in events.get_children():
		var k := int(card.get_meta("event_index", card.get_index()))
		card.z_index = events.get_child_count() - k
		var compact := Vector2(16 + k * 3, 136 + count * compact_step + k * 2)
		var expanded := Vector2(30 + k * 26, event_top + k * event_step)
		card.position = compact.lerp(expanded, openness)
		card.scale = Vector2.ONE * lerpf(1.0, EVENT_STACK_SCALE, openness)
	score.position = Vector2(16, strip.size.y - 48).lerp(Vector2(strip.size.x - 76, 32), openness)
	# 流动金框按卷轴实际尺寸算周长：布局每次变化（展开/收起/缩放）都同步一次
	var flow := strip.get_node_or_null("FlowBorder") as Control
	if flow != null:
		_bind_flow_border(flow, strip.size)





## ---------- 提示条 + 敌人行动横幅 ----------

func _bind_hint() -> void:
	var curr := GameProgress.current_player_id
	var mine := curr == _local_player_id
	(_hint.get_node("Bar") as ColorRect).color = get_theme_color("font_color", "Gold2") if mine or curr < 0 else get_theme_color("font_color", "Blood2")
	var main_text := ""
	var sub_text := ""
	if curr < 0:
		main_text = "对局已结束"
	elif mine:
		var area := _player_area(_local_player_id)
		main_text = "轮到你行动 · %s阶段" % _phase_cn(_phase_name())
		if area != null:
			main_text += " · " + str(area._area_name)
		var pl := _pl(_local_player_id)
		sub_text = "常规出牌 %d / %d · 技能需魔力≥%d" % [RegularPlay.played_count(_local_player_id), _num(pl.get("play_limit")), _num(GameData.skill_zone_magic_limit)]
	else:
		main_text = "%s 正在行动" % _player_name(curr)
		var area := _player_area(curr)
		sub_text = "顺位 %d" % (EffectManager.get_player_order_index(curr) + 1)
		if area != null:
			sub_text += " · 位于 " + str(area._area_name)
		sub_text += " · 等待对方完成"
	# 等待选位置：在提示条上常驻说明，不重复弹窗打扰
	var pending_loc: Dictionary = EffectManager.get_pending_location_selection()
	if not pending_loc.is_empty():
		var loc_eff: BaseEffect = pending_loc.get("effect")
		if loc_eff != null and loc_eff._trigger_player_id == _local_player_id:
			main_text = "请点击要选定的战区"
			sub_text = _pending_location_hint(pending_loc)
	_set_text(_hint, "Main", main_text)
	_set_text(_hint, "Sub", sub_text)
	_banner.position.x = (size.x - _banner.size.x) / 2
	if not _banner_initialized:
		_banner_initialized = true
		_banner_actor_id = curr
		# 开局首名行动者沿用"非我方才亮相"的规则，同样走淡入淡出
		if curr >= 0 and not mine:
			_show_banner_actor(curr)
		elif curr >= 0:
			_set_banner_actor(curr)
		else:
			_banner.hide()
	elif curr != _banner_actor_id:
		_banner_actor_id = curr
		if curr >= 0:
			if not _phase_anim_busy:
				_show_banner_actor(curr)
			# 阶段横幅播放期间先不显示行动者，等阶段动画结束的 callback 补上
		else:
			if _banner_tween != null:
				_banner_tween.kill()
			_banner.hide()


## ---------- 4/5 本方面板 ----------

func _bind_self() -> void:
	var pl := _pl(_local_player_id)
	var servant = pl.get("servant")
	var master = pl.get("master")
	var sv := _self.get_node("ServantCard") as Control
	_bind_card(sv, str(servant.get("_servant_card_img")) if servant != null else "")
	bind_zoom_for_card(sv, servant, "_servant_card_img")
	_set_text(sv, "Class", _servant_class(_local_player_id).to_upper())
	_set_text(sv, "HiddenTag/Label", "真名解放" if ReleaseTrueName.is_released(_local_player_id) else "真名隐藏")
	var stats := _self.get_node("Stats")
	_set_text(stats, "ScoreRow/Score", str(_num(pl.get("score"))))
	_set_text(stats, "ScoreRow/Rank", "名次 %d" % (_score_sorted_ids().find(_local_player_id) + 1))
	var magic := _num(pl.get("magic"))
	var limit := _num(GameData.player_magic_limit(_local_player_id))
	_bind_bar(stats.get_node("MagicBar"), float(magic) / maxf(1.0, float(limit)), float(_num(GameData.skill_zone_magic_limit)) / maxf(1.0, float(limit)))
	_set_text(stats, "MagicNum", "%d / %d" % [magic, limit])
	var brk: Dictionary = GetPlayerTotalPower.breakdown(_local_player_id)
	_set_text(stats, "PowerRow/Power", str(int(brk.get("total", 0))))
	var parts: Array[String] = ["出牌 %d" % int(brk.get("power", 0))]
	for key_label in [["location_benefit", "地利"], ["board", "场上"], ["bonus", "加成"]]:
		if int(brk.get(key_label[0], 0)) != 0:
			parts.append("%s %d" % [key_label[1], int(brk.get(key_label[0], 0))])
	_set_text(stats, "PowerRow/Break", " + ".join(parts))
	var spells := stats.get_node("Spells")
	var cs_img := str(master.get("_command_spell_img")) if master != null else ""
	var cs_count := _num(pl.get("command_spell_count"))
	var spell_card := LoadCommandSpell.resolve_player_command_spell(master, servant)
	_sync_items(spells, "SpellCard", maxi(_num(pl.get("command_spell_limit")), cs_count))
	for i in range(spells.get_child_count()):
		var cs := spells.get_child(i) as Control
		_bind_card(cs, cs_img)
		bind_zoom_for_card(cs, spell_card)
		if cs_img != "" and not bool(cs.get_meta("zoom_disabled", true)):
			cs.set_meta("zoom_img", cs_img)
		cs.modulate.a = 1.0 if i < cs_count else 0.28
	# 令咒点击入口：把第一个"已持有"令咒卡做成可点；点发动时复用 EffectManager.request_manual_activation。
	# 判据沿用旧版 _command_spell_block_reason：可发动亮呼吸金框；不可发动弹原因
	if spells.get_child_count() > 0 and cs_count > 0:
		var entry := spells.get_child(0) as Control
		_bind_command_spell_entry(entry)
	var me := _self.get_node("Me")
	_bind_avatar(me.get_node("Avatar"), _header_img(_local_player_id))
	_set_text(me, "Name", _player_name(_local_player_id))
	_set_text(me, "Order", "%d / %d" % [EffectManager.get_player_order_index(_local_player_id) + 1, _ordered_ids().size()])
	_set_text(me, "Place", _seat_summary(_local_player_id, "\n"))
	_set_text(me, "Hand", "%d · %d" % [(pl.get("hand_cards", []) as Array).size(), (pl.get("deck", []) as Array).size()])


## ---------- 8 御主卡 ----------

func _bind_master() -> void:
	var master = _pl(_local_player_id).get("master")
	_set_img(_master, "Frame/Img", str(master.get("_master_card_img")) if master != null else "")
	var portrait := _master.get_node("Frame/Img") as TextureRect
	bind_zoom_for_card(portrait, master, "_master_card_img")
	if portrait.texture != null:
		var path: String = str(master.get("_master_card_img"))
		if not _portrait_textures.has(path):
			# 裁出独立纹理，使遮罩 UV 覆盖完整椭圆；同一御主只裁一次。
			var image := portrait.texture.get_image()
			if image.is_compressed():
				image.decompress()
			var height := int(image.get_height() * 0.70)
			var width := mini(image.get_width(), int(height * portrait.size.x / portrait.size.y))
			var region := Rect2i((image.get_width() - width) / 2, int(image.get_height() * 0.03), width, height)
			_portrait_textures[path] = ImageTexture.create_from_image(image.get_region(region))
		portrait.texture = _portrait_textures[path]
	_set_text(_master, "Name", _player_name(_local_player_id))


## ---------- 11 御主下方的手牌抽屉与椭圆两侧的技能卡 ----------

func _bind_hand() -> void:
	var pl := _pl(_local_player_id)
	# 真名是否解放同时决定技能区牌要不要盖未公开遮罩，整组绑定前取一次
	_local_true_name_released = ReleaseTrueName.is_released(_local_player_id)
	var live_cards: Array = []
	for card in pl.get("hand_cards", []):
		if card is BaseHandCard:
			live_cards.append(card)
	for entry in _zone_hand_entries(pl):
		if not live_cards.has(entry.card):
			live_cards.append(entry.card)
	for slot in _hand.get_children():
		if not live_cards.has(_meta_or(slot, "card", null)):
			_hand.remove_child(slot)
			slot.queue_free()
	_selected_cards = _selected_cards.filter(func(card): return live_cards.has(card))
	var right_entries: Array = []
	for card in pl.get("hand_cards", []):
		if card is BaseHandCard:
			right_entries.append({"card": card, "kind": "手牌", "count": 1})
	var portrait_rect := _master.get_rect()
	var servant_entries: Array = []
	var master_entries: Array = []
	for entry in _zone_hand_entries(pl):
		if entry.kind == "从者技能":
			servant_entries.append(entry)
		else:
			master_entries.append(entry)
	var center := portrait_rect.get_center().x
	_layout_held_group(servant_entries, "ZoneCard", _self.get_rect().end.x + HELD_GAP, portrait_rect.position.x - HELD_GAP, "zone")
	_layout_held_group(master_entries, "ZoneCard", portrait_rect.end.x + HELD_GAP, _ops.get_node("PlayButton").get_global_rect().position.x - HELD_GAP, "zone")
	# 手牌范围取御主卡宽度的 0.8 倍半径：1.5 倍会伸进两侧技能卡区域，0.5 倍又太窄、
	# 会把牌间距压缩回几乎重合；手牌整组已在最上层，轻度重叠技能卡也能看清
	_layout_held_group(right_entries, "HandCard", center - portrait_rect.size.x * 0.9, center + portrait_rect.size.x * 0.9, "hand")
	_update_held_cards(0.0)


## 水平排布两侧卡组；宽度不足时等距叠放，让首尾恰好贴合可用边界。
## 手牌另在御主下方组成抽屉，所有牌共用同一套卡位绑定与点击逻辑。
func _layout_held_group(entries: Array, template: String, left: float, right: float, group: String) -> void:
	if entries.is_empty():
		return
	var card_size: Vector2 = _tpl.get_node(template).size
	var ordered: Array = []
	var groups_by_key: Dictionary = {}
	for entry: Dictionary in entries:
		var card = entry.card
		var key: Array = [entry.kind, card._name, card._card_img, card._card_back_img, card._is_concealed]
		if card is BaseHandCard:
			key.append_array([_num(card._cost), _num(card._power)])
		var signature := JSON.stringify(key)
		if not groups_by_key.has(signature):
			groups_by_key[signature] = []
			ordered.append(signature)
		groups_by_key[signature].append(entry)
	var arranged: Array = []
	var gaps: Array = []
	for signature in ordered:
		var matching: Array = groups_by_key[signature]
		for i in range(matching.size()):
			if not arranged.is_empty():
				# 同组（同名同图同状态）之间只做轻微错位：0.16 会几乎完全重合，看不出是两张
				gaps.append(card_size.x * HELD_STACK_GAP_RATIO if i > 0 else card_size.x)
			var item: Dictionary = matching[i].duplicate()
			item["stack_count"] = matching.size() if i == 0 else 0
			arranged.append(item)
	var available := maxf(card_size.x, right - left)
	var natural_span := 0.0
	for gap in gaps:
		natural_span += gap
	var factor := minf(1.0, maxf(0.0, available - card_size.x) / natural_span) if natural_span > 0.0 else 1.0
	var width := card_size.x + natural_span * factor
	var x := left + (available - width) * 0.5
	var half_span := (width - card_size.x) * 0.5
	var fan_center := x + half_span
	var fan_radius := half_span / sin(deg_to_rad(10.0)) if half_span > 0.0 else 0.0
	for i in range(arranged.size()):
		if i > 0:
			x += gaps[i - 1] * factor
		var entry: Dictionary = arranged[i]
		var slot := _held_slot(entry.card, template)
		var rest := Vector2(x, size.y - HELD_VISIBLE_HEIGHT if group == "hand" else size.y - card_size.y - HELD_GAP)
		var angle := 0.0
		if group == "hand" and fan_radius > 0.0:
			# 用同一圆弧决定位置与倾角，重复牌的紧凑间距也能保持扇面连续。
			angle = asin(clampf((x - fan_center) / fan_radius, -1.0, 1.0))
			rest.y += fan_radius * (1.0 - cos(angle))
		# 收起的抽屉只露出牌的上一截：旋转支点取"可见部分的底边"，
		# 扇形才是绕露出的牌脚展开；用整张牌的底边会把露出的上缘甩向两侧，看起来整排是歪的
		slot.pivot_offset = Vector2(card_size.x * 0.5, HELD_VISIBLE_HEIGHT) if group == "hand" else Vector2.ZERO
		if not slot.has_meta("rest_position"):
			slot.position = rest
			slot.rotation = angle
		slot.set_meta("rest_position", rest)
		# 位置与倾角由 _update_held_cards 同步过渡，避免两个时钟造成牌面歪乱。
		slot.set_meta("rest_rotation", angle)
		slot.set_meta("held_group", group)
		# 未公开遮罩由调用方声明：技能区/御主牌区要标出"这张牌对别人是暗的"，
		# 手牌区不标——手牌本来只有自己可见，盖闭眼遮罩没有信息量，只会挡住卡面
		_bind_hand_card(slot, entry.card, entry.kind, entry.count, _is_acting(_local_player_id), group == "zone")
		var badge := slot.get_node("StackCount") as Label
		badge.visible = entry.stack_count > 1
		badge.text = "x%d" % entry.stack_count if badge.visible else ""

## 手牌"可出"提示的重算签名。规则搜索是深度组合搜索（实测 5~8 张牌一轮约 4ms，
## 占掉 120FPS 预算的一半），不能每帧跑；但也不能只在定时刷新时更新，
## 否则阶段/回合/选牌/魔力一变，金色呼吸描边会滞后。这里用这几项做轻量签名，
## 只有真的变了才重算，平时零成本
func _held_playable_signature() -> String:
	var pl := _pl(_local_player_id)
	return "%d|%d|%d|%d|%d" % [_selected_cards.size(), GameProgress.current_player_id,
		GameProgress.current_phase_index, GameProgress.current_round, _num(pl.get("magic"))]


## 手牌悬浮判据：鼠标确实落在牌上（over 来自真实 GUI 命中），且抽屉已开始展开（含上升过程中）。
## 不能用收起态的 rest.y 去比较——抽屉把整副牌抬起后牌已经不在那个坐标上，
## 会让鼠标明明在牌上却判不出悬浮（表现：整体上移后单张牌不再跟随）。
## 侧翼技能卡不受抽屉影响，只看是否命中。
static func held_hover_allowed(over: bool, is_hand: bool, drawer_open: float) -> bool:
	if not over:
		return false
	# 抽屉上升过程中就要能跟随：要求"完全展开"会卡掉整段过渡期，
	# 表现为上移动画期间点不出牌、要等它停稳才响应
	return true if not is_hand else drawer_open > 0.0

## 悬浮放大的跟随位移：鼠标相对牌中心的偏移按比例跟随，并限制最大位移。
## 抽成静态纯函数是为了能直接断言跟随幅度，不必模拟真实鼠标事件
static func held_hover_shift(mouse: Vector2, card_center: Vector2) -> Vector2:
	# 横向完全不跟随：牌横着挪会盖到相邻的牌上，挡住对其他牌的点击。
	# 纵向也只允许向上：向下跟会挡住卡片下方的东西，而手牌在屏幕底部本就该向上浮
	var want := (mouse - card_center) * HELD_HOVER_FOLLOW
	return Vector2(0.0, clampf(want.y, -HELD_HOVER_MAX_SHIFT.y, 0.0))

## GUI 的真实命中节点决定悬浮，纯装饰子节点不接收输入。
func _update_held_cards(delta: float) -> void:
	var hovered := get_viewport().gui_get_hovered_control()
	var slots := _hand.get_children()
	var mouse := get_global_mouse_position()
	var drawer_bounds := Rect2()
	var has_hand := false
	for slot: Control in slots:
		if slot.get_meta("held_group", "") != "hand":
			continue
		var rest: Vector2 = slot.get_meta("rest_position")
		var area := Rect2(rest.x, size.y - slot.size.y - HELD_GAP, slot.size.x, slot.size.y + HELD_GAP)
		drawer_bounds = area if not has_hand else drawer_bounds.merge(area)
		has_hand = true
	var drawer_over := has_hand and drawer_bounds.has_point(mouse)
	if not drawer_over and _hand_drawer_open > 0.0 and hovered != null:
		for slot: Control in slots:
			if slot.get_meta("held_group", "") == "hand" and (hovered == slot or slot.is_ancestor_of(hovered)):
				drawer_over = true
				break
	_hand_drawer_open = move_toward(_hand_drawer_open, 1.0 if drawer_over else 0.0, delta * HELD_HOVER_SPEED)
	# 离开悬浮后恢复原始左右叠放次序，否则上一张提到顶层的牌会挡住邻牌。
	# 手牌整组压在技能卡之上：原实现按 x 降序重排，最左侧的从者技能卡会被抬到最上层，
	# 手牌就被压在下面（表现为"手牌被从者技能卡挡住"）
	var by_x := slots.duplicate()
	by_x.sort_custom(func(a, b): return (a.get_meta("rest_position", Vector2.ZERO) as Vector2).x > (b.get_meta("rest_position", Vector2.ZERO) as Vector2).x)
	for slot: Control in by_x:
		if str(slot.get_meta("held_group", "")) != "hand":
			_hand.move_child(slot, -1)
	for slot: Control in by_x:
		if str(slot.get_meta("held_group", "")) == "hand":
			_hand.move_child(slot, -1)
	slots = by_x
	# 状态变了才重算可出提示：选牌/阶段/回合/当前玩家/魔力任一变化都会换签名
	var sig := _held_playable_signature()
	if str(_hand.get_meta("playable_sig", "")) != sig:
		_hand.set_meta("playable_sig", sig)
		for slot: Control in slots:
			if slot.has_meta("card"):
				slot.set_meta("held_playable", _held_card_playable(_meta_or(slot, "card", null)))
	for slot: Control in slots:
		if not slot.has_meta("rest_position"):
			continue
		var card = slot.get_meta("card")
		var playable: bool = bool(slot.get_meta("held_playable", false)) and _held_input_available()
		var breath := slot.get_node("Breath") as Control
		var selected := slot.get_node("Selected") as Control
		selected.visible = _selected_cards.has(card)
		if selected.visible and not _breathing.has(selected):
			_breathing.append(selected)
		breath.visible = playable and not selected.visible
		if breath.visible and not _breathing.has(breath):
			_breathing.append(breath)
		var over := hovered == slot or (hovered != null and slot.is_ancestor_of(hovered))
		var is_hand: bool = slot.get_meta("held_group", "") == "hand"
		var rest: Vector2 = slot.get_meta("rest_position")
		# 抽屉展开会把整副牌抬起来：这里先算出抬升量，位移用它
		var drawer_rise: float = _hand_drawer_open * (slot.size.y - HELD_VISIBLE_HEIGHT + HELD_GAP) if is_hand else 0.0
		slot.set_meta("held_hovered", held_hover_allowed(over, is_hand, _hand_drawer_open))
		var target := rest
		var target_scale := Vector2.ONE
		if is_hand:
			target.y -= drawer_rise
			if bool(slot.get_meta("held_hovered", false)):
				target_scale *= HELD_HOVER_SCALE
				# 只做有限跟随：原来把牌中心钉死在鼠标上，指针一动整张牌就满屏跑
				# 基准是牌当前的静止位置（含抽屉上移），所以牌不会离开手牌堆
				target += held_hover_shift(mouse, target + slot.size * 0.5)
				# scale 绕 pivot 缩放：放大后补回 pivot 差值，视觉位置才不偏
				target += slot.pivot_offset * (HELD_HOVER_SCALE - 1.0)
				target.x = clampf(target.x, 0.0, size.x - slot.size.x * HELD_HOVER_SCALE)
				target.y = clampf(target.y, 0.0, size.y - slot.size.y * HELD_HOVER_SCALE)
				_hand.move_child(slot, -1)
		elif over:
			target.y -= HELD_GAP
			_hand.move_child(slot, -1)
		var weight := 1.0 - exp(-HELD_HOVER_SPEED * delta)
		slot.position = slot.position.lerp(target, weight)
		slot.rotation = lerp_angle(slot.rotation, float(slot.get_meta("rest_rotation", 0.0)), weight)
		slot.scale = slot.scale.lerp(target_scale, weight)
	(_ops.get_node("PlayButton") as Button).disabled = not _can_confirm_held_cards()


## 单张手牌：卡图 + 类别 + 费用/威力角标 + 名字与属性；可出牌呼吸框；
## 技能区牌魔力不足时盖门槛遮罩；轮到自己但不可出则压暗。判据只用 RegularPlay.modes
func _held_slot(card, template: String) -> Control:
	for slot: Control in _hand.get_children():
		if _meta_or(slot, "card", null) == card:
			return slot
	var slot := _spawn(template, _hand)
	slot.set_meta("card", card)
	for child in slot.find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.gui_input.connect(_on_held_card_input.bind(slot))
	return slot


func _on_held_card_input(event: InputEvent, slot: Control) -> void:
	if not event is InputEventMouseButton or not event.pressed or not _held_input_available():
		return
	var card = _meta_or(slot, "card", null)
	if not card is BaseCard:
		return
	var pl := _pl(_local_player_id)
	if not (pl.get("hand_cards", []) as Array).has(card) and not _zone_hand_entries(pl).any(func(entry): return entry.card == card):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if _selected_cards.has(card):
			_selected_cards.erase(card)
		else:
			_selected_cards.append(card)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		SetCardConcealed.new().exec(card, not card._is_concealed, _local_player_id)
	else:
		return
	slot.accept_event()
	refresh_all_ui()


func _held_card_playable(card) -> bool:
	if not card is BaseHandCard or not _held_input_available():
		return false
	var proposed := _selected_cards.duplicate()
	if not proposed.has(card):
		proposed.append(card)
	for chosen in proposed:
		if not chosen is BaseHandCard:
			return false
	# 完整组合使用提交入口的同一校验；未满组逐步复用 pending_modes，
	# 同时复核已选牌当前状态，避免其中一张失效后其他牌仍显示旧金框。
	if proposed.size() + RegularPlay.played_count(_local_player_id) >= RegularPlay.minimum(_local_player_id):
		return RegularPlay.can_submit_group(_local_player_id, proposed, _held_hidden(proposed))
	var pending: Array = []
	for chosen in proposed:
		if not RegularPlay.pending_modes(_local_player_id, pending, _held_hidden(pending), chosen).has(chosen._is_concealed):
			return false
		pending.append(chosen)
	return true


## 牌面翻转动画：绕垂直中线折到最窄时执行 on_mid（换贴图/换遮罩由调用方决定），再展开。
## 二维投影模拟，与头像翻转同一手法；只负责"折、在中点回调、再展开"这一件事。
## 作用在卡图节点（Frame）而不是卡位：卡位的 scale 被悬浮缩放每帧 lerp 控制，两处会互相打架。
## 回调与采样一律按 instance_id 取节点，避免卡位被刷新回收后 lambda 捕获已释放对象。
func _play_card_flip(frame: Control, on_mid: Callable) -> void:
	# 用 _meta_or 判存在性，不要写 get_meta(key, null)（见其定义处的说明）
	var running: Tween = _meta_or(frame, "card_flip_tween", null) as Tween
	if running != null and running.is_valid():
		running.kill()
	var step := CARD_FLIP_SECONDS * 0.5
	var id := frame.get_instance_id()
	frame.set_meta("card_flipping", true)
	frame.pivot_offset = frame.size * 0.5
	var tween := frame.create_tween()
	frame.set_meta("card_flip_tween", tween)
	tween.tween_method(_apply_flip_scale.bind(id), 1.0, 0.0, step).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(on_mid)
	tween.tween_method(_apply_flip_scale.bind(id), 0.0, 1.0, step).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.finished.connect(_finish_card_flip.bind(id))


func _apply_flip_scale(v: float, id: int) -> void:
	var node := instance_from_id(id) as Control
	if node != null:
		node.scale.x = maxf(v, 0.02)


## 翻面中点：贴图与未公开遮罩一起换——遮罩的有无也属于"这一面"的观感
func _apply_hand_face(id: int, img: String, mark: bool) -> void:
	var node := instance_from_id(id) as Control
	if node == null:
		return
	_set_img(node, "Img", img)
	_sync_overlay(node, mark, "ConcealOverlay", CONCEAL_COLOR, CONCEAL_ICON)


func _finish_card_flip(id: int) -> void:
	var node := instance_from_id(id) as Control
	if node == null:
		return
	node.scale = Vector2.ONE
	node.set_meta("card_flipping", false)


func _bind_hand_card(node: Control, card, kind: String, count: int, mine: bool, show_conceal_mark: bool = true) -> void:
	var frame := node.get_node("Frame") as Control
	frame.modulate = Color.WHITE
	node.get_node("Breath").hide()
	var awakened := not (card is BaseSkill and not bool(card.get("_is_awakened")))
	var concealed := bool(card._is_concealed)
	var back: String = str(card.get("_card_back_img"))
	# 暗置＝贴卡背（牌面不给看）；未公开遮罩（半透明灰 + 闭眼图标）表达"这张牌还没向其他玩家公开"，
	# 明置≠已公开：技能区牌的卡面要等【真名解放】才真正公开（见 ReleaseTrueName / HideTrueName）。
	# 未觉醒升华技本来就只有卡背（玩家尚未获得这张牌）。
	var face_img: String = str(card.get("_card_img")) if awakened and not concealed else back
	var mark: bool = awakened and show_conceal_mark and (concealed or not _local_true_name_released)
	var prev_face: String = str(frame.get_meta("face_img", ""))
	var prev_mark: bool = bool(frame.get_meta("face_mark", false))
	frame.set_meta("face_img", face_img)
	frame.set_meta("face_mark", mark)
	if prev_face != "" and (prev_face != face_img or prev_mark != mark):
		# 换面（明置↔暗置、升华技觉醒等）：折到最窄时同时换贴图与遮罩，不让牌面瞬间跳变
		_play_card_flip(frame, _apply_hand_face.bind(frame.get_instance_id(), face_img, mark))
	elif not bool(frame.get_meta("card_flipping", false)):
		# 动画进行中不要提前换面（贴图与遮罩都由动画在中点换）
		_bind_card(frame, face_img)
		_sync_overlay(frame, mark, "ConcealOverlay", CONCEAL_COLOR, CONCEAL_ICON)
	if kind == "升华技":
		_set_variation(frame, "CardUpgrade")
	var playable := awakened and _held_card_playable(card)
	# 提示随数据绑定更新；逐帧动画不重复执行规则搜索。
	node.set_meta("held_playable", playable)
	var pl := _pl(_local_player_id)
	var need := _num(GameData.skill_zone_magic_limit)
	var locked := awakened and mine and not playable and not (pl.get("hand_cards", []) as Array).has(card) \
		and _num(pl.get("magic")) < need \
		and not bool(pl.get("ignore_skill_zone_magic_limit", false)) and not bool(pl.get("is_magic_immune", false))
	if playable:
		_breathe(node.get_node("Breath"))
	elif mine and awakened:
		frame.modulate = Color(0.55, 0.55, 0.55)
	# 牌面不附说明文字：牌名、属性与底部底条都改由放大卡图与右键说明承担
	var lock := node.get_node("Lock") as Control
	lock.visible = locked
	# 放大与右键说明绑在卡位自身：Frame 及其子节点都被设为不接收鼠标，绑在它们上面收不到事件。
	# 手牌与技能区的右键已被明置/暗置占用，说明改由放大卡图上右键触发（right_action 声明式传入）。
	if awakened:
		bind_zoom_for_card(node, card, "", "none")
	else:
		_disable_card_zoom(node)

func _bind_ops() -> void:
	var pl := _pl(_local_player_id)
	(_ops.get_node("PlayButton") as Button).disabled = not _can_confirm_held_cards()
	(_ops.get_node("EndButton") as Button).disabled = not _is_acting(_local_player_id)
	var list := _ops.get_node("BuffBox/List")
	_clear(list, ["None"])
	var buffs: Array = (pl.get("buffs", []) as Array).filter(func(b): return b is BaseBuff)
	list.get_node("None").visible = buffs.is_empty()
	for b in buffs:
		var row := _spawn("BuffRow", list)
		_set_variation(row, "BuffActive" if bool(b._is_active) else "BuffInactive")
		var img := str(b.get("_buff_img"))
		var avatar := row.get_node("H/Avatar") as Control
		avatar.visible = img != "" and LoadHelper.texture_exists(img)
		if avatar.visible:
			_bind_avatar(avatar, img)
		bind_zoom_for_card(row, b, "_buff_img")
		_set_text(row, "H/Name", _shown(b))
		row.get_node("H/Inactive").visible = not bool(b._is_active)
	var deck: Array = pl.get("deck", [])
	var discard: Array = pl.get("discard", [])
	_bind_pile(_ops.get_node("Deck"), _back("attack"), deck.size())
	_bind_pile(_ops.get_node("Discard"), str(discard.back().get("_card_img")) if not discard.is_empty() else _back("attack"), discard.size())


## 结束阶段：直接走引擎公开入口；被拒时把引擎给本地玩家的提示原样弹出
func _held_hidden(cards: Array) -> Array:
	return cards.map(func(card): return bool(card._is_concealed))


func _held_input_available() -> bool:
	return not _submitting and not $LogBrowser.visible and not $CardBrowser.visible and not $EventDiscardMenu.visible \
		and not EffectManager.is_waiting_for_choice() and not EffectManager.is_waiting_for_card_selection()


func _can_confirm_held_cards() -> bool:
	return _held_input_available() and RegularPlay.can_submit_group(_local_player_id, _selected_cards, _held_hidden(_selected_cards))


func _confirm_held_cards() -> void:
	if not _can_confirm_held_cards():
		return
	# 对象与当前明暗状态在确认时一同快照；提交入口仍执行完整规则校验。
	var cards := _selected_cards.duplicate()
	var hidden := _held_hidden(cards)
	_submitting = true
	var submitted := RegularPlay.submit_group(_local_player_id, cards, hidden)
	if submitted:
		_selected_cards.clear()
	_submitting = false
	refresh_all_ui()
	if submitted:
		# 提交后节点会复用；旧坐标属于打出的牌数，剩余牌立即采用新扇形布局。
		for slot: Control in _hand.get_children():
			if slot.get_meta("held_group", "") == "hand":
				slot.position = slot.get_meta("rest_position")
				slot.rotation = slot.get_meta("rest_rotation")


func _bind_board() -> void:
	if not _board.visible:
		return
	var rows := _board.get_node("Rows") as Control
	_clear(rows)
	var ids := _score_sorted_ids()
	var row_h := 0.0
	for i in range(ids.size()):
		var id: int = ids[i]
		var row := _spawn("BoardRow", rows)
		row_h = row.custom_minimum_size.y
		var variation := "Mana" if id == _local_player_id else "Text"
		var rank := row.get_node("Rank") as Label
		rank.text = str(i + 1)
		rank.theme_type_variation = variation
		_bind_avatar(row.get_node("Avatar"), _header_img(id))
		var nm := row.get_node("Name") as Label
		nm.text = _player_name(id)
		nm.theme_type_variation = variation
		_set_text(row, "Class", _class_shown(id))
		_set_text(row, "Score", str(_num(_pl(id).get("score"))))
	_board.size.y = 40.0 + ids.size() * row_h + 12.0


# -----------------------------------------------------------------------------
# 本批新增：与 ModalLayer 配套的等待输入 / 弹窗 / AI 推进 / 出牌区新排版
# -----------------------------------------------------------------------------
var _card_select_request: Dictionary = {}
var _card_select_hidden: Dictionary = {}
var _card_select_submit: Callable = Callable()
var _card_select_effect: BaseEffect = null
var _card_select_picked: Array = []
var _card_select_cards: Array = []
var _player_select_effect: BaseEffect = null
var _player_select_panel_ready: bool = false
var _pending_tactical_action: Dictionary = {}
var _pending_confirm_desc: String = ""
var _confirm_alert_mode: bool = false
var _should_end_after_confirm: bool = false

const AI_STEP_INTERVAL := 0.7

func _process_waiting_inputs(_delta: float) -> void:
	if _is_debug_console_blocking_progress():
		return
	if _effect_result_modal != null and _effect_result_modal.visible:
		_current_waiting_effect = null
		return
	if _tactical_confirm != null and _tactical_confirm.visible:
		return
	_check_waiting_effects()
	_check_waiting_card_selection()
	_check_waiting_player_selection()
	_check_waiting_location_selection()
	_flush_effect_messages()


# --- 等待效果发动 / 放弃 ---
func _check_waiting_effects() -> void:
	if not EffectManager.is_waiting_for_choice():
		if _effect_modal != null and _effect_modal.visible:
			_effect_modal.visible = false
			_current_waiting_effect = null
		return
	var pending: BaseEffect = EffectManager.get_pending_active_effect()
	if pending == null:
		return
	var trigger_id: int = pending._trigger_player_id
	if trigger_id != _local_player_id and trigger_id >= 0:
		DummyBot.new().resolve_active_effect(pending, trigger_id)
		refresh_all_ui()
		return
	if pending != _current_waiting_effect:
		_current_waiting_effect = pending
		_show_effect_modal(pending)


# --- 令咒入口：把已持有令咒之一做成可点击，规则与旧控制器同源 ---
func _bind_command_spell_entry(card: Control) -> void:
	if card == null:
		return
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.set_meta("clickable", true)
	if not card.has_meta("command_spell_bound"):
		card.set_meta("command_spell_bound", true)
		card.gui_input.connect(_on_command_spell_clicked)
	_refresh_command_spell_glow(card)


func _command_spell_block_reason() -> String:
	if GameData.player_data_library.has(_local_player_id):
		var pl: Dictionary = GameDataManager.get_player_data(_local_player_id)
		var cards: Array = GetPlCommandSpellOutGame.new().exec(_local_player_id)
		var can_use := false
		for c in cards:
			var effs = c.get("_effects") if c != null else null
			if not (effs is Array):
				continue
			for e in effs:
				if EffectManager.can_manual_activate(e, _local_player_id):
					can_use = true
					break
			if can_use:
				break
		if can_use:
			return ""
		var cnt: int = _num(pl.get("command_spell_count"))
		if cnt <= 0:
			return "没有令咒可用"
	if EffectManager.is_waiting_for_choice() or EffectManager.is_waiting_for_card_selection():
		return "请先处理当前待你答复的效果"
	return "现在不能发动令咒"


func _refresh_command_spell_glow(card: Control) -> void:
	if card == null:
		return
	var reason := _command_spell_block_reason()
	if reason == "":
		_breathe(card)
	else:
		card.modulate.a = 0.55


func _on_command_spell_clicked(event: InputEvent) -> void:
	if _is_progress_blocked():
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	if _tactical_confirm != null and _tactical_confirm.visible:
		return
	if _effect_modal != null and _effect_modal.visible:
		return
	var reason := _command_spell_block_reason()
	if reason != "":
		_say(reason)
		return
	var cards: Array = GetPlCommandSpellOutGame.new().exec(_local_player_id)
	for c in cards:
		var effs = c.get("_effects") if c != null else null
		if not (effs is Array):
			continue
		for e in effs:
			if EffectManager.can_manual_activate(e, _local_player_id):
				if EffectManager.request_manual_activation(e, _local_player_id):
					refresh_all_ui()
					return


# --- 等待选牌 ---
func _check_waiting_card_selection() -> void:
	var pending: Dictionary = EffectManager.get_pending_card_selection()
	if pending.is_empty():
		if _card_select_panel != null and _card_select_panel.visible:
			_card_select_panel.visible = false
		_card_select_effect = null
		_card_select_picked = []
		return
	var eff: BaseEffect = pending.get("effect")
	if eff == null:
		return
	var trigger_id: int = eff._trigger_player_id
	if trigger_id != _local_player_id and trigger_id >= 0:
		DummyBot.new().resolve_card_selection(pending)
		refresh_all_ui()
		return
	if _card_select_effect != eff or _card_select_panel == null or not _card_select_panel.visible:
		_card_select_effect = eff
		_card_select_picked = []
		_show_card_select_panel(pending)


# --- 等待选玩家 ---
func _check_waiting_player_selection() -> void:
	var pending: Dictionary = EffectManager.get_pending_player_selection()
	if pending.is_empty():
		if _player_select_panel != null and _player_select_panel.visible:
			_player_select_panel.visible = false
		_player_select_effect = null
		return
	var eff: BaseEffect = pending.get("effect")
	if eff == null:
		return
	var trigger_id: int = eff._trigger_player_id
	if trigger_id != _local_player_id and trigger_id >= 0:
		DummyBot.new().resolve_player_selection(pending)
		return
	if _player_select_effect != eff or _player_select_panel == null or not _player_select_panel.visible:
		_show_player_select_panel(pending)


# --- 等待选位置 ---
func _check_waiting_location_selection() -> void:
	var pending: Dictionary = EffectManager.get_pending_location_selection()
	if pending.is_empty():
		return
	var eff: BaseEffect = pending.get("effect")
	if eff == null:
		return
	var trigger_id: int = eff._trigger_player_id
	if trigger_id != _local_player_id and trigger_id >= 0:
		DummyBot.new().resolve_location_selection(pending, self)


# --- AI 推进 ---
func _check_and_step_ai(delta: float) -> void:
	if _broadcast_active:
		return
	if GameProgress.is_game_over:
		return
	if _effect_result_modal != null and _effect_result_modal.visible:
		return
	if _ai_acting:
		if GameProgress.current_player_id != _ai_acting_for_id:
			_ai_acting = false
		return
	var curr_id: int = GameProgress.current_player_id
	if curr_id < 0:
		return
	var phase_name: String = str(GameProgress.get_current_phase().get("name", ""))
	var acts_here: bool = curr_id >= 0 and (GameProgress.is_phase_for(curr_id, "outpost") or GameProgress.is_phase_for(curr_id, "action"))
	if (phase_name == "battle" or phase_name == "prepare") and not acts_here:
		if curr_id == _local_player_id:
			if phase_name == "battle" and EffectManager.has_manual_activation(curr_id):
				return
			if phase_name != "battle" and EffectManager.has_manual_activation(curr_id):
				return
			GameProgress.end_current_player_action()
			return
		if not EffectManager.has_manual_activation(curr_id):
			GameProgress.end_current_player_action()
			return
		_ai_cooldown -= delta
		if _ai_cooldown > 0.0:
			return
		_ai_cooldown = AI_STEP_INTERVAL
		_ai_acting = true
		_ai_acting_for_id = curr_id
		_run_dummy_bot_turn(curr_id)
		_ai_acting = false
		return
	if curr_id == _local_player_id:
		_ai_cooldown = 0.0
		return
	_ai_cooldown -= delta
	if _ai_cooldown > 0.0:
		return
	_ai_cooldown = AI_STEP_INTERVAL
	_ai_acting = true
	_ai_acting_for_id = curr_id
	_run_dummy_bot_turn(curr_id)
	_ai_acting = false


func _run_dummy_bot_turn(bot_id: int) -> void:
	_ai_play_prompt_player_id = -1
	_ai_play_prompt_card = null
	_ai_play_prompt_round = -1
	if is_instance_valid(_ai_play_prompt_node):
		_ai_play_prompt_node.visible = false
	DummyBot.new().step(self, bot_id)


# --- AI 宿主契约（与 DummyBot 签名一致） ---
func ai_deploy_areas() -> Array:
	var areas: Array = []
	for area: BaseMapArea in MapData.areas:
		if not DeployRules.open_locations(area).is_empty():
			areas.append(area)
	return areas


func ai_pick_deploy_location(area: BaseMapArea) -> BaseLocation:
	return DeployRules.pick_location(area)


func ai_apply_deploy_benefit(loc: BaseLocation, bot_id: int) -> void:
	DeployRules.apply_benefit(loc, bot_id)


func ai_record_played_card(bot_id: int, card: BaseCard) -> void:
	if bot_id == _local_player_id:
		return
	# 出牌的表现交给卷轴里的入场动画：这里只记下是谁打的，不再弹浮动提示
	_ai_play_prompt_player_id = bot_id
	_ai_play_prompt_card = card
	_ai_play_prompt_round = GameProgress.current_round
	if is_instance_valid(_ai_play_prompt_node):
		_ai_play_prompt_node.visible = false


func ai_pick_effect_location(spec: Dictionary) -> BaseLocation:
	var forbidden: Array = spec.get("forbidden_target_areas", []) as Array
	for area: BaseMapArea in MapData.areas:
		if forbidden.has(str(area._area_name)):
			continue
		var target: BaseLocation = TacticalBoardUI._first_effect_location_target(area, spec)
		if target != null:
			return target
	return null


# --- 终局展示 ---
## 对局结束时打开战果榜一次并报出胜者；只展示一次，不会被刷新重复弹出
func _check_game_over() -> void:
	if _game_over_shown or not GameProgress.is_game_over:
		return
	_game_over_shown = true
	if _board != null:
		_board.visible = true
		_bind_board()
	var ids := _score_sorted_ids()
	if not ids.is_empty():
		_say("对局结束 · 战果最高 %s" % _player_name(int(ids[0])))
	refresh_all_ui()


# --- 调试控制台（与旧控制器同源） ---
func _is_debug_console_blocking_progress() -> bool:
	return is_debug_console_enabled() and _debug_console != null and _debug_console.session != null and _debug_console.session.is_paused()


## 进度闸门：调试控制台暂停、或顺位动画（换人交接 / 轮次更迭）仍在播放时，界面不接受推进操作。
## 等动画演完再开始行动，否则玩家的结束阶段会和动画抢同一批卡片、把动画顶掉。
func _is_progress_blocked() -> bool:
	return _is_debug_console_blocking_progress() or _rival_anim_busy or _phase_anim_busy or _broadcast_active


func set_debug_console_enabled(enabled: bool) -> void:
	if enabled:
		if is_debug_console_enabled():
			return
		var scene := ResourceLoader.load(
			"res://assets/scenes/debug/debug_console.tscn",
			"PackedScene", ResourceLoader.CACHE_MODE_IGNORE
		) as PackedScene
		if scene == null:
			return
		_debug_console = scene.instantiate() as DebugConsoleUI
		if _debug_console == null:
			return
		add_child(_debug_console)
		_debug_console.initialize(self)
		return
	if not is_debug_console_enabled():
		return
	_debug_console.safe_shutdown()
	_debug_console.queue_free()
	_debug_console = null


func is_debug_console_enabled() -> bool:
	return _debug_console != null and is_instance_valid(_debug_console)


func discard_debug_console_pending_previews() -> void:
	_selected_cards.clear()
	_submitting = false
	if _tactical_confirm != null:
		_tactical_confirm.visible = false
	_pending_tactical_action.clear()
	_pending_confirm_desc = ""
	_confirm_alert_mode = false
	_card_select_request = {}
	_card_select_submit = Callable()
	_card_select_picked = []
	_card_select_hidden = {}
	_card_select_effect = null
	if _card_select_panel != null:
		_card_select_panel.visible = false
	_player_select_effect = null
	if _player_select_panel != null:
		_player_select_panel.visible = false
	_current_waiting_effect = null
	if _effect_modal != null:
		_effect_modal.visible = false
	refresh_all_ui()


# --- 弹窗：确认 / 提示 ---
func _show_tactical_confirm(desc_str: String, is_alert: bool = false) -> void:
	if _tactical_confirm == null:
		return
	var desc_lbl := _tactical_confirm.get_node_or_null("Box/ConfirmDesc") as Label
	if desc_lbl:
		desc_lbl.text = desc_str
	var btn_ok := _tactical_confirm.get_node_or_null("Box/ButtonsRow/BtnConfirmAction") as Button
	if btn_ok:
		btn_ok.visible = not is_alert
	var btn_cancel := _tactical_confirm.get_node_or_null("Box/ButtonsRow/BtnCancelAction") as Button
	if btn_cancel:
		btn_cancel.text = "知道了" if is_alert else "取消"
	_confirm_alert_mode = is_alert
	if not is_alert:
		_pending_confirm_desc = desc_str
	_tactical_confirm.visible = true
	_raise_modal(_tactical_confirm)


func _on_tactical_confirm_execute() -> void:
	if _is_progress_blocked():
		return
	if _tactical_confirm != null:
		_tactical_confirm.visible = false
	var act_type: String = _pending_tactical_action.get("type", "")
	if act_type == "deploy":
		var target_loc = _pending_tactical_action.get("target_loc")
		if target_loc is BaseLocation:
			var before_loc = GameDataManager.get_player_data(_local_player_id).get("location")
			Deploy.new().exec(target_loc, _local_player_id)
			var after_loc = GameDataManager.get_player_data(_local_player_id).get("location")
			if after_loc == before_loc:
				_show_tactical_confirm("无法部署至目标席位", true)
			else:
				DeployRules.apply_benefit(target_loc, _local_player_id)
				GameProgress.end_current_player_action()
	elif act_type == "move":
		var step: int = _pending_tactical_action.get("step_diff", 0)
		var before_loc = GameDataManager.get_player_data(_local_player_id).get("location")
		if step > 0:
			Move.new().exec(BaseNumber.new(step), _local_player_id)
		var after_loc = GameDataManager.get_player_data(_local_player_id).get("location")
		if after_loc == before_loc:
			var target_name: String = str(_pending_tactical_action.get("target_area_name", "目标战区"))
			var msgs: Array = EffectManager.pop_messages(_local_player_id)
			if msgs.is_empty():
				_show_tactical_confirm("无法移动至【%s】" % target_name, true)
			else:
				_show_tactical_confirm("\n".join(msgs.map(func(m): return str(m))), true)
	_pending_tactical_action.clear()
	refresh_all_ui()


func _on_tactical_confirm_cancel() -> void:
	if _tactical_confirm != null:
		_tactical_confirm.visible = false
	if _confirm_alert_mode:
		_confirm_alert_mode = false
		if not _pending_tactical_action.is_empty() and _pending_confirm_desc != "":
			_show_tactical_confirm(_pending_confirm_desc, false)
		return
	_pending_tactical_action.clear()
	_pending_confirm_desc = ""


# --- 主动效果发动弹窗 ---
## 选项类效果(单选/多选)动态生成勾选行；声明了 quantity_range 的选项额外带数量选择器；
## 无选项效果显示消耗资源行。判据走同一个引擎入口，界面不自己判规则
func _show_effect_modal(effect: BaseEffect) -> void:
	if _effect_modal == null:
		return
	var desc_lbl := _effect_modal.get_node_or_null("Box/Desc") as Label
	var options_row := _effect_modal.get_node_or_null("Box/OptionsRow") as VBoxContainer
	var btn_confirm := _effect_modal.get_node_or_null("Box/ButtonsRow/BtnConfirm") as Button
	var btn_cancel := _effect_modal.get_node_or_null("Box/ButtonsRow/BtnCancel") as Button
	if desc_lbl == null:
		return
	var eff_name: String = effect._shown_name if effect._shown_name != "" else "未知效果"
	if btn_cancel:
		btn_cancel.visible = true
	if effect.has_options():
		var is_multi: bool = effect.allows_multi_choice()
		desc_lbl.text = _attach_effect_cost_line("发动【%s】\n%s" % [eff_name, ("请选择要发动的效果，可多选" if is_multi else "请选择要发动的效果")], effect)
		if options_row:
			for child in options_row.get_children():
				child.queue_free()
			options_row.visible = true
			for i in range(effect._options.size()):
				var opt: Dictionary = effect._options[i]
				var opt_name: String = str(opt.get("shown_option_name", "选项%d" % (i + 1)))
				var available: bool = EffectManager.is_option_available(effect, i)
				if not available:
					# 用尽或不可选：写明原因并禁用；界面文案不加括号补充
					var opt_max: int = int(opt.get("max_uses", -1))
					opt_name += " · 已用完" if opt_max != -1 else " · 不可选"
				var has_qty: bool = opt.has("quantity_range")
				if is_multi:
					var row := HBoxContainer.new()
					row.name = "OptRow_%d" % i
					var cb := CheckBox.new()
					cb.text = opt_name
					cb.name = "Opt_%d" % i
					cb.disabled = not available
					cb.toggled.connect(_refresh_effect_confirm_state.bind(options_row, btn_confirm))
					row.add_child(cb)
					if has_qty and available:
						row.add_child(_build_quantity_spinbox(opt["quantity_range"], i))
					options_row.add_child(row)
				elif has_qty:
					# 单选带数量：选好数量再点确认，不是点了就走
					var row := HBoxContainer.new()
					row.name = "OptRow_%d" % i
					var lbl := Label.new()
					lbl.text = opt_name
					row.add_child(lbl)
					var spin := _build_quantity_spinbox(opt["quantity_range"], i)
					row.add_child(spin)
					var confirm_btn := Button.new()
					confirm_btn.text = "确认"
					confirm_btn.disabled = not available
					confirm_btn.pressed.connect(_on_effect_option_picked_with_quantity.bind(i, spin))
					row.add_child(confirm_btn)
					options_row.add_child(row)
				else:
					var opt_btn := Button.new()
					opt_btn.text = opt_name
					opt_btn.custom_minimum_size = Vector2(0, 38)
					opt_btn.disabled = not available
					opt_btn.pressed.connect(_on_effect_option_picked.bind(i))
					options_row.add_child(opt_btn)
		if btn_confirm:
			btn_confirm.visible = is_multi
			btn_confirm.text = "确认发动"
			_refresh_effect_confirm_state(options_row, btn_confirm)
	else:
		if options_row:
			options_row.visible = false
			for child in options_row.get_children():
				child.queue_free()
		if btn_confirm:
			btn_confirm.visible = true
			btn_confirm.disabled = false
			btn_confirm.text = "确认发动"
		desc_lbl.text = _attach_effect_cost_line("发动【%s】" % eff_name, effect)
	_effect_modal.visible = true
	_raise_modal(_effect_modal)


## 效果消耗行：复用旧控制器的成本格式化，界面不另写一套资源名
func _attach_effect_cost_line(base_text: String, effect: BaseEffect) -> String:
	return TacticalBoardUI._attach_cost_line(base_text, TacticalBoardUI._resolve_effect_cost_items(effect))


## 通用数量选择器：min~max 的 SpinBox，供声明了 quantity_range 的选项复用
func _build_quantity_spinbox(range_arr: Array, option_index: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.name = "Qty_%d" % option_index
	var min_value: int = int(range_arr[0]) if range_arr.size() > 0 else 1
	var max_value: int = int(range_arr[1]) if range_arr.size() > 1 else min_value
	spin.min_value = min_value
	spin.max_value = max_value
	spin.value = min_value
	spin.custom_minimum_size = Vector2(90, 0)
	return spin


## 单选带数量：先记录数量再提交该选项
func _on_effect_option_picked_with_quantity(option_index: int, spin: SpinBox) -> void:
	if _current_waiting_effect:
		var eff: BaseEffect = _current_waiting_effect
		var qty: int = int(spin.value) if spin != null else 1
		_current_waiting_effect = null
		if _effect_modal != null:
			_effect_modal.visible = false
		eff.set_option_quantity(option_index, qty)
		EffectManager.submit_option_choice(eff, [option_index])
		refresh_all_ui()


func _refresh_effect_confirm_state(options_row: Control, btn_confirm: Button) -> void:
	if btn_confirm == null or options_row == null:
		return
	var any_checked: bool = false
	for i in range(options_row.get_child_count()):
		var row := options_row.get_child(i)
		var cb := row.get_node_or_null("Opt_%d" % i) as CheckBox
		if cb == null:
			cb = row as CheckBox
		if cb and cb.button_pressed:
			any_checked = true
			break
	btn_confirm.disabled = not any_checked


func _on_effect_option_picked(option_index: int) -> void:
	if _current_waiting_effect:
		var eff: BaseEffect = _current_waiting_effect
		_current_waiting_effect = null
		if _effect_modal != null:
			_effect_modal.visible = false
		EffectManager.submit_option_choice(eff, [option_index])
		refresh_all_ui()


func _on_effect_modal_confirm() -> void:
	if _current_waiting_effect:
		var eff: BaseEffect = _current_waiting_effect
		_current_waiting_effect = null
		if _effect_modal != null:
			_effect_modal.visible = false
		if eff.has_options() and eff.allows_multi_choice():
			var picked: Array = []
			var options_row := _effect_modal.get_node_or_null("Box/OptionsRow") as VBoxContainer
			if options_row:
				for i in range(options_row.get_child_count()):
					var row := options_row.get_child(i)
					var cb := row.get_node_or_null("Opt_%d" % i) as CheckBox
					if cb == null:
						cb = row as CheckBox
					if cb and cb.button_pressed:
						picked.append(i)
						var spin := row.get_node_or_null("Qty_%d" % i) as SpinBox
						if spin != null:
							eff.set_option_quantity(i, int(spin.value))
			EffectManager.submit_option_choice(eff, picked)
		else:
			EffectManager.submit_active_choice(eff, true)
		refresh_all_ui()


func _on_effect_modal_cancel() -> void:
	if _current_waiting_effect:
		var eff: BaseEffect = _current_waiting_effect
		_current_waiting_effect = null
		if _effect_modal != null:
			_effect_modal.visible = false
		EffectManager.submit_active_choice(eff, false)
		refresh_all_ui()


# --- 发动结果 / 消息 ---
func _raise_modal(panel: Control) -> void:
	if panel == null:
		return
	var parent := panel.get_parent()
	if parent == null:
		return
	var idx := parent.get_child_count() - 1
	if parent.get_child(idx) != panel:
		parent.move_child(panel, idx)


## 引擎给本地玩家的提示消息（开局资源/规则拒绝等）通过 toast 形式逐条展示，
## 不再用 _show_tactical_confirm 挡住卷轴。一次最多 N 条，剩下的留到下一帧继续
const _EFFECT_MSG_TOAST_LIMIT := 1   ## 一次只显示一条：拼成一条长文本会把提示框撑成大面板挡住牌局
const _EFFECT_MSG_TOAST_INTERVAL := 1.2

func _flush_effect_messages() -> void:
	if _local_player_id < 0:
		return
	if _effect_result_modal != null and _effect_result_modal.visible:
		return
	if _effect_modal != null and _effect_modal.visible:
		return
	var results: Array = EffectManager.pop_effect_results(_local_player_id)
	if not results.is_empty():
		var texts: Array[String] = []
		for r in results:
			var t := str(r)
			if t != "" and not texts.has(t):
				texts.append(t)
		if not texts.is_empty():
			_say_effect_batches(texts)
		return
	if _tactical_confirm != null and _tactical_confirm.visible:
		return
	var msgs: Array = EffectManager.pop_messages(_local_player_id)
	if msgs.is_empty():
		return
	var texts2: Array[String] = []
	for m in msgs:
		var s := str(m)
		if s != "" and not texts2.has(s):
			texts2.append(s)
	if texts2.is_empty():
		return
	_say_effect_batches(texts2)


## 成批提示统一走这条：一次最多若干条 toast，剩余的插回队列下一拍继续。
## 不再用模态弹窗——成批文本会盖住整个卷轴，玩家看不到牌局在发生什么
func _say_effect_batches(texts: Array) -> void:
	if texts.is_empty():
		return
	var batch: Array = texts.slice(0, _EFFECT_MSG_TOAST_LIMIT)
	var leftover: Array = texts.slice(_EFFECT_MSG_TOAST_LIMIT)
	_say("\n".join(batch))
	if not leftover.is_empty():
		if _effect_result_modal != null:
			_effect_result_modal.visible = false
		var t := get_tree().create_timer(_EFFECT_MSG_TOAST_INTERVAL)
		t.timeout.connect(func() -> void: _say_effect_batches(leftover))


func _show_effect_result(text: String) -> void:
	if _effect_result_modal == null or text == "":
		return
	var desc := _effect_result_modal.get_node_or_null("Box/ResultScroll/ResultDesc") as Label
	if desc:
		desc.text = text
	if _effect_modal != null:
		_effect_modal.visible = false
	_current_waiting_effect = null
	_effect_result_modal.visible = true
	_raise_modal(_effect_result_modal)


func _on_effect_result_closed() -> void:
	if _effect_result_modal != null:
		_effect_result_modal.visible = false
	_check_waiting_effects()


# --- 选牌浮层 ---
func _show_card_select_panel(pending: Dictionary) -> void:
	if _card_select_panel == null:
		return
	_card_select_cards = pending.get("cards", [])
	_card_select_request = pending.duplicate()
	var vp := get_viewport_rect().size
	_card_select_panel.position = Vector2(maxf(0.0, (vp.x - 820.0) * 0.5), vp.y * 0.16)
	var title := _card_select_panel.get_node_or_null("Box/Title") as Label
	if title:
		title.text = _select_card_title(pending)
	var row := _card_select_panel.get_node_or_null("Box/CardScroll/CardRow") as HBoxContainer
	if row == null:
		return
	for child in row.get_children():
		child.queue_free()
	for card in _card_select_cards:
		var rect := TextureRect.new()
		rect.custom_minimum_size = Vector2(146, 200)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.mouse_filter = Control.MOUSE_FILTER_STOP
		rect.set_meta("select_card", card)
		rect.gui_input.connect(_on_select_card_input.bind(rect))
		_render_card_face(rect, card, true)
		row.add_child(rect)
	_card_select_panel.visible = true
	_raise_modal(_card_select_panel)
	_refresh_card_select_confirm(pending)


## 选牌面板标题：效果名 + 数量范围。秘密选择不展示数量提示以免泄露
func _select_card_title(pending: Dictionary) -> String:
	var eff = pending.get("effect")
	var base_name := str(pending.get("shown_name", "请选择牌"))
	if eff != null and (eff._options[int(pending.get("option_index", 0))] as Dictionary).get("tags", []).has("secret_choice"):
		return base_name
	var low: int = int(pending.get("min", 1))
	var high: int = int(pending.get("max", low))
	var range_text: String = ("%d-%d" % [low, high]) if high != -1 else ("至少 %d" % low)
	return "%s · 选择 %s" % [base_name, range_text]


## 选牌面板"确认"按钮文案：动词来自选项 declaration.verb，缺省按数据语义"确认弃置/确认选择"
func _select_card_confirm_text(pending: Dictionary) -> String:
	var verb: String = str(pending.get("verb", ""))
	if verb != "":
		return "确认%s" % verb
	var eff = pending.get("effect")
	if eff != null:
		var opt_idx := int(pending.get("option_index", 0))
		if opt_idx >= 0 and opt_idx < eff._options.size():
			var opt_v: String = str(eff._options[opt_idx].get("shown_option_name", ""))
			if opt_v != "":
				return "确认 %s" % opt_v
	return "确认弃置"


func _refresh_card_select_confirm(pending: Dictionary) -> void:
	if _card_select_panel == null:
		return
	var hint := _card_select_panel.get_node_or_null("Box/Hint") as Label
	if hint:
		var eff2 = pending.get("effect")
		var opt_idx := int(pending.get("option_index", 0))
		var opt_tags: Array = []
		if eff2 != null and opt_idx >= 0 and opt_idx < eff2._options.size():
			var opt_dict: Dictionary = eff2._options[opt_idx]
			var tags_v = opt_dict.get("tags", [])
			if tags_v is Array:
				opt_tags = tags_v
		var is_secret: bool = opt_tags.has("secret_choice")
		if is_secret:
			hint.text = "已选 %d" % _card_select_picked.size()
		else:
			var low: int = int(pending.get("min", 1))
			var high: int = int(pending.get("max", low))
			var range_text: String = ("%d-%d" % [low, high]) if high != -1 else ("至少 %d" % low)
			hint.text = "已选 %d · %s" % [_card_select_picked.size(), range_text]
	var btn_ok := _card_select_panel.get_node_or_null("Box/ButtonsRow/BtnConfirmSelect") as Button
	if btn_ok:
		btn_ok.text = _select_card_confirm_text(pending)
		var low2: int = int(pending.get("min", 1))
		var high2: int = int(pending.get("max", low2))
		var ok: bool = _card_select_picked.size() >= low2
		if high2 != -1 and _card_select_picked.size() > high2:
			ok = false
		btn_ok.disabled = not ok


func _on_select_card_input(ev: InputEvent, slot: Control) -> void:
	if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed):
		return
	var card = _meta_or(slot, "select_card", null)
	if card == null:
		return
	if _card_select_picked.has(card):
		_card_select_picked.erase(card)
	else:
		var pending: Dictionary = _card_select_request
		var high: int = int(pending.get("max", -1))
		if high != -1 and _card_select_picked.size() >= high:
			return
		_card_select_picked.append(card)
	_refresh_card_select_confirm(_card_select_request)


func _on_card_select_confirmed() -> void:
	if _card_select_submit.is_valid():
		_card_select_submit.call(_card_select_picked.duplicate(), _card_select_hidden.values())
		return
	var eff: BaseEffect = _card_select_effect
	if eff == null:
		return
	var picks: Array = _card_select_picked.duplicate()
	_card_select_effect = null
	_card_select_picked = []
	if _card_select_panel != null:
		_card_select_panel.visible = false
	EffectManager.submit_card_selection(eff, picks)
	refresh_all_ui()


func _on_card_select_cancelled() -> void:
	if _card_select_request.get("regular", false):
		_card_select_request = {}
		_card_select_submit = Callable()
		_card_select_picked = []
		_card_select_hidden = {}
		_card_select_panel.hide()
		return
	var eff: BaseEffect = _card_select_effect
	_card_select_effect = null
	_card_select_picked = []
	if _card_select_panel != null:
		_card_select_panel.visible = false
	if eff != null:
		EffectManager.submit_card_selection(eff, [])
	refresh_all_ui()


# --- 选人浮层 ---
func _show_player_select_panel(pending: Dictionary) -> void:
	var eff: BaseEffect = pending.get("effect")
	if eff == null:
		return
	_player_select_effect = eff
	if _player_select_panel == null:
		return
	var vp := get_viewport_rect().size
	_player_select_panel.position = Vector2(maxf(0.0, (vp.x - 520.0) * 0.5), vp.y * 0.2)
	var title := _player_select_panel.get_node_or_null("Box/Title") as Label
	if title:
		title.text = str(eff._shown_name)
	var row := _player_select_panel.get_node_or_null("Box/NameRow") as HBoxContainer
	if row == null:
		return
	for child in row.get_children():
		child.queue_free()
	for raw_id in pending.get("candidates", []):
		var pid: int = int(raw_id)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(120, 44)
		btn.text = _player_name(pid)
		btn.pressed.connect(func(): _on_player_target_picked(pid))
		row.add_child(btn)
	_player_select_panel.visible = true
	_raise_modal(_player_select_panel)


func _on_player_target_picked(player_id: int) -> void:
	if _player_select_effect == null:
		return
	var eff: BaseEffect = _player_select_effect
	_player_select_effect = null
	if _player_select_panel != null:
		_player_select_panel.visible = false
	EffectManager.submit_player_selection(eff, [player_id])
	refresh_all_ui()


# --- 战报 ---
## 战斗结算并入日志：日志弹窗按"本次战斗结算 → 历史日志"的顺序展示同一份记录。
## 战报不再是独立入口，避免与日志重复展示同一批信息
func _battle_result_lines(res: Dictionary, header: String) -> Array[String]:
	var out: Array[String] = []
	var details: Dictionary = res.get("details_by_area", {})
	if details.is_empty():
		return out
	out.append(header)
	for area_name in details.keys():
		out.append(_battle_result_line(str(area_name), details[area_name]))
	return out


## 单个战区的结算文案：胜者与最高威力，或无需战斗 / 无人获胜
func _battle_result_line(area_name: String, detail: Dictionary) -> String:
	var winners: Array = detail.get("winners", [])
	var needs_win: bool = bool(detail.get("needs_win", true))
	if not needs_win:
		return "【%s】无需战斗，在场者共同获得战果" % area_name
	if winners.is_empty():
		return "【%s】无人可获胜，战区战果保留" % area_name
	var names := PackedStringArray()
	for wid in winners:
		names.append(_player_name(int(wid)))
	return "【%s】胜者：%s，最高威力 %d" % [area_name, "、".join(names), int(detail.get("highest_power", 0))]


# --- 战斗胜利播报 ---
## 全屏遮罩层：骨架（背板/暗角/粒子/标题/副标题/滚动区/继续按钮）在 tscn 里，脚本只按数据
## 生成每个战场的明细块并绑定文案、播放入场与确认节奏。样式用 v2 既有 Theme 变体 + 自绘金色装饰。
func _battle_broadcast_node() -> Control:
	if _broadcast_node != null and is_instance_valid(_broadcast_node):
		return _broadcast_node
	_broadcast_node = get_node_or_null("BattleBroadcast") as Control
	if _broadcast_node == null:
		return null
	var btn := _broadcast_node.get_node("ContinueBtn") as Button
	if btn != null and not btn.pressed.is_connected(_on_broadcast_continue_pressed):
		btn.pressed.connect(_on_broadcast_continue_pressed)
	_broadcast_node.hide()
	return _broadcast_node


## 每帧检查：结算暂停后弹出播报；AI 玩家逐人自动确认；全部确认后引擎放行并收起。
func _update_battle_broadcast(delta: float) -> void:
	if GameProgress == null:
		return
	var pending := GameProgress.is_battle_broadcast_pending()
	if pending and not _broadcast_active:
		_show_battle_broadcast()
	elif not pending and _broadcast_active:
		# 兜底：引擎已放行但播报还挂着（如外部直接全部确认），收起
		_hide_broadcast()
	if _broadcast_active:
		_tick_broadcast_ai_confirm(delta)
		_refresh_broadcast_continue()


## 弹出播报：逐战场生成明细块，再播放标题 + 分块入场。
func _show_battle_broadcast() -> void:
	var overlay := _battle_broadcast_node()
	if overlay == null:
		return
	var res: Dictionary = GameProgress.last_battle_result if GameProgress else {}
	var details: Dictionary = res.get("details_by_area", {})
	var list := overlay.get_node("AreaScroll/List") as VBoxContainer
	_clear(list)
	# 按地图从左到右的顺序（MapData.areas）从上到下排列
	for area: BaseMapArea in MapData.areas:
		var area_name := str(area._area_name)
		if details.has(area_name):
			list.add_child(_build_broadcast_area_row(area_name, details[area_name]))
	_broadcast_active = true
	_broadcast_reveal_done = false
	_broadcast_ai_queue = []
	_broadcast_ai_timer = 0.0
	overlay.modulate.a = 0.0
	overlay.visible = true
	move_child(overlay, get_child_count() - 1)
	_play_broadcast_open(overlay, list)


## 入场动画：背板淡入 + 标题缩放回弹 + 各战场块依次淡入，放完后开始 AI 逐人确认。
func _play_broadcast_open(overlay: Control, list: VBoxContainer) -> void:
	if _broadcast_reveal_tween != null and _broadcast_reveal_tween.is_valid():
		_broadcast_reveal_tween.kill()
	var title := overlay.get_node("Title") as Label
	var sub := overlay.get_node("Subtitle") as Label
	var continue_btn := overlay.get_node("ContinueBtn") as Button
	continue_btn.visible = false
	continue_btn.modulate.a = 0.0
	var rows: Array = []
	for child in list.get_children():
		if child is Control:
			rows.append(child)
	for row in rows:
		(row as Control).modulate.a = 0.0
	title.pivot_offset = title.size * 0.5
	title.scale = Vector2(0.72, 0.72)
	title.modulate.a = 0.0
	sub.modulate.a = 0.0
	_broadcast_reveal_tween = create_tween()
	_broadcast_reveal_tween.tween_property(overlay, "modulate:a", 1.0, BROADCAST_BACKDROP_FADE)
	_broadcast_reveal_tween.set_parallel(true)
	_broadcast_reveal_tween.tween_property(title, "modulate:a", 1.0, BROADCAST_TITLE_SECONDS)
	_broadcast_reveal_tween.tween_property(title, "scale", Vector2.ONE, BROADCAST_TITLE_SECONDS * 1.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_broadcast_reveal_tween.tween_property(sub, "modulate:a", 1.0, BROADCAST_TITLE_SECONDS)
	_broadcast_reveal_tween.set_parallel(false)
	for i in range(rows.size()):
		var r := rows[i] as Control
		_broadcast_reveal_tween.tween_property(r, "modulate:a", 1.0, BROADCAST_CARD_STEP)
	_broadcast_reveal_tween.tween_callback(func() -> void:
		_broadcast_reveal_done = true
		_queue_ai_confirmations()
	)


## 把非本地的在局玩家排进自动确认队列：他们没界面，逐人自动确认。
func _queue_ai_confirmations() -> void:
	_broadcast_ai_queue = []
	if GameProgress == null:
		return
	for id in GameProgress.battle_broadcast_confirmers():
		if int(id) != _local_player_id:
			_broadcast_ai_queue.append(int(id))
	_broadcast_ai_timer = 0.0


## AI 玩家逐人确认：让「已确认 n/7」可见地累加，而不是瞬间跳满。
func _tick_broadcast_ai_confirm(delta: float) -> void:
	if not _broadcast_reveal_done or _broadcast_ai_queue.is_empty():
		return
	_broadcast_ai_timer += delta
	if _broadcast_ai_timer < BROADCAST_AI_CONFIRM_STEP:
		return
	_broadcast_ai_timer = 0.0
	GameProgress.confirm_battle_broadcast(int(_broadcast_ai_queue.pop_front()))


## 亮起「继续」按钮并实时刷新「已确认 n/7」提示。
func _refresh_broadcast_continue() -> void:
	var overlay := _battle_broadcast_node()
	if overlay == null:
		return
	var btn := overlay.get_node("ContinueBtn") as Button
	if not _broadcast_reveal_done:
		return
	if not btn.visible:
		btn.visible = true
		btn.modulate.a = 0.0
		var tw := btn.create_tween()
		tw.tween_property(btn, "modulate:a", 1.0, 0.3)
	var confirmed := GameProgress.battle_broadcast_confirmed_count()
	var total := GameProgress.battle_broadcast_confirmers().size()
	btn.text = "继续（已确认 %d/%d）" % [confirmed, total]


## 「继续」按钮：本地玩家确认自己；AI 玩家由上面的逐人自动确认补齐。
func _on_broadcast_continue_pressed() -> void:
	if GameProgress != null and GameProgress.is_battle_broadcast_pending():
		GameProgress.confirm_battle_broadcast(_local_player_id)


func _hide_broadcast() -> void:
	_broadcast_active = false
	if _broadcast_reveal_tween != null and _broadcast_reveal_tween.is_valid():
		_broadcast_reveal_tween.kill()
	var overlay := _battle_broadcast_node()
	if overlay != null:
		overlay.visible = false


## 一个战场的结算明细块：结论 + 每名参战者的威力构成 + 战果去向。
## 所有数值都读 BattleResolver 写好的 last_battle_result，界面不重算威力/战果/胜负。
func _build_broadcast_area_row(area_name: String, detail: Dictionary) -> Control:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.11, 0.78)
	sb.border_color = Color(0.72, 0.56, 0.26, 0.5)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	row.add_theme_stylebox_override("panel", sb)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# 战区地图半透明背景（铺满卡片，垫在内容之下）
	var area_img := _broadcast_area_image(area_name)
	if area_img != "" and LoadHelper.texture_exists(area_img):
		var bg := TextureRect.new()
		bg.texture = LoadHelper.load_texture(area_img)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.modulate = Color(1, 1, 1, 0.14)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bg)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.add_child(box)
	row.add_child(margin)

	var winners: Array = detail.get("winners", [])
	var needs_win: bool = bool(detail.get("needs_win", true))
	# 标题只写战区名
	var title := Label.new()
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font", _broadcast_font(true))
	title.add_theme_font_size_override("font_size", 24)
	title.text = area_name
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	box.add_child(title)
	# 结论：仅战斗区域写胜者；魔术工房/侦察（无需比威力）只写标题不写胜者
	if needs_win:
		var concl := Label.new()
		concl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		concl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		concl.add_theme_font_override("font", _broadcast_font(false))
		concl.add_theme_font_size_override("font_size", 16)
		if winners.is_empty():
			concl.text = "无人可获胜，战区战果保留"
			concl.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))
		else:
			concl.text = "胜者：%s" % _broadcast_names_text(winners)
			concl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		box.add_child(concl)

	# 细分隔线
	var sep := ColorRect.new()
	sep.color = Color(0.72, 0.56, 0.26, 0.32)
	sep.custom_minimum_size = Vector2(0, 1)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(sep)

	# 每名参战玩家：头像 + 威力构成
	var powers: Dictionary = detail.get("powers", {})
	var effective: Array = detail.get("effective_players", [])
	for pid in detail.get("players", []):
		var pname: String = _player_name(int(pid))
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 10)
		var avatar := TextureRect.new()
		avatar.custom_minimum_size = Vector2(36, 36)
		avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		avatar.material = _broadcast_avatar_mask()
		var himg := _header_img(int(pid))
		avatar.texture = LoadHelper.load_texture(himg) if himg != "" and LoadHelper.texture_exists(himg) else null
		prow.add_child(avatar)
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_theme_font_override("font", _broadcast_font(false))
		line.add_theme_font_size_override("font_size", 17)
		if powers.has(pid):
			var pw: Dictionary = powers[pid]
			var parts: Array[String] = ["%s 威力 %d ＝ 出牌 %d" % [pname, int(pw.get("total", 0)), int(pw.get("power", 0))]]
			for item in [["bonus", "加成"], ["board", "场上牌"], ["location_benefit", "地利"]]:
				var v: int = int(pw.get(item[0], 0))
				if v != 0:
					parts.append("%s %+d" % [item[1], v])
			line.text = " ＋ ".join(parts)
			line.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5) if winners.has(pid) else Color(0.85, 0.88, 0.95))
		elif not effective.has(pid):
			line.text = "%s 不参与胜负判定" % pname
			line.add_theme_color_override("font_color", Color(0.72, 0.62, 0.62))
		else:
			line.text = "%s 未参与威力比较" % pname
			line.add_theme_color_override("font_color", Color(0.72, 0.74, 0.8))
		prow.add_child(line)
		box.add_child(prow)

	# 战果去向：事件牌 + 竞争 = 总战果，再写每人实得净变化（含令咒 / 扣分）
	var total_score: int = int(detail.get("total_score", 0))
	var score_line := Label.new()
	score_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	score_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_line.add_theme_font_override("font", _broadcast_font(false))
	score_line.add_theme_font_size_override("font_size", 16)
	score_line.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	var gained: Dictionary = detail.get("score_gained", {})
	var gained_parts: Array[String] = []
	for pid in gained.keys():
		gained_parts.append("%s %+d" % [_player_name(int(pid)), int(gained[pid])])
	var source_text: String = "事件牌 %d ＋ 竞争 %d ＝ %d" % [int(detail.get("event_score", 0)), int(detail.get("competition_score", 0)), total_score]
	if gained_parts.is_empty():
		score_line.text = "战果 %s，无人获得" % source_text
	else:
		score_line.text = "战果 %s；%s" % [source_text, "、".join(gained_parts)]
	box.add_child(score_line)
	return row


## 播报文案的衬线中文字体（与主题 CnSys 同源：Noto Serif SC / 思源宋体 / 宋体），懒建共享。
func _broadcast_font(bold: bool) -> Font:
	if bold:
		if _broadcast_font_bold == null:
			var f := SystemFont.new()
			f.font_names = PackedStringArray(["Noto Serif SC", "Source Han Serif SC", "SimSun"])
			f.font_weight = 700
			_broadcast_font_bold = f
		return _broadcast_font_bold
	if _broadcast_font_regular == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Noto Serif SC", "Source Han Serif SC", "SimSun"])
		_broadcast_font_regular = f
	return _broadcast_font_regular


## 战区名 → 该战区的地图底图（按 MapData.areas 顺序对应 AREA_IMAGES）。
func _broadcast_area_image(area_name: String) -> String:
	for i in range(MapData.areas.size()):
		var area: BaseMapArea = MapData.areas[i]
		if str(area._area_name) == area_name:
			return _area_image(i)
	return ""


## 播报玩家头像的圆形遮罩材质（复用 ui_mask 着色器，懒建共享）
func _broadcast_avatar_mask() -> ShaderMaterial:
	if _broadcast_avatar_mat == null:
		_broadcast_avatar_mat = ShaderMaterial.new()
		_broadcast_avatar_mat.shader = load("res://assets/shaders/ui_mask.gdshader")
		_broadcast_avatar_mat.set_shader_parameter("shape", 1)
		_broadcast_avatar_mat.set_shader_parameter("softness", 0.02)
	return _broadcast_avatar_mat


## 一组玩家的示人名字，用顿号连接（平局双方、胜者名单共用）
func _broadcast_names_text(ids: Array) -> String:
	var parts: Array[String] = []
	for id in ids:
		parts.append(_player_name(int(id)))
	return "、".join(parts)


# --- 卡面渲染（明置 / 暗置 / 未激活遮罩） ---
func _render_card_face(node: TextureRect, obj, owned: bool, fallback_type: String = "skill", show_conceal_mark: bool = true, concealed_override = null) -> void:
	if node == null or obj == null:
		return
	var concealed: bool = bool(concealed_override) if concealed_override != null else (obj is BaseCard and bool(obj.get("_is_concealed")))
	if obj is BaseSkill and not bool(obj.get("_is_awakened")):
		node.texture = LoadHelper.load_texture(LoadHelper.resolve_card_back("", "", "upgrade_skill"))
		_sync_overlay(node, false, "ConcealOverlay", CONCEAL_COLOR)
		_sync_overlay(node, false, "InactiveOverlay", INACTIVE_COLOR)
		_disable_card_zoom(node)
		return
	_sync_overlay(node, concealed and owned and show_conceal_mark, "ConcealOverlay", CONCEAL_COLOR, CONCEAL_ICON)
	if concealed and not owned:
		node.texture = LoadHelper.load_texture(LoadHelper.resolve_card_back("", "", fallback_type))
		_disable_card_zoom(node)
		return
	var img = obj.get("_card_img")
	if img != null and str(img) != "" and LoadHelper.texture_exists(str(img)):
		node.texture = LoadHelper.load_texture(str(img))
	_sync_overlay(node, _is_card_inactive(obj), "InactiveOverlay", INACTIVE_COLOR)
	bind_zoom_for_card(node, obj)


func _is_card_inactive(obj) -> bool:
	var buff = obj.get("_relate_buff")
	if buff == null:
		return false
	return not bool(buff.get("_is_active"))


func _sync_overlay(node: Control, show_overlay: bool, overlay_name: String, color: Color, icon_path := "") -> void:
	var overlay := node.get_node_or_null(overlay_name) as ColorRect
	if not show_overlay:
		if overlay:
			overlay.visible = false
		return
	if overlay == null:
		overlay = ColorRect.new()
		overlay.name = overlay_name
		overlay.color = color
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		node.add_child(overlay)
		if icon_path != "":
			var icon := TextureRect.new()
			icon.name = "OverlayIcon"
			icon.texture = LoadHelper.load_texture(icon_path)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# 纯 UI 装饰，不是卡也不是头像：显式关掉放大，否则它接近正方形会被当成展示位
			icon.set_meta("zoom_disabled", true)
			overlay.add_child(icon)
	overlay.visible = true
	var icon_node := overlay.get_node_or_null("OverlayIcon") as TextureRect
	if icon_node:
		# 图标跟着卡位大小走，卡越小图标越小，始终占卡面约四成宽（与旧控制器一致）
		var side: float = maxf(18.0, minf(node.size.x, node.size.y) * 0.40)
		icon_node.custom_minimum_size = Vector2(side, side)
		icon_node.size = Vector2(side, side)
		icon_node.position = (node.size - icon_node.size) * 0.5


# --- 放大 / 说明面板 ---
func _show_zoom_for(card: Control) -> void:
	if not is_instance_valid(card) or not card.is_visible_in_tree() or bool(card.get_meta("zoom_disabled", true)):
		return
	var img_path := str(card.get_meta("zoom_img", ""))
	if img_path.is_empty() or not LoadHelper.texture_exists(img_path):
		_hide_event_zoom(false)
		return
	var tex: Texture2D = LoadHelper.load_texture(img_path)
	_hover_zoom_source = card
	_zoom_hide_remaining = -1.0
	# 说明面板与放大图共生：放大图换到别的展示位时，上一张牌的说明一起收，
	# 不让说明停留在已经不再查看的牌上。
	if _hover_desc != null and _hover_desc.visible and _desc_source_id != card.get_instance_id():
		_close_card_desc()
	# 图标左侧常显无背景小字“右键大图查看文字说明”（tscn 的 Hint/DefaultHint）；
	# 需要额外文字说明的展示位用 zoom_hint 声明（显示在图标右侧），
	# 没有说明的展示位（title 与 desc 都为空）整组提示都不显示，避免误导。
	var hint := _hover_zoom.get_node("Hint") as Control
	var hint_text := str(card.get_meta("zoom_hint", ""))
	var hint_label := hint.get_node("Text") as Label
	hint_label.text = hint_text
	hint_label.visible = not hint_text.is_empty()
	hint.visible = not hint_text.is_empty() \
		or not str(card.get_meta("zoom_title", "")).is_empty() \
		or not str(card.get_meta("zoom_desc", "")).is_empty()
	(_hover_zoom.get_node("BigCard") as TextureRect).texture = tex
	var vp := get_viewport_rect().size
	# 提示图标叠在卡图右上角，不再占底部空间
	var ratio := float(tex.get_width()) / maxf(1.0, tex.get_height())
	var image_height := minf(ZOOM_PREVIEW_HEIGHT, vp.y - 16.0)
	var width := minf(image_height * ratio, minf(ZOOM_PREVIEW_MAX_WIDTH, vp.x - 16.0))
	var height := width / ratio
	var src_rect := card.get_global_rect()
	var px := src_rect.end.x + 14.0
	if px + width > vp.x - 8.0:
		px = src_rect.position.x - width - 14.0
	px = clampf(px, 8.0, maxf(8.0, vp.x - width - 8.0))
	var py := clampf(src_rect.get_center().y - height * 0.5, 8.0, maxf(8.0, vp.y - height - 8.0))
	_hover_zoom.size = Vector2(width, height)
	_hover_zoom.global_position = Vector2(px, py)
	_hover_zoom.show()

func _hide_event_zoom(also_desc := true) -> void:
	if _hover_zoom != null:
		_hover_zoom.hide()
	_hover_zoom_source = null
	_zoom_hide_remaining = -1.0
	_zoom_hover_candidate_id = 0
	_zoom_hover_elapsed = 0.0
	if also_desc:
		_close_card_desc()


func _close_card_desc() -> void:
	if _hover_desc != null:
		_hover_desc.hide()
	_desc_source_id = 0

# --- 卡面放大与悬浮说明 ---
## 给节点绑定放大/悬浮说明：mouse_entered 显示放大卡面，mouse_exited 隐藏；
## 右键弹详细说明面板。左键仍走原本的点击逻辑（发动 / 翻面 / 选牌）。
## img_field 区分"御主头像"vs"御主卡"等同类对象的多种图片字段，缺省看 _card_img
## right_action 声明该展示位的右键语义："desc" 由这里弹出说明，"none" 表示右键已被调用方占用
## （如手牌/技能区的明置暗置），此时仍可右键放大卡图看说明。无图的展示位也能右键看说明。
func _disable_card_zoom(node: Control) -> void:
	node.set_meta("zoom_disabled", true)
	for key in ["zoom_img", "zoom_obj", "zoom_title", "zoom_desc"]:
		if node.has_meta(key):
			node.remove_meta(key)
	if node == _hover_zoom_source:
		_hide_event_zoom(false)
	if node.get_instance_id() == _desc_source_id:
		_close_card_desc()


func bind_zoom_for_card(node: Control, obj, img_field: String = "", right_action: String = "desc") -> void:
	if node == null:
		return
	var kind: String = obj.get_zoom_kind(img_field) if obj != null and obj.has_method("get_zoom_kind") else ""
	if not kind in [LoadHelper.ZOOM_KIND_CARD, LoadHelper.ZOOM_KIND_AVATAR, LoadHelper.ZOOM_KIND_TOKEN]:
		_disable_card_zoom(node)
		return
	var img = obj.get(img_field) if img_field != "" else obj.get("_card_img")
	var has_img: bool = img != null and str(img) != "" and LoadHelper.texture_exists(str(img))
	node.set_meta("zoom_img", str(img) if has_img else "")
	node.set_meta("zoom_obj", obj)
	node.set_meta("zoom_disabled", false)
	node.set_meta("zoom_title", _object_shown_name(obj))
	var desc := ""
	if kind == LoadHelper.ZOOM_KIND_CARD:
		desc = _build_card_desc(obj)
	elif kind == LoadHelper.ZOOM_KIND_TOKEN:
		desc = TacticalBoardUI._build_token_desc(obj)
	node.set_meta("zoom_desc", desc)
	node.set_meta("zoom_right_action", right_action)
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	if not node.has_meta("zoom_bound"):
		node.set_meta("zoom_bound", true)
		node.gui_input.connect(_on_zoom_target_gui_input.bind(node))


## 悬浮候选：从真实命中控件向上找最近的、声明了放大的展示位。
## 用每帧命中判定而不是 mouse_entered 脉冲：子节点抢命中、子像素进出、布局变化引起的
## 进入/离开抖动都不会误触发放大。
func _zoom_hover_candidate() -> Control:
	var node := get_viewport().gui_get_hovered_control()
	while node != null:
		if node.has_meta("zoom_bound") and not bool(node.get_meta("zoom_disabled", true)):
			return node
		node = node.get_parent() as Control
	return null


func _on_hover_zoom_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if is_instance_valid(_hover_zoom_source) and _show_desc_for(_hover_zoom_source):
			_hover_zoom.accept_event()


## 鼠标是否落在「查看卡片」的浮层上（放大卡图或说明面板，含其子节点）。
## 落在浮层上视为仍在看这张牌，保活计时冻结。
func _is_zoom_overlay(ctrl: Control) -> bool:
	if ctrl == null:
		return false
	for layer in [_hover_zoom, _hover_desc]:
		if layer != null and is_instance_valid(layer) and layer.visible \
				and (ctrl == layer or layer.is_ancestor_of(ctrl)):
			return true
	return false


## 每帧推进两件事：
## ① 悬浮够时长才放大——短暂划过、或从一张牌扫到另一张时都不弹图；
## ② 收起——源被刷新释放或被禁用时立即收，鼠标离开源卡、放大图与说明面板后按保活窗口收。
## 放大图与说明面板属于同一个「查看卡片」状态：鼠标落在源卡、放大图或说明面板上都保持，
## 三者全部离开后一起收起，说明不会在放大图消失后孤立残留在屏幕上。
func _update_hover_zoom_keepalive(delta: float) -> void:
	if _hover_zoom == null:
		return
	if _hover_zoom.visible and (not is_instance_valid(_hover_zoom_source) or _hover_zoom_source.is_queued_for_deletion() \
			or not _hover_zoom_source.is_visible_in_tree() or bool(_hover_zoom_source.get_meta("zoom_disabled", false))):
		_hide_event_zoom(false)
	var hovered := get_viewport().gui_get_hovered_control()
	if _is_zoom_overlay(hovered):
		_zoom_hide_remaining = -1.0
		return
	var candidate := _zoom_hover_candidate()
	if candidate == null:
		_zoom_hover_candidate_id = 0
		_zoom_hover_elapsed = 0.0
	else:
		# 换到别的展示位要重新计时：扫过一排牌时不该依次弹出
		if candidate.get_instance_id() != _zoom_hover_candidate_id:
			_zoom_hover_candidate_id = candidate.get_instance_id()
			_zoom_hover_elapsed = 0.0
		_zoom_hover_elapsed += delta
		if _zoom_hover_elapsed >= ZOOM_HOVER_DELAY_SECONDS:
			# 同一张展示位被二次悬浮时也要重新打开（上次可能是被别处关掉的）
			if not _hover_zoom.visible or _hover_zoom_source != candidate:
				_show_zoom_for(candidate)
			_zoom_hide_remaining = -1.0
			return
	if not _hover_zoom.visible and not (_hover_desc != null and _hover_desc.visible):
		return
	if _zoom_hide_remaining < 0.0:
		_zoom_hide_remaining = ZOOM_KEEPALIVE_SECONDS
	_zoom_hide_remaining -= delta
	if _zoom_hide_remaining <= 0.0:
		# 一并收说明：放大图消失后说明不该单独留着
		_hide_event_zoom(true)

func _on_zoom_target_gui_input(event: InputEvent, node: Control) -> void:
	if node.get_meta("zoom_disabled", false):
		return
	# 右键语义由展示位声明：明置/暗置等已占用右键的展示位只保留放大卡图上的说明入口
	if str(node.get_meta("zoom_right_action", "desc")) != "desc":
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_RIGHT:
		return
	if _show_desc_for(node):
		get_viewport().set_input_as_handled()


## 显示展示位的说明面板：卡位右键与放大卡图右键共用同一入口
func _show_desc_for(node: Control) -> bool:
	if not is_instance_valid(node) or bool(node.get_meta("zoom_disabled", true)):
		return false
	if _hover_desc.visible and _desc_source_id == node.get_instance_id():
		_close_card_desc()
		return true
	var title := str(node.get_meta("zoom_title", ""))
	var desc := str(node.get_meta("zoom_desc", ""))
	if title.is_empty() and desc.is_empty():
		return false
	_desc_source_id = node.get_instance_id()
	_set_text(_hover_desc, "VBox/Title", title)
	_set_text(_hover_desc, "VBox/Body/Desc", desc)
	(_hover_desc.get_node("VBox/Body") as ScrollContainer).scroll_vertical = 0
	_hover_desc.get_node("VBox/Body").visible = not desc.is_empty()
	var vp := get_viewport_rect().size
	_hover_desc.size = Vector2(minf(440.0, vp.x - 16.0), minf(320.0 if not desc.is_empty() else 56.0, vp.y - 16.0))
	var extent := _hover_desc.size
	var anchor := _hover_zoom.get_global_rect() if _hover_zoom.visible and node == _hover_zoom_source else node.get_global_rect()
	var candidates := [Vector2(anchor.end.x + 12.0, anchor.position.y), Vector2(anchor.position.x - extent.x - 12.0, anchor.position.y), Vector2(anchor.position.x, anchor.end.y + 12.0), Vector2(anchor.position.x, anchor.position.y - extent.y - 12.0)]
	for candidate: Vector2 in candidates:
		var point := candidate.clamp(Vector2(8, 8), (vp - extent - Vector2(8, 8)).max(Vector2(8, 8)))
		_hover_desc.global_position = point
		if not Rect2(point, extent).intersects(anchor):
			break
	_hover_desc.show()
	return true

func _object_shown_name(obj) -> String:
	if obj == null:
		return ""
	if obj.has_method("get_shown_name"):
		var s := str(obj.get_shown_name())
		if s != "":
			return s
	var n = obj.get("_name")
	return str(n) if n != null else ""


func _build_card_desc(obj) -> String:
	return TacticalBoardUI._build_card_desc(obj)


# --- 顶栏与对手抽屉接线 ---
func _on_opponent_gui_input(event: InputEvent, opponent_card: Control) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		var pid: int = int(opponent_card.get_meta("turn_order_player_id", -1))
		if pid < 0:
			return
		if _opponent_drawer.visible and _selected_opponent_id == pid:
			_opponent_drawer.visible = false
			_selected_opponent = null
			_selected_opponent_id = -1
		else:
			_selected_opponent = opponent_card
			_selected_opponent_id = pid
			opponent_card.set_meta("turn_order_player_id", pid)
			_update_drawer_visuals(opponent_card)
			_opponent_drawer.visible = true
			if _board != null:
				_board.visible = false
		get_viewport().set_input_as_handled()


func _on_close_opponent_drawer_pressed() -> void:
	_selected_opponent = null
	_selected_opponent_id = -1
	if _opponent_drawer != null:
		_opponent_drawer.visible = false


func _update_drawer_visuals(opponent_card: Control) -> void:
	if _opponent_drawer == null:
		return
	var bot_id: int = _selected_opponent_id
	if opponent_card != null and opponent_card.has_meta("turn_order_player_id"):
		bot_id = int(opponent_card.get_meta("turn_order_player_id"))
	if bot_id < 0:
		return
	_selected_opponent_id = bot_id
	_selected_opponent = opponent_card
	var pl_data: Dictionary = GameDataManager.get_player_data(bot_id)
	var master_obj = pl_data.get("master")
	var servant_obj = pl_data.get("servant")
	# 头像直接按玩家数据取：来源卡既可能是顺位 RivalCard（Avatar 是 Panel），
	# 也可能是其他形态的卡位，不依赖调用方的节点结构
	var sel_avatar := _opponent_drawer.get_node_or_null("VBox/HeaderBar/SelectedAvatarFrame/Avatar") as TextureRect
	if sel_avatar != null:
		sel_avatar.texture = LoadHelper.load_texture(_header_img(bot_id))
	var badge := _opponent_drawer.get_node_or_null("VBox/HeaderBar/OrderBadge") as Label
	if badge:
		badge.text = "%s\n战果 %d" % [_player_name(bot_id), _num(pl_data.get("score"))]
	var loc = pl_data.get("location") as BaseLocation
	var area = loc.get_from() if loc != null else null
	var area_name: String = str(area._area_name) if (area != null and "_area_name" in area) else ""
	var marker := _opponent_drawer.get_node_or_null("VBox/ResourceVisuals/BattleMarker") as Label
	if marker:
		if area_name == "":
			marker.text = "未部署"
		else:
			marker.text = area_name + (" · 交战" if bool(pl_data.get("is_battle", false)) else "")
	var played_lbl := _opponent_drawer.get_node_or_null("VBox/CardsContentRow/Col_PlayedCards_Opponent/Label") as Label
	if played_lbl:
		var opp_power: int = GetPlayerTotalPower.new().exec(bot_id)
		played_lbl.text = "⚔ %s 已打出牌 · 威力 %d" % [(area_name if area_name != "" else "未部署"), opp_power]
	var mc := _opponent_drawer.get_node_or_null("VBox/CardsContentRow/Col_MasterServant/CardsH/MasterCard") as TextureRect
	if mc != null and master_obj != null:
		mc.texture = LoadHelper.load_texture(str(master_obj.get("_master_card_img")))
		bind_zoom_for_card(mc, master_obj, "_master_card_img")
	var sc_node := _opponent_drawer.get_node_or_null("VBox/CardsContentRow/Col_MasterServant/CardsH/ServantCard") as TextureRect
	if sc_node != null and servant_obj != null:
		var revealed := ReleaseTrueName.is_released(bot_id)
		if not revealed:
			sc_node.texture = LoadHelper.load_texture(LoadHelper.resolve_card_back("", "", "servant"))
			_disable_card_zoom(sc_node)
		else:
			sc_node.texture = LoadHelper.load_texture(str(servant_obj.get("_servant_card_img")))
			bind_zoom_for_card(sc_node, servant_obj, "_servant_card_img")
	var opp_row := _opponent_drawer.get_node_or_null("VBox/CardsContentRow/Col_PlayedCards_Opponent/CardsOverlapRow") as HBoxContainer
	if opp_row != null:
		_fill_card_row_from_list(opp_row, pl_data.get("played_cards", []), false, false)
	var magic_lbl := _opponent_drawer.get_node_or_null("VBox/ResourceVisuals/MagicH/Magic") as Label
	if magic_lbl:
		magic_lbl.text = "魔力 %d" % _num(pl_data.get("magic"))
	var cs_lbl := _opponent_drawer.get_node_or_null("VBox/ResourceVisuals/CommandSpells") as Label
	if cs_lbl:
		cs_lbl.text = "令咒 ×%d" % _num(pl_data.get("command_spell_count"))
	var hint_lbl := _opponent_drawer.get_node_or_null("VBox/IdentityHint") as Label
	if hint_lbl:
		hint_lbl.text = "真名解放" if ReleaseTrueName.is_released(bot_id) else "真名未解放"


func _refresh_opponent_resource_icons() -> void:
	if _opponent_drawer != null and _opponent_drawer.visible and _selected_opponent_id >= 0:
		_update_drawer_visuals(null)


# --- AI 出牌提示 ---
func _refresh_ai_play_prompt() -> void:
	if _ai_play_prompt_card == null or _ai_play_prompt_round != GameProgress.current_round or _ai_play_prompt_player_id < 0 or GameProgress.current_player_id == _local_player_id:
		if is_instance_valid(_ai_play_prompt_node):
			_ai_play_prompt_node.visible = false
		return
	var cards: Array = GameDataManager.get_player_data(_ai_play_prompt_player_id).get("played_cards", [])
	if cards.is_empty():
		if is_instance_valid(_ai_play_prompt_node):
			_ai_play_prompt_node.visible = false
		return
	if not is_instance_valid(_ai_play_prompt_node):
		_ai_play_prompt_node = Button.new()
		_ai_play_prompt_node.name = "AIPlayPrompt"
		_ai_play_prompt_node.custom_minimum_size = Vector2(220, 140)
		_ai_play_prompt_node.pressed.connect(_on_ai_play_prompt_pressed)
		add_child(_ai_play_prompt_node)
		var title := Label.new()
		title.name = "Title"
		title.text = "已出牌 · 点击查看"
		title.position = Vector2(10, 6)
		_ai_play_prompt_node.add_child(title)
		var scroll := ScrollContainer.new()
		scroll.name = "CardsScroll"
		scroll.position = Vector2(10, 40)
		_ai_play_prompt_node.add_child(scroll)
		var row := HBoxContainer.new()
		row.name = "Cards"
		scroll.add_child(row)
	_ai_play_prompt_node.set_meta("ai_prompt_player_id", _ai_play_prompt_player_id)
	var row_node := _ai_play_prompt_node.get_node("CardsScroll/Cards") as HBoxContainer
	for child in row_node.get_children():
		child.queue_free()
	for card in cards:
		var tex := TextureRect.new()
		tex.custom_minimum_size = Vector2(82, 116)
		tex.mouse_filter = Control.MOUSE_FILTER_STOP
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_render_card_face(tex, card, false)
		tex.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_on_ai_play_prompt_pressed()
				get_viewport().set_input_as_handled()
		)
		row_node.add_child(tex)
	_ai_play_prompt_node.size = Vector2(220, 140)
	(_ai_play_prompt_node.get_node("CardsScroll") as Control).size = _ai_play_prompt_node.size - Vector2(20, 48)
	_update_ai_play_prompt_geometry()


func _update_ai_play_prompt_geometry() -> void:
	if not is_instance_valid(_ai_play_prompt_node):
		return
	if _ai_play_prompt_round != GameProgress.current_round or _ai_play_prompt_card == null or _ai_play_prompt_player_id < 0 or GameProgress.current_player_id == _local_player_id or GameDataManager.get_player_data(_ai_play_prompt_player_id).get("played_cards", []).is_empty():
		_ai_play_prompt_node.hide()
		return
	var box := _rivals as Control
	if box == null:
		_ai_play_prompt_node.hide()
		return
	var target: Control = null
	for child in box.get_children():
		if child is Control and int(child.get_meta("turn_order_player_id", -1)) == _ai_play_prompt_player_id:
			target = child
			break
	if target == null:
		_ai_play_prompt_node.hide()
		return
	var bounds := get_viewport_rect()
	var sz := _ai_play_prompt_node.get_global_rect().size
	var above_y: float = target.get_global_rect().position.y - sz.y - 4.0
	_ai_play_prompt_node.global_position = Vector2(
		clampf(target.get_global_rect().get_center().x - sz.x * 0.5, bounds.position.x, maxf(bounds.position.x, bounds.end.x - sz.x)),
		maxf(bounds.position.y, above_y))
	_ai_play_prompt_node.show()


func _on_ai_play_prompt_pressed() -> void:
	if _ai_play_prompt_node == null:
		return
	var pid: int = int(_ai_play_prompt_node.get_meta("ai_prompt_player_id", -1))
	if pid < 0:
		return
	var box := _rivals as Control
	if box == null:
		return
	for child in box.get_children():
		if child is Control and int(child.get_meta("turn_order_player_id", -1)) == pid:
			_selected_opponent = child
			_selected_opponent_id = pid
			_update_drawer_visuals(child)
			_opponent_drawer.visible = true
			if _board != null:
				_board.visible = false
			break


# --- 通用卡位填充（搬运自旧控制器） ---
func _fill_card_row_from_list(row: Control, cards: Array, clickable: bool, owned: bool = true, merge_repeated: bool = true) -> void:
	if row == null:
		return
	for child in row.get_children():
		child.queue_free()
	var list: Array = _group_repeated_cards(cards) if merge_repeated else cards.map(func(c): return {"card": c, "count": 1})
	for entry in list:
		var slot := TextureRect.new()
		slot.custom_minimum_size = Vector2(82, 116)
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		var card = entry.get("card") if entry is Dictionary else entry
		_render_card_face(slot, card, owned)
		row.add_child(slot)
		var count: int = int(entry.get("count", 1)) if entry is Dictionary else 1
		if count > 1:
			var badge := Label.new()
			badge.text = "x%d" % count
			badge.add_theme_font_size_override("font_size", 12)
			badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			slot.add_child(badge)


func _group_repeated_cards(cards: Array) -> Array:
	var out: Array = []
	for card in cards:
		var found := -1
		for i in range(out.size()):
			if out[i].get("card", null)._name == card._name:
				found = i
				break
		if found >= 0:
			out[found]["count"] += 1
		else:
			out.append({"card": card, "count": 1})
	return out


# --- 镜像旧日志格式（供战报 / 日志弹窗复用） ---
static func _format_game_log_line(e: Dictionary) -> String:
	return preload("res://assets/scripts/game_scene/tactical_board_ui.gd")._format_game_log_line(e)


# --- 战区点击（消费位置等待 / 部署 / 移动） ---
func _on_battlefield_clicked(target_area_idx: int) -> void:
	if _is_progress_blocked():
		return
	var pending_loc: Dictionary = EffectManager.get_pending_location_selection()
	if not pending_loc.is_empty():
		if target_area_idx < 0 or target_area_idx >= MapData.areas.size():
			return
		var spec: Dictionary = pending_loc.get("spec", {})
		var selected: BaseLocation = TacticalBoardUI._first_effect_location_target(MapData.areas[target_area_idx], spec)
		if selected == null:
			_show_tactical_confirm("【%s】没有可用的位置" % MapData.areas[target_area_idx]._area_name, true)
			return
		EffectManager.submit_location_selection(pending_loc["effect"], selected)
		refresh_all_ui()
		return
	var blocked: String = _area_action_block_reason(target_area_idx)
	if blocked != "":
		_show_tactical_confirm(blocked, true)
		return
	var local_data: Dictionary = GameDataManager.get_player_data(_local_player_id)
	if GameProgress.is_phase_for(_local_player_id, "outpost") and local_data.get("location") == null:
		_prepare_battlefield_deploy_confirm(target_area_idx)
	elif GameProgress.is_phase_for(_local_player_id, "action"):
		_prepare_battlefield_move_confirm(target_area_idx)


func _area_action_block_reason(target_area_idx: int) -> String:
	return TacticalBoardUI.area_action_block_reason_for(_local_player_id, target_area_idx)


func _prepare_battlefield_deploy_confirm(target_area_idx: int) -> void:
	var area: BaseMapArea = MapData.areas[target_area_idx]
	var target_loc: BaseLocation = DeployRules.pick_location(area)
	if target_loc == null:
		_show_tactical_confirm("【%s】没有可用的部署席位" % area._area_name, true)
		return
	_pending_tactical_action = {"type": "deploy", "target_loc": target_loc, "area_name": area._area_name}
	var parts: Array[String] = []
	var mg: int = _num(target_loc._magic)
	var bn: int = _num(target_loc._benefit)
	if mg > 0:
		parts.append("魔力 +%d" % mg)
	if bn > 0:
		parts.append("地利 %d" % bn)
	var benefit_text = " · ".join(parts) if not parts.is_empty() else "常规席位"
	_show_tactical_confirm("部署至【%s】 · %s" % [area._area_name, benefit_text])


func _prepare_battlefield_move_confirm(target_area_idx: int) -> void:
	var pl_data: Dictionary = GameDataManager.get_player_data(_local_player_id)
	if IsEngaged.new().exec(_local_player_id):
		_show_tactical_confirm("处于交战状态，无法移动", true)
		return
	var curr_area: BaseMapArea = TacticalBoardUI._local_current_area(pl_data)
	if curr_area == null:
		return
	var current_idx: int = MapData.areas.find(curr_area)
	if current_idx == -1:
		return
	var step_diff: int = target_area_idx - current_idx
	if step_diff <= 0:
		_show_tactical_confirm("移动只能沿单方向前进", true)
		return
	var target_area_name: String = MapData.areas[target_area_idx]._area_name
	var cost: int = TacticalBoardUI._estimate_move_cost(pl_data, step_diff)
	if not TacticalBoardUI._is_magic_enough_for_move(pl_data, cost):
		_show_tactical_confirm("移动至【%s】\n所需资源：魔力 %d\n当前魔力不足" % [target_area_name, cost], true)
		return
	_pending_tactical_action = {"type": "move", "step_diff": step_diff, "target_area_idx": target_area_idx, "target_area_name": target_area_name}
	var cost_parts: Array[String] = []
	if cost > 0:
		cost_parts.append("魔力 %d" % cost)
	var desc := "移动至【%s】" % target_area_name
	if not cost_parts.is_empty():
		desc += "\n消耗资源：" + "、".join(cost_parts)
	_show_tactical_confirm(desc)


## 等待选位置时的说明：允许的出发地由效果数据声明，界面不写死区域名
func _pending_location_hint(pending: Dictionary) -> String:
	var spec: Dictionary = pending.get("spec", {})
	var allowed: Array = spec.get("allowed_origin_areas", []) as Array
	if allowed.is_empty():
		return "点击地图上的战区完成选择"
	var names := PackedStringArray()
	for a in allowed:
		names.append(str(a))
	return "出发地需为 %s" % " 或 ".join(names)


# --- 结束行动：直接走引擎 ---
func _on_end_phase_pressed() -> void:
	if _is_progress_blocked():
		return
	if GameProgress.current_player_id != _local_player_id:
		return
	if GameProgress.is_phase_for(_local_player_id, "action"):
		var block := ActionRules.block_reason(_local_player_id)
		if block != "":
			_show_tactical_confirm(block, true)
			return
	GameProgress.end_current_player_action()
	refresh_all_ui()


# -----------------------------------------------------------------------------
# 出牌区新排版：一玩家一行 + 装饰条 + 动态统一卡尺寸 + 区域溢出滚动
# -----------------------------------------------------------------------------
func _bind_groups(area: BaseMapArea, content: Control) -> void:
	var region := content.get_node_or_null("Groups/List") as Control
	if region == null:
		region = content.get_node_or_null("Groups") as Control
		if region == null:
			return
	var active_keys: Array[String] = []
	for pid: int in _players_in_area(area):
		var played: Array = _pl(pid).get("played_cards", [])
		if played.is_empty():
			continue
		var key := "Player_%d" % pid
		active_keys.append(key)
		var grp := region.get_node_or_null(key) as Control
		if grp == null:
			grp = _spawn("PlayGroup", region)
			grp.name = key
			grp.set_meta("player_id", pid)
		_bind_player_row(grp, pid)
	for grp in region.get_children():
		if not active_keys.has(str(grp.name)):
			region.remove_child(grp)
			grp.queue_free()
	# 首次整理完场上已有牌之后再武装动画：之后新出现的牌才播入场
	_fly_armed = true


## 一位玩家占一整排：头像在左、牌在右，按实际出牌顺序逐张平铺。
## 槽位按真实卡对象复用（不按下标），刷新保留节点身份、悬浮与放大绑定；
## 同名多张各占一个槽位，不用一张代替多张
func _set_avatar_turn(angle: float, avatar_id: int) -> void:
	var avatar := instance_from_id(avatar_id) as Control
	if not is_instance_valid(avatar):
		return
	# 围绕当前尺寸的中心投影，布局变动时也不会偏向一侧。
	avatar.pivot_offset = avatar.size * 0.5
	avatar.scale = Vector2(maxf(cos(deg_to_rad(angle)), 0.025), 1.0)


func _play_avatar_entrance(avatar: Control, badge: Control) -> void:
	avatar.modulate.a = 1.0
	badge.modulate.a = 0.0
	var avatar_id := avatar.get_instance_id()
	_set_avatar_turn(88.0, avatar_id)
	var turn := avatar.create_tween()
	turn.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	turn.tween_method(_set_avatar_turn.bind(avatar_id), 88.0, 0.0, 0.46)
	turn.tween_method(_set_avatar_turn.bind(avatar_id), 0.0, -14.0, 0.12)
	turn.tween_method(_set_avatar_turn.bind(avatar_id), -14.0, 0.0, 0.12)
	# 徽章自身绑定生命周期，头像或整组移除不会留下悬空回调。
	var badge_fade := badge.create_tween()
	badge_fade.tween_interval(0.70)
	badge_fade.tween_property(badge, "modulate:a", 1.0, 0.10)


func _bind_player_row(grp: Control, pid: int) -> void:
	# 当前战场完全展开后同步启动各战场头像，收拢战场也持续计时。
	var current_open := not _scroll_is_animating() and _strip_open(_strip_by_index(_main_area_index))
	var first_reveal := not grp.has_meta("shown") and current_open
	if first_reveal:
		grp.set_meta("shown", true)
		grp.set_meta("shown_at", Time.get_ticks_msec() / 1000.0)
	grp.modulate.a = 1.0 if grp.has_meta("shown") else 0.0
	var played: Array = _pl(pid).get("played_cards", [])
	var who := grp.get_node("Who") as Control
	# 已启动的头像由卷轴自身裁切并随其移动，不在展开结束时重新显现。
	var avatar := who.get_node("Avatar") as Control
	_bind_avatar(avatar, _header_img(pid), "AvatarMana" if pid == _local_player_id else "AvatarGold3")
	var head_img: String = _header_img(pid)
	if first_reveal:
		avatar.set_meta("last_head", head_img)
		_play_avatar_entrance(avatar, who.get_node("Total") as Control)
	elif str(avatar.get_meta("last_head", "")) != head_img and grp.has_meta("shown"):
		avatar.set_meta("last_head", head_img)
		avatar.modulate.a = 0.0
		var fade := avatar.create_tween()
		fade.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		fade.tween_property(avatar, "modulate:a", 1.0, FADE_SECONDS)
	# 威力徽章只显示数字（剑图标已去掉）
	_set_text(who, "Total/Text", "%d" % int(GetPlayerTotalPower.breakdown(pid).get("total", 0)))
	var cards_box := grp.get_node("Cards") as Control
	var cards_row := cards_box.get_node("Row") as Control
	for slot in cards_row.get_children():
		if not played.has(_meta_or(slot, "card", null)):
			cards_row.remove_child(slot)
			slot.queue_free()
	for k in range(played.size()):
		var card = played[k]
		var slot := _played_card_slot(cards_row, card)
		cards_row.move_child(slot, k)
		var hidden := bool(card.get("_is_concealed")) and pid != _local_player_id
		_bind_card(slot, _back("attack" if card is BaseAttack else "skill") if hidden else str(card.get("_card_img")), 0.85 if hidden else 1.0)
		# 自己打出的暗置牌仍显示卡面，盖未公开遮罩（半透明灰 + 闭眼图标）标出"它对别人是暗的"；
		# 他人的暗置牌只给卡背，不给内容
		_sync_overlay(slot, bool(card.get("_is_concealed")) and pid == _local_player_id, "ConcealOverlay", CONCEAL_COLOR, CONCEAL_ICON)
		slot.set_meta("card_object", card)
		slot.set_meta("card", card)
		slot.set_meta("card_owner", pid)
		slot.visible = true
		# 他人的暗置牌维持卡背与未知信息：不给放大与完整说明
		if hidden or not (card is BaseCard):
			_disable_card_zoom(slot)
		else:
			bind_zoom_for_card(slot, card)
		_note_played_card_takeoff(slot, card, pid)


## 取该卡对象对应的出牌槽位：已有就复用，没有才新建
func _played_card_slot(cards_row: Control, card) -> Control:
	for slot in cards_row.get_children():
		if _meta_or(slot, "card", null) == card:
			return slot
	var slot := _spawn("PlayedCard", cards_row)
	slot.set_meta("card", card)
	return slot


## 返回槽位所属的战区卷轴（strip）节点；找不到（不在任何卷轴下）返回 null。
func _slot_strip(slot: Control) -> Control:
	if _strips == null:
		return null
	var n: Node = slot
	while n != null and n.get_parent() != _strips:
		n = n.get_parent()
	return n as Control

## 返回槽位所属战场的下标（_strips 子节点索引）；找不到返回 -1。
func _slot_strip_index(slot: Control) -> int:
	var strip := _slot_strip(slot)
	return -1 if strip == null else strip.get_index()

## 按下标取战场卷轴；越界或未初始化返回 null。
func _strip_by_index(strip_idx: int) -> Control:
	if _strips == null or strip_idx < 0 or strip_idx >= _strips.get_child_count():
		return null
	return _strips.get_child(strip_idx) as Control

## 战区卷轴是否已"完全显示"：判据是**视觉上**完全不透明，不是 open 标记。
## open 在 _select_scroll 调用时就立刻置 1，而内容还在 tween 淡入，用它会在卷轴
## 还是半透明时误判"完全显示"。主战场的"显示"是卷轴自身尺寸展开（content_a 恒为 1），
## 所以还要加一条"卷轴尺寸已稳定"。这个函数一帧内会被调用多次，尺寸比较必须按帧推进，
## 否则退化成"同一帧内两次调用一致"（等于没判）。
func _strip_open(strip: Control) -> bool:
	if strip == null:
		return false
	# content 引用只查一次并缓存：这里每帧会被调用几十次
	var content: Control = null
	if strip.has_meta("content_ref"):
		content = strip.get_meta("content_ref") as Control
	else:
		content = strip.get_node_or_null("Main") as Control
		strip.set_meta("content_ref", content)
	if content == null:
		return false
	var _vis: float = content.modulate.a
	var frame: int = Engine.get_process_frames()
	# 一帧内只真正算一次：这个函数每帧会被调用几十次（4 个战场 × 每帧多次）
	if int(strip.get_meta("open_frame", -1)) == frame:
		return bool(strip.get_meta("open_val", false))
	strip.set_meta("open_frame", frame)
	var cur_size: Vector2 = strip.size
	if int(strip.get_meta("size_frame", -1)) != frame:
		strip.set_meta("size_frame", frame)
		strip.set_meta("prev_size", strip.get_meta("cur_size", Vector2(-1.0, -1.0)))
		strip.set_meta("cur_size", cur_size)
	var settled: bool = cur_size == Vector2(strip.get_meta("prev_size", Vector2(-1.0, -1.0)))
	# 日志降频：只在 settled 翻转时打印一次（原来每帧几十条，既刷屏又有开销）
	strip.set_meta("open_val", _vis >= 0.99 and settled)
	if _fade_debug and bool(strip.get_meta("log_settled", not settled)) != settled:
		strip.set_meta("log_settled", settled)
		print("[FADE] open_check strip=", strip.name, " content_a=", snappedf(_vis, 0.01),
			" size=", cur_size, " settled=", settled,
			" t=", snappedf(Time.get_ticks_msec() / 1000.0, 0.01))
	return _vis >= 0.99 and settled

## 槽位所属战区是否完全显示（供头像淡入等旧调用点继续使用）。
func _slot_battlefield_open(slot: Control) -> bool:
	return _strip_open(_slot_strip(slot))


## 新打出的牌登记一次入场动画：只有"这张牌第一次出现在场上"才播。
## 不再等待该牌所属战场展开——牌打出即入队，其战场的飞行泵独立计时并行推进；
## 其他战场的牌照常在后台飞，切换过去时时间到的牌已经落位。
func _note_played_card_takeoff(slot: Control, card, pid: int) -> void:
	var cid: int = card.get_instance_id()
	if _takeoff_done.has(cid):
		return
	if not is_instance_valid(slot) or not slot.is_inside_tree() or slot.is_queued_for_deletion():
		return
	_takeoff_done[cid] = true
	# 首次刷新（_fly_armed 为假）只登记不播，避免进入对局时先把已有牌全飞一遍
	if not _fly_armed:
		return
	var strip_idx := _slot_strip_index(slot)
	if strip_idx < 0:
		return
	# 入队就隐藏：等到开始飞行才隐藏的话，中间那一帧牌已经出现在出牌区了
	# （表现为"牌飞过去之前出牌区就有牌"）
	slot.modulate.a = 0.0
	var queue: Array = _fly_queues.get(strip_idx, [])
	queue.append({"slot": slot, "card": card, "pid": pid})
	_fly_queues[strip_idx] = queue
	_pump_fly_queue(strip_idx)


## 逐张播放：一张落位后再飞下一张，队列由动画自身驱动
## 在途飞牌的尺寸要跟着出牌区的统一卡尺寸走：
## 起飞时只设一次尺寸，飞行途中牌数再变就会在落位瞬间跳变
func _update_fly_sizes(delta: float) -> void:
	if _fly_layer == null:
		return
	var weight := 1.0 - exp(-FLY_RESIZE_SPEED * delta)
	for fly in _fly_layer.get_children():
		var fc := fly as Control
		if fc == null:
			continue
		# 保险：清掉滞留的飞牌。正常靠 tween 结束时 queue_free，
		# 但 tween 被打断或帧率极低时它会一直留在满屏飞行层里（看着像"粒子没消失"）
		var age: float = Time.get_ticks_msec() / 1000.0 - float(fc.get_meta("spawn_at", 0.0))
		if age > FLY_SECONDS * 4.0:
			fc.queue_free()
			continue
		# 飞牌可见性跟随其所属战场：后台战场不可见，但 tween 仍在实时推进时间；
		# 切换战场瞬间，还在这条轨迹上的飞牌就在正确的时间位置显形/隐去
		var strip_idx: int = int(fc.get_meta("strip_idx", -1))
		if strip_idx >= 0:
			fc.visible = _strip_open(_strip_by_index(strip_idx))
		if _play_card_target_size == Vector2.ZERO:
			continue
		if fc.size.distance_to(_play_card_target_size) < 0.5:
			fc.size = _play_card_target_size
		else:
			# 只改尺寸，不动 position：飞行 tween 每帧在写 position，这里插一脚会抖
			fc.size = fc.size.lerp(_play_card_target_size, weight)

## 单个战场的飞行泵：只消费自己队列里的牌，一张落位后再飞下一张。
## 每个战场的泵独立并行推进，互不阻塞。
func _pump_fly_queue(strip_idx: int) -> void:
	if _fly_busy.get(strip_idx, false) or _fly_layer == null:
		return
	if not _fly_queues.has(strip_idx) or (_fly_queues[strip_idx] as Array).is_empty():
		return
	_fly_busy[strip_idx] = true
	# 先等这一帧的布局跑完：槽位的最终位置由布局写入，而登记发生在布局之前，
	# 不先等的话比较到的是上一轮的位置，"从左到右"就选错了
	await get_tree().process_frame
	if _fly_layer == null:
		_fly_busy[strip_idx] = false
		return
	var queue: Array = _fly_queues.get(strip_idx, [])
	# await 期间槽位可能被刷新或换回合释放，必须先验证再作类型转换。
	for i in range(queue.size() - 1, -1, -1):
		var queued_slot = queue[i].get("slot")
		if not is_instance_valid(queued_slot) or not queued_slot.is_inside_tree() or queued_slot.is_queued_for_deletion():
			queue.remove_at(i)
	if queue.is_empty():
		_fly_busy[strip_idx] = false
		_restore_played_slots(strip_idx)
		return
	# 按目标位置从左到右取：登记顺序与最终落位顺序不一定一致，
	# 直接 pop_front 会出现"右边那张先飞"
	var best := 0
	for i in range(queue.size()):
		var cur_slot := queue[i].get("slot") as Control
		var best_slot := queue[best].get("slot") as Control
		if cur_slot != null and is_instance_valid(cur_slot) and best_slot != null:
			if cur_slot.global_position.x < best_slot.global_position.x:
				best = i
	var item: Dictionary = queue[best]
	queue.remove_at(best)
	await _play_takeoff(item.slot, item.card, int(item.pid), strip_idx)
	_fly_busy[strip_idx] = false
	var left: Array = _fly_queues.get(strip_idx, [])
	if not left.is_empty():
		await get_tree().create_timer(FLY_INTERVAL).timeout
		_pump_fly_queue(strip_idx)
	else:
		_restore_played_slots(strip_idx)


## 徽章与牌区起点每帧按头像的**当前**尺寸重算：
## 用目标尺寸算一次的话，头像还在过渡时两者就会错开（牌甚至盖住头像）
## 卷轴过渡中不让裁切边界擦出半张头像；可完整显示后才柔和显现。
## 只控制 Who 的透明度，头像内部的翻面 tween 始终继续计时。
func _update_avatar_scroll_reveal(who: Control, avatar: Control) -> void:
	if not _scroll_is_animating() and who.modulate.a >= 1.0:
		return
	if _scroll_is_animating():
		var portrait := avatar.get_global_rect()
		var visible_rect := portrait
		var ancestor: Node = who.get_parent()
		while ancestor is Control:
			if (ancestor as Control).clip_contents:
				visible_rect = visible_rect.intersection((ancestor as Control).get_global_rect())
			ancestor = ancestor.get_parent()
		if not visible_rect.grow(0.5).encloses(portrait):
			who.modulate.a = 0.0
			return
	# 布局与每帧更新都会调用这里，一帧只推进一次淡入。
	var frame := Engine.get_process_frames()
	if int(who.get_meta("reveal_frame", -1)) != frame:
		who.set_meta("reveal_frame", frame)
		who.modulate.a = move_toward(who.modulate.a, 1.0, get_process_delta_time() / 0.18)


func _update_power_badges(rows = null) -> void:
	if rows == null:
		rows = _play_group_nodes()
	for grp in rows:
		# 引用只解析一次，之后走缓存：这个函数每帧对每个组都要跑
		var who := (grp as Control).get_node_or_null("Who") as Control
		if who == null:
			continue
		var refs: Dictionary = who.get_meta("refs", {} as Dictionary)
		if refs.is_empty():
			refs = {
				"av": who.get_node_or_null("Avatar"),
				"badge": who.get_node_or_null("Total"),
				"cards": (grp as Control).get_node_or_null("Cards"),
			}
			who.set_meta("refs", refs)
		var av := refs.get("av") as Control
		var badge := refs.get("badge") as Control
		if av == null or badge == null:
			continue
		_update_avatar_scroll_reveal(who, av)
		# 只在头像/徽章的实际尺寸变了才写坐标：给 position 赋相同值同样会标脏，
		# 每帧无条件写会让整块出牌区持续重绘（实测帧率随之崩掉）。
		# 这里记录上次用到的尺寸，过渡中（尺寸每帧在变）照样每帧跟随。
		var stamp := Vector4(av.size.x, av.size.y, badge.size.x, who.size.y)
		if (who.get_meta("badge_stamp", Vector4(-1.0, -1.0, -1.0, -1.0)) as Vector4).is_equal_approx(stamp):
			continue
		who.set_meta("badge_stamp", stamp)
		var d: float = badge.size.x
		badge.position = Vector2(av.position.x + av.size.x - d * POWER_BADGE_INSET_RATIO,
			av.position.y + av.size.y - d * POWER_BADGE_INSET_RATIO)
		# 牌区起点同样按头像当前宽度与当前卡高同步：它要是走过渡，
		# 中途就会滑到头像与徽章上面
		var cards_box := refs.get("cards") as Control   # Cards 挂在组下，不在 who 下
		if cards_box != null:
			# 起点要同时避开头像和它右下角的威力徽章：徽章右缘会比头像右缘更靠右，
			# 只按头像宽度推会让牌压住徽章
			var blocked_right: float = maxf(av.position.x + av.size.x, badge.position.x + badge.size.x)
			cards_box.position.x = blocked_right + maxf(who.size.y * PLAYED_SIDE_GAP_RATIO, PLAYED_SIDE_GAP_MIN)
			# 判定用真实全局矩形：局部 position/size 推出来的关系不等于实际绘制矩形
			# （Cards 是 ScrollContainer，局部量与实际矩形不同源）
			if _fade_debug:
				var cards_rect: Rect2 = cards_box.get_global_rect()
				var av_rect: Rect2 = av.get_global_rect()
				var badge_rect: Rect2 = badge.get_global_rect()
				if cards_rect.intersects(av_rect) or cards_rect.intersects(badge_rect):
					print("[GAP] cards=", cards_rect, " avatar=", av_rect, " badge=", badge_rect)

## 所有卷轴里已建立的出牌组（带 player_id 的那些）
func _play_group_nodes() -> Array:
	# 一帧只收集一次：这个函数每帧会被徽章/布局/恢复等多处调用，
	# 每次都 get_node 路径查找的话开销很大（实测组一多帧率就崩）
	var frame: int = Engine.get_process_frames()
	if _groups_frame == frame:
		return _groups_cache
	_groups_frame = frame
	var out: Array = []
	var strips := get_node_or_null("Strips") as Control
	if strips == null:
		return out
	for strip in strips.get_children():
		var list := (strip as Control).get_node_or_null("Main/Groups/List") as Control
		if list == null:
			continue
		for grp in list.get_children():
			if grp is Control and grp.has_meta("player_id"):
				out.append(grp)
	_groups_cache = out
	return out

## 队列播完后把该战场的出牌区槽位统一恢复可见：万一某张牌没飞成，
## 入队时隐藏的槽位不会一直空着
func _restore_played_slots(strip_idx: int) -> void:
	var strip := _strip_by_index(strip_idx)
	if strip == null:
		return
	var list := strip.get_node_or_null("Main/Groups/List") as Control
	if list == null:
		return
	for grp in list.get_children():
		if not (grp is Control and grp.has_meta("player_id")):
			continue
		var row := (grp as Control).get_node_or_null("Cards/Row") as Control
		if row == null:
			continue
		for slot in row.get_children():
			(slot as Control).modulate.a = 1.0

## 一张牌的入场动画：飞行期间真实槽位隐去，落位后再显示，避免"先出现再瞬移"。
## 飞牌节点记录所属战场（strip_idx），可见性随战场：后台战场不可见但 tween 实时推进，
## 切换过去时牌已推进到正确的时间位置；落位点每帧朝 slot 当前全局坐标插值，
## 这样飞行途中切换战场（卷轴移动）时，飞牌会追着正确落位点而不是飞向旧坐标。
func _play_takeoff(slot: Control, card, pid: int, strip_idx: int) -> void:
	if slot == null or not is_instance_valid(slot) or _fly_layer == null:
		return
	# 等这一帧的布局跑完再取尺寸：槽位的目标尺寸由布局阶段写入，
	# 登记入队发生在布局之前，先取会拿到模板尺寸、落位时跳变
	await get_tree().process_frame
	if slot == null or not is_instance_valid(slot):
		return
	var fly := _spawn("PlayedCard", _fly_layer)
	var img := fly.get_node("Img") as TextureRect
	var src_img := slot.get_node("Img") as TextureRect
	img.texture = src_img.texture      # 直接复用槽位贴图：明置/卡背/压暗都已经处理好
	fly.size = slot.get_meta("layout_size_target", slot.size)
	fly.set_meta("spawn_at", Time.get_ticks_msec() / 1000.0)
	fly.set_meta("strip_idx", strip_idx)
	var start_pos := _takeoff_origin(pid, card)
	fly.global_position = start_pos
	fly.scale = Vector2.ONE * FLY_START_SCALE
	fly.visible = _strip_open(_strip_by_index(strip_idx))
	slot.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 位置每帧朝 slot 当前落位点插值：飞行中切换战场时落位点跟着卷轴移动。
	# 用 instance_from_id 而非直接捕获 slot/fly 引用：槽位在飞行途中可能被刷新释放，
	# 直接捕获会让 Godot 每帧报 "Lambda capture was freed" 并塞 null
	var slot_id := slot.get_instance_id()
	var fly_id := fly.get_instance_id()
	tw.tween_method(func(t: float) -> void:
		var s := instance_from_id(slot_id) as Control
		var f := instance_from_id(fly_id) as Control
		if is_instance_valid(f) and is_instance_valid(s):
			f.global_position = start_pos.lerp(s.global_position, t)
	, 0.0, 1.0, FLY_SECONDS)
	tw.tween_property(fly, "scale", Vector2.ONE, FLY_SECONDS)
	await tw.finished
	if is_instance_valid(fly):
		fly.queue_free()
	if is_instance_valid(slot):
		slot.modulate.a = 1.0


## 起飞点：自己的牌从它此刻在自身界面上的位置起飞（手牌或技能区卡位），
## 找不到时退回御主卡；对手的牌从它的顺位玩家信息卡起飞
func _takeoff_origin(pid: int, card) -> Vector2:
	if pid == _local_player_id:
		for slot in _hand.get_children():
			if _meta_or(slot as Control, "card", null) == card:
				return (slot as Control).get_global_rect().get_center()
		return (_master as Control).get_global_rect().get_center()
	for rival in _rivals.get_children():
		if rival is Control and int((rival as Control).get_meta("turn_order_player_id", -1)) == pid:
			return (rival as Control).get_global_rect().get_center()
	return (_rivals as Control).get_global_rect().get_center()


## 出牌区可用矩形：在卷轴内扣除标题带、事件列、双排席位与设计边距，
## 得到"已打出牌"能用的空白区。只测量，不改动任何面板自身的位置与尺寸
func _play_area_rect(strip: Control) -> Rect2:
	var top := PLAYED_AREA_TOP
	var name_lbl := strip.get_node_or_null("Main/Name") as Control
	if name_lbl != null:
		top = maxf(top, name_lbl.position.y + name_lbl.size.y + 10.0)
	var left := minf(strip.size.x * 0.30, 466.0)
	var events := strip.get_node_or_null("EventIcons") as Control
	if events != null and events.visible and events.get_child_count() > 0:
		var last_ev := events.get_child(events.get_child_count() - 1) as Control
		left = maxf(left, last_ev.position.x + last_ev.size.x * last_ev.scale.x + PLAYED_AREA_MARGIN)
	# 席位只占卷轴左下角：若出牌区起点已经在席位排右缘之外，就不必按席位高度扣减，
	# 只在横向仍与席位重叠时才让位。这样右侧整条高度都能给出牌区用
	var seat_right := 0.0
	var seat_top := strip.size.y - PLAYED_AREA_MARGIN
	for row_name in ["MeleeScroll", "SeatScroll"]:
		var sc := strip.get_node_or_null("Seats/" + row_name) as Control
		if sc != null and sc.visible:
			seat_right = maxf(seat_right, sc.position.x + sc.size.x)
			seat_top = minf(seat_top, sc.position.y - PLAYED_AREA_MARGIN)
	var bottom := strip.size.y - PLAYED_AREA_MARGIN
	if left < seat_right + PLAYED_AREA_MARGIN:
		bottom = seat_top
	var right := strip.size.x - PLAYED_AREA_MARGIN
	return Rect2(Vector2(left, top), Vector2(maxf(1.0, right - left), maxf(1.0, bottom - top)))


## 卡牌原始宽高比：优先读该排第一张牌的实际纹理，读不到时退回模板比例
func _played_card_aspect(rows: Array) -> float:
	for grp in rows:
		var row := (grp as Control).get_node_or_null("Cards/Row") as Control
		if row == null:
			continue
		for slot in row.get_children():
			var img := (slot as Control).get_node_or_null("Img") as TextureRect
			if img != null and img.texture != null and img.texture.get_height() > 0:
				return float(img.texture.get_width()) / float(img.texture.get_height())
	var tpl := _tpl.get_node("PlayedCard") as Control
	return tpl.size.x / maxf(1.0, tpl.size.y)


## 卷轴出牌区排版：按当前地图的总牌量、玩家排数、各排牌数与可用矩形
## 解出一套统一卡尺寸，优先放大到刚好占满空白区并保留边距；
## 低于最小可读尺寸时固定为下限，由 Groups 的滚动容器提供局部滚动，
## 绝不隐藏牌、重新叠放、泄露暗置牌面或越界绘制
## 按行装箱：把各组依次往右排，放不下才换行，返回所需行数
## 卡尺寸与行数互相依赖（卡小→组窄→行少），调用方用二分求解
func _packed_play_rows(counts: Array[int], card_w: float, card_h: float, avail_w: float) -> int:
	var avatar_w := card_h * PLAYED_AVATAR_W_RATIO
	var side_gap := card_h * PLAYED_SIDE_GAP_RATIO
	var card_gap := card_h * PLAYED_CARD_GAP_RATIO
	var rows_used := 1
	var cur_x := 0.0
	for i in range(counts.size()):
		var n: int = counts[i]
		var shown: int = mini(n, PLAYED_ROW_CARD_CAP)
		var grp_w := avatar_w + side_gap + float(shown) * card_w + float(maxi(0, shown - 1)) * card_gap
		# 单组就超过可用宽度：这个卡尺寸不可行，返回一个不可能满足的行数，
		# 让二分继续缩小卡尺寸，而不是让这一排横向压到相邻列上
		if grp_w > avail_w:
			return PACKED_ROWS_IMPOSSIBLE
		if cur_x > 0.0 and cur_x + grp_w > avail_w:
			rows_used += 1
			cur_x = 0.0
		cur_x += grp_w + side_gap
	return rows_used

## 某条带容纳 rows_needed 行时能给出的最大卡高（受带高与带宽共同限制）
func _band_card_h(band: Rect2, rows_needed: int, aspect: float, counts: Array[int]) -> float:
	if rows_needed <= 0 or band.size.x <= 1.0 or band.size.y <= 1.0:
		return 0.0
	var h_rows := band.size.y / (float(rows_needed) + float(maxi(0, rows_needed - 1)) * PLAYED_ROW_GAP_RATIO)
	var h_cards := INF
	for i in range(counts.size()):
		var shown: int = mini(counts[i], PLAYED_ROW_CARD_CAP)
		if shown <= 0:
			continue
		var unit := PLAYED_AVATAR_W_RATIO + PLAYED_SIDE_GAP_RATIO + float(shown) * aspect + float(maxi(0, shown - 1)) * PLAYED_CARD_GAP_RATIO
		h_cards = minf(h_cards, band.size.x / unit)
	return minf(h_rows, h_cards)

## 尺寸变化带过渡：目标变了才重建 tween，避免每次刷新把动画重启
## 尺寸过渡
func _tween_size(node: Control, target: Vector2, key: String, instant := false) -> void:
	_tween_vec(node, &"size", target, key, instant)

func _tween_vec(node: Control, prop: StringName, target: Vector2, key: String, instant := false) -> void:
	if node == null or not is_instance_valid(node):
		return
	# 这一组首次布局、或节点首次遇到该属性：直接到位。
	# 出现时只做淡入（位置与大小固定），不会从空白处滑过来
	if instant or not node.has_meta(key):
		node.set_meta(key, target)
		node.set(prop, target)
		return
	if Vector2(node.get_meta(key, Vector2(-1.0, -1.0))) == target:
		return
	node.set_meta(key, target)
	var tw: Tween = null
	if node.has_meta(key + "_tw"):
		tw = node.get_meta(key + "_tw") as Tween
	if tw != null and tw.is_valid():
		tw.kill()
	if Vector2(node.get(prop)).distance_to(target) < 0.5:
		node.size = target
		return
	var t := node.create_tween()
	t.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(node, String(prop), target, FLY_SECONDS)
	node.set_meta(key + "_tw", t)

func _layout_play_groups(groups: Control) -> void:
	if groups == null:
		return
	# 可用矩形取滚动容器自身的尺寸；排容器是它内部唯一的 List
	var list := groups.get_node_or_null("List") as Control
	if list == null:
		return
	var rect := Rect2(Vector2.ZERO, groups.size)
	# 御主面板压在卷轴底部之上：出牌区必须在面板顶边之前结束，
	# 否则排满时最下面的牌会盖住御主头像（反向也被头像遮住）
	var groups_global := groups.get_global_rect()
	var master_top: float = _master.get_global_rect().position.y - HELD_GAP
	if master_top > groups_global.position.y and master_top < groups_global.end.y:
		rect.size.y = maxf(0.0, master_top - groups_global.position.y)
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	var rows: Array = []
	for grp in list.get_children():
		if grp is Control and grp.has_meta("player_id"):
			rows.append(grp)
	if rows.is_empty():
		return
	var counts: Array[int] = []
	var total_cards := 0
	for grp in rows:
		var n := ((grp as Control).get_node("Cards/Row") as Control).get_child_count()
		counts.append(n)
		total_cards += n
	if total_cards == 0:
		return
	var aspect := _played_card_aspect(rows)
	var row_count := rows.size()
	# 可用矩形不取自容器自身：ScrollContainer 被内容撑大后既不再滚动，
	# 又会形成"内容越宽→卡越大→内容更宽"的正反馈（尺寸指数爆炸）
	var anchor: Vector2 = groups.get_global_rect().position
	var area_w: float = rect.size.x
	var area_bottom: float = rect.size.y
	var strip_ctl := groups.get_parent().get_parent() as Control
	if strip_ctl != null:
		var strip_rect: Rect2 = strip_ctl.get_global_rect()
		area_w = maxf(1.0, strip_rect.end.x - anchor.x - PLAYED_AREA_RIGHT_PAD)
		# rect 的高度只是『面板上方』那块；两侧竖带要能落到卷轴底部，
		# 所以这里不 min 上它
		area_bottom = maxf(1.0, strip_rect.end.y - anchor.y - PLAYED_AREA_BOTTOM_PAD)
	# 御主面板压在卷轴底部中央：它上方的整宽区域是一条带，
	# 它左右两侧的空白（凸出部分两边）也各自是一条带——那两条不与面板重叠，可以一直落到卷轴底部
	var master_rect: Rect2 = _master.get_global_rect()
	var master_top_h: float = maxf(1.0, master_rect.position.y - HELD_GAP - anchor.y)
	var master_x0: float = maxf(0.0, master_rect.position.x - HELD_GAP - anchor.x)
	var master_x1: float = minf(area_w, master_rect.end.x + HELD_GAP - anchor.x)
	# 容器尺寸钉回可用矩形（含面板两侧），并开启裁剪：
	# 尺寸被内容撑大后就不再提供滚动，超出部分也会画到容器外
	groups.size = Vector2(area_w, area_bottom)
	groups.clip_contents = true
	list.clip_contents = true
	rect = Rect2(Vector2.ZERO, Vector2(area_w, area_bottom))
	# 布局是重活（14 次二分 × 每次都遍历所有组）。输入没变就跳过：
	# 尺寸与位置的变化由各自的 tween 每帧自行推进，不需要重算布局
	# （注意：这里必须排在 area_w/counts/rows 都算好之后）
	var sig := "%s|%d" % [str(Vector2(area_w, area_bottom)), row_count]
	for i in range(row_count):
		sig += ",%d:%d" % [counts[i], 1 if (rows[i] as Control).has_meta("shown") else 0]
	if str(groups.get_meta("layout_sig", "")) == sig:
		return
	groups.set_meta("layout_sig", sig)
	var bands: Array[Rect2] = []
	if master_x0 > 1.0:
		bands.append(Rect2(Vector2(0.0, 0.0), Vector2(master_x0, area_bottom)))
	if area_w - master_x1 > 1.0:
		bands.append(Rect2(Vector2(master_x1, 0.0), Vector2(area_w - master_x1, area_bottom)))
	bands.append(Rect2(Vector2(0.0, 0.0), Vector2(area_w, minf(master_top_h, area_bottom))))
	# 每条带内缩一圈留白：内容贴着面板/卷轴边缘会很难看
	for bi in range(bands.size()):
		var b: Rect2 = bands[bi]
		if b.size.x > PLAYED_AREA_PADDING * 2.0 and b.size.y > PLAYED_AREA_PADDING * 2.0:
			bands[bi] = Rect2(b.position + Vector2(PLAYED_AREA_PADDING, PLAYED_AREA_PADDING),
				b.size - Vector2(PLAYED_AREA_PADDING * 2.0, PLAYED_AREA_PADDING * 2.0))
	# 靠左优先：玩家缩小后先占左边的位置；位置相同（都贴着出牌区左缘）时，
	# 再选能给出更大卡尺寸的那条带
	bands.sort_custom(func(a, b):
		var ax: float = (a as Rect2).position.x
		var bx: float = (b as Rect2).position.x
		if not is_equal_approx(ax, bx):
			return ax < bx
		return _band_card_h(a, row_count, aspect, counts) > _band_card_h(b, row_count, aspect, counts))
	# 卡尺寸：先用 1 条带解算，放不下（小于最小卡高）就多带并用
	var bands_used := 1
	var card_h: float = PLAYED_CARD_MIN_H
	while true:
		var per_band: int = int(ceil(float(row_count) / float(bands_used)))
		var h_rows := INF
		var h_cards := INF
		for bi in range(bands_used):
			var band: Rect2 = bands[bi]
			h_rows = minf(h_rows, band.size.y / (float(per_band) + float(maxi(0, per_band - 1)) * PLAYED_ROW_GAP_RATIO))
			for i in range(row_count):
				var shown_i: int = mini(counts[i], PLAYED_ROW_CARD_CAP)
				if shown_i <= 0:
					continue
				var unit_i := PLAYED_AVATAR_W_RATIO + PLAYED_SIDE_GAP_RATIO + float(shown_i) * aspect + float(maxi(0, shown_i - 1)) * PLAYED_CARD_GAP_RATIO
				h_cards = minf(h_cards, band.size.x / unit_i)
		var candidate: float = minf(h_rows, h_cards)
		if candidate >= PLAYED_CARD_MIN_H or bands_used >= bands.size():
			card_h = maxf(candidate, PLAYED_CARD_MIN_H)
			break
		bands_used += 1
	var per_band: int = int(ceil(float(row_count) / float(bands_used)))
	var card_w := card_h * aspect
	var avatar_w := card_h * PLAYED_AVATAR_W_RATIO
	var side_gap := card_h * PLAYED_SIDE_GAP_RATIO
	var card_gap := card_h * PLAYED_CARD_GAP_RATIO
	var row_gap := card_h * PLAYED_ROW_GAP_RATIO
	var widest := 0.0
	for i in range(row_count):
		var grp := rows[i] as Control
		var n: int = counts[i]
		# 还没露面的组整帧保持不可见（布局每帧都会跑，比等下一次绑定更及时）
		if not grp.has_meta("shown") and not _slot_battlefield_open(grp):
			grp.modulate.a = 0.0
		# 这一组第一次被布局、或还处在"刚出现"的这一小段时间内：位置与尺寸全部直接到位。
		# 只靠淡入出现，任何元素都不许从别处滑过来
		var grp_first := not grp.has_meta("laid_out")
		grp.set_meta("laid_out", true)
		# settling 从"露面"起算，不能用 laid_out：那个标记在卷轴展开之前就被打上了，
		# 拿它当基准会让展开后的首次定位也走过渡（表现为头像滑入、牌区扫过头像）
		# 冻结窗只管"还没露面"这一瞬：露面后的尺寸/位置变化必须照常有动画。
		# 之前用 FADE_SECONDS*1.5 当窗口，淡入一放慢就把变化动画整段吃掉了
		var settling: bool = not grp.has_meta("shown")
		var shown: int = mini(n, PLAYED_ROW_CARD_CAP)
		var grp_w := avatar_w + side_gap + float(shown) * card_w + float(maxi(0, shown - 1)) * card_gap
		var bi: int = i / per_band
		var ri: int = i % per_band
		var band: Rect2 = bands[bi]
		var rows_in_band: int = mini(per_band, row_count - bi * per_band)
		var band_h: float = float(rows_in_band) * card_h + row_gap * float(maxi(0, rows_in_band - 1))
		var x: float = rect.position.x + band.position.x
		var y: float = rect.position.y + band.position.y + maxf(0.0, (band.size.y - band_h) * 0.5) + float(ri) * (card_h + row_gap)
		widest = maxf(widest, band.position.x + grp_w)

		var who := grp.get_node("Who") as Control
		var cards_box := grp.get_node("Cards") as Control
		var cards_row := cards_box.get_node("Row") as Control
		var deco := grp.get_node_or_null("DecoBar") as Control
		# 装饰承接条：从头像区域延伸至牌区末尾，位于牌与头像后方，不接收鼠标
		if deco != null:
			deco.position = Vector2(0.0, (card_h - card_h * PLAYED_DECO_H_RATIO) * 0.5)
			deco.size = Vector2(grp_w, card_h * PLAYED_DECO_H_RATIO)
			deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
		who.position = Vector2(0.0, 0.0)
		# 清掉模板的 custom_minimum_size：它是硬下限，目标比它小时尺寸缩不下去
		# （Who 会被钉在 130 高、Cards 钉在 200 宽，间距与牌区宽度都跟着错）
		who.custom_minimum_size = Vector2.ZERO
		cards_box.custom_minimum_size = Vector2.ZERO
		_tween_size(who, Vector2(avatar_w, card_h), "lay_who", settling)
		# 头像随卡高缩放并垂直居中（模板里是固定 54px，缩小的排宽下会压到牌上）
		var av := who.get_node_or_null("Avatar") as Control
		if av != null:
			var av_size := minf(avatar_w, card_h * 0.78)
			_tween_size(av, Vector2(av_size, av_size), "lay_av", settling)
			# 头像锚在组中心（anchors_preset = 5）：只设尺寸，位置由锚点自动保持居中。
			# 手动设位置会覆盖锚点居中，尺寸/位置两处过渡不同步时就会把头像挤偏
		# 威力是头像右下角的圆形徽章：圆形底 + 数字，不再带剑图标
		# 威力徽章钉在头像右下角（半径按卡高走），并提到头像之上——
		# 锚在 Who 底部会落到头像下方，层级不够则会被头像盖住
		# 徽章尺寸走过渡（位置不在这里定：见 _update_power_badges，
		# 布局时用目标尺寸算位置的话，头像还在过渡时就会错位）
		var total_badge := who.get_node_or_null("Total") as Control
		if total_badge != null:
			_tween_size(total_badge, Vector2(avatar_w * 0.46, avatar_w * 0.46), "lay_badge", settling)
			who.move_child(total_badge, -1)
		var total_lbl := who.get_node_or_null("Total/Text") as Label
		if total_lbl != null:
			total_lbl.add_theme_font_size_override("font_size", clampi(int(card_h * 0.20), 9, 20))
		# 牌区起点：布局时直接到位，并由 _update_power_badges 每帧按头像当前宽度同步。
		# 只靠每帧同步的话，布局这一帧牌区还停在旧位置，就会扫过头像与徽章
		# 与逐帧同步同一口径：避开头像与徽章右缘的较大者
		var blocked_right: float = av.position.x + av.size.x
		if total_badge != null:
			blocked_right = maxf(blocked_right, total_badge.position.x + total_badge.size.x)
		cards_box.position = Vector2(blocked_right + maxf(who.size.y * PLAYED_SIDE_GAP_RATIO, PLAYED_SIDE_GAP_MIN), 0.0)
		_tween_size(cards_box, Vector2(float(shown) * card_w + float(maxi(0, shown - 1)) * card_gap, card_h), "lay_cards", settling)
		cards_row.position = Vector2.ZERO
		# 内容宽度按全部牌算：多出来的部分由这一排自己横向滚动查看
		cards_row.custom_minimum_size = Vector2(float(n) * card_w + float(maxi(0, n - 1)) * card_gap, card_h)
		cards_row.size = cards_row.custom_minimum_size
		for k in range(n):
			var slot := cards_row.get_child(k) as Control
			_tween_vec(slot, &"position", Vector2(float(k) * (card_w + card_gap), 0.0), "lay_slot_pos%d" % k, settling)
			var target_size := Vector2(card_w, card_h)
			_play_card_target_size = target_size
			# 不设 custom_minimum_size：目标变大时 minimum 会把 size 立刻顶上去（硬切），
			# 尺寸完全由 size 过渡驱动
			slot.custom_minimum_size = Vector2.ZERO
			# 牌数变化会改变统一卡尺寸：尺寸要过渡而不是硬切，节奏与入场飞行一致。
			# 只在目标尺寸真的变了时重建过渡，否则每次刷新都会把动画重启
			if slot.get_meta("layout_size_target", Vector2.ZERO) != target_size:
				slot.set_meta("layout_size_target", target_size)
				var size_tw: Tween = null
				if slot.has_meta("layout_size_tween"):
					size_tw = slot.get_meta("layout_size_tween") as Tween
				if size_tw != null and size_tw.is_valid():
					size_tw.kill()
				if slot.size.distance_to(target_size) < 0.5:
					slot.size = target_size
				else:
					var tw := slot.create_tween()
					tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
					tw.tween_property(slot, "size", target_size, FLY_SECONDS)
					slot.set_meta("layout_size_tween", tw)
		_tween_vec(grp, &"position", Vector2(x, y), "lay_grp_pos", settling)
		grp.custom_minimum_size = Vector2.ZERO
		_tween_size(grp, Vector2(grp_w, card_h), "lay_grp", settling)
	var used_h := float(per_band) * card_h + row_gap * float(maxi(0, per_band - 1))
	_update_power_badges(rows)
	list.custom_minimum_size = Vector2(widest, maxf(rect.size.y, used_h))
