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

var _selected_opponent: Control = null
var _selected_opponent_id: String = ""
var _local_player_id: int = 0
var _ai_acting: bool = false
## 正在替哪位玩家跑 AI，用于异常兜底复位
var _ai_acting_for_id: int = -1
## AI 步进冷却计时，避免一帧把整轮对手跑完
var _ai_cooldown: float = 0.0
var _current_waiting_effect: BaseEffect = null
## 正在等待玩家挑牌的效果与已挑中的牌（与"等发动/放弃"是两条并列的玩家输入）
var _card_select_effect: BaseEffect = null
var _card_select_picked: Array = []
var _card_select_cards: Array = []
var _card_select_panel: Control = null
var _hovered_event_card: Control = null
## 说明面板当前正在显示哪张卡（区别于会随鼠标悬浮实时变化的 _hovered_event_card），
## 用于在 _input 判断"这一击是不是点在面板来源自身上"，避免右键同卡关闭又被误判成切换重开
var _desc_panel_source: Control = null
var _hand_is_expanded: bool = false
var _hand_tween: Tween = null
var _last_hand_hover_state: bool = false

@onready var opponent_drawer: Control = get_node_or_null(opponent_drawer_path)
@onready var leaderboard_drawer: Control = get_node_or_null(leaderboard_drawer_path)
@onready var hand_tray: Control = get_node_or_null(hand_tray_path)
@onready var effect_modal: Control = get_node_or_null(effect_modal_path)
@onready var event_zoom_preview: Control = get_node_or_null(event_zoom_preview_path)
@onready var event_desc_panel: Control = get_node_or_null("EventCardDescPanel")
@onready var battle_report_modal: Control = get_node_or_null("Modal_BattleReport")
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
#未公开(暗置)遮罩：半透明灰 + 闭眼图标
const CONCEAL_COLOR := Color(0.32, 0.32, 0.36, 0.55)
#尚未激活的卡(如未激活buff的御主物品卡)遮罩：半透明深红。
#只表达"这张卡还没生效"，不带图标——和"未公开"是两回事，可以同时盖
const INACTIVE_COLOR := Color(0.45, 0.06, 0.10, 0.45)
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
	if event_zoom_preview:
		event_zoom_preview.visible = false
	if event_desc_panel:
		event_desc_panel.visible = false
	
	# 弹窗可拖动，便于查看被弹窗遮挡的战场
	for modal in [tactical_confirm_modal, effect_modal, battle_report_modal]:
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
	
	# 如果游戏引擎尚未启动，则启动 7 位玩家完整对局并分发初始手牌
	if !GameStart._started:
		GameStart.game_start([0, 1, 2, 3, 4, 5, 6])
		for id in GameDataManager.get_active_player_ids():
			for _k in range(3):
				DrawCardFromPlDeckToHand.new().exec(BaseNumber.new(0), id)
		# 准备阶段自动流转，直接进入前哨部署阶段 (outpost)
		if GameProgress.get_current_phase().get("name", "") == "prepare":
			GameProgress.advance_phase()
	
	refresh_all_ui()

var _ui_refresh_accum: float = 0.0

func _process(delta: float) -> void:
	_update_hand_hover_from_mouse()
	_update_event_card_hover_check()
	_check_waiting_effects()
	_check_waiting_card_selection()
	_check_and_step_ai(delta)
	# 效果结算产生的提示消息：取走并展示。消息由operation产生，展示形态是界面的事
	_flush_effect_messages()
	# 战报：战斗阶段的结果一变就弹一次（此前该函数没有任何调用点，战报永远不显示）
	_check_battle_report()
	# 轻量节流刷新：顶栏敌人魔力/总威力/战果与行动者提示实时跟随
	_ui_refresh_accum += delta
	if _ui_refresh_accum >= 0.5:
		_ui_refresh_accum = 0.0
		_refresh_opponent_resource_icons()
		_refresh_clickable_strength()

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
## 御主/从者可在自身数据的 specials.COMMAND_SPELLS 里声明专属令咒
## （写 data/command_spells 下的 card_name，支持单个字符串或按顺序取的数组），
## 因此特殊角色不必改动界面逻辑即可使用自己的令咒。
func _resolve_player_command_spell(pl_data: Dictionary) -> BaseCard:
	for holder in [pl_data.get("master"), pl_data.get("servant")]:
		var declared := _declared_command_spell(holder)
		if declared != null:
			return declared
	return LoadCommandSpell.get_normal()

## 从御主/从者声明的令咒名解析出令咒对象，未声明返回 null
func _declared_command_spell(holder) -> BaseCard:
	if holder == null:
		return null
	var specials = holder.get("_specials")
	if not (specials is Dictionary):
		return null
	var declared = specials.get("COMMAND_SPELLS", null)
	if declared is String:
		return LoadCommandSpell.get_command_spell(declared)
	if declared is Array and declared.size() > 0:
		return LoadCommandSpell.get_command_spell(str(declared[0]))
	return null

