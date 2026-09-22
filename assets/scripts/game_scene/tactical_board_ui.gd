extends Control

## TacticalBoardUI: 战术界面总控制器 (增强点位版)
## 实现了：
## 1. 真实数据绑定 (手牌、打出区、魔力长条、战果、令咒、顺位、驻留立牌)
## 2. 玩家手牌出牌、阶段推进
## 3. 对手 AI 极简自动行动
## 4. 事件牌鼠标悬浮放大
## 5. 四大战区点击移动
## 6. 技能牌与附加宝具点击发动
## 7. 分支效果决策弹窗 (Waiting Effect Dialog)
## 8. 明确的魔术工房魔力补充位、深山町/新都地利位、侦察先锋位渲染

@export_node_path("Control") var opponent_drawer_path: NodePath = NodePath("OpponentDrawer_Expanded")
@export_node_path("Control") var leaderboard_drawer_path: NodePath = NodePath("Drawer_Leaderboard")
@export_node_path("Control") var hand_tray_path: NodePath = NodePath("HandTray_Collapsible")
@export_node_path("Control") var effect_modal_path: NodePath = NodePath("Modal_EffectChoice")
@export_node_path("Control") var event_zoom_preview_path: NodePath = NodePath("EventCardZoomPreview")
@export var debug_console_enabled_on_start: bool = false

var _selected_opponent: Control = null
var _selected_opponent_id: int = -1
#本地玩家身份哨兵：声明为 -1(未初始化)，_ready() 里从 GameData.player_id 取真实值。
#不要写死 0——0 是合法玩家 id，若在赋值前被读到会把 0 号玩家静默当成自己，
#而 -1 是明显无效值，误读会当场暴露而不是静默错位
var _local_player_id: int = -1
var _ai_acting: bool = false
## 正在替哪位玩家跑 AI，用于异常兜底复位
var _ai_acting_for_id: int = -1
## AI 最近一次成功打出的卡，用于顶栏卡位下方的行动提示
var _ai_play_prompt_player_id: int = -1
var _ai_play_prompt_card: BaseCard = null
## 提示对应的回合号：与 GameProgress.current_round 不一致时提示自动失效
var _ai_play_prompt_round: int = -1
var _ai_play_prompt_node: Control = null
## AI 步进冷却计时，避免一帧把整轮对手跑完
var _ai_cooldown: float = 0.0
var _current_waiting_effect: BaseEffect = null
## 战斗阶段手动能力的自动询问记录。作用域由回合、阶段、行动者组成；
## 同一窗口每条效果只自动询问一次，避免玩家放弃后下一帧再次弹出。
var _manual_prompt_scope:String = ""
var _manual_prompted_effect_ids:Array[int] = []
## 正在等待玩家挑牌的效果与已挑中的牌（与"等发动/放弃"是两条并列的玩家输入）
var _card_select_request: Dictionary = {}
var _card_select_hidden: Dictionary = {}
var _card_select_submit: Callable
## 常规出牌待确认组：选择阶段只暂存在这里，不扣魔力、不移动卡牌、不触发效果。
## 点击撤销只移除最后一项；确认后才由 RegularPlay.submit_group 一次提交并广播。
var _regular_play_pending_cards:Array = []
var _regular_play_pending_hidden:Array = []
## 这次确认是否由“结束阶段”触发；若是，提交整组后才真正结束当前行动
var _regular_play_confirm_ends_action:bool = false
var _card_select_effect: BaseEffect = null
var _card_select_picked: Array = []
var _card_select_cards: Array = []
var _card_select_panel: Control = null
## 玩家目标选择浮层（选项级 select_players）：与选牌浮层并列，同样按需现建
var _player_select_effect: BaseEffect = null
var _player_select_panel: Control = null
## 只读卡牌浏览面板：弃牌堆、事件牌/局势牌弃牌区、历史牌共用一个
var _card_browser_panel: Control = null
## 战报分步展开的动画句柄：连开两次战报时要先 kill 上一次，否则会留下半透明的行
var _battle_report_tween: Tween = null
var _battle_report_backdrop: ColorRect = null
var _power_tooltip_panel: PanelContainer = null
var _hovered_event_card: Control = null
## 说明面板当前正在显示哪张卡（区别于会随鼠标悬浮实时变化的 _hovered_event_card），
## 用于在 _input 判断"这一击是不是点在面板来源自身上"，避免右键同卡关闭又被误判成切换重开
var _desc_panel_source: Control = null
var _hand_is_expanded: bool = false
var _hand_tween: Tween = null
var _last_hand_hover_state: bool = false
var _debug_console: DebugConsoleUI = null

@onready var opponent_drawer: Control = get_node_or_null(opponent_drawer_path)
@onready var leaderboard_drawer: Control = get_node_or_null(leaderboard_drawer_path)
@onready var hand_tray: Control = get_node_or_null(hand_tray_path)
@onready var effect_modal: Control = get_node_or_null(effect_modal_path)
@onready var event_zoom_preview: Control = get_node_or_null(event_zoom_preview_path)
@onready var event_desc_panel: Control = get_node_or_null("EventCardDescPanel")
@onready var battle_report_modal: Control = get_node_or_null("Modal_BattleReport")
@onready var effect_result_modal: Control = get_node_or_null("Modal_EffectResult")
@onready var tactical_confirm_modal: Control = get_node_or_null("Modal_TacticalConfirm")
var _pending_tactical_action: Dictionary = {}
## 当前确认弹窗是不是"纯提示"模式；以及被提示顶掉的待确认文案（关掉提示后放回来）
var _confirm_alert_mode: bool = false
var _pending_confirm_desc: String = ""
## 手牌托盘是否被按钮锁定为展开（锁定时鼠标移出不自动收起）
var _hand_pinned_open: bool = false
var _shown_battle_result: Dictionary = {}
# 排行榜三种底板样式，从场景现有条目借用，供动态排序复用
var _lb_style_top1: StyleBox = null
var _lb_style_normal: StyleBox = null
var _lb_style_active: StyleBox = null

# ---- 通用卡牌悬浮放大系统参数 ----
# 放大预览的目标高度与宽度上限（过宽的卡自动受宽度约束）
const ZOOM_PREVIEW_HEIGHT := 460.0
const ZOOM_PREVIEW_MAX_WIDTH := 760.0
# 会被视作"遮挡层"的最小 z_index（弹窗、抽屉等），用于屏蔽其下方卡牌的悬浮识别
const MODAL_Z_THRESHOLD := 25
## 自己的未公开卡蒙的闭眼图标（相对路径，与其余外部资源一致）
const CONCEAL_ICON := "assets/images/ui/icons/icon_eye_closed.png"
## 两种遮罩的节点名。遮罩挂在卡图节点下面，递归找卡图时要按这两个名字排除
const OVERLAY_NODE_NAMES := ["ConcealOverlay", "InactiveOverlay"]
## 数量角标的节点名：重复的牌合并成一个卡位后，由它显示这份有多少张。
## 填充卡名/技能名时要跳过它，否则角标会被当成名字标签改写
const COUNT_BADGE_NAME := "CountBadge"
## AI 每步之间的间隔（秒）：一帧跑完会让玩家看不到对手行动过程
const AI_STEP_INTERVAL := 0.7
## 战报每行淡入的时长（秒）：结算过程分步展开的节奏，太长会让人等，太短看不出分步
const BATTLE_REPORT_STEP := 0.16
## 战报按钮的位置与图标已移入场景（BtnBattleReport 节点），不再由脚本设定
## 顶栏顺位行与其"我"的紧凑卡位：卡位名只在场景里定义一次，代码里不再重复拼字符串
const ORDER_BOX_PATH := "TopPanel_AllPlayers/AllPlayersOrderScroll/OrderHBox"
const LOCAL_ORDER_SLOT_NAME := "P1_Me_AvatarOnly"
## 底栏御座上的令咒卡卡位：玩家主动发动令咒的入口与提示都挂在它上面
const COMMAND_SPELL_CARD_PATH := "Bottom_PlayerDock/TacticalDeskLayout/Section_CommandPodium/VBox/LowerCommandSpellRow/Tex"
#未公开(暗置)遮罩：半透明灰 + 闭眼图标
const CONCEAL_COLOR := Color(0.32, 0.32, 0.36, 0.55)
#尚未激活的卡(如未激活buff的御主物品卡)遮罩：半透明深红。
#只表达"这张卡还没生效"，不带图标——和"未公开"是两回事，可以同时盖
const INACTIVE_COLOR := Color(0.45, 0.06, 0.10, 0.45)
#令咒耗尽遮罩：半透明纯灰，不带图标。表达"令咒已全部用完"
const EXHAUSTED_COLOR := Color(0.18, 0.18, 0.22, 0.65)
# 攻击牌类别的中文标签（卡面右下角角标）
const ATTACK_CATEGORY_LABELS := {
	"basic": "基础攻击牌",
	"class": "职阶攻击牌",
	"non_basic": "专属攻击牌",
}
# 数值字段的中文标签表：卡牌说明按此通用提取，"新增数值字段只需补一行标签"
const FIELD_LABELS := {
	"_cost": "魔力消耗",
	"_power": "威力",
	"_score": "战果",
	"_magic": "魔力",
	"_benefit": "地利战力",
	"_buff_level": "层数",
}

var _modal_blockers: Array[Control] = []
var _dragging_modal: Control = null
var _zoom_preview_size := Vector2.ZERO
# 可点击标识：已套用呼吸光晕的控件，供刷新时批量调整强度
var _clickable_nodes: Array[Control] = []

var mana_icon_texture: Texture2D = preload("res://assets/images/ui/icons/icon_mana_orb.png")
var grail_icon_texture: Texture2D = preload("res://assets/images/ui/icons/icon_holy_grail.png")
var swords_icon_texture: Texture2D = preload("res://assets/images/ui/icons/icon_swords.png")

# UI 核心节点引用
@onready var round_label: Label = get_node_or_null("TopPanel_AllPlayers/PhaseInfo/Round")
@onready var turn_seq_label: Label = get_node_or_null("TopPanel_AllPlayers/PhaseInfo/TurnSeq")
@onready var magic_bar: ProgressBar = get_node_or_null("Bottom_PlayerDock/MyIdentityRow/MagicLongBarBox/MagicProgressBar")
@onready var magic_num_label: Label = get_node_or_null("Bottom_PlayerDock/MyIdentityRow/MagicLongBarBox/BarTopLabel/Num")
@onready var score_text_label: Label = get_node_or_null("Bottom_PlayerDock/MyIdentityRow/VBox/Subtitle/ScoreBadgeIntegrated/H/ScoreText")
@onready var cs_label: Label = get_node_or_null("Bottom_PlayerDock/MyIdentityRow/VBox/Subtitle/CommandSpellOnly")
@onready var total_power_label: Label = get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_PlayBattleZone/VBox/ZoneHeader/TotalPower")
@onready var btn_end_phase: Button = get_node_or_null("Bottom_PlayerDock/MyIdentityRow/BtnEndPhaseBar")

# 容器节点引用
@onready var hand_cards_row: HBoxContainer = get_node_or_null("HandTray_Collapsible/VBox/HandCardsRow")
@onready var played_cards_row: HBoxContainer = get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_PlayBattleZone/VBox/CardsScroll/CardsH")
@onready var skills_scroll_h: HBoxContainer = get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_SkillsAndPhantasms/VBox/CardsScroll/H")

# 战区主节点
@onready var area_workshop: Control = get_node_or_null("Middle_MainPlayground/Battlefields_CenterContainer/Area_Workshop")
@onready var area_miyama: Control = get_node_or_null("Middle_MainPlayground/Battlefields_CenterContainer/Area_Miyama")
@onready var area_shinto: Control = get_node_or_null("Middle_MainPlayground/Battlefields_CenterContainer/Area_Shinto")
@onready var area_scout: Control = get_node_or_null("Middle_MainPlayground/Battlefields_CenterContainer/Area_Scout")
@onready var arrow_ws_miyama: Label = get_node_or_null("Middle_MainPlayground/Battlefields_CenterContainer/Arrow_WS_Miyama")
@onready var arrow_miyama_shinto: Label = get_node_or_null("Middle_MainPlayground/Battlefields_CenterContainer/Arrow_Miyama_Shinto")
@onready var arrow_shinto_scout: Label = get_node_or_null("Middle_MainPlayground/Battlefields_CenterContainer/Arrow_Shinto_Scout")

const HAND_COLLAPSED_TOP: float = -64.0
const HAND_COLLAPSED_BOTTOM: float = 208.0
const HAND_EXPANDED_TOP: float = -272.0
const HAND_EXPANDED_BOTTOM: float = 0.0

func _ready() -> void:
	# 本地玩家以引擎侧的 GameData.player_id 为唯一来源：界面不再另立默认值。
	# 否则界面认 0、引擎默认认 6，两套"我是谁"会让不传 player_id 的 operation 作用到别人身上
	_local_player_id = GameData.player_id
	if tactical_confirm_modal:
		var btn_ok := tactical_confirm_modal.get_node_or_null("Box/VBox/ButtonsRow/BtnConfirmAction") as Button
		var btn_no := tactical_confirm_modal.get_node_or_null("Box/VBox/ButtonsRow/BtnCancelAction") as Button
		if btn_ok and not btn_ok.pressed.is_connected(_on_tactical_confirm_execute):
			btn_ok.pressed.connect(_on_tactical_confirm_execute)
		if btn_no and not btn_no.pressed.is_connected(_on_tactical_confirm_cancel):
			btn_no.pressed.connect(_on_tactical_confirm_cancel)
	if battle_report_modal:
		var btn_close := battle_report_modal.get_node_or_null("Box/VBox/BtnCloseReport") as Button
		if btn_close and not btn_close.pressed.is_connected(_on_close_battle_report):
			btn_close.pressed.connect(_on_close_battle_report)
	if opponent_drawer:
		opponent_drawer.visible = false
		_block_panel_clicks(opponent_drawer)
		# Godot 的鼠标命中检测按子节点顺序从后往前测试，与 z_index（只影响绘制层叠）
		# 无关。抽屉原本排在 Middle_MainPlayground 之前，视觉上盖住战区，点击却会先
		# 命中排在后面的战区、穿透过去——按 z_index 语义把子节点顺序也一并对齐，
		# 排到"正常场景元素"之后、"确认类弹窗"之前，两套顺序（绘制/命中）就不会打架。
		_reorder_child_by_z(opponent_drawer)
	if leaderboard_drawer:
		leaderboard_drawer.visible = false
		leaderboard_drawer.z_index = max(leaderboard_drawer.z_index, MODAL_Z_THRESHOLD)
		_block_panel_clicks(leaderboard_drawer)
		_reorder_child_by_z(leaderboard_drawer)
	# 底栏两个开关按钮接上已有函数：手牌托盘展开/收起、对手抽屉关闭。
	# 不留"亮着呼吸光晕、点了没反应"的死按钮
	var btn_tray := get_node_or_null("Bottom_PlayerDock/MyIdentityRow/BtnToggleHandTray") as Button
	if btn_tray and not btn_tray.pressed.is_connected(_on_toggle_hand_tray_pressed):
		btn_tray.pressed.connect(_on_toggle_hand_tray_pressed)
	if opponent_drawer:
		var btn_close_opp := opponent_drawer.get_node_or_null("VBox/HeaderBar/BtnCloseOppDrawer") as Button
		if btn_close_opp:
			btn_close_opp.visible = true
			if not btn_close_opp.pressed.is_connected(_on_close_opponent_drawer_pressed):
				btn_close_opp.pressed.connect(_on_close_opponent_drawer_pressed)
	_cache_leaderboard_styles()
	if effect_modal:
		effect_modal.visible = false
	if effect_result_modal:
		effect_result_modal.visible = false
		var result_close := effect_result_modal.get_node_or_null("Box/VBox/BtnClose") as Button
		if result_close and not result_close.pressed.is_connected(_on_effect_result_closed):
			result_close.pressed.connect(_on_effect_result_closed)
	if event_zoom_preview:
		event_zoom_preview.visible = false
	if event_desc_panel:
		event_desc_panel.visible = false
	
	# 弹窗可拖动，便于查看被弹窗遮挡的战场
	for modal in [tactical_confirm_modal, effect_modal, effect_result_modal, battle_report_modal]:
		_enable_modal_drag(modal)
	# 战区是主要的点击目标：加呼吸光晕 + 环绕光尘粒子
	for area in [area_workshop, area_miyama, area_shinto, area_scout]:
		if area:
			area.set_meta("clickable", true)
			area.set_meta("clickable_color", Color(1.0, 0.85, 0.3, 1.0))
	
	_register_opponent_cards()
	_register_leaderboard_toggle()
	_setup_floating_hand_tray()
	_connect_player_actions()
	_connect_battlefield_movement()
	_register_all_hover_zoom()
	_connect_effect_modal_buttons()
	# 右侧常驻的战报入口（与战果榜按钮同一列）
	_setup_battle_report_entry()
	
	# 如果游戏引擎尚未启动，则启动 7 位玩家完整对局。
	# 初始手牌与准备阶段的推进都由引擎规则负责（准备阶段补牌到上限、无操作自动跳过），
	# 界面不再自己摸牌、也不硬跳阶段
	if !GameStart._started:
		GameStart.game_start([0, 1, 2, 3, 4, 5, 6])
	set_debug_console_enabled(debug_console_enabled_on_start)
	
	refresh_all_ui()

var _ui_refresh_accum: float = 0.0



func _process(delta: float) -> void:
	_update_ai_play_prompt_geometry()
	_update_hand_hover_from_mouse()
	# 明暗按钮条的显隐每帧统一判定：鼠标离开卡位就收起
	_update_regular_play_bars()
	_update_event_card_hover_check()
	if !_is_debug_console_blocking_progress():
		_check_waiting_effects()
		_check_waiting_card_selection()
		_check_waiting_player_selection()
		_check_waiting_location_selection()
		_check_and_step_ai(delta)
	# 效果结算产生的提示消息：取走并展示。消息由operation产生，展示形态是界面的事
	_flush_effect_messages()
	# 战报：战斗阶段的结果一变就弹一次（此前该函数没有任何调用点，战报永远不显示）
	_check_battle_report()
	# 轻量节流刷新：顶栏敌人魔力/总威力/战果与行动者提示实时跟随
	_ui_refresh_accum += delta
	if _ui_refresh_accum >= 0.5:
		_ui_refresh_accum = 0.0
		# 顺位行先刷新（它负责记录卡位属于谁），资源刷新再按绑定取数
		_refresh_turn_order_bar()
		_refresh_opponent_resource_icons()
		_refresh_open_opponent_drawer()
		_refresh_dynamic_labels(GameDataManager.get_player_data(_local_player_id))
		_refresh_removed_cards_entry(
			get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_SkillsAndPhantasms/VBox/RackHeader/BtnOutOfGame") as Button,
			GameDataManager.get_player_data(_local_player_id), true
		)
		# 令咒的可发动提示跟着阶段/回合走，不能只在整屏刷新时更新
		_refresh_command_spell_action()
		# 等待玩家选位置这类状态随时进入/结束，不能只靠整屏刷新
		_refresh_pending_input_tip()
		_refresh_clickable_strength()

## 每帧统一收拢所有明暗按钮条：鼠标不在对应卡位上就隐藏。
## 不能只靠 mouse_exited——卡位每次刷新都会重建/复用，
## 信号丢失或鼠标以非常规轨迹离开时按钮就永久留在卡上（用户报的"按钮不消失"）。
## 同时按最新的 modes 重算每个按钮的可见性：玩家出掉第一张后，
## 第二张的暗置按钮可能已不再合法，不该还显示着
func _update_regular_play_bars() -> void:
	for bar in find_children("RegularPlayModes", "HBoxContainer", true, false):
		var slot: Control = _regular_bar_slot(bar)
		if slot == null:
			continue
		# 现取现算，不用卡位上缓存的 modes：
		# 卡位会被复用，且 metadata 只在整屏刷新时写；玩家出掉第一张后，
		# 第二张牌此刻究竟还能不能明置/暗置只有 RegularPlay 知道。
		# 读缓存会让"已暗置一张后第二张的暗置按钮不出现"（非交战本可暗置两张）。
		var card = slot.get_meta("regular_play_card", null)
		var modes: Array = _regular_play_modes(card)
		# 缓存同步更新，让金框等其它读这份 metadata 的地方也拿到最新值
		slot.set_meta("regular_play_modes", modes)
		var show_bar: bool = not modes.is_empty() and _pointer_over_regular_slot(slot, bar)
		bar.visible = show_bar
		if show_bar:
			for child in bar.get_children():
				child.visible = modes.has(bool(child.get_meta("hidden_mode", false)))


## 按钮条所属的卡位：按钮条挂在卡图节点上，卡位是记着 regular_play_modes 的那一层。
## 向上找第一个带该 metadata 的祖先，不按固定层数写死（两种卡位结构嵌套深度不同）
func _regular_bar_slot(bar: Control) -> Control:
	var node: Node = bar.get_parent()
	while node != null and node != self:
		if node is Control and node.has_meta("regular_play_modes"):
			return node as Control
		node = node.get_parent()
	return null


func _update_hand_hover_from_mouse() -> void:
	if hand_tray == null or not is_inside_tree():
		return
	var viewport_size := get_viewport_rect().size
	var mouse_pos := get_viewport().get_mouse_position()
	# 收起时只需要命中底部触发带；展开后要把整个托盘算作悬浮区域。
	var trigger_top := viewport_size.y - 64.0
	var trigger_rect := Rect2(
		Vector2(hand_tray.get_global_rect().position.x, trigger_top),
		Vector2(hand_tray.get_global_rect().size.x, viewport_size.y - trigger_top)
	)
	var tray_rect := hand_tray.get_global_rect().grow(8.0)
	var hovering_trigger: bool = trigger_rect.has_point(mouse_pos) or (_hand_is_expanded and tray_rect.has_point(mouse_pos))
	if hovering_trigger != _last_hand_hover_state:
		_last_hand_hover_state = hovering_trigger
		if hovering_trigger:
			_expand_hand_tray()
		else:
			_collapse_hand_tray()

## -------------------------------------------------------------
## 1. 真实数据绑定与 UI 整体刷新
## -------------------------------------------------------------
## 通用令咒解析：优先御主自带的令咒，其次从者自带，最后回退通用常规令咒。
## 解析逻辑下沉在 LoadCommandSpell.resolve_player_command_spell，与开局效果挂载
## 共用同一个口径（御主/从者可在自身数据的 specials.COMMAND_SPELLS 里声明专属令咒），
## 因此特殊角色不必改动界面逻辑即可使用自己的令咒。
func _resolve_player_command_spell(pl_data: Dictionary) -> BaseCard:
	return LoadCommandSpell.resolve_player_command_spell(
		pl_data.get("master"), pl_data.get("servant"))

## 绑定底栏静态卡牌、头像与局势牌的悬浮说明（数据取自当前玩家与当前局势）
func _refresh_static_card_infos(pl_data: Dictionary) -> void:
	var master = pl_data.get("master")
	var servant = pl_data.get("servant")
	var podium := "Bottom_PlayerDock/TacticalDeskLayout/Section_CommandPodium/VBox/UpperRow/"
	# 卡图按数据填，不用场景预置图：卡位只当尺寸模板，取不到图就保持原样
	_fill_card_slot(get_node_or_null(podium + "MasterCardBox/Tex"), master, "_master_card_img")
	_fill_card_slot(get_node_or_null(podium + "ServantCardBox/Tex"), servant, "_servant_card_img")
	# 令咒卡：卡图优先用该御主自己的令咒图案，说明取令咒数据
	var cs_node := get_node_or_null(COMMAND_SPELL_CARD_PATH) as TextureRect
	var cs := _resolve_player_command_spell(pl_data)
	if cs_node and cs != null:
		var cs_num: int = (pl_data.get("command_spell_count", BaseNumber.new(3)) as BaseNumber).number
		# 卡图上显示哪张，放大图就必须是哪张：优先该御主自己的令咒图案，
		# 御主没声明令咒图时才回退令咒卡自带的默认图
		var cs_img: String = str(master.get("_command_spell_img")) if master else ""
		if cs_img == "" or not LoadHelper.texture_exists(cs_img):
			cs_img = str(cs.get("_card_img"))
		if cs_img != "" and LoadHelper.texture_exists(cs_img):
			cs_node.texture = LoadHelper.load_texture(cs_img)
		# 先绑定（标题与说明来自令咒卡本身），再指定放大图。
		# 顺序不能反：_bind_zoom_info 会用卡自带的 _card_img 覆盖 zoom_img，
		# 那样放大出来的是通用令咒图，与卡位上显示的那张不是同一张
		_bind_zoom_info(cs_node, cs)
		if cs_img != "" and LoadHelper.texture_exists(cs_img):
			cs_node.set_meta("zoom_img", cs_img)
		cs_node.set_meta("zoom_desc", "剩余 %d\n%s" % [cs_num, _build_card_desc(cs)])
		var cs_info := get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_CommandPodium/VBox/LowerCommandSpellRow/InfoV")
		if cs_info:
			var cs_lbl := cs_info.get_node_or_null("Lbl") as Label
			if cs_lbl:
				# 数量用 ×N 表达，不用括号补充
				cs_lbl.text = _object_shown_name(cs) + ("　×%d" % cs_num if cs_num > 1 else "")
			var cs_desc_lbl := _ensure_command_spell_desc_scroll()
			if cs_desc_lbl:
				var lines: Array[String] = []
				var cs_effs = cs.get("_effects")
				if cs_effs is Array:
					for e in cs_effs:
						if e.has_method("has_options") and e.has_options():
							for opt in e._options:
								var on: String = str(opt.get("shown_option_name", ""))
								if on != "":
									lines.append(on)
						else:
							var en: String = _object_shown_name(e)
							if en != "":
								lines.append(en)
				# 固定高度的无滚动条滚动区域：完整保留说明，不撑高底栏
				cs_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				cs_desc_lbl.text = "\n".join(lines)
				cs_desc_lbl.visible = lines.size() > 0
	# 自己的头像：贴图与说明都按真实御主刷新。
	# 此前只绑了放大说明、从不赋贴图，于是底栏与顶栏"我"的头像永远是场景预置的那张
	var my_avatar := get_node_or_null("Bottom_PlayerDock/MyIdentityRow/Avatar") as TextureRect
	if my_avatar:
		_apply_header_texture(my_avatar, master)
		_bind_zoom_info(my_avatar, master, "_header_img")
	var p1 := get_node_or_null("TopPanel_AllPlayers/AllPlayersOrderScroll/OrderHBox/P1_Me_AvatarOnly")
	if p1:
		for sub in p1.find_children("*", "TextureRect", true, false):
			if sub is TextureRect:
				_apply_header_texture(sub as TextureRect, master)
			_bind_zoom_info(sub, master, "_header_img")
	_refresh_situation_card()

## -------------------------------------------------------------
func _ensure_command_spell_desc_scroll() -> Label:
	var info := get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_CommandPodium/VBox/LowerCommandSpellRow/InfoV") as VBoxContainer
	if info == null:
		return null
	var desc := info.get_node_or_null("Desc") as Label
	if desc == null:
		var scroll := info.get_node_or_null("DescScroll") as ScrollContainer
		if scroll == null:
			return null
		_configure_command_spell_desc_scroll(scroll)
		return scroll.get_node_or_null("Desc") as Label
	var scroll := ScrollContainer.new()
	scroll.name = "DescScroll"
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_configure_command_spell_desc_scroll(scroll)
	var index := desc.get_index()
	info.remove_child(desc)
	info.add_child(scroll)
	info.move_child(scroll, index)
	desc.custom_minimum_size = Vector2(0, 0)
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(desc)
	return desc


func _configure_command_spell_desc_scroll(scroll: ScrollContainer) -> void:
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 36)
	scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# SHOW_NEVER 与 AUTO 后手动隐藏不同：仍响应滚轮，但布局永远不会重新画出滚动条。
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
## 不是几位玩家共用的模板卡——发动模板会把用量与消耗记到别人身上
func _local_command_spell_effects() -> Array:
	var effects: Array = []
	var cards: Array = GetPlCommandSpellOutGame.new().exec(_local_player_id)
	for card in cards:
		var card_effects = card.get("_effects") if card != null else null
		if card_effects is Array:
			effects.append_array(card_effects)
	return effects


## 此刻真的能主动发动的令咒效果（判据在引擎里，界面不自己再判一套）
func _usable_command_spell_effects() -> Array:
	return _usable_manual_effects(_local_command_spell_effects())


## 从一组效果里挑出此刻能主动发动的那些：判据只认引擎的 can_manual_activate
func _usable_manual_effects(effects: Array) -> Array:
	var usable: Array = []
	for eff in effects:
		if EffectManager.can_manual_activate(eff, _local_player_id):
			usable.append(eff)
	return usable


## 一个展示对象上此刻可主动发动的效果——点击该卡位就发动它。
## 效果可能挂在对象自己身上，也可能挂在与它关联的状态对象上：物品卡（宝石卡等）与它的
## buff 是两个独立对象，卡面负责展示、能力挂在 buff 上（JSON 用 relate_buff 接的引用）。
## 两条来源都查，因此"哪张卡能点着发动"完全由数据（效果声明 + relate_buff）决定，
## 界面不按卡名分支；没声明手动效果的对象返回空数组，卡位保持只展示不发动
func _manual_effects_of(obj) -> Array:
	var result: Array = []
	if obj == null:
		return result
	var holders: Array = [obj]
	var related = obj.get("_relate_buff")
	if related != null:
		holders.append(related)
	for holder in holders:
		var effects = holder.get("_effects")
		if effects is Array:
			for effect in _usable_manual_effects(effects):
				if not result.has(effect):
					result.append(effect)
	return result


## 令咒此刻不可发动的原因（空串表示可以发动）。
## 与战区一样：提示与点击入口共用同一份判据，不给玩家"亮着却点不动"的假提示
func _command_spell_block_reason() -> String:
	if not _usable_command_spell_effects().is_empty():
		return ""
	# 下面只是把原因说得更具体，真正的判定就是上面那一句
	var pl_data: Dictionary = GameDataManager.get_player_data(_local_player_id)
	if (pl_data.get("command_spell_count", BaseNumber.new(0)) as BaseNumber).number <= 0:
		return "没有令咒可用"
	# 有别的效果正等玩家答复时，引擎会拒绝手动发动（判据在 can_manual_activate 里）。
	# 这时要说真正的原因，不能让玩家误以为是自己挑错了时机
	if EffectManager.is_waiting_for_choice() or EffectManager.is_waiting_for_card_selection():
		return "请先处理当前待你答复的效果"
	return "现在不能发动令咒，只能在你的行动阶段使用"


