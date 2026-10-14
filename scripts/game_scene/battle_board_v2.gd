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
## 对手抽屉的四个分区行（纵向铺满面板，没有内容的行整行收起），行内超出靠无滚动条滚动查看。
## 子树路径只在这里声明一次，增删分区时不会散落出多份写死路径
const DRAWER_ROWS: Array = [
	"VBox/Sections/Row_MasterServant",
	"VBox/Sections/Row_Played",
	"VBox/Sections/Row_Skills",
	"VBox/Sections/Row_Buffs",
	"VBox/Sections/Row_CommandSpells",
]
## 分区里的卡位比例与最小高度：高度铺满行内滚动区、宽度按这个比例等比（卡图不变形）。
## 数值取自既有卡位模板，只作为"这一行还没量出高度"时的兜底
const DRAWER_CARD_WIDTH := 82.0
const DRAWER_CARD_HEIGHT := 116.0
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
const SPELL_BOX_SIZE := Vector2(90, 126)
const SPELL_BOX_STEP := 96.0

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
const BROADCAST_OPEN_DELAY := 3.0       # 最后一人战斗阶段结束后等待再显示结算
const BROADCAST_TITLE_SECONDS := 0.55   # 标题缩放回弹入场
const BROADCAST_CARD_STEP := 0.18       # 每个战场块淡入单段时长

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
const ROUND_LIFTED_Z := 80
## 棋盘动画 < 提示横幅 < 原生浏览器(100)：压过抽出的卡片，不越过浏览/日志/播报层。
const BANNER_Z := 85


## 卷轴出牌区：所有比例都相对"卡高"，随可用区域与牌数动态求解，不写死某个牌数
const PLAYED_CARD_MIN_H := 46.0     ## 最小可读卡高，低于此值改用局部滚动
const PLAYED_AVATAR_W_RATIO := 0.66 ## 头像宽 / 卡高
## 出牌区内容的内边距：别贴着面板/卷轴边缘
const PLAYED_AREA_PADDING := 20.0
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

var _seat_controller = preload("res://scripts/match/seat_controller.gd").new()
var _driver = preload("res://scripts/match/match_driver.gd").new(_seat_controller)
var _commands = preload("res://scripts/match/match_commands.gd").new()
## 由大厅在入树前传入；网络显示不进入单机引擎路径。
var network_session = null
var _network_presenter = null
## source 在 ready 选定；共同投影负责 BUFF、牌堆、资源、顺位、阶段、残留与战区。
var _source = null
## 与本地 source/query 共享的公开 ID 表；只适配旧对象输入，不执行规则。
var _held_action_ids = null
var _source_is_local := false
## D15：实例代际与 UI attempt 分离；发送 OK 不结算。
var _battle_commands = null
var _battle_command_epoch: int = 0
var _battle_command_result: Callable
var _battle_command_observer: int = -1
var _battle_commands_retiring: bool = false
var _battle_commands_invalidating: bool = false
var _battle_commands_stopped: bool = false
var _end_command_attempt: Dictionary = {}
var _host_lifecycle = null
var _local_player_id: int = -1:
	set(value):
		if _local_player_id == value:
			return
		_local_player_id = value
		_seat_controller.set_single_local(value)
		if _source_is_local and _source != null:
			_source.set_seat(value)
			_retire_battle_commands("座位已变化，执行结果未知")
			_rebuild_battle_commands()
var _main_area_index: int = -1

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
var _toast_hide_tween: Tween
var _toast_generation: int = 0
## 模块集中开关：以下功能默认关闭，需要打开时手动置 true
var enable_old_features := false

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
@onready var _debug_console:DebugConsoleUI = $DebugConsole
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
## 旧专项夹具写入兼容；生产阶段判断只读共享 key，不回退本机下标。
var _last_phase_index: int = -1
var _shared_phase_key: Array = []
var _shared_phase_observer: int = -1
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
var _broadcast_batch_id: int = 0
var _broadcast_node: Control = null
var _broadcast_active := false
var _broadcast_wait_elapsed := 0.0
var _broadcast_reveal_done := false

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


@onready var _tactical_confirm: Control = $ModalLayer/TacticalConfirm
@onready var _effect_modal: Control = $ModalLayer/EffectChoice
@onready var _effect_result_modal: Control = $ModalLayer/EffectResult
@onready var _hover_zoom: Control = $HoverZoom
@onready var _hover_desc: Control = $HoverDesc
@onready var _card_select_panel: Control = $ModalLayer/CardSelect
@onready var _player_select_panel: Control = $ModalLayer/PlayerSelect
@onready var _opponent_drawer: Control = $ModalLayer/OpponentDrawer
@onready var _power_tooltip: Control = $ModalLayer/PowerTooltip
@onready var _pause_menu: Control = $ModalLayer/PauseMenu


func _ready() -> void:
	_ops.get_node("EndButton").pressed.connect(_on_end_phase_pressed)
	_bind_host_lifecycle()
	_bind_board_return_controls()
	_bind_tactical_confirmation()
	_bind_card_view_controls()
	_bind_pause_menu_controls()
	_bind_fly_layer()
	$CardBrowser/Panel/Close.pressed.connect(_close_card_browser)
	$LogBrowser/Panel/Close.pressed.connect(func() -> void: $LogBrowser.hide())
	$CardModificationHistory/Panel/Close.pressed.connect(_close_card_modification_history)
	var drawer_box := _opponent_drawer.get_node("VBox") as Control
	drawer_box.set_meta("layout_insets", Vector4(drawer_box.offset_left, drawer_box.offset_top, drawer_box.offset_right, drawer_box.offset_bottom))
	var spell_scroll := _self.get_node("Spells/SpecialScroll") as ScrollContainer
	spell_scroll.gui_input.connect(_on_hscroll_wheel.bind(spell_scroll))
	if _opponent_drawer != null:
		var btn_oog := _opponent_drawer.get_node_or_null("VBox/BtnOutOfGame") as Button
		if btn_oog and not btn_oog.pressed.is_connected(_on_drawer_out_of_game_pressed):
			btn_oog.pressed.connect(_on_drawer_out_of_game_pressed)
	if network_session != null:
		_source = preload("res://scripts/game_scene/battle_io/network_battle_source.gd").new(network_session)
		_bind_event_discard_controls("公共事件弃牌 · %s", false)
		_bind_discard_browsing_controls()
		_network_presenter = preload("res://scripts/net/ui/v2_view_presenter.gd").new(self, network_session)
		_source.bind_group_selection(_network_presenter.selection)
		network_session.request_associations_invalidated.connect(_on_battle_commands_invalidated)
		_rebuild_battle_commands()
		_network_presenter.refresh()
		_update_board_return_controls()
		_select_scroll(_default_area_index())
		return
	_driver.state_changed.connect(refresh_all_ui)
	_driver.ai_turn_started.connect(_clear_ai_play_prompt)
	_driver.ai_played_card.connect(_on_ai_played_card)
	_local_player_id = GameData.player_id
	if !GameStart._started:
		GameStart.game_start([0, 1, 2, 3, 4, 5, 6])
	# 本地成功开局的创建边界只交接原来源；AI 延期入口不补票。
	_driver.source_context = GameStart.startup_context()
	var builder = create_local_view_builder()
	var query = preload("res://scripts/match/match_seat_query.gd").new(builder)
	_held_action_ids = builder.ids
	_source = preload("res://scripts/game_scene/battle_io/local_battle_source.gd").new(_local_player_id, builder, query)
	_source_is_local = true
	_bind_event_discard_controls("%s · 事件弃牌", true)
	_rebuild_battle_commands()
	# 原主图作为各卷轴的内容模板；所有地图初始收起。
	if not _declare_local_broadcast_confirmation():
		_stop_battle_commands()
		set_process(false)
		_say("播报确认能力声明失败，已停止本地推进；请返回菜单重新开局")
		return
	_main.hide()
	_events.hide()
	_seats.hide()
	_top.get_node("BoardButton").pressed.connect(_toggle_scoreboard)
	# 行动横幅是提示层：它排在卷轴之前会被卷轴里的出牌区盖住（牌压住横幅头像）。
	# 提到最后一位保证横幅在上，同时忽略鼠标，避免它吃掉底下的地图点击
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	move_child(_banner, get_child_count() - 1)
	# 轮次变更时被抽出的卡会抬到卷轴之上，横幅要再高一层才不会被它平移时盖住
	_banner.z_index = BANNER_Z
	_ops.get_node("PlayButton").pressed.connect(_confirm_held_cards)
	_top.get_node("LogButton").pressed.connect(_open_game_log)

	# ModalLayer 弹窗接线（用旧控制器的同源判据，规则不变）

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

	if _board != null:
		_board.visible = false
	set_debug_console_enabled(_debug_console_enabled_on_start)
	refresh_all_ui()
	_select_scroll(_default_area_index())


## 本地组合根的单职责构建器工厂；query/source/commands 沿用同一身份表。
func create_local_view_builder() -> RefCounted:
	return preload("res://scripts/match/view_builder.gd").new()


func _bind_fly_layer() -> void:
	# 打牌动画层：满屏、不吃鼠标，压在手牌之上、弹窗之下
	_fly_layer = Control.new()
	_fly_layer.name = "FlyLayer"
	_fly_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fly_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fly_layer)
	move_child(_fly_layer, _hand.get_index() + 1)



func _exit_tree() -> void:
	_stop_battle_commands()
	if _source != null:
		if _source_is_local:
			_source.invalidate()
		else:
			_source.close()
		_source = null
	if _network_presenter != null:
		_network_presenter.release()
		_network_presenter = null
	if _host_lifecycle != null:
		_host_lifecycle.close()
		_host_lifecycle = null



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
	if network_session != null:
		return _network_presenter.default_area_index()
	var area := _player_area(_local_player_id)
	return MapData.areas.find(area if area != null else MapData.magic_workshop)


func _return_to_network_lobby() -> void:
	if _host_lifecycle != null and _host_lifecycle.lobby_available():
		_host_lifecycle.request_lobby()


## 组合根显式声明协议/场景以及两种查询；组件不猜 UI 或规则状态。
func _bind_host_lifecycle() -> void:
	if network_session == null:
		return
	_host_lifecycle = preload("res://scripts/game_scene/battle_io/battle_host_lifecycle.gd").new(
		self, network_session, preload("res://assets/scenes/main_menu/multiplayer_lobby.tscn"),
		"match_finished_lobby", _read_finished_lobby_request, _read_network_lobby_state)
	_host_lifecycle.changed.connect(_update_board_return_controls)
	_host_lifecycle.notice.connect(_say)
	_host_lifecycle.transferring.connect(_stop_battle_commands)

func _network_lobby_available() -> bool:
	return _host_lifecycle != null and _host_lifecycle.lobby_available()

func _read_network_lobby_state() -> bool:
	return network_session != null and network_session.view.get("phase", "") == "lobby" and network_session.read_match().is_empty()

func _read_finished_lobby_request() -> Dictionary:
	if network_session == null:
		return {}
	var state: Dictionary = network_session.read_match()
	if network_session.view.get("phase") != "playing" or network_session.view.get("owner") != network_session.peer_id() or not state.get("game_over", false) or not state.get("seq") is int or network_session.read_actions().get("management_paused", false):
		return {}
	return {"view_seq":state.seq}

func _request_finished_lobby() -> void:
	if _host_lifecycle != null:
		_host_lifecycle.request_lobby()


func _bind_board_return_controls() -> void:
	if _board == null:
		return
	for item in [["ReturnActions/ReturnToLobby", _request_finished_lobby], ["ReturnActions/ReturnToMainMenu", _return_to_main_menu]]:
		var button := _board.get_node_or_null(item[0]) as Button
		if button != null and not button.pressed.is_connected(item[1]):
			button.pressed.connect(item[1])
	_update_board_return_controls()


func _update_board_return_controls() -> void:
	if _board == null:
		return
	var ended: bool = bool(network_session.read_match().get("game_over", false)) if network_session != null else GameProgress.is_game_over
	if _host_lifecycle != null and (_host_lifecycle.pending() or _host_lifecycle.outcome_unknown()):
		ended = ended or _game_over_shown
	var main_menu := _board.get_node_or_null("ReturnActions/ReturnToMainMenu") as Button
	if main_menu != null:
		main_menu.visible = ended
	var lobby := _board.get_node_or_null("ReturnActions/ReturnToLobby") as Button
	if lobby != null:
		var completed:bool = _network_lobby_available()
		var owner:bool = network_session != null and network_session.view.get("owner") == network_session.peer_id()
		var pending:bool = _host_lifecycle != null and _host_lifecycle.pending()
		var unknown:bool = _host_lifecycle != null and _host_lifecycle.outcome_unknown()
		lobby.visible = completed or (network_session != null and ended)
		lobby.disabled = not completed and (not owner or pending or unknown or network_session.view.get("phase") != "playing" or network_session.read_actions().get("management_paused",false))
		lobby.text = "返回房间大厅" if completed or (owner and not pending and not unknown) else ("执行结果未知" if unknown else ("正在返回大厅…" if owner else "等待房主返回大厅"))

func _process(delta: float) -> void:
	_refresh_card_modification_history()
	if network_session != null:
		if _host_lifecycle == null or not _host_lifecycle.poll(delta):
			return
		_rebuild_battle_commands()
		_network_presenter.refresh()
		_update_board_return_controls()
		_update_fly_sizes(delta)
		_update_held_cards(delta)
		_update_power_badges()
		_update_hover_zoom_keepalive(delta)
		_update_event_fan(delta, get_global_mouse_position())
		_update_local_spell_box(delta)
		_update_default_area(delta)
		_update_breathing()
		_update_battle_broadcast(delta)
		return
	var _t0 := Time.get_ticks_usec()
	_update_fly_sizes(delta)

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
	_update_event_fan(delta, get_global_mouse_position())

	_update_local_spell_box(delta)
	_update_default_area(delta)
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
	
	_update_breathing()
	# 测完整 _process 耗时（之前只在 _update_fly_sizes 后累加，测到的几乎为空，
	# 后半段重活全漏掉了，导致误判"逻辑不耗时"）
	if _fade_debug:
		_proc_us_sum += Time.get_ticks_usec() - _t0
		_proc_n += 1


func _update_breathing() -> void:
	var alpha := BREATH_MIN_ALPHA + (1.0 - BREATH_MIN_ALPHA) * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU / BREATH_PERIOD))
	for frame in _breathing:
		if is_instance_valid(frame):
			frame.modulate.a = alpha

func _update_default_area(delta:float) -> void:
	if _main_area_index >= 0 and _main_area_index < _strips.get_child_count():
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

func refresh_all_ui() -> void:
	if _source_is_local and _source != null:
		_source.invalidate()
	_update_board_return_controls()
	if network_session != null:
		if _network_presenter != null:
			_network_presenter.refresh()
		return
	if !GameData.player_data_library.has(_local_player_id):
		return
	var key := [GameProgress.current_round, GameProgress.current_phase_index, GameProgress.current_player_id]
	if key != _turn_presentation_key:
		_turn_read_remaining = TURN_ENTRY_SECONDS + TURN_READ_SECONDS if GameProgress.current_player_id >= 0 else 0.0
		_turn_presentation_key = key
	_main_area_index = clampi(_main_area_index, -1, MapData.areas.size() - 1)
	_breathing.clear()
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
	_bind_residue_piles()


## ---------- 数据读取（全部走引擎，界面不自己判规则） ----------

func _pl(id: int) -> Dictionary:
	return GameDataManager.find_player_data(id)


## 对应玩家的已过滤 BUFF；不从规则对象自行重建展示字段。
## 抽屉可由独立点击触发，显式开启新读取周期以免使用上次整屏刷新快照。
func _projected_buffs(id: int, fresh: bool = false) -> Array:
	if _source == null:
		return []
	if fresh and _source_is_local:
		_source.invalidate()
	var view: Dictionary = _source.read_view()
	for player in view.get("players", []):
		if player is Dictionary and int(player.get("id", -1)) == id:
			return player.get("buffs", [])
	return []


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
	var view: Dictionary = _source.read_view() if _source != null else {}
	for player in view.get("players", []):
		if int(player.id) == id:
			return str(player.get("master", {}).get("name", player.get("player_name", "")))
	return ""


## 玩家名（玩家数据字段 player_name，开局由 GameStart 按号位写入默认名）。
## 与 _player_name 的区别：那个返回御主显示名，这里返回玩家本人的名字；
## 没命名时返回空串，不用御主名顶替（数据缺了就不显示，不猜）。
func _player_name_data(id: int) -> String:
	return str(_pl(id).get("player_name", ""))


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
	var view: Dictionary = _source.read_view() if _source != null else {}
	var players: Array = view.get("players", []).duplicate()
	players.sort_custom(func(a, b): return a.get("score", 0) > b.get("score", 0))
	return players.map(func(player): return int(player.id))


func _players_in_area(area: BaseMapArea) -> Array:
	return _ordered_ids().filter(func(id): return _player_area(id) == area)


func _area_score(area: BaseMapArea) -> int:
	var total := _num(area._score)
	for ev in area._events:
		if ev is BaseEvent and not bool(ev.get("_is_concealed")):
			total += _num(ev._score)
	return total


## 网络与单机共用事件堆排序、图片和原有查看入口。
func _bind_area_event_cards(row: Control, events: Array) -> void:
	_sync_items(row, "MiniEventCard", events.size())
	row.visible = not events.is_empty()
	var slots: Array = row.get_children()
	slots.sort_custom(func(a, b): return int(a.get_meta("event_index", events.size())) < int(b.get_meta("event_index", events.size())))
	for index in range(events.size()):
		var event = events[index]
		var slot: Control = slots[index]
		slot.set_meta("event_index", index)
		row.move_child(slot, 0)
		var concealed: bool = event.get("concealed", true) if event is Dictionary else event._is_concealed
		var image: String = (event.get("back_image", "") if concealed else event.get("image", "")) if event is Dictionary else (_back("event") if concealed else str(event._card_img))
		_bind_card(slot, image)
		if concealed:
			_disable_card_zoom(slot)
		else:
			bind_zoom_for_card(slot, event)

func _area_events(area: BaseMapArea) -> Array:
	return area._events.filter(func(e): return e is BaseEvent)


func _servant_class(id: int) -> String:
	var servant = _pl(id).get("servant")
	return str(servant.get("_servant_class")).capitalize() if servant != null else ""


func _class_shown(id: int) -> String:
	return (_servant_class(id) if GameDataManager.can_see_servant_class(_local_player_id, id) else "???").to_upper()


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
	var benefit := GetEffectiveLocationBenefit.current_benefit(loc)
	if benefit > 0:
		return "地利 %d" % benefit
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
	var removed: Array = _out_of_game_cards(pl)
	for key in ["hand_cards", "deck", "discard", "played_cards"]:
		removed.append_array(pl.get(key, []))
	return entries.filter(func(e): return not removed.has(e["card"]))


## 玩家的"游戏外"卡牌（攻击/技能/其他三区）：抽屉的入口数量与浏览列表共用这一份采集
func _out_of_game_cards(pl: Dictionary) -> Array:
	var cards: Array = []
	var zone: Dictionary = pl.get("out_of_game", {})
	for key in ["attacks", "skills", "others"]:
		var values = zone.get(key, [])
		if not values is Array:
			continue
		for card in values:
			if card is BaseCard and not cards.has(card):
				cards.append(card)
	return cards


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


## 令咒余额与声明的特殊令咒种类分别展示，不虚构特殊令咒独立使用次数。
func _special_command_spells(spell_list: Array) -> Array:
	return spell_list.filter(func(card): return card != LoadCommandSpell.get_normal())


func _bind_sigils(row: Control, count: int, spell_list: Array) -> void:
	# 调用方只传 builder 已声明的特殊令咒，不用本机模板重新分类。
	var specials := spell_list
	_sync_items(row, "SpellSummary", 1 if specials.is_empty() else 2)
	for i in range(row.get_child_count()):
		var summary := row.get_child(i) as Control
		var icon := summary.get_node("Icon") as TextureRect
		icon.texture = summary.get_meta("special_texture") if i > 0 else summary.get_meta("normal_texture")
		_set_text(summary, "Count", "×%d" % (specials.size() if i > 0 else count))
		summary.tooltip_text = "特殊令咒" if i > 0 else "令咒"
		summary.modulate.a = 1.0 if i > 0 or count > 0 else 0.4



## 完整令咒仅消费本人过滤卡面，主卡/特殊卡按声明顺序，不解析本机模板。
func _bind_spell_box(box: Control, player: Dictionary) -> void:
	var spells: Array = player.get("command_spells", [])
	box.visible = not spells.is_empty()
	_self.get_node("CountBadge").visible = not spells.is_empty()
	_set_text(_self, "CountBadge/Label", BaseNumber.display_text(player.get("command_spell_count", 0)))
	var primary := box.get_node("SpellCard") as Control
	_bind_spell_view_slot(primary, spells[0] if not spells.is_empty() else {}, int(player.get("id", -1)))
	var row := box.get_node("SpecialScroll/Cards") as Control
	_sync_items(row, "SpellCard", maxi(0, spells.size() - 1))
	for i in range(row.get_child_count()):
		_bind_spell_view_slot(row.get_child(i), spells[i + 1], int(player.get("id", -1)))
	if row.get_child_count() == 0:
		box.set_meta("open", 0.0)
		box.get_node("SpecialScroll").hide()
		box.size.x = SPELL_BOX_SIZE.x

func _bind_spell_view_slot(slot: Control, card: Dictionary, owner: int = -1) -> void:
	slot.set_meta("command_spell_owner", owner)
	slot.set_meta("card", card)
	_bind_card(slot, card.get("image", "") if card.get("visible", false) and not card.get("concealed", true) else card.get("back_image", ""))
	bind_zoom_for_card(slot, card)
	var effects := _manual_effects_of(card)
	slot.set_meta("manual_effects", effects)
	slot.modulate = Color.WHITE if not effects.is_empty() else Color(0.55, 0.55, 0.55)
	if not slot.has_meta("spell_view_bound"):
		slot.set_meta("spell_view_bound", true)
		for child in slot.find_children("*", "Control", true, false):
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		_bind_effect_button(slot)
		slot.gui_input.connect(_on_local_special_spell_input.bind(slot))


func _on_local_special_spell_input(event: InputEvent, slot: Control) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	slot.accept_event()
	# 本人资源区入口先核权威候选；无权限不弹窗、不写暂存、不提示副作用。
	if _source == null or _is_progress_blocked() or not _held_input_available() or not _battle_command_input_available("activate"):
		return
	if _source_is_local:
		_source.invalidate()
	var owner = slot.get_meta("command_spell_owner", -1)
	if owner != _source.read_view().get("observer", -1) or owner != _local_player_id or owner != _battle_command_observer \
			or not _source.read_pending().is_empty() or _manual_effects_of(slot.get_meta("card", {})).is_empty():
		return
	_on_held_effect_pressed(slot)


## 卡框与展开条共用连续命中区，向右最多展示一张特殊卡，其余横向无条滚动。
func _update_local_spell_box(delta: float) -> void:
	var box := _self.get_node("Spells") as Control
	var scroll := box.get_node("SpecialScroll") as ScrollContainer
	var row := scroll.get_node("Cards") as Control
	# 令咒不在手牌列表中，但共用同一个候选声明与发动按钮，不另建网络路由。
	var slots: Array = [box.get_node("SpellCard")]
	slots.append_array(row.get_children())
	var hovered := get_viewport().gui_get_hovered_control()
	var actions: Dictionary = _source.read_actions() if _source != null else {}
	for slot: Control in slots:
		var effects := _manual_effects_of(slot.get_meta("card", {}), actions)
		var enabled := slot.is_visible_in_tree() and not _is_progress_blocked() and _battle_command_input_available("activate")
		slot.set_meta("manual_effects", effects if enabled else [])
		_update_held_effect_button(slot, hovered == slot or (hovered != null and slot.is_ancestor_of(hovered)), delta)
	var hover := box.get_global_rect().has_point(get_global_mouse_position())
	var open := move_toward(float(box.get_meta("open", 0.0)), 1.0 if hover and row.get_child_count() > 0 else 0.0, delta / SCROLL_LEAVE_SECONDS)
	box.set_meta("open", open)
	box.size.x = SPELL_BOX_SIZE.x + SPELL_BOX_STEP * open
	scroll.visible = open > 0.0
	scroll.size.x = SPELL_BOX_SIZE.x * open
	scroll.modulate.a = open


## 呼吸描边：登记到 _breathing，由 _process 统一按全局相位设透明度
func _breathe(frame: Control) -> void:
	frame.visible = true
	_breathing.append(frame)