## 绑定底栏静态卡牌、头像与局势牌的悬浮说明（数据取自当前玩家与当前局势）
func _refresh_static_card_infos(pl_data: Dictionary) -> void:
	var master = pl_data.get("master")
	var servant = pl_data.get("servant")
	var podium := "Bottom_PlayerDock/TacticalDeskLayout/Section_CommandPodium/VBox/UpperRow/"
	# 卡图按数据填，不用场景预置图：卡位只当尺寸模板，取不到图就保持原样
	_fill_card_slot(get_node_or_null(podium + "MasterCardBox/Tex"), master, "_master_card_img")
	_fill_card_slot(get_node_or_null(podium + "ServantCardBox/Tex"), servant, "_servant_card_img")
	# 令咒卡：卡图优先用该御主自己的令咒图案，说明取令咒数据
	var cs_node := get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_CommandPodium/VBox/LowerCommandSpellRow/Tex")
	var cs := _resolve_player_command_spell(pl_data)
	if cs_node and cs != null:
		var cs_num: int = (pl_data.get("command_spell_count", BaseNumber.new(3)) as BaseNumber).number
		# 卡图优先该御主自己的令咒图案；御主没有图时回退令咒卡自带的默认图
		var cs_img: String = ""
		if master and str(master.get("_command_spell_img")) != "" and LoadHelper.texture_exists(str(master.get("_command_spell_img"))):
			cs_img = str(master.get("_command_spell_img"))
		if cs_img != "":
			cs_node.texture = LoadHelper.load_texture(cs_img)
			cs_node.set_meta("zoom_img", cs_img)
			_bind_zoom_info(cs_node, cs)
		else:
			_fill_card_slot(cs_node, cs)
		cs_node.set_meta("zoom_desc", "剩余 %d\n%s" % [cs_num, _build_card_desc(cs)])
		var cs_info := get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_CommandPodium/VBox/LowerCommandSpellRow/InfoV")
		if cs_info:
			var cs_lbl := cs_info.get_node_or_null("Lbl") as Label
			if cs_lbl:
				# 数量用 ×N 表达，不用括号补充
				cs_lbl.text = _object_shown_name(cs) + ("　×%d" % cs_num if cs_num > 1 else "")
			var cs_desc_lbl := cs_info.get_node_or_null("Desc") as Label
			if cs_desc_lbl:
				# 效果自身带选项时列出各选项文案，否则列效果名——
				# 令咒是"一条效果+三选项"，只列效果名会漏掉玩家真正要选的内容
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
		servant_lbl.text = ("从者卡 · %s" % cls) if cls != "" else "从者卡"

	# 出牌区提示：常规出牌上限与当前席位地利，两段都从数据读，
	# 不写死"已计入深山町地利+3"
	var zone_tip := get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_PlayBattleZone/VBox/ZoneTip") as Label
	if zone_tip:
		var limit: int = (pl_data.get("play_limit", BaseNumber.new(0)) as BaseNumber).number
		var tip := "常规出牌 %d" % limit
		if area != null:
			var benefit: int = (loc._benefit as BaseNumber).number
			tip += " · %s 地利 %d" % [area_name, benefit]
		zone_tip.text = tip

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
		if curr_id == _local_player_id:
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

	# 刷新魔力长条与战果
	var magic_num: int = (pl_data["magic"] as BaseNumber).number
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

	# 刷新前线打出区卡牌与威力
	var total_pow: int = (pl_data["power"] as BaseNumber).number + (pl_data["total_power_bonus"] as BaseNumber).number
	if total_power_label:
		total_power_label.text = "当前合计威力: %d" % total_pow
	
	_refresh_hand_cards(pl_data)
	_refresh_played_cards(pl_data)
	_refresh_battlefield_specific_slots()
	_refresh_clickable_skills(pl_data)
	_refresh_opponent_resource_icons()
	_refresh_leaderboard()
	_refresh_battlefield_events()
	_refresh_static_card_infos(pl_data)
	_refresh_movement_arrows()
	_refresh_dynamic_labels(pl_data)
	# 数据刷新后可能有新卡入树，统一重扫一次放大目标与遮挡层
	_register_all_hover_zoom()
	_apply_clickable_indicators()

## 将顶部对手资源文字替换为统一的图标组件
func _refresh_opponent_resource_icons() -> void:
	var opponent_names := ["P2", "P3", "P4", "P5", "P6", "P7"]
	for node_name in opponent_names:
		var bot_id: int = _opponent_node_to_id(node_name)
		if bot_id < 0:
			continue
		var bot_pl: Dictionary = GameDataManager.get_player_data(bot_id) if GameDataManager else {}
		var bot_master = bot_pl.get("master") if bot_pl else null
		var av := get_node_or_null("TopPanel_AllPlayers/AllPlayersOrderScroll/OrderHBox/%s/HBox/Avatar" % node_name) as TextureRect
		if av:
			_bind_zoom_info(av, bot_master, "_header_img")
		# 名字标签与头像贴图都按真实数据刷新——场景预置的是草案占位，与加载序无关
		var name_lbl := get_node_or_null("TopPanel_AllPlayers/AllPlayersOrderScroll/OrderHBox/%s/HBox/Info/Name" % node_name) as Label
		if name_lbl and bot_pl:
			var shown: String = _object_shown_name(bot_master) if bot_master else "玩家 %d" % bot_id
			# 名次前缀按当前真实顺位生成：order 会被 ChangePlOrder 改动，不再恒等于 id+1
			name_lbl.text = "%s %s ▼" % [_ordinal_label(EffectManager.get_player_order_index(bot_id) + 1), shown]
		if av and bot_master:
			_apply_header_texture(av, bot_master)
		var info_path := "TopPanel_AllPlayers/AllPlayersOrderScroll/OrderHBox/%s/HBox/Info" % node_name
		var info := get_node_or_null(info_path)
		if info == null:
			continue
		var old_stats := info.get_node_or_null("Stats")
		if old_stats:
			_free_runtime_child(old_stats)
		
		# 读取真实数据
		var pl_data: Dictionary = GameDataManager.get_player_data(bot_id) if GameDataManager else {}
		var magic_num: int = pl_data.get("magic", BaseNumber.new(0)).number if pl_data else 0
		var score_num: int = pl_data.get("score", BaseNumber.new(0)).number if pl_data else 0
		var spell_num: int = pl_data.get("command_spell_count", BaseNumber.new(3)).number if pl_data else 3
		
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
		
		# 动态添加真实以太魔力、总威力、金色战果图标
		var power_num: int = (pl_data.get("power", BaseNumber.new(0)) as BaseNumber).number \
			+ (pl_data.get("total_power_bonus", BaseNumber.new(0)) as BaseNumber).number
		# 魔力按"当前/上限"显示，上限取自数据而非写死 12
		_add_resource_icon(resources, mana_icon_texture, "%d/%d" % [magic_num, (GameData.magic_limit as BaseNumber).number], Color(0.45, 0.9, 1.0))
		_add_resource_icon(resources, swords_icon_texture, "%d" % power_num, Color(0.85, 0.92, 1.0))
		_add_resource_icon(resources, grail_icon_texture, "%d" % score_num, Color(1.0, 0.85, 0.35))
		var spell_label := Label.new()
		spell_label.text = "令咒 ×%d" % spell_num
		spell_label.add_theme_font_size_override("font_size", 10)
		spell_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.5))
		resources.add_child(spell_label)
		# 当前行动者头像挂青色呼吸描边，作为敌人行动的可视提示
		if av:
			var acting: bool = GameProgress.current_player_id == bot_id
			av.set_meta("actor_avatar", true)
			av.set_meta("is_acting", acting)
			av.set_meta("clickable", true)
			av.set_meta("clickable_color", Color(0.4, 0.95, 1.0, 1.0))
			if acting:
				av.z_index = 5
			else:
				av.z_index = 0

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