## 令咒卡的提示与点击接线：能发动时亮金色呼吸描边，不能发动时完全不亮。
## 耗尽时盖纯灰遮罩，一眼看出没有剩余令咒可用
func _refresh_command_spell_action() -> void:
	var cs_node := get_node_or_null(COMMAND_SPELL_CARD_PATH) as TextureRect
	if cs_node == null:
		return
	var pl_data: Dictionary = GameDataManager.get_player_data(_local_player_id)
	var cs_count: int = (pl_data.get("command_spell_count", BaseNumber.new(0)) as BaseNumber).number
	# 令咒耗尽：盖纯灰半透明遮罩（复用已有的 _sync_overlay，不带图标）。
	# MOUSE_FILTER_IGNORE 不挡点击，点击仍能弹出"没有令咒可用"的具体说明
	_sync_overlay(cs_node, cs_count <= 0, "ExhaustedOverlay", EXHAUSTED_COLOR)
	cs_node.mouse_filter = Control.MOUSE_FILTER_STOP
	cs_node.set_meta("clickable", true)
	cs_node.set_meta("clickable_color", Color(1.0, 0.85, 0.3, 1.0))
	cs_node.set_meta("playable_hint", _command_spell_block_reason() == "")
	if not cs_node.has_meta("command_spell_click_bound"):
		cs_node.set_meta("command_spell_click_bound", true)
		cs_node.gui_input.connect(_on_command_spell_clicked)


## 令咒卡点击：发动不了就把原因告诉玩家，不让点击静默无反应
func _on_command_spell_clicked(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed):
		return
	var blocked := _command_spell_block_reason()
	if blocked != "":
		_show_tactical_confirm(blocked, true)
		return
	# 多分支用一条效果的 options 表达（数据模型如此），所以这里取第一个可发动的手动效果
	var usable: Array = _usable_command_spell_effects()
	if usable.is_empty():
		return
	EffectManager.request_manual_activation(usable[0], _local_player_id)
	_refresh_pending_input_tip()
	refresh_all_ui()


## 刷新那些原先写死在场景里、但本来就是"按数据算"的文案。
## 全部在这里按同一口径生成，避免同一个数字在不同节点上各写一种格式
func _refresh_dynamic_labels(pl_data: Dictionary) -> void:
	var master = pl_data.get("master")
	var servant = pl_data.get("servant")
	var loc = pl_data.get("location") as BaseLocation
	var area := loc.get_from() as BaseMapArea if loc != null else null
	var area_name: String = area._area_name if area != null else ""

	# 底栏身份行：御主 · 职阶 · 所在战区（缺哪段就少哪段，不留固定占位）
	var title := get_node_or_null("Bottom_PlayerDock/MyIdentityRow/VBox/Title") as Label
	if title:
		var parts: Array[String] = []
		var master_name: String = _object_shown_name(master)
		if master_name != "":
			parts.append(master_name)
		var servant_class: String = str(servant.get("_servant_class")) if servant != null else ""
		if servant_class != "":
			parts.append(servant_class.capitalize())
		if area_name != "":
			parts.append(area_name)
		title.text = " · ".join(parts)

	# 顶栏"我"的顺位徽章：名次按当前真实顺位生成，不再是恒定的 1st
	var my_tag := get_node_or_null("TopPanel_AllPlayers/AllPlayersOrderScroll/OrderHBox/P1_Me_AvatarOnly/V/Tag") as Label
	if my_tag:
		my_tag.text = "%s [你]" % _ordinal_label(EffectManager.get_player_order_index(_local_player_id) + 1)

	# 牌库 / 弃牌张数
	var deck_lbl := get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_Logistics/DeckBox/Lbl") as Label
	if deck_lbl:
		deck_lbl.text = "牌库 %d" % (pl_data.get("deck", []) as Array).size()
	var discard_lbl := get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_Logistics/DiscardBox/Lbl") as Label
	if discard_lbl:
		discard_lbl.text = "弃牌 %d" % (pl_data.get("discard", []) as Array).size()
	# 自己的弃牌堆随时可以查看：点弃牌堆用只读浏览面板列出来
	var discard_box := get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_Logistics/DiscardBox") as Control
	if discard_box != null and not discard_box.has_meta("discard_click_bound"):
		discard_box.set_meta("discard_click_bound", true)
		discard_box.mouse_filter = Control.MOUSE_FILTER_STOP
		discard_box.set_meta("clickable", true)
		discard_box.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
				_show_card_browser("我的弃牌堆",
					GameDataManager.get_player_data(_local_player_id).get("discard", []))
		)

	# 手牌托盘手柄：张数跟着手牌走
	var handle := get_node_or_null("HandTray_Collapsible/VBox/TrayHandle/HandleBar") as Label
	if handle:
		handle.text = "▲ 手牌 %d" % (pl_data.get("hand_cards", []) as Array).size()

	# 御座上的御主卡 / 从者卡标题
	var master_lbl := get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_CommandPodium/VBox/UpperRow/MasterCardBox/Label") as Label
	if master_lbl:
		master_lbl.text = "御主卡"
	var servant_lbl := get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_CommandPodium/VBox/UpperRow/ServantCardBox/Label") as Label
	if servant_lbl:
		var cls: String = str(servant.get("_servant_class")).capitalize() if servant != null else ""
		_set_true_name_status(servant_lbl, _local_player_id)
		servant_lbl.text = (("从者卡 · %s" % cls) if cls != "" else "从者卡") + "\n" + servant_lbl.text

	# 出牌区提示：常规出牌上限与当前席位地利，两段都从数据读，
	# 不写死"已计入深山町地利+3"
	var zone_tip := get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_PlayBattleZone/VBox/ZoneTip") as Label
	if zone_tip:
		var limit: int = (pl_data.get("play_limit", BaseNumber.new(0)) as BaseNumber).number
		var tip := "常规出牌 %d" % limit
		if area != null:
			var benefit: int = (loc._benefit as BaseNumber).number
			tip += " · %s 地利 %d" % [area_name, benefit]
		if not _regular_play_pending_cards.is_empty():
			tip += " · 已选择 %d" % _regular_play_pending_cards.size()
		# 记下常规文案：等待玩家选位置时会临时顶掉它，选完要放回来
		zone_tip.set_meta("normal_text", tip)
		zone_tip.text = tip
	var undo := get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_PlayBattleZone/VBox/ZoneHeader/BtnUndoRegularPlay") as Button
	if undo != null:
		undo.visible = false
	_refresh_pending_input_tip()


## 等待玩家做出选择时给出操作提示。
## 目前覆盖选项级的位置选择（如令咒的"移动至任意位置"）：引擎已进入等待状态、
## 地图点击也已接好，但此前没有任何文字告诉玩家该干什么，表现就是"选了移动令咒后没反应"。
## 提示文字里的可选起点从效果自己的声明(allowed_origin_areas)取，不写死战区名；
## 没有等待中的输入时把出牌区提示恢复成常规文案
func _refresh_pending_input_tip() -> void:
	var zone_tip := get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_PlayBattleZone/VBox/ZoneTip") as Label
	if zone_tip == null:
		return
	var pending: Dictionary = EffectManager.get_pending_location_selection()
	if pending.is_empty():
		if zone_tip.has_meta("pending_tip_shown"):
			zone_tip.remove_meta("pending_tip_shown")
			zone_tip.text = str(zone_tip.get_meta("normal_text", zone_tip.text))
			zone_tip.remove_theme_color_override("font_color")
		return
	zone_tip.set_meta("pending_tip_shown", true)
	# 效果自己声明了从哪些战区出发才合法，提示按声明列出，缺声明就只提示"点击目标战区"
	var spec: Dictionary = pending.get("spec", {})
	var allowed: Array = spec.get("allowed_origin_areas", []) as Array
	var text := "请点击要移动到的战区"
	if not allowed.is_empty():
		text += " · 出发地需为 %s" % "或".join(allowed)
	zone_tip.text = text
	zone_tip.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))

## 动态刷新战果天梯榜：按真实战果排序，名次前缀/头像/分值/底板样式全部跟随
func _refresh_leaderboard() -> void:
	if leaderboard_drawer == null:
		return
	var active_ids: Array = GameDataManager.get_active_player_ids() if GameDataManager else []
	if active_ids.is_empty():
		return
	var players_rank: Array = []
	for id in active_ids:
		var data: Dictionary = GameDataManager.get_player_data(id)
		var master = data.get("master")
		players_rank.append({
			"id": id,
			"score": (data.get("score", BaseNumber.new(0)) as BaseNumber).number,
			"master": master,
			"name": (_object_shown_name(master) if master else ("玩家 %d" % id)),
			"avatar": (master._header_img if master else ""),
			"is_me": id == _local_player_id,
			"is_current": id == GameProgress.current_player_id
		})
	players_rank.sort_custom(func(a, b):
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return a["id"] < b["id"]
	)
	# 排行行按场景实际提供的行数遍历（不写死行数），玩家不足时把多余的行隐藏——
	# 否则空行会留着场景预置的演示条目，看起来像真实排名
	var lb_rows: Array = []
	var lb_vbox := leaderboard_drawer.get_node_or_null("VBox")
	if lb_vbox:
		for child in lb_vbox.get_children():
			if child is PanelContainer and str(child.name).begins_with("R"):
				lb_rows.append(child)
	for i in range(lb_rows.size()):
		var row := lb_rows[i] as PanelContainer
		if i >= players_rank.size():
			row.visible = false
			continue
		row.visible = true
		var item: Dictionary = players_rank[i]
		var rank: int = i + 1
		var h := row.get_node_or_null("H")
		if h == null:
			continue
		var av := h.get_node_or_null("Av") as TextureRect
		if av and str(item["avatar"]) != "" and LoadHelper.texture_exists(str(item["avatar"])):
			av.texture = LoadHelper.load_texture(str(item["avatar"]))
		# 头像只显示名字
		_bind_zoom_info(av, item.get("master"), "_header_img")
		var name_lbl := h.get_node_or_null("Name") as Label
		if name_lbl:
			var suffix: String = " · 你" if item["is_me"] else ""
			name_lbl.text = "%s%s%s" % [_rank_prefix(rank), item["name"], suffix]
			if rank == 1:
				name_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
			elif item["is_me"]:
				name_lbl.add_theme_color_override("font_color", Color(0.4, 0.85, 1))
			else:
				name_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
		var score_lbl := h.get_node_or_null("ScoreH/Score") as Label
		if score_lbl:
			score_lbl.text = str(item["score"])
		# 底板优先级：当前行动者 > 榜首 > 常规
		if item["is_current"] and _lb_style_active != null:
			row.add_theme_stylebox_override("panel", _lb_style_active)
		elif rank == 1 and _lb_style_top1 != null:
			row.add_theme_stylebox_override("panel", _lb_style_top1)
		elif _lb_style_normal != null:
			row.add_theme_stylebox_override("panel", _lb_style_normal)

## 名次前缀：前三名用奖牌，其余用序号
func _rank_prefix(rank: int) -> String:
	match rank:
		1: return "🥇 "
		2: return "🥈 "
		3: return "🥉 "
		_: return "%d. " % rank

## 从场景现有排行条目借用三种底板样式，供动态排序复用（不写死样式内容）
func _cache_leaderboard_styles() -> void:
	if leaderboard_drawer == null:
		return
	var r1 := leaderboard_drawer.get_node_or_null("VBox/R1") as PanelContainer
	var r2 := leaderboard_drawer.get_node_or_null("VBox/R2") as PanelContainer
	var r3 := leaderboard_drawer.get_node_or_null("VBox/R3") as PanelContainer
	if r1:
		_lb_style_top1 = r1.get_theme_stylebox("panel")
	if r2:
		_lb_style_normal = r2.get_theme_stylebox("panel")
	if r3:
		_lb_style_active = r3.get_theme_stylebox("panel")

func refresh_all_ui() -> void:
	if !GameData.player_data_library.has(_local_player_id):
		return
	# 本次刷新会释放并重建手牌/出牌区节点，悬停记录必须同时清空，
	# 否则下一帧会去访问已释放实例的 rect（刷 error 日志、放大图闪断）
	_hovered_event_card = null
	
	var pl_data: Dictionary = GameDataManager.get_player_data(_local_player_id)
	
	# 刷新顶栏阶段与回合信息
	if round_label and turn_seq_label:
		var curr_phase := GameProgress.get_current_phase()
		round_label.text = "第 %d 回合 · %s" % [GameProgress.current_round, _phase_shown_name(str(curr_phase.get("name", "")))]
		
		var curr_id := GameProgress.current_player_id
		if curr_id < 0:
			turn_seq_label.text = "对局已结束"
			turn_seq_label.modulate = Color(0.75, 0.8, 0.9)
		elif curr_id == _local_player_id:
			# 顺位文案按当前真实顺位生成，不写死 1st，也不用括号补充
			turn_seq_label.text = "轮到你行动 · %s" % _ordinal_label(EffectManager.get_player_order_index(_local_player_id) + 1)
			turn_seq_label.modulate = Color(0.4, 0.9, 1.0)
		else:
			# 敌人行动提示：显示当前行动敌人的名字，而不是笼统的"等待对手"
			var cur_pl: Dictionary = GameData.player_data_library.get(curr_id, {}) if GameData else {}
			var cur_master = cur_pl.get("master")
			var actor_name: String = _object_shown_name(cur_master) if cur_master else ("玩家 %d" % curr_id)
			turn_seq_label.text = "%s 行动中..." % actor_name
			turn_seq_label.modulate = Color(1.0, 0.6, 0.3)

	# 刷新魔力长条与战果。待确认常规出牌只改 UI 预览账本：
	# 真实 magic 在最终确认时才由 RegularPlay.submit_group 一次扣除；
	# 撤回某张牌时预览费用自然消失，不需要反向改资源。
	var real_magic:int = (pl_data["magic"] as BaseNumber).number
	var preview_cost:float = _pending_regular_magic_cost(pl_data)
	var magic_num: int = real_magic if bool(pl_data.get("is_magic_immune", false)) else maxi(0, int(real_magic - preview_cost))
	var magic_limit: int = (GameData.magic_limit as BaseNumber).number
	if magic_bar:
		magic_bar.max_value = magic_limit
		magic_bar.value = magic_num
	if magic_num_label:
		magic_num_label.text = "%d / %d" % [magic_num, magic_limit]
	
	var score_num: int = (pl_data["score"] as BaseNumber).number
	if score_text_label:
		score_text_label.text = "战果: %d" % score_num
	
	var cs_num: int = (pl_data["command_spell_count"] as BaseNumber).number
	if cs_label:
		cs_label.text = "令咒 ×%d" % cs_num

	# 刷新前线打出区卡牌与威力。
	# 合计威力含当前实际享有的地利（部署到该位置才算）：与战力结算共用同一个查询，
	# 否则会出现"界面显示的威力"与"结算用的威力"不一致
	# 与战斗结算共用 GetPlayerTotalPower，界面不再自己拼公式
	# 待确认的常规出牌作为预估增量并入：出牌区里已经摆着这些牌，玩家要在确认前就能
	# 算出自己打完是多少威力，与魔力预览账本同一套做法
	var pending_pow: int = _pending_regular_power()
	var pw_break: Dictionary = GetPlayerTotalPower.breakdown(_local_player_id, pending_pow, _regular_play_pending_cards, _regular_play_pending_hidden)
	var location_benefit: int = int(pw_break["location_benefit"])
	var total_pow: int = int(pw_break["total"])
	if total_power_label:
		total_power_label.text = "当前合计威力: %d" % total_pow
		_bind_instant_power_tooltip(total_power_label, _local_player_id, pending_pow)
	
	_refresh_hand_cards(pl_data)
	_refresh_played_cards(pl_data)
	_refresh_battlefield_specific_slots()
	_refresh_clickable_skills(pl_data)
	_refresh_turn_order_bar()
	_refresh_opponent_resource_icons()
	_refresh_open_opponent_drawer()
	_refresh_ai_play_prompt()
	_refresh_leaderboard()
	_refresh_battlefield_events()
	_refresh_static_card_infos(pl_data)
	_refresh_command_spell_action()
	_refresh_movement_arrows()
	_refresh_dynamic_labels(pl_data)
	# 数据刷新后可能有新卡入树，统一重扫一次放大目标与遮挡层
	_register_all_hover_zoom()
	_apply_clickable_indicators()

## 顶栏顺位行：卡位只当布局模板，身份由卡位上的玩家 id 记着。
## 绑定时按身份分配：本地玩家的紧凑卡位(LOCAL_ORDER_SLOT_NAME)永远属于本地玩家，
## 其余卡位按真实顺位依次分给其他玩家；随后整行按顺位从左到右排列。
## 不能按下标分配——"我的卡位"与"别人的卡位"外观和内部结构都不同
## （我的是头像+顺位徽章，别人的是头像+名字+资源），错位会把别人的资料显示在"我"的格子上
func _refresh_turn_order_bar() -> void:
	var order_box := get_node_or_null(ORDER_BOX_PATH) as HBoxContainer
	if order_box == null or EffectManager == null:
		return
	# 顶栏只列还在局中的玩家：被淘汰的人不该继续占着顺位格子。
	# 出局判定读 player_data.is_out，不按卡位数量或下标猜
	var ordered_ids: Array = []
	for id in EffectManager.get_player_order_ids():
		var d: Dictionary = GameDataManager.get_player_data(int(id))
		if not bool(d.get("is_out", false)):
			ordered_ids.append(int(id))
	var local_slot := order_box.get_node_or_null(LOCAL_ORDER_SLOT_NAME) as Control
	if local_slot == null:
		return
	var other_slots: Array = []
	for child in order_box.get_children():
		if child is Control and str(child.name).begins_with("P") and str(child.name) != LOCAL_ORDER_SLOT_NAME:
			other_slots.append(child)
	var other_ids: Array = []
	for id in ordered_ids:
		if int(id) != _local_player_id:
			other_ids.append(int(id))
	# 卡位数与在局人数不一致是常态（有人被淘汰）：多余的卡位隐藏，不能整体 return——
	# 提前返回会让卡位保留上一次的身份，且下面的按顺位重排也不执行，
	# 玩家看到的先后就与真实顺位无关（表现为"顺位表显示 A 在前，实际 B 先动"）
	var slot_by_id: Dictionary = {}
	if ordered_ids.has(_local_player_id):
		slot_by_id[_local_player_id] = local_slot
		local_slot.visible = true
	else:
		local_slot.visible = false
	for i in range(other_slots.size()):
		var slot_i := other_slots[i] as Control
		if i < other_ids.size():
			slot_by_id[other_ids[i]] = slot_i
			slot_i.visible = true
		else:
			# 淘汰后空出来的卡位：隐藏并清掉身份，避免右键到已出局玩家的旧数据
			slot_i.visible = false
			if slot_i.has_meta("turn_order_player_id"):
				slot_i.remove_meta("turn_order_player_id")
	for id in ordered_ids:
		var slot := slot_by_id.get(int(id), null) as Control
		if slot != null:
			slot.set_meta("turn_order_player_id", int(id))
			# 完整卡位的行动状态独立于本地玩家是否可操作。
			var acting: bool = int(id) == GameProgress.current_player_id
			slot.set_meta("playable_hint", acting)
			_apply_clickable_indicator(slot, Color(1.0, 0.85, 0.3))
			# PanelContainer 会把普通子节点缩进内容边距；行动框必须覆盖整个卡位。
			var glow := slot.get_node("ClickableGlow") as Control
			glow.set_as_top_level(true)
			# 顶栏框由卡位矩形唯一驱动，不能同时保留 FULL_RECT 拉伸锚点。
			glow.set_anchors_preset(Control.PRESET_TOP_LEFT)
			glow.global_position = slot.global_position
			glow.size = slot.size
			if not slot.has_meta("turn_glow_layout_bound"):
				slot.set_meta("turn_glow_layout_bound", true)
				slot.item_rect_changed.connect(func():
					glow.global_position = slot.global_position
					glow.size = slot.size
				)
			_set_clickable_active(slot, acting)
	if turn_seq_label:
		# 行动提示要醒目但不能溢出 PhaseInfo 的显示范围：18 号在最长文案下仍放得下
		turn_seq_label.add_theme_font_size_override("font_size", 18)
		turn_seq_label.add_theme_constant_override("outline_size", 4)
		turn_seq_label.add_theme_color_override("font_outline_color", Color(0.06, 0.04, 0.02))
	# 箭头是卡位之间的分隔符：先全部隐藏并清除旧布局残留。
	# 被淘汰玩家离场后，箭头数量应始终是“在场玩家数 - 1”，不能留下旧箭头。
	var arrows: Array = []
	for child in order_box.get_children():
		if child is Label and str(child.name).begins_with("Arrow"):
			arrows.append(child)
			child.visible = false
	# 只展示相邻在场玩家之间的箭头，并按当前可见玩家顺序重新插入。
	var visible_index:int = 0
	for i in range(ordered_ids.size()):
		var slot := slot_by_id.get(int(ordered_ids[i]), null) as Control
		if slot == null:
			continue
		order_box.move_child(slot, visible_index)
		slot.visible = true
		visible_index += 1
		if i < ordered_ids.size() - 1 and i < arrows.size():
			var arrow := arrows[i] as Label
			arrow.visible = true
			order_box.move_child(arrow, visible_index)
			visible_index += 1
	# 容器完成本帧排序后，提示跟随真实卡位位置。
	_refresh_ai_play_prompt.call_deferred()


## 顶栏其他人的头像、名字与资源：全部按卡位上记的玩家 id 取数据。
## 本地玩家自己的卡位只显示头像与顺位徽章（资源在底栏），
## 那部分由 _refresh_static_card_infos / _refresh_dynamic_labels 负责，这里跳过
func _refresh_opponent_resource_icons() -> void:
	var order_box := get_node_or_null(ORDER_BOX_PATH) as HBoxContainer
	if order_box == null:
		return
	var bot_id: int = 0
	for child in order_box.get_children():
		if !(child is Control) or !str(child.name).begins_with("P"):
			continue
		bot_id = int(child.get_meta("turn_order_player_id", -1))
		if bot_id < 0 or bot_id == _local_player_id:
			continue
		var bot_pl: Dictionary = GameDataManager.get_player_data(bot_id) if GameDataManager else {}
		var bot_master = bot_pl.get("master") if bot_pl else null
		var av := child.get_node_or_null("HBox/Avatar") as TextureRect
		if av:
			_bind_zoom_info(av, bot_master, "_header_img")
			if bot_master:
				_apply_header_texture(av, bot_master)
		var name_lbl := child.get_node_or_null("HBox/Info/Name") as Label
		if name_lbl and bot_pl:
			var shown: String = _object_shown_name(bot_master) if bot_master else "玩家 %d" % bot_id
			name_lbl.text = "%s %s ▼" % [_ordinal_label(EffectManager.get_player_order_index(bot_id) + 1), shown]
		var info := child.get_node_or_null("HBox/Info")
		if info == null:
			continue
		var status := info.get_node_or_null("TrueNameStatus") as Label
		if status == null:
			status = Label.new()
			status.name = "TrueNameStatus"
			status.add_theme_font_size_override("font_size", 10)
			info.add_child(status)
		_set_true_name_status(status, bot_id)
		var old_stats := info.get_node_or_null("Stats")
		if old_stats:
			_free_runtime_child(old_stats)
		var magic_num: int = bot_pl.get("magic", BaseNumber.new(0)).number if bot_pl else 0
		var score_num: int = bot_pl.get("score", BaseNumber.new(0)).number if bot_pl else 0
		var spell_num: int = bot_pl.get("command_spell_count", BaseNumber.new(3)).number if bot_pl else 3
		var resources := info.get_node_or_null("ResourceIcons") as HBoxContainer
		if resources == null:
			resources = HBoxContainer.new()
			resources.name = "ResourceIcons"
			resources.add_theme_constant_override("separation", 5)
			resources.mouse_filter = Control.MOUSE_FILTER_IGNORE
			info.add_child(resources)
		else:
			for c in resources.get_children():
				_free_runtime_child(c)
		var power_num: int = GetPlayerTotalPower.new().exec(bot_id)
		_add_resource_icon(resources, mana_icon_texture, "%d/%d" % [magic_num, (GameData.magic_limit as BaseNumber).number], Color(0.45, 0.9, 1.0))
		var pow_lbl := _add_resource_icon(resources, swords_icon_texture, "%d" % power_num, Color(0.85, 0.92, 1.0))
		_bind_instant_power_tooltip(pow_lbl, bot_id)
		_add_resource_icon(resources, grail_icon_texture, "%d" % score_num, Color(1.0, 0.85, 0.35))
		var spell_label := Label.new()
		spell_label.text = "令咒 ×%d" % spell_num
		spell_label.add_theme_font_size_override("font_size", 10)
		spell_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.5))
		resources.add_child(spell_label)
		if av:
			av.set_meta("actor_avatar", true)
			av.set_meta("is_acting", GameProgress.current_player_id == bot_id)
			av.set_meta("clickable", true)
			av.set_meta("clickable_color", Color(0.4, 0.95, 1.0, 1.0))
			av.z_index = 5 if GameProgress.current_player_id == bot_id else 0




## 给头像节点套上所属御主/从者的头像图：所有"按数据刷头像"的地方共用它，
## 避免有的地方只贴图、有的地方只绑说明。取不到图时保持原样，不清空
func _apply_header_texture(node: TextureRect, obj) -> void:
	if node == null or obj == null:
		return
	var img: String = str(obj.get("_header_img"))
	if img == "" or not LoadHelper.texture_exists(img):
		return
	node.texture = LoadHelper.load_texture(img)

## 顺位序数文案：英文序数后缀按规则生成，不写死表（11th/12th/13th 等特例一并覆盖）
func _ordinal_label(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]

func _add_resource_icon(parent: HBoxContainer, icon: Texture2D, value: String, color: Color) -> Label:
	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(15, 15)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture = icon
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon_rect)
	var value_label := Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 10)
	value_label.add_theme_color_override("font_color", color)
	parent.add_child(value_label)
	return value_label

## 与 PlayAttack 完全一致的可打出判据：阶段/回合/上限/费用/【败北】/已激活，
## 不满足任何一条时 UI 不给提示。规则数字全部读数据，不写死
func _can_play_attack_now(card: BaseAttack, _pl_data: Dictionary) -> bool:
	return not RegularPlay.modes(_local_player_id, card).is_empty()


func _refresh_hand_cards(pl_data: Dictionary) -> void:
	if hand_cards_row == null:
		return
	var hand_cards: Array = []
	for card in pl_data.get("hand_cards", []):
		#待确认的牌仍在真实手牌数据里（所以可无损撤销），但界面上先移到出牌区展示
		if not _regular_play_pending_cards.has(card):
			hand_cards.append(card)
	var slots: Array = _ensure_slot_nodes(hand_cards_row, hand_cards.size())
	for i in range(slots.size()):
		var slot := slots[i] as Control
		var card = hand_cards[i] if i < hand_cards.size() else null
		if not (card is BaseHandCard):
			slot.visible = false
			continue
		slot.visible = true
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		var modes: Array = _regular_play_modes(card)
		var can_play: bool = not modes.is_empty()
		slot.set_meta("clickable", can_play)
		slot.set_meta("clickable_color", Color(1.0, 0.85, 0.3, 1.0))
		slot.set_meta("playable_hint", can_play)
		slot.set_meta("click_hand_card", card)
		_setup_regular_play_slot(slot, card, modes)
		if can_play and not _clickable_nodes.has(slot):
			_apply_clickable_indicator(slot, Color(1.0, 0.85, 0.3, 1.0), _card_art_of(slot))
		# 不可打出的牌立刻收起金框：playable_hint 也会在节流刷新里收，
		# 但那要等下一次 _refresh_clickable_strength，中间一帧会亮着
		_set_clickable_active(slot, can_play)
		if not slot.has_meta("hand_click_bound"):
			slot.set_meta("hand_click_bound", true)
			slot.gui_input.connect(_on_hand_slot_gui_input.bind(slot))
		# 手牌不盖闭眼遮罩：手牌只有自己看得到，标"未公开"没有信息量
		_render_card_face(slot, card, true, _card_back_type_of(card), false)

## 手牌卡位点击：打出 metadata 里现取的那张卡（卡位会被复用）
func _on_hand_slot_gui_input(ev: InputEvent, slot: Control) -> void:
	if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed):
		return
	var card = slot.get_meta("click_hand_card", null)
	if card is BaseAttack:
		_on_hand_card_clicked(card)

## 刷新打出区卡牌：卡位复用场景预置模板（卡图 + 威力标签），不足克隆、多余隐藏
func _refresh_played_cards(pl_data: Dictionary) -> void:
	if played_cards_row == null:
		return
	# 待确认牌必须逐张占位：每个卡位保存具体对象，点击才能撤回点击的那一张。
	# 已提交牌可继续按显示语义合并，因为它们没有撤回交互。
	var entries:Array = []
	for i in range(_regular_play_pending_cards.size()):
		entries.append({"card": _regular_play_pending_cards[i], "pending": true, "concealed": bool(_regular_play_pending_hidden[i])})
	for card in pl_data.get("played_cards", []):
		entries.append({"card": card, "pending": false, "concealed": bool(card.get("_is_concealed")), "count": 1})
	var slots: Array = _ensure_slot_nodes(played_cards_row, entries.size())
	for i in range(slots.size()):
		var slot := slots[i] as Control
		var entry = entries[i] if i < entries.size() else null
		if entry == null:
			slot.visible = false
			_set_slot_count_badge(slot, 0)
			continue
		slot.visible = true
		var card = entry["card"]
		var is_pending:bool = bool(entry["pending"])
		slot.set_meta("pending_regular_card", card if is_pending else null)
		if is_pending and not slot.has_meta("pending_regular_click_bound"):
			slot.set_meta("pending_regular_click_bound", true)
			slot.gui_input.connect(_on_pending_played_slot_input.bind(slot))
		for sub in _card_texture_nodes(slot):
			_render_card_face(sub, card, true, "skill", true, entry["concealed"])
			if is_pending:
				if not sub.has_meta("pending_regular_click_bound"):
					sub.set_meta("pending_regular_click_bound", true)
					sub.gui_input.connect(_on_pending_played_slot_input.bind(slot))
		var power_lbl := slot.get_node_or_null("Lbl") as Label
		if power_lbl:
			power_lbl.text = "威力: %d%s" % [card._power.number, " · 待确认" if is_pending else ""]
		_set_slot_count_badge(slot, 1 if is_pending else int(entry.get("count", 1)))

## 刷新四大战区明确点位 (魔力充能位 / 地利位 / 侦察席)
func _on_pending_played_slot_input(ev:InputEvent, slot:Control) -> void:
	if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed):
		return
	var card = slot.get_meta("pending_regular_card", null)
	if card == null:
		return
	var index:int = _regular_play_pending_cards.find(card)
	if index == -1:
		return
	_regular_play_pending_cards.remove_at(index)
	_regular_play_pending_hidden.remove_at(index)
	var was_confirming: bool = str(_pending_tactical_action.get("type", "")) == "regular_play"
	_pending_tactical_action.clear()
	_regular_play_confirm_ends_action = false
	if was_confirming and tactical_confirm_modal != null and tactical_confirm_modal.visible:
		tactical_confirm_modal.visible = false
	refresh_all_ui()
	get_viewport().set_input_as_handled()