## 席位模板（Seat / StripSeat 内的 Seat）：环色、空席数值或占位头像与角标
func _bind_seat(seat: Control, loc: Dictionary, with_label: bool) -> void:
	var magic = loc.get("magic", 0)
	var benefit = loc.get("benefit", 0)
	var is_mana: bool = magic > 0
	seat.get_node("Ring").mana = is_mana
	var occupants: Array = loc.get("players", [])
	for path in ["ValueNum", "ValueEmpty", "Avatar", "Badge"]:
		seat.get_node(path).hide()
	var value := seat.get_node("ValueNum") as Label
	if occupants.is_empty():
		value.visible = is_mana or benefit > 0
		value.text = "+" + BaseNumber.display_text(magic) if is_mana else BaseNumber.display_text(benefit)
		value.theme_type_variation = "Mana" if is_mana else "Gold2"
		seat.get_node("ValueEmpty").visible = not value.visible
	else:
		var pid: int = int(occupants[0])
		var avatar := seat.get_node("Avatar") as Control
		avatar.show()
		var view: Dictionary = _source.read_view() if _source != null else {}
		var image := ""
		for player in view.get("players", []):
			if player.id == pid:
				image = str(player.get("avatar", ""))
		_bind_avatar(avatar, image, "AvatarMana" if pid == _local_player_id else "AvatarGold2")
		if is_mana or benefit > 0:
			_bind_badge(seat.get_node("Badge"), "+" + BaseNumber.display_text(magic) if is_mana else BaseNumber.display_text(benefit), "BadgeMana" if is_mana else "BadgeGold")
	if with_label:
		_set_text(seat, "Label", "魔力席" if is_mana else ("地利 " + BaseNumber.display_text(benefit) if benefit > 0 else "席位"))


func _say(text: String) -> void:
	_toast_generation += 1
	if _toast_hide_tween != null and _toast_hide_tween.is_valid():
		_toast_hide_tween.kill()
	_set_text(_toast, "Label", text)
	_toast.visible = true
	_toast_hide_tween = _toast.create_tween()
	_toast_hide_tween.tween_interval(TOAST_SECONDS)
	_toast_hide_tween.tween_callback(_hide_toast.bind(_toast_generation))

func _hide_toast(generation: int) -> void:
	if generation == _toast_generation:
		_toast.visible = false
		_toast_hide_tween = null


## ---------- 0 顶栏 ----------

func _bind_top() -> void:
	var view: Dictionary = _source.read_view() if _source != null else {}
	_bind_shared_phase_view(view)

## 同源生命周期：首次及 observer/恢复重绑不播；同 key 不重播，终局终止。
func _bind_shared_phase_view(view: Dictionary) -> void:
	if view.is_empty():
		_clear_shared_phase_residue_visuals()
		return
	var observer := int(view.get("observer", -1))
	if observer != _shared_phase_observer:
		_clear_shared_phase_residue_visuals()
		_shared_phase_observer = observer
	_bind_phase_timeline(int(view.get("round", 0)), str(view.get("phase", "")), view.get("state", {}))
	var key: Array = [view.get("round", 0), view.get("phase", ""), view.get("game_over", false)]
	if key == _shared_phase_key:
		return
	if bool(view.get("game_over", false)):
		if _phase_tween != null:
			_phase_tween.kill()
		if _phase_banner != null:
			_phase_banner.hide()
		_phase_anim_busy = false
	elif not _shared_phase_key.is_empty() and str(view.get("phase", "")) != "":
		_phase_anim_busy = network_session == null
		_play_phase_banner(str(view.phase), _finish_local_phase_banner if network_session == null else Callable())
	_shared_phase_key = key

## 展示退出只清视觉，不操作规则；presenter 自行失效传输/手牌缓存。
func _clear_shared_phase_residue_visuals() -> void:
	_shared_phase_key.clear()
	_shared_phase_observer = -1
	_phase_anim_busy = false
	for path in ["Self", "Master", "Hand"]:
		get_node(path).hide()
	_bind_spell_box(_self.get_node("Spells"), {})
	_on_close_opponent_drawer_pressed()
	if _phase_tween != null:
		_phase_tween.kill()
	if _phase_banner != null:
		_phase_banner.hide()
	var local := get_node_or_null("LocalResiduePile") as Control
	if local != null:
		local.hide()
	for child in _rivals.get_children():
		var pile := child.get_node_or_null("ResiduePile") as Control
		if pile != null:
			pile.hide()

## 纯视觉入口：单人规则与网络过滤视图共用模板与状态颜色。
func _bind_phase_timeline(cur: int, current: String, state: Dictionary) -> void:
	var center := _top.get_node("Center")
	_set_text(center, "RoundLabel", "第 %d 回合" % cur)
	var climax: Array = state.get("climax_rounds", [])
	var total: int = int(state.get("total_rounds", 0))
	_set_text(center, "NightLabel", "高潮回合" if climax.has(cur) else "夜 %d / %d" % [cur, total])
	var phases := center.get_node("Phases")
	_clear(phases)
	var passed := true
	for key in state.get("phases", []):
		var on: bool = key == current
		if on:
			passed = false
		var tag := _spawn("PhaseOn" if on else ("PhasePassed" if passed else "PhasePending"), phases)
		_set_text(tag, "Label", "%s阶段" % _phase_cn(key))
	var dots := center.get_node("Dots")
	dots.show()
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
	var view: Dictionary = _source.read_view() if _source != null else {}
	_local_player_id = int(view.get("observer", -1))
	_rivals.visible = not view.is_empty()
	var ids: Array = view.get("players", []).map(func(player): return int(player.id))
	_bind_rival_order(ids, -1 if view.get("game_over", false) else int(view.get("current_player", -1)), int(view.get("round", 0)), _bind_single_rival)

func _bind_rival_order(actual_ids:Array, actor:int, current_round:int, bind_player:Callable) -> void:
	var ids := actual_ids.duplicate()
	# 从行动者起循环展示真实顺位：已行动者回到队尾，不改规则顺位和编号。
	var actor_index := ids.find(actor)
	if actor_index > 0:
		ids = ids.slice(actor_index) + ids.slice(0, actor_index)
	var old_positions: Dictionary = {}
	var order_changed := not _rival_order_snapshot.is_empty() and ids != _rival_order_snapshot
	# 轮次变更：回合号变化。换人交接：回合号不变、仅行动者变化。首次绑定两者都不触发。
	var round_changed := _last_round != -1 and current_round != _last_round
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
			# "我方"槽与对手卡共用同一份取数：只显示我方头像（头像在上、文字在下，由场景节点定义）
			var self_player: Dictionary = _view_player_in(_source.read_view() if _source != null else {}, id)
			_bind_avatar(slot.get_node("Avatar"), self_player.get("avatar", ""), "AvatarMana")
			_set_text(slot, "Order/Label", str(actual_ids.find(id) + 1))
			# 轮到自己时与其它玩家用同一套高亮；换人交接期间先不亮，等金框飞到再亮
			_set_acting_highlight(slot, id == actor and id != _pending_rival_highlight_id)
			continue
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
		_set_acting_highlight(card, id == actor and id != _pending_rival_highlight_id)
		_set_text(card, "Order/Label", str(actual_ids.find(id) + 1))
		bind_player.call(card, id)
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
	_last_round = current_round

func _bind_single_rival(card: Control, id: int) -> void:
	var view: Dictionary = _source.read_view() if _source != null else {}
	var player: Dictionary = _view_player_in(view, id)
	if player.is_empty():
		return
	card.modulate = Color(0.6, 0.6, 0.6, 0.45) if player.get("is_out", false) else Color.WHITE
	_bind_avatar(card.get_node("Avatar"), player.get("avatar", ""))
	_set_text(card, "Name", player.get("master", {}).get("name", player.get("player_name", "")))
	_set_text(card, "Class", player.get("servant_class", ""))
	var area_name := ""
	for area in view.get("areas", []):
		for location in area.get("locations", []):
			if location.id == player.get("location", 0):
				area_name = str(area.name)
	_set_text(card, "Loc", area_name)
	card.get_node("MagicSigil").set_value(player.get("magic", 0), player.get("magic_limit", 0))
	_set_text(card, "Stats/PowerStat/V", BaseNumber.display_text(player.get("total_power", 0)))
	_set_text(card, "Stats/ScoreStat/V", BaseNumber.display_text(player.get("score", 0)))
	_bind_sigils(card.get_node("Stats/Spells"), int(player.get("command_spell_count", 0)), player.get("special_command_spells", []))
	card.get_node("Stats").add_theme_constant_override("separation", 2 if card.get_node("Stats/Spells").get_child_count() > 1 else 10)


## 从给定视图里按玩家 id 取玩家字典（找不到返回空字典）。
## 顺位栏的"我方"槽与对手卡共用这一份取数逻辑，避免两处各写一遍查找；
## 视图由调用方读一次后传入，不在这里重复读取。
func _view_player_in(view: Dictionary, id: int) -> Dictionary:
	for candidate in view.get("players", []):
		if int(candidate.id) == id:
			return candidate
	return {}

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


## 动画只对同一组、非空且无重复的顺位序列生效；玩家加入/退出及空投影由绑定结果直接呈现。
## 这样既保留合法单元素交接，也不让异常输入进入依赖首元素的传送带路径。
func _rival_animation_inputs_are_compatible(expected_ids: Array, previous_ids: Array) -> bool:
	if expected_ids.is_empty() or previous_ids.is_empty() or expected_ids.size() != previous_ids.size():
		return false
	var expected_set: Dictionary = {}
	var previous_set: Dictionary = {}
	for raw_id in expected_ids:
		var id := int(raw_id)
		if expected_set.has(id):
			return false
		expected_set[id] = true
	for raw_id in previous_ids:
		var id := int(raw_id)
		if previous_set.has(id):
			return false
		previous_set[id] = true
	if expected_set.size() != previous_set.size():
		return false
	for id in expected_set:
		if not previous_set.has(id):
			return false
	return true


## 无法动画的投影不应留下上一代 busy、tween 或 pending 高亮。
func _clear_rival_animation_state() -> void:
	_rival_anim_generation += 1
	_rival_anim_busy = false
	_pending_rival_highlight_id = -1
	if _rival_shift_tween != null and _rival_shift_tween.is_running():
		_rival_shift_tween.kill()
	_rival_shift_tween = null
	if _gold_frame_tween != null and _gold_frame_tween.is_running():
		_gold_frame_tween.kill()
	_gold_frame_tween = null
	if _gold_frame_node != null:
		_gold_frame_node.visible = false
		_breathing.erase(_gold_frame_node)
	for tween in _rival_wrap_tweens:
		if tween.is_running():
			tween.kill()
	_rival_wrap_tweens.clear()


## 传送带：从当前视觉位置并排左移到目标位置，队首卡左出右进绕到队尾。
## 调用前卡片已钉在旧位置；await 到所有平移完成，供调用方串行。
func _shift_cards(targets: Dictionary, expected_ids: Array, previous_ids: Array, seconds: float) -> void:
	if not _rival_animation_inputs_are_compatible(expected_ids, previous_ids):
		return
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
	if not _rival_animation_inputs_are_compatible(expected_ids, previous_ids):
		_clear_rival_animation_state()
		return
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
	if not _rival_animation_inputs_are_compatible(expected_ids, previous_ids):
		_clear_rival_animation_state()
		return
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
	_phase_anim_busy = true
	_play_phase_banner(str(GameProgress.phases[phase_index].get("name", "")), _finish_local_phase_banner)

func _finish_local_phase_banner() -> void:
	_phase_anim_busy = false
	var curr := GameProgress.current_player_id
	if curr >= 0:
		_show_banner_actor(curr)

## 网络可直接调用的纯视觉动画，不访问本机规则，不冻结远端权威。
func _play_phase_banner(phase_name: String, completed: Callable = Callable()) -> void:
	if phase_name == "":
		return
	var pb := _phase_banner_node()
	_phase_banner_label.text = "%s阶段" % _phase_cn(phase_name)
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
		if completed.is_valid():
			completed.call()
	)


## ---------- 12 局势 / 弃牌 / 17 路线 ----------

func _bind_situation_and_piles() -> void:
	var view: Dictionary = _source.read_view() if _source != null else {}
	var situ: Dictionary = view.get("situation", {})
	_situation.visible = not view.is_empty()
	_piles.visible = not view.is_empty()
	var situ_card := _situation.get_node("SituCard") as Control
	situ_card.visible = not situ.is_empty()
	_situation.get_node("Empty").visible = situ.is_empty()
	if not situ.is_empty():
		_bind_card(situ_card, situ.get("image", "") if situ.get("visible", false) and not situ.get("concealed", true) else situ.get("back_image", ""))
		bind_zoom_for_card(situ_card, situ)
	else:
		_disable_card_zoom(situ_card)
	_bind_pile(_piles.get_node("EventPile"), _back("event"), view.get("event_discard", []).size())
	_bind_pile(_piles.get_node("SituationPile"), _back("situation"), view.get("situation_discard", []).size())
	var mine: Dictionary = {}
	for player in view.get("players", []):
		if player.id == view.get("observer", -1):
			mine = player
	_bind_pile(_ops.get_node("Deck"), _back("attack"), int(mine.get("deck_count", 0)))
	var discard: Array = mine.get("discard", [])
	var face := _back("attack")
	if not discard.is_empty():
		var card: Dictionary = discard.back()
		face = card.get("image", "") if card.get("visible", false) and not card.get("concealed", true) else card.get("back_image", "")
	_bind_pile(_ops.get_node("Discard"), face, discard.size())
	var row := _route.get_node("Row")
	var areas: Array = view.get("areas", [])
	var needed := maxi(0, areas.size() * 2 - 1)
	while row.get_child_count() > needed:
		var last := row.get_child(row.get_child_count() - 1)
		row.remove_child(last)
		last.queue_free()
	while row.get_child_count() < needed:
		_spawn("RouteNode" if row.get_child_count() % 2 == 0 else "RouteArrow", row)
	for i in areas.size():
		var area: Dictionary = areas[i]
		var on := i == _main_area_index
		var node := row.get_child(i * 2) as Control
		_bind_avatar(node.get_node("Circle"), _area_image(i), "AvatarGold2" if on else "AvatarThin")
		_set_text(node, "Name", str(area.get("name", "")))
		node.get_node("Name").theme_type_variation = "Gold2" if on else "Text"
		if i < areas.size() - 1:
			# builder 未声明 move_cost；禁止用本机规则补齐网络/本地投影。
			var cost := row.get_child(i * 2 + 1).get_node("Cost") as Label
			cost.visible = area.has("move_cost")
			cost.text = "魔力 " + BaseNumber.display_text(area.move_cost) if cost.visible else ""


func _bind_pile(pile: Control, back: String, count: int) -> void:
	_bind_card(pile.get_node("Back1"), back)
	_bind_card(pile.get_node("Back2"), back)
	_set_text(pile, "Count/Label", str(count))


## 组合根保留原有标题与按钮开合约定；浏览逻辑不感知传输或规则对象。
func _bind_event_discard_controls(title_format: String, toggle: bool) -> void:
	_piles.get_node("EventPile/Open").pressed.connect(_open_event_discard_menu.bind(toggle))
	for entry in [["Shinto", "shinto", "新都"], ["Miyama", "miyama", "深山町"], ["Other", "other", "其他"]]:
		$EventDiscardMenu.get_node("Choices/" + entry[0]).pressed.connect(_open_event_discard.bind(entry[1], title_format % entry[2]))


func _open_event_discard_menu(toggle: bool) -> void:
	$EventDiscardMenu.visible = not $EventDiscardMenu.visible if toggle else true
	if $EventDiscardMenu.visible:
		_raise_modal($EventDiscardMenu)


## 分类、公开权限与数组顺序由 source 声明；缺字段为空，不回查本机 MapData。
func _open_event_discard(category: String, title: String) -> void:
	var view: Dictionary = _source.read_view() if _source != null else {}
	var grouped: Dictionary = view.get("event_discard_by_source", {})
	$EventDiscardMenu.hide()
	_show_card_browser(title, grouped.get(category, []))


## 当前只有网络组合根开放这两个入口；不改变本地牌堆的既有能力。
func _bind_discard_browsing_controls() -> void:
	for entry in [["Ops/Discard", "我方弃牌", true], ["Piles/SituationPile", "公共局势弃牌", false]]:
		var pile: Control = get_node(entry[0])
		pile.mouse_filter = Control.MOUSE_FILTER_STOP
		pile.gui_input.connect(_on_discard_browse_input.bind(pile, entry[1], entry[2]))
		for child in pile.find_children("*", "Control", true, false):
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_discard_browse_input(event: InputEvent, pile: Control, title: String, personal: bool) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_open_discard_browser(title, personal)
		pile.accept_event()


## 只消费当前 source：本人按 observer 精确选择；不缓存、不排序、不合并相同 ID。
func _open_discard_browser(title: String, personal: bool) -> void:
	if _source_is_local and _source != null:
		_source.invalidate()
	var view: Dictionary = _source.read_view() if _source != null else {}
	var cards: Array = []
	if personal:
		var observer: int = int(view.get("observer", -1))
		if observer >= 0:
			for player in view.get("players", []):
				if int(player.get("id", -1)) == observer:
					cards = player.get("discard", [])
					break
	else:
		cards = view.get("situation_discard", [])
	$EventDiscardMenu.hide()
	_show_card_browser(title, cards)


## 只读查看与效果选牌分离；复用现有事件卡模板和贴图绑定，不提交任何规则动作。
func _show_card_browser(title: String, cards: Array) -> void:
	_hide_event_zoom()
	var panel := $CardBrowser/Panel
	_set_text(panel, "Title", "%s · %d" % [title, cards.size()])
	panel.get_node("Empty").visible = cards.is_empty()
	var row := panel.get_node("CardScroll/Row")
	_clear(row)
	for card in cards:
		var slot := _spawn("MiniEventCard", row)
		slot.custom_minimum_size = (_tpl.get_node("EventCard") as Control).size
		slot.set_meta("card", card)
		var image: String = str(card.get("image", "")) if card is Dictionary and card.get("visible", false) and not card.get("concealed", true) else (str(card.get("back_image", "")) if card is Dictionary else str(card.get("_card_img")))
		_bind_card(slot, image)
		bind_zoom_for_card(slot, card)
	panel.get_node("CardScroll").scroll_horizontal = 0
	$CardBrowser.show()
	# 绘制层级不决定 GUI 命中顺序；浏览器必须在底层抽屉之后接收输入。
	_raise_modal($CardBrowser)
	_raise_modal(_hover_zoom)
	_raise_modal(_hover_desc)


func _close_card_browser() -> void:
	$CardBrowser.hide()
	_hide_event_zoom()


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

func _bind_main(area: Dictionary, content: Control) -> void:
	_set_text(content, "Latin", str(AREA_LATIN.get(str(area.get("name", "")), "")))
	_set_text(content, "Name", str(area.get("name", "")))
	_bind_groups(area, content)


## 席位两排：下排 = 战区固定席位（含空席），上排 = 无固定席位（混战区）玩家头像。
## 两排都放在 ScrollContainer 里，内容超宽时用滚轮横向滚动；滚动位置在刷新间保留
func _bind_seat_rows(area: Dictionary, seats: Control) -> void:
	var locations: Array = area.get("locations", [])
	var seat_sc := seats.get_node("SeatScroll") as ScrollContainer
	var melee_sc := seats.get_node("MeleeScroll") as ScrollContainer
	var seat_row := seat_sc.get_node("Row")
	var melee_row := melee_sc.get_node("Row")
	var fixed: Array = locations.filter(func(loc): return loc.has("capacity") and loc.capacity >= 0)
	var unseated: Array = []
	for loc in locations:
		if loc.has("capacity") and loc.capacity < 0:
			for pid in loc.get("players", []):
				unseated.append({"pid": int(pid), "loc": loc})
	_sync_items(seat_row, "SeatSlot", fixed.size())
	_sync_items(melee_row, "MeleeSeat", unseated.size())
	for i in fixed.size():
		var loc: Dictionary = fixed[i]
		var slot := seat_row.get_child(i) as Control
		_bind_seat(slot.get_node("Seat"), loc, true)
		slot.set_meta("compact", Vector2(13, 148 + locations.find(loc) * 64))
	var view: Dictionary = _source.read_view() if _source != null else {}
	for i in unseated.size():
		var entry: Dictionary = unseated[i]
		var loc: Dictionary = entry.loc
		var seat := melee_row.get_child(i) as Control
		var image := ""
		for player in view.get("players", []):
			if player.id == entry.pid:
				image = str(player.get("avatar", ""))
		_bind_avatar(seat.get_node("Avatar"), image, "AvatarMana" if entry.pid == _local_player_id else "AvatarGold2")
		_set_text(seat, "Label", "混战区")
		var slot: int = loc.players.find(entry.pid)
		seat.set_meta("compact", Vector2(4 + (slot % 3) * 22, 148 + locations.find(loc) * 64 + (slot / 3) * 24))
	melee_sc.visible = not unseated.is_empty()
	seat_sc.visible = not fixed.is_empty()


## 卷轴本体（战区）点击。点击落在这里时消费等待中的位置选择，或走部署/移动
## 入口。复用 _on_battlefield_clicked 已写好的判据链：等位置 → 部署 → 移动
func _on_strip_gui_input(event: InputEvent, strip: Control) -> void:
	if network_session != null:
		_network_presenter.area_input(event, strip)
		return
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


## 滚轮方向：向"后"为 +1（下/右），向"前"为 -1（上/左），其它事件为 0
static func _wheel_direction(event: InputEvent) -> int:
	if not (event is InputEventMouseButton) or not event.pressed:
		return 0
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
		return 1
	if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_LEFT:
		return -1
	return 0


## 按滚轮方向滚动无滚动条的容器：纵向放不下就滚纵向，否则平移横向。
## 判据取滚动条自身范围，不写死内容高度；席位横排与对手抽屉内容区共用
func _wheel_scroll(sc: ScrollContainer, dir: int) -> void:
	if sc == null or dir == 0:
		return
	var v_bar := sc.get_v_scroll_bar()
	if v_bar.max_value > v_bar.page:
		sc.scroll_vertical += int(dir * SEAT_SCROLL_STEP)
	else:
		sc.scroll_horizontal += int(dir * SEAT_SCROLL_STEP)
		sc.set_meta("scroll", sc.scroll_horizontal)


## 席位横排：控件级滚轮（排本身可命中时）
func _on_hscroll_wheel(event: InputEvent, sc: ScrollContainer) -> void:
	var dir := _wheel_direction(event)
	if dir == 0:
		return
	_wheel_scroll(sc, dir)
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


## 展开状态跟随持久玩家组，刷新不重置；复用布局与尺寸过渡。
func _set_group_spread(group: Control, expanded: bool) -> void:
	group.set_meta("expanded", expanded)
	if bool(group.get_meta("residue_pile", false)):
		(group.get_node("Cards") as ScrollContainer).scroll_horizontal = 0
		_layout_residue_pile(group)
		return
	group.get_node("Who/Avatar/CollapseHint").visible = expanded
	group.get_node("Who").tooltip_text = "点击头像收起牌堆" if expanded else "点击牌堆或头像展开"
	(group.get_node("Cards") as ScrollContainer).scroll_horizontal = 0
	(group.get_node("Cards") as ScrollContainer).scroll_vertical = 0
	_layout_play_groups(group.get_parent().get_parent() as Control)


func _on_play_group_toggle(event: InputEvent, group: Control) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_group_spread(group, not bool(group.get_meta("expanded", false)))
		get_viewport().set_input_as_handled()


## 用同一间距同时计算牌堆宽度与槽位位置，避免实际布局与尺寸求解不一致。
func _played_step_ratio(group: Control, count: int, aspect: float) -> float:
	if bool(group.get_meta("expanded", false)):
		return aspect + PLAYED_CARD_GAP_RATIO
	return aspect * minf(float(group.get_meta("stack_step_ratio")), float(group.get_meta("stack_span_ratio")) / maxf(1.0, count - 1))


func _scroll_is_animating() -> bool:
	return _scroll_tween != null and _scroll_tween.is_running()


func _input(event: InputEvent) -> void:
	if _card_modification_history_input(event):
		return
	if network_session != null:
		if _network_presenter.browse_input(event):
			return
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_handle_escape()
		elif event is InputEventMouseMotion:
			_handle_scroll_hover(event)
		return
	# 抽屉分区行没有滚动条：鼠标落在哪一行，滚轮就滚哪一行（卡行横向、状态行纵向）
	if event is InputEventMouseButton and event.pressed and _opponent_drawer != null \
			and _opponent_drawer.visible and _opponent_drawer.get_global_rect().has_point(event.position):
		var drawer_dir := _wheel_direction(event)
		if drawer_dir != 0:
			for row in _drawer_rows():
				var row_scroll := row.get_node_or_null("Scroll") as ScrollContainer
				if row_scroll != null and row_scroll.visible and row_scroll.get_global_rect().has_point(event.position):
					_wheel_scroll(row_scroll, drawer_dir)
					get_viewport().set_input_as_handled()
					return
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
		_handle_escape()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not $EventDiscardMenu.get_global_rect().has_point(event.position) and not _piles.get_node("EventPile/Open").get_global_rect().has_point(event.position):
			$EventDiscardMenu.hide()
	if $CardBrowser.visible or $EventDiscardMenu.visible or $LogBrowser.visible:
		return
	if (_hover_zoom.visible and _hover_zoom.get_global_rect().has_point(get_global_mouse_position())) or (_hover_desc.visible and _hover_desc.get_global_rect().has_point(get_global_mouse_position())):
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] \
			and _opponent_drawer.visible and not _opponent_drawer.get_global_rect().has_point(event.position):
		# 玩家头像保留原本的切换/收起入口；其他外部点击只收抽屉，不穿透操作底层。
		var hovered := get_viewport().gui_get_hovered_control()
		while hovered != null:
			if hovered.has_meta("turn_order_player_id"):
				return
			hovered = hovered.get_parent_control()
		_on_close_opponent_drawer_pressed()
		_hide_event_zoom()
		get_viewport().set_input_as_handled()
		return
	# 只响应真实鼠标移动，不响应布局移动引发的 mouse_entered，避免静止连环切图。
	_handle_scroll_hover(event)