func _add_resource_icon(parent: HBoxContainer, icon: Texture2D, value: String, color: Color) -> void:
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

## 与 PlayAttack 完全一致的可打出判据：阶段/回合/上限/费用/【败北】/已激活，
## 不满足任何一条时 UI 不给提示。规则数字全部读数据，不写死
func _can_play_attack_now(card: BaseAttack, pl_data: Dictionary) -> bool:
	if card == null or not (pl_data is Dictionary) or pl_data.is_empty():
		return false
	if pl_data.get("is_out", false):
		return false
	if PlayerBuffsHaveEffect.new().exec(CannotPlayCardsEffect.EFFECT_NAME, _local_player_id):
		return false
	if GameProgress.get_current_phase().get("name", "") != "action":
		return false
	if GameProgress.current_player_id != _local_player_id:
		return false
	if card._is_activating:
		return false
	var play_limit = pl_data.get("play_limit", BaseNumber.new(2)) as BaseNumber
	var played_this_turn: Array = pl_data.get("played_attacks_this_turn", [])
	if played_this_turn.size() >= play_limit.number:
		return false
	var final_cost: int = card._cost.number \
		- (pl_data.get("attack_cost_discount", BaseNumber.new(0)) as BaseNumber).number \
		- card._cost_discount.number
	if final_cost < 0:
		final_cost = 0
	if not pl_data.get("is_magic_immune", false):
		if (pl_data.get("magic", BaseNumber.new(0)) as BaseNumber).number < final_cost:
			return false
	return true

## 刷新手牌列表：能打出的卡亮金色呼吸描边，不能打的恢复常亮描边。
## 卡位复用场景预置的模板（不足克隆、多余隐藏），不再每次删除重建：
## 删除重建会让同一帧内新旧卡位并存，也会把场景里的卡位尺寸模板一起销毁
func _refresh_hand_cards(pl_data: Dictionary) -> void:
	if hand_cards_row == null:
		return
	var hand_cards: Array = pl_data.get("hand_cards", [])
	var slots: Array = _ensure_slot_nodes(hand_cards_row, hand_cards.size())
	for i in range(slots.size()):
		var slot := slots[i] as Control
		var card = hand_cards[i] if i < hand_cards.size() else null
		if not (card is BaseAttack):
			slot.visible = false
			continue
		slot.visible = true
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		var can_play: bool = _can_play_attack_now(card, pl_data)
		slot.set_meta("clickable", can_play)
		slot.set_meta("clickable_color", Color(1.0, 0.85, 0.3, 1.0))
		slot.set_meta("playable_hint", can_play)
		# 点击回调只在首次接线一次，之后靠 metadata 现取当前卡：
		# 每次刷新都 connect(func.bind(card)) 的话，bind 过的 Callable 与原来不是同一个，
		# is_connected 永远为假、旧连接不断，点一下会同时打出好几张旧卡
		slot.set_meta("click_hand_card", card)
		if not slot.has_meta("hand_click_bound"):
			slot.set_meta("hand_click_bound", true)
			slot.gui_input.connect(_on_hand_slot_gui_input.bind(slot))
		# 卡面统一走 _render_card_face：暗置的手牌同样盖灰遮罩+闭眼图标，
		# 放大说明也由它一起管，不再各处自己赋一次贴图（否则"暗置怎么表现"会分裂成多套）
		_render_card_face(slot, card, true)

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
	var played: Array = pl_data.get("played_cards", [])
	# 场上同名的牌同样合并显示 + 数量角标
	var groups: Array = _group_repeated_cards(played)
	var slots: Array = _ensure_slot_nodes(played_cards_row, groups.size())
	for i in range(slots.size()):
		var slot := slots[i] as Control
		var group = groups[i] if i < groups.size() else null
		if group == null:
			slot.visible = false
			_set_slot_count_badge(slot, 0)
			continue
		slot.visible = true
		var card = group["card"]
		for sub in _card_texture_nodes(slot):
			_render_card_face(sub, card, true)
		var power_lbl := slot.get_node_or_null("Lbl") as Label
		if power_lbl:
			power_lbl.text = "威力: %d" % card._power.number
		_set_slot_count_badge(slot, int(group["count"]))

## 刷新四大战区明确点位 (魔力充能位 / 地利位 / 侦察席)
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

## 局势牌按当前激活对象填卡图与说明，场景预置图只当空位模板
func _refresh_situation_card() -> void:
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
func _render_card_face(node: TextureRect, obj, owned: bool, fallback_type: String = "skill") -> void:
	if node == null or obj == null:
		return
	var concealed: bool = obj is BaseCard and bool(obj.get("_is_concealed"))
	# 未觉醒的升华技：玩家尚未获得这张牌，连拥有者也不给看卡面，一律显示升华技卡背。
	# 与普通暗置牌不同——普通暗置牌是"已有但对别人隐藏"，自己看卡面+灰遮罩即可
	if obj is BaseSkill and not bool(obj.get("_is_awakened")):
		var up_back: String = str(obj.get("_card_back_img")) if obj.get("_card_back_img") != null else ""
		if up_back == "" or not LoadHelper.texture_exists(up_back):
			up_back = LoadHelper.resolve_card_back("", "", "upgrade_skill")
		node.texture = LoadHelper.load_texture(up_back)
		_set_conceal_overlay(node, false)
		_set_inactive_overlay(node, false)
		node.set_meta("zoom_disabled", true)
		node.remove_meta("zoom_title")
		node.remove_meta("zoom_desc")
		node.remove_meta("zoom_img")
		return
	_set_conceal_overlay(node, concealed and owned)
	if concealed and not owned:
		var back: String = str(obj.get("_card_back_img")) if obj.get("_card_back_img") != null else ""
		if back == "" or not LoadHelper.texture_exists(back):
			back = LoadHelper.resolve_card_back("", "", fallback_type)
		node.texture = LoadHelper.load_texture(back)
		_set_inactive_overlay(node, false)
		node.set_meta("zoom_disabled", true)
		node.remove_meta("zoom_title")
		node.remove_meta("zoom_desc")
		node.remove_meta("zoom_img")
		return
	var img = obj.get("_card_img")
	if img != null and str(img) != "" and LoadHelper.texture_exists(str(img)):
		node.texture = LoadHelper.load_texture(str(img))
	#卡面照给，但关联的buff尚未激活时盖一层半透明深红：一眼看出这张卡还没生效
	_set_inactive_overlay(node, _is_card_inactive(obj))
	node.set_meta("zoom_disabled", false)
	_bind_zoom_info(node, obj)