func _refresh_battlefield_specific_slots() -> void:
	# 圆形槽位的 Holder 路径（头像放这里），额外席默认隐藏
	# 工房 (+2立体上层/三个+1中层/额外下层)；深山町/新都地利圆槽 + 混战流动垫；侦察先锋圆槽/额外
	var slot_nodes := [
		"Middle_MainPlayground/Battlefields_CenterContainer/Area_Workshop/VBox/WorkshopSlots/TierTop/SlotMagicPlus2/Circle/Holder",
		"Middle_MainPlayground/Battlefields_CenterContainer/Area_Workshop/VBox/WorkshopSlots/TierMid/SlotMagicPlus1A/Circle/Holder",
		"Middle_MainPlayground/Battlefields_CenterContainer/Area_Workshop/VBox/WorkshopSlots/TierMid/SlotMagicPlus1B/Circle/Holder",
		"Middle_MainPlayground/Battlefields_CenterContainer/Area_Workshop/VBox/WorkshopSlots/TierMid/SlotMagicPlus1C/Circle/Holder",
		"Middle_MainPlayground/Battlefields_CenterContainer/Area_Workshop/VBox/WorkshopSlots/TierBottom/SlotExtra/Circle/Holder",
		"Middle_MainPlayground/Battlefields_CenterContainer/Area_Miyama/VBox/MiyamaSlots/SlotPowerPlus3/Circle/Holder",
		"Middle_MainPlayground/Battlefields_CenterContainer/Area_Miyama/VBox/MiyamaSlots/SlotPowerPlus1/Circle/Holder",
		"Middle_MainPlayground/Battlefields_CenterContainer/Area_Miyama/VBox/SlotBattleCommon/Pad/Holder",
		"Middle_MainPlayground/Battlefields_CenterContainer/Area_Shinto/VBox/ShintoSlots/SlotPowerPlus3/Circle/Holder",
		"Middle_MainPlayground/Battlefields_CenterContainer/Area_Shinto/VBox/ShintoSlots/SlotPowerPlus1/Circle/Holder",
		"Middle_MainPlayground/Battlefields_CenterContainer/Area_Shinto/VBox/SlotBattleCommon/Pad/Holder",
		"Middle_MainPlayground/Battlefields_CenterContainer/Area_Scout/VBox/ScoutSlots/TierFirst/SlotScoutFirst/Circle/Holder",
		"Middle_MainPlayground/Battlefields_CenterContainer/Area_Scout/VBox/ScoutSlots/TierExtra/SlotScoutExtra/Circle/Holder"
	]
	
	# 额外席的父节点（含圆形框+标签），默认隐藏，有人占位才显示
	var workshop_extra_slot := get_node_or_null("Middle_MainPlayground/Battlefields_CenterContainer/Area_Workshop/VBox/WorkshopSlots/TierBottom/SlotExtra")
	var scout_extra_slot := get_node_or_null("Middle_MainPlayground/Battlefields_CenterContainer/Area_Scout/VBox/ScoutSlots/TierExtra/SlotScoutExtra")
	if workshop_extra_slot:
		workshop_extra_slot.visible = false
	if scout_extra_slot:
		scout_extra_slot.visible = false
	
	for path in slot_nodes:
		var node = get_node_or_null(path)
		if node:
			for child in node.get_children():
				# 清掉上一次生成的动态头像；场景预置的占位头像(写死的角色图)一并隐藏——
				# 槽位归属只由真实数据决定，留着占位图会让玩家右键到没有数据的假头像
				if child.has_meta("tactical_runtime_avatar"):
					_free_runtime_child(child)
				elif child is TextureRect:
					child.visible = false
	
	# 根据各玩家 location 放入对应圆形槽位
	for id in GameDataManager.get_active_player_ids():
		var data: Dictionary = GameDataManager.get_player_data(id)
		var loc = data.get("location")
		if loc == null:
			continue
		var map_area = loc.get_from()
		if map_area == null:
			continue
		var area_name: String = map_area._area_name if "_area_name" in map_area else ""
		var target_path: String = ""
		
		match area_name:
			"魔术工房":
				if loc == MapData.magic_workshop0:
					target_path = slot_nodes[0]
				elif loc == MapData.magic_workshop1:
					target_path = slot_nodes[1]
				elif loc == MapData.magic_workshop2:
					target_path = slot_nodes[2]
				elif loc == MapData.magic_workshop3:
					target_path = slot_nodes[3]
				else:
					target_path = slot_nodes[4]
					if workshop_extra_slot:
						workshop_extra_slot.visible = true
			"深山町":
				if loc == MapData.miyama0:
					target_path = slot_nodes[5]
				elif loc == MapData.miyama1:
					target_path = slot_nodes[6]
				else:
					target_path = slot_nodes[7]
			"新都":
				if loc == MapData.shinto0:
					target_path = slot_nodes[8]
				elif loc == MapData.shinto1:
					target_path = slot_nodes[9]
				else:
					target_path = slot_nodes[10]
			"侦察":
				if loc == MapData.scout0:
					target_path = slot_nodes[11]
				else:
					target_path = slot_nodes[12]
					if scout_extra_slot:
						scout_extra_slot.visible = true
					
		if target_path != "":
			var holder = get_node_or_null(target_path)
			if holder:
				var av := TextureRect.new()
				av.custom_minimum_size = Vector2(44, 44)
				av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				av.set_meta("tactical_runtime_avatar", true)
				var master = data.get("master")
				if master and LoadHelper.texture_exists(master._header_img):
					av.texture = LoadHelper.load_texture(master._header_img)
				_bind_zoom_info(av, master, "_header_img")
				holder.add_child(av)
				var total_power_num: int = GetPlayerTotalPower.new().exec(id)
				if total_power_num > 0:
					var power_label := Label.new()
					power_label.name = "TacticalPower"
					power_label.text = "威力 %d" % total_power_num
					# 贴在头像内部底边：圆形槽 Circle 设了 clip_contents，
					# 放到头像外侧会被裁掉，玩家看不到
					power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					power_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
					power_label.add_theme_font_size_override("font_size", 11)
					power_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
					power_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
					power_label.add_theme_constant_override("outline_size", 6)
					power_label.mouse_filter = Control.MOUSE_FILTER_STOP
					_bind_instant_power_tooltip(power_label, id)
					av.add_child(power_label)
					power_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
					power_label.offset_top = -15.0

## 局势牌按当前激活对象填卡图与说明，场景预置图只当空位模板
func _refresh_situation_card() -> void:
	# 弃牌区入口与"当前有没有局势牌"无关：先建，否则开局第一回合还没抽牌时
	# 这个函数会提前 return，入口永远不会出现
	_setup_discard_zone_entries()
	var situ_node := get_node_or_null("Middle_MainPlayground/LeftSituationSpot/VBox/BigSituationCard") as TextureRect
	var situ = MapData.active_situation if MapData else null
	if situ_node == null:
		return
	var note := get_node_or_null("Middle_MainPlayground/LeftSituationSpot/VBox/SitEffectNote") as Label
	if situ == null:
		situ_node.visible = false
		if note:
			note.visible = false
		return
	situ_node.visible = true
	var img: String = str(situ.get("_card_img"))
	if img != "" and LoadHelper.texture_exists(img):
		situ_node.texture = LoadHelper.load_texture(img)
		situ_node.set_meta("zoom_img", img)
	situ_node.remove_meta("event_zoom_img")
	situ_node.remove_meta("event_title")
	situ_node.remove_meta("event_desc")
	_bind_zoom_info(situ_node, situ)
	if note:
		note.visible = false


## 常驻历史入口只接线一次，点击时读取当前弃牌区；事件按来源战区筛选。
func _setup_discard_zone_entries() -> void:
	if has_meta("discard_entries_bound"):
		return
	set_meta("discard_entries_bound", true)
	# 按钮本体在场景里（位置可视化可调），脚本只接线：
	# 局势牌与两个战区各有自己的入口，不复制引擎的弃牌数组。
	for entry in [
		{
			"path": "Middle_MainPlayground/LeftSituationSpot/VBox/SituationDiscardRow/BtnSituationDiscard",
			"title": "历史局势牌", "key": "situation_discard"
		},
		{
			"path": "Middle_MainPlayground/Battlefields_CenterContainer/Area_Miyama/VBox/EventDiscardRow/BtnEventDiscard",
			"title": "深山町历史事件牌", "key": "event_discard", "area": MapData.miyama
		},
		{
			"path": "Middle_MainPlayground/Battlefields_CenterContainer/Area_Shinto/VBox/EventDiscardRow/BtnEventDiscard",
			"title": "新都历史事件牌", "key": "event_discard", "area": MapData.shinto
		}
	]:
		var btn := get_node_or_null(str(entry["path"])) as Button
		if btn == null:
			continue
		# 纯入口按钮：不参与呼吸金框提示（那是"现在能出这张牌"的语义）
		btn.set_meta("no_clickable_hint", true)
		var key: String = str(entry["key"])
		var title: String = str(entry["title"])
		var area = entry.get("area")
		btn.pressed.connect(func():
			var cards: Array = MapData.get(key)
			if area != null:
				cards = cards.filter(func(card): return card is BaseEvent and card.get_from() == area)
			_show_card_browser(title, cards)
		)

## 实际移除的卡只从卡牌区读取；令咒登记与 buff 状态不是移除卡。
func _collect_removed_cards(pl_data: Dictionary) -> Array:
	var cards: Array = []
	var zone: Dictionary = pl_data.get("out_of_game", {})
	for key in ["attacks", "skills", "others"]:
		var values = zone.get(key, [])
		if not values is Array:
			continue
		for card in values:
			if card is BaseCard and not cards.has(card):
				cards.append(card)
	return cards

## 本地与复用抽屉共用显隐判据；回调现场取身份与卡牌，不缓存某次刷新数据。
func _refresh_removed_cards_entry(button: Button, pl_data: Dictionary, local: bool) -> void:
	if button == null:
		return
	var removed_cards:Array = _collect_removed_cards(pl_data)
	button.visible = not removed_cards.is_empty()
	button.text = ("🗃 游戏外卡牌 ×%d" if local else "游戏外 ×%d") % removed_cards.size()
	if button.has_meta("removed_cards_bound"):
		return
	button.set_meta("removed_cards_bound", true)
	button.pressed.connect(func():
		var player_id: int = _local_player_id if local else _selected_opponent_id
		if not GameData.player_data_library.has(player_id):
			return
		var current: Dictionary = GameDataManager.get_player_data(player_id)
		_show_card_browser("游戏外", _collect_removed_cards(current))
	)

## 战报入口：战报只在结算后自动弹一次，关掉就找不回来，需要一个常驻入口。
## 按钮本体在场景里（界面右侧垂直居中，位置可视化可调），脚本只接线
func _setup_battle_report_entry() -> void:
	if has_meta("battle_report_entry_bound"):
		return
	set_meta("battle_report_entry_bound", true)
	var btn := get_node_or_null("BtnBattleReport") as Button
	if btn == null:
		return
	# 纯查询入口：不参与呼吸金框提示（那是"现在能出这张牌"的语义）
	btn.set_meta("no_clickable_hint", true)
	# 命中测试按场景树子节点倒序，与 z_index（只影响绘制层叠）无关。
	# 本按钮在场景里声明得比 Middle_MainPlayground 早，于是点击总是先落到战区
	# ——它右侧居中的位置正好压在侦察战区的矩形里，现象就是"按钮点不了、反而点到了侦察"。
	# 按 z_index 语义重排一次，让绘制与命中两套顺序一致
	_reorder_child_by_z(btn)
	btn.pressed.connect(func():
		var res: Dictionary = GameProgress.last_battle_result if GameProgress else {}
		_show_battle_report(res, true)
	)


## 事件架按各战区真实事件重建：卡图/暗置卡背/说明全部取自对象，场景预置卡只当尺寸模板
func _refresh_battlefield_events() -> void:
	var area_names := ["Area_Workshop", "Area_Miyama", "Area_Shinto", "Area_Scout"]
	for i in range(area_names.size()):
		var area_name: String = area_names[i]
		var event_slot := get_node_or_null("Middle_MainPlayground/Battlefields_CenterContainer/%s/VBox/EventSlot" % area_name)
		var cards_row := get_node_or_null("Middle_MainPlayground/Battlefields_CenterContainer/%s/VBox/EventSlot/EventScroll/EventCardsRow" % area_name)
		if cards_row == null:
			if event_slot:
				event_slot.visible = false
			continue
		var evs: Array = []
		if i < MapData.areas.size() and MapData.areas[i] is BaseMapArea:
			evs = (MapData.areas[i] as BaseMapArea)._events
		_rebuild_event_row(cards_row, evs)
		if event_slot:
			event_slot.visible = evs.size() > 0

func _rebuild_event_row(cards_row: Control, events: Array) -> void:
	var card_size := Vector2(160, 226)
	var olds: Array = cards_row.get_children()
	for child in olds:
		if child is TextureRect:
			card_size = (child as TextureRect).custom_minimum_size
			break
	for child in olds:
		cards_row.remove_child(child)
		child.free()
	for ev in events:
		if not (ev is BaseEvent):
			continue
		var card := TextureRect.new()
		card.custom_minimum_size = card_size
		card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		var concealed: bool = bool(ev.get("_is_concealed"))
		if concealed:
			var back: String = str(ev.get("_card_back_img"))
			if back == "" or not LoadHelper.texture_exists(back):
				back = LoadHelper.resolve_card_back("", "", "event")
			if back != "" and LoadHelper.texture_exists(back):
				card.texture = LoadHelper.load_texture(back)
			card.set_meta("zoom_disabled", true)
		else:
			var img: String = str(ev.get("_card_img"))
			if img != "" and LoadHelper.texture_exists(img):
				card.texture = LoadHelper.load_texture(img)
				card.set_meta("zoom_img", img)
			card.set_meta("zoom_disabled", false)
			_bind_zoom_info(card, ev)
		cards_row.add_child(card)

## 常规移动方向箭头：默认低亮，行动阶段高亮当前玩家所在战区相邻的两个方向
func _refresh_movement_arrows() -> void:
	if arrow_ws_miyama == null:
		return
	var dim := Color(0.55, 0.8, 0.95, 0.85)
	var bright := Color(0.25, 1.0, 1.0, 1.0)
	arrow_ws_miyama.modulate = dim
	arrow_miyama_shinto.modulate = dim
	arrow_shinto_scout.modulate = dim
	if GameProgress.current_player_id != _local_player_id:
		return
	var pl_data: Dictionary = GameDataManager.get_player_data(_local_player_id)
	var curr_loc = pl_data.get("location")
	if curr_loc == null:
		return
	var curr_area = curr_loc.get_from()
	if curr_area == null:
		return
	var idx: int = MapData.areas.find(curr_area)
	# 移动只能沿 魔术工房→深山町→新都→侦察 单向，高亮当前区域指向的前进方向
	if idx == 0:
		arrow_ws_miyama.modulate = bright
	elif idx == 1:
		arrow_miyama_shinto.modulate = bright
	elif idx == 2:
		arrow_shinto_scout.modulate = bright
	# idx == 3（侦察）为终点，无前进方向

## 统一的卡面渲染：把"暗置怎么表现"收敛在一处，按 owned（是不是自己的卡）分流。
## owned=true  自己的卡：永远显示卡面，未公开时盖半透明灰遮罩 + 闭眼图标（自己知道是什么牌，
##              但要能一眼看出它对别人是暗的）；
## owned=false 别人的卡：未公开只显示卡背，不给放大也不给说明。
## 卡背取卡自己的 _card_back_img（加载时已按类型/去向定好：御主物品=skill、入牌库=attack、
## 升华技=upgrade_skill、JSON 写了 card_back_img 的用特殊卡背），拿不到才按 fallback_type 兜底。
## show_conceal_mark 由调用方声明这个位置要不要标出"未公开"：
## 打出区/技能区要标（那些牌对别人是暗的，自己得能一眼看出来），
## 手牌区不标——手牌本来只有自己可见，盖闭眼遮罩没有信息量，只会挡住卡面
func _render_card_face(node: TextureRect, obj, owned: bool, fallback_type: String = "skill", show_conceal_mark: bool = true, concealed_override = null) -> void:
	if node == null or obj == null:
		return
	var concealed: bool = bool(concealed_override) if concealed_override != null else (obj is BaseCard and bool(obj.get("_is_concealed")))
	# 未觉醒的升华技：玩家尚未获得这张牌，连拥有者也不给看卡面，一律显示升华技卡背。
	# 与普通暗置牌不同——普通暗置牌是"已有但对别人隐藏"，自己看卡面+灰遮罩即可
	if obj is BaseSkill and not bool(obj.get("_is_awakened")):
		var up_back: String = str(obj.get("_card_back_img")) if obj.get("_card_back_img") != null else ""
		if up_back == "" or not LoadHelper.texture_exists(up_back):
			up_back = LoadHelper.resolve_card_back("", "", "upgrade_skill")
		node.texture = LoadHelper.load_texture(up_back)
		_set_conceal_overlay(node, false)
		_set_inactive_overlay(node, false)
		_sync_modification_badge(node, null)
		node.set_meta("zoom_disabled", true)
		node.remove_meta("zoom_title")
		node.remove_meta("zoom_desc")
		node.remove_meta("zoom_img")
		return
	_set_conceal_overlay(node, concealed and owned and show_conceal_mark)
	if concealed and not owned:
		var back: String = str(obj.get("_card_back_img")) if obj.get("_card_back_img") != null else ""
		if back == "" or not LoadHelper.texture_exists(back):
			back = LoadHelper.resolve_card_back("", "", fallback_type)
		node.texture = LoadHelper.load_texture(back)
		_set_inactive_overlay(node, false)
		_sync_modification_badge(node, null)
		node.set_meta("zoom_disabled", true)
		node.remove_meta("zoom_title")
		node.remove_meta("zoom_desc")
		node.remove_meta("zoom_img")
		return
	var img = obj.get("_card_img")
	if img != null and str(img) != "" and LoadHelper.texture_exists(str(img)):
		node.texture = LoadHelper.load_texture(str(img))
	_set_inactive_overlay(node, _is_card_inactive(obj))
	# 牌背不显示修改标记；明置卡与自己可见的暗置卡按原规则处理。
	if not (owned and concealed):
		_sync_modification_badge(node, obj)
	else:
		_sync_modification_badge(node, null)
	node.set_meta("zoom_disabled", false)
	_bind_zoom_info(node, obj)

## 未公开遮罩：半透明灰 + 闭眼图标。语义是"这张牌已有，但对观看者隐藏"
func _set_conceal_overlay(node: Control, show_overlay: bool) -> void:
	_sync_overlay(node, show_overlay, "ConcealOverlay", CONCEAL_COLOR, CONCEAL_ICON)

## 未激活遮罩：半透明深红。语义是"这张卡还没生效"（御主物品卡对应的buff尚未激活）。
## 与未公开遮罩用不同节点名，两者互不覆盖，可以同时盖在一张卡上
func _set_inactive_overlay(node: Control, show_overlay: bool) -> void:
	_sync_overlay(node, show_overlay, "InactiveOverlay", INACTIVE_COLOR)

const MODIFICATION_BADGE_NAME := "CardModificationBadge"

## 卡牌被效果修改（威力/魔力消耗/属性）的持久提示：金色【改】字标签，点击可查看明细
func _sync_modification_badge(node: Control, obj) -> void:
	if node == null: return
	var has_mods: bool = obj != null and obj.has_method("has_modifications") and obj.has_modifications()
	var badge := node.get_node_or_null(MODIFICATION_BADGE_NAME) as Button
	if not has_mods:
		if badge != null: badge.visible = false
		return
	if badge == null:
		badge = Button.new()
		badge.name = MODIFICATION_BADGE_NAME
		badge.text = "改"
		badge.set_meta("no_clickable_hint", true)
		badge.mouse_filter = Control.MOUSE_FILTER_STOP
		badge.z_index = 3
		badge.add_theme_font_size_override("font_size", 11)
		badge.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35, 1.0))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.08, 0.04, 0.85)
		sb.border_color = Color(1.0, 0.82, 0.3, 1.0)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		badge.add_theme_stylebox_override("normal", sb)
		badge.add_theme_stylebox_override("hover", sb)
		badge.add_theme_stylebox_override("pressed", sb)
		badge.custom_minimum_size = Vector2(22, 22)
		badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
		badge.offset_left = 2
		badge.offset_top = 2
		badge.offset_right = 24
		badge.offset_bottom = 24
		node.add_child(badge)
	badge.visible = true
	badge.set_meta("mod_target_card", obj)
	if not badge.has_meta("mod_click_bound"):
		badge.set_meta("mod_click_bound", true)
		badge.pressed.connect(func():
			var card = badge.get_meta("mod_target_card", null)
			if card != null and card.has_method("get_modification_details"):
				var lines: Array = ["【%s】被效果更改记录：" % card.get_shown_name()]
				for mod in card.get_modification_details():
					lines.append("• " + str(mod.get("detail", "")))
				_show_tactical_confirm("\n".join(lines), true)
		)

## 卡面叠加遮罩的通用实现：用独立 ColorRect 子节点而不是改 modulate，
## 这样不影响卡图本身的色彩，也不干扰放大预览取原图。icon_path 传空串就是纯色遮罩。
## 遮罩名由调用方给：一张卡上可以挂多种遮罩，各自独立显隐
func _sync_overlay(node: Control, show_overlay: bool, overlay_name: String, color: Color, icon_path: String = "") -> void:
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
		# 必须用 and_offsets 版本：只设锚点会为"保持当前矩形"重算 offsets，
		# 新建控件当前是 0×0，于是遮罩永远是 0 尺寸（不报错，只是从不显示）
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.z_index = 1
		node.add_child(overlay)
		if icon_path != "":
			var icon := TextureRect.new()
			icon.name = "OverlayIcon"
			icon.texture = LoadHelper.load_texture(icon_path)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# 纯 UI 装饰，不是卡也不是头像：显式关掉放大，否则它 44×44 接近正方形，
			# 会被扫描当成"头像档"注册进放大系统（尺寸区间与真实头像天然重叠，挡不住）
			icon.set_meta("zoom_disabled", true)
			overlay.add_child(icon)
	overlay.visible = true
	var icon_node := overlay.get_node_or_null("OverlayIcon") as TextureRect
	if icon_node:
		# 图标跟着卡位大小走，卡越小图标越小，始终占卡面约四成宽
		var side: float = maxf(18.0, minf(node.size.x, node.size.y) * 0.40)
		icon_node.custom_minimum_size = Vector2(side, side)
		icon_node.size = Vector2(side, side)
		icon_node.position = (node.size - icon_node.size) * 0.5

## 这张卡是否尚未生效：看它关联的buff此刻是否未激活。
## 没关联buff的卡一律视为已生效——拿不到依据就不遮，宁可少盖也不要盖错
func _is_card_inactive(obj) -> bool:
	var buff = obj.get("_relate_buff")
	if buff == null:
		return false
	return not bool(buff.get("_is_active"))

## 通用 buff 专区渲染：col 是整块容器（控制显隐），row 是纵向列表容器（装每条 buff）。
## 规则：无 buff 时整列隐藏；只显示已激活的 buff（未激活的不占位，玩家看到的就是当前生效的状态）；
## 每条只显示 图标(若有) + 名字 + 层数（1 层不显示层数）；
## buff 效果说明不在状态区里平铺，走右键说明（与卡牌一致的交互），左键/右键关闭。
## 本地信息栏与对手抽屉共用。
func _refresh_buff_zone(col: Control, row: Control, buffs: Array) -> void:
	if col == null or row == null:
		return
	# 只列已激活的：未激活的 buff 是"将来会激活"的卡面信息，不属于当前状态
	var active_buffs: Array = []
	for b in buffs:
		if b != null and bool(b.get("_is_active")):
			active_buffs.append(b)
	col.visible = !active_buffs.is_empty()
	for c in row.get_children():
		_free_runtime_child(c)
	for buff in active_buffs:
		var entry := HBoxContainer.new()
		entry.alignment = BoxContainer.ALIGNMENT_BEGIN
		entry.add_theme_constant_override("separation", 4)
		entry.mouse_filter = Control.MOUSE_FILTER_STOP
		# buff 通常没有图；有也是 token/图标规格，有才加一个小图标
		var bimg: String = str(buff.get("_buff_img")) if buff.get("_buff_img") != null else ""
		if bimg != "" and LoadHelper.texture_exists(bimg):
			var icon := TextureRect.new()
			icon.custom_minimum_size = Vector2(18, 18)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture = LoadHelper.load_texture(bimg)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			entry.add_child(icon)
		var nm := Label.new()
		var lvl = buff.get("_buff_level")
		var lvl_num: int = (lvl.number as int) if lvl is BaseNumber else 1
		nm.text = _object_shown_name(buff) + ((" ×%d" % lvl_num) if lvl_num > 1 else "")
		nm.add_theme_color_override("font_color", Color(0.9, 0.78, 1))
		nm.add_theme_font_size_override("font_size", 12)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.add_child(nm)
		# 效果说明只走右键：绑在整条上，不在列表里占版面。
		# 不设 zoom_disabled（那会连右键说明一起禁掉）；buff 条是容器又没有 zoom_img，
		# _show_zoom_for 取不到贴图会自然跳过放大图，最终只弹说明面板
		_bind_zoom_info(entry, buff)
		entry.remove_meta("zoom_img")
		if not entry.has_meta("buff_left_click_bound"):
			entry.set_meta("buff_left_click_bound", true)
			entry.gui_input.connect(func(ev: InputEvent):
				if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
					_show_zoom_and_desc_for(entry)
					get_viewport().set_input_as_handled()
			)
		row.add_child(entry)

## 采集一个玩家"未加入牌库"的全部卡：从者技能牌、御主技能牌之外，还包括御主自带的
## 专属技能/攻击牌(如阴炁弹)、升华技、附带物(如宝石卡)。本地信息栏与对手抽屉共用同一份
## 采集逻辑，保证呈现口径一致；需要加入牌库的攻击牌由效果说明并搬运，牌库内的不在此重复展示
func _collect_uncataloged_cards(pl_data: Dictionary) -> Array:
	var all_cards: Array = []
	for group in _collect_uncataloged_card_groups(pl_data):
		all_cards += group
	return all_cards


## 同上，但按类别分组返回，顺序固定为：
## 从者技能牌 → 御主技能牌 → 御主自带技能/攻击牌 → 御主附带物 → 升华技（最右）。
## 分组是必要的：这些卡铺在同一行里，若拼成一个扁平数组按下标铺，
## 从者技能牌被打出后数组变短，后面的御主牌会整体前移填补空位——
## 玩家看到的就是"打出从者技能牌后御主牌补了位"。按组铺则各类固定占自己的段落
func _collect_uncataloged_card_groups(pl_data: Dictionary) -> Array:
	var groups: Array = []
	var seen: Array = []
	var append_unique = func(target: Array, values):
		if not values is Array:
			return
		for card in values:
			if card != null and not seen.has(card):
				seen.append(card)
				target.append(card)
	var servant_group: Array = []
	append_unique.call(servant_group, pl_data.get("servant_skills", []))
	append_unique.call(servant_group, pl_data.get("side", {}).get("skills", []))
	groups.append(servant_group)
	var master_group: Array = []
	append_unique.call(master_group, pl_data.get("master_skills", []))
	groups.append(master_group)
	var master = pl_data.get("master")
	if master != null:
		var sp = master.get("_specials")
		if sp is Dictionary:
			var owned_group: Array = []
			append_unique.call(owned_group, sp.get("SKILLS", []))
			append_unique.call(owned_group, sp.get("ATTACKS", []))
			groups.append(owned_group)
		var ot_group: Array = []
		append_unique.call(ot_group, master.get("_other_things"))
		groups.append(ot_group)
		var up_group: Array = []
		append_unique.call(up_group, master.get("_upgrade_skill"))
		groups.append(up_group)
	var removed: Array = _collect_removed_cards(pl_data)
	for i in range(groups.size()):
		groups[i] = groups[i].filter(func(card): return not removed.has(card))
	return groups

## 刷新可点击发动的技能牌：按数据填充卡位（卡图/名字/点击/悬浮说明全部取自数据），
## 卡位位置模板沿用场景预置，数量不足时复用模板动态补位，多余卡位隐藏。
## 顺带刷新自己的状态专区（与对手抽屉共用同一份 buff 渲染逻辑）
func _refresh_clickable_skills(pl_data: Dictionary) -> void:
	_refresh_removed_cards_entry(
		get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_SkillsAndPhantasms/VBox/RackHeader/BtnOutOfGame") as Button,
		pl_data, true
	)
	if skills_scroll_h == null:
		return
	# 自己的卡：未公开的也显示卡面，只盖灰遮罩+闭眼图标（owned 默认 true）。
	# 按组铺：从者技能牌被打出后，御主的牌不会前移来填补空位
	_fill_card_row_by_groups(skills_scroll_h, _collect_uncataloged_card_groups(pl_data), true)
	var my_buffs: Array = []
	var master = pl_data.get("master")
	if master != null:
		var sp = master.get("_specials")
		if sp is Dictionary:
			my_buffs = sp.get("BUFFS", [])
	_refresh_buff_zone(
		get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_MyBuffs"),
		get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_MyBuffs/BuffsH"),
		my_buffs
	)

## 按需要的数量准备好一行的卡位：复用场景预置卡位，回收上一次克隆出来的运行时卡位，
## 不够就克隆第一个卡位补位（插在分隔线之前，保持分区语义），返回全部卡位数组。
## 多余的那部分不在这里隐藏——调用方按自己的数据决定谁可见。
## 卡位回收一律用 _free_runtime_child(remove_child + free)：queue_free 是帧末延迟释放，
## 同一帧内 get_children() 仍会返回旧节点，下面的补位逻辑就会重复补出新卡位
func _ensure_slot_nodes(row: Control, need: int) -> Array:
	if row == null:
		return []
	var slots: Array = []
	var runtime_slots: Array = []
	for child in row.get_children():
		if not (child is Control) or child is Separator:
			continue
		if child.has_meta("skill_slot_runtime"):
			# 上一次刷新克隆出来的卡位：复用而不是销毁重建。
			# 每次刷新都 free 再 duplicate 会让同一帧内的子节点索引反复变动，
			# move_child 插错位置后多张牌会叠在同一处（出牌区卡牌重叠就是这么来的）
			runtime_slots.append(child)
		else:
			slots.append(child)
	if slots.is_empty():
		return slots
	# 预置卡位在前、复用的克隆卡位在后。这个顺序必须与子节点顺序一致：
	# 调用方（_fill_card_row / _fill_card_row_by_groups）是按数组下标往卡位铺卡的，
	# 数组顺序一旦与树序不符，卡就会落到错的分区里。
	slots.append_array(runtime_slots)
	while slots.size() < need:
		var extra_slot: Control = (slots[0] as Control).duplicate()
		extra_slot.set_meta("skill_slot_runtime", true)
		_clear_runtime_slot_metas(extra_slot)
		# 补位卡位追加到行尾。曾经把它 move_child 到分隔线之前"保住分区语义"，
		# 结果数组顺序变成[预置…, 克隆]而树序是[分隔线前的预置…, 克隆, 分隔线, 分隔线后的预置…]，
		# 两套顺序不一致，全部按 need 铺卡的行都会错位——实测升华技因此出现在从者技能牌旁边。
		# 分隔线只是行内的视觉分区，多出来的卡本来就应该往后长。
		row.add_child(extra_slot)
		slots.append(extra_slot)
	# 多余的克隆卡位隐藏即可（调用方会按 need 逐个设 visible），
	# 但要确保它们不残留在可见状态盖住别的卡
	for i in range(need, slots.size()):
		var spare := slots[i] as Control
		if spare != null and spare.has_meta("skill_slot_runtime"):
			spare.visible = false
	return slots