func _handle_scroll_hover(event: InputEvent) -> void:
	if not event is InputEventMouseMotion or event.relative.is_zero_approx():
		return
	if _native_modal_visible():
		return
	if (_pause_menu != null and _pause_menu.visible) or (_debug_console != null and _debug_console.is_panel_open()):
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
	var count := _strips.get_child_count()
	var narrow := (_tpl.get_node("Strip") as Control).size.x
	var width := maxf(narrow, size.x - SCROLL_MARGIN * 2 - (count - 1) * STRIP_STEP)
	var x := (size.x - (count - 1) * STRIP_STEP - narrow) * 0.5 + index * STRIP_STEP
	if _main_area_index >= 0:
		x = SCROLL_MARGIN + index * STRIP_STEP
		if index > _main_area_index:
			x += width - narrow
	return Rect2(Vector2(x, STRIP_TOP), Vector2(width if index == _main_area_index else narrow, 540))


func _select_scroll(index: int) -> void:
	var area_count: int = _strips.get_child_count() if network_session != null else MapData.areas.size()
	if index == _main_area_index or index < -1 or index >= area_count:
		return
	var area_name:String = ""
	if index >= 0:
		if network_session != null:
			var areas:Array = network_session.read_match().get("areas", [])
			if index >= areas.size(): return
			area_name = str(areas[index].name)
		else:
			area_name = str(MapData.areas[index]._area_name)

	_main_area_index = index
	$AreaTitle.visible = index >= 0
	if index >= 0:
		_set_text($AreaTitle, "Name", area_name)
		_set_text($AreaTitle, "Latin", str(AREA_LATIN.get(area_name, "")))
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
	if network_session == null:
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
	var view: Dictionary = _source.read_view() if _source != null else {}
	var areas: Array = view.get("areas", [])
	var actions: Dictionary = _source.read_actions() if _source != null else {}
	var pending: Dictionary = _source.read_pending() if _source != null else {}
	_sync_items($Background, "AreaBackdrop", areas.size())
	var previous_count := _strips.get_child_count()
	_sync_items(_strips, "Strip", areas.size())
	for i in range(areas.size()):
		var area: Dictionary = areas[i]
		var strip := _strips.get_child(i) as Control
		if not strip.has_node("Main"):
			var content := _main.duplicate() as Control
			strip.add_child(content)
			content.show()
			_clear(content.get_node("Groups/List"))
			strip.move_child(content, 2)
			strip.position = _scroll_target(i).position
			strip.size = _scroll_target(i).size
			var seats := _seats.duplicate() as Control
			strip.add_child(seats)
			seats.position = Vector2.ZERO
			seats.show()
			for row_name in ["MeleeScroll", "SeatScroll"]:
				var sc := seats.get_node(row_name) as ScrollContainer
				sc.gui_input.connect(_on_hscroll_wheel.bind(sc))
		strip.set_meta("area_id", area.get("id", 0))
		strip.set_meta("area_name", area.get("name", ""))
		strip.set_meta("location_count", area.get("locations", []).size())
		_set_img(strip, "Background", _area_image(i))
		($Background.get_child(i) as TextureRect).texture = (strip.get_node("Background") as TextureRect).texture
		_bind_main(area, strip.get_node("Main"))
		_bind_seat_rows(area, strip.get_node("Seats"))
		var chars := PackedStringArray()
		for ch in str(area.name):
			chars.append(ch)
		_set_text(strip, "Col/Vertical", "\n".join(chars))
		_set_text(strip, "Col/Latin", str(AREA_LATIN.get(str(area.name), "")).left(6))

		var ev_items := strip.get_node("EventIcons")
		var events: Array = area.get("events", [])
		_bind_area_event_cards(ev_items, events)
		strip.get_node("Score").visible = area.has("score") and area.get("score", 0) != 0
		_set_text(strip, "Score/Num", BaseNumber.display_text(area.get("score", 0)))
		# 地图战区点击：战区本体接收 gui_input；命中后消费等待中的位置选择 / 部署 / 移动
		if not strip.has_meta("area_idx"):
			strip.set_meta("area_idx", i)
			strip.gui_input.connect(_on_strip_gui_input.bind(strip))
		else:
			strip.set_meta("area_idx", i)
		# 当前战区是否可操作，就能沿卷轴外缘亮一圈流动金框（判据与点击入口共用）
		var flow := strip.get_node_or_null("FlowBorder") as Control
		if flow != null:
			flow.visible = pending.get("areas", []).has(area.get("id")) if pending.get("kind") == "location_choice" else actions.get("deploy_areas", []).has(area.get("id")) or actions.get("move_areas", []).has(area.get("id"))
			_bind_flow_border(flow)
		_layout_scroll(strip, float(strip.get_meta("open", 0.0)))
	if previous_count != _strips.get_child_count() and previous_count > 0:
		# 区域由引擎增删时重算端点；不影响游戏规则。
		var selected := _main_area_index
		_main_area_index = -2
		_select_scroll(selected)


func _update_event_fan(delta: float, mouse: Vector2) -> void:
	for strip: Control in _strips.get_children():
		var events := strip.get_node("EventIcons") as Control
		var hovered := false
		if strip.get_index() == _main_area_index and events.visible and events.get_child_count() > 1:
			var bounds := Rect2()
			for card: Control in events.get_children():
				var rect := card.get_global_rect()
				bounds = rect if bounds.size == Vector2.ZERO else bounds.merge(rect)
			hovered = bounds.has_point(mouse)
		var current := float(strip.get_meta("event_fan", 0.0))
		var next := move_toward(current, 1.0 if hovered else 0.0, delta / SCROLL_LEAVE_SECONDS)
		if not is_equal_approx(current, next):
			strip.set_meta("event_fan", next)
			_layout_scroll(strip, float(strip.get_meta("open", 0.0)))


func _layout_scroll_refs(strip: Control) -> Dictionary:
	var refs: Dictionary = _meta_or(strip, "layout_refs", {})
	if not refs.is_empty():
		return refs
	var panel_style := strip.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	strip.add_theme_stylebox_override("panel", panel_style)
	refs = {
		"panel_style": panel_style,
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
	var panel_style := refs["panel_style"] as StyleBoxFlat
	var base_style := _tpl.get_node("Strip").get_theme_stylebox("panel") as StyleBoxFlat
	panel_style.bg_color.a = lerpf(base_style.bg_color.a, 0.0, openness)
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
	var count: int = int(strip.get_meta("location_count", 0))
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
	var event_left := 30.0
	var event_style := (_tpl.get_node("MiniEventCard") as Control).get_theme_stylebox("panel") as StyleBoxFlat
	var shadow_bottom := 0.0
	var shadow_left := 0.0
	if event_style != null:
		shadow_bottom = maxf(0.0, event_style.shadow_size + event_style.shadow_offset.y) * EVENT_STACK_SCALE
		shadow_left = maxf(0.0, event_style.shadow_size - event_style.shadow_offset.x) * EVENT_STACK_SCALE
	# 局势向下延伸时，事件连同阴影从它的右侧开始，避免两类场上牌互相遮挡。
	var situation_rect := _situation.get_global_rect()
	if situation_rect.end.y > strip.global_position.y + event_top:
		event_left = maxf(event_left, situation_rect.end.x - strip.global_position.x + EVENT_STACK_GAP + shadow_left)
	if event_count > 0:
		var event_h: float = (_tpl.get_node("MiniEventCard") as Control).size.y * EVENT_STACK_SCALE
		var seat_top: float = (refs["melee"] as Control).position.y
		var lowest := event_top + float(event_count - 1) * event_step + event_h + shadow_bottom
		if lowest > seat_top - EVENT_STACK_GAP:
			event_top = maxf(0.0, seat_top - EVENT_STACK_GAP - float(event_count - 1) * event_step - event_h - shadow_bottom)
	var fan := float(strip.get_meta("event_fan", 0.0))
	fan = fan * fan * (3.0 - 2.0 * fan)
	var template_width := (_tpl.get_node("MiniEventCard") as Control).size.x
	var fan_scale := minf(EVENT_STACK_SCALE, maxf(1.0, strip.size.x - event_left - EVENT_STACK_GAP - shadow_left - maxf(0.0, event_count - 1) * EVENT_STACK_GAP) / maxf(1.0, event_count * template_width))
	var card_scale := lerpf(EVENT_STACK_SCALE, fan_scale, fan)
	var fan_step := template_width * fan_scale + EVENT_STACK_GAP
	for card: Control in events.get_children():
		var k := int(card.get_meta("event_index", card.get_index()))
		card.z_index = events.get_child_count() - k
		var compact := Vector2(16 + k * 3, 136 + count * compact_step + k * 2)
		var expanded := Vector2(event_left + k * lerpf(26.0, fan_step, fan), event_top + k * event_step * (1.0 - fan))
		card.position = compact.lerp(expanded, openness)
		card.scale = Vector2.ONE * lerpf(1.0, card_scale, openness)
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
	else:
		main_text = "%s 正在行动" % _player_name(curr)
		var area := _player_area(curr)
		sub_text = "顺位 %d" % (EffectManager.get_player_order_index(curr) + 1)
		if area != null:
			sub_text += " · 位于 " + str(area._area_name)
		sub_text += " · 等待对方完成"
	# 等待选位置：在提示条上常驻说明，不重复弹窗打扰
	var pending_loc: Dictionary = _source.read_pending() if _source != null else {}
	if pending_loc.get("kind") == "location_choice":
		main_text = "请点击要选定的战区"
		sub_text = str(pending_loc.get("label", "")) + " · 请选择目标地点"
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
	var view: Dictionary = _source.read_view() if _source != null else {}
	var player: Dictionary = {}
	for candidate in view.get("players", []):
		if candidate.id == view.get("observer", -1):
			player = candidate
	_self.visible = not player.is_empty()
	if player.is_empty():
		# 网络威力由 presenter 在本轮 observer/seq 绑定后统一清空。
		if network_session == null:
			preload("res://scripts/game_scene/battle_io/shared_view_sections.gd").render_self_power(_self.get_node("Stats"), {}, {}, false)
		return
	var servant: Dictionary = player.get("servant", {})
	var sv := _self.get_node("ServantCard") as Control
	sv.visible = not servant.is_empty()
	_bind_card(sv, servant.get("image", "") if servant.get("visible", false) and not servant.get("concealed", true) else servant.get("back_image", ""))
	bind_zoom_for_card(sv, servant)
	_set_text(sv, "Class", str(player.get("servant_class", "")).to_upper())
	_set_text(sv, "HiddenTag/Label", "真名解放" if player.get("servant_released", false) else "真名隐藏")
	var stats := _self.get_node("Stats")
	_set_text(stats, "ScoreRow/Score", BaseNumber.display_text(player.get("score", 0)))
	var rank := 1
	for other in view.get("players", []):
		if other.get("score", 0) > player.get("score", 0):
			rank += 1
	_set_text(stats, "ScoreRow/Rank", "名次 %d" % rank)
	stats.get_node("MagicSigil").set_value(player.get("magic", 0), player.get("magic_limit", 0))
	var power_label := stats.get_node("PowerRow/Power") as Control
	_bind_power_hover(power_label, _local_player_id, true)
	if network_session == null:
		var brk: Dictionary = player.get("power_breakdown", {})
		# 本地选牌仍使用原规则查询；网络只消费 presenter 的私有预览。
		if not _selected_cards.is_empty():
			brk = GetPlayerTotalPower.breakdown(_local_player_id, _selected_cards_power(), _selected_cards.duplicate(), _selected_cards_hidden())
		preload("res://scripts/game_scene/battle_io/shared_view_sections.gd").render_self_power(stats, player, brk, false)
	_bind_spell_box(_self.get_node("Spells"), player)
	var me := _self.get_node("Me")
	me.show()
	_bind_avatar(me.get_node("Avatar"), player.get("avatar", ""))
	_set_text(me, "PlayerName", str(player.get("player_name", "")))
	_set_text(me, "Name", str(player.get("master", {}).get("name", "")))


## ---------- 8 御主卡 ----------

func _bind_master() -> void:
	_master.show()
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
	_hand.show()
	var pl := _pl(_local_player_id)

	var zone_entries := _zone_hand_entries(pl)
	# 出牌区与技能栏是同一规则对象的两个展示位，不复制规则对象。
	# 只保留确实从技能栏打出的卡位，普通手牌仍离开手牌栏。
	var zone_positions: Dictionary = {}
	for slot: Control in _hand.get_children():
		var card = _meta_or(slot, "card", null)
		if slot.get_meta("held_group", "") == "zone" and slot.has_meta("rest_position"):
			zone_positions[card] = (slot.get_meta("rest_position") as Vector2).x
		if card is BaseSkill and slot.get_meta("held_group", "") == "zone" and (pl.get("played_cards", []) as Array).has(card) \
				and not zone_entries.any(func(entry): return entry.card == card):
			zone_entries.append(slot.get_meta("held_entry"))
	# 子节点顺序会为重叠绘制反转，不能再拿它决定布局顺序。
	# 复用已有卡位的目标顺序，避免刷新后已出牌互换，也避免挤走未出牌。
	zone_entries.sort_custom(func(a, b): return zone_positions.get(a.card, INF) < zone_positions.get(b.card, INF))
	var live_cards: Array = []
	for card in pl.get("hand_cards", []):
		if card is BaseHandCard:
			live_cards.append(card)
	for entry in zone_entries:
		if not live_cards.has(entry.card):
			live_cards.append(entry.card)
	for slot in _hand.get_children():
		if not live_cards.has(_meta_or(slot, "card", null)):
			_hand.remove_child(slot)
			slot.queue_free()
	_selected_cards = _selected_cards.filter(func(card): return live_cards.has(card) and not (pl.get("played_cards", []) as Array).has(card))
	var right_entries: Array = []
	for card in pl.get("hand_cards", []):
		if card is BaseHandCard:
			right_entries.append({"card": card, "kind": "手牌", "count": 1})
	var portrait_rect := _master.get_rect()
	var servant_entries: Array = []
	var master_entries: Array = []
	for entry in zone_entries:
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
		var visual := _held_visual_data(card)
		var key: Array = [entry.kind, visual.name, visual.image, visual.back_image, visual.concealed, visual.cost, visual.power]
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
		slot.set_meta("held_entry", entry)
		# 未公开与明暗朝向分离：技能真名未解放时，明置也不向他人公开。
		# 手牌本来只有自己可见，不标未公开遮罩；由调用方声明最终可见性。
		var unpublished: bool
		if network_session != null:
			unpublished = group == "zone" and _network_presenter.card_unpublished(entry.card)
		else:
			unpublished = group == "zone" and (entry.card._is_concealed \
				or (entry.card is BaseSkill and not ReleaseTrueName.is_released(_local_player_id)))
		_bind_hand_card(slot, entry.card, entry.kind, entry.count, true, unpublished)
		var badge := slot.get_node("StackCount") as Label
		badge.visible = entry.stack_count > 1
		badge.text = "x%d" % entry.stack_count if badge.visible else ""

## 卡面数据适配不参与动作合法性。
func _held_visual_data(card) -> Dictionary:
	if card is Dictionary:
		return card
	return {"name": card._name, "image": card._card_img, "back_image": card._card_back_img,
		"concealed": card._is_concealed, "cost": _num(card._cost) if card is BaseHandCard else 0,
		"power": _num(card._power) if card is BaseHandCard else 0}

## 组合快照与主动效果共同决定提示；独立 cards 不代表可加入当前组。
func _held_playable_signature(actions = null, group = null) -> String:
	if actions == null:
		actions = _source.read_actions() if _source != null else {}
	if group == null:
		group = _read_group_preview()
	return var_to_str([group, actions.get("effects", [])])

func _read_group_preview() -> Dictionary:
	return _source.read_group_preview(_selected_cards, _selected_cards_hidden()) if _source != null else {}

static func _group_preview_ready(group: Dictionary) -> bool:
	return not group.get("waiting", false) and not group.get("submitted", false) and bool(group.get("preview", {}).get("ok", false))

func _held_action_card_id(card) -> int:
	if card is Dictionary:
		return int(card.get("id", 0))
	return _held_action_ids.id_for(card) if card is BaseCard and _held_action_ids != null else 0

## 授权 view 已包含牌及关联 BUFF 的效果 ID，不在 UI 重建规则关系。
func _held_action_card_view(card) -> Dictionary:
	if card is Dictionary:
		return card
	var id := _held_action_card_id(card)
	if id <= 0 or _source == null:
		return {}
	var view: Dictionary = _source.read_view()
	for player in view.get("players", []):
		for entry in player.get("held_cards", []):
			if int(entry.card.get("id", 0)) == id:
				return entry.card
		for played in player.get("played_cards", []):
			if int(played.get("id", 0)) == id:
				return played
	return {}


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
	# 同次更新只读一份 actions；不跨刷新缓存动作合法性。
	var actions: Dictionary = _source.read_actions() if _source != null else {}
	var group := _read_group_preview()
	var sig := _held_playable_signature(actions, group)
	if str(_hand.get_meta("playable_sig", "")) != sig:
		_hand.set_meta("playable_sig", sig)
		for slot: Control in slots:
			if slot.has_meta("card"):
				var effects := _manual_effects_of(_meta_or(slot, "card", null), actions)
				slot.set_meta("manual_effects", effects)
				slot.set_meta("held_playable", _held_card_playable(_meta_or(slot, "card", null), actions, group))
	for slot: Control in slots:
		if not slot.has_meta("rest_position"):
			continue
		var card = slot.get_meta("card")
		var input_available := _held_input_available()
		var playable: bool = bool(slot.get_meta("held_playable", false)) and input_available
		var manual_available := input_available and not (slot.get_meta("manual_effects", []) as Array).is_empty()
		_sync_held_affordance_frames(slot, playable, manual_available, group.get("cards", []).has(_held_action_card_id(card)))
		var over := hovered == slot or (hovered != null and slot.is_ancestor_of(hovered))
		_update_held_effect_button(slot, over, delta)
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
## 技能区牌魔力不足时盖门槛遮罩；不可用则压暗，不依赖当前行动者。
func _held_slot(card, template: String) -> Control:
	for slot: Control in _hand.get_children():
		var existing = _meta_or(slot, "card", null)
		if existing == card or (card is Dictionary and existing is Dictionary and existing.get("id") == card.get("id")):
			slot.set_meta("card", card)
			return slot
	var slot := _spawn(template, _hand)
	slot.set_meta("card", card)
	for child in slot.find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.gui_input.connect(_on_held_card_input.bind(slot))
	_bind_effect_button(slot)
	return slot

func _bind_effect_button(slot: Control) -> void:
	if slot.has_node("EffectButton"):
		return
	var button := _spawn("EffectButton", slot) as Button
	button.name = "EffectButton"
	button.hide()
	button.pressed.connect(_on_held_effect_pressed.bind(slot))
	(button.get_node("Effects") as PopupMenu).id_pressed.connect(_on_held_effect_choice.bind(slot))


func _on_held_card_input(event: InputEvent, slot: Control) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if not _held_input_available() or not _battle_command_input_available("set_concealed"): return
		var held = _meta_or(slot, "card", null)
		var card_id: int = int(held.get("id", -1)) if held is Dictionary else (_held_action_ids.id_for(held) if held is BaseCard and _held_action_ids != null else -1)
		var concealed: bool = bool(held.get("concealed", false)) if held is Dictionary else (held._is_concealed if held is BaseCard else false)
		for entry in _source.read_actions().get("flip_cards", []):
			if entry.get("id") == card_id and entry.get("modes", []).has(not concealed):
				_submit_battle_command("set_concealed", {"card": card_id, "concealed": not concealed})
				break
		slot.accept_event()
		return
	if network_session != null:
		_network_presenter.card_input(event, slot, _battle_commands.submit if _battle_command_input_available("set_concealed") else Callable())
		return
	if not event is InputEventMouseButton or not event.pressed or not _held_input_available():
		return
	var card = _meta_or(slot, "card", null)
	if not card is BaseCard:
		return
	var pl := _pl(_local_player_id)
	# 已出牌即使仍有持有区展示副本，也不能从该副本手动翻面。
	if event.button_index == MOUSE_BUTTON_RIGHT and (pl.get("played_cards", []) as Array).has(card):
		return
	if card is BaseSkill and slot.get_meta("held_group", "") == "zone" and (pl.get("played_cards", []) as Array).has(card):
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_held_effect_pressed(slot)
			slot.accept_event()
		return
	if not (pl.get("hand_cards", []) as Array).has(card) and not _zone_hand_entries(pl).any(func(entry): return entry.card == card):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if _selected_cards.has(card):
			_selected_cards.erase(card)

		else:
			_selected_cards.append(card)

	else:
		return
	slot.accept_event()
	refresh_all_ui()


## 悬浮按钮只改变自身位置与透明度，不更改卡位布局。
func _update_held_effect_button(slot: Control, over: bool, delta: float) -> void:
	var button := slot.get_node("EffectButton") as Button
	var popup := button.get_node("Effects") as PopupMenu
	var available := _held_input_available() and not (slot.get_meta("manual_effects", []) as Array).is_empty()
	# 失去候选/生命周期可用性时没有残留的可见发动入口；离开悬浮仍保留滑出动画。
	if not available:
		button.set_meta("slide", 0.0)
		button.hide()
		button.disabled = true
		popup.hide()
		return
	var progress := move_toward(float(button.get_meta("slide", 0.0)), 1.0 if available and (over or popup.visible) else 0.0, delta * HELD_HOVER_SPEED)
	button.set_meta("slide", progress)
	button.disabled = not available
	button.visible = progress > 0.0
	button.modulate.a = progress
	button.size = Vector2(slot.size.x, button.get_combined_minimum_size().y)
	var gap := float(button.get_meta("card_gap"))
	button.position = Vector2(0, -(button.size.y + gap) * progress)
	# 透明命中区接通按钮与卡牌之间的留白，跨过间隙不收回按钮。
	var bridge := button.get_node("HoverBridge") as Control
	bridge.position = Vector2(0, button.size.y)
	bridge.size = Vector2(button.size.x, gap)


func _on_held_effect_pressed(slot: Control) -> void:
	if not _held_input_available():
		return
	var effects := _manual_effects_of(_meta_or(slot, "card_object", _meta_or(slot, "card", null)) if network_session == null else _meta_or(slot, "card", null))
	if effects.is_empty():
		return
	if effects.size() == 1:
		_request_held_effect(effects[0])
		return
	var button := slot.get_node("EffectButton") as Button
	var popup := button.get_node("Effects") as PopupMenu
	popup.clear()
	button.set_meta("choices", effects)
	for i in range(effects.size()):
		popup.add_item(str(effects[i].label) if effects[i] is Dictionary else _shown(effects[i]), i)
	popup.position = Vector2i(button.global_position + Vector2(0, button.size.y))
	popup.popup()


func _on_held_effect_choice(index: int, slot: Control) -> void:
	if not _held_input_available():
		return
	var effects: Array = slot.get_node("EffectButton").get_meta("choices", [])
	if index >= 0 and index < effects.size():
		_request_held_effect(effects[index])


func _request_held_effect(effect) -> void:
	if not _battle_command_input_available() or not _held_input_available():
		return
	if _source_is_local:
		_source.invalidate()
	var id = effect.get("id") if effect is Dictionary else (_held_action_ids.id_for(effect) if effect is BaseEffect and _held_action_ids != null else null)
	if not id is int or id <= 0 or not _source.read_pending().is_empty():
		return
	if _activation_effect_ids().has(id):
		_submit_battle_command("activate", {"effect": id})

## 合法性只来自 actions，身份只来自本人实际 view 的牌面效果 ID。
func _activation_effect_ids(spells_only: bool = false) -> Array:
	var declared: Array = []
	for player in _source.read_view().get("players", []):
		if player.get("id") != _battle_command_observer:
			continue
		var cards: Array = player.get("command_spells", []).duplicate()
		if not spells_only:
			for entry in player.get("held_cards", []):
				cards.append(entry.card)
			cards.append_array(player.get("played_cards", []))
			for entry in player.get("zone_hand_entries", []):
				cards.append(entry.card)
		for card in cards:
			for id in card.get("effects", []):
				if id is int and id > 0 and not declared.has(id):
					declared.append(id)
	var allowed: Array = []
	for effect in _source.read_actions().get("effects", []):
		var id = effect.get("id")
		if id is int and declared.has(id) and not allowed.has(id):
			allowed.append(id)
	return allowed


## 卡面声明的效果 ID 与只读 actions 相交；对象解析仅兼容旧本地命令输入。
func _manual_effects_of(card, actions = null) -> Array:
	var result: Array = []
	if actions == null:
		actions = _source.read_actions() if _source != null else {}
	var card_view := _held_action_card_view(card)
	var seen: Array = []
	for effect in actions.get("effects", []):
		var id: int = int(effect.get("id", 0))
		if id <= 0 or seen.has(id) or not card_view.get("effects", []).has(id):
			continue
		seen.append(id)
		if card is Dictionary:
			result.append(effect.duplicate(true))
		elif _held_action_ids != null:
			var object = _held_action_ids.object_for(id)
			if object is BaseEffect:
				result.append(object)
	return result


## 已选牌看整组可提交；未选牌只看当前组 preview.candidates，绝不回退独立候选。
func _held_card_playable(card, _actions = null, group = null) -> bool:
	if group == null:
		group = _read_group_preview()
	if not _group_preview_ready(group):
		return false
	var id := _held_action_card_id(card)
	if id <= 0:
		return false
	var preview: Dictionary = group.get("preview", {})
	if group.get("cards", []).has(id):
		return bool(preview.get("can_submit", false))
	for candidate in preview.get("candidates", []):
		if int(candidate.get("id", 0)) == id:
			return not candidate.get("modes", []).is_empty()
	return false


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
	_sync_card_modification_badge(node, card, mine)
	if network_session != null:
		_network_presenter.bind_hand_card(node, card, show_conceal_mark)
		return
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
	var mark: bool = awakened and show_conceal_mark
	_bind_hand_face(frame, face_img, mark)
	if kind == "升华技":
		_set_variation(frame, "CardUpgrade")
	var actions: Dictionary = _source.read_actions() if _source != null else {}
	var playable := awakened and _held_card_playable(card, actions)
	var manual_effects: Array = _manual_effects_of(card, actions) if awakened and mine else []
	var pl := _pl(_local_player_id)
	var need := _num(GameData.skill_zone_magic_limit)
	var locked := awakened and mine and not playable and not (pl.get("hand_cards", []) as Array).has(card) \
		and _num(pl.get("magic")) < need \
		and not bool(pl.get("ignore_skill_zone_magic_limit", false)) and not bool(pl.get("is_magic_immune", false))
	_bind_hand_availability(node, manual_effects, playable, mine and awakened, locked)
	# 牌面不附说明文字：牌名、属性与底部底条都改由放大卡图与右键说明承担

	# 放大与右键说明绑在卡位自身：Frame 及其子节点都被设为不接收鼠标，绑在它们上面收不到事件。
	# 手牌与技能区的右键已被明置/暗置占用，说明改由放大卡图上右键触发（right_action 声明式传入）。
	if awakened:
		bind_zoom_for_card(node, card, "", "none")
	else:
		_disable_card_zoom(node)

## 两种来源共用徽标与只读模态；网络只能消费当前完整快照的本人记录。
var _modification_slots: Array[WeakRef] = []

func _strict_modification_records(card: Dictionary) -> bool:
	if typeof(card.get("visible")) != TYPE_BOOL or not card.visible \
			or typeof(card.get("concealed")) != TYPE_BOOL or card.concealed \
			or typeof(card.get("modification_history")) != TYPE_ARRAY:
		return false
	for record in card.modification_history:
		if typeof(record) != TYPE_DICTIONARY or record.size() != 2 or not record.has_all(["type", "detail"]) \
				or typeof(record.type) != TYPE_STRING or typeof(record.detail) != TYPE_STRING:
			return false
	return true

## 只查当前observer自己的展示集合；controller/visible不能代替历史授权。
func _network_modification_card(card, channel: String) -> Dictionary:
	if _source_is_local or network_session == null or _source == null or not card is Dictionary \
			or typeof(card.get("id")) != TYPE_INT or not _strict_modification_records(card):
		return {}
	var view: Dictionary = _source.read_view()
	if typeof(view.get("observer")) != TYPE_INT or view.observer < 0 \
			or view.observer != _local_player_id or typeof(view.get("seq")) != TYPE_INT:
		return {}
	var channels: Array = [channel] if not channel.is_empty() else ["held_cards", "hand_cards", "master_skills", "servant_skills", "zone_hand_entries"]
	for player in view.get("players", []):
		if typeof(player.get("id")) != TYPE_INT or player.id != view.observer:
			continue
		for key in channels:
			for entry in player.get(key, []):
				var current = entry.get("card", {}) if key in ["held_cards", "zone_hand_entries"] else entry
				if current is Dictionary and typeof(current.get("id")) == TYPE_INT and current.id == card.id:
					return current if _strict_modification_records(current) else {}
	return {}

func _modification_records(card, channel: String = "") -> Array:
	if card is Dictionary:
		return _network_modification_card(card, channel).get("modification_history", [])
	return card.get_modification_details() if _local_modification_card_allowed(card) else []

func _same_modification_target(a, b) -> bool:
	if a is Dictionary and b is Dictionary:
		return typeof(a.get("id")) == TYPE_INT and typeof(b.get("id")) == TYPE_INT and a.id == b.id
	if a is Dictionary or b is Dictionary:
		return false
	return a == b

## 本地沿用真实对象权限；网络绝不落入本机对象分支。
func _local_modification_card_allowed(card) -> bool:
	if network_session != null or not _source_is_local or not card is BaseHandCard:
		return false
	if card._is_concealed or (card is BaseSkill and not card._is_awakened):
		return false
	# 查询不创建玩家；按当前持有集合验证，离区/换观察者即失效。
	var pl: Dictionary = GameData.player_data_library.get(_local_player_id, {})
	if pl.is_empty():
		return false
	if pl.get("hand_cards", []).has(card) or pl.get("played_cards", []).has(card):
		return true
	return _zone_hand_entries(pl).any(func(entry): return entry.card == card)

func _sync_card_modification_badge(slot: Control, card, authorized: bool, channel: String = "") -> void:
	var badge := slot.get_node_or_null("CardModificationBadge") as Button
	if badge == null:
		return
	if not slot.has_meta("modification_tracked"):
		slot.set_meta("modification_tracked", true)
		_modification_slots.append(weakref(slot))
	var records := _modification_records(card, channel) if authorized else []
	badge.mouse_filter = Control.MOUSE_FILTER_STOP
	badge.visible = not records.is_empty()
	badge.set_meta("mod_target_card", card if badge.visible else null)
	badge.set_meta("mod_authorized", authorized)
	badge.set_meta("mod_channel", channel)
	var view: Dictionary = _source.read_view() if _source != null else {}
	badge.set_meta("mod_observer", view.get("observer", -1) if card is Dictionary else _local_player_id)
	badge.set_meta("mod_seq", view.get("seq", -1) if card is Dictionary else -1)
	if not badge.pressed.is_connected(_on_card_modification_pressed.bind(slot)):
		badge.pressed.connect(_on_card_modification_pressed.bind(slot))
	var reader := get_node("CardModificationHistory") as Control
	var source: WeakRef = _meta_or(reader, "history_source", null)
	if reader.visible and source != null and source.get_ref() == slot:
		if not badge.visible or not _same_modification_target(_meta_or(reader, "history_card", null), card) \
				or reader.get_meta("history_observer", -1) != badge.get_meta("mod_observer", -1):
			_close_card_modification_history()
		else:
			reader.set_meta("history_card", card)
			reader.set_meta("history_seq", badge.get_meta("mod_seq", -1))
			_render_card_modification_history(card, channel)

func _on_card_modification_pressed(slot: Control) -> void:
	var badge := slot.get_node("CardModificationBadge") as Button
	var card = _meta_or(badge, "mod_target_card", null)
	var channel: String = badge.get_meta("mod_channel", "")
	var observer: int = _source.read_view().get("observer", -1) if card is Dictionary and _source != null else _local_player_id
	if not badge.is_visible_in_tree() or not bool(badge.get_meta("mod_authorized", false)) \
			or badge.get_meta("mod_observer", -1) != observer or _modification_records(card, channel).is_empty():
		_close_card_modification_history()
		return
	var reader := get_node("CardModificationHistory") as Control
	reader.set_meta("history_source", weakref(slot))
	reader.set_meta("history_card", card)
	reader.set_meta("history_observer", observer)
	reader.set_meta("history_seq", badge.get_meta("mod_seq", -1))
	_render_card_modification_history(card, channel)
	(reader.get_node("Panel/Entries") as RichTextLabel).scroll_to_line(0)
	reader.show()
	_raise_modal(reader)

func _render_card_modification_history(card, channel: String = "") -> void:
	var lines: PackedStringArray = []
	for record in _modification_records(card, channel):
		# 真实记录只有type/detail；不解释BBCode，不补时间、来源或前后值。
		if record is Dictionary and record.get("detail") is String:
			lines.append("• " + record.detail)
	var title: String = _network_modification_card(card, channel).get("name", "") if card is Dictionary else card.get_shown_name()
	_set_text($CardModificationHistory/Panel, "Title", "【%s】修改记录" % title)
	var entries := $CardModificationHistory/Panel/Entries as RichTextLabel
	entries.bbcode_enabled = false
	var rendered := "\n\n".join(lines)
	if entries.text != rendered:
		entries.text = rendered

func _refresh_card_modification_history() -> void:
	# 即使面板未打开也每帧撤销旧徽标；只保留WeakRef，不持有已离树的卡位。
	for index in range(_modification_slots.size() - 1, -1, -1):
		var tracked = _modification_slots[index].get_ref()
		if not is_instance_valid(tracked) or not tracked.is_inside_tree() or tracked.is_queued_for_deletion():
			_modification_slots.remove_at(index)
			continue
		var target_badge: Button = tracked.get_node("CardModificationBadge")
		var target = _meta_or(target_badge, "mod_target_card", null)
		if target == null:
			continue
		var channel: String = target_badge.get_meta("mod_channel", "")
		var observer: int = _source.read_view().get("observer", -1) if target is Dictionary and _source != null else _local_player_id
		if target_badge.get_meta("mod_observer", -1) != observer or not tracked.is_visible_in_tree():
			_sync_card_modification_badge(tracked, null, false, channel)
		else:
			var current = _network_modification_card(target, channel) if target is Dictionary else target
			_sync_card_modification_badge(tracked, current, bool(target_badge.get_meta("mod_authorized", false)), channel)
	var reader := get_node("CardModificationHistory") as Control
	if not reader.visible:
		return
	var source: WeakRef = _meta_or(reader, "history_source", null)
	var slot = source.get_ref() if source != null else null
	if not is_instance_valid(slot) or not slot.is_inside_tree() or slot.is_queued_for_deletion() or not slot.is_visible_in_tree():
		_close_card_modification_history()
		return
	var card = _meta_or(reader, "history_card", null)
	var badge := slot.get_node("CardModificationBadge") as Button
	var channel: String = badge.get_meta("mod_channel", "")
	if not badge.visible or not bool(badge.get_meta("mod_authorized", false)) \
			or not _same_modification_target(_meta_or(badge, "mod_target_card", null), card) or _modification_records(card, channel).is_empty():
		_close_card_modification_history()
		return
	_render_card_modification_history(card, channel)

func _close_card_modification_history() -> void:
	var reader := get_node("CardModificationHistory") as Control
	reader.hide()
	reader.remove_meta("history_source")
	reader.remove_meta("history_card")
	reader.remove_meta("history_observer")
	reader.remove_meta("history_seq")
	_set_text(reader, "Panel/Title", "修改记录")
	(reader.get_node("Panel/Entries") as RichTextLabel).text = ""

func _card_modification_history_input(event: InputEvent) -> bool:
	if not $CardModificationHistory.visible:
		return false
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_card_modification_history()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] \
			and not ($CardModificationHistory/Panel as Control).get_global_rect().has_point(event.position):
		_close_card_modification_history()
		get_viewport().set_input_as_handled()
	# 面板内交给预置控件；全局地图/抽屉悬浮逻辑不再处理本事件。
	return true