## 未公开遮罩：半透明灰 + 闭眼图标。语义是"这张牌已有，但对观看者隐藏"
func _set_conceal_overlay(node: Control, show_overlay: bool) -> void:
	_sync_overlay(node, show_overlay, "ConcealOverlay", CONCEAL_COLOR, CONCEAL_ICON)

## 未激活遮罩：半透明深红。语义是"这张卡还没生效"（御主物品卡对应的buff尚未激活）。
## 与未公开遮罩用不同节点名，两者互不覆盖，可以同时盖在一张卡上
func _set_inactive_overlay(node: Control, show_overlay: bool) -> void:
	_sync_overlay(node, show_overlay, "InactiveOverlay", INACTIVE_COLOR)

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
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
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
		row.add_child(entry)

## 采集一个玩家"未加入牌库"的全部卡：从者技能牌、御主技能牌之外，还包括御主自带的
## 专属技能/攻击牌(如阴炁弹)、升华技、附带物(如宝石卡)。本地信息栏与对手抽屉共用同一份
## 采集逻辑，保证呈现口径一致；需要加入牌库的攻击牌由效果说明并搬运，牌库内的不在此重复展示
func _collect_uncataloged_cards(pl_data: Dictionary) -> Array:
	var all_cards: Array = pl_data.get("servant_skills", []) + pl_data.get("master_skills", [])
	var master = pl_data.get("master")
	if master != null:
		var sp = master.get("_specials")
		if sp is Dictionary:
			all_cards += sp.get("SKILLS", [])
			all_cards += sp.get("ATTACKS", [])
		var ot = master.get("_other_things")
		if ot is Array:
			all_cards += ot
		#升华技最后加，让它固定排在最右边：它是觉醒之后才启用的牌，
		#跟常规牌混在一起摆会被当成"现在就能用"
		var up = master.get("_upgrade_skill")
		if up is Array:
			all_cards += up
	return all_cards

## 刷新可点击发动的技能牌：按数据填充卡位（卡图/名字/点击/悬浮说明全部取自数据），
## 卡位位置模板沿用场景预置，数量不足时复用模板动态补位，多余卡位隐藏。
## 顺带刷新自己的状态专区（与对手抽屉共用同一份 buff 渲染逻辑）
func _refresh_clickable_skills(pl_data: Dictionary) -> void:
	if skills_scroll_h == null:
		return
	# 自己的卡：未公开的也显示卡面，只盖灰遮罩+闭眼图标（owned 默认 true）
	_fill_card_row_from_list(skills_scroll_h, _collect_uncataloged_cards(pl_data), true)
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
	for child in row.get_children():
		if not (child is Control) or child is Separator:
			continue
		if child.has_meta("skill_slot_runtime"):
			_free_runtime_child(child)
		else:
			slots.append(child)
	if slots.is_empty():
		return slots
	while slots.size() < need:
		var extra_slot: Control = (slots[0] as Control).duplicate()
		extra_slot.set_meta("skill_slot_runtime", true)
		_clear_runtime_slot_metas(extra_slot)
		row.add_child(extra_slot)
		# 克隆出的卡位要落在分隔线之前：分隔线之后是场景预置的另一个分区，
		# 直接追加到行尾会让多出来的卡长进别的分区里
		var sep_idx := _first_separator_index(row)
		if sep_idx != -1:
			row.move_child(extra_slot, sep_idx)
		slots.append(extra_slot)
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
		var key: String = "%s|%s|%s|%s|%s" % [
			str(card.get("_name")),
			str(card.get("_card_img")),
			str(_number_text(card.get("_power"))),
			str(_number_text(card.get("_cost"))),
			_card_visual_state_key(card),
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
		badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		host.add_child(badge)
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	badge.text = "×%d" % count
	badge.visible = true


## 通用卡位行填充：给定一个容器和一组卡对象，按场景预置的卡位模板铺开，
## 数量不足时克隆模板补位，多余隐藏。clickable=false 用于对手抽屉等只展示不可发动的场景，
## owned=false 表示这是别人的卡（未公开只显示卡背）。
## 本地信息栏与对手抽屉共用同一套铺卡逻辑，暗置/明置由 _render_card_face 统一处理
func _fill_card_row_from_list(row: Control, cards: Array, clickable: bool, owned: bool = true) -> void:
	# 重复的牌合并成一个卡位、用角标显示数量：10 张宝石卡不必铺满整条信息栏
	var groups: Array = _group_repeated_cards(cards)
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
			_fill_display_slot(slot, card_obj, owned)
		_set_slot_count_badge(slot, int(group["count"]))
	# 分隔线本身不承载数据：只有它后面还有可见卡位时才显示，
	# 否则卡少了会留一条孤零零的分隔线
	_refresh_row_separators(row)

## 行内第一条分隔线的下标（没有返回 -1）。克隆卡位要插在它前面，保持分区语义
func _first_separator_index(row: Control) -> int:
	var children := row.get_children()
	for i in range(children.size()):
		if children[i] is Separator:
			return i
	return -1

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
	for key in ["zoom_bound", "skill_click_bound", "hand_click_bound", "click_skill", "click_hand_card", "playable_hint"]:
		if node.has_meta(key):
			node.remove_meta(key)
	for child in node.get_children():
		_clear_runtime_slot_metas(child)

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
func _fill_display_slot(slot: Control, obj, owned: bool = true) -> void:
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.set_meta("click_skill", null)
	var concealed: bool = obj is BaseCard and bool(obj.get("_is_concealed"))
	# 别人的暗置牌不暴露名字；自己的暗置牌名字照显（卡面都能看见，没有隐藏的意义）
	var shown: String = "" if (concealed and not owned) else _object_shown_name(obj)
	for sub in _card_texture_nodes(slot):
		sub.set_meta("clickable", false)
		_render_card_face(sub, obj, owned, _card_back_type_of(obj))
	for lbl in slot.find_children("*", "Label", true, false):
		if str(lbl.name) == COUNT_BADGE_NAME:
			continue
		lbl.text = shown
		lbl.visible = shown != ""

## 把一个技能数据填进卡位：卡图、名字标签、点击发动、悬浮说明。
## owned 决定未公开时的表现（同 _fill_display_slot）；别人的暗置牌不可点击发动
func _fill_skill_slot(slot: Control, skill: BaseSkill, clickable: bool = true, owned: bool = true) -> void:
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	var concealed: bool = bool(skill.get("_is_concealed"))
	var hidden_from_viewer: bool = concealed and not owned
	# 点击回调不绑定具体技能，改由卡位上的 metadata 现取，
	# 避免卡位复用后旧连接残留导致触发到上一次的技能
	slot.set_meta("click_skill", null if (hidden_from_viewer or not clickable) else skill)
	if not slot.has_meta("skill_click_bound"):
		slot.set_meta("skill_click_bound", true)
		slot.gui_input.connect(_on_skill_slot_clicked.bind(slot))
	var skill_name: String = "" if hidden_from_viewer else _object_shown_name(skill)
	for sub in _card_texture_nodes(slot):
		sub.set_meta("clickable", clickable and not hidden_from_viewer)
		if clickable and not hidden_from_viewer:
			sub.set_meta("clickable_color", Color(1.0, 0.85, 0.35, 1.0))
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
	if GameProgress.current_player_id != _local_player_id:
		return
	var skill = slot.get_meta("click_skill", null)
	if skill is BaseSkill:
		PlaySkill.new().exec(skill, _local_player_id)
		refresh_all_ui()


## -------------------------------------------------------------
## 2. 玩家交互：出牌、阶段推进、战区点击移动
## -------------------------------------------------------------
func _connect_player_actions() -> void:
	if btn_end_phase and not btn_end_phase.pressed.is_connected(_on_end_phase_pressed):
		btn_end_phase.pressed.connect(_on_end_phase_pressed)

func _on_hand_card_clicked(card: BaseAttack) -> void:
	if GameProgress.current_player_id != _local_player_id:
		return
	var success: bool = PlayAttack.new().exec(card, _local_player_id)
	if success:
		refresh_all_ui()

func _on_end_phase_pressed() -> void:
	if GameProgress.current_player_id != _local_player_id:
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
	var curr_area := _local_current_area(pl_data)
	if curr_area == null:
		return
	var current_idx: int = MapData.areas.find(curr_area)
	if current_idx == -1:
		return
	var step_diff: int = target_area_idx - current_idx
	
	# 规则：只能向右单向前进
	if step_diff <= 0:
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
		"target_area_name": target_area_name
	}
	
	var move_costs: Array[String] = []
	if total_cost > 0:
		move_costs.append("魔力 %d" % total_cost)
	_show_tactical_confirm(_attach_cost_line("移动至【%s】" % target_area_name, move_costs))