## 立即回收一个运行时新建的子节点：先摘出场景树再 free。
## 不用 queue_free——它帧末才释放，同一帧内父节点的 get_children() 仍会返回该节点，
## 凡"数一数够不够、不够就克隆补位"的刷新逻辑都会因此每次刷新重复补位
func _free_runtime_child(node: Node) -> void:
	if node == null or !is_instance_valid(node):
		return
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.free()

## 把重复的牌合并成一项：同名、同卡图、同卡面数值、同"未公开/尚未生效"表现的多张牌
## 只占一个卡位，数量交给角标表达。手牌区不走这里（每张牌都要能单独点出）。
## 键只由"显示上真的看不出差别"的字段组成，避免把表现不同的牌合到一起
func _group_repeated_cards(cards: Array) -> Array:
	var groups: Array = []
	var key_to_index: Dictionary = {}
	for card in cards:
		if card == null:
			continue
		var key: String = "%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
			str(card.get("_name")),
			str(card.get("_card_img")),
			str(card.get("_card_back_img")),
			str(card.get("_zoom_kind")),
			str(card.get("_category")),
			str(_number_text(card.get("_power"))),
			str(_number_text(card.get("_cost"))),
			_card_visual_state_key(card),
			_card_relation_key(card),
		]
		if key_to_index.has(key):
			var existed: Dictionary = groups[int(key_to_index[key])]
			existed["count"] = int(existed["count"]) + 1
			continue
		key_to_index[key] = groups.size()
		groups.append({"card": card, "count": 1})
	return groups


## 一张牌在界面上的"表现状态"：未公开与否、尚未生效与否。
## 状态不同的同名卡不能合并——合并会让玩家以为那张暗置的牌也能点、也生效
func _card_visual_state_key(card) -> String:
	return "%s/%s" % [str(bool(card.get("_is_concealed"))), str(_is_card_inactive(card))]


func _card_relation_key(card) -> String:
	var buff = card.get("_relate_buff")
	if buff == null:
		return "none"
	return "%s/%s/%s" % [str(buff.get("_name")), str(buff.get("_is_active")), str(buff.get("_buff_level"))]


## 取数字的显示值：BaseNumber 用 .number，其余原样
func _number_text(value) -> String:
	if value is BaseNumber:
		return str(value.number)
	return str(value)


## 卡位上的数量角标：数量大于 1 才显示（1 张不写量词）。
## 角标挂在卡图节点上而不是卡位上——卡位可能是容器（VBox），挂在容器上会被当成又一个列表项排版。
## 节点按需创建、之后只改文本，避免每次刷新都新建
func _set_slot_count_badge(slot: Control, count: int) -> void:
	if slot == null:
		return
	var hosts := _card_texture_nodes(slot)
	var host: Control = hosts[0] if hosts.size() > 0 else slot
	var badge := host.get_node_or_null(COUNT_BADGE_NAME) as Label
	if count <= 1:
		if badge != null:
			badge.visible = false
		return
	if badge == null:
		badge = Label.new()
		badge.name = COUNT_BADGE_NAME
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_font_size_override("font_size", 14)
		badge.add_theme_color_override("font_color", Color(1.0, 0.9, 0.45))
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		badge.add_theme_constant_override("outline_size", 5)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		host.add_child(badge)
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		# 明确放在卡图右上角内部；只有锚点没有 offsets 时，Label 最小尺寸会向卡外延伸。
		badge.offset_left = -48
		badge.offset_top = 4
		badge.offset_right = -4
		badge.offset_bottom = 30
	badge.text = "×%d" % count
	badge.visible = true


## 通用卡位行填充：给定一个容器和一组卡对象，按场景预置的卡位模板铺开，
## 数量不足时克隆模板补位，多余隐藏。clickable=false 用于对手抽屉等只展示不可发动的场景，
## owned=false 表示这是别人的卡（未公开只显示卡背）。
## 本地信息栏与对手抽屉共用同一套铺卡逻辑，暗置/明置由 _render_card_face 统一处理
func _fill_card_row_from_list(row: Control, cards: Array, clickable: bool, owned: bool = true, merge_repeated: bool = true) -> void:
	var groups: Array = _group_repeated_cards(cards) if merge_repeated else []
	if not merge_repeated:
		for card in cards:
			if card != null:
				groups.append({"card":card, "count":1})
	var slots: Array = _ensure_slot_nodes(row, groups.size())
	if slots.is_empty():
		return
	for i in range(slots.size()):
		var slot := slots[i] as Control
		var group = groups[i] if i < groups.size() else null
		if group == null:
			slot.visible = false
			_set_slot_count_badge(slot, 0)
			continue
		slot.visible = true
		var card_obj = group["card"]
		if card_obj is BaseSkill:
			_fill_skill_slot(slot, card_obj, clickable, owned)
		else:
			# 只对自己接主动发动入口：对手抽屉里的卡不发动
			_fill_display_slot(slot, card_obj, owned, _manual_effects_of(card_obj) if owned else [])
		_set_slot_count_badge(slot, int(group["count"]))
	# 分隔线本身不承载数据：只有它后面还有可见卡位时才显示，
	# 否则卡少了会留一条孤零零的分隔线
	_refresh_row_separators(row)

## 按分组铺卡：每组占用固定宽度的卡位段落，段内不足的位置留空而不是让后面的组前移。
## 占位宽度取"本局内该组出现过的最多张数"，记在容器上按需增长——
## 不写死每组容量（各御主/从者带的牌数不同，效果还能增减）。
## 某组临时变少（技能牌被打出）时空位保留，玩家看到的位置是稳定的
func _fill_card_row_by_groups(row: Control, groups: Array, clickable: bool, owned: bool = true) -> void:
	if row == null:
		return
	var widths: Array = row.get_meta("group_slot_widths", [])
	# 每组的段落宽度只增不减：这样某组暂时空了也不会让后面的组挪位置
	while widths.size() < groups.size():
		widths.append(0)
	var plan: Array = []
	for i in range(groups.size()):
		var merged: Array = _group_repeated_cards(groups[i])
		if merged.size() > int(widths[i]):
			widths[i] = merged.size()
		plan.append(merged)
	row.set_meta("group_slot_widths", widths)
	var need: int = 0
	for w in widths:
		need += int(w)
	var slots: Array = _ensure_slot_nodes(row, need)
	if slots.is_empty():
		return
	var cursor: int = 0
	for i in range(plan.size()):
		var merged: Array = plan[i]
		for j in range(int(widths[i])):
			if cursor >= slots.size():
				break
			var slot := slots[cursor] as Control
			cursor += 1
			if j >= merged.size():
				# 该组的空位：隐藏但仍占着位置，后面的组因此不会前移
				slot.visible = false
				_set_slot_count_badge(slot, 0)
				continue
			slot.visible = true
			var card_obj = merged[j]["card"]
			if card_obj is BaseSkill:
				_fill_skill_slot(slot, card_obj, clickable, owned)
			else:
				# 只对自己接主动发动入口：对手抽屉里的卡不发动
				_fill_display_slot(slot, card_obj, owned, _manual_effects_of(card_obj) if owned else [])
			_set_slot_count_badge(slot, int(merged[j]["count"]))
	# 计划之外的多余卡位一律隐藏
	while cursor < slots.size():
		var extra := slots[cursor] as Control
		extra.visible = false
		_set_slot_count_badge(extra, 0)
		cursor += 1
	_refresh_row_separators(row)


## 行内分隔线按"其后是否还有可见卡位"显隐
func _refresh_row_separators(row: Control) -> void:
	var children := row.get_children()
	for i in range(children.size()):
		var child := children[i]
		if !(child is Separator):
			continue
		var has_visible_after: bool = false
		for j in range(i + 1, children.size()):
			var sib := children[j]
			if sib is Control and (sib as Control).visible and not (sib is Separator):
				has_visible_after = true
				break
		child.visible = has_visible_after

## 克隆出的卡位要清掉复制来的绑定痕迹，否则放大/点击系统会误以为已经接过线
## （继承了 *_bound 标记就不会再接线；继承了 click_* 会在回调里取到上一次的对象）
func _clear_runtime_slot_metas(node: Node) -> void:
	for key in ["zoom_bound", "skill_click_bound", "hand_click_bound", "click_skill", "click_hand_card", "playable_hint",
			"regular_hover_bound", "regular_play_modes", "regular_play_card", "regular_play_selected",
			"pending_regular_card", "pending_regular_click_bound", "pending_regular_card_bound",
			"display_object", "manual_effect_click_bound"]:
		if node.has_meta(key):
			node.remove_meta(key)
	# duplicate() 默认带 DUPLICATE_SIGNALS：克隆体会继承源卡位的信号连接，而那些 Callable
	# 已经 bind 了源卡位本身。只清 *_bound 标记会让克隆体再接一次线，结果一次点击触发两个
	# 回调，继承的那个仍作用在上一张卡上（表现为"点第二张撤回了第一张"）。
	# 断开是按连接表遍历的通用动作，不针对某个具体回调写死。
	_disconnect_inherited_signals(node)
	# 运行时生成的明暗按钮条不能被克隆继承：duplicate 会把信号连接一起复制，
	# 继承下来的按钮仍绑在上一个卡位的回调上，点新卡位会打到旧卡
	for child in node.get_children():
		if str(child.name) == "RegularPlayModes":
			node.remove_child(child)
			child.free()
			continue
		_clear_runtime_slot_metas(child)

## 断开克隆体从源节点继承来的信号连接。
## 只断"目标对象是本控制器"的那些——它们是刷新函数接的线，Callable 里已经 bind 了源卡位；
## 节点自身内部的连接（Container 的布局信号等）与本控制器无关，不能动。
## 按连接表遍历，新增任何一种卡位回调都不必再改这里。
func _disconnect_inherited_signals(node: Node) -> void:
	for sig in node.get_signal_list():
		var sig_name: String = str(sig.get("name", ""))
		for conn in node.get_signal_connection_list(sig_name):
			var callable: Callable = conn.get("callable")
			if callable.get_object() == self:
				node.disconnect(sig_name, callable)

## 取一个卡位里承载卡图的所有 TextureRect：卡位可能是含子 TextureRect 的容器（底栏卡位），
## 也可能本身就是一个 TextureRect（抽屉里的简易卡位）。两种结构都要支持，
## 否则按其中一种写死会让另一种静默不渲染（表现为卡位数量对但全是空白/旧图）
func _card_texture_nodes(slot: Control) -> Array:
	if slot is TextureRect:
		return [slot]
	var result: Array = []
	for node in slot.find_children("*", "TextureRect", true, false):
		if _is_overlay_art(node):
			continue
		result.append(node)
	return result

## 该节点是否位于某层遮罩之下（遮罩本体与它的装饰图标都算）。
## 遮罩是挂在卡图节点上的叠加层，不是承载卡图的节点：递归收集卡图时必须排除，
## 否则下一次刷新会把遮罩里的闭眼图标当成卡图改写贴图，还会在图标里再套一层遮罩，
## 表现为"图标变成灰底缩略图"且节点每刷新一次成对增长
func _is_overlay_art(node: Node) -> bool:
	var p := node.get_parent()
	while p != null and p != self:
		if str(p.name) in OVERLAY_NODE_NAMES:
			return true
		p = p.get_parent()
	return false

## 只展示不发动的卡位（御主攻击牌/附带物等：打出由效果负责，不接点击）。
## owned 决定未公开时的表现：自己的卡显示卡面+灰遮罩，别人的卡显示卡背
func _fill_display_slot(slot: Control, obj, owned: bool = true, manual_effects: Array = []) -> void:
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.set_meta("click_skill", null)
	#卡位会复用，回调里现取对象而不是把对象绑进 Callable
	slot.set_meta("display_object", obj)
	var concealed: bool = obj is BaseCard and bool(obj.get("_is_concealed"))
	# 别人的暗置牌不暴露名字；自己的暗置牌名字照显（卡面都能看见，没有隐藏的意义）
	var shown: String = "" if (concealed and not owned) else _object_shown_name(obj)
	#声明了可主动发动的效果时，这个卡位同时是发动入口：亮呼吸金框并接点击。
	#没声明的卡位保持"只展示不发动"，不给玩家空点的假提示
	var hint_node: Control = _card_art_of(slot)
	if hint_node == null:
		hint_node = slot
	hint_node.set_meta("playable_hint", not manual_effects.is_empty())
	if not manual_effects.is_empty():
		if not _clickable_nodes.has(hint_node):
			_apply_clickable_indicator(hint_node, Color(1.0, 0.85, 0.3, 1.0))
		_set_clickable_active(hint_node, true)
		if not slot.has_meta("manual_effect_click_bound"):
			slot.set_meta("manual_effect_click_bound", true)
			slot.gui_input.connect(_on_manual_effect_slot_clicked.bind(slot))
		#卡图节点默认是 MOUSE_FILTER_STOP，会吃掉落在卡面上的点击，只把回调接在卡位上
		#等于点不动（卡位里只有卡图以外的空隙能触发）。待确认出牌卡位同样是槽位与卡图
		#两处都接，这里沿用同一做法；hint_node 就是 slot 时不需要重复接
		if hint_node != slot and not hint_node.has_meta("manual_effect_click_bound"):
			hint_node.set_meta("manual_effect_click_bound", true)
			hint_node.gui_input.connect(_on_manual_effect_slot_clicked.bind(slot))
	else:
		_set_clickable_active(hint_node, false)
	for sub in _card_texture_nodes(slot):
		sub.set_meta("clickable", not manual_effects.is_empty())
		sub.set_meta("playable_hint", not manual_effects.is_empty())
		if not manual_effects.is_empty():
			sub.set_meta("clickable_color", Color(1.0, 0.85, 0.35, 1.0))
		_render_card_face(sub, obj, owned, _card_back_type_of(obj))
	for lbl in slot.find_children("*", "Label", true, false):
		if str(lbl.name) == COUNT_BADGE_NAME:
			continue
		lbl.text = shown
		lbl.visible = shown != ""


## 卡位上的主动发动入口（宝石这类能力）：从卡位现取对象再请求发动。
## 效果能不能发动由引擎判，界面只在拿不到可发动效果时不动作
func _on_manual_effect_slot_clicked(ev: InputEvent, slot: Control) -> void:
	if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed):
		return
	var obj = slot.get_meta("display_object", null)
	var usable: Array = _manual_effects_of(obj)
	if usable.is_empty():
		return
	EffectManager.request_manual_activation(usable[0], _local_player_id)
	_refresh_pending_input_tip()
	refresh_all_ui()


## 把一个技能数据填进卡位：卡图、名字标签、点击发动、悬浮说明。
## owned 决定未公开时的表现（同 _fill_display_slot）；别人的暗置牌不可点击发动
func _fill_skill_slot(slot: Control, skill: BaseSkill, clickable: bool = true, owned: bool = true) -> void:
	#本地待确认技能牌先从技能区视觉上移到出牌区；数据仍在原区，撤销可无损恢复
	if owned and _regular_play_pending_cards.has(skill):
		slot.visible = false
		return
	slot.visible = true
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	var concealed: bool = bool(skill.get("_is_concealed"))
	var hidden_from_viewer: bool = concealed and not owned
	# 点击回调不绑定具体技能，改由卡位上的 metadata 现取，
	# 避免卡位复用后旧连接残留导致触发到上一次的技能
	var modes: Array = _regular_play_modes(skill) if clickable and not hidden_from_viewer else []
	var manual_effects:Array = _manual_effects_of(skill) if clickable and owned and not hidden_from_viewer else []
	slot.set_meta("display_object", skill)
	slot.set_meta("click_skill", null)
	_setup_regular_play_slot(slot, skill, modes)
	# 金框与"此刻能不能出"的状态必须落在同一个节点上，并且金框只圈卡图那一层。
	# 节流刷新是遍历"记进 _clickable_nodes 的那个节点"读 playable_hint 的：状态若留在卡位、
	# 框却画在卡图上，卡位读不到状态就会落进"轮到我 = 亮着"的兜底分支——症状是技能在自己
	# 回合的非行动阶段（前哨、战斗结算）也跟着闪金框。
	var hint_node: Control = _card_art_of(slot)
	if hint_node == null:
		hint_node = slot
	hint_node.set_meta("playable_hint", not modes.is_empty() or not manual_effects.is_empty())
	if (not modes.is_empty() or not manual_effects.is_empty()) and not _clickable_nodes.has(hint_node):
		_apply_clickable_indicator(hint_node, Color(1.0, 0.85, 0.3, 1.0))
	_set_clickable_active(hint_node, not modes.is_empty() or not manual_effects.is_empty())
	if not slot.has_meta("skill_click_bound"):
		slot.set_meta("skill_click_bound", true)
		slot.gui_input.connect(_on_skill_slot_clicked.bind(slot))
	var skill_name: String = "" if hidden_from_viewer else _object_shown_name(skill)
	for sub in _card_texture_nodes(slot):
		sub.set_meta("clickable", not modes.is_empty() or not manual_effects.is_empty())
		# 卡图会截获真实鼠标输入，常规出牌回调也必须接在卡图本身；
		# 回调内部按当前 modes 分流，行动阶段优先常规出牌，其它阶段才尝试手动能力。
		if not sub.has_meta("skill_click_bound"):
			sub.set_meta("skill_click_bound", true)
			sub.gui_input.connect(_on_skill_slot_clicked.bind(slot))
		# 卡图层的这一份供扫描式提示读取（战区子孙节点的提示也按它判断）
		sub.set_meta("playable_hint", not modes.is_empty() or not manual_effects.is_empty())
		if not modes.is_empty() or not manual_effects.is_empty():
			sub.set_meta("clickable_color", Color(1.0, 0.85, 0.35, 1.0))
		if not manual_effects.is_empty() and not sub.has_meta("manual_effect_click_bound"):
			sub.set_meta("manual_effect_click_bound", true)
			sub.gui_input.connect(_on_manual_effect_slot_clicked.bind(slot))
		_render_card_face(sub, skill, owned, _card_back_type_of(skill))
	for lbl in slot.find_children("*", "Label", true, false):
		if str(lbl.name) == COUNT_BADGE_NAME:
			continue
		lbl.text = skill_name
		lbl.visible = skill_name != ""

## 卡没有自带卡背时的兜底类型：升华技→升华技卡背，攻击牌→攻击牌卡背，其余→技能卡背。
## 正常情况卡在加载时就有 _card_back_img，这里只是防止数据缺失时显示空白
func _card_back_type_of(obj) -> String:
	if obj is BaseAttack:
		return "attack"
	return "skill"

## 卡位点击：从卡位 metadata 取当前技能后发动
func _on_skill_slot_clicked(ev: InputEvent, slot: Control) -> void:
	if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed):
		return
	var card = slot.get_meta("regular_play_card", null)
	var modes: Array = slot.get_meta("regular_play_modes", [])
	if card is BaseSkill and not modes.is_empty():
		# 技能牌与手牌攻击牌共用常规出牌入口，避免单独路径绕过门槛、费用和整组规则。
		# 明置/暗置按钮负责选择模式；点击卡体默认选择唯一合法模式。
		if modes.size() == 1:
			_choose_regular_play_mode(card, bool(modes[0]))
		return
	var usable:Array = _manual_effects_of(slot.get_meta("display_object", null))
	if not usable.is_empty():
		EffectManager.request_manual_activation(usable[0], _local_player_id)
		_refresh_pending_input_tip()
		refresh_all_ui()


func _connect_player_actions() -> void:
	if btn_end_phase and not btn_end_phase.pressed.is_connected(_on_end_phase_pressed):
		btn_end_phase.pressed.connect(_on_end_phase_pressed)
	var undo := get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_PlayBattleZone/VBox/ZoneHeader/BtnUndoRegularPlay") as Button
	if undo != null and not undo.pressed.is_connected(_undo_regular_play_selection):
		undo.pressed.connect(_undo_regular_play_selection)

func _regular_hidden() -> Array:
	var flags: Array = []
	for card in _card_select_picked:
		flags.append(_card_select_hidden.get(card, false))
	return flags

func _open_regular_play(card = null) -> void:
	# 保留兼容入口，但常规出牌不再打开中央选牌面板。
	if card != null and not _regular_play_modes(card).is_empty():
		refresh_all_ui()

## 返回固定这张牌及模式后，是否至少存在一个可完成的合法整组。
## false=明置，true=暗置；全部规则委托给 RegularPlay.validate，UI 不复制费用/区域规则。
func _pending_regular_magic_cost(pl_data:Dictionary) -> float:
	var total:float = 0.0
	for i in range(_regular_play_pending_cards.size()):
		if i < _regular_play_pending_hidden.size() and not bool(_regular_play_pending_hidden[i]):
			total += RegularPlay.cost(_regular_play_pending_cards[i], pl_data)
	return total


## 待确认出牌的威力预览：逐张按"这张牌计不计威力"的规则累加，规则与真实提交共用
## CardCountsPower（暗置单取其暂存的明暗标记），UI 不自己判断暗置与例外效果。
## 与 _pending_regular_magic_cost 同一套做法：确认前只算预览，不写 power，
## 所以撤回某张牌时预览自动消失，不需要反向改资源。
func _pending_regular_power() -> int:
	var counts = CardCountsPower.new()
	var total:int = 0
	for i in range(_regular_play_pending_cards.size()):
		var card = _regular_play_pending_cards[i]
		if not (card is BaseHandCard):
			continue
		var hidden:bool = i < _regular_play_pending_hidden.size() and bool(_regular_play_pending_hidden[i])
		if counts.counts_when_played(card, hidden, _local_player_id):
			total += (card._power as BaseNumber).number
	return total


func _regular_play_modes(card) -> Array:
	if card == null or EffectManager.is_waiting_for_choice() or EffectManager.is_waiting_for_card_selection(): return []
	return RegularPlay.pending_modes(_local_player_id, _regular_play_pending_cards, _regular_play_pending_hidden, card)

func _choose_regular_play_mode(card, hidden: bool) -> void:
	if _is_debug_console_blocking_progress():
		return
	if str(_pending_tactical_action.get("type", "")) == "regular_play":
		return
	if not _regular_play_modes(card).has(hidden):
		return
	_regular_play_pending_cards.append(card)
	_regular_play_pending_hidden.append(hidden)
	refresh_all_ui()
	#还可以继续打时不打断玩家；只有没有合法后续且已满足最低要求时才询问确认
	if !RegularPlay.pending_has_legal_add(_local_player_id, _regular_play_pending_cards, _regular_play_pending_hidden) \
			and RegularPlay.can_submit_group(_local_player_id, _regular_play_pending_cards, _regular_play_pending_hidden):
		_show_regular_play_confirm(false)


func _show_regular_play_confirm(end_action_after_submit:bool = false) -> void:
	if !RegularPlay.can_submit_group(_local_player_id, _regular_play_pending_cards, _regular_play_pending_hidden):
		return
	_regular_play_confirm_ends_action = end_action_after_submit
	var lines:Array = ["确认打出以下卡牌"]
	for i in range(_regular_play_pending_cards.size()):
		var card = _regular_play_pending_cards[i]
		lines.append("%s　%s" % [card.get_shown_name(), "暗置" if bool(_regular_play_pending_hidden[i]) else "明置"])
	_pending_tactical_action = {"type":"regular_play"}
	_show_tactical_confirm("\n".join(lines), false)


func _undo_regular_play_selection() -> void:
	if _regular_play_pending_cards.is_empty():
		return
	_regular_play_pending_cards.pop_back()
	_regular_play_pending_hidden.pop_back()
	#撤销选择也撤销尚未执行的确认，不产生任何资源或卡牌副作用
	_pending_tactical_action.clear()
	if tactical_confirm_modal:
		tactical_confirm_modal.visible = false
	refresh_all_ui()

func _setup_regular_play_slot(slot: Control, card, modes: Array) -> void:
	slot.set_meta("regular_play_modes", modes)
	slot.set_meta("regular_play_card", card)
	var bar := slot.find_child("RegularPlayModes", true, false) as HBoxContainer
	if bar == null:
		bar = HBoxContainer.new()
		bar.name = "RegularPlayModes"
		# 按钮压在卡位内部的顶部：卡位上方属于父容器（手牌托盘 clip_contents），
		# 放到外侧会被裁掉，玩家看不到也就点不到
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
		bar.offset_top = 0.0
		bar.offset_bottom = 32.0
		bar.alignment = BoxContainer.ALIGNMENT_CENTER
		bar.z_index = 20
		bar.mouse_filter = Control.MOUSE_FILTER_STOP
		# 挂在卡图节点上：卡位若是 Container，直接挂会被内容边距缩进；
		# 卡图不是容器，锚点按卡位矩形生效，两种卡位结构都通用
		var host: Control = slot
		for sub in _card_texture_nodes(slot):
			if sub is Control and not (sub is Container):
				host = sub
				break
		host.add_child(bar)
		for hidden in [false, true]:
			var button := Button.new()
			button.text = "暗置" if hidden else "明置"
			button.custom_minimum_size = Vector2(82, 30)
			button.z_index = 21
			button.mouse_filter = Control.MOUSE_FILTER_STOP
			button.set_meta("hidden_mode", hidden)
			button.pressed.connect(func(): _choose_regular_play_mode(slot.get_meta("regular_play_card"), bool(button.get_meta("hidden_mode"))))
			bar.add_child(button)
	if not slot.has_meta("regular_hover_bound"):
		slot.set_meta("regular_hover_bound", true)
		slot.mouse_entered.connect(func(): bar.visible = not (slot.get_meta("regular_play_modes", []) as Array).is_empty())
		slot.mouse_exited.connect(func(): call_deferred("_hide_regular_bar_if_outside", slot, bar))
	# 显隐以"鼠标此刻在不在这个卡位上"为准，不能无条件置 false：
	# mouse_entered 只在跨入那一刻发一次，刷新把按钮收掉后鼠标已经停在卡上，
	# 不会再有进入事件，按钮就再也不出现了
	bar.visible = not modes.is_empty() and _pointer_over_regular_slot(slot, bar)
	for child in bar.get_children():
		child.visible = modes.has(bool(child.get_meta("hidden_mode")))
	slot.set_meta("regular_play_selected", false)

## 鼠标此刻是否停在这个卡位（或它的明暗按钮条）上。刷新与收起共用同一判据
func _pointer_over_regular_slot(slot: Control, bar: Control) -> bool:
	if slot == null:
		return false
	var mouse := get_viewport().get_mouse_position()
	if slot.get_global_rect().grow(4.0).has_point(mouse):
		return true
	return bar != null and is_instance_valid(bar) and bar.get_global_rect().grow(4.0).has_point(mouse)

func _hide_regular_bar_if_outside(slot: Control, bar: Control) -> void:
	if bar == null or not is_instance_valid(bar):
		return
	if not _pointer_over_regular_slot(slot, bar):
		bar.visible = false

func _on_hand_card_clicked(card: BaseAttack) -> void:
	_open_regular_play(card)


func _on_end_phase_pressed() -> void:
	if _is_debug_console_blocking_progress():
		return
	if GameProgress.current_player_id != _local_player_id:
		return
	#行动结束的声明式前置条件：与引擎共用同一份判据，不满足时说出原因而不是静默无反应
	if str(GameProgress.get_current_phase().get("name", "")) == "action":
		var requirement_block: String = ActionRules.block_reason(_local_player_id)
		if requirement_block != "":
			_show_tactical_confirm(requirement_block, true)
			return
	if str(GameProgress.get_current_phase().get("name", "")) == "action" \
			and not _regular_play_pending_cards.is_empty():
		if RegularPlay.can_submit_group(_local_player_id, _regular_play_pending_cards, _regular_play_pending_hidden):
			_show_regular_play_confirm(true)
		else:
			_show_tactical_confirm("尚未满足常规出牌最低要求", true)
		return
	GameProgress.end_current_player_action()
	refresh_all_ui()

## -------------------------------------------------------------
## 战区点击交互接线：根据当前阶段统一处理【前哨阶段部署】与【行动阶段移动】
## -------------------------------------------------------------
func _connect_battlefield_movement() -> void:
	for node in [area_workshop, area_miyama, area_shinto, area_scout]:
		if node == null:
			continue
		var area_node := node as Control
		area_node.mouse_filter = Control.MOUSE_FILTER_STOP
		# 下标在点击时按实例查（_area_index_of_node），不预先写死
		area_node.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
				_on_battlefield_clicked(_area_index_of_node(area_node))
		)

func _on_battlefield_clicked(target_area_idx: int) -> void:
	if _is_debug_console_blocking_progress():
		return
	# 选项级位置选择优先消费地图点击：效果声明决定何时进入这条分支，常规部署/移动规则不被改写。
	var pending_location:Dictionary = EffectManager.get_pending_location_selection()
	if !pending_location.is_empty():
		if target_area_idx < 0 or target_area_idx >= MapData.areas.size():
			return
		var spec: Dictionary = pending_location.get("spec", {})
		var selected:BaseLocation = _first_effect_location_target(MapData.areas[target_area_idx], spec)
		if selected == null:
			_show_tactical_confirm("【%s】没有可用的位置" % MapData.areas[target_area_idx]._area_name, true)
			return
		EffectManager.submit_location_selection(pending_location["effect"], selected)
		_refresh_pending_input_tip()
		_refresh_clickable_strength()
		refresh_all_ui()
		return
	# 能不能点由 _area_action_block_reason 一处决定（呼吸光晕用的是同一条判据）。
	# 不能操作时把原因提示出来，不让玩家面对"点了没反应"
	var blocked := _area_action_block_reason(target_area_idx)
	if blocked != "":
		_show_tactical_confirm(blocked, true)
		return
	var phase_name := str(GameProgress.get_current_phase().get("name", ""))
	if phase_name == "outpost":
		_prepare_battlefield_deploy_confirm(target_area_idx)
	elif phase_name == "action":
		_prepare_battlefield_move_confirm(target_area_idx)