## 两种意图独立：选牌时金框原位变白；点选发动时紫框原位变白。
func _sync_held_affordance_frames(node: Control, playable: bool, manual_available: bool, selected: bool) -> void:
	# 金/白共用同一个节点，保留原位与呼吸相位；发动选择只控制外侧紫/白框。
	var play_frame := node.get_node("Breath") as Panel
	var play_style := _meta_or(play_frame, "selected_outline" if selected else "available_outline", null) as StyleBox
	if play_style != null and play_frame.get_theme_stylebox("panel") != play_style:
		play_frame.add_theme_stylebox_override("panel", play_style)
	node.get_node("Selected").hide()
	var effect_selected := _held_effect_intent_selected(node)
	var effect_frame := node.get_node("EffectBreath") as Panel
	var effect_style := _meta_or(effect_frame, "selected_outline" if effect_selected else "available_outline", null) as StyleBox
	if effect_style != null and effect_frame.get_theme_stylebox("panel") != effect_style:
		effect_frame.add_theme_stylebox_override("panel", effect_style)
	for entry in [[play_frame, playable or selected], [effect_frame, manual_available or effect_selected]]:
		var outline: Control = entry[0]
		outline.visible = entry[1]
		if outline.visible and not _breathing.has(outline):
			_breathe(outline)

## 只读既有菜单/命令/权威等待；不把hover、选牌或旧卡位metadata当发动选择。
func _held_effect_intent_selected(node: Control) -> bool:
	if _source == null:
		return false
	var card = _meta_or(node, "card", null)
	var declared: Array = _held_action_card_view(card).get("effects", [])
	if declared.is_empty():
		return false
	var pending_id = _source.read_pending().get("effect")
	if pending_id is int and declared.has(pending_id):
		return true
	var requested_id = _end_command_attempt.get("args", {}).get("effect")
	if requested_id is int and declared.has(requested_id):
		return true
	var button := node.get_node_or_null("EffectButton") as Button
	if button == null or not (button.get_node("Effects") as PopupMenu).visible:
		return false
	var choices: Array = button.get_meta("choices", [])
	for effect in _manual_effects_of(card):
		var id = effect.get("id") if effect is Dictionary else (_held_action_ids.id_for(effect) if effect is BaseEffect and _held_action_ids != null else null)
		if not id is int or not declared.has(id):
			continue
		for choice in choices:
			var choice_id = choice.get("id") if choice is Dictionary else (_held_action_ids.id_for(choice) if choice is BaseEffect and _held_action_ids != null else null)
			if choice_id == id:
				return true
	return false

func _bind_hand_availability(node: Control, effects: Array, playable: bool, dim_unavailable: bool, locked: bool) -> void:
	node.set_meta("manual_effects", effects)
	node.set_meta("held_playable", playable)
	var actionable := playable or not effects.is_empty()
	var frame: Control = node.get_node("Frame")
	frame.modulate = Color(0.55, 0.55, 0.55) if dim_unavailable and not actionable else Color.WHITE
	var input_available := _held_input_available()
	var selected: bool = _read_group_preview().get("cards", []).has(_held_action_card_id(node.get_meta("card")))
	_sync_held_affordance_frames(node, playable and input_available, not effects.is_empty() and input_available, selected)
	node.get_node("Lock").visible = locked

func _bind_hand_face(frame: Control, face_img: String, mark: bool) -> void:
	var prev_face: String = str(frame.get_meta("face_img", ""))
	var prev_mark: bool = bool(frame.get_meta("face_mark", false))
	frame.set_meta("face_img", face_img)
	frame.set_meta("face_mark", mark)
	if prev_face != "" and (prev_face != face_img or prev_mark != mark):
		_play_card_flip(frame, _apply_hand_face.bind(frame.get_instance_id(), face_img, mark))
	elif not bool(frame.get_meta("card_flipping", false)):
		_bind_card(frame, face_img)
		_sync_overlay(frame, mark, "ConcealOverlay", CONCEAL_COLOR, CONCEAL_ICON)

func _bind_ops() -> void:
	_bind_mana_cost_preview()
	(_ops.get_node("PlayButton") as Button).disabled = not _can_confirm_held_cards()
	_update_end_command_button()
	var list := _ops.get_node("BuffBox/List")
	var buffs: Array = _projected_buffs(_local_player_id)
	(list.get_node("None") as Control).visible = _fill_buff_rows(list, buffs, ["None"]) == 0
	# 牌堆由 _bind_situation_and_piles 统一消费 source 投影。


## 说明常驻、图可选的展示位绑定（buff 这类对象常常没有图，但点开要看得到效果说明）：
## 有图且数据声明了放大分类时走 bind_zoom_for_card 的完整口径（悬浮放大 + 右键说明）；
## 没有可放大的图时退成"只给说明"，说明文本与放大预览共用同一份 token 说明，不另写文案。
func _bind_entry_info(node: Control, obj, img_field: String = "") -> void:
	if node == null or obj == null:
		return
	bind_zoom_for_card(node, obj, img_field)
	if obj is Dictionary:
		# 只允许传输视图明确授权、正面且有说明的条目退回说明模式。
		if obj.get("visible", false) and not obj.get("concealed", true) and bool(node.get_meta("zoom_disabled", true)):
			node.set_meta("zoom_disabled", false)
			node.set_meta("zoom_img", "")
			node.set_meta("zoom_obj", obj)
			node.set_meta("zoom_title", obj.get("name", ""))
			node.set_meta("zoom_desc", obj.get("description", ""))
			node.set_meta("zoom_right_action", "desc")
			node.mouse_filter = Control.MOUSE_FILTER_STOP
			if not node.has_meta("zoom_bound"):
				node.set_meta("zoom_bound", true)
				node.gui_input.connect(_on_zoom_target_gui_input.bind(node))
		_bind_desc_click(node)
		return
	if bool(node.get_meta("zoom_disabled", true)):
		node.set_meta("zoom_disabled", false)
		node.set_meta("zoom_img", "")
		node.set_meta("zoom_obj", obj)
		node.set_meta("zoom_title", _object_shown_name(obj))
		node.set_meta("zoom_desc", CardDescText.token_desc(obj))
		node.set_meta("zoom_right_action", "desc")
		node.mouse_filter = Control.MOUSE_FILTER_STOP
		if not node.has_meta("zoom_bound"):
			node.set_meta("zoom_bound", true)
			node.gui_input.connect(_on_zoom_target_gui_input.bind(node))
	_bind_desc_click(node)


## 左键点击展开说明、再点同一个源收起：没有放大图的展示位（buff 条等）用右键不直观
func _bind_desc_click(node: Control) -> void:
	if node == null or node.has_meta("desc_click_bound"):
		return
	node.set_meta("desc_click_bound", true)
	node.gui_input.connect(func(ev: InputEvent):
		if not (ev is InputEventMouseButton) or not ev.pressed or ev.button_index != MOUSE_BUTTON_LEFT:
			return
		if _show_desc_for(node):
			# 手动点开的说明不吃保活倒计时：鼠标不动时它就该一直留着
			_zoom_hide_remaining = -1.0
			get_viewport().set_input_as_handled()
	)


## 铺状态行：本地资源栏与对手抽屉共用同一个 BuffRow 模板与同一套绑定口径。
## 返回铺出的条数，调用方自己决定"没有状态"时的表现（本地显示占位，抽屉整列收起）；
## keep 里列出的常驻子节点（如本地占位）保留不动
func _fill_buff_rows(row: Node, buffs: Array, keep: Array = []) -> int:
	if row == null:
		return 0
	_clear(row, keep)
	var count := 0
	for b in buffs:
		if not b is Dictionary:
			continue
		var card: Dictionary = b.get("card", {})
		if not card.get("visible", false) or card.get("concealed", true):
			continue
		var entry := _spawn("BuffRow", row)
		var active: bool = bool(b.get("active", false))
		_set_variation(entry, "BuffActive" if active else "BuffInactive")
		var avatar: Control = entry.get_node("H/Avatar")
		var image: String = card.get("image", "")
		avatar.visible = not image.is_empty() and LoadHelper.texture_exists(image)
		if avatar.visible:
			_bind_avatar(avatar, image)
		_bind_entry_info(entry, card)
		_set_text(entry, "H/Name", card.get("name", ""))
		entry.get_node("H/Inactive").visible = not active
		count += 1
	return count


## 结束阶段：直接走引擎公开入口；被拒时把引擎给本地玩家的提示原样弹出
func _held_hidden(cards: Array) -> Array:
	return cards.map(func(card): return bool(card._is_concealed))


## 当前待选择牌的明暗快照，只用于只读威力预览。
func _selected_cards_hidden() -> Array:
	return _selected_cards.map(func(card): return bool(card.get("_is_concealed")))


## 当前待选择牌计入威力的增量，逐张复用真实出牌的明暗判定。
func _selected_cards_power() -> int:
	var counts := CardCountsPower.new()
	var total := 0
	var hidden := _selected_cards_hidden()
	for i in range(_selected_cards.size()):
		var card = _selected_cards[i]
		if not (card is BaseHandCard):
			continue
		if counts.counts_when_played(card, bool(hidden[i]), _local_player_id):
			total += _num(card.get("_power"))
	return total


func _held_input_available() -> bool:
	if $CardModificationHistory.visible:
		return false
	if not _end_command_attempt.is_empty():
		return false
	if network_session != null:
		return _network_presenter.input_available()
	return not _submitting and not $LogBrowser.visible and not $CardBrowser.visible and not $EventDiscardMenu.visible \
		and not EffectManager.is_waiting_for_choice() and not EffectManager.is_waiting_for_card_selection()


func _can_confirm_held_cards() -> bool:
	var group := _read_group_preview()
	return _held_input_available() and _group_preview_ready(group) and bool(group.get("preview", {}).get("can_submit", false))


func _confirm_held_cards() -> void:
	if not _can_confirm_held_cards():
		return
	var group: Dictionary = _read_group_preview()
	_submit_battle_command("play_group", {"cards": group.get("cards", []).duplicate(), "hidden": group.get("hidden", []).duplicate()})

func _complete_held_group(attempt: Dictionary) -> void:
	var ids: Array = attempt.get("args", {}).get("cards", [])
	if not _source_is_local:
		# 暂选只是 UI 状态；只在权威成功后移除本次提交的牌，不调用旧 confirm。
		for id in ids: _network_presenter.selection.remove(id)
		return
	var cards: Array = []
	for id in ids:
		var card = _held_action_ids.object_for(id)
		if card != null:
			cards.append(card)
			_selected_cards.erase(card)
	if not cards.is_empty():
		# 打出与阶段能力发动是两次操作；只提示此刻引擎确认仍可发动的牌。
		for card in cards:
			if not _manual_effects_of(card).is_empty():
				EffectManager.push_message("【%s】可发动能力，点击技能牌发动能力" % _shown(card), _local_player_id)
		# 提交后节点会复用；旧坐标属于打出的牌数，剩余牌立即采用新扇形布局。
		for slot: Control in _hand.get_children():
			if slot.get_meta("held_group", "") == "hand":
				slot.position = slot.get_meta("rest_position")
				slot.rotation = slot.get_meta("rest_rotation")


func _toggle_scoreboard() -> void:
	_board.visible = not _board.visible
	_bind_board()


func _bind_board() -> void:
	_update_board_return_controls()
	if not _board.visible:
		return
	var view: Dictionary = _source.read_view() if _source != null else {}
	var players: Array = view.get("players", []).duplicate()
	players.sort_custom(func(a, b): return a.get("score", 0) > b.get("score", 0))
	var rows := _board.get_node("Rows") as Control
	_sync_items(rows, "BoardRow", players.size())
	var row_h := 0.0
	for i in players.size():
		var player: Dictionary = players[i]
		var row := rows.get_child(i) as Control
		row_h = row.custom_minimum_size.y
		var variation := "Mana" if player.id == view.get("observer", -1) else "Text"
		_set_text(row, "Rank", str(i + 1))
		_set_variation(row.get_node("Rank"), variation)
		_bind_avatar(row.get_node("Avatar"), player.get("avatar", ""))
		_set_text(row, "Name", player.get("master", {}).get("name", player.get("player_name", "")))
		_set_variation(row.get_node("Name"), variation)
		_set_text(row, "Class", player.get("servant_class", ""))
		_set_text(row, "Score", BaseNumber.display_text(player.get("score", 0)))
	_board.size.y = 52.0 + players.size() * row_h

# 等待输入状态与既有 AI 推进节拍（不属于榜单投影）。
var _card_select_request: Dictionary = {}
var _card_select_hidden: Dictionary = {}
var _card_select_submit: Callable = Callable()
var _card_select_effect: BaseEffect = null
## card_choice 使用 source 的稳定声明；不把 raw pending 对象带入本地展示或回执。
var _card_choice_prompt: Dictionary = {}
var _card_choice_generation: int = 0
var _card_choice_command_epoch: int = -1
var _card_select_picked: Array = []
var _card_select_cards: Array = []
var _player_select_effect: BaseEffect = null
var _player_choice_prompt: Dictionary = {}
var _player_choice_generation: int = 0
var _player_choice_command_epoch: int = -1
var _player_select_panel_ready: bool = false
var _pending_tactical_action: Dictionary = {}
var _pending_confirm_desc: String = ""
var _confirm_alert_mode: bool = false
var _should_end_after_confirm: bool = false