## 取走并展示效果产生的提示消息。
## 消息由 operation(show_message) 产生，怎么显示由界面决定——这里复用战术确认那套
## 纯提示弹窗(只有"知道了")。多条消息合并成一段显示，避免连续弹窗互相覆盖丢信息
func _flush_effect_messages() -> void:
	if _local_player_id < 0:
		return
	var msgs: Array = EffectManager.pop_messages(_local_player_id)
	if msgs.is_empty():
		return
	var texts: Array[String] = []
	for m in msgs:
		var s := str(m)
		if s != "":
			texts.append(s)
	if texts.is_empty():
		return
	_show_tactical_confirm("\n".join(texts), true)

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
	if tactical_confirm_modal:
		tactical_confirm_modal.visible = false
	
	var act_type: String = _pending_tactical_action.get("type", "")
	if act_type == "deploy":
		var target_loc = _pending_tactical_action.get("target_loc")
		if target_loc is BaseLocation:
			Deploy.new().exec(target_loc, _local_player_id)
			GameProgress.end_current_player_action()
	elif act_type == "move":
		var step: int = _pending_tactical_action.get("step_diff", 0)
		if step > 0:
			Move.new().exec(BaseNumber.new(step), _local_player_id)
	
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
	if bool(card.get_meta("zoom_disabled", false)):
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

## 顶栏顺位节点名 → 玩家 id（节点按 P1、P2… 编号命名，对应 id 0、1…）
func _opponent_node_to_id(node_name: String) -> int:
	var re := RegEx.new()
	# 顶栏节点按顺位编号命名(P1~P7)，后缀可有可无：只认编号，角色由数据决定，
	# 不能靠节点名猜角色(加载顺序变了节点名就会误导)
	re.compile("^P(\\d+)")
	var r := re.search(node_name)
	if r:
		return int(r.get_string(1)) - 1
	return -1

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
	if effs is Array:
		var es: Array[String] = []
		for e in effs:
			var en: String = _object_shown_name(e)
			if en != "":
				es.append(en)
		if es.size() > 0:
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
		if child is Button or child is ScrollContainer or child is LineEdit:
			continue
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_make_children_passive(child)

func _on_modal_drag_input(ev: InputEvent, panel: Control) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_dragging_modal = panel
			panel.z_index = max(panel.z_index, MODAL_Z_THRESHOLD + 40)
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
## 给控件叠加一层呼吸发光边框。
## 用独立叠加层而非修改控件材质：材质方案对 StyleBox 绘制的按钮会采到白色内置纹理导致控件变白。
func _apply_clickable_indicator(ctrl: Control, color: Color) -> void:
	if ctrl == null or ctrl.get_node_or_null("ClickableGlow") != null:
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
	ctrl.add_child(glow)
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	if not _clickable_nodes.has(ctrl):
		_clickable_nodes.append(ctrl)