# 效果搬运目标由效果自己的 select_location.target_slot 声明：
# - "unlimited"：只选 _pl_num_limit == -1 的无限位（令咒移动按基础规则摆在地利旁边）
# - 未声明：沿用原行为，取第一个能容纳玩家的席位；其他卡效仍可移动到地利位
# 缺少或不认识的规则值不猜，按默认行为处理；不按卡名/角色名分支。
func _first_effect_location_target(area:BaseMapArea, spec:Dictionary = {}) -> BaseLocation:
	if area == null:
		return null
	var target_slot:String = str(spec.get("target_slot", ""))
	var is_workshop_or_scout: bool = area == MapData.magic_workshop or area == MapData.scout
	for loc:BaseLocation in area._locations:
		# 规则：魔术工房与侦察战区严禁移入无限格，只能移到这两个区域的合法有限席位上；
		# 有限席位全满时判定为无法移动
		if is_workshop_or_scout:
			if loc._pl_num_limit != -1 and loc._players.size() < loc._pl_num_limit:
				return loc
			continue
		if target_slot == "unlimited":
			if loc._pl_num_limit == -1:
				return loc
			continue
		if loc._pl_num_limit == -1 or loc._players.size() < loc._pl_num_limit:
			return loc
	return null

## 【前哨阶段】准备部署确认
func _prepare_battlefield_deploy_confirm(target_area_idx: int) -> void:
	if target_area_idx < 0 or target_area_idx >= MapData.areas.size():
		return
	var area: BaseMapArea = MapData.areas[target_area_idx]
	# 落点判定与 AI 部署、呼吸光晕共用同一个函数：界面说能部署的席位就是实际会用的席位。
	# 哪些战区可部署由地图数据声明(_can_deploy)，不在这里写死下标
	var target_loc: BaseLocation = _pick_open_deploy_location(area)
	if target_loc == null:
		_show_tactical_confirm("【%s】没有可用的部署席位" % area._area_name, true)
		return
	
	_pending_tactical_action = {
		"type": "deploy",
		"target_loc": target_loc,
		"area_name": area._area_name
	}
	
	var deploy_costs: Array[String] = []
	var deploy_text := _attach_cost_line("部署至【%s】· %s" % [area._area_name, _slot_benefit_desc(target_loc)], deploy_costs)
	_show_tactical_confirm(deploy_text)

## 席位收益文案：按落点自己声明的印刷数字生成（充能位报魔力、地利位报地利），
## 不写死"核心充能席/最高地利高台"这类描述，地图数据改了文案自动跟着变
func _slot_benefit_desc(loc: BaseLocation) -> String:
	if loc == null:
		return ""
	var parts: Array[String] = []
	var magic_gain: int = (loc._magic as BaseNumber).number
	var benefit: int = (loc._benefit as BaseNumber).number
	if magic_gain > 0:
		parts.append("魔力 +%d" % magic_gain)
	if benefit > 0:
		parts.append("地利 %d" % benefit)
	if parts.is_empty():
		return "常规席位"
	return " · ".join(parts)

## 【行动阶段】准备移动确认
func _prepare_battlefield_move_confirm(target_area_idx: int) -> void:
	var pl_data: Dictionary = GameDataManager.get_player_data(_local_player_id)
	if IsEngaged.new().exec(_local_player_id):
		_show_tactical_confirm("处于交战状态，无法移动", true)
		return
	var curr_area := _local_current_area(pl_data)
	if curr_area == null:
		return
	var current_idx: int = MapData.areas.find(curr_area)
	if current_idx == -1:
		return
	var step_diff: int = target_area_idx - current_idx
	
	# 规则：只能向右单向前进。不能直接 return，否则玩家点击后没有任何反馈
	if step_diff <= 0:
		_show_tactical_confirm("移动只能沿单方向前进", true)
		return
	
	var target_area_name: String = MapData.areas[target_area_idx]._area_name
	# 费用测算与可操作性判据共用同一个函数，避免两处各算一套
	var total_cost: int = _estimate_move_cost(pl_data, step_diff)
	if !_is_magic_enough_for_move(pl_data, total_cost):
		var alert_text := "移动至【%s】\n所需资源：魔力 %d\n当前魔力不足" % [target_area_name, total_cost]
		_show_tactical_confirm(alert_text, true)
		return
	
	_pending_tactical_action = {
		"type": "move",
		"step_diff": step_diff,
		"target_area_idx": target_area_idx,
		"target_area_name": target_area_name
	}
	
	var move_costs: Array[String] = []
	if total_cost > 0:
		move_costs.append("魔力 %d" % total_cost)
	_show_tactical_confirm(_attach_cost_line("移动至【%s】" % target_area_name, move_costs))

## 取走并展示效果产生的提示消息。
## 手动能力的成功结算走独立“发动结果”弹窗；普通规则提示仍复用纯提示框。
## 结果框显示期间不取普通消息，避免两类提示互相覆盖。
func _flush_effect_messages() -> void:
	if _local_player_id < 0:
		return
	if effect_result_modal != null and effect_result_modal.visible:
		return
	if tactical_confirm_modal != null and tactical_confirm_modal.visible:
		return
	var results:Array = EffectManager.pop_effect_results(_local_player_id)
	var result_texts:Array[String] = []
	for result in results:
		var result_text := str(result)
		if result_text != "" and not result_texts.has(result_text):
			result_texts.append(result_text)
	if not result_texts.is_empty():
		_show_effect_result("\n".join(result_texts))
		return
	# 能力询问正在显示时，普通提示留在队列中，等询问处理完再展示。
	if effect_modal != null and effect_modal.visible:
		return
	var msgs: Array = EffectManager.pop_messages(_local_player_id)
	if msgs.is_empty():
		return
	var texts: Array[String] = []
	for m in msgs:
		var s := str(m)
		if s != "" and not texts.has(s):
			texts.append(s)
	if texts.is_empty():
		return
	_show_tactical_confirm("\n".join(texts), true)


func _show_effect_result(text:String) -> void:
	if effect_result_modal == null or text == "":
		return
	var desc := effect_result_modal.get_node_or_null("Box/VBox/ResultScroll/ResultDesc") as Label
	if desc != null:
		desc.text = text
	# 如果下一条能力询问已在同帧打开，先收起它；引擎等待仍保留，关闭结果后再显示。
	if effect_modal != null:
		effect_modal.visible = false
	_current_waiting_effect = null
	effect_result_modal.visible = true
	move_child(effect_result_modal, get_child_count() - 1)


func _on_effect_result_closed() -> void:
	if effect_result_modal != null:
		effect_result_modal.visible = false
	# 结果看完后立即恢复已在引擎等待队列中的下一条能力询问。
	_check_waiting_effects()

## 展示战术确认浮窗（无标题、无括号废话，直奔核心）
func _show_tactical_confirm(desc_str: String, is_alert: bool = false) -> void:
	if tactical_confirm_modal == null:
		return
	var desc_lbl := tactical_confirm_modal.get_node_or_null("Box/VBox/ConfirmDesc") as Label
	var btn_ok := tactical_confirm_modal.get_node_or_null("Box/VBox/ButtonsRow/BtnConfirmAction") as Button
	var btn_cancel := tactical_confirm_modal.get_node_or_null("Box/VBox/ButtonsRow/BtnCancelAction") as Button
	
	if desc_lbl:
		desc_lbl.text = desc_str
	if btn_ok:
		btn_ok.visible = not is_alert
	if btn_cancel:
		btn_cancel.text = "知道了" if is_alert else "取消"
	
	# 记下这次是纯提示还是待确认操作：纯提示关掉后要把被顶掉的待确认弹窗原样放回来，
	# 不能顺手把玩家正在准备的部署/移动清掉
	_confirm_alert_mode = is_alert
	if !is_alert:
		_pending_confirm_desc = desc_str
	tactical_confirm_modal.visible = true
	# 后显示的弹窗排到子节点末尾：Godot 的点击命中也按子节点倒序，
	# 排最后才能既画在上层、也真正挡住下面的弹窗
	move_child(tactical_confirm_modal, get_child_count() - 1)

func _on_tactical_confirm_execute() -> void:
	if _is_debug_console_blocking_progress():
		return
	if tactical_confirm_modal:
		tactical_confirm_modal.visible = false
	
	var act_type: String = _pending_tactical_action.get("type", "")
	if act_type == "deploy":
		var target_loc = _pending_tactical_action.get("target_loc")
		if target_loc is BaseLocation:
			var before_location = GameDataManager.get_player_data(_local_player_id).get("location")
			Deploy.new().exec(target_loc, _local_player_id)
			var after_location = GameDataManager.get_player_data(_local_player_id).get("location")
			if after_location == before_location:
				_show_tactical_confirm("无法部署至目标席位", true)
			else:
				_apply_deploy_benefit(target_loc, _local_player_id)
				GameProgress.end_current_player_action()
	elif act_type == "move":
		var step: int = _pending_tactical_action.get("step_diff", 0)
		var before_location = GameDataManager.get_player_data(_local_player_id).get("location")
		if step > 0:
			Move.new().exec(BaseNumber.new(step), _local_player_id)
		var after_location = GameDataManager.get_player_data(_local_player_id).get("location")
		if after_location == before_location:
			var target_name: String = str(_pending_tactical_action.get("target_area_name", "目标战区"))
			var messages: Array = EffectManager.pop_messages(_local_player_id)
			if messages.is_empty():
				_show_tactical_confirm("无法移动至【%s】" % target_name, true)
			else:
				_show_tactical_confirm("\n".join(messages.map(func(m): return str(m))), true)
	elif act_type == "regular_play":
		#确认前没有任何副作用；只有这里提交成功后才写 play/regular_play 日志、
		#触发词条与时点。对外观察者以 regular_play 完成事实作为广播边界
		var should_end_action:bool = _regular_play_confirm_ends_action
		_regular_play_confirm_ends_action = false
		if RegularPlay.submit_group(_local_player_id, _regular_play_pending_cards, _regular_play_pending_hidden):
			_regular_play_pending_cards.clear()
			_regular_play_pending_hidden.clear()
			if should_end_action:
				GameProgress.end_current_player_action()
		else:
			_show_tactical_confirm("当前选择已不再合法，请撤销后重新选择", true)
	
	_pending_tactical_action.clear()
	refresh_all_ui()

func _on_tactical_confirm_cancel() -> void:
	if tactical_confirm_modal:
		tactical_confirm_modal.visible = false
	if _confirm_alert_mode:
		# 纯提示只是"知道了"：关掉自己，把之前等待确认的操作放回来
		_confirm_alert_mode = false
		if !_pending_tactical_action.is_empty() and _pending_confirm_desc != "":
			_show_tactical_confirm(_pending_confirm_desc, false)
		return
	if str(_pending_tactical_action.get("type", "")) == "regular_play":
		#取消确认只退回编辑状态，已选牌保留在出牌区，可继续撤销或再次结束阶段
		_regular_play_confirm_ends_action = false
	_pending_tactical_action.clear()
	# 取消后清空待确认文案：下次"知道了"不该把这次已取消的操作再放回来
	_pending_confirm_desc = ""

## -------------------------------------------------------------
## 通用卡牌悬浮放大系统
## 规则：放大能力由**数据类型**决定，不靠扫描节点尺寸猜。
## 每个展示位在按数据填充时就调 _bind_zoom_info(node, obj)，此时"这是什么"是已知事实：
##   BaseCard 及其子类（攻击牌/技能牌/事件牌/局势牌/御主物品）→ 卡，放大 + 右键说明
##   BaseMaster / BaseServant 传 with_desc=false      → 头像，放大但只显示名字
##   BaseBuff                                          → 状态，只给右键说明，无放大图
##   纯 UI 装饰（闭眼图标等）根本不会被绑定，自然不会放大
## metadata 仅用于覆盖细节：
##   zoom_img            指定放大的图，留空则用自身贴图
##   zoom_title/zoom_desc 右键说明文字（兼容事件牌的 event_* 旧键）
##   zoom_disabled=true  显式关闭该节点的放大（如对手的暗置牌）
## -------------------------------------------------------------
func _register_all_hover_zoom() -> void:
	_rebuild_modal_blockers()

## 接上放大系统的输入信号。参数放宽到 Control：buff 条这类容器也要能右键看说明，
## 不限定 TextureRect（它只是扫描阶段的筛选条件，不是接线的前提）
func _bind_hover_zoom(card: Control) -> void:
	if card.has_meta("zoom_bound"):
		return
	card.set_meta("zoom_bound", true)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_entered.connect(_on_zoom_card_entered.bind(card))
	card.gui_input.connect(_on_zoom_card_gui_input.bind(card))

## 读取放大系统元数据：优先新键，兼容事件牌的历史 event_* 键
func _zoom_meta(card: Control, key: String, legacy_key: String) -> String:
	var v: String = str(card.get_meta(key, ""))
	if v == "" and legacy_key != "":
		v = str(card.get_meta(legacy_key, ""))
	return v

func _on_zoom_card_entered(card: Control) -> void:
	# 暗置牌（显示卡背）不参与放大
	if card == null or not is_instance_valid(card) or not card.is_visible_in_tree():
		return
	if bool(card.get_meta("zoom_disabled", false)):
		return
	var mouse_pos := get_viewport().get_mouse_position()
	if _is_mouse_covered_by_modal(mouse_pos, card):
		return
	_hovered_event_card = card
	_show_zoom_for(card)

## 按原图比例等比放大，过宽的卡自动受宽度上限约束
func _show_zoom_for(card: Control) -> void:
	if event_zoom_preview == null:
		return
	var tex: Texture2D = null
	var img_path: String = _zoom_meta(card, "zoom_img", "event_zoom_img")
	if img_path != "" and LoadHelper.texture_exists(img_path):
		tex = LoadHelper.load_texture(img_path)
	elif card is TextureRect:
		tex = (card as TextureRect).texture
	if tex == null:
		return
	var big := event_zoom_preview.get_node_or_null("BigCard") as TextureRect
	if big:
		big.texture = tex
	var src := Vector2(max(1, tex.get_width()), max(1, tex.get_height()))
	var w: float = ZOOM_PREVIEW_HEIGHT * (src.x / src.y)
	var h: float = ZOOM_PREVIEW_HEIGHT
	if w > ZOOM_PREVIEW_MAX_WIDTH:
		w = ZOOM_PREVIEW_MAX_WIDTH
		h = w * (src.y / src.x)
	_zoom_preview_size = Vector2(w, h)
	# 放大图贴着源卡显示：优先右侧，空间不足改左侧；垂直与源卡居中并在视口内收边
	var vp := get_viewport_rect().size
	var src_rect := card.get_global_rect()
	var gap := 14.0
	var px := src_rect.end.x + gap
	if px + w > vp.x - 8.0:
		px = src_rect.position.x - w - gap
	px = clampf(px, 8.0, maxf(8.0, vp.x - w - 8.0))
	var py := src_rect.position.y + src_rect.size.y * 0.5 - h * 0.5
	py = clampf(py, 8.0, maxf(8.0, vp.y - h - 8.0))
	event_zoom_preview.offset_left = px - vp.x * 0.5
	event_zoom_preview.offset_right = event_zoom_preview.offset_left + w
	event_zoom_preview.offset_top = py - vp.y * 0.5
	event_zoom_preview.offset_bottom = event_zoom_preview.offset_top + h
	_set_control_mouse_filter_recursive(event_zoom_preview, Control.MOUSE_FILTER_IGNORE)
	event_zoom_preview.visible = true

## 通用卡牌说明：从任意游戏对象按字段标签表提取 名字/数值/属性/效果，
## 不针对具体卡写死；对象上没有的字段自动跳过
func _build_card_desc(obj) -> String:
	if obj == null:
		return ""
	var lines: Array[String] = []
	# 名字由金色标题展示，描述里不再重复
	for prop in obj.get_property_list():
		var pname: String = str(prop.get("name", ""))
		if not FIELD_LABELS.has(pname):
			continue
		var v = obj.get(pname)
		if v is BaseNumber:
			lines.append("%s：%d" % [FIELD_LABELS[pname], v.number])
		elif v is int or v is float:
			lines.append("%s：%d" % [FIELD_LABELS[pname], int(v)])
	var attrs = obj.get("_attributes")
	if attrs is Array and attrs.size() > 0:
		# 复用 Attributes 的通用显示名映射（含自定义属性注册），不重复造表
		lines.append("属性：" + "、".join(Attributes.get_shown_attributes(attrs)))
	var cat = obj.get("_category")
	if cat != null and str(cat) != "":
		lines.append("类别：" + ATTACK_CATEGORY_LABELS.get(str(cat), str(cat)))
	#卡面印的打出条件与提示行：文案来自卡自己的数据，这里只负责逐条列出。
	#注意 Object.get 只接受属性名一个参数，不能带默认值
	var notes = obj.get("_shown_notes")
	if notes is Array:
		for note in notes:
			if str(note) != "":
				lines.append(str(note))
	var play_reqs = obj.get("_play_requirements")
	if play_reqs is Array:
		for req in play_reqs:
			if req is Dictionary and str(req.get("shown_note", "")) != "":
				lines.append(str(req["shown_note"]))
	var effs = obj.get("_effects")
	if effs is Array and effs.size() > 0:
		var es: Array[String] = []
		for e in effs:
			# 选项类效果(单选/多选，如令咒三选一)：本体没有独立说明，把各选项文案列出来
			if e is BaseEffect and e.has_options():
				for opt in e._options:
					var opt_name: String = str(opt.get("shown_option_name", ""))
					if opt_name != "":
						es.append(opt_name)
				continue
			var en: String = _object_shown_name(e)
			if en != "":
				es.append(en)
		if es.size() > 0:
			# 效果不带前缀标签，多条换行缩进罗列
			lines.append("\n　　".join(es))
	return "\n".join(lines)

## 通用显示名：优先对象自己的显示名接口，回退内部名
func _object_shown_name(obj) -> String:
	if obj == null:
		return ""
	if obj.has_method("get_shown_name"):
		var s: String = str(obj.get_shown_name())
		if s != "":
			return s
	var n = obj.get("_name")
	return str(n) if n != null else ""

## 通用卡位填充：按对象上的卡图字段填 texture 并绑定说明，无数据的卡位隐藏。
## img_prop 可传多个候选字段名，按顺序取第一个存在的图（御主用_master_card_img、卡牌用_card_img…）
func _fill_card_slot(node: TextureRect, obj, img_prop: String = "_card_img") -> void:
	if node == null:
		return
	if obj == null:
		node.visible = false
		return
	node.visible = true
	var img: String = ""
	for prop in [img_prop, "_card_img"]:
		var v = obj.get(prop)
		if v != null and str(v) != "" and LoadHelper.texture_exists(str(v)):
			img = str(v)
			break
	if img != "":
		node.texture = LoadHelper.load_texture(img)
		node.set_meta("zoom_img", img)
	# 把实际用的图片字段传下去：御主同时有头像与御主卡，分类要按这张图取
	_bind_zoom_info(node, obj, img_prop)

## 给节点绑定放大/说明信息并接好输入信号。
## 展示形态由**数据自己声明的分类**决定（JSON 里紧跟图片路径的 zoom_kind）：
##   card   → 可放大 + 右键完整卡牌说明
##   avatar → 可放大，右键只显示名字
##   token  → 可放大该小图标，右键只显示名字与层数
##   空串   → 未声明，不给放大也不接说明（宁可不放大也不猜错分类）
## img_field 传这个节点展示的是哪张图（御主同时有头像与卡图，靠它区分档位）。
## 必须在这里接线：卡位与 buff 条都是每次刷新动态创建的，没有一次性扫描能覆盖它们。
func _bind_zoom_info(node: Control, obj, img_field: String = "") -> void:
	if node == null or obj == null:
		return
	var kind: String = ""
	if obj.has_method("get_zoom_kind"):
		kind = obj.get_zoom_kind(img_field)
	if kind == "":
		# 数据没声明分类：清掉可能残留的放大绑定信息，不接线
		node.set_meta("zoom_disabled", true)
		node.remove_meta("zoom_title")
		node.remove_meta("zoom_desc")
		node.remove_meta("zoom_img")
		return
	node.set_meta("zoom_disabled", false)
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	var shown: String = _object_shown_name(obj)
	if shown != "":
		node.set_meta("zoom_title", shown)
	else:
		node.remove_meta("zoom_title")
	# 只有卡才给完整卡牌说明；头像只有名字；token 给名字与层数
	if kind == LoadHelper.ZOOM_KIND_CARD:
		node.set_meta("zoom_desc", _build_card_desc(obj))
	elif kind == LoadHelper.ZOOM_KIND_TOKEN:
		node.set_meta("zoom_desc", _build_token_desc(obj))
	else:
		node.set_meta("zoom_desc", "")
	# 旧场景手写的 event_* 会盖住真实对象，绑定时清掉
	node.remove_meta("event_title")
	node.remove_meta("event_desc")
	node.remove_meta("event_zoom_img")
	var img = obj.get(img_field) if img_field != "" else obj.get("_card_img")
	if img == null or str(img) == "":
		img = obj.get("_card_img")
	if img != null and str(img) != "" and LoadHelper.texture_exists(str(img)):
		node.set_meta("zoom_img", str(img))
	_bind_hover_zoom(node)

## token(状态图标)的说明：名字与层数，不走卡牌式字段罗列。
## 效果文案照旧列出，玩家要靠它知道这个状态在做什么
func _build_token_desc(obj) -> String:
	var lines: Array[String] = []
	var lvl = obj.get("_buff_level")
	var lvl_num: int = (lvl.number as int) if lvl is BaseNumber else 1
	if lvl_num > 1:
		lines.append("层数：%d" % lvl_num)
	var effs = obj.get("_effects")
	var es: Array[String] = []
	if effs is Array:
		for e in effs:
			if e is BaseEffect and e.has_options():
				for opt in e._options:
					var option_name: String = str(opt.get("shown_option_name", ""))
					if option_name != "":
						es.append(option_name)
			else:
				var en: String = _object_shown_name(e)
				if en != "":
					es.append(en)
	var related: Array = obj.get("_related_effect_names")
	var owner = obj.from.get_ref() if obj.from is WeakRef else obj.from
	if related is Array and owner != null:
		var owner_effects = owner.get("_effects")
		if owner_effects is Array:
			for effect_name in related:
				for eff in owner_effects:
					if eff is BaseEffect and eff._name == str(effect_name):
						var shown: String = _object_shown_name(eff)
						if shown != "" and not es.has(shown):
							es.append(shown)
						break
	if not es.is_empty():
		lines.append("\n　　".join(es))
	return "\n".join(lines)

## 右键展示某个放大目标的图与说明。两处右键入口（普通卡牌、顶栏对手头像）共用
func _show_zoom_and_desc_for(card: Control) -> bool:
	if card == null or bool(card.get_meta("zoom_disabled", false)):
		return false
	_hovered_event_card = card
	_desc_panel_source = card
	_show_zoom_for(card)
	var title: String = _zoom_meta(card, "zoom_title", "event_title")
	var desc: String = _zoom_meta(card, "zoom_desc", "event_desc")
	if title != "" or desc != "":
		_show_event_desc(title, desc, card)
	return true

func _on_zoom_card_gui_input(ev: InputEvent, card: Control) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
		if _show_zoom_and_desc_for(card):
			get_viewport().set_input_as_handled()

## 收集所有会遮挡内容的上层容器（判据通用：z_index 达标且自身会接收鼠标）
func _rebuild_modal_blockers() -> void:
	_modal_blockers.clear()
	_collect_modal_blockers(self)