const AI_STEP_INTERVAL := 0.7

func _process_waiting_inputs(_delta: float) -> void:
	if _is_debug_console_blocking_progress() or _is_paused():
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
var _active_choice_prompt: Dictionary = {}
var _active_choice_generation: int = 0
var _active_choice_command_epoch: int = -1

func _check_waiting_effects() -> void:
	# raw 只用于显式 AI 的身份适配；展示和真人答复只读 source 声明。
	var raw: BaseEffect = EffectManager.get_pending_active_effect()
	if raw != null and _seat_controller.is_ai(raw._trigger_player_id):
		await _driver.answer_effect_async(raw,get_tree())
		if _source != null: _source.invalidate()
	var prompt: Dictionary = _source.read_pending() if _source != null else {}
	if prompt.get("kind") != "active_choice":
		if not _active_choice_prompt.is_empty(): _active_choice_generation += 1
		_active_choice_prompt = {}
		_current_waiting_effect = null
		if _effect_modal != null: _effect_modal.hide()
		return
	if prompt != _active_choice_prompt or _active_choice_command_epoch != _battle_command_epoch or not _effect_modal.visible:
		_show_effect_modal(raw)
	_refresh_active_choice_lock()


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
	if _source == null or not _battle_command_input_available():
		return "当前命令尚未确认或会话不可操作"
	if not _source.read_pending().is_empty():
		return "请先处理当前待你答复的效果"
	if not _activation_effect_ids(true).is_empty():
		return ""
	for player in _source.read_view().get("players", []):
		if player.get("id") == _battle_command_observer and player.get("command_spell_count", 0) <= 0:
			return "没有令咒可用"
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
	if _source_is_local and _source != null:
		_source.invalidate()
	var reason := _command_spell_block_reason()
	if reason != "":
		_say(reason)
		return
	var effects: Array = _activation_effect_ids(true)
	if not effects.is_empty():
		_request_held_effect({"id": effects[0]})


# --- 等待选牌 ---
func _check_waiting_card_selection() -> void:
	var pending: Dictionary = EffectManager.get_pending_card_selection()
	var raw_effect: BaseEffect = pending.get("effect")
	# AI 仍由本地规则 driver 直接答复；真人/网络视图只消费 source 声明。
	if raw_effect != null and _seat_controller.is_ai(raw_effect._trigger_player_id):
		await _driver.answer_selection_async("cards",pending,get_tree())
		refresh_all_ui()
		return
	var declaration: Dictionary = _source.read_pending() if _source != null else {}
	if declaration.get("kind") != "card_choice":
		if not _card_choice_prompt.is_empty(): _card_choice_generation += 1
		_card_choice_prompt = {}
		_card_select_effect = null
		if _card_select_panel != null and _card_select_panel.visible:
			_card_select_panel.visible = false
		_card_select_picked = []
		return
	if not _card_choice_same(_card_choice_prompt, declaration) or _card_choice_command_epoch != _battle_command_epoch or _card_select_panel == null or not _card_select_panel.visible:
		_card_choice_generation += 1
		_card_choice_prompt = declaration.duplicate(true)
		_card_choice_command_epoch = _battle_command_epoch
		_card_select_picked = []
		_show_card_select_panel(_card_choice_display(declaration))
	elif _card_choice_declaration_changed(_card_select_request, declaration):
		_card_select_picked = _card_select_picked.filter(func(card): return _card_choice_ids(_card_select_request.get("cards", [])).has(_card_choice_id(card)))
		_show_card_select_panel(_card_choice_display(declaration))
	else:
		_refresh_card_select_confirm(_card_select_request)

func _card_choice_id(card) -> int:
	return int(card) if card is int else (int(card.get("id", -1)) if card is Dictionary else (_held_action_ids.id_for(card) if _held_action_ids != null and card is BaseCard else -1))

func _card_choice_ids(cards: Array) -> Array:
	var ids: Array = []
	for card in cards:
		var id := _card_choice_id(card)
		if id >= 0 and not ids.has(id): ids.append(id)
	return ids

func _card_choice_display(declaration: Dictionary) -> Dictionary:
	var views: Array = declaration.get("card_views", []).duplicate(true)
	var required_ids: Array = declaration.get("required", []).duplicate()
	return {"cards": views, "required_cards": views.filter(func(card): return required_ids.has(_card_choice_id(card))), "shown_name": declaration.get("label", "请选择牌"), "min": int(declaration.get("min", 1)), "max": int(declaration.get("max", -1)), "allow_cancel": bool(declaration.get("allow_cancel", false)), "verb": str(declaration.get("verb", "选择")), "secret": bool(declaration.get("secret", false)), "confirm_text": str(declaration.get("confirm_text", "确认选择"))}

func _card_choice_declaration_changed(display: Dictionary, declaration: Dictionary) -> bool:
	return _card_choice_ids(display.get("cards", [])) != _card_choice_ids(declaration.get("card_views", [])) or display.get("min") != declaration.get("min") or display.get("max") != declaration.get("max") or display.get("required_cards", []).size() != declaration.get("required", []).size()

func _card_choice_same(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty(): return false
	return int(a.get("effect", -1)) == int(b.get("effect", -1)) and _card_choice_ids(a.get("card_views", [])) == _card_choice_ids(b.get("card_views", [])) and _card_choice_ids(a.get("required", [])) == _card_choice_ids(b.get("required", [])) and int(a.get("min", 1)) == int(b.get("min", 1)) and int(a.get("max", -1)) == int(b.get("max", -1)) and bool(a.get("allow_cancel", false)) == bool(b.get("allow_cancel", false)) and str(a.get("verb", "")) == str(b.get("verb", "")) and bool(a.get("secret", false)) == bool(b.get("secret", false)) and str(a.get("confirm_text", "")) == str(b.get("confirm_text", ""))


# --- 等待选玩家 ---
func _check_waiting_player_selection() -> void:
	# raw 只进入显式 AI 控制席的原 driver，绝不作为本地展示声明。
	var raw: Dictionary = EffectManager.get_pending_player_selection()
	var effect: BaseEffect = raw.get("effect")
	if effect != null and _seat_controller.is_ai(effect._trigger_player_id):
		await _driver.answer_selection_async("players",raw,get_tree())
	var prompt: Dictionary = _source.read_pending() if _source != null else {}
	if prompt.get("kind") != "player_choice":
		if not _player_choice_prompt.is_empty(): _player_choice_generation += 1
		_player_choice_prompt = {}
		_player_select_effect = null
		if _player_select_panel != null: _player_select_panel.hide()
		return
	if prompt != _player_choice_prompt or _player_choice_command_epoch != _battle_command_epoch or not _player_select_panel.visible:
		_show_player_select_panel(prompt)
	_refresh_player_choice_lock()


# --- 等待选位置 ---
var _location_choice_prompt: Dictionary = {}
var _location_choice_generation: int = 0
var _location_choice_command_epoch: int = -1

func _check_waiting_location_selection() -> void:
	if not _source_is_local: return
	# AI 的对象身份适配与真人声明消费分开；不把 raw 候选传入展示。
	var raw: Dictionary = EffectManager.get_pending_location_selection()
	if not raw.is_empty() and _seat_controller.is_ai(raw.effect._trigger_player_id):
		await _driver.answer_selection_async("location",raw,get_tree())
	var declaration: Dictionary = _source.read_pending() if _source != null else {}
	if declaration.get("kind") != "location_choice":
		if not _location_choice_prompt.is_empty(): _location_choice_generation += 1
		_location_choice_prompt = {}
		get_node("Hint/LocationCancel").hide()
		return
	if declaration != _location_choice_prompt or _location_choice_command_epoch != _battle_command_epoch:
		_location_choice_generation += 1
		_location_choice_prompt = declaration.duplicate(true)
		_location_choice_command_epoch = _battle_command_epoch
		var cancel: Button = get_node("Hint/LocationCancel")
		for connection in cancel.pressed.get_connections(): cancel.pressed.disconnect(connection.callable)
		preload("res://scripts/game_scene/native_choice_renderer.gd").location(self,str(declaration.label),bool(declaration.allow_cancel),_cancel_location_choice.bind(declaration.duplicate(true),_location_choice_generation,_battle_command_epoch))
	get_node("Hint/LocationCancel").disabled = not _battle_command_input_available()

func _location_choice_current(declaration: Dictionary, generation: int, epoch: int) -> bool:
	if not _source_is_local or _source == null or generation != _location_choice_generation or epoch != _battle_command_epoch: return false
	if declaration.is_empty() or declaration != _location_choice_prompt or declaration != _source.read_pending():
		_check_waiting_location_selection()
		return false
	return true

func _submit_location_choice(area: int, declaration: Dictionary, generation: int, epoch: int) -> void:
	if not _location_choice_current(declaration,generation,epoch) or not declaration.get("areas",[]).has(area): return
	_submit_battle_command("location_choice", {"effect":declaration.effect,"area":area})

func _cancel_location_choice(declaration: Dictionary = {}, generation: int = -1, epoch: int = -1) -> void:
	if not _location_choice_current(declaration,generation,epoch) or not declaration.get("allow_cancel",false): return
	_submit_battle_command("cancel_choice", {"effect":declaration.effect})


# --- AI 推进 ---
func _check_and_step_ai(delta: float) -> void:
	if _broadcast_active or _is_paused():
		return
	if _is_debug_console_blocking_progress():
		return
	if _effect_result_modal != null and _effect_result_modal.visible:
		return
	_driver.step_interval = AI_STEP_INTERVAL
	var action:String = _driver.prepare_step(delta)
	if action == "ai_turn":
		await _driver.run_bot_turn_async(GameProgress.current_player_id,get_tree())
	elif action == "end_current_player_action":
		GameProgress.end_current_player_action(_driver.source_context)


func _run_dummy_bot_turn(bot_id: int) -> void:
	await _driver.run_bot_turn_async(bot_id,get_tree())


func _clear_ai_play_prompt(_bot_id: int) -> void:
	_ai_play_prompt_player_id = -1
	_ai_play_prompt_card = null
	_ai_play_prompt_round = -1
	if is_instance_valid(_ai_play_prompt_node):
		_ai_play_prompt_node.visible = false



func _on_ai_played_card(bot_id: int, card: BaseCard) -> void:
	if bot_id == _local_player_id:
		return
	# 出牌的表现交给卷轴里的入场动画：这里只记下是谁打的，不再弹浮动提示
	_ai_play_prompt_player_id = bot_id
	_ai_play_prompt_card = card
	_ai_play_prompt_round = GameProgress.current_round
	if is_instance_valid(_ai_play_prompt_node):
		_ai_play_prompt_node.visible = false



# --- 终局展示 ---
## 对局结束时打开战果榜一次并报出胜者；只展示一次，不会被刷新重复弹出
func _check_game_over() -> void:
	var view: Dictionary = _source.read_view() if _source != null else {}
	if not view.get("game_over", false):
		_game_over_shown = false
		return
	if _game_over_shown:
		return
	_game_over_shown = true
	if _board != null:
		_board.show()
		_bind_board()
	var winners := PackedStringArray()
	for player in view.get("players", []):
		if player.get("is_victory", false):
			winners.append(str(player.get("master", {}).get("name", player.get("player_name", ""))))
	_say("对局结束" if winners.is_empty() else "对局结束 · 胜者 " + "、".join(winners))


# --- 调试控制台（与旧控制器同源） ---
func _is_debug_console_blocking_progress() -> bool:
	return is_debug_console_enabled() and _debug_console != null and _debug_console.session != null and _debug_console.session.is_paused()


## 进度闸门：调试控制台暂停、或顺位动画（换人交接 / 轮次更迭）仍在播放时，界面不接受推进操作。
## 等动画演完再开始行动，否则玩家的结束阶段会和动画抢同一批卡片、把动画顶掉。
func _is_progress_blocked() -> bool:
	return _is_debug_console_blocking_progress() or _rival_anim_busy or _phase_anim_busy or _broadcast_active or _is_paused()


# --- 暂停菜单 ---
## 纯展示接线，单机与网络初始化均调用；不暂停权威规则进程。
func _bind_pause_menu_controls() -> void:
	if _pause_menu == null:
		return
	(_pause_menu.get_node("Box/BtnResume") as Button).pressed.connect(_close_pause_menu)
	(_pause_menu.get_node("Box/BtnMainMenu") as Button).pressed.connect(_return_to_main_menu)
	(_pause_menu.get_node("Box/BtnQuit") as Button).pressed.connect(get_tree().quit)

func _handle_escape() -> void:
	if $CardModificationHistory.visible:
		_close_card_modification_history()
		get_viewport().set_input_as_handled()
		return
	var had_overlay: bool = $EventDiscardMenu.visible or $CardBrowser.visible or $LogBrowser.visible \
			or (_hover_zoom != null and _hover_zoom.visible) or (_hover_desc != null and _hover_desc.visible)
	$EventDiscardMenu.hide()
	_close_card_browser()
	$LogBrowser.hide()
	_hide_event_zoom()
	if not had_overlay:
		_toggle_pause_menu()
	get_viewport().set_input_as_handled()

func _is_paused() -> bool:
	return _pause_menu != null and _pause_menu.visible


func _toggle_pause_menu() -> void:
	if _is_paused():
		_close_pause_menu()
	else:
		_open_confirmation_panel(_pause_menu)


func _close_pause_menu() -> void:
	if _pause_menu != null:
		_pause_menu.hide()


## 作废本局：先停掉本界面的帧循环（避免切场景前再推进一次 AI/刷新），
## 再由 GameStart 统一结束会话并复位引擎，最后切回主菜单
func _return_to_main_menu() -> void:
	_stop_battle_commands()
	set_process(false)
	_close_pause_menu()
	if network_session != null:
		if _host_lifecycle != null:
			_host_lifecycle.close()
	else:
		GameStart.end_session()
	get_tree().change_scene_to_file(GameStart.MAIN_MENU_SCENE)


func set_debug_console_enabled(enabled: bool) -> void:
	# 联机客户端没有本地权威调试许可，不能初始化规则编辑会话。
	if network_session != null and enabled:
		return
	if enabled:
		if is_debug_console_enabled():
			return
		_debug_console.initialize(self)
		return
	if not is_debug_console_enabled():
		return
	_debug_console.safe_shutdown()


func is_debug_console_enabled() -> bool:
	return _debug_console != null and is_instance_valid(_debug_console) and _debug_console.session != null


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
func _bind_tactical_confirmation() -> void:
	if _tactical_confirm == null:
		return
	var btn_ok := _tactical_confirm.get_node("Box/ButtonsRow/BtnConfirmAction") as Button
	if not btn_ok.pressed.is_connected(_on_tactical_confirm_execute):
		btn_ok.pressed.connect(_on_tactical_confirm_execute)
	var btn_cancel := _tactical_confirm.get_node("Box/ButtonsRow/BtnCancelAction") as Button
	if not btn_cancel.pressed.is_connected(_on_tactical_confirm_cancel):
		btn_cancel.pressed.connect(_on_tactical_confirm_cancel)

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
		_pending_tactical_action["command_epoch"] = _battle_command_epoch
	_open_confirmation_panel(_tactical_confirm)


func _on_tactical_confirm_execute() -> void:
	if _is_progress_blocked() or not _battle_command_input_available():
		return
	var act_type: String = _pending_tactical_action.get("type", "")
	if act_type not in ["deploy", "move"]:
		return
	if _pending_tactical_action.get("command_epoch", _battle_command_epoch) != _battle_command_epoch or (not _source_is_local and _pending_tactical_action.get("view_seq", -1) != _read_battle_command_sequence()):
		_pending_tactical_action.clear()
		_tactical_confirm.hide()
		_say("局面已更新，请重新选择战区并确认")
		return
	var area_id: int = int(_pending_tactical_action.get("area", -1))
	if _source_is_local and not _pending_tactical_action.has("area"):
		if act_type == "deploy":
			var target_loc = _pending_tactical_action.get("target_loc")
			if target_loc is BaseLocation: area_id = _held_action_ids.id_for(target_loc.get_from())
		else:
			var index: int = int(_pending_tactical_action.get("target_area_idx", -1))
			if index >= 0 and index < MapData.areas.size(): area_id = _held_action_ids.id_for(MapData.areas[index])
	_tactical_confirm.hide()
	_pending_tactical_action.clear()
	_submit_battle_command(act_type, {"area": area_id}, act_type == "deploy")


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
func _show_effect_modal(_effect: BaseEffect) -> void:
	var prompt: Dictionary = _source.read_pending() if _source != null else {}
	if prompt.get("kind") != "active_choice": return
	_active_choice_generation += 1
	_active_choice_command_epoch = _battle_command_epoch
	_active_choice_prompt = prompt.duplicate(true)
	var declaration: Dictionary = prompt.duplicate(true)
	preload("res://scripts/game_scene/native_choice_renderer.gd").active(self, declaration, _active_pick.bind(declaration, _active_choice_generation, _battle_command_epoch), _active_pick_quantity.bind(declaration, _active_choice_generation, _battle_command_epoch))
	var confirm: Button = _effect_modal.get_node("Box/ButtonsRow/BtnConfirm")
	var cancel: Button = _effect_modal.get_node("Box/ButtonsRow/BtnCancel")
	for connection in confirm.pressed.get_connections(): confirm.pressed.disconnect(connection.callable)
	for connection in cancel.pressed.get_connections(): cancel.pressed.disconnect(connection.callable)
	confirm.pressed.connect(_active_confirm.bind(declaration, _active_choice_generation, _battle_command_epoch))
	cancel.pressed.connect(_active_cancel.bind(declaration, _active_choice_generation, _battle_command_epoch))


## 效果消耗行：复用独立成本文本模块，界面不另写一套资源名
func _attach_effect_cost_line(base_text: String, effect: BaseEffect) -> String:
	return CostText.attach_line(base_text, CostText.effect_cost_items(effect))


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


## 兼容入口只转声明命令；数量不写入规则对象。
func _on_effect_option_picked_with_quantity(index: int, spin: SpinBox) -> void:
	_active_pick_quantity(index, spin, _active_choice_prompt.duplicate(true))

func _on_effect_option_picked(index: int) -> void:
	_active_pick(index, _active_choice_prompt.duplicate(true))

func _on_effect_modal_confirm() -> void:
	_active_confirm(_active_choice_prompt.duplicate(true))

func _on_effect_modal_cancel() -> void:
	_active_cancel(_active_choice_prompt.duplicate(true))

func _active_choice_current(declaration: Dictionary, generation: int = -1, epoch: int = -1) -> bool:
	if generation >= 0 and generation != _active_choice_generation: return false
	if epoch >= 0 and epoch != _battle_command_epoch: return false
	if not _source_is_local or _source == null or declaration.get("kind") != "active_choice": return false
	if declaration != _source.read_pending():
		_check_waiting_effects()
		return false
	return _battle_command_input_available() and not _is_paused()

func _active_pick(index: int, declaration: Dictionary, generation: int = -1, epoch: int = -1) -> void:
	if not _active_choice_current(declaration, generation, epoch): return
	if index < 0 or index >= declaration.options.size(): return
	var option: Dictionary = declaration.options[index]
	if not option.available or option.has("quantity_range"): return
	_submit_battle_command("option_choice", {"effect":declaration.effect, "choices":[{"index":option.index, "count":1}]})

func _active_pick_quantity(index: int, spin: SpinBox, declaration: Dictionary, generation: int = -1, epoch: int = -1) -> void:
	if not _active_choice_current(declaration, generation, epoch): return
	if spin == null or index < 0 or index >= declaration.options.size(): return
	var option: Dictionary = declaration.options[index]
	if not option.available or not option.has("quantity_range"): return
	spin.apply()
	var quantity: int = int(spin.value)
	if quantity < option.quantity_range[0] or quantity > option.quantity_range[1]: return
	_submit_battle_command("option_choice", {"effect":declaration.effect, "choices":[{"index":option.index, "count":1, "quantity":quantity}]})

func _active_confirm(declaration: Dictionary, generation: int = -1, epoch: int = -1) -> void:
	if not _active_choice_current(declaration, generation, epoch): return
	if declaration.options.is_empty():
		_submit_battle_command("active_choice", {"effect":declaration.effect, "activate":true})
		return
	if not declaration.multi: return
	var choices: Array = preload("res://scripts/game_scene/native_choice_renderer.gd").active_choices(self, declaration)
	if not choices.is_empty(): _submit_battle_command("option_choice", {"effect":declaration.effect, "choices":choices})

func _active_cancel(declaration: Dictionary, generation: int = -1, epoch: int = -1) -> void:
	if not _active_choice_current(declaration, generation, epoch) or not declaration.allow_cancel: return
	_submit_battle_command("cancel_choice", {"effect":declaration.effect})

func _refresh_effect_confirm_state(options_row: Control, btn_confirm: Button) -> void:
	if btn_confirm == null or options_row == null: return
	var selected: bool = false
	for row in options_row.get_children():
		for child in row.get_children():
			if child is CheckBox and child.button_pressed and not child.disabled: selected = true
	btn_confirm.disabled = not selected or not _end_command_attempt.is_empty()

func _refresh_active_choice_lock() -> void:
	if _effect_modal == null or not _effect_modal.visible: return
	var locked: bool = not _battle_command_input_available()
	for button in _effect_modal.find_children("*", "Button", true, false):
		if locked and not button.has_meta("active_choice_disabled"): button.set_meta("active_choice_disabled", button.disabled)
		if locked: button.disabled = true
		elif button.has_meta("active_choice_disabled"):
			button.disabled = bool(button.get_meta("active_choice_disabled"))
			button.remove_meta("active_choice_disabled")


# --- 发动结果 / 消息 ---
func _bind_mana_cost_preview(_pl: Dictionary = {}) -> void:
	_render_group_cost_preview(_read_group_preview(), _held_input_available())

## 只渲染既有预览数值；等待、拒绝、字段缺失均收起，不用卡面补算。
func _render_group_cost_preview(group: Dictionary, input_available: bool) -> void:
	var panel := get_node("ManaCostPreview") as Control
	var preview: Dictionary = group.get("preview", {})
	panel.visible = input_available and not group.get("cards", []).is_empty() and _group_preview_ready(group) and preview.has_all(["mana_cost", "remaining_magic"])
	if not panel.visible:
		return
	_set_text(panel, "Box/Cost", "魔力消耗 %s" % BaseNumber.display_text(preview.mana_cost))
	_set_text(panel, "Box/Remaining", "剩余魔力 %s" % BaseNumber.display_text(preview.remaining_magic))
	_layout_mana_cost_preview(panel)


## 仅定位；单人与联机共用，不读取规则和资源。
func _layout_mana_cost_preview(panel: Control) -> void:
	if _strips.get_child_count() == 0:
		return
	var self_rect := _self.get_global_rect()
	var master_rect := (_master.get_node("Frame") as Control).get_global_rect()
	var left := self_rect.end.x + HELD_GAP
	var right := master_rect.position.x - HELD_GAP
	var scroll_rect := (_strips.get_child(maxi(0, _main_area_index)) as Control).get_global_rect()
	var skill_top := get_viewport_rect().end.y
	for slot: Control in _hand.get_children():
		if slot.get_meta("held_group", "") == "zone" and slot.has_meta("rest_position"):
			skill_top = minf(skill_top, (_hand.get_global_transform() * (slot.get_meta("rest_position") as Vector2)).y)
	panel.global_position = Vector2(
		minf(left, maxf(self_rect.end.x, right - panel.size.x)),
		minf(scroll_rect.end.y - panel.size.y / 3.0, skill_top - HELD_GAP - panel.size.y))


func _fit_confirmation_panel(panel: Control) -> void:
	if not is_instance_valid(panel) or not panel.visible:
		return
	var box := panel.get_node("Box") as Control
	panel.size.y = box.get_combined_minimum_size().y + box.offset_top - box.offset_bottom
	panel.global_position = get_viewport_rect().get_center() - panel.size * 0.5


func _open_confirmation_panel(panel: Control) -> void:
	panel.show()
	_fit_confirmation_panel(panel)
	_fit_confirmation_panel.call_deferred(panel)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_make_confirmation_children_passive(panel)
	if not panel.has_meta("drag_enabled"):
		panel.set_meta("drag_enabled", true)
		panel.gui_input.connect(_on_confirmation_drag_input.bind(panel))
	_raise_modal(panel)


func _make_confirmation_children_passive(node: Node) -> void:
	for child in node.get_children():
		if child is Button or child is ScrollContainer or child is LineEdit or child is TextEdit or child is Range:
			continue
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_make_confirmation_children_passive(child)


func _on_confirmation_drag_input(event: InputEvent, panel: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging_modal = panel if event.pressed else null
		_raise_modal(panel)
		panel.accept_event()
	elif event is InputEventMouseMotion and _dragging_modal == panel:
		var target: Vector2 = panel.global_position + event.relative
		var bounds := get_viewport_rect()
		panel.global_position = Vector2(
			clampf(target.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - panel.size.x)),
			clampf(target.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - panel.size.y)))
		panel.accept_event()


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
		var t := get_tree().create_timer(_EFFECT_MSG_TOAST_INTERVAL, false)
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
	var cancel := _card_select_panel.get_node_or_null("Box/ButtonsRow/BtnCancelSelect") as Button
	if cancel:
		cancel.visible = bool(pending.get("allow_cancel", true))
	_card_select_cards = pending.get("cards", [])
	_card_select_request = pending.duplicate()
	if pending.get("regular", false):
		_card_select_request["command_epoch"] = _battle_command_epoch
		_card_select_request["view_seq"] = _read_battle_command_sequence()
	var required_ids: Array = _card_choice_ids(pending.get("required_cards", []))
	for card in pending.get("cards", []):
		if required_ids.has(_card_choice_id(card)) and not _card_select_picked.any(func(picked): return _card_choice_id(picked) == _card_choice_id(card)):
			_card_select_picked.append(card)
	var vp := get_viewport_rect().size
	_card_select_panel.position = Vector2(maxf(0.0, (vp.x - 820.0) * 0.5), vp.y * 0.16)
	var title := _card_select_panel.get_node_or_null("Box/Title") as Label
	if title:
		title.text = _select_card_title(pending)
	var row := _card_select_panel.get_node_or_null("Box/CardScroll/CardRow") as HBoxContainer
	if row == null:
		return
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	for card in _card_select_cards:
		var rect := TextureRect.new()
		rect.custom_minimum_size = Vector2(146, 200)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.mouse_filter = Control.MOUSE_FILTER_STOP
		rect.set_meta("select_card", card)
		rect.gui_input.connect(_on_select_card_input.bind(rect))
		preload("res://scripts/game_scene/native_choice_renderer.gd").choice_card(self,rect,card)
		row.add_child(rect)
	_card_select_panel.visible = true
	_raise_modal(_card_select_panel)
	_refresh_card_select_confirm(pending)