## 可点击时显示呼吸边框，不可点击时收起，避免误导
func _set_clickable_active(ctrl: Control, active: bool) -> void:
	if ctrl == null:
		return
	var glow := ctrl.get_node_or_null("ClickableGlow") as Control
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
		var want := false
		if child is Button:
			want = true
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
		elif bool(ctrl.get_meta("playable_hint", false)):
			# 可打的手牌：只在真能打时呼吸（判据由 _can_play_attack_now 给出）
			_set_clickable_active(ctrl, true)
		elif ctrl.get_meta("actor_avatar", false):
			# 当前行动者头像：跟随行动者变化呼吸
			_set_clickable_active(ctrl, bool(ctrl.get_meta("is_acting", false)))
		elif ctrl is Button:
			_set_clickable_active(ctrl, true)
		else:
			_set_clickable_active(ctrl, my_turn)

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
	if GameProgress.current_player_id != _local_player_id:
		return "还没轮到你行动"
	if target_area_idx < 0 or target_area_idx >= MapData.areas.size():
		return "目标战区不存在"
	var phase_name := str(GameProgress.get_current_phase().get("name", ""))
	if phase_name == "outpost":
		var target_area: BaseMapArea = MapData.areas[target_area_idx]
		if _open_deploy_locations(target_area).is_empty():
			return "【%s】没有可用的部署席位" % target_area._area_name
		return ""
	if phase_name != "action":
		return "当前是%s，不能部署或移动" % _phase_shown_name(phase_name)
	var pl_data: Dictionary = GameDataManager.get_player_data(_local_player_id)
	var curr_area := _local_current_area(pl_data)
	if curr_area == null:
		return "你还没有部署到任何战区"
	var current_idx: int = MapData.areas.find(curr_area)
	if current_idx == -1:
		return "你当前的位置不在任何战区上"
	var step_diff: int = target_area_idx - current_idx
	if step_diff <= 0:
		return "移动只能沿单方向前进"
	if !_is_magic_enough_for_move(pl_data, _estimate_move_cost(pl_data, step_diff)):
		return "魔力不足，无法移动至【%s】" % MapData.areas[target_area_idx]._area_name
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
	# 抽屉展开时左键点击抽屉之外的区域：收起抽屉。顶栏对手头像格自己的开/关/切换逻辑
	# 走 _on_opponent_gui_input（在 GUI 分发阶段，晚于这里），这里只处理"点在别处"的收起，
	# 点在头像格上时让事件正常往下走，避免和头像自己的开/关/切换互相打架
	if opponent_drawer != null and opponent_drawer.visible \
			and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = (event as InputEventMouseButton).global_position
		if not opponent_drawer.get_global_rect().has_point(pos) and not _is_point_over_opponent_cards(pos):
			opponent_drawer.visible = false
			_selected_opponent = null
			_selected_opponent_id = ""

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
	if not EffectManager.is_waiting_for_choice():
		if effect_modal and effect_modal.visible and _current_waiting_effect != null:
			effect_modal.visible = false
			_current_waiting_effect = null
		return
	
	var pending: BaseEffect = EffectManager.get_pending_active_effect()
	if pending == null:
		return
	
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


## 临时测试用 AI 的挑牌：按来源顺序取够声明的最少张数；来源不够就放弃
## （提交空 = 放弃。此刻来源资源与用量都还没扣，放弃等于这个效果没发动）
func _resolve_bot_card_selection(pending: Dictionary) -> void:
	var eff: BaseEffect = pending.get("effect")
	if eff == null:
		return
	var cards: Array = pending.get("cards", [])
	var low: int = int(pending.get("min", 1))
	var picks: Array = []
	for card in cards:
		if picks.size() >= low:
			break
		picks.append(card)
	if picks.size() < low:
		picks = []
	EffectManager.submit_card_selection(eff, picks)
	refresh_all_ui()


## 选牌面板：结构与"效果决策弹窗"同源（标题 + 卡牌行 + 提示 + 两个按钮），
## 但它是本界面自己按需创建的——这种只为一个流程服务的浮层没必要写进场景文件
func _ensure_card_select_panel() -> Control:
	if _card_select_panel != null and is_instance_valid(_card_select_panel):
		return _card_select_panel
	var panel := PanelContainer.new()
	panel.name = "Modal_CardSelect"
	panel.z_index = MODAL_Z_THRESHOLD + 20
	panel.visible = false
	panel.custom_minimum_size = Vector2(820, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.12, 0.96)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.45, 0.6, 0.9, 0.9)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	var vbox := VBoxContainer.new()
	vbox.name = "Box"
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	var title := Label.new()
	title.name = "Title"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	vbox.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.name = "CardScroll"
	scroll.custom_minimum_size = Vector2(0, 250)
	vbox.add_child(scroll)
	var row := HBoxContainer.new()
	row.name = "CardRow"
	row.add_theme_constant_override("separation", 8)
	scroll.add_child(row)
	var hint := Label.new()
	hint.name = "Hint"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	vbox.add_child(hint)
	var buttons := HBoxContainer.new()
	buttons.name = "ButtonsRow"
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	vbox.add_child(buttons)
	var btn_ok := Button.new()
	btn_ok.name = "BtnConfirmSelect"
	btn_ok.text = "确认弃置"
	buttons.add_child(btn_ok)
	var btn_cancel := Button.new()
	btn_cancel.name = "BtnCancelSelect"
	btn_cancel.text = "取消"
	buttons.add_child(btn_cancel)
	add_child(panel)
	_block_panel_clicks(panel)
	_enable_modal_drag(panel)
	btn_ok.pressed.connect(_on_card_select_confirmed)
	btn_cancel.pressed.connect(_on_card_select_cancelled)
	_card_select_panel = panel
	return panel


func _show_card_select_panel(pending: Dictionary) -> void:
	var panel := _ensure_card_select_panel()
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
		var pending: Dictionary = EffectManager.get_pending_card_selection()
		var high: int = int(pending.get("max", -1))
		if high != -1 and _card_select_picked.size() >= high:
			return
		_card_select_picked.append(card)
		_set_card_selected_mark(slot, true)
	_refresh_card_select_confirm(EffectManager.get_pending_card_selection())


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
	mark.set_anchors_preset(Control.PRESET_FULL_RECT)


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
		var low2: int = int(pending.get("min", 1))
		var high2: int = int(pending.get("max", low2))
		var ok: bool = _card_select_picked.size() >= low2
		if high2 != -1 and _card_select_picked.size() > high2:
			ok = false
		btn_ok.disabled = not ok