func _collect_modal_blockers(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			var c := child as Control
			if c.z_index >= MODAL_Z_THRESHOLD and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				_modal_blockers.append(c)
		_collect_modal_blockers(child)

## 鼠标是否落在遮挡层内。source 自身及其祖先链不算遮挡，
## 否则放在上层容器（手牌托盘、抽屉）里的卡会永远无法触发放大
func _is_mouse_covered_by_modal(mouse_pos: Vector2, source: Control) -> bool:
	for c in _modal_blockers:
		if not is_instance_valid(c) or not c.visible:
			continue
		if source != null and (c == source or c.is_ancestor_of(source)):
			continue
		if c.get_global_rect().has_point(mouse_pos):
			return true
	return false

## -------------------------------------------------------------
## 弹窗拖动：按住弹窗任意非交互区域即可拖动，便于查看被遮挡的战场
## -------------------------------------------------------------
## 把 target 的场景树位置调整到与它的 z_index 一致：找到第一个 z_index 严格更大的
## 兄弟节点，插到它前面（同层级维持原有顺序不变）。这样"绘制层叠"（z_index 大盖住小）
## 与"输入命中"（子节点顺序倒序优先响应）两套判定规则就统一了，任何面板只要按 z_index
## 声明清楚，都能既显示在上层、也真正挡住下层的点击——不必给每个新面板单独调顺序。
func _reorder_child_by_z(target: Control) -> void:
	var target_z: int = target.z_index
	var target_idx: int = target.get_index()
	for i in range(get_child_count()):
		var sib := get_child(i)
		if sib == target:
			continue
		if sib is Control and (sib as Control).z_index > target_z:
			# move_child 的第2个参数是"移动完成后的下标"，不是"插到谁前面"。
			# 目标原本排在该兄弟之前时，摘除自身会让兄弟前移一位，所以下标要减 1，
			# 否则会落到兄弟后面，绘制层叠与点击命中两套顺序又会相反
			move_child(target, i - 1 if target_idx < i else i)
			return
	move_child(target, get_child_count() - 1)

func _enable_modal_drag(panel: Control) -> void:
	if panel == null or panel.has_meta("drag_enabled"):
		return
	panel.set_meta("drag_enabled", true)
	_block_panel_clicks(panel)
	_reorder_child_by_z(panel)
	if not panel.gui_input.is_connected(_on_modal_drag_input):
		panel.gui_input.connect(_on_modal_drag_input.bind(panel))

## 让一个浮层面板真正挡住点击：只 STOP 不够——纯容器没有连接任何输入处理器时，
## Godot 的 GUI 分发仍可能把事件继续派给下层被遮挡的兄弟节点（抽屉盖住战区、点击却
## 穿透部署确认弹窗的根因）。挂一个空 gui_input 吞掉事件即可让"所有面板都能挡住操作"。
## 不触碰子节点：抽屉这类面板内部的卡牌仍需接收右键放大，不能像拖动弹窗那样整体被动化。
func _block_panel_clicks(panel: Control) -> void:
	if panel == null:
		return
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if not panel.gui_input.is_connected(_on_panel_swallow_input):
		panel.gui_input.connect(_on_panel_swallow_input)

func _on_panel_swallow_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		get_viewport().set_input_as_handled()

func _make_children_passive(node: Node) -> void:
	for child in node.get_children():
		if _is_interactive_control(child):
			continue
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_make_children_passive(child)

## 面板里"自己就能交互"的子控件：按钮、滚动区、输入框。
## 拖动穿透（_make_children_passive）必须放行这些类型——它们自己处理输入，
## 设成 IGNORE 会让按钮点不动、滚动条拖不了
func _is_interactive_control(node: Node) -> bool:
	return node is Button or node is ScrollContainer or node is LineEdit

func _on_modal_drag_input(ev: InputEvent, panel: Control) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_dragging_modal = panel
			panel.z_index = max(panel.z_index, MODAL_Z_THRESHOLD + 40)
			# 提升 z_index 只改绘制层叠；命中顺序按场景树子节点倒序，必须同步重排，
			# 否则会出现"画在上面、点击却给下面的兄弟"
			_reorder_child_by_z(panel)
		elif _dragging_modal == panel:
			_dragging_modal = null
		get_viewport().set_input_as_handled()
	elif ev is InputEventMouseMotion and _dragging_modal == panel:
		var d: Vector2 = ev.relative
		panel.offset_left += d.x
		panel.offset_right += d.x
		panel.offset_top += d.y
		panel.offset_bottom += d.y
		_clamp_modal_on_screen(panel)

## 拖动边界约束：至少保留一部分面板在屏幕内，避免拖出视口找不回来
func _clamp_modal_on_screen(panel: Control) -> void:
	var vp := get_viewport_rect().size
	var r := panel.get_global_rect()
	var margin := 48.0
	var dx := 0.0
	var dy := 0.0
	if r.position.x < -r.size.x + margin:
		dx = -r.size.x + margin - r.position.x
	elif r.position.x > vp.x - margin:
		dx = vp.x - margin - r.position.x
	if r.position.y < 0.0:
		dy = -r.position.y
	elif r.position.y > vp.y - margin:
		dy = vp.y - margin - r.position.y
	if dx != 0.0 or dy != 0.0:
		panel.offset_left += dx
		panel.offset_right += dx
		panel.offset_top += dy
		panel.offset_bottom += dy

## -------------------------------------------------------------
## 可点击动态标识
## 通则：可点击处自动获得"呼吸光晕"；大面积点击目标（战区）额外叠加环绕光尘粒子。
## 颜色与是否生效由 metadata 驱动，可在任意节点上覆盖：
##   clickable=true        显式标记为可点击
##   clickable_color=Color 指定标识颜色
##   clickable_particles=true 额外叠加环绕粒子
## -------------------------------------------------------------

## 卡位的"卡图那一层"。金框只圈这一层：卡位是"卡图 + 牌名"的容器时，
## 框满整个卡位会把牌名一起圈进去（看起来像包着字的框）。
## 卡位本身就是卡图 → 返回它自己；容器里卡图数量不为 1 时返回 null，
## 表示"这一层不明确"，由调用方沿用原行为（框整个卡位），不靠猜。
func _card_art_of(slot: Control) -> Control:
	if slot == null:
		return null
	if slot is TextureRect:
		return slot
	var arts: Array = _card_texture_nodes(slot)
	return arts[0] as Control if arts.size() == 1 else null

## -------------------------------------------------------------
## 给控件叠加一层呼吸发光边框。金框画在哪一层由调用方声明（frame_on）：
## 不传就画在 ctrl 自己身上（顶栏行动框、地区框、提示按钮等都是这个用法）；
## 卡位则传卡图节点，让金框只圈卡图。宿主记在 ctrl 的 clickable_host 上，
## 之后无论是"收回"还是"重新上色"，都按这条记录找同一个边框。
## 用独立叠加层而非修改控件材质：材质方案对 StyleBox 绘制的按钮会采到白色内置纹理导致控件变白。
func _apply_clickable_indicator(ctrl: Control, color: Color, frame_on: Control = null) -> void:
	if ctrl == null:
		return
	var host: Control = frame_on if frame_on != null else ctrl
	# 已记录过宿主就以记录为准：节流扫描是按卡位（ctrl）调进来的，若改画到 ctrl 上，
	# 卡位里会多出一个框，和卡图层那个同时呼吸
	if ctrl.has_meta("clickable_host"):
		var recorded = ctrl.get_meta("clickable_host")
		if recorded is Control and is_instance_valid(recorded):
			host = recorded
	if host.get_node_or_null("ClickableGlow") != null:
		ctrl.set_meta("clickable_host", host)
		return
	var glow := Panel.new()
	glow.name = "ClickableGlow"
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.z_index = 2
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.draw_center = false
	sb.set_border_width_all(4)
	sb.border_color = color
	sb.set_corner_radius_all(7)
	# 不加外扩阴影：光晕外扩会让面板看起来"变大"，呼吸只用边框亮度体现
	sb.shadow_color = Color(0, 0, 0, 0)
	sb.shadow_size = 0
	glow.add_theme_stylebox_override("panel", sb)
	host.add_child(glow)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ctrl.set_meta("clickable_host", host)
	if not _clickable_nodes.has(ctrl):
		_clickable_nodes.append(ctrl)

## 找控件的呼吸边框。宿主可能是控件本身，也可能是卡位里的卡图层（见 clickable_host）
func _clickable_glow_of(ctrl: Control) -> Control:
	if ctrl == null:
		return null
	if ctrl.has_meta("clickable_host"):
		var host = ctrl.get_meta("clickable_host")
		if host is Control and is_instance_valid(host):
			return (host as Control).get_node_or_null("ClickableGlow") as Control
	return ctrl.get_node_or_null("ClickableGlow") as Control

## 可点击时显示呼吸边框，不可点击时收起，避免误导
func _set_clickable_active(ctrl: Control, active: bool) -> void:
	if ctrl == null:
		return
	var glow := _clickable_glow_of(ctrl)
	if glow == null:
		return
	if not active:
		glow.visible = false
		if glow.has_meta("glow_tween"):
			var old_tw = glow.get_meta("glow_tween")
			if old_tw is Tween and old_tw.is_valid():
				old_tw.kill()
			glow.remove_meta("glow_tween")
		return
	glow.visible = true
	if glow.has_meta("glow_tween"):
		return
	var tw := glow.create_tween().set_loops()
	tw.tween_property(glow, "modulate:a", 0.12, 1.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(glow, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_SINE)
	glow.set_meta("glow_tween", tw)

## 扫描并套用可点击标识：所有按钮自动生效，其余节点靠 clickable 标记
func _apply_clickable_indicators() -> void:
	_scan_clickable_targets(self)
	_refresh_clickable_strength()

func _scan_clickable_targets(node: Node) -> void:
	for child in node.get_children():
		# 隐藏的子树不扫：弹窗（战报、只读浏览、选牌）平时不可见，
		# 里面的按钮照扫会在屏幕中央留下一个没有对应可点目标的金框
		if child is Control and not (child as Control).visible:
			continue
		var want := false
		if child is Button:
			# 按钮默认参与呼吸提示（手牌上的"明置/暗置"按钮就要这个提示），
			# 但纯功能按钮（如战果榜开关）只需要自身样式，由它自己声明 no_clickable_hint 退出
			want = !bool((child as Control).get_meta("no_clickable_hint", false))
		elif child is Control and bool((child as Control).get_meta("clickable", false)):
			want = true
		if want and child is Control:
			var c := child as Control
			var col: Color = c.get_meta("clickable_color", Color(1.0, 0.85, 0.3, 1.0))
			# 幂等由 _apply_clickable_indicator 内部按 "ClickableGlow" 子节点判断，
			# 不再读一个没人写入的 metadata 键（配置键与内部标记键混用会让守卫恒为真/恒为假）
			_apply_clickable_indicator(c, col)
		_scan_clickable_targets(child)

## 刷新可点击强度：只有轮到自己、且该目标此刻真的能操作时才满亮。
## 战区判据与点击入口共用 _can_act_on_area，"看起来能点"与"点得动"永远是同一条件
func _refresh_clickable_strength() -> void:
	# 剔除已释放的节点：手牌卡位每次刷新都会重建，只 append 不清理会让列表
	# 与 0.5 秒一次的遍历越跑越大。
	# 用类型化数组承接：_clickable_nodes 是 Array[Control]，赋未类型化的 Array 会运行时报错
	var alive: Array[Control] = []
	for c in _clickable_nodes:
		if is_instance_valid(c):
			alive.append(c)
	_clickable_nodes = alive
	var my_turn: bool = GameProgress.current_player_id == _local_player_id
	for c in _clickable_nodes:
		if !(c is Control):
			continue
		var ctrl := c as Control
		var area_idx: int = _area_index_of_node(ctrl)
		if area_idx != -1:
			_set_clickable_active(ctrl, my_turn and _can_act_on_area(area_idx))
			_set_area_descendant_clickable_active(ctrl, my_turn and _can_act_on_area(area_idx))
		elif ctrl.has_meta("playable_hint"):
			# 自己带着"此刻能不能用"的状态（手牌、令咒卡）：状态为假时不落到下面的兜底分支，
			# 否则会变成"轮到我 = 亮着"，看起来能点却点不动
			_set_clickable_active(ctrl, bool(ctrl.get_meta("playable_hint", false)))
		elif ctrl.get_meta("actor_avatar", false):
			# 当前行动者头像：跟随行动者变化呼吸
			_set_clickable_active(ctrl, bool(ctrl.get_meta("is_acting", false)))
		elif ctrl is Button:
			_set_clickable_active(ctrl, true)
		else:
			_set_clickable_active(ctrl, my_turn)


## 战区内部可能还有 clickable 子节点；父战区不可操作时，子节点也必须关闭光晕。
## 否则父节点判定已禁止，内部静态标记仍会留下金框。
func _set_area_descendant_clickable_active(area_node: Control, active: bool) -> void:
	for child in area_node.find_children("*", "Control", true, false):
		if child == area_node or child.get_meta("playable_hint", false):
			continue
		if child.get_node_or_null("ClickableGlow") != null:
			_set_clickable_active(child, active)


## 战区节点对应的 MapData.areas 下标：按 MapData 里的实例查，不写死 0/1/2/3，
## 区域表顺序变化时也不会出现暗中的错位
func _area_index_of_node(node: Control) -> int:
	if node == null:
		return -1
	if node == area_workshop:
		return MapData.areas.find(MapData.magic_workshop)
	if node == area_miyama:
		return MapData.areas.find(MapData.miyama)
	if node == area_shinto:
		return MapData.areas.find(MapData.shinto)
	if node == area_scout:
		return MapData.areas.find(MapData.scout)
	return -1

## 本地玩家当前所在战区（没有位置时返回 null）
func _local_current_area(pl_data: Dictionary) -> BaseMapArea:
	var loc = pl_data.get("location") as BaseLocation
	if loc == null:
		return null
	return loc.get_from() as BaseMapArea

## 从当前战区分几步到目标战区的移动费用（含魔术工房折扣）。判据与确认文案共用，
## 避免两处各算一套导致"界面显示能走、实际走不动"
func _estimate_move_cost(pl_data: Dictionary, step_diff: int) -> int:
	var area := _local_current_area(pl_data)
	if area == null:
		return 0
	var total_cost: int = 0
	for n in range(step_diff):
		if area._linked_map_area == null:
			break
		total_cost += (area._move_cost as BaseNumber).number
		area = area._linked_map_area
	if _local_current_area(pl_data) == MapData.magic_workshop:
		var discount: int = (pl_data.get("move_cost_discount_from_workshop", BaseNumber.new(0)) as BaseNumber).number
		total_cost = max(0, total_cost - discount)
	return total_cost

## 魔力够不够付这笔移动费用（魔力免疫视为够）
func _is_magic_enough_for_move(pl_data: Dictionary, cost: int) -> bool:
	if bool(pl_data.get("is_magic_immune", false)):
		return true
	return (pl_data.get("magic", BaseNumber.new(0)) as BaseNumber).number >= cost

## 该战区此刻不可操作的原因（空串表示可操作）。呼吸光晕与点击入口共用同一份判据，
## 保证"看起来能点"与"点得动"永不漂移；不能操作时还能给玩家一个具体说法，
## 不再出现"战区亮着、点下去什么都不发生"
func _area_action_block_reason(target_area_idx: int) -> String:
	if target_area_idx < 0 or target_area_idx >= MapData.areas.size():
		return "目标战区不存在"
	# 选项级位置选择（令咒"从新都或深山町移动至任意位置"等）：
	# 呼吸光晕与点击入口(_on_battlefield_clicked)共用这一条判据。
	# 只要当前正等玩家选位置、且该战区有合法落点，战区就属于"可操作"，必须亮金框；
	# 否则会陷入常规移动的单向/交战判定，导致"能点却不亮框"
	var pending_loc: Dictionary = EffectManager.get_pending_location_selection()
	if not pending_loc.is_empty():
		var spec: Dictionary = pending_loc.get("spec", {})
		var eff: BaseEffect = pending_loc.get("effect")
		var trigger_id: int = eff._trigger_player_id if eff != null else _local_player_id
		if trigger_id != _local_player_id and trigger_id >= 0:
			return "当前是其他玩家在选择位置"
		var target_area: BaseMapArea = MapData.areas[target_area_idx]
		# 起点战区校验（如令咒只允许从新都/深山町出发）
		var allowed: Array = spec.get("allowed_origin_areas", []) as Array
		if not allowed.is_empty():
			var origin: BaseLocation = GetLocation.new().exec(trigger_id)
			var origin_area: BaseMapArea = origin.get_from() as BaseMapArea if origin != null else null
			var origin_name: String = origin_area._area_name if origin_area != null else ""
			if not allowed.has(origin_name):
				return "当前战区【%s】不是合法的出发地" % origin_name
		if _first_effect_location_target(target_area, spec) == null:
			return "【%s】没有可用的席位" % target_area._area_name
		return ""
	if GameProgress.current_player_id != _local_player_id:
		return "还没轮到你行动"
	var phase_name := str(GameProgress.get_current_phase().get("name", ""))
	if phase_name == "outpost":
		var target_area: BaseMapArea = MapData.areas[target_area_idx]
		if _open_deploy_locations(target_area).is_empty():
			return "【%s】没有可用的部署席位" % target_area._area_name
		return ""
	if phase_name != "action":
		return "当前是%s，不能部署或移动" % _phase_shown_name(phase_name)
	var pl_data: Dictionary = GameDataManager.get_player_data(_local_player_id)
	#交战判定与引擎共用同一个查询：与对手同处一处会发生战斗的战场时不能常规移动
	if IsEngaged.new().exec(_local_player_id):
		return "处于交战状态，无法移动"
	var curr_area := _local_current_area(pl_data)
	if curr_area == null:
		return "你还没有部署到任何战区"
	var current_idx: int = MapData.areas.find(curr_area)
	if current_idx == -1:
		return "你当前的位置不在任何战区上"
	var step_diff: int = target_area_idx - current_idx
	if step_diff <= 0:
		return "移动只能沿单方向前进"
	#落点判据与真正的移动(MoveLocation)共用同一份规则：区域不可移入、或常规落点已满，
	#这里就判为不可操作——既不亮金色提示，点击时也能直接给出原因
	var target_area: BaseMapArea = MapData.areas[target_area_idx]
	if target_area == MapData.scout and GetMoveTargetLocation.new().exec(target_area) == null:
		return "侦查先锋位已被占用"
	if target_area._can_move_to == false:
		return "无法移动至【%s】" % target_area._area_name
	if GetMoveTargetLocation.new().exec(target_area) == null:
		return "【%s】的常规落点已满" % target_area._area_name
	if !_is_magic_enough_for_move(pl_data, _estimate_move_cost(pl_data, step_diff)):
		return "魔力不足，无法移动至【%s】" % target_area._area_name
	return ""

## 该战区此刻对本地玩家是否可操作
func _can_act_on_area(target_area_idx: int) -> bool:
	return _area_action_block_reason(target_area_idx) == ""

## 阶段名的中文口径：界面各处统一由它生成，避免同一阶段在不同位置出现不同写法
func _phase_shown_name(phase_key: String) -> String:
	match phase_key:
		"prepare": return "准备阶段"
		"outpost": return "前哨阶段"
		"action": return "行动阶段"
		"battle": return "战斗阶段"
	return phase_key

## 递归设置鼠标过滤：放大预览层需整体忽略鼠标，避免抢走底层卡牌的悬浮判定
func _set_control_mouse_filter_recursive(node: Node, filter: Control.MouseFilter) -> void:
	if node is Control:
		node.mouse_filter = filter
	for child in node.get_children():
		_set_control_mouse_filter_recursive(child, filter)

## 收起放大图；also_desc=true 时连说明面板一起收起。
## 放大图由悬停驱动、说明面板由右键驱动，两者生命周期不同：
## 鼠标移开只收放大图（also_desc=false），点击关闭才连说明一起收
func _hide_event_zoom(also_desc: bool = true) -> void:
	if event_zoom_preview:
		event_zoom_preview.visible = false
	if also_desc and event_desc_panel:
		event_desc_panel.visible = false
		_desc_panel_source = null

## 悬浮检测：遮挡层优先，其次按几何坐标判定，避免边缘微动闪烁
func _update_event_card_hover_check() -> void:
	if _hovered_event_card == null or not is_inside_tree():
		return
	if not is_instance_valid(_hovered_event_card) or not _hovered_event_card.is_visible_in_tree():
		_hovered_event_card = null
		_hide_event_zoom(false)
		return
	var mouse_pos := get_viewport().get_mouse_position()
	if _is_mouse_covered_by_modal(mouse_pos, _hovered_event_card):
		_hovered_event_card = null
		_hide_event_zoom(false)
		return
	var card_rect: Rect2 = _hovered_event_card.get_global_rect().grow(6.0)
	if card_rect.has_point(mouse_pos):
		return
	# 放大图贴在源卡旁边，鼠标移到放大图上时应保持显示，便于贴近查看
	if event_zoom_preview != null and event_zoom_preview.visible:
		if event_zoom_preview.get_global_rect().has_point(mouse_pos):
			return
	_hovered_event_card = null
	# 鼠标移开只收起"悬停触发的放大图"，不关说明面板：
	# 说明面板是右键开的，按约定只能由左键/右键点击关闭。两者触发方式不同，
	# 生命周期也必须分开，否则右键看 buff 说明时一移开鼠标就消失
	_hide_event_zoom(false)

func _show_event_desc(title_text: String, desc_text: String, source: Control = null) -> void:
	if event_desc_panel == null:
		return
	var title_lbl := event_desc_panel.get_node_or_null("VBox/Title") as Label
	var desc_lbl := event_desc_panel.get_node_or_null("VBox/Desc") as Label
	if title_lbl:
		title_lbl.text = title_text
	if desc_lbl:
		desc_lbl.text = desc_text
		desc_lbl.visible = desc_text != ""
	# 只有名字（头像）时收紧面板高度，避免留出大块空白
	var panel_h: float = 240.0 if desc_text != "" else 92.0
	event_desc_panel.custom_minimum_size = Vector2(420.0, panel_h)
	# 说明贴在放大图旁；没有放大图时贴源卡旁
	var vp := get_viewport_rect().size
	var anchor := Rect2()
	if event_zoom_preview != null and event_zoom_preview.visible:
		anchor = event_zoom_preview.get_global_rect()
	elif source != null:
		anchor = source.get_global_rect()
	var ps := Vector2(420.0, panel_h)
	# 候选位：锚右侧 → 锚左侧 → 锚下方 → 锚上方。
	# 面板绝不能压住源卡，否则悬浮检测会判定"鼠标被遮挡"从而立刻收起面板。
	var keep_clear: Rect2 = source.get_global_rect().grow(6.0) if source != null else Rect2()
	var cands: Array[Vector2] = [
		Vector2(anchor.end.x + 14.0, anchor.position.y),
		Vector2(anchor.position.x - ps.x - 14.0, anchor.position.y),
		Vector2(anchor.position.x, anchor.end.y + 14.0),
		Vector2(anchor.position.x, anchor.position.y - ps.y - 14.0)
	]
	var pos := Vector2.ZERO
	var picked := false
	for c in cands:
		var p := Vector2(
			clampf(c.x, 8.0, maxf(8.0, vp.x - ps.x - 8.0)),
			clampf(c.y, 8.0, maxf(8.0, vp.y - ps.y - 8.0))
		)
		# 收边后仍不压住源卡才算可用
		if keep_clear.size == Vector2.ZERO or not Rect2(p, ps).intersects(keep_clear):
			pos = p
			picked = true
			break
	if not picked:
		pos = Vector2(
			clampf(cands[0].x, 8.0, maxf(8.0, vp.x - ps.x - 8.0)),
			clampf(cands[0].y, 8.0, maxf(8.0, vp.y - ps.y - 8.0))
		)
	event_desc_panel.global_position = pos
	event_desc_panel.visible = true

func _on_close_event_desc() -> void:
	if event_desc_panel:
		event_desc_panel.visible = false

## 说明面板开着时的点击：收起面板。
## _input 跑在 GUI 分发之前且此处会吞掉事件（防止穿透到下层战区），所以点向另一张卡的那一击
## 到不了它的 gui_input。此时直接用放大系统已维护的悬浮目标接管，实现"面板开着也能连续右键别的卡"。
## 用独立的 _desc_panel_source（而不是会随悬浮实时变化的 _hovered_event_card）判断"这一击是否
## 就是面板当前显示的那张卡"——否则右键同一张卡想关闭时，命中的正是它自己，会被误判成切换到新目标
## 从而立刻重开，表现为"右键卡关不掉说明"。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and !event.echo \
			and event.physical_keycode == KEY_QUOTELEFT:
		# 物理波浪号键是控制台的随时入口：默认不预加载控制台，第一次按键时
		# 才按需实例化；之后同一按键只切换面板，不反复销毁会话与命令历史。
		if !is_debug_console_enabled():
			set_debug_console_enabled(true)
		if is_debug_console_enabled():
			_debug_console.toggle_panel()
		get_viewport().set_input_as_handled()
		return
	if event_desc_panel != null and event_desc_panel.visible \
			and event is InputEventMouseButton and event.pressed \
			and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		var hovered: Control = _hovered_event_card
		var is_same_as_current: bool = hovered != null and hovered == _desc_panel_source
		event_desc_panel.visible = false
		_desc_panel_source = null
		# 右键落在另一个放大目标（非当前正显示的那张）上：直接切换到它
		if event.button_index == MOUSE_BUTTON_RIGHT and not is_same_as_current and hovered != null \
				and is_instance_valid(hovered) and hovered.visible \
				and hovered.get_global_rect().has_point(event.global_position):
			_show_zoom_and_desc_for(hovered)
		get_viewport().set_input_as_handled()
		return
	# 通用只读卡牌浏览器（弃牌堆、游戏外等）：内部点击保留给滚动/关闭按钮，
	# 外部左键只负责收起并吞掉本次事件，不能顺便点穿到战区。
	if _card_browser_panel != null and is_instance_valid(_card_browser_panel) and _card_browser_panel.visible \
			and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var browser_pos: Vector2 = (event as InputEventMouseButton).global_position
		if not _card_browser_panel.get_global_rect().has_point(browser_pos):
			_card_browser_panel.visible = false
			get_viewport().set_input_as_handled()
			return
	# 抽屉展开时左键点击抽屉之外的区域：收起抽屉。顶栏对手头像格自己的开/关/切换逻辑
	# 走 _on_opponent_gui_input（在 GUI 分发阶段，晚于这里），这里只处理"点在别处"的收起，
	# 点在头像格上时让事件正常往下走，避免和头像自己的开/关/切换互相打架
	if opponent_drawer != null and opponent_drawer.visible \
			and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = (event as InputEventMouseButton).global_position
		# AI 出牌提示按钮的职责就是打开对应抽屉，不能被"点在抽屉外"的收起逻辑抢先关掉，
		# 否则会出现"这一击先关抽屉、按钮再开抽屉"的抖动
		var on_ai_prompt: bool = _ai_play_prompt_node != null and is_instance_valid(_ai_play_prompt_node) \
				and _ai_play_prompt_node.visible and _ai_play_prompt_node.get_global_rect().has_point(pos)
		if not on_ai_prompt and not opponent_drawer.get_global_rect().has_point(pos) and not _is_point_over_opponent_cards(pos):
			opponent_drawer.visible = false
			_selected_opponent = null
			_selected_opponent_id = -1


## 调试控制台是独立 CanvasLayer：启用时才实例化，禁用时完整卸载。
## CanvasLayer 的 layer 自己负责绘制层级，不调用只接受宿主 Control 子节点的 _reorder_child_by_z。
func set_debug_console_enabled(enabled:bool) -> void:
	if enabled:
		if is_debug_console_enabled():
			return
		# 调试场景按需加载且不进入全局资源缓存；默认关闭时不增加正式对局的资源占用，
		# 反复启停后也不会由宿主脚本常量永久持有整份控制台场景。
		var scene := ResourceLoader.load(
			"res://assets/scenes/debug/debug_console.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE
		) as PackedScene
		if scene == null:
			return
		_debug_console = scene.instantiate() as DebugConsoleUI
		if _debug_console == null:
			return
		add_child(_debug_console)
		_debug_console.initialize(self)
		return
	if !is_debug_console_enabled():
		_debug_console = null
		return
	_debug_console.safe_shutdown()
	_debug_console.queue_free()
	_debug_console = null


func is_debug_console_enabled() -> bool:
	return _debug_console != null and is_instance_valid(_debug_console)


func _is_debug_console_blocking_progress() -> bool:
	return is_debug_console_enabled() and _debug_console.session != null and _debug_console.session.is_paused()


## 控制台关闭或卸载后，不允许把编辑前保存的预览对象再次提交。
## 这里只清 UI 预览，不碰 EffectManager 的真实等待；效果等待必须由 wait.* 命令显式回答。
func discard_debug_console_pending_previews() -> void:
	_regular_play_pending_cards.clear()
	_regular_play_pending_hidden.clear()
	_regular_play_confirm_ends_action = false
	if str(_pending_tactical_action.get("type", "")) == "regular_play":
		_pending_tactical_action.clear()
		_pending_confirm_desc = ""
		_confirm_alert_mode = false
		if tactical_confirm_modal:
			tactical_confirm_modal.visible = false
	refresh_all_ui()

## -------------------------------------------------------------
## 4. 分支效果决策弹窗 (Waiting Effect Dialog)
## -------------------------------------------------------------
func _connect_effect_modal_buttons() -> void:
	if effect_modal == null:
		return
	var btn_confirm := effect_modal.get_node_or_null("Box/VBox/ButtonsRow/BtnConfirm") as Button
	var btn_cancel := effect_modal.get_node_or_null("Box/VBox/ButtonsRow/BtnCancel") as Button
	if btn_confirm and not btn_confirm.pressed.is_connected(_on_effect_modal_confirm):
		btn_confirm.pressed.connect(_on_effect_modal_confirm)
	if btn_cancel and not btn_cancel.pressed.is_connected(_on_effect_modal_cancel):
		btn_cancel.pressed.connect(_on_effect_modal_cancel)

## -------------------------------------------------------------
## 4. 主动效果时点抉择弹窗 (Active Effect Choice At Any TimePoint)
## 规则：主动效果可能在游戏任何时点触发（出牌前/后、战斗时、移动时、阶段转换时等）。
## 判定规则：
## 1. 若为玩家自己的主动效果：在任何时点均弹窗供玩家选择【确认发动】或【跳过/放弃】；
## 2. 若为对手AI的主动效果：AI自动快速决断并提交，绝不弹窗打扰玩家，保证时点管线顺畅推进。
## -------------------------------------------------------------
func _check_waiting_effects() -> void:
	# 已有普通确认/提示先由玩家处理；等待效果保留在引擎队列，不叠放询问框。
	if tactical_confirm_modal != null and tactical_confirm_modal.visible:
		return
	# 发动结果必须先让玩家看完；下一条能力可以留在引擎等待队列，但询问框暂不显示，
	# 关闭结果框后再由本函数展示，避免两个居中弹窗重叠。
	if effect_result_modal != null and effect_result_modal.visible:
		if effect_modal != null:
			effect_modal.visible = false
		_current_waiting_effect = null
		return
	if not EffectManager.is_waiting_for_choice():
		if effect_modal and effect_modal.visible and _current_waiting_effect != null:
			effect_modal.visible = false
			_current_waiting_effect = null
		return
	
	var pending: BaseEffect = EffectManager.get_pending_active_effect()
	if pending == null:
		return
	
	# 手动效果(如令咒)不会被时点自动弹窗：引擎侧的 collect_current_effects 已经把
	# _is_manual 的效果排除在自动询问之外，玩家主动点击时才由 request_manual_activation 排进来。
	# 所以这里不能再按 _is_manual 把队列里的效果抹掉——那会连"玩家刚点出来的等待"一起清掉
	var trigger_id: int = pending._trigger_player_id
	# 若为AI对手的效果，由AI自动决断，绝不弹窗打扰玩家
	if trigger_id != _local_player_id and trigger_id >= 0:
		_resolve_bot_active_effect(pending, trigger_id)
		return
	
	# 若为本地玩家自身的主动效果，且尚未弹窗，立即展示时点抉择
	if pending != _current_waiting_effect:
		_current_waiting_effect = pending
		_show_effect_modal(pending)

## 选牌等待的处理：与"发动/放弃"并列的第二种玩家输入。
## 效果被发动后，若被选中的选项声明了 select_cards，就在这里停下来让玩家挑具体牌张
func _check_waiting_player_selection() -> void:
	# 与选牌并列的第三种玩家输入：选项声明了 select_players 时停下来让玩家点目标
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
	# AI 的目标由它自己按候选集挑，不弹窗打扰玩家
	if trigger_id != _local_player_id and trigger_id >= 0:
		_resolve_bot_player_selection(pending)
		return
	if _player_select_effect != eff or _player_select_panel == null or not _player_select_panel.visible:
		_show_player_select_panel(pending)


## 按候选集现建一个选人浮层：每个候选一张名牌，点谁就是谁。
## 候选来自数据声明（引擎侧求值），界面不判断"谁算对手"
func _show_player_select_panel(pending: Dictionary) -> void:
	var eff: BaseEffect = pending.get("effect")
	if eff == null:
		return
	_player_select_effect = eff
	var panel := _ensure_player_select_panel()
	if panel == null:
		return
	var vp := get_viewport_rect().size
	panel.position = Vector2(maxf(0.0, (vp.x - 520.0) * 0.5), vp.y * 0.2)
	var title := panel.get_node_or_null("Box/Title") as Label
	if title:
		var shown: String = str(eff._shown_name)
		title.text = shown if shown != "" else "请选择目标"
	var row := panel.get_node_or_null("Box/NameRow")
	if row == null:
		return
	for child in row.get_children():
		_free_runtime_child(child)
	for raw_id in pending.get("candidates", []):
		var pid: int = int(raw_id)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(120, 44)
		btn.text = _player_shown_name(pid)
		btn.pressed.connect(func(): _on_player_target_picked(pid))
		row.add_child(btn)
	panel.visible = true
	move_child(panel, get_child_count() - 1)

## 玩家名：取御主的展示名，取不到就退回玩家编号
func _player_shown_name(player_id: int) -> String:
	var data: Dictionary = GameDataManager.get_player_data(player_id)
	var master = data.get("master")
	if master != null and master.has_method("get_shown_name"):
		var nm: String = str(master.get_shown_name())
		if nm != "":
			return nm
	return "玩家%d" % player_id

func _on_player_target_picked(player_id: int) -> void:
	if _player_select_effect == null:
		return
	var eff := _player_select_effect
	_player_select_effect = null
	if _player_select_panel:
		_player_select_panel.visible = false
	EffectManager.submit_player_selection(eff, [player_id])
	refresh_all_ui()

## AI 的目标选择：交给临时 AI（策略见 system/ai/temp/dummy_bot.gd）
func _resolve_bot_player_selection(pending: Dictionary) -> void:
	DummyBot.new().resolve_player_selection(pending)


## 位置选择对本地玩家仍由地图点击完成；AI 复用同一套落点选择规则自动提交。
func _check_waiting_location_selection() -> void:
	var pending:Dictionary = EffectManager.get_pending_location_selection()
	if pending.is_empty():
		return
	var eff:BaseEffect = pending.get("effect")
	if eff == null:
		return
	var trigger_id:int = eff._trigger_player_id
	if trigger_id != _local_player_id and trigger_id >= 0:
		DummyBot.new().resolve_location_selection(pending, self)


## 供临时 AI 选择效果搬运落点：范围排除由数据声明，具体席位复用界面已有规则。
func ai_pick_effect_location(spec:Dictionary) -> BaseLocation:
	var forbidden:Array = spec.get("forbidden_target_areas", []) as Array
	for area:BaseMapArea in MapData.areas:
		if forbidden.has(str(area._area_name)):
			continue
		var target:BaseLocation = _first_effect_location_target(area, spec)
		if target != null:
			return target
	return null


## 选人浮层按需动态创建，不进场景模板
func _ensure_player_select_panel() -> Control:
	if _player_select_panel != null and is_instance_valid(_player_select_panel):
		return _player_select_panel
	var panel := PanelContainer.new()
	panel.name = "PlayerSelectPanel"
	panel.custom_minimum_size = Vector2(520, 140)
	panel.z_index = MODAL_Z_THRESHOLD + 5
	var box := VBoxContainer.new()
	box.name = "Box"
	panel.add_child(box)
	var title := Label.new()
	title.name = "Title"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35, 1.0))
	box.add_child(title)
	var row := HBoxContainer.new()
	row.name = "NameRow"
	box.add_child(row)
	add_child(panel)
	_player_select_panel = panel
	return panel

## 选牌等待的处理：与"发动/放弃"并列的第二种玩家输入。
## 效果被发动后，若被选中的选项声明了 select_cards，就在这里停下来让玩家挑具体牌张
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
	# AI 的挑牌由它自己按规则完成，不弹窗打扰玩家
	if trigger_id != _local_player_id and trigger_id >= 0:
		_resolve_bot_card_selection(pending)
		return
	if _card_select_effect != eff or _card_select_panel == null or not _card_select_panel.visible:
		_card_select_effect = eff
		_card_select_picked = []
		_show_card_select_panel(pending)
	else:
		_refresh_card_select_confirm(pending)


## 等玩家挑牌/选目标：交给临时 AI（策略见 system/ai/temp/dummy_bot.gd）
## （提交空 = 放弃。此刻来源资源与用量都还没扣，放弃等于这个效果没发动）
func _resolve_bot_card_selection(pending: Dictionary) -> void:
	DummyBot.new().resolve_card_selection(pending)
	refresh_all_ui()