## 选牌面板标题：效果名 + 数量范围。秘密选择不展示数量提示以免泄露
func _select_card_title(pending: Dictionary) -> String:
	var eff = pending.get("effect")
	var base_name := str(pending.get("shown_name", "请选择牌"))
	if pending.get("secret",false): return base_name
	if eff != null and (eff._options[int(pending.get("option_index", 0))] as Dictionary).get("tags", []).has("secret_choice"):
		return base_name
	var low: int = int(pending.get("min", 1))
	var high: int = int(pending.get("max", low))
	var range_text: String = ("%d-%d" % [low, high]) if high != -1 else ("至少 %d" % low)
	return "%s · 选择 %s" % [base_name, range_text]


## 选牌面板"确认"按钮文案：动词来自选项 declaration.verb，缺省按数据语义"确认弃置/确认选择"
func _select_card_confirm_text(pending: Dictionary) -> String:
	if pending.has("confirm_text"): return str(pending.confirm_text)
	var option_label: String = ""
	var effect = pending.get("effect")
	var index: int = int(pending.get("option_index",0))
	if effect != null and index >= 0 and index < effect._options.size():
		option_label = str(effect._options[index].get("shown_option_name",""))
	return preload("res://scripts/game_scene/native_choice_renderer.gd").card_confirm(str(pending.get("verb","")),option_label)


func _refresh_card_select_confirm(pending: Dictionary) -> void:
	if _card_select_panel == null:
		return
	var hint := _card_select_panel.get_node_or_null("Box/Hint") as Label
	var row := _card_select_panel.get_node_or_null("Box/CardScroll/CardRow")
	if row != null:
		for slot in row.get_children():
			var card = slot.get_meta("select_card", null)
			_set_card_selected_mark(slot, _card_select_picked.any(func(picked): return _card_choice_id(picked) == _card_choice_id(card)))
			slot.tooltip_text = "必选：保留原手牌" if _card_choice_ids(pending.get("required_cards", [])).has(_card_choice_id(card)) else ""
	if hint:
		var eff2 = pending.get("effect")
		var opt_idx := int(pending.get("option_index", 0))
		var opt_tags: Array = []
		if eff2 != null and opt_idx >= 0 and opt_idx < eff2._options.size():
			var opt_dict: Dictionary = eff2._options[opt_idx]
			var tags_v = opt_dict.get("tags", [])
			if tags_v is Array:
				opt_tags = tags_v
		var is_secret: bool = bool(pending.get("secret",false)) or opt_tags.has("secret_choice")
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
		if high2 != -1 and pending.get("required_cards", []).size() > high2 and hint != null:
			hint.text = "当前必选牌超过上限，无法重组；所有原牌保留"


func _on_select_card_input(ev: InputEvent, slot: Control) -> void:
	if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed):
		return
	var card = _meta_or(slot, "select_card", null)
	if card == null:
		return
	if _card_choice_ids(_card_select_request.get("required_cards", [])).has(_card_choice_id(card)):
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


func _set_card_selected_mark(node: Control, selected: bool) -> void:
	var mark := node.get_node_or_null("SelectMark") as Panel
	if mark != null:
		mark.visible = selected
		return
	if not selected:
		return
	mark = Panel.new()
	mark.name = "SelectMark"
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.set_border_width_all(5)
	style.border_color = Color(1.0, 0.85, 0.3)
	mark.add_theme_stylebox_override("panel", style)
	node.add_child(mark)
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _card_choice_current(declaration: Dictionary, generation: int, command_epoch: int) -> bool:
	if generation != _card_choice_generation or command_epoch != _battle_command_epoch or _source == null or not _source_is_local: return false
	var current: Dictionary = _source.read_pending()
	if not _card_choice_same(declaration, current):
		_check_waiting_card_selection()
		return false
	return _battle_command_input_available() and not _is_paused()


func _on_card_select_confirmed() -> void:
	if _card_select_request.get("regular", false):
		if not _battle_command_input_available("play_group") or _is_paused(): return
		# network source 的预览只绑定 held selection，不接受独立 regular draft。
		# 缺少显式 draft 预览接口时失败关闭，不能错发另一组暂选。
		if not _source_is_local:
			_say("独立常规选牌尚未绑定权威预览，请使用持有区出牌")
			return
		if _card_select_request.get("command_epoch") != _battle_command_epoch or _card_select_request.get("view_seq") != _read_battle_command_sequence(): return
		var cards: Array = _card_select_picked.duplicate()
		var hidden: Array = []
		for card in cards:
			hidden.append(bool(_card_select_hidden.get(card, card.get("concealed", false) if card is Dictionary else card._is_concealed)))
		var group: Dictionary = _source.read_group_preview(cards, hidden)
		if not _group_preview_ready(group) or not group.get("preview", {}).get("can_submit", false): return
		_submit_battle_command("play_group", {"cards": group.cards, "hidden": group.hidden})
		return
	if not _card_choice_prompt.is_empty():
		if not _card_choice_current(_card_choice_prompt, _card_choice_generation, _card_choice_command_epoch): return
		var ids: Array = _card_choice_ids(_card_select_picked)
		var low := int(_card_choice_prompt.get("min", 1))
		var high := int(_card_choice_prompt.get("max", -1))
		if ids.size() < low or (high != -1 and ids.size() > high): return
		for required in _card_choice_prompt.get("required", []):
			if not ids.has(int(required)): return
		_submit_battle_command("card_choice", {"effect": int(_card_choice_prompt.get("effect", -1)), "cards": ids})
		return
	# 没有声明的旧 effect 回退不执行规则；重读真实 pending 后重新接线。
	_check_waiting_card_selection()


func _on_card_select_cancelled() -> void:
	if not _battle_command_input_available() or _is_paused(): return
	if not bool(_card_select_request.get("allow_cancel", true)):
		return
	if not _card_choice_prompt.is_empty():
		if not _card_choice_current(_card_choice_prompt, _card_choice_generation, _card_choice_command_epoch) or not _card_choice_prompt.get("allow_cancel", false): return
		_submit_battle_command("cancel_choice", {"effect": int(_card_choice_prompt.get("effect", -1))})
		return
	if _card_select_request.get("regular", false):
		_card_select_request = {}
		_card_select_submit = Callable()
		_card_select_picked = []
		_card_select_hidden = {}
		_card_select_panel.hide()
		return
	_check_waiting_card_selection()


# --- 选人浮层 ---
func _show_player_select_panel(pending: Dictionary) -> void:
	_player_choice_generation += 1
	_player_choice_command_epoch = _battle_command_epoch
	_player_choice_prompt = pending.duplicate(true)
	var declaration: Dictionary = _player_choice_prompt.duplicate(true)
	var names: Dictionary = {}
	for pid in declaration.players: names[pid] = _player_name(pid)
	preload("res://scripts/game_scene/native_choice_renderer.gd").players(self, declaration, names, _submit_player_choice.bind(declaration, _player_choice_generation, _battle_command_epoch), _cancel_player_choice.bind(declaration, _player_choice_generation, _battle_command_epoch))

func _player_choice_current(declaration: Dictionary, generation: int = -1, command_epoch: int = -1) -> bool:
	if generation >= 0 and generation != _player_choice_generation: return false
	if command_epoch >= 0 and command_epoch != _battle_command_epoch: return false
	if _source == null or not _source_is_local or declaration.is_empty(): return false
	if declaration != _source.read_pending():
		_check_waiting_player_selection()
		return false
	return _battle_command_input_available() and not _is_paused()

func _submit_player_choice(picks: Array, declaration: Dictionary, generation: int = -1, command_epoch: int = -1) -> void:
	if not _player_choice_current(declaration, generation, command_epoch): return
	_submit_battle_command("player_choice", {"effect": declaration.effect, "players": picks.duplicate()})

func _cancel_player_choice(declaration: Dictionary, generation: int = -1, command_epoch: int = -1) -> void:
	if not _player_choice_current(declaration, generation, command_epoch) or not declaration.get("allow_cancel", false): return
	_submit_battle_command("cancel_choice", {"effect": declaration.effect})

func _refresh_player_choice_lock() -> void:
	if _player_select_panel == null or not _player_select_panel.visible: return
	var locked: bool = not _battle_command_input_available()
	for button in _player_select_panel.find_children("*", "Button", true, false):
		if locked and not button.has_meta("player_choice_disabled"):
			button.set_meta("player_choice_disabled", button.disabled)
		if locked: button.disabled = true
		elif button.has_meta("player_choice_disabled"):
			button.disabled = bool(button.get_meta("player_choice_disabled"))
			button.remove_meta("player_choice_disabled")


func _on_player_target_picked(player_id: int) -> void:
	_submit_player_choice([player_id], _player_choice_prompt.duplicate(true))


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
	return "【%s】胜者：%s，最高威力 %s" % [area_name, "、".join(names), BaseNumber.display_text(detail.get("highest_power", 0))]


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
	var absent := _broadcast_node.get_node("ConfirmAbsentBtn") as Button
	if not absent.pressed.is_connected(_on_broadcast_absent_pressed):
		absent.pressed.connect(_on_broadcast_absent_pressed)
	_broadcast_node.hide()
	return _broadcast_node


## 每帧检查：结算暂停后等待再弹出；AI 只在入场完成后确认，全部确认后放行。
func _update_battle_broadcast(delta: float) -> void:
	var declaration := _read_broadcast_declaration()
	var pending: bool = declaration.get("pending", false)
	var batch: int = declaration.get("batch_id", 0)
	if batch != _broadcast_batch_id:
		_hide_broadcast()
		_broadcast_wait_elapsed = 0.0
		_broadcast_reveal_done = false
		_broadcast_batch_id = batch
	if not pending:
		_broadcast_wait_elapsed = 0.0
	if pending and not _broadcast_active:
		_broadcast_wait_elapsed += maxf(0.0, delta)
		if _broadcast_wait_elapsed >= BROADCAST_OPEN_DELAY:
			_show_battle_broadcast()
	elif not pending and _broadcast_active:
		# 兜底：引擎已放行但播报还挂着（如外部直接全部确认），收起
		_hide_broadcast()
	if _broadcast_active:
		if _source_is_local and _broadcast_reveal_done and _battle_command_input_available("confirm_broadcast"):
			if _battle_commands.tick_broadcast_confirmation(delta): _source.invalidate()
		_refresh_broadcast_continue()

## UI 只消费显式屏障声明，不从核心补齐资格。
func _read_broadcast_declaration() -> Dictionary:
	return _source.read_view().get("battle_broadcast", {}) if _source != null else {}

## reset 完成后、首次推进前调用；名单来自 driver 控制声明。
func _declare_local_broadcast_confirmation() -> bool:
	if not _source_is_local or _battle_commands == null: return false
	var ai_seats: Array = []
	for seat in GameData.player_data_library:
		if seat is int and _driver.seats.is_ai(seat): ai_seats.append(seat)
	ai_seats.sort()
	return _battle_commands.declare_broadcast_confirmation(true, ai_seats)


## 弹出播报：逐战场生成明细块，再播放标题 + 分块入场。
func _show_battle_broadcast() -> void:
	var overlay := _battle_broadcast_node()
	if overlay == null:
		return
	var view: Dictionary = _source.read_view()
	var details: Dictionary = GameProgress.last_battle_result.get("details_by_area", {}) if _source_is_local else view.get("battle_result", {})
	var list := overlay.get_node("AreaScroll/List") as VBoxContainer
	_clear(list)
	# 按地图从左到右的顺序（MapData.areas）从上到下排列
	for area in view.get("areas", []):
		var area_name := str(area.get("name", ""))
		if details.has(area_name):
			if _source_is_local:
				list.add_child(_build_broadcast_area_row(area_name, details[area_name]))
			else:
				var summary := Label.new()
				summary.text = _battle_result_line(area_name, details[area_name])
				summary.theme_type_variation = &"Gold2"
				summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				list.add_child(summary)
	_broadcast_active = true
	_broadcast_reveal_done = false
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
	)



## 亮起「继续」按钮并实时刷新「已确认 n/7」提示。
func _refresh_broadcast_continue() -> void:
	var overlay := _battle_broadcast_node()
	if overlay == null:
		return
	var btn := overlay.get_node("ContinueBtn") as Button
	var absent := overlay.get_node("ConfirmAbsentBtn") as Button
	absent.visible = _broadcast_reveal_done and not _broadcast_absent_declaration().is_empty()
	absent.disabled = not _battle_command_input_available("broadcast_confirm_absent")
	if not _broadcast_reveal_done:
		return
	if not btn.visible:
		btn.visible = true
		btn.modulate.a = 0.0
		var tw := btn.create_tween()
		tw.tween_property(btn, "modulate:a", 1.0, 0.3)
	var declaration := _read_broadcast_declaration()
	var confirmed: Array = declaration.get("confirmed", [])
	var confirmers: Array = declaration.get("confirmers", [])
	btn.text = "继续（已确认 %d/%d）" % [confirmed.size(), confirmers.size()]
	btn.disabled = not _broadcast_confirm_available(declaration)


## 「继续」按钮：本地玩家确认自己；AI 玩家由上面的逐人自动确认补齐。
func _on_broadcast_continue_pressed() -> void:
	var declaration := _read_broadcast_declaration()
	if not _broadcast_confirm_available(declaration): return
	_submit_battle_command("confirm_broadcast", {"batch_id": declaration.batch_id})

func _broadcast_confirm_available(declaration: Dictionary) -> bool:
	return _broadcast_reveal_done and declaration.get("pending", false) and declaration.get("batch_id") == _broadcast_batch_id and declaration.get("confirmers", []).has(_battle_command_observer) and not declaration.get("confirmed", []).has(_battle_command_observer) and _battle_command_input_available("confirm_broadcast")

## 尚无此授权投影，缺字段保持隐藏，不拿 connection_wait 充当授权。
## 交接 schema: actions.broadcast_confirm_absent = {can_confirm:bool, view_seq:int, batch_id:int, seats:Array[int]}。
func _broadcast_absent_declaration() -> Dictionary:
	if _source_is_local or network_session == null or _source == null: return {}
	var view: Dictionary = _source.read_view()
	var broadcast: Dictionary = view.get("battle_broadcast", {})
	var declared = _source.read_actions().get("broadcast_confirm_absent")
	if not declared is Dictionary or declared.get("can_confirm") != true or not declared.get("view_seq") is int or not declared.get("batch_id") is int or not declared.get("seats") is Array: return {}
	if not broadcast.get("pending", false) or declared.view_seq != view.get("seq") or declared.batch_id != broadcast.get("batch_id") or declared.seats.is_empty(): return {}
	if network_session.view.get("owner") != network_session.peer_id(): return {}
	var seats: Array = []
	for seat in declared.seats:
		if not seat is int or seats.has(seat) or not broadcast.get("confirmers", []).has(seat) or broadcast.get("confirmed", []).has(seat): return {}
		seats.append(seat)
	return {"view_seq":declared.view_seq, "batch_id":declared.batch_id, "seats":seats}

func _on_broadcast_absent_pressed() -> void:
	var declaration := _broadcast_absent_declaration()
	if not _broadcast_reveal_done or declaration.is_empty(): return
	_submit_battle_command("broadcast_confirm_absent", declaration)


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
	if obj is Dictionary:
		var disclosed: bool = obj.get("visible", false) and not obj.get("concealed", true)
		node.texture = LoadHelper.load_texture(obj.get("image", "") if disclosed else obj.get("back_image", ""))
		_sync_overlay(node, owned and show_conceal_mark and obj.get("concealed", true), "ConcealOverlay", CONCEAL_COLOR, CONCEAL_ICON)
		_sync_overlay(node, false, "InactiveOverlay", INACTIVE_COLOR)
		bind_zoom_for_card(node, obj)
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
	if _native_modal_visible():
		return
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
	hint.visible = _can_show_card_desc(card)
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
	if obj is Dictionary:
		if not obj.get("visible", false):
			_disable_card_zoom(node)
			return
		_bind_zoom_data(node, obj, obj.get("zoom_kind", ""), obj.get("back_image", "") if obj.get("concealed", true) else obj.get("image", ""), obj.get("concealed", true), obj.get("name", ""), obj.get("description", ""), right_action)
		return
	var kind: String = obj.get_zoom_kind(img_field) if obj != null and obj.has_method("get_zoom_kind") else ""
	if not kind in [LoadHelper.ZOOM_KIND_CARD, LoadHelper.ZOOM_KIND_AVATAR, LoadHelper.ZOOM_KIND_TOKEN]:
		_disable_card_zoom(node)
		return
	var concealed := obj is BaseCard and bool(obj.get("_is_concealed"))
	# 与网络展示字典一致：暗置只能使用对象声明的卡背，不能把正面交给浮图。
	# 这里先重绑当前查看数据，旧owner由_bind_zoom_data立即失效，不等翻面tween中点。
	var img = obj.get("_card_back_img") if concealed else (obj.get(img_field) if img_field != "" else obj.get("_card_img"))
	var has_img: bool = img != null and str(img) != "" and LoadHelper.texture_exists(str(img))
	var desc := ""
	if kind == LoadHelper.ZOOM_KIND_CARD and not concealed:
		desc = _build_card_desc(obj)
	elif kind == LoadHelper.ZOOM_KIND_TOKEN and not concealed:
		desc = CardDescText.token_desc(obj)
	_bind_zoom_data(node, obj, kind, str(img) if has_img else "", concealed, _object_shown_name(obj), desc, right_action)


## 悬浮候选：从真实命中控件向上找最近的、声明了放大的展示位。
## 用每帧命中判定而不是 mouse_entered 脉冲：子节点抢命中、子像素进出、布局变化引起的
## 进入/离开抖动都不会误触发放大。
func _bind_card_view_controls() -> void:
	# 原生弹窗本身拥有生命周期；show/hide/visible 的全部本地及网络入口共用，
	# 不复制选择外壳，也不把只读 CardBrowser（允许看牌）当成禁止放大的选择窗。
	_modal_blockers.assign([_tactical_confirm, _effect_modal, _effect_result_modal, _card_select_panel, _player_select_panel, _pause_menu, $CardModificationHistory])
	for panel in _modal_blockers:
		if panel != null and not panel.visibility_changed.is_connected(_on_native_modal_visibility_changed):
			panel.visibility_changed.connect(_on_native_modal_visibility_changed)
	if _native_modal_visible():
		_hide_event_zoom()
	if _hover_zoom != null and not _hover_zoom.gui_input.is_connected(_on_hover_zoom_gui_input):
		_hover_zoom.gui_input.connect(_on_hover_zoom_gui_input)
	var close: Button = _hover_desc.get_node("Close")
	if not close.pressed.is_connected(_close_card_desc):
		close.pressed.connect(_close_card_desc)

func _native_modal_visible() -> bool:
	for panel in _modal_blockers:
		if is_instance_valid(panel) and panel.is_visible_in_tree():
			return true
	return false

func _on_native_modal_visibility_changed() -> void:
	# 开/关均作废旧owner、悬浮候选和保活计时；关闭后只由新的真实GUI命中重新计时。
	# zoom本身没有异步tween；不要添加另一套延时或吞掉关闭后的新地图点击。
	_hide_event_zoom()

func _bind_zoom_data(node: Control, obj, kind: String, image: String, concealed: bool, title: String, description: String, right_action: String) -> void:
	if kind not in LoadHelper.ZOOM_KINDS:
		_disable_card_zoom(node)
		return
	# 同一展示槽重绑卡背/新卡面时，旧浮图不能继续保留先前的公开图片。
	if node == _hover_zoom_source and str(node.get_meta("zoom_img", "")) != image:
		_hide_event_zoom(false)
	node.set_meta("zoom_disabled", false)
	node.set_meta("zoom_img", image)
	node.set_meta("zoom_obj", obj)
	node.set_meta("zoom_title", "" if concealed else title)
	node.set_meta("zoom_desc", "" if concealed else description)
	node.set_meta("zoom_right_action", right_action)
	if concealed and _desc_source_id == node.get_instance_id():
		_close_card_desc()
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	if not node.has_meta("zoom_bound"):
		node.set_meta("zoom_bound", true)
		node.gui_input.connect(_on_zoom_target_gui_input.bind(node))

func _zoom_hover_candidate() -> Control:
	if _native_modal_visible():
		return null
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


## 只给说明的展示位：声明了标题或说明、但没有可放大的图（状态条这类）。
## 这类展示位的「查看」只有说明面板，点击与悬浮都按它对待，不参与放大图的悬浮计时
func _is_desc_only(node: Control) -> bool:
	if node == null or bool(node.get_meta("zoom_disabled", true)):
		return false
	if str(node.get_meta("zoom_img", "")) != "":
		return false
	return str(node.get_meta("zoom_title", "")) != "" or str(node.get_meta("zoom_desc", "")) != ""


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
	if _hover_zoom == null or _native_modal_visible():
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
	elif _is_desc_only(candidate):
		# 只给说明的展示位（buff 这类没有图）：悬浮稳定后直接显示说明，
		# 不走放大图分支；鼠标停在展示位或说明面板上期间保持可见。
		_zoom_hover_candidate_id = candidate.get_instance_id()
		_zoom_hover_elapsed = ZOOM_HOVER_DELAY_SECONDS
		_zoom_hide_remaining = -1.0
		if not (_hover_desc.visible and _desc_source_id == candidate.get_instance_id()):
			_show_desc_for(candidate)
		return
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


## 朝向实时检查，防止翻暗后旧绑定或放大图继续泄露说明。
func _can_show_card_desc(node: Control) -> bool:
	if not is_instance_valid(node) or bool(node.get_meta("zoom_disabled", true)):
		return false
	var obj = node.get_meta("zoom_obj", null)
	if obj is BaseCard and obj._is_concealed:
		return false
	return not str(node.get_meta("zoom_title", "")).is_empty() or not str(node.get_meta("zoom_desc", "")).is_empty()


## 显示展示位的说明面板：卡位右键与放大卡图右键共用同一入口
func _show_desc_for(node: Control) -> bool:
	if _native_modal_visible():
		return false
	if not _can_show_card_desc(node):
		if is_instance_valid(node) and _desc_source_id == node.get_instance_id():
			_close_card_desc()
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
	return CardDescText.card_desc(obj)


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
			_hide_event_zoom(false)
			_close_card_desc()
			opponent_card.set_meta("turn_order_player_id", pid)
			# 先显示再刷新：分区行的高度要等布局算完，刷新里的"下一帧补算"才排得上
			_opponent_drawer.visible = true
			_update_drawer_visuals(opponent_card)
			if _board != null:
				_board.visible = false
		get_viewport().set_input_as_handled()


func _on_close_opponent_drawer_pressed() -> void:
	_selected_opponent = null
	_selected_opponent_id = -1
	if _opponent_drawer != null:
		_opponent_drawer.visible = false


