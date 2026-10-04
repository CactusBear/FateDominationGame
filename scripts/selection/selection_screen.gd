extends Control

const MODE_INTERFACE = preload("res://scripts/selection/selection_mode.gd")
const BATTLE_SCENE := "res://assets/scenes/game_scene/battle_board_v2.tscn"

@onready var mode_picker: OptionButton = $Margin/Content/Settings/Mode
@onready var player_count: SpinBox = $Margin/Content/Settings/Players
@onready var status: Label = $Margin/Content/Status
@onready var choices: VBoxContainer = $Margin/Content/Scroll/Choices
@onready var begin_button: Button = $Margin/Content/Actions/Begin
@onready var enter_button: Button = $Margin/Content/Actions/Enter
var modes: Array = []
var session
var _next_player := 0
var _bot := DummyBot.new()
@onready var roster: Label = $Margin/Content/RosterScroll/Roster
var _roster_signature: Array = []
var _refresh_elapsed := 0.0
@export var roster_refresh_seconds := 1.0

func _ready() -> void:
	$Margin/Content/Actions/Back.pressed.connect(_back)
	begin_button.pressed.connect(begin_selection)
	enter_button.pressed.connect(enter_battle)
	mode_picker.item_selected.connect(_mode_changed)
	var file := FileAccess.open(LoadHelper.get_data_dir().path_join("selection_modes.json"), FileAccess.READ)
	if file == null:
		status.text = "无法读取选人模式配置"
		begin_button.disabled = true
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not parsed.get("modes") is Array:
		status.text = "选人模式配置无效"
		begin_button.disabled = true
		return
	modes = parsed.modes
	for mode in modes:
		mode_picker.add_item(str(mode.get("name", mode.get("id", ""))))
		if mode.get("id", "") == parsed.get("default_mode", ""):
			mode_picker.select(mode_picker.item_count - 1)
	_mode_changed(mode_picker.selected)
	player_count.value = player_count.max_value
	_refresh_roster()

func _process(delta: float) -> void:
	_refresh_elapsed += delta
	if _refresh_elapsed >= roster_refresh_seconds:
		_refresh_elapsed = 0.0
		_refresh_roster()

func _refresh_roster() -> void:
	LoadGame.refresh_roster()
	var signature: Array = []
	var master_names: PackedStringArray = []
	var servant_names: PackedStringArray = []
	for master in GameStart.get_masters_can_use():
		signature.append([master.get_instance_id(), master.get_shown_name()])
		master_names.append(master.get_shown_name())
	for servant in GameStart.get_servants_can_use():
		signature.append([servant.get_instance_id(), servant.get_shown_name(), servant._servant_class])
		servant_names.append("%s · %s" % [servant.get_shown_name(), servant._servant_class.capitalize()])
	if signature != _roster_signature:
		var had_session: bool = session != null
		_roster_signature = signature
		roster.text = "御主候选：%s\n从者候选：%s" % ["、".join(master_names), "、".join(servant_names)]
		_mode_changed(mode_picker.selected)
		if had_session:
			status.text = "角色名单已更新，请重新开始选人。" + status.text
	if not LoadGame.roster_catalog.error.is_empty():
		status.text = LoadGame.roster_catalog.error
		begin_button.disabled = true
		enter_button.disabled = true
	elif begin_button.disabled and mode_picker.selected >= 0:
		_mode_changed(mode_picker.selected)

func _mode_changed(index: int) -> void:
	_clear_choices()
	enter_button.disabled = true
	session = null
	if index < 0 or index >= modes.size():
		status.text = "没有可用选人模式"
		begin_button.disabled = true
		return
	var script = load(str(modes[index].get("script", "")))
	if script == null or not script is Script or not script.can_instantiate():
		status.text = "无法加载选人规则"
		begin_button.disabled = true
		return
	var candidate = script.new()
	if not is_instance_of(candidate, MODE_INTERFACE):
		status.text = "选人规则未实现统一接口"
		begin_button.disabled = true
		return
	var maximum: int = candidate.capacity(GameStart.get_masters_can_use(), GameStart.get_servants_can_use(), modes[index])
	begin_button.disabled = maximum <= 0
	player_count.min_value = 1
	player_count.max_value = maxi(1, maximum)
	status.text = candidate.error if maximum <= 0 else "选择人数后开始选人。当前容量：%d" % maximum

func _clear_choices() -> void:
	for child in choices.get_children():
		choices.remove_child(child)
		child.queue_free()

func begin_selection() -> void:
	_refresh_roster()
	if begin_button.disabled or mode_picker.selected < 0:
		return
	var config: Dictionary = modes[mode_picker.selected]
	session = load(str(config.script)).new()
	var ids: Array = []
	# 本地玩家 ID 来自现有对局配置，不假定必须为 0。
	ids.append(GameData.player_id)
	for i in int(player_count.value):
		if ids.size() >= int(player_count.value):
			break
		if i != GameData.player_id:
			ids.append(i)
	if not session.setup(ids, GameStart.get_masters_can_use(), GameStart.get_servants_can_use(), config):
		status.text = session.error
		session = null
		return
	_next_player = 0
	enter_button.disabled = true
	_show_choices()

func _show_choices() -> void:
	_clear_choices()
	# 同一提交入口处理人类与 AI；循环推进避免人数增加时递归堆栈增长。
	while not session.is_complete() and _next_player < session.player_ids.size():
		var bot_id: int = session.player_ids[_next_player]
		if bot_id == GameData.player_id:
			break
		var master = _bot.pick_master(session, bot_id)
		if master == null or not session.choose_master(bot_id, master):
			status.text = "AI 无法选择御主：" + session.error
			return
		_next_player += 1
	if session.is_complete():
		# 选人界面是共用屏幕，完成状态不读取或展示私人从者归属。
		status.text = "御主选择完成，从者已抽取。抽取结果不公示。"
		enter_button.disabled = false
		return
	var id: int = session.player_ids[_next_player]
	status.text = "%s 选择御主，已选御主不可重复" % (GameData.default_player_name_pattern % (id + 1))
	for master in session.available_masters(id):
		var button := Button.new()
		button.text = master.get_shown_name()
		button.pressed.connect(_choose.bind(id, master))
		choices.add_child(button)

func _choose(id: int, master) -> void:
	_refresh_roster()
	if not LoadGame.roster_catalog.error.is_empty():
		return
	if session == null or session.is_complete() or session.player_ids[_next_player] != id:
		return
	if not session.choose_master(id, master):
		status.text = session.error
		return
	_next_player += 1
	_show_choices()

func enter_battle() -> void:
	# 防止刷新间隔内刚删除的角色进入对局。
	_refresh_roster()
	if not LoadGame.roster_catalog.error.is_empty():
		return
	if session == null or not session.is_complete():
		return
	if not GameStart.game_start(session.player_ids, session.get_assignments(), session.get_initial_order()):
		status.text = "阵容无效或对局已经启动"
		return
	var result := get_tree().change_scene_to_file(BATTLE_SCENE)
	if result != OK:
		status.text = "无法进入对局"

func _back() -> void:
	get_tree().change_scene_to_file(GameStart.MAIN_MENU_SCENE)