## 选牌面板：结构与"效果决策弹窗"同源（标题 + 卡牌行 + 提示 + 两个按钮）。
## 骨架在场景里（Modal_CardSelect），脚本只接线——样式与尺寸在编辑器里可视化调整
func _ensure_card_select_panel() -> Control:
	if _card_select_panel != null and is_instance_valid(_card_select_panel):
		return _card_select_panel
	var panel := get_node_or_null("Modal_CardSelect") as Control
	if panel == null:
		return null
	_block_panel_clicks(panel)
	_enable_modal_drag(panel)
	var btn_ok := panel.get_node_or_null("Box/ButtonsRow/BtnConfirmSelect") as Button
	var btn_cancel := panel.get_node_or_null("Box/ButtonsRow/BtnCancelSelect") as Button
	if btn_ok != null and not btn_ok.has_meta("select_ok_bound"):
		btn_ok.set_meta("select_ok_bound", true)
		btn_ok.pressed.connect(_on_card_select_confirmed)
	if btn_cancel != null and not btn_cancel.has_meta("select_cancel_bound"):
		btn_cancel.set_meta("select_cancel_bound", true)
		btn_cancel.pressed.connect(_on_card_select_cancelled)
	_card_select_panel = panel
	return panel


func _show_card_select_panel(pending: Dictionary) -> void:
	_card_select_request = pending
	if not pending.get("regular", false):
		_card_select_submit = Callable()
	var panel := _ensure_card_select_panel()
	if panel == null:
		return
	_card_select_cards = pending.get("cards", [])
	# 面板摆在上方偏中，留出下面的手牌区（拖动可自行调整）
	var vp := get_viewport_rect().size
	panel.position = Vector2(maxf(0.0, (vp.x - 820.0) * 0.5), vp.y * 0.16)
	var title := panel.get_node_or_null("Box/Title") as Label
	if title:
		var shown: String = str(pending.get("shown_name", ""))
		title.text = shown if shown != "" else "请选择牌"
	var row := panel.get_node_or_null("Box/CardScroll/CardRow")
	if row == null:
		return
	# 卡位是随本次选牌现生成的，不属于场景模板，整批回收
	for child in row.get_children():
		_free_runtime_child(child)
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
		if pending.get("regular", false):
			var toggle := CheckButton.new()
			toggle.text = "暗置"
			toggle.position = Vector2(0, 162)
			toggle.disabled = not GameDataManager.get_player_data(_local_player_id).hand_cards.has(card)
			toggle.button_pressed = _card_select_hidden.get(card, false)
			toggle.toggled.connect(func(value):
				_card_select_hidden[card] = value
				_refresh_card_select_confirm(_card_select_request)
			)
			rect.add_child(toggle)
		_set_card_selected_mark(rect, _card_select_picked.has(card))
	panel.visible = true
	# 后显示的浮层排到子节点末尾：命中也按子节点倒序，排最后才能真正挡住下层
	move_child(panel, get_child_count() - 1)
	_refresh_card_select_confirm(pending)


## 点卡切换选中状态
func _on_select_card_input(ev: InputEvent, slot: Control) -> void:
	if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed):
		return
	var card = slot.get_meta("select_card", null)
	if card == null:
		return
	if _card_select_picked.has(card):
		_card_select_picked.erase(card)
		_set_card_selected_mark(slot, false)
	else:
		# 上限由声明决定：选满了就不再接受新的，避免提交上去被判非法
		var pending: Dictionary = _card_select_request
		var high: int = int(pending.get("max", -1))
		if high != -1 and _card_select_picked.size() >= high:
			return
		_card_select_picked.append(card)
		_set_card_selected_mark(slot, true)
	_refresh_card_select_confirm(_card_select_request)


## 已挑中的卡加一圈金色描边（只表达"选中"，不是"可点击"提示）
func _set_card_selected_mark(node: Control, selected: bool) -> void:
	if node == null:
		return
	var mark := node.get_node_or_null("SelectMark") as Panel
	if !selected:
		if mark != null:
			_free_runtime_child(mark)
		return
	if mark != null:
		return
	mark = Panel.new()
	mark.name = "SelectMark"
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.z_index = 3
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.draw_center = false
	sb.set_border_width_all(5)
	sb.border_color = Color(1.0, 0.85, 0.3)
	sb.set_corner_radius_all(8)
	mark.add_theme_stylebox_override("panel", sb)
	node.add_child(mark)
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## 提示与确认按钮的可用性：张数落在声明范围内才能确认
func _refresh_card_select_confirm(pending: Dictionary) -> void:
	if _card_select_panel == null:
		return
	var hint := _card_select_panel.get_node_or_null("Box/Hint") as Label
	if hint:
		var low: int = int(pending.get("min", 1))
		var high: int = int(pending.get("max", low))
		var range_text: String = ("%d-%d" % [low, high]) if high != -1 else ("至少 %d" % low)
		hint.text = "已选 %d · 可弃置 %s" % [_card_select_picked.size(), range_text]
	var btn_ok := _card_select_panel.get_node_or_null("Box/ButtonsRow/BtnConfirmSelect") as Button
	if btn_ok:
		btn_ok.text = "确认弃置"
		var low2: int = int(pending.get("min", 1))
		var high2: int = int(pending.get("max", low2))
		var ok: bool = _card_select_picked.size() >= low2
		if high2 != -1 and _card_select_picked.size() > high2:
			ok = false
		btn_ok.disabled = not ok


func _on_card_select_confirmed() -> void:
	if _card_select_submit.is_valid():
		_card_select_submit.call(_card_select_picked.duplicate(), _regular_hidden())
		return
	var eff := _card_select_effect
	if eff == null:
		return
	var picks: Array = _card_select_picked.duplicate()
	_card_select_effect = null
	_card_select_picked = []
	if _card_select_panel:
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
	var eff := _card_select_effect
	_card_select_effect = null
	_card_select_picked = []
	if _card_select_panel:
		_card_select_panel.visible = false
	if eff != null:
		# 空提交按"放弃"处理：此刻来源资源与用量都还没扣，等于这个效果没发动
		EffectManager.submit_card_selection(eff, [])
	refresh_all_ui()


## AI自动决断主动效果：策略全部在 system/ai/temp/dummy_bot.gd，界面这里只做委托
func _resolve_bot_active_effect(effect: BaseEffect, bot_id: int) -> void:
	DummyBot.new().resolve_active_effect(effect, bot_id)
	refresh_all_ui()

## 解析效果自身显式声明的消耗资源项。
## 卡牌的 _cost 是“打出这张牌”的费用，不是“发动牌上能力”的费用；
## 能力没有声明 cost 时不显示资源行，也不会在确认发动时扣卡牌费用。
func _resolve_effect_cost_items(effect: BaseEffect) -> Array[String]:
	var costs: Array[String] = []
	if effect == null:
		return costs
	if effect._cost != null:
		_collect_cost_items(effect._cost, costs)
	return costs

## 收集 cost 声明（支持单个 Dictionary 或 Array）
func _collect_cost_items(cost_data, out_costs: Array[String]) -> void:
	if cost_data is Dictionary:
		var one := _format_cost_item(cost_data)
		if one != "":
			out_costs.append(one)
	elif cost_data is Array:
		for item in cost_data:
			if item is Dictionary:
				var one := _format_cost_item(item)
				if one != "":
					out_costs.append(one)

## 格式化单项消耗：资源名 + 数字，无量词
func _format_cost_item(c_dict: Dictionary) -> String:
	var type_str: String = str(c_dict.get("type", "")).to_lower()
	var amount: int = int(c_dict.get("amount", 1))
	var res_name: String = str(c_dict.get("name", ""))
	match type_str:
		"buff":
			return "%s %d" % [res_name if res_name != "" else "状态", amount]
		"magic":
			return "魔力 %d" % amount
		"command_spell":
			return "令咒 %d" % amount
		_:
			return "%s %d" % [res_name, amount] if res_name != "" else ""

## 拼接消耗资源行：有消耗才追加，无消耗整行不显示
func _attach_cost_line(base_text: String, cost_items: Array[String]) -> String:
	if cost_items.is_empty():
		return base_text
	return base_text + "\n消耗资源：" + "、".join(cost_items)

## 效果确认弹窗（无标题、无括号、无消耗则不显示资源行）
## 选项类效果(单选/多选)动态生成勾选行；带quantity_range的选项额外带一个数量选择器；
## 普通效果保持原有"确认发动/放弃"二元弹窗
func _show_effect_modal(effect: BaseEffect) -> void:
	if effect_modal == null:
		return
	var desc_lbl := effect_modal.get_node_or_null("Box/VBox/Desc") as Label
	var options_row := effect_modal.get_node_or_null("Box/VBox/OptionsRow") as VBoxContainer
	var btn_confirm := effect_modal.get_node_or_null("Box/VBox/ButtonsRow/BtnConfirm") as Button
	if desc_lbl == null:
		return
	var eff_name: String = effect._shown_name if effect._shown_name != "" else "未知效果"

	if effect.has_options():
		var is_multi: bool = effect.allows_multi_choice()
		desc_lbl.text = "发动【%s】\n%s" % [eff_name, ("请选择要发动的效果（可多选）" if is_multi else "请选择要发动的效果")]
		if options_row:
			for child in options_row.get_children():
				_free_runtime_child(child)
			options_row.visible = true
			for i in range(effect._options.size()):
				var opt: Dictionary = effect._options[i]
				var opt_name: String = opt.get("shown_option_name", "选项%d" % (i + 1))
				var available: bool = EffectManager.is_option_available(effect, i)
				if !available:
					# 用量已耗尽的选项：文案标注剩余次数用完，禁止再选，但仍展示让玩家知道存在过
					var opt_max: int = opt.get("max_uses", -1) as int
					opt_name += "（已用完）" if opt_max != -1 else "（不可选）"
				var has_qty: bool = opt.has("quantity_range")
				if is_multi:
					var row := HBoxContainer.new()
					row.name = "OptRow_%d" % i
					var cb := CheckBox.new()
					cb.text = opt_name
					cb.name = "Opt_%d" % i
					cb.disabled = !available
					# 勾选一变就刷新"确认发动"可用性：空勾选提交会被引擎当成放弃，
					# 玩家以为发动了却什么都没发生
					cb.toggled.connect(_refresh_effect_confirm_state.bind(options_row, btn_confirm))
					row.add_child(cb)
					if has_qty and available:
						row.add_child(_build_quantity_spinbox(opt["quantity_range"], i))
					options_row.add_child(row)
				elif has_qty:
					# 单选+带数量：数量选择器和"确认此项"按钮放一行，选好数量再提交，不是点了就走
					var row := HBoxContainer.new()
					row.name = "OptRow_%d" % i
					var lbl := Label.new()
					lbl.text = opt_name
					row.add_child(lbl)
					var spin := _build_quantity_spinbox(opt["quantity_range"], i)
					row.add_child(spin)
					var confirm_btn := Button.new()
					confirm_btn.text = "确认"
					confirm_btn.disabled = !available
					confirm_btn.pressed.connect(_on_effect_option_picked_with_quantity.bind(i, spin))
					row.add_child(confirm_btn)
					options_row.add_child(row)
				else:
					var opt_btn := Button.new()
					opt_btn.text = opt_name
					opt_btn.custom_minimum_size = Vector2(0, 38)
					opt_btn.disabled = !available
					# 单选：点哪个选项直接提交那一项，不需要再点确认
					opt_btn.pressed.connect(_on_effect_option_picked.bind(i))
					options_row.add_child(opt_btn)
		if btn_confirm:
			# 多选靠勾选后点"确认发动"提交；单选靠上面按钮直接提交，确认按钮隐藏
			btn_confirm.visible = is_multi
			btn_confirm.text = "确认发动"
			_refresh_effect_confirm_state(options_row, btn_confirm)
	else:
		if options_row:
			options_row.visible = false
			for child in options_row.get_children():
				_free_runtime_child(child)
		if btn_confirm:
			btn_confirm.visible = true
			btn_confirm.disabled = false
			btn_confirm.text = "确认发动"
		desc_lbl.text = _attach_cost_line("发动【%s】" % eff_name, _resolve_effect_cost_items(effect))
	effect_modal.visible = true
	# 与确认弹窗同一套：后显示的排最后，才能既画在上层又挡住下层点击
	move_child(effect_modal, get_child_count() - 1)

## 多选效果的"确认发动"可用性：一个都没勾就不让点，避免空提交被当成放弃
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

## 通用数量选择器：min~max范围的SpinBox，供带quantity_range的选项复用
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

## 单选分支：点击某个选项按钮直接提交该选项，不用再点确认
func _on_effect_option_picked(option_index: int) -> void:
	if _current_waiting_effect:
		var eff = _current_waiting_effect
		_current_waiting_effect = null
		if effect_modal:
			effect_modal.visible = false
		EffectManager.submit_option_choice(eff, [option_index])
		_refresh_pending_input_tip()
		_refresh_clickable_strength()
		refresh_all_ui()

## 单选+带数量分支：读取数量选择器的值，先记录数量再提交该选项
func _on_effect_option_picked_with_quantity(option_index: int, spin: SpinBox) -> void:
	if _current_waiting_effect:
		var eff = _current_waiting_effect
		var qty: int = int(spin.value) if spin else 1
		_current_waiting_effect = null
		if effect_modal:
			effect_modal.visible = false
		eff.set_option_quantity(option_index, qty)
		EffectManager.submit_option_choice(eff, [option_index])
		refresh_all_ui()

func _on_effect_modal_confirm() -> void:
	if _current_waiting_effect:
		var eff = _current_waiting_effect
		_current_waiting_effect = null
		if effect_modal:
			effect_modal.visible = false
		if eff.has_options() and eff.allows_multi_choice():
			# 多选：收集所有勾选中的CheckBox对应下标一并提交，同时读取各自的数量选择器(若有)
			var picked: Array = []
			var options_row := effect_modal.get_node_or_null("Box/VBox/OptionsRow") as VBoxContainer
			if options_row:
				for i in range(options_row.get_child_count()):
					var row := options_row.get_child(i)
					var cb := row.get_node_or_null("Opt_%d" % i) as CheckBox
					if cb == null:
						cb = row as CheckBox
					if cb and cb.button_pressed:
						picked.append(i)
						var spin := row.get_node_or_null("Qty_%d" % i) as SpinBox
						if spin:
							eff.set_option_quantity(i, int(spin.value))
			EffectManager.submit_option_choice(eff, picked)
		else:
			EffectManager.submit_active_choice(eff, true)
		refresh_all_ui()

func _on_effect_modal_cancel() -> void:
	if _current_waiting_effect:
		var eff = _current_waiting_effect
		_current_waiting_effect = null
		if effect_modal:
			effect_modal.visible = false
		EffectManager.submit_active_choice(eff, false)
		refresh_all_ui()

## -------------------------------------------------------------
## 5. 对手极简 AI 自动轮转 (Dummy Bot Agent)
## -------------------------------------------------------------
## 在当前玩家阶段窗口中，自动询问一条尚未询问过的手动能力。
## 返回 true 表示当前仍需等待玩家处理，调用方不得推进阶段。
func _prompt_next_manual_activation(player_id:int, phase_name:String) -> bool:
	var scope := "%d:%s:%d" % [GameProgress.current_round, phase_name, player_id]
	if _manual_prompt_scope != scope:
		_manual_prompt_scope = scope
		_manual_prompted_effect_ids.clear()
	# 先处理已经展示的规则提示/确认；不能在其上再叠一层战斗能力询问。
	if tactical_confirm_modal != null and tactical_confirm_modal.visible:
		return true
	# 已有任意输入等待时保持暂停；不能用新的能力询问覆盖选项、选牌、地点或玩家选择。
	if EffectManager.is_waiting_for_choice():
		return true
	for effect in EffectManager.manual_activations(player_id):
		var effect_id:int = effect.get_instance_id()
		if _manual_prompted_effect_ids.has(effect_id):
			continue
		# 请求前先登记，避免请求过程中同步刷新/重入时重复加入同一效果。
		_manual_prompted_effect_ids.append(effect_id)
		if EffectManager.request_manual_activation(effect, player_id):
			_check_waiting_effects()
			return true
	return false


func _check_and_step_ai(delta: float = 0.0) -> void:
	if GameProgress.is_game_over:
		return
	if effect_result_modal != null and effect_result_modal.visible:
		return
	# 上一轮 AI 步进被脚本异常打断时兜底复位：否则一个错误会把整局 AI 永久冻住
	if _ai_acting:
		if GameProgress.current_player_id != _ai_acting_for_id:
			_ai_acting = false
		return
	var curr_id: int = GameProgress.current_player_id
	var phase_name: String = str(GameProgress.get_current_phase().get("name", ""))
	#准备阶段与战斗阶段都没有"点击类"操作：准备阶段能做的只有能力（有抉择时
	#EffectManager 会挂起，end_current_player_action 自己就推不动），所以逐个跳过，
	#不让回合停在没有操作可做的玩家身上。战斗阶段同理，最后由 end_phase 统一结算。
	#但这两个阶段确实存在"要玩家决定的"手动效果（"战斗阶段：关闭此牌，然后从手牌
	#打出一张力量基础攻击"这类）：无条件推进会让它们永远没机会使用，玩家看到的就是
	#"战斗阶段可以使用的效果被直接跳过"。所以本地玩家此刻点得动时先停下来等他点，
	#金框已经亮着，点结束阶段即可继续；AI 没有这类决策，仍然逐个跳过。
	if phase_name == "battle" or phase_name == "prepare":
		if curr_id < 0:
			return
		if curr_id == _local_player_id:
			#本地玩家：逐条弹出此刻可发动的手动能力；全部询问完才自动推进。
			#准备阶段沿用原有“有能力则停住供点击”的口径，自动询问只用于用户明确要求的战斗阶段。
			if phase_name == "battle" and _prompt_next_manual_activation(curr_id, phase_name):
				return
			if phase_name != "battle" and EffectManager.has_manual_activation(curr_id):
				return
			GameProgress.end_current_player_action()
			return
		#对手：只有在它真的有阶段能力要发动时才走决策路径（并照旧节流），
		#否则直接跳过——不为了一个空决策把战斗阶段的推进变慢
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
	if curr_id < 0:
		return
	#本地玩家也没有战斗阶段操作，避免回合在本地玩家处停住。
	if curr_id == _local_player_id:
		return
	# 节流：不在一帧里把整轮对手跑完，玩家才看得到 AI 的行动过程
	_ai_cooldown -= delta
	if _ai_cooldown > 0.0:
		return
	_ai_cooldown = AI_STEP_INTERVAL
	_ai_acting = true
	_ai_acting_for_id = curr_id
	_run_dummy_bot_turn(curr_id)
	_ai_acting = false

func _run_dummy_bot_turn(bot_id: int) -> void:
	#每位 AI 开始行动前清除上一位玩家的提示，避免提示残留到新的行动者
	_ai_play_prompt_player_id = -1
	_ai_play_prompt_card = null
	_ai_play_prompt_round = -1
	if is_instance_valid(_ai_play_prompt_node):
		_ai_play_prompt_node.visible = false
	#行为全部在 system/ai/temp/dummy_bot.gd：界面只提供展示与查询能力
	DummyBot.new().step(self, bot_id)

## -------------------------------------------------------------
## 宿主能力：临时 AI（DummyBot）按这些公开方法取它需要的东西。
## AI 不直接摸界面私有状态，界面也不必知道 AI 的策略
## -------------------------------------------------------------
func ai_deploy_areas() -> Array:
	var areas: Array = []
	for area: BaseMapArea in MapData.areas:
		if !_open_deploy_locations(area).is_empty():
			areas.append(area)
	return areas

func ai_pick_deploy_location(area: BaseMapArea) -> BaseLocation:
	return _pick_open_deploy_location(area)

func ai_apply_deploy_benefit(target: BaseLocation, bot_id: int) -> void:
	_apply_deploy_benefit(target, bot_id)

func ai_record_played_card(bot_id: int, card: BaseCard) -> void:
	_set_ai_play_prompt(bot_id, card)

## 记录 AI 最近一次成功出牌，提示节点只保存身份与卡牌引用，不按顶栏位置猜玩家。
func _set_ai_play_prompt(bot_id: int, card: BaseCard) -> void:
	if bot_id == _local_player_id:
		return
	_ai_play_prompt_player_id = bot_id
	_ai_play_prompt_card = card
	# 提示只在本回合内有意义：记下回合号，跨回合自动失效，不用额外的清理调用点
	_ai_play_prompt_round = GameProgress.current_round
	#出牌发生在 AI 步进中，不能等下一次整屏刷新；等本帧顶栏布局完成后立即显示。
	_refresh_ai_play_prompt.call_deferred()

## 在对应 AI 顶栏卡位下方显示“已出牌 · 点击查看”。点击后打开该玩家抽屉，
## 抽屉内的已出牌卡仍由 _fill_card_row_from_list + _bind_zoom_info 处理放大与说明。
func _refresh_ai_play_prompt() -> void:
	var order_box := get_node_or_null(ORDER_BOX_PATH) as HBoxContainer
	if order_box == null:
		return
	var target: Control = null
	# 轮到本地玩家时，上一位 AI 的出牌提示不再有意义（手牌与出牌区就在眼前）。
	# 只靠"新 AI 行动开始时清理"不够：本地玩家不会走 AI 那条路径，提示会一直挂在界面上
	var show_ok: bool = _ai_play_prompt_round == GameProgress.current_round \
			and _ai_play_prompt_card != null \
			and GameProgress.current_player_id >= 0 \
			and GameProgress.current_player_id != _local_player_id
	if show_ok:
		for child in order_box.get_children():
			if child is Control and int(child.get_meta("turn_order_player_id", -1)) == _ai_play_prompt_player_id:
				target = child
				break
	if target == null or str(target.name) == LOCAL_ORDER_SLOT_NAME:
		if is_instance_valid(_ai_play_prompt_node):
			_ai_play_prompt_node.hide()
		return
	if not is_instance_valid(_ai_play_prompt_node):
		var prompt := Button.new()
		_ai_play_prompt_node = prompt
		prompt.name = "AIPlayPrompt"
		prompt.custom_minimum_size = Vector2(226, 178)
		prompt.pressed.connect(_on_ai_play_prompt_pressed)
		add_child(prompt)
		var title := Label.new()
		title.name = "Title"
		title.text = "已出牌 · 点击查看"
		title.position = Vector2(10, 6)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.add_theme_font_size_override("font_size", 22)
		title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.3))
		prompt.add_child(title)
		var scroll := ScrollContainer.new()
		scroll.name = "CardsScroll"
		scroll.mouse_filter = Control.MOUSE_FILTER_PASS
		scroll.position = Vector2(10, 40)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		prompt.add_child(scroll)
		var row := HBoxContainer.new()
		row.name = "Cards"
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_theme_constant_override("separation", 8)
		scroll.add_child(row)
		prompt.z_index = MODAL_Z_THRESHOLD - 1
		_reorder_child_by_z(prompt)
	var cards: Array = GameDataManager.get_player_data(_ai_play_prompt_player_id).get("played_cards", [])
	var row := _ai_play_prompt_node.get_node("CardsScroll/Cards") as HBoxContainer
	while row.get_child_count() > cards.size():
		_free_runtime_child(row.get_child(row.get_child_count() - 1))
	for i in range(cards.size()):
		var texture: TextureRect
		if i < row.get_child_count():
			texture = row.get_child(i) as TextureRect
		else:
			texture = TextureRect.new()
			texture.custom_minimum_size = Vector2(82, 116)
			texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(texture)
			texture.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
					_on_ai_play_prompt_pressed()
					get_viewport().set_input_as_handled()
			)
		_render_card_face(texture, cards[i], false)
		texture.mouse_filter = Control.MOUSE_FILTER_STOP
	_ai_play_prompt_node.set_meta("ai_prompt_player_id", _ai_play_prompt_player_id)
	_ai_play_prompt_node.size = Vector2(maxf(226, target.size.x), 144)
	var scroll := _ai_play_prompt_node.get_node("CardsScroll") as ScrollContainer
	scroll.size = _ai_play_prompt_node.size - Vector2(20, 48)
	_update_ai_play_prompt_geometry()
	_apply_clickable_indicator(_ai_play_prompt_node, Color(1.0, 0.75, 0.2))
	_set_clickable_active(_ai_play_prompt_node, true)

func _on_ai_play_prompt_pressed() -> void:
	if _ai_play_prompt_node == null:
		return
	var player_id: int = int(_ai_play_prompt_node.get_meta("ai_prompt_player_id", -1))
	if player_id < 0:
		return
	var order_box := get_node_or_null(ORDER_BOX_PATH) as HBoxContainer
	if order_box == null:
		return
	for child in order_box.get_children():
		if child is Control and int(child.get_meta("turn_order_player_id", -1)) == player_id:
			_selected_opponent = child
			_selected_opponent_id = player_id
			_update_drawer_visuals(child)
			if opponent_drawer:
				opponent_drawer.visible = true
			if leaderboard_drawer:
				leaderboard_drawer.visible = false
			break

## 注意这里**不能**用 _will_move_to 当判据：那个字段的含义是"常规移动会去的落点"，
## 与"能不能部署"是两回事——地利位/充能位都不是常规移动目的地，却正是部署要抢的席位。
## 哪个战区可部署由地图数据声明(area._can_deploy)，不在这里写死战区下标
## 以下四个都是对 DeployRules 的转发：部署判定属于规则，已下沉到 system/deploy_rules.gd。
## 界面保留同名薄包装，让点击入口、AI、既有测试的调用点不必各自改写；
## 规则本体只有一份，任何不经界面的推进（headless、AI 推演）也能正确部署
func _open_deploy_locations(area: BaseMapArea) -> Array:
	return DeployRules.open_locations(area)

func _apply_deploy_benefit(loc: BaseLocation, player_id: int) -> void:
	DeployRules.apply_benefit(loc, player_id)

func _pick_open_deploy_location(area: BaseMapArea) -> BaseLocation:
	return DeployRules.pick_location(area)

func _deploy_slot_score(loc: BaseLocation) -> int:
	return DeployRules.slot_score(loc)

## -------------------------------------------------------------
## 6. 辅助折叠菜单与悬浮手牌托盘
## -------------------------------------------------------------
func _register_opponent_cards() -> void:
	var order_box := get_node_or_null("TopPanel_AllPlayers/AllPlayersOrderScroll/OrderHBox")
	if order_box == null:
		return
	for child in order_box.get_children():
		if child.name.begins_with("P") and child.name != "P1_Me_AvatarOnly":
			child.mouse_filter = Control.MOUSE_FILTER_STOP
			if not child.gui_input.is_connected(_on_opponent_gui_input):
				child.gui_input.connect(_on_opponent_gui_input.bind(child))

## 判断屏幕坐标是否落在任一顶栏对手卡片（P2~P7 整块）上——用于抽屉"点外部关闭"时
## 排除头像格本身，头像格自己的开/关/切换逻辑走 _on_opponent_gui_input，不能被这里抢先关掉
func _is_point_over_opponent_cards(pos: Vector2) -> bool:
	var order_box := get_node_or_null("TopPanel_AllPlayers/AllPlayersOrderScroll/OrderHBox")
	if order_box == null:
		return false
	for child in order_box.get_children():
		if child is Control and child.name.begins_with("P") and child.name != "P1_Me_AvatarOnly":
			if (child as Control).get_global_rect().has_point(pos):
				return true
	return false

func _register_leaderboard_toggle() -> void:
	var btn_rank := get_node_or_null("TopPanel_AllPlayers/BtnRankMenu") as Button
	if btn_rank:
		# 战果榜开关只是打开/收起排行榜的入口，不是"此刻能操作的目标"：
		# 声明退出呼吸金框提示，保留按钮自身样式
		btn_rank.set_meta("no_clickable_hint", true)
	if btn_rank and not btn_rank.pressed.is_connected(_on_leaderboard_btn_pressed):
		btn_rank.pressed.connect(_on_leaderboard_btn_pressed)

func _on_leaderboard_btn_pressed() -> void:
	if leaderboard_drawer == null:
		return
	var will_show: bool = not leaderboard_drawer.visible
	leaderboard_drawer.visible = will_show
	if will_show:
		_refresh_leaderboard()
	if will_show and opponent_drawer and opponent_drawer.visible:
		opponent_drawer.visible = false
		_selected_opponent = null

func _on_opponent_gui_input(event: InputEvent, opponent_card: Control) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var avatar := opponent_card.get_node_or_null("HBox/Avatar") as TextureRect
	# 顶栏整块会抢走头像命中：鼠标落在头像矩形上时，右键走头像说明、左键仍开抽屉
	var over_avatar: bool = avatar != null and avatar.get_global_rect().has_point(event.global_position)
	if event.button_index == MOUSE_BUTTON_RIGHT and over_avatar:
		if _show_zoom_and_desc_for(avatar):
			get_viewport().set_input_as_handled()
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if opponent_drawer.visible and _selected_opponent_id == int(opponent_card.get_meta("turn_order_player_id", -1)):
			_selected_opponent = null
			_selected_opponent_id = -1
			if opponent_drawer:
				opponent_drawer.visible = false
		else:
			_selected_opponent = opponent_card
			_selected_opponent_id = int(opponent_card.get_meta("turn_order_player_id", -1))
			_update_drawer_visuals(opponent_card)
			if opponent_drawer:
				opponent_drawer.visible = true
			if leaderboard_drawer:
				leaderboard_drawer.visible = false
		get_viewport().set_input_as_handled()

func _update_ai_play_prompt_geometry() -> void:
	if not is_instance_valid(_ai_play_prompt_node):
		return
	if _ai_play_prompt_round != GameProgress.current_round or _ai_play_prompt_card == null \
			or _ai_play_prompt_player_id < 0 or GameProgress.current_player_id == _local_player_id \
			or GameDataManager.get_player_data(_ai_play_prompt_player_id).get("played_cards", []).is_empty():
		_ai_play_prompt_node.hide()
		return
	var order_box := get_node_or_null(ORDER_BOX_PATH) as HBoxContainer
	var target: Control = null
	if order_box != null:
		for child in order_box.get_children():
			if child is Control and int(child.get_meta("turn_order_player_id", -1)) == _ai_play_prompt_player_id:
				target = child
				break
	if target == null or not target.is_visible_in_tree() or str(target.name) == LOCAL_ORDER_SLOT_NAME:
		_ai_play_prompt_node.hide()
		return
	# Rectangles must share canvas coordinates; size alone ignores ancestor scaling.
	var target_rect := target.get_global_rect()
	var bounds := get_viewport_rect()
	var visible_rect := target_rect.intersection(bounds)
	var ancestor := target.get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents:
			visible_rect = visible_rect.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	if not visible_rect.has_area():
		_ai_play_prompt_node.hide()
		return
	var prompt_size := _ai_play_prompt_node.get_global_rect().size
	# 始终向顶栏卡位上方展开；空间不足就贴住视口上缘，不能回退到棋盘标题区。
	var above_y: float = target_rect.position.y - prompt_size.y - 4.0
	var prompt_y: float = maxf(bounds.position.y, above_y)
	_ai_play_prompt_node.global_position = Vector2(
		clampf(target_rect.get_center().x - prompt_size.x * 0.5, bounds.position.x, maxf(bounds.position.x, bounds.end.x - prompt_size.x)),
		clampf(prompt_y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - prompt_size.y)))
	_ai_play_prompt_node.show()