func _update_drawer_visuals(opponent: Control) -> void:
	if _opponent_drawer == null:
		return
	if _source_is_local and _source != null:
		_source.invalidate()
	var pid: int = int(opponent.get_meta("turn_order_player_id", -1)) if is_instance_valid(opponent) else _selected_opponent_id
	var player: Dictionary = {}
	var view: Dictionary = _source.read_view() if _source != null else {}
	for item in view.get("players", []):
		if item.id == pid:
			player = item
	if player.is_empty():
		_on_close_opponent_drawer_pressed()
		return
	_selected_opponent_id = pid
	_selected_opponent = opponent
	var drawer: Control = _opponent_drawer
	_set_img(drawer, "VBox/HeaderBar/SelectedAvatarFrame/Avatar", player.avatar)
	# 头像路径本身是已授权的快照字段；不加载本机御主模板。
	bind_zoom_for_card(drawer.get_node("VBox/HeaderBar/SelectedAvatarFrame/Avatar"), {"visible": true, "concealed": false, "zoom_kind": "avatar", "image": player.avatar, "name": player.master.get("name", ""), "description": ""})
	_set_text(drawer, "VBox/HeaderBar/OrderBadge", "%s · %s\n战果 %s" % [player.master.get("name", player.player_name), player.servant_class, BaseNumber.display_text(player.score)])
	var hint: Label = drawer.get_node("VBox/IdentityHint")
	hint.text = "真名已解放" if player.get("servant_released", false) else "真名未解放"
	hint.theme_type_variation = "Gold2" if player.get("servant_released", false) else "Dim2"
	_set_text(drawer, "VBox/ResourceVisuals/MagicH/Magic", "魔力 " + BaseNumber.display_text(player.magic))
	_set_text(drawer, "VBox/ResourceVisuals/CommandSpells", "令咒 ×" + BaseNumber.display_text(player.command_spell_count))
	_set_text(drawer, "VBox/ResourceVisuals/Power", "合计威力 " + BaseNumber.display_text(player.total_power))
	var area_name: String = "未部署"
	for area in view.get("areas", []):
		for loc in area.locations:
			if loc.id == player.location:
				area_name = area.name
	_set_text(drawer, "VBox/ResourceVisuals/BattleMarker", area_name + (" · 交战" if player.is_battle else ""))
	var rows: Array = _drawer_rows()
	var size: Vector2 = _drawer_card_size(rows[0])
	var identities: Control = rows[0].get_node("Scroll/CardsH")
	for key in ["master", "servant"]:
		var slot: TextureRect = identities.get_node("MasterCard" if key == "master" else "ServantCard")
		slot.custom_minimum_size = size
		slot.visible = not player[key].is_empty()
		if slot.visible:
			var card_image: String = player[key].get("image", "") if player[key].get("visible", false) and not player[key].get("concealed", true) else (_back("servant") if key == "servant" and player[key].get("placeholder_kind") == "servant" else "")
			slot.texture = LoadHelper.load_texture(card_image)
			if player[key].get("visible", false) and not player[key].get("concealed", true):
				bind_zoom_for_card(slot, player[key])
			else:
				_disable_card_zoom(slot)
		else:
			slot.texture = null
			_disable_card_zoom(slot)
	rows[0].visible = identities.get_node("MasterCard").visible or identities.get_node("ServantCard").visible
	var sources: Array = []
	for entry in player.get("zone_hand_entries", []):
		if entry is Dictionary and entry.get("card", {}).get("visible", false):
			sources.append(entry.card)
	for i in [1, 2]:
		var cards: Array = player.played_cards if i == 1 else sources
		rows[i].visible = not cards.is_empty()
		_fill_card_row_from_list(_drawer_row_cards(rows[i]), cards, false, player.own, i == 2, size)
	_set_text(rows[1], "Title", "%s 已打出牌 · 威力 %s" % [area_name, BaseNumber.display_text(player.total_power)])
	_bind_drawer_buffs(rows[3], player.get("buffs", []))
	var spell_row: Control = drawer.get_node("VBox/Sections/Row_CommandSpells")
	var special_spells: Array = player.get("special_command_spells", [])
	spell_row.visible = not special_spells.is_empty()
	_fill_card_row_from_list(_drawer_row_cards(spell_row), special_spells, false, player.own, true, size)
	drawer.get_node("VBox/Sections/Row_CommandSpells").visible = not special_spells.is_empty()
	var out_button: Button = drawer.get_node("VBox/BtnOutOfGame")
	if not out_button.has_meta("base_text"):
		out_button.set_meta("base_text", out_button.text)
	var removed: Array = player.get("out_of_game_cards", [])
	out_button.visible = not removed.is_empty()
	out_button.text = "%s ×%d" % [str(out_button.get_meta("base_text")), removed.size()]
	_bind_power_hover(drawer.get_node("VBox/ResourceVisuals/Power"), pid)
	var box: Control = drawer.get_node("VBox")
	var insets: Vector4 = box.get_meta("layout_insets")
	box.offset_left = insets.x
	box.offset_top = insets.y
	box.offset_right = insets.z
	box.offset_bottom = insets.w
	for row in rows:
		_bind_drawer_row_remeasure(row)
	_queue_drawer_remeasure(opponent)

func _bind_drawer_buffs(row: Control, buffs: Array) -> void:
	var list: Control = row.get_node("Scroll/Buffs")
	_fill_buff_rows(list, buffs)
	row.visible = not buffs.is_empty()
	var title: Control = row.get_node("Title")
	row.get_node("Scroll").custom_minimum_size.y = minf(list.get_combined_minimum_size().y, maxf(0.0, _drawer_row_share(_drawer_rows()) - title.get_combined_minimum_size().y - row.get_theme_constant("separation"))) if row.visible else 0.0

## 抽屉分区行，顺序与 DRAWER_ROWS 一致。
func _drawer_rows() -> Array:
	var rows: Array = []
	if _opponent_drawer == null:
		return rows
	for path in DRAWER_ROWS:
		var row := _opponent_drawer.get_node_or_null(path) as Control
		if row != null:
			rows.append(row)
	return rows


## 分区行的卡行（Scroll 内的横排容器）；行结构由 tscn 声明
func _drawer_row_cards(row: Control) -> Control:
	return row.get_node_or_null("Scroll/CardsH") as Control


## 分区行的卡位尺寸：高度铺满行内滚动区，宽度按卡位比例等比。
## 行高由布局决定，抽屉刚打开那一帧还量不到，此时先用模板尺寸兜底
func _drawer_card_size(row: Control) -> Vector2:
	var ratio: float = DRAWER_CARD_WIDTH / DRAWER_CARD_HEIGHT
	var height: float = DRAWER_CARD_HEIGHT
	if row != null:
		var share := _drawer_row_share(_drawer_rows())
		var title := row.get_node_or_null("Title") as Control
		if share > 0.0:
			height = maxf(1.0, floorf(share - (title.get_combined_minimum_size().y if title != null else 0.0) - row.get_theme_constant("separation")))
	return Vector2(floorf(height * ratio), height)


## 分区行的高度由布局决定：行高变化时按新高度重排一次卡位（自收敛，不会与布局互相触发）
func _bind_drawer_row_remeasure(row: Control) -> void:
	var scroll := row.get_node_or_null("Scroll") as Control
	if scroll != null and not scroll.has_meta("drawer_row_remeasure_bound"):
		scroll.set_meta("drawer_row_remeasure_bound", true)
		scroll.resized.connect(_on_drawer_row_resized)


## 行高变了就重排：只有卡位尺寸确实对不上行高时才动手，避免刷新与布局互相触发成自激
func _on_drawer_row_resized() -> void:
	if _opponent_drawer == null or not _opponent_drawer.visible:
		return
	for row in _drawer_rows():
		if not row.visible:
			continue
		var cards_row := _drawer_row_cards(row)
		if cards_row == null or cards_row.get_child_count() == 0:
			continue
		var slot := cards_row.get_child(0) as Control
		if slot != null and absf(slot.custom_minimum_size.y - _drawer_card_size(row).y) > 1.0:
			_update_drawer_visuals(null)
			return


## 分区行的平分份额：内容区高度按当前可见行数平分（随面板与行数变化，不写死像素）
func _drawer_row_share(rows: Array) -> float:
	if _opponent_drawer == null:
		return 0.0
	var sections := _opponent_drawer.get_node_or_null("VBox/Sections") as Control
	if sections == null:
		return 0.0
	var visible := 0
	for row in rows:
		if (row as Control).visible:
			visible += 1
	if visible == 0:
		return 0.0
	var box := _opponent_drawer.get_node("VBox") as VBoxContainer
	var insets: Vector4 = box.get_meta("layout_insets")
	var available := _opponent_drawer.size.y - insets.y + insets.w
	var visible_children := 0
	for child in box.get_children():
		if child is Control and child.visible:
			visible_children += 1
			if child != sections:
				available -= child.get_combined_minimum_size().y
	available -= box.get_theme_constant("separation") * maxi(0, visible_children - 1)
	available -= sections.get_theme_constant("separation") * maxi(0, visible - 1)
	var equitable_share := available / float(visible)
	var card_rows := 0
	for row: Control in rows:
		if not row.visible:
			continue
		if _drawer_row_cards(row) != null:
			card_rows += 1
			continue
		var scroll := row.get_node("Scroll") as ScrollContainer
		var title := row.get_node("Title") as Control
		var content_height := (scroll.get_child(0) as Control).get_combined_minimum_size().y if scroll.get_child_count() > 0 else 0.0
		available -= minf(equitable_share, content_height + title.get_combined_minimum_size().y + row.get_theme_constant("separation"))
	return maxf(1.0, available / float(card_rows)) if card_rows > 0 else maxf(1.0, equitable_share)


## 行高要等这一帧布局算完才准：尺寸还未知时下一帧补一次重算，让卡位真正铺满行。
## meta 防重，避免刷新与布局互相触发成自激
func _queue_drawer_remeasure(opponent_card) -> void:
	if _opponent_drawer == null or not _opponent_drawer.visible:
		return
	if _drawer_layout_ready():
		_opponent_drawer.remove_meta("drawer_remeasure_queued")
		return
	if _opponent_drawer.has_meta("drawer_remeasure_queued"):
		return
	_opponent_drawer.set_meta("drawer_remeasure_queued", true)
	call_deferred("_update_drawer_visuals", opponent_card)


## 是否已有可见分区量到高度（说明这一轮布局完成）
func _drawer_layout_ready() -> bool:
	for row in _drawer_rows():
		if not row.visible:
			continue
		var scroll := row.get_node_or_null("Scroll") as Control
		if scroll != null and scroll.size.y > 0.0:
			return true
	return false


## 两种来源共用当前过滤投影；不读取规则玩家，也不补全缺失的卡面声明。
func _on_drawer_out_of_game_pressed() -> void:
	if _opponent_drawer == null or _selected_opponent_id < 0:
		return
	if _source_is_local and _source != null:
		_source.invalidate()
	var view: Dictionary = _source.read_view() if _source != null else {}
	var btn := _opponent_drawer.get_node_or_null("VBox/BtnOutOfGame") as Button
	var title := str(btn.get_meta("base_text", btn.text)) if btn != null else ""
	for player in view.get("players", []):
		if int(player.get("id", -1)) == _selected_opponent_id:
			_show_card_browser(title, player.get("out_of_game_cards", []))
			return


## 合计威力标签：悬浮显示威力构成明细（复用场景里的 PowerTooltip 与引擎的明细接口，
## 与本地资源栏同一份口径）；抽屉在屏幕右侧，面板优先贴标签左侧并在视口内 clamp
func _bind_power_hover(label: Control, player_id: int, include_selected_preview: bool = false) -> void:
	if label == null or _power_tooltip == null:
		return
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.set_meta("power_hover_player_id", player_id)
	if label.has_meta("power_hover_bound"):
		return
	label.set_meta("power_hover_bound", true)
	label.mouse_entered.connect(func():
		var pid := int(label.get_meta("power_hover_player_id", -1))
		if pid < 0 or (network_session == null and not GameData.player_data_library.has(pid)):
			return
		var preview_power := 0
		var preview_cards: Array = []
		var preview_hidden: Array = []
		if include_selected_preview and pid == _local_player_id:
			preview_power = _selected_cards_power()
			preview_cards = _selected_cards.duplicate()
			preview_hidden = _selected_cards_hidden()
		var lines: Array = _network_presenter.power_lines(_network_presenter.player_view(pid)) if network_session != null else GetPlayerTotalPower.breakdown_lines(pid, preview_power, preview_cards, preview_hidden)
		_set_text(_power_tooltip, "VBox/Desc", "\n".join(lines) if not lines.is_empty() else "当前无威力")
		var rect := label.get_global_rect()
		var panel_size := _power_tooltip.size
		var vp := get_viewport_rect().size
		var px: float = rect.position.x - panel_size.x - 8.0
		if px < 8.0:
			px = rect.end.x + 8.0
		px = clampf(px, 8.0, maxf(8.0, vp.x - panel_size.x - 8.0))
		var py: float = clampf(rect.get_center().y - panel_size.y * 0.5, 8.0, maxf(8.0, vp.y - panel_size.y - 8.0))
		_power_tooltip.global_position = Vector2(px, py)
		_power_tooltip.show()
	)
	label.mouse_exited.connect(func():
		_power_tooltip.hide()
	)


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
			# 先显示再刷新：分区行的高度要等布局算完，刷新里的"下一帧补算"才排得上
			_opponent_drawer.visible = true
			_update_drawer_visuals(child)
			if _board != null:
				_board.visible = false
			break


# --- 通用卡位填充（搬运自旧控制器） ---
func _fill_card_row_from_list(row: Control, cards: Array, clickable: bool, owned: bool = true, merge_repeated: bool = true, card_size := Vector2(DRAWER_CARD_WIDTH, DRAWER_CARD_HEIGHT)) -> void:
	if row == null:
		return
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	var list: Array = _group_repeated_cards(cards) if merge_repeated else cards.map(func(c): return {"card": c, "count": 1})
	for entry in list:
		var slot := TextureRect.new()
		slot.custom_minimum_size = card_size
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
		if card is Dictionary:
			# 不依赖规则对象 _name；隐藏条目不按空名称合并。
			var match_index: int = -1
			if card.get("visible", false):
				for i in out.size():
					var existing = out[i].get("card")
					if not existing is Dictionary or not existing.get("visible", false):
						continue
					var same: bool = true
					for field in ["name", "image", "back_image", "concealed", "cost", "power", "description", "zoom_kind"]:
						if existing.get(field) != card.get(field):
							same = false
							break
					if same:
						match_index = i
						break
			if match_index >= 0:
				out[match_index]["count"] += 1
			else:
				out.append({"card": card, "count": 1})
			continue
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


# --- 共用独立日志文本模块（供战报 / 日志弹窗复用） ---
static func _format_game_log_line(e: Dictionary) -> String:
	return GameLogText.line(e)


# --- 战区点击（消费位置等待 / 部署 / 移动） ---
func _on_battlefield_clicked(target_area_idx: int) -> void:
	if _is_progress_blocked():
		return
	var pending_loc: Dictionary = _source.read_pending() if _source != null else {}
	if pending_loc.get("kind") == "location_choice":
		var areas: Array = _source.read_view().get("areas", [])
		if target_area_idx < 0 or target_area_idx >= areas.size(): return
		var area: int = int(areas[target_area_idx].get("id", -1))
		if not _source_is_local:
			get_node("NetworkChoices/Panel").choose_area(area)
		else:
			_check_waiting_location_selection()
			_submit_location_choice(area,_location_choice_prompt,_location_choice_generation,_battle_command_epoch)
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
	return AreaActionRules.block_reason(_local_player_id, target_area_idx)


func _prepare_battlefield_deploy_confirm(target_area_idx: int) -> void:
	var area: BaseMapArea = MapData.areas[target_area_idx]
	var target_loc: BaseLocation = DeployRules.pick_location(area)
	if target_loc == null:
		_show_tactical_confirm("【%s】没有可用的部署席位" % area._area_name, true)
		return
	_pending_tactical_action = {"type": "deploy", "target_loc": target_loc, "area_name": area._area_name}
	var parts: Array[String] = []
	var mg: int = _num(target_loc._magic)
	var bn: int = GetEffectiveLocationBenefit.current_benefit(target_loc)
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
	var curr_area: BaseMapArea = AreaActionRules.current_area(pl_data)
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
	var cost: int = AreaActionRules.estimate_move_cost(pl_data, step_diff)
	if not AreaActionRules.magic_enough_for_move(pl_data, cost):
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


# --- 结束行动：共同 source/command，不迁移部署后的结束链 ---
func _on_end_phase_pressed() -> void:
	if not _end_command_available():
		return
	_submit_battle_command("end_action", {})

## 同步本地/host 与异步 guest 复用同一个单请求 attempt。
func _submit_battle_command(kind: String, args: Dictionary, end_after_deploy: bool = false) -> void:
	if not _battle_command_input_available(kind):
		return
	var adapter = _battle_commands
	var epoch: int = _battle_command_epoch
	var attempt: Dictionary = {"epoch": epoch, "kind": kind, "request_id": 0, "buffer": [], "settled": false, "end_after_deploy": end_after_deploy, "args": args.duplicate(true)}
	if kind == "play_group" and _card_select_request.get("regular", false):
		attempt["regular_prompt"] = _card_select_request.duplicate(true)
	_end_command_attempt = attempt
	_update_end_command_button()
	_refresh_player_choice_lock()
	_refresh_active_choice_lock()
	_refresh_broadcast_continue()
	if kind == "broadcast_confirm_absent":
		var sent: Error = network_session.request(kind, args, _register_broadcast_absent_attempt.bind(attempt))
		if sent != OK and not attempt.settled:
			_settle_end_command(attempt, false, "代确认请求发送失败：" + error_string(sent))
		return
	var request_id: int = adapter.submit(kind, args)
	if attempt.settled or epoch != _battle_command_epoch or adapter != _battle_commands:
		return
	attempt.request_id = request_id
	for reply in attempt.buffer:
		if reply[0] == request_id:
			_settle_end_command(attempt, reply[1], reply[2])
			break
	attempt.buffer.clear()

func _register_broadcast_absent_attempt(sequence: int, attempt: Dictionary) -> void:
	if attempt.settled or attempt.epoch != _battle_command_epoch or _end_command_attempt != attempt: return
	attempt.request_id = sequence

func _on_broadcast_management_result(sequence: int, ok: bool, reason: String) -> void:
	if not _end_command_attempt.is_empty() and _end_command_attempt.get("kind") == "broadcast_confirm_absent" and _end_command_attempt.get("request_id") == sequence:
		_settle_end_command(_end_command_attempt, ok, reason)

func _run_battle_command(method: String, argv: Array, context: SessionContext):
	# dispatcher 唯一规则执行桥：显式契约，不通过反射掩盖不支持的命令。
	match method:
		"submit_group": return _commands.submit_group(argv[0], argv[1], argv[2], context)
		"request_manual_activation": return _commands.request_manual_activation(argv[0], argv[1])
		"set_card_concealed": _commands.set_card_concealed(argv[0], argv[1], argv[2])
		"move": _commands.move(argv[0], argv[1])
		"deploy_to_area": return _commands.deploy_to_area(argv[0], argv[1])
		"submit_option_choice": return _commands.submit_option_choice(argv[0], argv[1], argv[2])
		"submit_active_choice": return _commands.submit_active_choice(argv[0], argv[1])
		"cancel_pending_choice": return _commands.cancel_pending_choice(argv[0])
		"submit_card_selection": return _commands.submit_card_selection(argv[0], argv[1])
		"submit_player_selection": return _commands.submit_player_selection(argv[0], argv[1])
		"submit_location_selection": return _commands.submit_location_selection(argv[0], argv[1])
		"confirm_battle_broadcast": _commands.confirm_battle_broadcast(argv[0])
		"end_current_player_action": return _commands.end_current_player_action()
	return false

func _read_battle_command_sequence():
	return _source.read_view().get("seq") if _source != null else null

## 生命周期通知栈之外显式构造；普通快照不退休/结算。
func _rebuild_battle_commands() -> void:
	if _battle_commands_stopped or _battle_commands_retiring or _battle_commands_invalidating or _source == null:
		return
	var observer: int = _local_player_id
	if not _source_is_local:
		var view: Dictionary = _source.read_view()
		observer = int(view.get("observer", -1))
		if _battle_commands != null and observer != _battle_command_observer:
			_retire_battle_commands("观察座位已变化，执行结果未知")
		if network_session == null or network_session.view.get("phase") != "playing" or observer < 0 or not view.get("seq") is int or not _network_battle_input_available("confirm_broadcast"):
			_update_end_command_button()
			return
	if _battle_commands != null:
		return
	_battle_command_epoch += 1
	_battle_command_observer = observer
	if _source_is_local:
		var dispatcher = preload("res://scripts/match/match_command_dispatcher.gd").new(EffectManager.is_card_selection_valid, EffectManager.location_option_origin_allowed)
		_battle_commands = preload("res://scripts/game_scene/battle_io/local_battle_commands.gd").new(observer, _held_action_ids, dispatcher, _run_battle_command, GameStart.startup_context())
	else:
		_battle_commands = preload("res://scripts/game_scene/battle_io/network_battle_commands.gd").new(network_session, _read_battle_command_sequence)
		if not network_session.request_completed.is_connected(_on_broadcast_management_result):
			network_session.request_completed.connect(_on_broadcast_management_result)
	_battle_command_result = _on_battle_command_result.bind(_battle_commands, _battle_command_epoch)
	_battle_commands.result.connect(_battle_command_result)
	_update_end_command_button()

func _on_battle_command_result(request_id: int, ok: bool, reason: String, adapter, epoch: int) -> void:
	if adapter != _battle_commands or epoch != _battle_command_epoch or _end_command_attempt.is_empty():
		return
	if _end_command_attempt.get("kind") == "broadcast_confirm_absent": return
	var attempt: Dictionary = _end_command_attempt
	if attempt.settled:
		return
	if attempt.request_id == 0:
		attempt.buffer.append([request_id, ok, reason])
	elif attempt.request_id == request_id:
		_settle_end_command(attempt, ok, reason)

func _settle_end_command(attempt: Dictionary, ok: bool, reason: String) -> void:
	if attempt.settled:
		return
	attempt.settled = true
	_end_command_attempt = {}
	if ok and not _battle_commands_stopped and not _battle_commands_retiring and attempt.get("kind") == "play_group":
		_complete_held_group(attempt)
		if attempt.has("regular_prompt") and attempt.regular_prompt == _card_select_request:
			_card_select_request = {}
			_card_select_picked = []
			_card_select_hidden = {}
			_card_select_submit = Callable()
			_card_select_panel.hide()
	if _source_is_local and not _battle_commands_stopped and not _battle_commands_retiring and attempt.get("kind") in ["player_choice", "card_choice", "location_choice", "cancel_choice", "option_choice", "active_choice"]:
		if _source != null: _source.invalidate()
		_check_waiting_player_selection()
		_check_waiting_card_selection()
		_check_waiting_location_selection()
		_check_waiting_effects()
	if not ok and not _battle_commands_stopped:
		_say(reason if not reason.is_empty() else "操作未确认，请查看当前局面")
	if not _battle_commands_stopped and not _battle_commands_retiring:
		refresh_all_ui()
		if _source_is_local and attempt.get("kind") == "activate":
			_process_waiting_inputs(0.0)
	_update_end_command_button()
	_refresh_broadcast_continue()
	# 部署成功与结束是两条独立权威命令；拒绝、退休、退出均不续发。
	if ok and attempt.get("kind") == "deploy" and attempt.get("end_after_deploy", false) and attempt.get("epoch") == _battle_command_epoch and _end_command_available():
		_submit_battle_command("end_action", {})

func _retire_battle_commands(reason: String) -> void:
	_battle_commands_retiring = true
	if _battle_commands != null:
		if not _source_is_local:
			_battle_commands.close()
		if not _end_command_attempt.is_empty():
			_settle_end_command(_end_command_attempt, false, reason)
		if _battle_commands.result.is_connected(_battle_command_result):
			_battle_commands.result.disconnect(_battle_command_result)
	_battle_commands = null
	_battle_command_result = Callable()
	_battle_command_epoch += 1
	_battle_commands_retiring = false
	_update_end_command_button()

func _on_battle_commands_invalidated(_generation: int, _reason: String) -> void:
	_battle_commands_invalidating = true
	_retire_battle_commands("会话请求关联已失效，执行结果未知；不自动重发")
	# session 正在同步重置，不在其通知栈中用旧视图建实例。
	call_deferred("_resume_battle_command_rebuild", _battle_command_epoch)

func _resume_battle_command_rebuild(epoch: int) -> void:
	if epoch != _battle_command_epoch or _battle_commands_stopped:
		return
	_battle_commands_invalidating = false
	_rebuild_battle_commands()

func _stop_battle_commands() -> void:
	_battle_commands_stopped = true
	_retire_battle_commands("界面退出，执行结果未知；不自动重发")
	if network_session != null and network_session.request_associations_invalidated.is_connected(_on_battle_commands_invalidated):
		network_session.request_associations_invalidated.disconnect(_on_battle_commands_invalidated)
	if network_session != null and network_session.request_completed.is_connected(_on_broadcast_management_result):
		network_session.request_completed.disconnect(_on_broadcast_management_result)

func _battle_command_input_available(kind: String = "") -> bool:
	if _battle_commands_stopped or _battle_commands_retiring or _battle_commands_invalidating or _battle_commands == null or _source == null or not _end_command_attempt.is_empty():
		return false
	if not _source_is_local:
		var view: Dictionary = _source.read_view()
		if network_session.view.get("phase") != "playing" or int(view.get("observer", -1)) != _battle_command_observer or _battle_command_observer < 0 or not view.get("seq") is int or not _network_battle_input_available(kind):
			return false
	return true

