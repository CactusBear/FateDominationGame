extends Control

## UI 草案交互：
## 1. 顶部对手卡负责展开、切换和再次收起。
## 2. 顶部【战果榜】点击展开 / 再次点击收起。
## 3. 底部手牌浮动托盘：常态只露把手，鼠标移入伸出，移出收回；卡牌放大顶框。

@export_node_path("Control") var opponent_drawer_path: NodePath = NodePath("OpponentDrawer_Expanded")
@export_node_path("Control") var leaderboard_drawer_path: NodePath = NodePath("Drawer_Leaderboard")
@export_node_path("Control") var hand_tray_path: NodePath = NodePath("HandTray_Collapsible")

var _selected_opponent: Control = null
var _selected_opponent_id: String = ""

@onready var opponent_drawer: Control = get_node_or_null(opponent_drawer_path)
@onready var leaderboard_drawer: Control = get_node_or_null(leaderboard_drawer_path)
@onready var hand_tray: Control = get_node_or_null(hand_tray_path)

# 手牌抽屉折叠与伸出坐标参数 (高 270px，折叠时仅露 32px 把手)
const HAND_COLLAPSED_TOP: float = -34.0
const HAND_EXPANDED_TOP: float = -272.0

func _ready() -> void:
	if opponent_drawer:
		opponent_drawer.visible = false
	if leaderboard_drawer:
		leaderboard_drawer.visible = false
	
	_register_opponent_cards()
	_register_leaderboard_toggle()
	_setup_floating_hand_tray()

func _register_opponent_cards() -> void:
	var order_box := get_node_or_null("TopPanel_AllPlayers/AllPlayersOrderScroll/OrderHBox")
	if order_box == null:
		return
	for child in order_box.get_children():
		if child.name.begins_with("P") and child.name != "P1_Me_AvatarOnly":
			child.mouse_filter = Control.MOUSE_FILTER_STOP
			if not child.gui_input.is_connected(_on_opponent_gui_input):
				child.gui_input.connect(_on_opponent_gui_input.bind(child))

func _register_leaderboard_toggle() -> void:
	var btn_rank := get_node_or_null("TopPanel_AllPlayers/BtnRankMenu") as Button
	if btn_rank:
		if not btn_rank.pressed.is_connected(_on_leaderboard_btn_pressed):
			btn_rank.pressed.connect(_on_leaderboard_btn_pressed)

func _on_leaderboard_btn_pressed() -> void:
	if leaderboard_drawer == null:
		return
	var will_show: bool = not leaderboard_drawer.visible
	leaderboard_drawer.visible = will_show
	if will_show and opponent_drawer and opponent_drawer.visible:
		_set_drawer_visible(false)
		_selected_opponent = null

func _on_opponent_gui_input(event: InputEvent, opponent_card: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var opponent_id := opponent_card.name
		if _selected_opponent == opponent_card:
			_selected_opponent = null
			_selected_opponent_id = ""
			_set_drawer_visible(false)
		else:
			_selected_opponent = opponent_card
			_selected_opponent_id = opponent_id
			_update_drawer_visuals(opponent_card)
			_set_drawer_visible(true)
			if leaderboard_drawer:
				leaderboard_drawer.visible = false
		get_viewport().set_input_as_handled()

func _set_drawer_visible(should_show: bool) -> void:
	if opponent_drawer:
		opponent_drawer.visible = should_show

func _update_drawer_visuals(opponent_card: Control) -> void:
	if opponent_drawer == null:
		return
	var avatar := opponent_card.get_node_or_null("HBox/Avatar") as TextureRect
	var selected_avatar := opponent_drawer.get_node_or_null("VBox/HeaderBar/SelectedAvatarFrame/Avatar") as TextureRect
	if avatar and selected_avatar:
		selected_avatar.texture = avatar.texture

	var order_badge := opponent_drawer.get_node_or_null("VBox/HeaderBar/OrderBadge") as Label
	if order_badge:
		var order_text := opponent_card.name.trim_prefix("P").split("_")[0]
		order_badge.text = "%s\n◆" % order_text

func _setup_floating_hand_tray() -> void:
	if hand_tray == null:
		return
	hand_tray.visible = true
	hand_tray.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# 初始状态设为收敛露底
	hand_tray.offset_top = HAND_COLLAPSED_TOP
	hand_tray.offset_bottom = 0.0
	
	if not hand_tray.mouse_entered.is_connected(_on_hand_tray_mouse_entered):
		hand_tray.mouse_entered.connect(_on_hand_tray_mouse_entered)
	if not hand_tray.mouse_exited.is_connected(_on_hand_tray_mouse_exited):
		hand_tray.mouse_exited.connect(_on_hand_tray_mouse_exited)

func _on_hand_tray_mouse_entered() -> void:
	if hand_tray:
		# 鼠标滑入：伸出手牌，完整展现
		var tween := create_tween()
		tween.tween_property(hand_tray, "offset_top", HAND_EXPANDED_TOP, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_hand_tray_mouse_exited() -> void:
	if hand_tray:
		# 鼠标移出：收回手牌，只露把手
		var tween := create_tween()
		tween.tween_property(hand_tray, "offset_top", HAND_COLLAPSED_TOP, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