func _refresh_open_opponent_drawer() -> void:
	if opponent_drawer == null or not opponent_drawer.visible or _selected_opponent_id < 0:
		return
	var box := get_node_or_null(ORDER_BOX_PATH) as HBoxContainer
	if box == null: return
	for child in box.get_children():
		if child is Control and int(child.get_meta("turn_order_player_id", -1)) == _selected_opponent_id:
			_selected_opponent = child
			_update_drawer_visuals(child)
			return

func _set_true_name_status(label: Label, player_id: int) -> void:
	if label == null: return
	var released := ReleaseTrueName.is_released(player_id)
	label.text = "真名解放" if released else "真名未解放"
	label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.3) if released else Color(0.6, 0.64, 0.7))

func _update_drawer_visuals(opponent_card: Control) -> void:
	if opponent_drawer == null:
		return
	# 玩家 id 只认卡位上的身份绑定：按节点名猜 id 在顺位被打乱后会取到别人的资料
	var bot_id: int = int(opponent_card.get_meta("turn_order_player_id", -1))
	if bot_id < 0:
		return
	_selected_opponent_id = bot_id
	_selected_opponent = opponent_card
	var pl_data: Dictionary = GameDataManager.get_player_data(bot_id) if (GameDataManager and bot_id >= 0) else {}
	if pl_data.is_empty():
		return
	_refresh_removed_cards_entry(
		opponent_drawer.get_node_or_null("VBox/HeaderBar/BtnOutOfGame") as Button,
		pl_data, false
	)
	var master_obj = pl_data.get("master")
	var servant_obj = pl_data.get("servant")
	
	# 1. 头部头像与顺位徽章
	var avatar := opponent_card.get_node_or_null("HBox/Avatar") as TextureRect
	var selected_avatar := opponent_drawer.get_node_or_null("VBox/HeaderBar/SelectedAvatarFrame/Avatar") as TextureRect
	if avatar and selected_avatar:
		selected_avatar.texture = avatar.texture
	_bind_zoom_info(selected_avatar, master_obj, "_header_img")
	var order_badge := opponent_drawer.get_node_or_null("VBox/HeaderBar/OrderBadge") as Label
	if order_badge:
		order_badge.text = "%s\n战果%d" % [
			_object_shown_name(master_obj),
			(pl_data.get("score", BaseNumber.new(0)) as BaseNumber).number
		]
	# 已打出牌标题：按该对手真实所在战区与合计威力生成，不再是场景预置的固定文案
	var played_lbl := opponent_drawer.get_node_or_null("VBox/CardsContentRow/Col_PlayedCards_Opponent/Label") as Label
	if played_lbl:
		var opp_loc = pl_data.get("location") as BaseLocation
		var opp_area := opp_loc.get_from() as BaseMapArea if opp_loc != null else null
		var opp_area_txt: String = opp_area._area_name if opp_area != null else "未部署"
		# 与战斗结算共用同一份威力公式，界面不自己拼
		var opp_power: int = GetPlayerTotalPower.new().exec(bot_id)
		played_lbl.text = "⚔️ %s 已打出牌 · 威力 %d" % [opp_area_txt, opp_power]
	
	# 2. 公开御主卡 / 从者卡（从者未公开时显示卡背且不放大）
	var master_card := opponent_drawer.get_node_or_null("VBox/CardsContentRow/Col_MasterServant/CardsH/MasterCard") as TextureRect
	if master_card:
		master_card.set_meta("zoom_disabled", false)
		_fill_card_slot(master_card, master_obj, "_master_card_img")
	var servant_card := opponent_drawer.get_node_or_null("VBox/CardsContentRow/Col_MasterServant/CardsH/ServantCard") as TextureRect
	if servant_card and servant_obj:
		var revealed := ReleaseTrueName.is_released(bot_id)
		if not revealed:
			servant_card.texture = LoadHelper.load_texture(LoadHelper.resolve_card_back("", "", "servant"))
			servant_card.set_meta("zoom_disabled", true)
		else:
			servant_card.set_meta("zoom_disabled", false)
			_fill_card_slot(servant_card, servant_obj, "_servant_card_img")
	
	# 3. 该对手已打出的牌：与本地信息栏共用同一套铺卡逻辑（卡位复用场景模板、不足才克隆），
	# 抽屉里的卡不可发动(clickable=false)、别人的未公开牌按卡背渲染(owned=false)
	var opp_row := opponent_drawer.get_node_or_null("VBox/CardsContentRow/Col_PlayedCards_Opponent/CardsOverlapRow") as Control
	if opp_row:
		_fill_card_row_from_list(opp_row, pl_data.get("played_cards", []), false, false, false)
	
	# 4. 资源文字：魔力/令咒/所在战区按真实数据填，不用场景预置文案
	var magic_lbl := opponent_drawer.get_node_or_null("VBox/HeaderBar/ResourceVisuals/MagicH/Magic") as Label
	if magic_lbl:
		magic_lbl.text = "魔力: %d" % (pl_data.get("magic", BaseNumber.new(0)) as BaseNumber).number
	var cs_lbl_node := opponent_drawer.get_node_or_null("VBox/HeaderBar/ResourceVisuals/CommandSpells") as Label
	if cs_lbl_node:
		cs_lbl_node.text = "令咒 ×%d" % (pl_data.get("command_spell_count", BaseNumber.new(3)) as BaseNumber).number
	var marker_lbl := opponent_drawer.get_node_or_null("VBox/HeaderBar/ResourceVisuals/BattleMarker") as Label
	if marker_lbl:
		var loc = pl_data.get("location")
		var area = loc.get_from() if loc != null else null
		var area_name: String = str(area._area_name) if (area != null and "_area_name" in area) else ""
		if area_name == "":
			marker_lbl.text = "未部署"
		else:
			marker_lbl.text = area_name + (" · 交战" if bool(pl_data.get("is_battle", false)) else "")
	# 对手抽屉内的总威力展示与即时悬浮浮层
	var rv := opponent_drawer.get_node_or_null("VBox/HeaderBar/ResourceVisuals") as VBoxContainer
	if rv != null:
		var opp_power_lbl := rv.get_node_or_null("OpponentTotalPower") as Label
		if opp_power_lbl == null:
			opp_power_lbl = Label.new()
			opp_power_lbl.name = "OpponentTotalPower"
			opp_power_lbl.add_theme_font_size_override("font_size", 12)
			opp_power_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35, 1.0))
			rv.add_child(opp_power_lbl)
		var opp_power_num: int = GetPlayerTotalPower.new().exec(bot_id)
		opp_power_lbl.text = "合计威力: %d" % opp_power_num
		_bind_instant_power_tooltip(opp_power_lbl, bot_id)
	var hint_lbl := opponent_drawer.get_node_or_null("VBox/HeaderBar/IdentityHint") as Label
	_set_true_name_status(hint_lbl, bot_id)
	
## 5. 未入牌库的卡（技能牌/御主专属技能攻击牌/升华技/附带物）：与本地信息栏同一套采集
	## 与渲染逻辑，暗置的从者技能牌显示卡背；对手抽屉里这些卡只展示不可点击发动
	var skills_col := opponent_drawer.get_node_or_null("VBox/CardsContentRow/Col_Skills")
	if skills_col:
		var skills_row := skills_col.get_node_or_null("CardsH") as HBoxContainer
		if skills_row:
			# 与本地信息栏同一套：按组铺，某类牌被打出后其余类不前移
			var card_groups: Array = _collect_uncataloged_card_groups(pl_data)
			var cards: Array = _collect_uncataloged_cards(pl_data)
			skills_col.visible = !cards.is_empty()
			_fill_card_row_by_groups(skills_row, card_groups, false, false)

## 6. buff 专区：无 buff 整列隐藏；无图标显示"名字 ×层数"，有图标额外加一个小图。
	## 御主的卡类附带物已并入第 5 步的统一采集范围，这里只负责 BUFF 状态展示，
	## 不与卡类附带物混在一起——BUFF 不是卡，不该出现在"卡"的展示区里
	var buffs: Array = []
	if master_obj != null:
		var sp = master_obj.get("_specials")
		if sp is Dictionary:
			buffs = sp.get("BUFFS", [])
	_refresh_buff_zone(
		opponent_drawer.get_node_or_null("VBox/CardsContentRow/Col_Buffs"),
		opponent_drawer.get_node_or_null("VBox/CardsContentRow/Col_Buffs/BuffsH"),
		buffs
	)

func _setup_floating_hand_tray() -> void:
	if hand_tray == null:
		return
	hand_tray.visible = true
	hand_tray.mouse_filter = Control.MOUSE_FILTER_STOP
	hand_tray.offset_top = HAND_COLLAPSED_TOP
	hand_tray.offset_bottom = HAND_COLLAPSED_BOTTOM
	if not hand_tray.mouse_entered.is_connected(_on_hand_tray_mouse_entered):
		hand_tray.mouse_entered.connect(_on_hand_tray_mouse_entered)
	if not hand_tray.mouse_exited.is_connected(_on_hand_tray_mouse_exited):
		hand_tray.mouse_exited.connect(_on_hand_tray_mouse_exited)

func _on_hand_tray_mouse_entered() -> void:
	_expand_hand_tray()

func _on_hand_tray_mouse_exited() -> void:
	# 按钮锁定展开时不因鼠标移开而收起
	if _hand_pinned_open:
		return
	if not _last_hand_hover_state:
		_collapse_hand_tray()

## 底栏"手牌"按钮：已展开就收起，否则展开并锁定，鼠标移开也不自动收
func _on_toggle_hand_tray_pressed() -> void:
	_hand_pinned_open = not _hand_is_expanded
	if _hand_pinned_open:
		_expand_hand_tray()
	else:
		_collapse_hand_tray()

## 对手抽屉的关闭按钮：与"再点头像"共用同一套状态清理
func _on_close_opponent_drawer_pressed() -> void:
	_selected_opponent = null
	_selected_opponent_id = -1
	if opponent_drawer:
		opponent_drawer.visible = false

func _expand_hand_tray() -> void:
	if hand_tray == null or _hand_is_expanded:
		return
	_hand_is_expanded = true
	if _hand_tween:
		_hand_tween.kill()
	_hand_tween = create_tween()
	_hand_tween.set_parallel(true)
	_hand_tween.tween_property(hand_tray, "offset_top", HAND_EXPANDED_TOP, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hand_tween.tween_property(hand_tray, "offset_bottom", HAND_EXPANDED_BOTTOM, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _collapse_hand_tray() -> void:
	if hand_tray == null or not _hand_is_expanded:
		return
	_hand_is_expanded = false
	if _hand_tween:
		_hand_tween.kill()
	_hand_tween = create_tween()
	_hand_tween.set_parallel(true)
	_hand_tween.tween_property(hand_tray, "offset_top", HAND_COLLAPSED_TOP, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_hand_tween.tween_property(hand_tray, "offset_bottom", HAND_COLLAPSED_BOTTOM, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## -------------------------------------------------------------
## 战报结算弹窗 (Battle Report Modal)
## -------------------------------------------------------------
func _check_battle_report() -> void:
	if battle_report_modal == null:
		return
	var res: Dictionary = GameProgress.last_battle_result if GameProgress else {}
	if not res.is_empty() and res != _shown_battle_result:
		_shown_battle_result = res
		_show_battle_report(res)

func _ensure_battle_report_backdrop() -> ColorRect:
	if _battle_report_backdrop != null and is_instance_valid(_battle_report_backdrop):
		return _battle_report_backdrop
	var backdrop := ColorRect.new()
	backdrop.name = "BattleReportBackdrop"
	backdrop.color = Color(0.0, 0.0, 0.0, 0.18)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.z_index = MODAL_Z_THRESHOLD + 19
	# 先隐藏再入树：全屏遮罩一旦可见就会吞掉所有落在它上面的点击，
	# 任何"创建了却忘了隐藏"的路径都会让右侧常驻入口按钮点不动
	backdrop.visible = false
	backdrop.gui_input.connect(func(ev:InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			get_viewport().set_input_as_handled()
	)
	add_child(backdrop)
	_battle_report_backdrop = backdrop
	return backdrop


## -------------------------------------------------------------
## 威力即时悬浮浮层：鼠标移到威力数字上立刻出现，没有任何系统级0.5秒延迟
## -------------------------------------------------------------
func _ensure_power_tooltip_panel() -> PanelContainer:
	if _power_tooltip_panel != null and is_instance_valid(_power_tooltip_panel):
		return _power_tooltip_panel
	var panel := PanelContainer.new()
	panel.name = "InstantPowerTooltipPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 250
	panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.16, 0.95)
	sb.border_color = Color(1.0, 0.85, 0.35, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.name = "VBox"
	var title := Label.new()
	title.name = "Title"
	title.text = "威力构成"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35, 1.0))
	vbox.add_child(title)
	var desc := Label.new()
	desc.name = "Desc"
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 1.0))
	vbox.add_child(desc)
	panel.add_child(vbox)
	add_child(panel)
	_power_tooltip_panel = panel
	return panel

func _bind_instant_power_tooltip(label: Control, player_id: int, preview_power: int = 0) -> void:
	if label == null:
		return
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.set_meta("instant_power_target_id", player_id)
	# 预估增量每次刷新都会变（待确认的牌在增减），所以每次都写，不跟着绑定走
	label.set_meta("instant_power_preview", preview_power)
	if label.has_meta("instant_power_bound"):
		return
	label.set_meta("instant_power_bound", true)
	label.mouse_entered.connect(func():
		var pid: int = int(label.get_meta("instant_power_target_id", -1))
		if pid < 0 or !GameData.player_data_library.has(pid):
			return
		var panel := _ensure_power_tooltip_panel()
		# 本地预览与资源栏共用卡牌上下文；其他玩家只展示已提交状态。
		var preview_cards: Array = _regular_play_pending_cards if pid == _local_player_id else []
		var preview_hidden: Array = _regular_play_pending_hidden if pid == _local_player_id else []
		var pending_power: int = _pending_regular_power() if pid == _local_player_id else 0
		var lines := GetPlayerTotalPower.breakdown_lines(pid, pending_power, preview_cards, preview_hidden)
		var desc_node := panel.get_node_or_null("VBox/Desc") as Label
		if desc_node:
			desc_node.text = "\n".join(lines) if not lines.is_empty() else "当前无威力"
		var vp := get_viewport_rect().size
		var rect := label.get_global_rect()
		var p_size := panel.get_combined_minimum_size()
		# 优先贴在标签上方，放不下改下方，X 居中并 clamp 在视口内
		var px: float = clampf(rect.position.x + (rect.size.x - p_size.x) * 0.5, 8.0, maxf(8.0, vp.x - p_size.x - 8.0))
		var py: float = rect.position.y - p_size.y - 6.0
		if py < 8.0:
			py = rect.end.y + 6.0
		py = clampf(py, 8.0, maxf(8.0, vp.y - p_size.y - 8.0))
		panel.position = Vector2(px, py)
		panel.visible = true
	)
	label.mouse_exited.connect(func():
		if _power_tooltip_panel != null and is_instance_valid(_power_tooltip_panel):
			_power_tooltip_panel.visible = false
	)


## 格式化单条对局日志为直观清晰的中文描述
func _format_game_log_line(e: Dictionary) -> String:
	var round_num: int = int(e.get("round", 0))
	var phase_name: String = str(e.get("phase", ""))
	var phase_zh: String = ""
	match phase_name:
		"prepare": phase_zh = "准备"
		"outpost": phase_zh = "前哨"
		"action": phase_zh = "行动"
		"battle": phase_zh = "战斗"
		"end": phase_zh = "结束"
		_: phase_zh = phase_name
	var tag: String = "[第%d回合" % round_num + ("·%s]" % phase_zh if phase_zh != "" else "]")
	var actor_id: int = int(e.get("actor", -1))
	var actor_name: String = _player_shown_name_by_id(actor_id) if actor_id >= 0 else ""
	var e_type: String = str(e.get("type", ""))
	var place: String = str(e.get("place", ""))
	match e_type:
		"deploy":
			return "%s %s 部署至【%s】" % [tag, actor_name, place]
		"move":
			return "%s %s 移动至【%s】" % [tag, actor_name, place]
		"command_spell_used":
			return "%s %s 使用令咒" % [tag, actor_name]
		"draw":
			# 抽到的具体牌属于隐藏信息；事实日志保留对象供规则查询，玩家战报只公布抽牌动作。
			return "%s %s 抽牌" % [tag, actor_name]
		"refill_hand":
			return "%s %s 补充手牌" % [tag, actor_name]
		"reshuffle_discard":
			return "%s %s 将弃牌洗入牌库" % [tag, actor_name]
		"magic_add", "magic_decrease", "score_add", "score_decrease":
			var resource_name: String = "魔力" if e_type.begins_with("magic") else "战果"
			var delta: int = int(e.get("data", {}).get("delta", 0))
			return "%s %s %s %+d" % [tag, actor_name, resource_name, delta]
		"eliminated":
			return "%s %s 被淘汰" % [tag, actor_name]
		"true_name_release":
			return "%s %s 解放真名" % [tag, actor_name]
		"true_name_hidden":
			return "%s %s 隐藏真名" % [tag, actor_name]
		"score_add", "score_decrease":
			var score_data: Dictionary = e.get("data", {})
			var delta_score: int = int(score_data.get("delta", 0))
			var verb: String = "获得" if e_type == "score_add" else "失去"
			return "%s %s %s战果%s，当前%s" % [tag, actor_name, verb, abs(delta_score), int(score_data.get("now", 0))]
		"game_end":
			var winner_names: Array[String] = []
			for winner_id in e.get("data", {}).get("winners", []):
				winner_names.append(_player_shown_name_by_id(int(winner_id)))
			return "%s 对局结束：圣杯溢出，全员判负" % tag if winner_names.is_empty() else "%s 对局结束，胜者：%s" % [tag, "、".join(winner_names)]
		"play":
			var played = e.get("object")
			var card_name: String = _object_shown_name(played) if played != null else str(e.get("data", {}).get("card_name", ""))
			return "%s %s 打出%s%s" % [tag, actor_name, ("【%s】" % card_name) if card_name != "" else "牌", " · 暗置" if bool(e.get("data", {}).get("concealed", false)) else ""]
		"regular_play":
			return "%s %s 完成常规出牌，打出%s" % [tag, actor_name, str(e.get("data", {}).get("count", 0))]
		"effect":
			var data: Dictionary = e.get("data", {})
			var shown_effect: String = str(data.get("shown_effect", ""))
			if shown_effect == "" or not bool(data.get("applied", false)):
				return ""
			var source_name: String = str(data.get("source_name", ""))
			var points: Array = data.get("trigger_time_points", [])
			var shown_points: Array[String] = []
			for point in points:
				var shown_point: String = str(TimePoints.shown_time_points.get(str(point), ""))
				if shown_point != "" and not shown_points.has(shown_point):
					shown_points.append(shown_point)
			var when: String = " · " + "、".join(shown_points) if not shown_points.is_empty() else ""
			var source_text: String = "【%s】" % source_name if source_name != "" else ""
			return "%s %s%s发动%s：%s" % [tag, actor_name, when, source_text if source_text != "" else "效果", shown_effect]
		"option_used":
			var option_text: String = str(e.get("data", {}).get("option_name", ""))
			return "%s %s 选择【%s】" % [tag, actor_name, option_text] if option_text != "" else ""
		"time_point":
			return ""
		"battle":
			return "%s 【%s】完成战斗结算" % [tag, place]
		_:
			return ""

func _show_battle_report(res: Dictionary, show_all_logs: bool = false) -> void:
	if battle_report_modal == null:
		return
	var title_lbl := battle_report_modal.get_node_or_null("Box/VBox/Header/Title") as Label
	if title_lbl:
		title_lbl.text = "📜 对局战报与日志" if show_all_logs else "🏆 战斗结算战报"
	var list := battle_report_modal.get_node_or_null("Box/VBox/ReportScroll/ReportList") as VBoxContainer
	if list == null:
		return
	for c in list.get_children():
		_free_runtime_child(c)
	
	var details: Dictionary = res.get("details_by_area", {})
	if not details.is_empty():
		for area_name in details.keys():
			list.add_child(_build_battle_report_area_row(str(area_name), details[area_name]))
	var draws: Array = res.get("draw_areas", [])
	for area_name in draws:
		if details.has(area_name):
			continue
		var draw_lbl := Label.new()
		draw_lbl.text = "【%s】无人交战或全员败北，战区战果保留" % area_name
		draw_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
		draw_lbl.add_theme_font_size_override("font_size", 12)
		list.add_child(draw_lbl)

	# 综合日志展示：玩家主动点击右侧战报按钮时，完整拉取整局历史日志
	if show_all_logs or details.is_empty():
		var sec_title := Label.new()
		sec_title.text = "══ 对局历史日志 ══"
		sec_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35, 1.0))
		sec_title.add_theme_font_size_override("font_size", 13)
		list.add_child(sec_title)
		var logs: Array = GameLog.query({}, null, -1)
		if logs.is_empty():
			var empty_lbl := Label.new()
			empty_lbl.text = "暂无对局日志记录"
			empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
			empty_lbl.add_theme_font_size_override("font_size", 12)
			list.add_child(empty_lbl)
		else:
			# 最新的日志排在最前面
			for i in range(logs.size() - 1, -1, -1):
				var log_entry = logs[i]
				if log_entry is Dictionary:
					var l_text := _format_game_log_line(log_entry)
					if l_text == "":
						continue
					var row := Label.new()
					row.text = l_text
					row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					row.add_theme_font_size_override("font_size", 12)
					row.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
					list.add_child(row)
	
	# 战报行是每次动态新建的，补齐拖动穿透，保证面板空白处仍可拖动
	_make_children_passive(battle_report_modal)
	var backdrop := _ensure_battle_report_backdrop()
	backdrop.visible = true
	# 面板自身必须挡住点击；按钮和滚动区恢复可命中，避免"点不到战报"
	_block_panel_clicks(battle_report_modal)
	var close_button := battle_report_modal.get_node_or_null("Box/VBox/BtnCloseReport") as Button
	if close_button:
		close_button.mouse_filter = Control.MOUSE_FILTER_STOP
		close_button.visible = true
	_enable_modal_drag(battle_report_modal)
	battle_report_modal.visible = true
	battle_report_modal.z_index = max(battle_report_modal.z_index, MODAL_Z_THRESHOLD + 20)
	_reorder_child_by_z(backdrop)
	_reorder_child_by_z(battle_report_modal)
	if not show_all_logs:
		_play_battle_report_reveal(list)


## 战报的分步展开动画：每一行依次淡入 + 轻微上移。
## 行的内容已经填好，这里只做呈现节奏；动画期间不阻塞交互，
## 玩家可以直接拖动或关闭弹窗（跳过等待）
func _play_battle_report_reveal(list: VBoxContainer) -> void:
	if list == null:
		return
	# 上一次的展开动画要先停掉，否则快速连开两次战报会两套动画互相打断，
	# 留下 modulate 没恢复的半透明行
	if _battle_report_tween != null and _battle_report_tween.is_valid():
		_battle_report_tween.kill()
	var rows: Array = []
	for child in list.get_children():
		if child is Control:
			rows.append(child)
	if rows.is_empty():
		return
	_battle_report_tween = create_tween()
	for i in range(rows.size()):
		var row := rows[i] as Control
		row.modulate.a = 0.0
		_battle_report_tween.tween_property(row, "modulate:a", 1.0, BATTLE_REPORT_STEP) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

## -------------------------------------------------------------
## 通用只读卡牌浏览面板
## 任何"给我看看这一堆卡"的需求都用它：自己的弃牌堆、事件牌与局势牌弃牌区、
## 历史局势/事件牌。它只展示，不接任何提交流程——效果挑牌仍走 _show_card_select_panel，
## 两者混用会让"查看"意外提交效果选择
## -------------------------------------------------------------
func _ensure_card_browser_panel() -> Control:
	if _card_browser_panel != null and is_instance_valid(_card_browser_panel):
		return _card_browser_panel
	# 面板骨架在场景里（Modal_CardBrowser），脚本只接线：
	# 尺寸、配色、层级都在编辑器里可视化调整，不在代码里拼样式
	var panel := get_node_or_null("Modal_CardBrowser") as Control
	if panel == null:
		return null
	_block_panel_clicks(panel)
	_enable_modal_drag(panel)
	var btn_close := panel.get_node_or_null("Box/Buttons/BtnCloseBrowser") as Button
	if btn_close != null and not btn_close.has_meta("browser_close_bound"):
		btn_close.set_meta("browser_close_bound", true)
		btn_close.pressed.connect(func(): panel.visible = false)
	_card_browser_panel = panel
	return panel


## 展示一组卡。cards 为空时也照样打开并说明是空的——
## 静默不响应会让玩家以为点击没生效
func _show_card_browser(title_text: String, cards: Array) -> void:
	var panel := _ensure_card_browser_panel()
	if panel == null:
		return
	var vp := get_viewport_rect().size
	panel.position = Vector2(maxf(0.0, (vp.x - 860.0) * 0.5), vp.y * 0.18)
	var title := panel.get_node_or_null("Box/Title") as Label
	if title:
		title.text = "%s ×%d" % [title_text, cards.size()]
	var row := panel.get_node_or_null("Box/CardScroll/CardRow") as HBoxContainer
	if row == null:
		return
	for child in row.get_children():
		_free_runtime_child(child)
	if cards.is_empty():
		var empty := Label.new()
		empty.text = "这里还没有卡"
		empty.add_theme_color_override("font_color", Color(0.7, 0.74, 0.8))
		row.add_child(empty)
	else:
		# 同名卡合并 + 数量角标：弃牌堆里重复的牌很多，逐张铺会撑爆一行
		for group in _group_repeated_cards(cards):
			var slot := TextureRect.new()
			slot.custom_minimum_size = Vector2(146, 200)
			slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			slot.mouse_filter = Control.MOUSE_FILTER_STOP
			# owned=true：这些都是可以给观看者看的牌（自己的弃牌、已公开过的事件/局势牌）
			_render_card_face(slot, group["card"], true)
			row.add_child(slot)
			_set_slot_count_badge(slot, int(group["count"]))
	panel.visible = true
	move_child(panel, get_child_count() - 1)


## 一个战场的结算明细行：战场结论 + 每名参战者的威力构成 + 战果去向。
## 所有数值都取自 BattleResolver 写好的结算结果，界面不重算——
## 否则界面显示的威力与实际结算口径会分裂（本项目已因此出过"12 打不赢 10"的误报）
func _build_battle_report_area_row(area_name: String, detail: Dictionary) -> Control:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.12, 0.2, 0.85)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)

	var winners: Array = detail.get("winners", [])
	var needs_win: bool = bool(detail.get("needs_win", true))
	var title := Label.new()
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	if not needs_win:
		# 侦察这类不比威力的战区：所有在场者一同获得战果
		title.text = "【%s】无需战斗，在场者共同获得战果" % area_name
		title.add_theme_color_override("font_color", Color(0.45, 0.9, 1.0))
	elif winners.is_empty():
		title.text = "【%s】无人可获胜，战区战果保留" % area_name
		title.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	elif bool(detail.get("is_draw", false)):
		# 平局要写清是谁和谁平局，只写"平局"玩家无法核对
		title.text = "【%s】平局：%s 同为最高威力 %d，战果平分" % [
			area_name, _player_names_text(winners), int(detail.get("highest_power", 0))]
		title.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	else:
		title.text = "【%s】胜者：%s，最高威力 %d" % [
			area_name, _player_names_text(winners), int(detail.get("highest_power", 0))]
		title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	box.add_child(title)

	# 每人的威力构成：出牌威力 + 合计威力加成 + 地利 = 比较用的总威力
	var powers: Dictionary = detail.get("powers", {})
	var effective: Array = detail.get("effective_players", [])
	for pid in detail.get("players", []):
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_theme_font_size_override("font_size", 12)
		var pname: String = _player_shown_name_by_id(int(pid))
		if powers.has(pid):
			var p: Dictionary = powers[pid]
			# 场上牌加成（协同、占领高地等）单列一项：不列的话各项加起来对不上总数，
			# 玩家会以为战报算错了
			line.text = "　%s 威力 %d ＝ 出牌 %d ＋ 加成 %d ＋ 场上牌 %d ＋ 地利 %d" % [
				pname, int(p.get("total", 0)), int(p.get("power", 0)),
				int(p.get("bonus", 0)), int(p.get("board", 0)),
				int(p.get("location_benefit", 0))]
			line.add_theme_color_override("font_color",
				Color(1.0, 0.9, 0.5) if winners.has(pid) else Color(0.85, 0.88, 0.95))
		elif not effective.has(pid):
			# 被排除出胜负判定（如【败北】）：既不能获胜也不阻止他人获胜
			line.text = "　%s 不参与胜负判定" % pname
			line.add_theme_color_override("font_color", Color(0.7, 0.6, 0.6))
		else:
			line.text = "　%s 未参与威力比较" % pname
			line.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
		box.add_child(line)

	# 战果去向：事件牌战果 + 竞争战果 = 总战果，再写每人实得
	var total_score: int = int(detail.get("total_score", 0))
	var score_line := Label.new()
	score_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	score_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_line.add_theme_font_size_override("font_size", 12)
	score_line.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	var gained: Dictionary = detail.get("score_gained", {})
	var gained_parts: Array[String] = []
	for pid in gained.keys():
		gained_parts.append("%s %+d" % [_player_shown_name_by_id(int(pid)), int(gained[pid])])
	var source_text: String = "事件牌 %d ＋ 竞争 %d ＝ %d" % [
		int(detail.get("event_score", 0)), int(detail.get("competition_score", 0)), total_score]
	if gained_parts.is_empty():
		score_line.text = "　战果 %s，无人获得" % source_text
	else:
		score_line.text = "　战果 %s；" % source_text + "、".join(gained_parts)
	box.add_child(score_line)
	row.add_child(box)
	return row


## 一组玩家的示人名字，用顿号连接（平局双方、胜者名单共用）
func _player_names_text(ids: Array) -> String:
	var parts: Array[String] = []
	for id in ids:
		parts.append(_player_shown_name_by_id(int(id)))
	return "、".join(parts)


## 按玩家 id 取示人名字：走对象自己的显示名接口，不直接读 _shown_name
## （_shown_name 为空时该接口会回退内部名，直接读字段会显示空白）
func _player_shown_name_by_id(player_id: int) -> String:
	if not GameData.player_data_library.has(player_id):
		return "玩家 %d" % player_id
	var master = (GameDataManager.get_player_data(player_id) as Dictionary).get("master")
	var shown: String = _object_shown_name(master)
	return shown if shown != "" else ("玩家 %d" % player_id)


func _on_close_battle_report() -> void:
	if battle_report_modal:
		battle_report_modal.visible = false
	if _battle_report_backdrop != null and is_instance_valid(_battle_report_backdrop):
		_battle_report_backdrop.visible = false
	refresh_all_ui()