## 本人确认/显式管理确认允许断线等待；普通行动保持原可用性闸门。
func _network_battle_input_available(kind: String) -> bool:
	if network_session == null: return false
	if kind not in ["confirm_broadcast", "broadcast_confirm_absent"]:
		return network_session.match_commands_available()
	if not network_session.transport.is_connected_to_host(): return false
	var actions: Dictionary = _source.read_actions()
	return not actions.get("guard", {}).get("paused", false) and not actions.get("management_paused", false)

func _end_command_available() -> bool:
	return _battle_command_input_available() and bool(_source.read_actions().get("can_end", false)) and _source.read_pending().is_empty()

func _update_end_command_button() -> void:
	if _ops != null:
		(_ops.get_node("EndButton") as Button).disabled = not _end_command_available()


# -----------------------------------------------------------------------------
# 出牌区新排版：一玩家一行 + 装饰条 + 动态统一卡尺寸 + 区域溢出滚动
# -----------------------------------------------------------------------------
## 与回合末留场判据一致，读取显式残留效果，不改变真实 played_cards。
func _is_residue_card(card) -> bool:
	return card is BaseHandCard and not card._is_closed and not card._is_concealed \
		and card._effects.any(func(effect): return effect._is_residue)


func _current_played_cards(pid: int) -> Array:
	return (_pl(pid).get("played_cards", []) as Array).filter(func(card): return not _is_residue_card(card))


func _residue_pile(parent: Control, node_name: String) -> Control:
	var pile := parent.get_node_or_null(NodePath(node_name)) as Control
	if pile == null:
		pile = _spawn("ResiduePile", parent)
		pile.name = node_name
		pile.get_node("Collapse").pressed.connect(_on_residue_toggle.bind(pile))
	return pile


func _on_residue_toggle(pile: Control) -> void:
	_set_group_spread(pile, not bool(pile.get_meta("expanded", false)))


func _bind_residue_piles() -> void:
	var view: Dictionary = _source.read_view() if _source != null else {}
	_bind_residue_entries(view.get("players", []), int(view.get("observer", -1)), true)

## 只接已判定牌区；网络输入为权威过滤卡视图，布局与输入仍走原模板。
func _bind_residue_entries(entries: Array, observer: int, network: bool) -> void:
	_local_player_id = observer
	var active: Array = []
	for entry in entries:
		active.append(entry.id)
	var local := get_node_or_null("LocalResiduePile") as Control
	if local != null and not active.has(observer):
		local.hide()
	# 绘制 z_index 不改变鼠标命中顺序，顺位栏须排在卷轴之后。
	if _rivals.get_index() < _strips.get_index():
		move_child(_rivals, _strips.get_index() + 1)
	for entry in entries:
		var id: int = entry.id
		var cards: Array = entry.get("residue_cards", [])
		var parent := self as Control if id == _local_player_id else _rival_card(id)
		if parent == null:
			continue
		var node_name := "LocalResiduePile" if id == _local_player_id else "ResiduePile"
		if cards.is_empty() and not parent.has_node(NodePath(node_name)):
			continue
		var pile := _residue_pile(parent, node_name)
		pile.visible = not cards.is_empty()
		pile.set_meta("player_id", id)
		_bind_played_cards_row(pile.get_node("Cards/Row"), cards, id, network)
		if cards.is_empty():
			pile.set_meta("expanded", false)
			continue
		if id == _local_player_id:
			# 用户标注的右侧空位：提示下沿与技能牌上沿之间，不移动相邻面板。
			var left := _master.get_rect().end.x + HELD_GAP
			var right := _ops.get_rect().position.x - HELD_GAP
			var top := ($Hint as Control).get_rect().end.y + 8.0
			var bottom := size.y - (_tpl.get_node("ZoneCard") as Control).size.y - HELD_GAP * 2.0
			pile.position = Vector2(left, top)
			pile.size = Vector2(maxf(1.0, right - left), maxf(1.0, minf((_tpl.get_node("ResiduePile") as Control).size.y, bottom - top)))
		else:
			# 真正挂在玩家信息卡下面，所有平移、下抽、回绕与淡出天然同步。
			pile.position = Vector2(0, parent.size.y + 6.0)
			pile.size.x = parent.size.x
		_layout_residue_pile(pile)


func _layout_residue_pile(pile: Control) -> void:
	var row := pile.get_node("Cards/Row") as Control
	var box := pile.get_node("Cards") as ScrollContainer
	var expanded := bool(pile.get_meta("expanded", false))
	var collapse := pile.get_node("Collapse") as TextureButton
	if collapse.visible != expanded:
		collapse.visible = expanded
		if expanded:
			collapse.modulate.a = 0.0
			collapse.create_tween().tween_property(collapse, "modulate:a", 1.0, 0.15)
	box.offset_right = -collapse.size.x - 4.0 if expanded else 0.0
	var card_size: Vector2 = pile.get_meta("card_size")
	card_size *= minf(1.0, maxf(1.0, pile.size.y - box.offset_top) / card_size.y)
	var step := card_size.x + float(pile.get_meta("card_gap")) if expanded else minf(card_size.x * float(pile.get_meta("stack_step_ratio")), maxf(0.0, pile.size.x - card_size.x) / maxi(1, row.get_child_count() - 1))
	row.custom_minimum_size = Vector2(card_size.x + maxi(0, row.get_child_count() - 1) * step, card_size.y)
	for i in range(row.get_child_count()):
		var slot := row.get_child(i) as Control
		slot.custom_minimum_size = Vector2.ZERO
		slot.size = card_size
		_tween_vec(slot, &"position", Vector2(i * step, 0), "residue_position")


func _bind_groups(area: Dictionary, content: Control) -> void:
	var region := content.get_node_or_null("Groups/List") as Control
	if region == null:
		region = content.get_node_or_null("Groups") as Control
		if region == null:
			return
	var view: Dictionary = _source.read_view() if _source != null else {}
	var occupants: Array = []
	for location in area.get("locations", []):
		occupants.append_array(location.get("players", []))
	var active_keys: Array[String] = []
	for player in view.get("players", []):
		var residue_ids: Array = player.get("residue_cards", []).map(func(card): return card.id)
		var played: Array = player.get("played_cards", []).filter(func(card): return not residue_ids.has(card.id))
		if not occupants.has(player.id) or played.is_empty():
			continue
		var pid: int = int(player.id)
		var key := "Player_%d" % pid
		active_keys.append(key)
		var grp := region.get_node_or_null(key) as Control
		if grp == null:
			grp = _spawn("PlayGroup", region)
			grp.name = key
			grp.set_meta("player_id", pid)
			var who := grp.get_node("Who") as Control
			who.mouse_filter = Control.MOUSE_FILTER_STOP
			who.tooltip_text = "点击展开或收起出牌"
			who.gui_input.connect(_on_play_group_toggle.bind(grp))
			who.get_node("Avatar/CollapseHint").gui_input.connect(_on_play_group_toggle.bind(grp))
		_bind_player_row(grp, pid)
	for grp in region.get_children():
		if not active_keys.has(str(grp.name)):
			region.remove_child(grp)
			grp.queue_free()
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
	var view: Dictionary = _source.read_view() if _source != null else {}
	var player: Dictionary = {}
	for candidate in view.get("players", []):
		if candidate.id == pid:
			player = candidate
	var residue_ids: Array = player.get("residue_cards", []).map(func(card): return card.id)
	var played: Array = player.get("played_cards", []).filter(func(card): return not residue_ids.has(card.id))
	var who := grp.get_node("Who") as Control
	var expanded := bool(grp.get_meta("expanded", false))
	who.get_node("Avatar/CollapseHint").visible = expanded
	who.tooltip_text = "点击头像收起牌堆" if expanded else "点击牌堆或头像展开"
	# 已启动的头像由卷轴自身裁切并随其移动，不在展开结束时重新显现。
	var avatar := who.get_node("Avatar") as Control
	_bind_avatar(avatar, str(player.get("avatar", "")), "AvatarMana" if pid == _local_player_id else "AvatarGold3")
	var head_img: String = str(player.get("avatar", ""))
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
	_set_text(who, "Total/Text", BaseNumber.display_text(player.get("total_power", 0)))
	var cards_box := grp.get_node("Cards") as Control
	var cards_row := cards_box.get_node("Row") as Control
	_bind_played_cards_row(cards_row, played, pid, true)


## 同一绑定供中央出牌与残留小牌堆复用，朝向、说明和点击权限不分叉。
func _bind_played_cards_row(cards_row: Control, played: Array, pid: int, animate: bool = false) -> void:
	for slot in cards_row.get_children():
		var existing = _meta_or(slot, "card", null)
		if not played.any(func(card): return _same_card(card, existing)):
			cards_row.remove_child(slot)
			slot.queue_free()
	for k in range(played.size()):
		var card = played[k]
		var slot := _played_card_slot(cards_row, card)
		cards_row.move_child(slot, k)
		# 正反面只读取真实明暗状态；是否未知与闭眼遮罩独立，已出牌不挂闭眼。
		var concealed: bool = card.get("concealed", true) if card is Dictionary else bool(card.get("_is_concealed"))
		var image: String
		if card is Dictionary:
			image = card.get("image", "") if card.get("visible", false) and not concealed else card.get("back_image", "")
		else:
			image = _back("attack" if card is BaseAttack else "skill") if concealed else str(card.get("_card_img"))
		_bind_card(slot, image)
		_sync_overlay(slot, false, "ConcealOverlay", CONCEAL_COLOR, CONCEAL_ICON)
		var input_card = card
		if _source_is_local and card is Dictionary:
			input_card = null
			var view: Dictionary = _source.read_view()
			for player in view.get("players", []):
				if player.id != pid:
					continue
				var projected: Array = player.get("played_cards", [])
				var objects: Array = (_pl(pid).get("played_cards", []) as Array).filter(func(item): return item is BaseCard)
				# MatchViewBuilder.cards 保序且只过滤非 BaseCard。仅供既有本地输入，不能用于牌面。
				if projected.size() == objects.size():
					for j in projected.size():
						if projected[j].id == card.id:
							input_card = objects[j]
				break
		slot.set_meta("card_object", input_card)
		slot.set_meta("card", card)
		slot.set_meta("card_owner", pid)
		# 本地投影仅复用当前会话已绑定的本人对象；网络绝不反查本机。
		var history_authorized := _source_is_local and network_session == null and pid == _local_player_id
		if card is Dictionary:
			history_authorized = history_authorized and card.get("visible", false) and not concealed \
				and input_card is BaseHandCard and _held_action_ids != null and _held_action_ids.id_for(input_card) == card.id
		_sync_card_modification_badge(slot, input_card, history_authorized if _source_is_local else pid == _local_player_id, "played_cards")
		slot.visible = true
		if not (card is BaseCard or card is Dictionary):
			_disable_card_zoom(slot)
		else:
			bind_zoom_for_card(slot, card)
			if concealed:
				slot.set_meta("zoom_img", image)
		if animate:
			_note_played_card_takeoff(slot, card, pid)


## 取该卡对象对应的出牌槽位：已有就复用，没有才新建
func _same_card(card, existing) -> bool:
	if card is Dictionary and existing is Dictionary:
		return card.has("id") and existing.has("id") and card.id == existing.id
	if card is Dictionary or existing is Dictionary:
		return false
	return card == existing

func _played_card_slot(cards_row: Control, card) -> Control:
	for slot in cards_row.get_children():
		var existing = _meta_or(slot, "card", null)
		if _same_card(card, existing):
			return slot
	var slot := _spawn("PlayedCard", cards_row)
	slot.set_meta("card", card)
	for child in slot.find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.gui_input.connect(_on_played_card_input.bind(slot))
	# 与技能栏共用主动效果选择入口；按钮保持隐藏，不改变已出牌布局。
	_bind_effect_button(slot)
	return slot


## 自己已打出的牌可通过真实卡位发动阶段能力；他人的牌与失效旧槽位只供查看。
func _on_played_card_input(event: InputEvent, slot: Control) -> void:
	var group := slot.get_parent().get_parent().get_parent() as Control
	var direction := _wheel_direction(event)
	if direction != 0:
		_wheel_scroll(group.get_node("Cards") as ScrollContainer, direction)
		slot.accept_event()
		return
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not bool(group.get_meta("expanded", false)):
		_set_group_spread(group, true)
		slot.accept_event()
		return
	if not _held_input_available() or int(slot.get_meta("card_owner", -1)) != _local_player_id:
		return
	var card = _meta_or(slot, "card", null)
	if network_session != null:
		if _network_presenter.played_card_live(slot):
			_on_held_effect_pressed(slot)
			slot.accept_event()
		return
	card = _meta_or(slot, "card_object", null)
	if not (_pl(_local_player_id).get("played_cards", []) as Array).has(card):
		return
	_on_held_effect_pressed(slot)
	slot.accept_event()


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
	var cid: int = int(card.id) if card is Dictionary else card.get_instance_id()
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
		await get_tree().create_timer(FLY_INTERVAL, false).timeout
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
	var start_pos := _takeoff_origin(pid, _meta_or(slot, "card_object", card) if _source_is_local else card)
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
			if _same_card(_meta_or(slot as Control, "card", null), card):
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
	var left := PLAYED_AREA_MARGIN
	var events := strip.get_node_or_null("EventIcons") as Control
	if events != null and events.visible and events.get_child_count() > 0:
		for event_card: Control in events.get_children():
			left = maxf(left, event_card.position.x + event_card.size.x * event_card.scale.x + PLAYED_AREA_MARGIN)
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


## 小签的负左锚点与最小宽度都可能向外伸出；只为正式出牌行预留所需内边距。
func _played_badge_left_padding(card_width: float) -> float:
	var badge := _tpl.get_node("PlayedCard/CardModificationBadge") as Control
	var anchored_width := (badge.anchor_right - badge.anchor_left) * card_width + badge.offset_right - badge.offset_left
	var extra_width := maxf(0.0, badge.get_combined_minimum_size().x - anchored_width)
	var grow_left := extra_width if badge.grow_horizontal == Control.GROW_DIRECTION_BEGIN else 0.0
	if badge.grow_horizontal == Control.GROW_DIRECTION_BOTH:
		grow_left = extra_width * 0.5
	return ceilf(maxf(0.0, -badge.anchor_left * card_width - badge.offset_left + grow_left))


## 各玩家组按实际宽高装箱，每行整体居中；求解与最终布局共用这些矩形。
func _packed_play_rows(units: Array[Vector2], card_h: float, avail_w: float, max_per_row: int, left_padding := 0.0) -> Array[Rect2]:
	var side_gap := maxf(card_h * PLAYED_SIDE_GAP_RATIO, PLAYED_SIDE_GAP_MIN)
	var result: Array[Rect2] = []
	var line_start := 0
	var cur_x := 0.0
	var cur_y := 0.0
	var line_h := 0.0
	var remaining_rows := ceili(float(units.size()) / maxi(1, max_per_row))
	var line_limit := ceili(float(units.size()) / maxi(1, remaining_rows))
	for unit in units:
		var grp_w := card_h * (PLAYED_AVATAR_W_RATIO + unit.x) + side_gap + left_padding
		if cur_x > 0.0 and (cur_x + grp_w > avail_w or result.size() - line_start >= line_limit):
			var shift := maxf(0.0, (avail_w - cur_x + side_gap) * 0.5)
			for j in range(line_start, result.size()):
				result[j].position.x += shift
			cur_y += line_h + card_h * PLAYED_ROW_GAP_RATIO
			line_start = result.size()
			remaining_rows = maxi(1, remaining_rows - 1)
			line_limit = mini(maxi(1, max_per_row), ceili(float(units.size() - line_start) / remaining_rows))
			cur_x = 0.0
			line_h = 0.0
		result.append(Rect2(Vector2(cur_x, cur_y), Vector2(grp_w, card_h * unit.y)))
		line_h = maxf(line_h, card_h * unit.y)
		cur_x += grp_w + side_gap
	var shift := maxf(0.0, (avail_w - cur_x + side_gap) * 0.5)
	for j in range(line_start, result.size()):
		result[j].position.x += shift
	return result

## 同时检验全部组的宽高，求可用区域内最大的统一卡高。
func _band_card_h(band: Rect2, units: Array[Vector2], max_per_row: int, card_aspect := 0.0) -> float:
	if units.is_empty() or band.size.x <= 1.0 or band.size.y <= 1.0:
		return 0.0
	var low := 0.0
	var high := band.size.y
	for iteration in range(18):
		var height := (low + high) * 0.5
		var fits := true
		var left_padding := _played_badge_left_padding(height * card_aspect) if card_aspect > 0.0 else 0.0
		for placed in _packed_play_rows(units, height, band.size.x, max_per_row, left_padding):
			if placed.end.x > band.size.x or placed.end.y > band.size.y:
				fits = false
				break
		if fits:
			low = height
		else:
			high = height
	return low

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
		node.set(prop, target)
		return
	var t := node.create_tween()
	t.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(node, String(prop), target, FLY_SECONDS)
	node.set_meta(key + "_tw", t)

## 三条互不重叠的可用带：御主左侧、御主上方、御主右侧。
## 只让实际碰到席位的带缩短，不把两侧一并截在御主头顶。
func _played_layout_bands(strip: Control, origin: Vector2, extent: Vector2) -> Array[Rect2]:
	var master_rect := _master.get_global_rect().grow(HELD_GAP)
	var left_end := clampf(master_rect.position.x - origin.x, 0.0, extent.x)
	var right_start := clampf(master_rect.end.x - origin.x, left_end, extent.x)
	var top_end := clampf(master_rect.position.y - origin.y, 0.0, extent.y)
	var bands: Array[Rect2] = [
		Rect2(0, 0, left_end, extent.y),
		Rect2(left_end, 0, right_start - left_end, top_end),
		Rect2(right_start, 0, extent.x - right_start, extent.y),
	]
	for i in range(bands.size()):
		for row_name in ["MeleeScroll", "SeatScroll"]:
			var seat := strip.get_node("Seats/" + row_name) as Control
			if not seat.visible:
				continue
			var obstacle := seat.get_global_rect().grow(PLAYED_AREA_MARGIN)
			obstacle.position -= origin
			if bands[i].intersects(obstacle):
				# 席位仅占左下局部：优先使用席位右缘与御主左缘之间的竖向空间。
				if i == 0 and obstacle.end.x < bands[i].end.x:
					var right := bands[i].end.x
					bands[i].position.x = maxf(bands[i].position.x, obstacle.end.x)
					bands[i].size.x = right - bands[i].position.x
				else:
					bands[i].size.y = maxf(0.0, obstacle.position.y)
		var pad := minf(PLAYED_AREA_PADDING, minf(bands[i].size.x, bands[i].size.y) * 0.1)
		bands[i] = bands[i].grow(-pad)
	return bands


## 枚举左右人数相差不超过一人的分配，取可容纳最大卡面的方案。
func _solve_played_bands(bands: Array[Rect2], units: Array[Vector2], card_aspect := 0.0) -> Dictionary:
	var best_height := 0.0
	var best_counts: Array[int] = []
	for left_count in range(units.size() + 1):
		for right_count in range(maxi(0, left_count - 1), mini(units.size() - left_count, left_count + 1) + 1):
			var middle_count := units.size() - left_count - right_count
			if units.size() == 1 and middle_count != 1:
				continue
			var counts: Array[int] = [left_count, middle_count, right_count]
			var start := 0
			var height := INF
			for i in range(bands.size()):
				if counts[i] > 0:
					height = minf(height, _band_card_h(bands[i], units.slice(start, start + counts[i]), 1, card_aspect))
				start += counts[i]
			if height > best_height:
				best_height = height
				best_counts = counts
	var placements: Array[Rect2] = []
	var start := 0
	for i in range(best_counts.size()):
		var batch := units.slice(start, start + best_counts[i])
		var left_padding := _played_badge_left_padding(best_height * card_aspect) if card_aspect > 0.0 else 0.0
		var local_rects := _packed_play_rows(batch, best_height, bands[i].size.x, 1, left_padding)
		for placed in local_rects:
			placed.position = bands[i].position + Vector2(0, placed.position.y)
			placements.append(placed)
		start += best_counts[i]
	return {"height": best_height, "placements": placements, "counts": best_counts}


func _layout_play_groups(groups: Control) -> void:
	if groups == null:
		return
	# 可用矩形取滚动容器自身的尺寸；排容器是它内部唯一的 List
	var list := groups.get_node_or_null("List") as Control
	if list == null:
		return
	var owner_strip := groups.get_parent().get_parent() as Control
	var base_rect := _play_area_rect(owner_strip)
	base_rect.size.y = maxf(1.0, owner_strip.size.y - PLAYED_AREA_MARGIN - base_rect.position.y)
	groups.position = base_rect.position
	groups.size = base_rect.size
	if groups.size.x <= 1.0 or groups.size.y <= 1.0:
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
	var units: Array[Vector2] = []
	for i in range(row_count):
		var group := rows[i] as Control
		var columns := maxi(1, int(group.get_meta("expanded_columns")))
		var shown := mini(counts[i], columns)
		var expanded_width := shown * aspect + maxi(0, shown - 1) * PLAYED_CARD_GAP_RATIO
		var card_rows := ceili(float(counts[i]) / columns)
		var visible_rows := mini(card_rows, maxi(1, int(group.get_meta("expanded_visible_rows"))))
		var expanded_height := visible_rows + maxi(0, visible_rows - 1) * PLAYED_ROW_GAP_RATIO
		if bool(group.get_meta("expanded", false)):
			units.append(Vector2(expanded_width, expanded_height))
		else:
			var stack_width := aspect + maxf(0.0, counts[i] - 1) * _played_step_ratio(group, counts[i], aspect)
			var reserve := clampf(float(group.get_meta("collapsed_reserve_ratio")), 0.0, 1.0)
			units.append(Vector2(lerpf(stack_width, expanded_width, reserve), 1.0 + minf(1.0, expanded_height - 1.0) * reserve))
	var bands := _played_layout_bands(owner_strip, groups.global_position, groups.size)
	groups.clip_contents = true
	list.clip_contents = true
	var max_per_row := maxi(1, int(groups.get_meta("max_groups_per_row")))
	# 缓存必须包含预留空间与展开行数；换行也会改变统一尺寸。
	var sig := "%s|%d|%d" % [str(bands), row_count, max_per_row]
	for i in range(row_count):
		sig += ",%d:%d:%s" % [counts[i], 1 if (rows[i] as Control).has_meta("shown") else 0, str(units[i])]
	if str(groups.get_meta("layout_sig", "")) == sig:
		return
	groups.set_meta("layout_sig", sig)
	var solution := _solve_played_bands(bands, units, aspect)
	var placements: Array[Rect2] = solution.placements
	if placements.size() != row_count:
		return
	groups.set_meta("layout_bands", bands)
	groups.set_meta("layout_band_counts", solution.counts)
	var card_h: float = solution.height
	var card_w := card_h * aspect
	var badge_left_padding := _played_badge_left_padding(card_w)
	var avatar_w := card_h * PLAYED_AVATAR_W_RATIO
	var side_gap := maxf(card_h * PLAYED_SIDE_GAP_RATIO, PLAYED_SIDE_GAP_MIN)
	var row_gap := card_h * PLAYED_ROW_GAP_RATIO
	var widest := 0.0
	var used_h := 0.0
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
		var step := card_h * _played_step_ratio(grp, n, aspect)
		var cards_width := card_h * units[i].x + badge_left_padding
		var group_height := card_h * units[i].y
		var grp_w := placements[i].size.x
		var x := placements[i].position.x
		var y := placements[i].position.y
		used_h = maxf(used_h, y + group_height)
		widest = maxf(widest, x + grp_w)

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
			av.custom_minimum_size = Vector2.ZERO
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
		_tween_size(cards_box, Vector2(cards_width, group_height), "lay_cards", settling)
		var columns := maxi(1, int(grp.get_meta("expanded_columns")))
		var expanded := bool(grp.get_meta("expanded", false))
		var content_rows := ceili(float(n) / columns) if expanded else 1
		var content_height := content_rows * card_h + maxi(0, content_rows - 1) * row_gap
		cards_row.custom_minimum_size = Vector2(cards_width, maxf(group_height, content_height))
		cards_row.size = cards_row.custom_minimum_size
		for k in range(n):
			var slot := cards_row.get_child(k) as Control
			var column := k % columns if expanded else k
			var card_row := k / columns if expanded else 0
			var row_cards := mini(columns, n - card_row * columns) if expanded else n
			var row_width := card_w + maxi(0, row_cards - 1) * step
			var slot_pos := Vector2(badge_left_padding + maxf(0.0, (cards_width - badge_left_padding - row_width) * 0.5) + column * step, card_row * (card_h + row_gap))
			_tween_vec(slot, &"position", slot_pos, "lay_slot_pos", settling)
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
		_tween_size(grp, Vector2(grp_w, group_height), "lay_grp", settling)
	_update_power_badges(rows)
	list.custom_minimum_size = Vector2(maxf(groups.size.x, widest), maxf(groups.size.y, used_h))