func _on_card_select_confirmed() -> void:
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
	var eff := _card_select_effect
	_card_select_effect = null
	_card_select_picked = []
	if _card_select_panel:
		_card_select_panel.visible = false
	if eff != null:
		# 空提交按"放弃"处理：此刻来源资源与用量都还没扣，等于这个效果没发动
		EffectManager.submit_card_selection(eff, [])
	refresh_all_ui()


## AI自动决断主动效果（检查费用后自动提交）
## 选项类效果(单选/多选)：AI按确定性策略选(每次呼出：单选选第一个仍可用的选项；
## 多选场景选够max_choices个不同的可用选项)，不弹窗
func _resolve_bot_active_effect(effect: BaseEffect, bot_id: int) -> void:
	var pdata: Dictionary = GameDataManager.get_player_data(bot_id) if GameDataManager else {}
	var curr_magic: int = (pdata.get("magic", BaseNumber.new(0)) as BaseNumber).number if pdata else 0
	# 默认AI在有至少1点魔力时积极发动主动效果，否则跳过
	var should_act: bool = (curr_magic >= 1)
	if effect.has_options():
		if !should_act or !EffectManager.has_available_options(effect):
			EffectManager.submit_active_choice(effect, false)
		elif effect.allows_multi_choice():
			var max_c: int = effect._max_choices
			# 只从仍可选(未耗尽用量)的选项里挑，数量不超过这一次提交的max_choices限额
			var available_indices: Array = []
			for i in range(effect._options.size()):
				if EffectManager.is_option_available(effect, i, 1):
					available_indices.append(i)
			var pick_count: int = available_indices.size() if max_c == -1 else min(max_c, available_indices.size())
			var picked: Array = available_indices.slice(0, pick_count)
			EffectManager.submit_option_choice(effect, picked)
		else:
			# 单选：每次呼出只选第一个仍可用的选项
			var first_available := -1
			for i in range(effect._options.size()):
				if EffectManager.is_option_available(effect, i, 1):
					first_available = i
					break
			if first_available == -1:
				EffectManager.submit_active_choice(effect, false)
			else:
				EffectManager.submit_option_choice(effect, [first_available])
	else:
		EffectManager.submit_active_choice(effect, should_act)
	refresh_all_ui()

## 解析效果消耗资源项（纯结构化 JSON 声明，杜绝正则猜测）
func _resolve_effect_cost_items(effect: BaseEffect) -> Array[String]:
	var costs: Array[String] = []
	if effect == null:
		return costs
	# 1. 优先读取 JSON 中声明的 cost
	if effect._cost != null:
		_collect_cost_items(effect._cost, costs)
	# 2. 来源卡牌/技能自带的魔力费用
	if costs.is_empty() and effect.from and "_cost" in effect.from:
		var c = effect.from._cost
		if c is BaseNumber and c.number > 0:
			costs.append("魔力 %d" % c.number)
		elif c is int and c > 0:
			costs.append("魔力 %d" % c)
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
	spin.min_value = int(range_arr[0]) if range_arr.size() > 0 else 1
	spin.max_value = int(range_arr[1]) if range_arr.size() > 1 else spin.min_value
	spin.value = spin.min_value
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
func _check_and_step_ai(delta: float = 0.0) -> void:
	if GameProgress.is_game_over:
		return
	# 上一轮 AI 步进被脚本异常打断时兜底复位：否则一个错误会把整局 AI 永久冻住
	if _ai_acting:
		if GameProgress.current_player_id != _ai_acting_for_id:
			_ai_acting = false
		return
	var curr_id: int = GameProgress.current_player_id
	# 不是自己的回合就交给 AI。判据只认"当前玩家 != 本地玩家"，
	# 不再写死 curr_id > 0——那等于假设本地玩家恒为 0，本地玩家一改，0 号玩家就没人推进
	if curr_id < 0 or curr_id == _local_player_id:
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
	var pl_data: Dictionary = GameDataManager.get_player_data(bot_id)
	var curr_phase := GameProgress.get_current_phase()
	var phase_name: String = curr_phase.get("name", "")
	
	if phase_name == "outpost":
		# 临时测试用 AI：在可部署的战区里随机挑战区、随机挑席位，不做战术权衡。
		# 席位池与本地玩家点击部署共用 _open_deploy_locations，永远只挑真实可用的席位
		var area_pool: Array = []
		for area: BaseMapArea in MapData.areas:
			if !_open_deploy_locations(area).is_empty():
				area_pool.append(area)
		if !area_pool.is_empty():
			area_pool.shuffle()
			# 战区可以随机挑，席位不行：席位必须按"先占满高收益档"的规则来，
			# 只是在当前该用的那一档里随机（同档位之间没有先后）
			var target: BaseLocation = _pick_open_deploy_location(area_pool[0], true)
			if target != null:
				Deploy.new().exec(target, bot_id)
	elif phase_name == "action":
		var hands: Array = pl_data.get("hand_cards", [])
		for card in hands:
			if card is BaseAttack:
				if PlayAttack.new().exec(card, bot_id):
					break
	
	GameProgress.end_current_player_action()
	_ai_acting = false
	refresh_all_ui()

## 列出某战区当前所有可用的部署席（没满员的点位）。
## 注意这里**不能**用 _will_move_to 当判据：那个字段的含义是"常规移动会去的落点"，
## 与"能不能部署"是两回事——地利位/充能位都不是常规移动目的地，却正是部署要抢的席位。
## 哪个战区可部署由地图数据声明(area._can_deploy)，不在这里写死战区下标
func _open_deploy_locations(area: BaseMapArea) -> Array:
	var open: Array = []
	if area == null or !area._can_deploy:
		return open
	for loc: BaseLocation in area._locations:
		if loc._pl_num_limit != -1 and loc._players.size() >= loc._pl_num_limit:
			continue
		open.append(loc)
	return open

## 从可用席位里挑一个：规则是先把收益最高的那一档席位占满，才能用下一档。
## random_within_tier=true 时只在"当前该用的这一档"里随机挑一个（临时测试 AI 用），
## false 时取该档第一位（本地玩家点击部署用）——两者都不会跳到低收益席位去
func _pick_open_deploy_location(area: BaseMapArea, random_within_tier: bool = false) -> BaseLocation:
	var open := _open_deploy_locations(area)
	if open.is_empty():
		return null
	var best_score: int = -1
	for loc in open:
		var score := _deploy_slot_score(loc)
		if score > best_score:
			best_score = score
	var tier: Array = []
	for loc in open:
		if _deploy_slot_score(loc) == best_score:
			tier.append(loc)
	if random_within_tier:
		return tier.pick_random()
	return tier[0]

## 席位的收益分：充能席给魔力、地利席给地利，两者都按席位自己印刷的数字算，
## 不写死"哪一类席位更优先"——数字大的就是该先被占的席位
func _deploy_slot_score(loc: BaseLocation) -> int:
	return int((loc._magic as BaseNumber).number) + int((loc._benefit as BaseNumber).number)

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
		if _selected_opponent == opponent_card:
			_selected_opponent = null
			_selected_opponent_id = ""
			if opponent_drawer:
				opponent_drawer.visible = false
		else:
			_selected_opponent = opponent_card
			_selected_opponent_id = opponent_card.name
			_update_drawer_visuals(opponent_card)
			if opponent_drawer:
				opponent_drawer.visible = true
			if leaderboard_drawer:
				leaderboard_drawer.visible = false
		get_viewport().set_input_as_handled()

func _update_drawer_visuals(opponent_card: Control) -> void:
	if opponent_drawer == null:
		return
	var bot_id: int = _opponent_node_to_id(opponent_card.name)
	var pl_data: Dictionary = GameDataManager.get_player_data(bot_id) if (GameDataManager and bot_id >= 0) else {}
	if pl_data.is_empty():
		return
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
		var opp_power: int = (pl_data.get("power", BaseNumber.new(0)) as BaseNumber).number \
			+ (pl_data.get("total_power_bonus", BaseNumber.new(0)) as BaseNumber).number
		played_lbl.text = "⚔️ %s 已打出牌 · 威力 %d" % [opp_area_txt, opp_power]
	
	# 2. 公开御主卡 / 从者卡（从者未公开时显示卡背且不放大）
	var master_card := opponent_drawer.get_node_or_null("VBox/CardsContentRow/Col_MasterServant/CardsH/MasterCard") as TextureRect
	if master_card:
		master_card.set_meta("zoom_disabled", false)
		_fill_card_slot(master_card, master_obj, "_master_card_img")
	var servant_card := opponent_drawer.get_node_or_null("VBox/CardsContentRow/Col_MasterServant/CardsH/ServantCard") as TextureRect
	if servant_card and servant_obj:
		# 从者是否公开看它的技能牌：技能牌发牌时暗置，被效果翻开(set_concealed(false))即视为公开
		var skills: Array = pl_data.get("servant_skills", [])
		var revealed := skills.is_empty()
		for sk in skills:
			if sk is BaseCard and not bool(sk.get("_is_concealed")):
				revealed = true
				break
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
		_fill_card_row_from_list(opp_row, pl_data.get("played_cards", []), false, false)
	
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
	var hint_lbl := opponent_drawer.get_node_or_null("VBox/HeaderBar/IdentityHint") as Label
	if hint_lbl:
		hint_lbl.text = ""
	
## 5. 未入牌库的卡（技能牌/御主专属技能攻击牌/升华技/附带物）：与本地信息栏同一套采集
	## 与渲染逻辑，暗置的从者技能牌显示卡背；对手抽屉里这些卡只展示不可点击发动
	var skills_col := opponent_drawer.get_node_or_null("VBox/CardsContentRow/Col_Skills")
	if skills_col:
		var skills_row := skills_col.get_node_or_null("CardsH") as HBoxContainer
		if skills_row:
			var cards: Array = _collect_uncataloged_cards(pl_data)
			skills_col.visible = !cards.is_empty()
			_fill_card_row_from_list(skills_row, cards, false, false)

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
	_selected_opponent_id = ""
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

func _show_battle_report(res: Dictionary) -> void:
	if battle_report_modal == null:
		return
	var list := battle_report_modal.get_node_or_null("Box/VBox/ReportScroll/ReportList") as VBoxContainer
	if list == null:
		return
	for c in list.get_children():
		_free_runtime_child(c)
	
	var winners: Dictionary = res.get("winners_by_area", {})
	for area_name in winners.keys():
		var w_ids: Array = winners[area_name]
		var row := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.12, 0.2, 0.85)
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_left = 6
		sb.corner_radius_bottom_right = 6
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		row.add_theme_stylebox_override("panel", sb)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		
		var area_lbl := Label.new()
		area_lbl.text = "【%s】" % area_name
		area_lbl.add_theme_color_override("font_color", Color(0.45, 0.9, 1.0))
		area_lbl.add_theme_font_size_override("font_size", 14)
		h.add_child(area_lbl)
		
		var result_lbl := Label.new()
		result_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if w_ids.size() == 1:
			var wid: int = w_ids[0]
			var pdata: Dictionary = GameDataManager.get_player_data(wid)
			var mname: String = pdata.get("master")._shown_name if pdata.get("master") else ("玩家 %d" % wid)
			result_lbl.text = "🏆 胜者：%s  赢取战区战果！" % mname
			result_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		else:
			result_lbl.text = "平局（多位最高战力平分战果）"
			result_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
		result_lbl.add_theme_font_size_override("font_size", 13)
		h.add_child(result_lbl)
		
		row.add_child(h)
		list.add_child(row)
	
	var draws: Array = res.get("draw_areas", [])
	for area_name in draws:
		var draw_lbl := Label.new()
		draw_lbl.text = "【%s】无人交战或全员败北，战区战果保留" % area_name
		draw_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
		draw_lbl.add_theme_font_size_override("font_size", 12)
		list.add_child(draw_lbl)
	
	# 战报行是每次动态新建的，补齐拖动穿透，保证面板空白处仍可拖动
	_make_children_passive(battle_report_modal)
	battle_report_modal.visible = true
	# 与确认/效果弹窗同一套：后显示的排最后，既画在上层也挡住下层点击
	move_child(battle_report_modal, get_child_count() - 1)

func _on_close_battle_report() -> void:
	if battle_report_modal:
		battle_report_modal.visible = false
	refresh_all_ui()
