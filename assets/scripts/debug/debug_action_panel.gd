class_name DebugActionPanel
extends HBoxContainer

## 按钮式调试操作面板。
## 只呈现按钮与数据驱动的选择控件：所有可选项都从当前局面现取（玩家、战区、席位、
## 卡牌实例、模板、Buff、属性），不写死玩家编号/卡牌名/战区名，也不接受或解析命令行文本。
## 执行统一走 DebugSession.execute_action(name, args)，仍经 registry 的既有白名单与校验。

## 提示类按钮退出宿主呼吸金框（与其余控制台按钮同一约定）
const NO_HINT := "no_clickable_hint"

## 每个命令的界面参数声明。kind 决定控件类型；参数按声明顺序生成，不靠命令名分支。
const COMMAND_FIELDS:Dictionary = {
	"inspect.player": [],
	"inspect.card": [{"key":"id", "label":"卡牌", "kind":"card"}],
	"inspect.board": [],
	"inspect.wait": [],
	"inspect.log": [{"key":"limit", "label":"最近条数", "kind":"int", "min":1, "max":500, "value":100}],
	"inspect.identity": [],
	"resource.magic": [
		{"key":"mode", "label":"方式", "kind":"choice", "value":"set",
			"options":[{"value":"set", "label":"设为"}, {"value":"vary", "label":"增减"}]},
		{"key":"amount", "label":"数值", "kind":"number", "value":1}],
	"resource.score": [
		{"key":"mode", "label":"方式", "kind":"choice", "value":"set",
			"options":[{"value":"set", "label":"设为"}, {"value":"vary", "label":"增减"}]},
		{"key":"amount", "label":"数值", "kind":"number", "value":1}],
	"resource.power": [
		{"key":"mode", "label":"方式", "kind":"choice", "value":"set",
			"options":[{"value":"set", "label":"设为"}, {"value":"vary", "label":"增减"}]},
		{"key":"amount", "label":"数值", "kind":"number", "value":1}],
	"resource.sync_power": [],
	"resource.number": [
		{"key":"key", "label":"字段", "kind":"choice", "value":"",
			"options_source":"number_keys"},
		{"key":"mode", "label":"方式", "kind":"choice", "value":"set",
			"options":[{"value":"set", "label":"设为"}, {"value":"vary", "label":"增减"}]},
		{"key":"amount", "label":"数值", "kind":"number", "value":1},
		{"key":"min", "label":"下限", "kind":"optional_number"},
		{"key":"max", "label":"上限", "kind":"optional_number"}],
	"zone.move": [
		{"key":"card_id", "label":"卡牌", "kind":"card"},
		{"key":"to", "label":"目标牌区", "kind":"zone"},
		{"key":"index", "label":"插入位置", "kind":"optional_int"}],
	"zone.add_clone": [
		{"key":"source_name", "label":"模板", "kind":"template"},
		{"key":"to", "label":"目标牌区", "kind":"zone"}],
	"zone.draw": [],
	"zone.refill_hand": [],
	"zone.shuffle": [{"key":"zone", "label":"牌区", "kind":"zone"}],
	"card.swap_zones": [
		{"key":"other_player", "label":"对方玩家", "kind":"player"},
		{"key":"from_zone", "label":"本玩家牌区", "kind":"zone", "scope":"swap"},
		{"key":"to_zone", "label":"对方牌区", "kind":"zone", "scope":"swap"}],
	"card.cost": [
		{"key":"card_id", "label":"卡牌", "kind":"card"},
		{"key":"mode", "label":"方式", "kind":"choice", "value":"set",
			"options":[{"value":"set", "label":"设为"}, {"value":"vary", "label":"增减"}]},
		{"key":"amount", "label":"数值", "kind":"number", "value":1}],
	"card.power": [
		{"key":"card_id", "label":"卡牌", "kind":"card"},
		{"key":"mode", "label":"方式", "kind":"choice", "value":"set",
			"options":[{"value":"set", "label":"设为"}, {"value":"vary", "label":"增减"}]},
		{"key":"amount", "label":"数值", "kind":"number", "value":1}],
	"card.attrs": [
		{"key":"card_id", "label":"卡牌", "kind":"card"},
		{"key":"add", "label":"新增属性", "kind":"attrs"},
		{"key":"remove", "label":"移除属性", "kind":"attrs"}],
	"card.conceal": [
		{"key":"card_id", "label":"卡牌", "kind":"card"},
		{"key":"bool", "label":"暗置", "kind":"bool", "value":true}],
	"card.close": [{"key":"card_id", "label":"已打出的牌", "kind":"card", "scope":"played"}],
	"map.deploy": [{"key":"area", "label":"战区", "kind":"area"}],
	"map.move": [
		{"key":"steps", "label":"步数", "kind":"int", "min":1, "max":3, "value":1},
		{"key":"ignore_limit", "label":"忽略落点上限", "kind":"bool", "value":false},
		{"key":"ignore_battle", "label":"忽略交战", "kind":"bool", "value":false}],
	"map.teleport": [{"key":"location_id", "label":"落点", "kind":"location"}],
	"map.leave": [],
	"play.regular": [
		{"key":"faceup", "label":"明置卡牌", "kind":"cards"},
		{"key":"hidden", "label":"暗置卡牌", "kind":"cards"}],
	"play.extra_attack": [{"key":"card_id", "label":"攻击牌", "kind":"card"}],
	"play.extra_skill": [{"key":"card_id", "label":"技能牌", "kind":"card"}],
	"name.release": [],
	"name.hide": [],
	"out.eliminate": [],
	"out.restore": [],
	"buff.add": [{"key":"buff_id", "label":"Buff 模板", "kind":"buff", "scope":"available"}],
	"buff.remove": [{"key":"buff_id", "label":"目标持有的 Buff", "kind":"buff", "scope":"owned"}],
	"buff.defeat": [],
	"buff.undead": [],
	"event.place": [
		{"key":"area", "label":"战区", "kind":"area"},
		{"key":"concealed", "label":"暗置放置", "kind":"bool", "value":false},
		{"key":"count", "label":"张数", "kind":"int", "min":1, "max":4, "value":1}],
	"event.clear": [],
	"event.reveal_planned": [],
	"situation.activate": [],
	"situation.clear": [],
	"situation.replace": [
		{"key":"source_name", "label":"局势模板", "kind":"situation"},
		{"key":"grant_printed_magic", "label":"发放印刷魔力", "kind":"bool", "value":false}],
	"identity.set_master": [
		{"key":"master_name", "label":"御主", "kind":"master"},
		{"key":"occupancy", "label":"占用政策", "kind":"choice", "value":"swap", "options_source":"occupancy"},
		{"key":"rebind_command_spell", "label":"重绑令咒", "kind":"bool", "value":true},
		{"key":"master_zone", "label":"卸下时御主技能区", "kind":"choice", "value":"clear", "options_source":"master_zone"}],
	"identity.equip_master": [
		{"key":"master_name", "label":"御主", "kind":"master"},
		{"key":"occupancy", "label":"占用政策", "kind":"choice", "value":"swap", "options_source":"occupancy"},
		{"key":"rebind_command_spell", "label":"重绑令咒", "kind":"bool", "value":true},
		{"key":"master_zone", "label":"卸下时御主技能区", "kind":"choice", "value":"clear", "options_source":"master_zone"}],
	"identity.set_servant": [
		{"key":"servant_name", "label":"从者", "kind":"servant"},
		{"key":"occupancy", "label":"占用政策", "kind":"choice", "value":"swap", "options_source":"occupancy"},
		{"key":"dealt_zones", "label":"已发牌区", "kind":"choice", "value":"swap", "options_source":"dealt_zones"},
		{"key":"true_name", "label":"真名政策", "kind":"choice", "value":"keep_log", "options_source":"true_name"},
		{"key":"rebind_command_spell", "label":"重绑令咒", "kind":"bool", "value":true}],
	"identity.equip_servant": [
		{"key":"servant_name", "label":"从者", "kind":"servant"},
		{"key":"occupancy", "label":"占用政策", "kind":"choice", "value":"swap", "options_source":"occupancy"},
		{"key":"dealt_zones", "label":"已发牌区", "kind":"choice", "value":"swap", "options_source":"dealt_zones"},
		{"key":"true_name", "label":"真名政策", "kind":"choice", "value":"keep_log", "options_source":"true_name"},
		{"key":"rebind_command_spell", "label":"重绑令咒", "kind":"bool", "value":true}],
	"identity.set_pair": [
		{"key":"master_name", "label":"御主", "kind":"master"},
		{"key":"servant_name", "label":"从者", "kind":"servant"},
		{"key":"occupancy", "label":"占用政策", "kind":"choice", "value":"swap", "options_source":"occupancy"},
		{"key":"order", "label":"更换顺序", "kind":"choice", "value":"master_first", "options_source":"order"}],
	"identity.unequip_master": [
		{"key":"master_zone", "label":"御主技能区", "kind":"choice", "value":"clear", "options_source":"master_zone"}],
	"identity.unequip_servant": [
		{"key":"dealt_zones", "label":"已发牌区", "kind":"choice", "value":"replace", "options_source":"removal_zones"},
		{"key":"true_name", "label":"真名政策", "kind":"choice", "value":"keep_log", "options_source":"true_name"}],
	"session.pause": [],
	"session.resume": [],
	"session.undo": [],
	"session.step_action": [],
	"session.step_ai": [],
	"wait.yes": [],
	"wait.no": [],
	"wait.option": [{"key":"selection", "label":"选项", "kind":"pending_options"}],
	"wait.cards": [{"key":"cards", "label":"卡牌", "kind":"pending_cards"}],
	"wait.location": [{"key":"location_id", "label":"落点", "kind":"location"}],
	"wait.players": [{"key":"players", "label":"玩家", "kind":"pending_players"}]
}

## 命令分组与界面按钮名。分组只用于排版，命令名仍是 registry 的键
const COMMAND_GROUPS:Array = [
	{"title":"检查", "commands":[
		{"name":"inspect.player", "label":"查看玩家"},
		{"name":"inspect.card", "label":"查看卡牌"},
		{"name":"inspect.board", "label":"查看版图"},
		{"name":"inspect.wait", "label":"查看等待"},
		{"name":"inspect.log", "label":"查看日志"},
		{"name":"inspect.identity", "label":"查看身份"}]},
	{"title":"资源", "commands":[
		{"name":"resource.magic", "label":"设置/增减魔力"},
		{"name":"resource.score", "label":"设置/增减战果"},
		{"name":"resource.power", "label":"设置/增减合计威力"},
		{"name":"resource.sync_power", "label":"按已出牌重算威力"},
		{"name":"resource.number", "label":"设置/增减玩家数值"}]},
	{"title":"牌区", "commands":[
		{"name":"zone.move", "label":"搬运卡牌"},
		{"name":"zone.add_clone", "label":"克隆卡牌入区"},
		{"name":"zone.draw", "label":"抽一张牌"},
		{"name":"zone.refill_hand", "label":"补牌到手牌上限"},
		{"name":"zone.shuffle", "label":"洗牌"},
		{"name":"card.swap_zones", "label":"交换两名玩家的牌区"}]},
	{"title":"卡牌", "commands":[
		{"name":"card.cost", "label":"改卡牌费用"},
		{"name":"card.power", "label":"改卡牌威力"},
		{"name":"card.attrs", "label":"改卡牌属性"},
		{"name":"card.conceal", "label":"明置/暗置卡牌"},
		{"name":"card.close", "label":"关闭已打出牌"}]},
	{"title":"地图与行动", "commands":[
		{"name":"map.deploy", "label":"常规部署"},
		{"name":"map.move", "label":"常规移动"},
		{"name":"map.teleport", "label":"瞬移落位"},
		{"name":"map.leave", "label":"移出版图"},
		{"name":"play.regular", "label":"常规整组出牌"},
		{"name":"play.extra_attack", "label":"追加打出攻击"},
		{"name":"play.extra_skill", "label":"追加打出技能"},
		{"name":"name.release", "label":"真名解放"},
		{"name":"name.hide", "label":"隐藏真名"},
		{"name":"out.eliminate", "label":"淘汰玩家"},
		{"name":"out.restore", "label":"恢复出局标记"}]},
	{"title":"Buff 与事件局势", "commands":[
		{"name":"buff.add", "label":"添加 Buff"},
		{"name":"buff.remove", "label":"移除 Buff"},
		{"name":"buff.defeat", "label":"标记败北"},
		{"name":"buff.undead", "label":"解除败北"},
		{"name":"event.place", "label":"放置事件牌"},
		{"name":"event.clear", "label":"清空场上事件牌"},
		{"name":"event.reveal_planned", "label":"展示计划内暗置事件"},
		{"name":"situation.activate", "label":"抽取并激活局势牌"},
		{"name":"situation.clear", "label":"弃置当前局势牌"},
		{"name":"situation.replace", "label":"替换为指定局势牌"}]},
	{"title":"身份与从者", "commands":[
		{"name":"identity.set_master", "label":"更换御主"},
		{"name":"identity.set_servant", "label":"更换从者"},
		{"name":"identity.set_pair", "label":"同时更换御主与从者"},
		{"name":"identity.unequip_master", "label":"卸下御主"},
		{"name":"identity.unequip_servant", "label":"卸下从者"}]},
	{"title":"会话与等待", "commands":[
		{"name":"session.pause", "label":"暂停自动推进"},
		{"name":"session.resume", "label":"恢复自动推进"},
		{"name":"session.undo", "label":"撤销上一处局部编辑"},
		{"name":"session.step_action", "label":"单步：结束当前行动"},
		{"name":"session.step_ai", "label":"单步：推进当前 AI"},
		{"name":"wait.yes", "label":"答复：发动"},
		{"name":"wait.no", "label":"答复：放弃"},
		{"name":"wait.option", "label":"答复：选择选项"},
		{"name":"wait.cards", "label":"答复：选择卡牌"},
		{"name":"wait.location", "label":"答复：选择落点"},
		{"name":"wait.players", "label":"答复：选择玩家"}]}
]

var session:DebugSession
var _on_result:Callable

var _command_buttons:Dictionary = {}
var _form_box:VBoxContainer
var _status:Label
var _run_button:Button
var _command_title:Label
var _selected_command:String = ""
var _selected_player_id:int = -1
var _field_controls:Dictionary = {}
var _field_saved:Dictionary = {}
var _field_placeholder:Dictionary = {}
var _player_picker:OptionButton


func initialize(p_session:DebugSession, p_on_result:Callable) -> void:
	session = p_session
	_on_result = p_on_result
	_selected_player_id = GameData.player_id
	_build_static_layout()
	rebuild_form()


func refresh_choices() -> void:
	# 局面变化后所有下拉都要按当前数据重建，而不是沿用旧选项。
	rebuild_form()


func _build_static_layout() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	# 重建时必须清掉旧引用：这些节点已被 free，留着它们会让
	# `_command_buttons` 的遍历与字段读取碰到已释放对象（重复 initialize 就会踩到）。
	_command_buttons.clear()
	_field_controls.clear()
	_field_saved.clear()
	_field_placeholder.clear()
	_player_picker = null
	add_theme_constant_override("separation", 8)

	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(268, 0)
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(left_scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	left_scroll.add_child(left)

	for group in COMMAND_GROUPS:
		var title := Label.new()
		title.text = str(group.title)
		title.add_theme_font_size_override("font_size", 15)
		title.add_theme_color_override("font_color", Color(0.62, 0.78, 1.0))
		left.add_child(title)
		for entry in group.commands:
			var command_name := str(entry.name)
			if !session.registry.schemas.has(command_name):
				continue
			var button := Button.new()
			button.text = str(entry.label)
			button.toggle_mode = true
			button.focus_mode = Control.FOCUS_NONE
			button.set_meta(NO_HINT, true)
			button.tooltip_text = command_name
			button.pressed.connect(_on_command_button_pressed.bind(command_name))
			left.add_child(button)
			_command_buttons[command_name] = button
		left.add_child(HSeparator.new())

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	add_child(right)

	var player_row := HBoxContainer.new()
	player_row.add_theme_constant_override("separation", 6)
	var player_label := Label.new()
	player_label.text = "目标玩家"
	player_row.add_child(player_label)
	var player_picker := OptionButton.new()
	player_picker.name = "PlayerPicker"
	player_picker.focus_mode = Control.FOCUS_NONE
	player_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_picker.item_selected.connect(_on_player_selected.bind(player_picker))
	player_row.add_child(player_picker)
	_player_picker = player_picker
	right.add_child(player_row)

	var body := ScrollContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(body)
	var body_box := VBoxContainer.new()
	body_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_box.add_theme_constant_override("separation", 6)
	body.add_child(body_box)

	_command_title = Label.new()
	_command_title.add_theme_font_size_override("font_size", 15)
	_command_title.add_theme_color_override("font_color", Color(0.62, 0.78, 1.0))
	body_box.add_child(_command_title)

	_form_box = VBoxContainer.new()
	_form_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form_box.add_theme_constant_override("separation", 6)
	body_box.add_child(_form_box)

	_run_button = Button.new()
	_run_button.text = "执行"
	_run_button.focus_mode = Control.FOCUS_NONE
	_run_button.set_meta(NO_HINT, true)
	_run_button.pressed.connect(_on_run_pressed)
	var refresh_button := Button.new()
	refresh_button.text = "刷新选项"
	refresh_button.focus_mode = Control.FOCUS_NONE
	refresh_button.set_meta(NO_HINT, true)
	refresh_button.pressed.connect(_on_refresh_pressed)
	var run_row := HBoxContainer.new()
	run_row.add_theme_constant_override("separation", 8)
	run_row.add_child(_run_button)
	run_row.add_child(refresh_button)
	body_box.add_child(run_row)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	body_box.add_child(_status)

	_fill_player_picker()


func _fill_player_picker() -> void:
	var picker := _player_picker
	if picker == null:
		return
	picker.clear()
	var ids:Array = GameData.player_data_library.keys()
	ids.sort()
	var selected_index:int = 0
	for raw_id in ids:
		var id:int = int(raw_id)
		var data:Dictionary = GameData.player_data_library[id]
		var master = data.get("master")
		var label := "玩家 %d" % id
		if master != null and master.has_method("get_shown_name"):
			label += " · %s" % str(master.get_shown_name())
		if id == GameData.player_id:
			label += "（本地）"
		if bool(data.get("is_out", false)):
			label += "（已淘汰）"
		picker.add_item(label, id)
		if id == _selected_player_id:
			selected_index = picker.item_count - 1
	picker.select(selected_index)
	if picker.item_count > 0:
		_selected_player_id = picker.get_item_id(selected_index)


func _on_player_selected(index:int, picker:OptionButton) -> void:
	if picker == null or index < 0:
		return
	_selected_player_id = picker.get_item_id(index)
	_field_saved.clear()
	rebuild_form(false)


func _on_refresh_pressed() -> void:
	_field_saved.clear()
	rebuild_form(false)


func _on_command_button_pressed(command_name:String) -> void:
	_selected_command = command_name
	for key in _command_buttons:
		var button := _command_buttons[key] as Button
		button.button_pressed = str(key) == command_name
	_field_saved.clear()
	rebuild_form(false)


## preserve=true 时先读回当前控件的值再重建，避免同一命令内刷新时清掉玩家已做的选择。
func rebuild_form(preserve:bool = true) -> void:
	if _form_box == null:
		return
	if preserve:
		_capture_saved_values()
	for child in _form_box.get_children():
		_form_box.remove_child(child)
		child.free()
	_field_controls.clear()
	_field_placeholder.clear()

	if _selected_command == "":
		_command_title.text = "请选择左侧操作"
		_run_button.disabled = true
		return
	var spec:Dictionary = session.registry.schema(_selected_command)
	_command_title.text = "%s（%s）" % [_command_label(_selected_command), _selected_command]
	_run_button.disabled = false

	var fields:Array = COMMAND_FIELDS.get(_selected_command, [])
	if _needs_player(_selected_command):
		var player_hint := Label.new()
		player_hint.text = "使用上方选定的目标玩家"
		player_hint.add_theme_color_override("font_color", Color(0.6, 0.68, 0.78))
		_form_box.add_child(player_hint)
	for field in fields:
		_add_field(field)
	if spec.get("undo_level", "none") == "forbidden" and str(spec.get("scope", "")) != "inspect":
		var warn := Label.new()
		warn.text = "该操作不可撤销，执行前请确认"
		warn.add_theme_color_override("font_color", Color(0.95, 0.7, 0.4))
		_form_box.add_child(warn)
	if spec.is_empty():
		_status.text = "该命令未登记"
	else:
		_status.text = ""
	_fill_player_picker()


func _command_label(command_name:String) -> String:
	for group in COMMAND_GROUPS:
		for entry in group.commands:
			if str(entry.name) == command_name:
				return str(entry.label)
	return command_name


func _needs_player(command_name:String) -> bool:
	var spec:Dictionary = session.registry.schema(command_name)
	return bool(spec.get("params", {}).get("player_required", false)) or command_name == "session.step_ai"


func _capture_saved_values() -> void:
	for key in _field_controls:
		var value = _read_control(_field_controls[key])
		if value != null:
			_field_saved[key] = value


func _add_field(field:Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var key := str(field.key)
	var label := Label.new()
	label.text = str(field.get("label", key))
	label.custom_minimum_size = Vector2(132, 0)
	row.add_child(label)
	var control := _build_control(field)
	if control == null:
		return
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field_controls[key] = control
	if control is Label:
		# 占位说明（如“当前没有选牌等待”）：没有可传的值，校验时跳过，让 registry 报出真实原因
		_field_placeholder[key] = true
	row.add_child(control)
	_form_box.add_child(row)


func _build_control(field:Dictionary) -> Control:
	var key := str(field.key)
	var kind := str(field.get("kind", "text"))
	match kind:
		"choice":
			var options:Array = field.get("options", [])
			if field.has("options_source"):
				options = _options_for_source(str(field.options_source))
			return _make_choice(options, str(_saved_or(key, field.get("value", ""))))
		"int":
			var spin := SpinBox.new()
			spin.min_value = float(field.get("min", 0))
			spin.max_value = float(field.get("max", 99))
			spin.step = 1
			spin.value = float(_saved_or(key, field.get("value", 0)))
			return spin
		"number":
			var number_spin := SpinBox.new()
			number_spin.min_value = -999.0
			number_spin.max_value = 999.0
			number_spin.value = float(_saved_or(key, field.get("value", 0)))
			return number_spin
		"optional_int":
			var holder := HBoxContainer.new()
			var check := CheckBox.new()
			check.text = "指定"
			check.focus_mode = Control.FOCUS_NONE
			check.set_meta(NO_HINT, true)
			holder.add_child(check)
			var value_spin := SpinBox.new()
			value_spin.min_value = -1.0
			value_spin.max_value = 999.0
			value_spin.value = float(_saved_or(key, field.get("value", -1)))
			value_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			holder.add_child(value_spin)
			holder.set_meta("optional_check", check)
			holder.set_meta("optional_value", value_spin)
			return holder
		"optional_number":
			var number_holder := HBoxContainer.new()
			var number_check := CheckBox.new()
			number_check.text = "限制"
			number_check.focus_mode = Control.FOCUS_NONE
			number_check.set_meta(NO_HINT, true)
			number_holder.add_child(number_check)
			var bound_spin := SpinBox.new()
			bound_spin.min_value = -999.0
			bound_spin.max_value = 999.0
			bound_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			number_holder.add_child(bound_spin)
			number_holder.set_meta("optional_check", number_check)
			number_holder.set_meta("optional_value", bound_spin)
			return number_holder
		"bool":
			var box := CheckBox.new()
			box.text = "是"
			box.focus_mode = Control.FOCUS_NONE
			box.set_meta(NO_HINT, true)
			box.button_pressed = bool(_saved_or(key, field.get("value", false)))
			return box
		"card", "cards", "zone", "area", "location", "master", "servant", "template", "buff", "situation", "attrs", "player":
			return _make_list_control(field)
		"pending_options":
			return _make_pending_options()
		"pending_cards":
			return _make_pending_cards()
		"pending_players":
			return _make_pending_players()
	return null


func _saved_or(key:String, fallback):
	return _field_saved.get(key, fallback)


func _make_choice(options:Array, wanted:String) -> OptionButton:
	var picker := OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE
	var selected:int = 0
	for i in range(options.size()):
		var option:Dictionary = options[i]
		var value := str(option.get("value", ""))
		picker.add_item(str(option.get("label", value)), i)
		picker.set_item_metadata(i, value)
		if value == wanted:
			selected = i
	picker.select(selected)
	return picker


func _options_for_source(source:String) -> Array:
	match source:
		"occupancy":
			return [
				{"value":"swap", "label":"交换：与持有者互换身份与随附状态"},
				{"value":"exclusive", "label":"独占：他人已持有则拒绝"},
				{"value":"steal", "label":"夺取：先卸下原持有者"}]
		"master_zone":
			return [
				{"value":"clear", "label":"移到游戏外"},
				{"value":"keep", "label":"保留现有御主技能牌"}]
		"dealt_zones":
			return [
				{"value":"swap", "label":"与交换对象对调牌区"},
				{"value":"replace", "label":"清退旧从者牌并重发"},
				{"value":"keep", "label":"保留现有牌区"}]
		"removal_zones":
			#单独"卸下"没有交换对象，只列出真的可用的两种政策
			return [
				{"value":"replace", "label":"清退旧从者牌并重发"},
				{"value":"keep", "label":"保留现有牌区"}]
		"true_name":
			return [
				{"value":"keep_log", "label":"保留真名历史"},
				{"value":"hide_if_released", "label":"已解放则隐藏"}]
		"order":
			return [
				{"value":"master_first", "label":"先换御主再换从者"},
				{"value":"servant_first", "label":"先换从者再换御主"}]
		"number_keys":
			var keys:Array = []
			for key in DebugPlayerAdapter.NUMBER_KEYS:
				keys.append({"value":str(key), "label":str(key)})
			return keys
	return []


func _make_list_control(field:Dictionary) -> Control:
	var kind := str(field.get("kind", "card"))
	var key := str(field.key)
	var scope := str(field.get("scope", "any"))
	var multiple:bool = kind == "cards" || kind == "attrs"
	if multiple:
		var list := ItemList.new()
		list.custom_minimum_size = Vector2(0, 96)
		list.select_mode = ItemList.SELECT_MULTI
		list.allow_reselect = true
		_populate_list(list, kind, key, scope)
		return list
	var picker := OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE
	_populate_options(picker, kind, key, scope)
	return picker


func _populate_list(list:ItemList, kind:String, key:String, scope:String) -> void:
	list.clear()
	var entries:Array = _entries_for(kind, scope)
	var wanted = _field_saved.get(key, [])
	for entry in entries:
		list.add_item(str(entry.label))
		list.set_item_metadata(list.item_count - 1, entry.value)
		if wanted is Array and wanted.has(entry.value):
			# Godot 4 的 ItemList 没有 set_item_selected；多选恢复用 select(idx, false)，
			# 第二参数为 false 表示加入当前选择而不是替换。写成 set_item_selected 会抛
			# `Nonexistent function 'set_item_selected'`：玩家在多选里挑完牌、表单一重建就断。
			list.select(list.item_count - 1, false)


func _populate_options(picker:OptionButton, kind:String, key:String, scope:String) -> void:
	picker.clear()
	var entries:Array = _entries_for(kind, scope)
	var wanted = _field_saved.get(key, null)
	var selected:int = 0
	for i in range(entries.size()):
		var entry:Dictionary = entries[i]
		picker.add_item(str(entry.label))
		picker.set_item_metadata(i, entry.value)
		if wanted != null and entry.value == wanted:
			selected = i
	# 没有任何候选时不能 select(0)：Godot 会报
	# `Index p_which = 0 is out of bounds (popup->get_item_count() = 0)`。
	if picker.item_count > 0:
		picker.select(selected)


## scope 由字段声明，用来只列出「这次调用真正会接受」的候选：
## `card.close` 只接受已打出的牌、`buff.remove` 只接受目标当前持有的实例。
## 这不是限制能力——registry 仍接受任意合法 id，只是不让按钮去撞必然失败的选项。
func _entries_for(kind:String, scope:String = "any") -> Array:
	var entries:Array = []
	match kind:
		"card":
			for entry in _player_card_entries(scope):
				entries.append(entry)
		"cards":
			for entry in _player_card_entries(scope):
				entries.append(entry)
		"zone":
			for path in _player_zone_paths(scope):
				entries.append({"value":str(path), "label":str(path)})
		"player":
			for raw_id in GameData.player_data_library.keys():
				var pid:int = int(raw_id)
				var label := "玩家 %d" % pid
				if pid == GameData.player_id:
					label += "（本地）"
				entries.append({"value":pid, "label":label})
		"area":
			for area in MapData.areas:
				if area is BaseMapArea:
					entries.append({"value":area._area_name, "label":area._area_name})
		"location":
			for area in MapData.areas:
				if !(area is BaseMapArea):
					continue
				for location in area._locations:
					if location is BaseLocation:
						entries.append({
							"value":location.get_instance_id(),
							"label":"%s / 席位 #%s" % [area._area_name, location.get_instance_id()]})
		"master":
			for master in GameData.loaded_masters:
				if master != null:
					entries.append({"value":master._name, "label":"%s（%s）" % [master.get_shown_name(), master._name]})
		"servant":
			for servant in GameData.loaded_servants:
				if servant != null:
					entries.append({"value":servant._name, "label":"%s（%s）" % [servant.get_shown_name(), servant._name]})
		"template":
			for object in _template_pool():
				entries.append({"value":object._name, "label":"%s（%s）" % [object.get_shown_name(), object._name]})
		"buff":
			for object in _buff_entries(scope):
				entries.append(object)
		"situation":
			for raw_name in _situation_template_names():
				entries.append({"value":str(raw_name), "label":str(raw_name)})
		"attrs":
			for attribute in Attributes.get_all_attributes():
				entries.append({"value":str(attribute), "label":Attributes.get_shown_attribute(str(attribute))})
	return entries


func _player_card_entries(scope:String = "any") -> Array:
	var entries:Array = []
	if !GameData.player_data_library.has(_selected_player_id):
		return entries
	var zones:Dictionary = DebugValidate.player_zones(_selected_player_id)
	var paths:Array = zones.keys()
	paths.sort()
	for raw_path in paths:
		var path := str(raw_path)
		if scope == "played" and path != "played_cards":
			continue
		for object in zones[raw_path]:
			if !(object is BaseCard):
				continue
			var shown_name:String = str(object.get_shown_name()) if object.has_method("get_shown_name") else str(object._name)
			entries.append({
				"value":object.get_instance_id(),
				"label":"%s：%s #%s" % [path, shown_name, object.get_instance_id()]})
	return entries


func _buff_entries(scope:String) -> Array:
	var entries:Array = []
	if scope == "owned":
		if !GameData.player_data_library.has(_selected_player_id):
			return entries
		for object in GameData.player_data_library[_selected_player_id].get("buffs", []):
			if object is BaseBuff:
				entries.append(_buff_entry(object))
		return entries
	# 可用模板/实例：新增时 registry 会克隆一份再挂上，所以这里列全体 Buff 对象
	for object in GameData.objects:
		if object is BaseBuff:
			entries.append(_buff_entry(object))
	return entries


func _buff_entry(object:BaseBuff) -> Dictionary:
	return {"value":object.get_instance_id(),
		"label":"%s ×%s #%s" % [object.get_shown_name(), object._buff_level, object.get_instance_id()]}


func _player_zone_paths(scope:String = "any") -> Array:
	if !GameData.player_data_library.has(_selected_player_id):
		return []
	var paths:Array = DebugValidate.player_zones(_selected_player_id).keys()
	if scope == "swap":
		#只交换可整体对调的牌区：名单与引擎侧校验共用 DebugCardAdapter.SWAP_ZONE_PATHS，
		#列表里不列必然被拒绝的牌区
		var allowed:Array = []
		for path in paths:
			if DebugCardAdapter.SWAP_ZONE_PATHS.has(str(path)):
				allowed.append(path)
		paths = allowed
	paths.sort()
	return paths


func _template_pool() -> Array:
	var pool:Array = []
	pool.append_array(LoadEvent.events)
	pool.append_array(LoadSituation.situations)
	pool.append_array(LoadSituation.climax_situations.values())
	pool.append_array(_command_spell_templates())
	for holder in GameData.loaded_masters + GameData.loaded_servants:
		if holder == null:
			continue
		if "_specials" in holder:
			for value in holder._specials.values():
				if value is Array:
					pool.append_array(value)
		if "_other_things" in holder:
			pool.append_array(holder._other_things)
		if "_upgrade_skill" in holder:
			pool.append_array(holder._upgrade_skill)
	return pool


func _situation_template_names() -> Array:
	var names:Array = []
	for template in LoadSituation.situations:
		if template is BaseSituation:
			names.append(template._name)
	for key in LoadSituation.climax_situations:
		var template = LoadSituation.climax_situations[key]
		if template is BaseSituation:
			names.append(template._name)
	return names


func _command_spell_templates() -> Array:
	var pool:Array = []
	var source = LoadCommandSpell.command_spells
	if source is Dictionary:
		pool.append_array(source.values())
	elif source is Array:
		pool.append_array(source)
	return pool


func _make_pending_options() -> Control:
	var effect = EffectManager.waiting_effect
	if effect == null:
		return _placeholder("当前没有选项等待")
	var options:Array = effect._options if "_options" in effect else []
	if options.is_empty():
		return _placeholder("该效果未声明选项")
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, 96)
	list.select_mode = ItemList.SELECT_MULTI if effect.has_method("allows_multi_choice") and effect.allows_multi_choice() else ItemList.SELECT_SINGLE
	for i in range(options.size()):
		var option:Dictionary = options[i] if options[i] is Dictionary else {}
		var shown := str(option.get("shown_option_name", option.get("option_name", "")))
		if shown == "":
			shown = "选项 %d" % i
		list.add_item(shown)
		list.set_item_metadata(list.item_count - 1, i)
	return list


func _make_pending_cards() -> Control:
	var pending:Dictionary = EffectManager.get_pending_card_selection()
	var cards:Array = pending.get("cards", [])
	if cards.is_empty():
		return _placeholder("当前没有选牌等待")
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, 96)
	list.select_mode = ItemList.SELECT_MULTI
	for card in cards:
		if card is BaseCard:
			list.add_item("%s #%s" % [str(card.get_shown_name()), card.get_instance_id()])
			list.set_item_metadata(list.item_count - 1, card.get_instance_id())
	return list


func _make_pending_players() -> Control:
	var pending:Dictionary = EffectManager.get_pending_player_selection()
	var candidates:Array = pending.get("candidates", [])
	if candidates.is_empty():
		return _placeholder("当前没有选玩家等待")
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, 96)
	list.select_mode = ItemList.SELECT_MULTI
	for raw_id in candidates:
		var id:int = int(raw_id)
		list.add_item("玩家 %d" % id)
		list.set_item_metadata(list.item_count - 1, id)
	return list


func _placeholder(text:String) -> Control:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.4))
	return label


func _on_run_pressed() -> void:
	if session == null or _selected_command == "":
		return
	var args:Dictionary = {}
	if _needs_player(_selected_command):
		args["player"] = _selected_player_id
	var fields:Array = COMMAND_FIELDS.get(_selected_command, [])
	for field in fields:
		var key := str(field.key)
		if !_field_controls.has(key):
			continue
		var value = _read_control(_field_controls[key])
		_apply_field_value(args, key, value, field)
	if _selected_command == "play.regular":
		_build_regular_play_args(args)
	if !_validate_args(args):
		return
	var result:Dictionary = session.execute_action(_selected_command, args)
	var label := "「%s」" % _command_label(_selected_command)
	if bool(result.get("ok", false)):
		# 成功但没产生变化时要说清楚，否则玩家会以为按钮没生效
		_status.text = "已执行：%s" % label if bool(result.get("changed", false)) else "已执行但未产生变化：%s" % label
	else:
		var reason := str(result.get("error", "")).strip_edges()
		_status.text = "被拒绝：%s" % (reason if reason != "" else label)
	if _on_result.is_valid():
		_on_result.call(label, result)
	_field_saved.clear()
	rebuild_form()


func _apply_field_value(args:Dictionary, key:String, value, field:Dictionary) -> void:
	var kind := str(field.get("kind", "text"))
	match kind:
		"optional_int":
			args[key] = value if value != null else -1
		"optional_number":
			if value != null:
				args[key] = value
		"bool":
			args[key] = bool(value)
		_:
			args[key] = value
	# 数值类命令用「方式 + 数值」两个控件表达，落到 registry 的 set / vary 两个参数位
	if ["resource.magic", "resource.score", "resource.power", "card.cost", "card.power"].has(_selected_command) and key == "amount":
		var mode_control = _field_controls.get("mode")
		var mode := str(_read_control(mode_control)) if mode_control != null else "set"
		args.erase("mode")
		args.erase("amount")
		args[mode] = value
	if _selected_command == "resource.number" and key == "amount":
		var number_mode_control = _field_controls.get("mode")
		var number_mode := str(_read_control(number_mode_control)) if number_mode_control != null else "set"
		args.erase("mode")
		args.erase("amount")
		args[number_mode] = value


func _build_regular_play_args(args:Dictionary) -> void:
	# 明置与暗置分开选，避免让界面替玩家猜整组里哪张翻面；
	# 两个数组等长且按同一顺序配对，规则校验仍由 RegularPlay.can_submit_group 负责。
	var faceup:Array = args.get("faceup", [])
	var hidden:Array = args.get("hidden", [])
	var cards:Array = []
	var hidden_flags:Array = []
	for raw_id in faceup:
		cards.append(int(raw_id))
		hidden_flags.append(false)
	for raw_id in hidden:
		cards.append(int(raw_id))
		hidden_flags.append(true)
	args.erase("faceup")
	args.erase("hidden")
	if !cards.is_empty():
		args["cards"] = cards
		args["hidden"] = hidden_flags


func _validate_args(args:Dictionary) -> bool:
	if _selected_command == "play.regular":
		if !args.has("cards"):
			_status.text = "请至少选择一张明置或暗置卡牌"
			return false
		return true
	if _selected_command == "resource.number" and str(args.get("key", "")) == "":
		_status.text = "请选择要修改的数值字段"
		return false
	var spec:Dictionary = session.registry.schema(_selected_command)
	for required in spec.get("params", {}).get("required", []):
		var key := str(required)
		if key == "player":
			continue
		if _field_placeholder.has(key):
			continue
		if !args.has(key) or _is_empty_value(args[key]):
			_status.text = _empty_reason(key)
			return false
	return true


## 参数没值时要分清两种原因：没有可选对象（如该玩家当前没有已打出的牌）
## 与单纯没选（对象存在但列表为空/多选没勾）。提示要说清是哪种，否则玩家不知道该改什么。
func _empty_reason(key:String) -> String:
	var control = _field_controls.get(key)
	var label := key
	for field in COMMAND_FIELDS.get(_selected_command, []):
		if str(field.key) == key:
			label = str(field.get("label", key))
	if control is OptionButton and (control as OptionButton).item_count == 0:
		return "没有可选对象：%s（当前没有符合条件的对象）" % label
	if control is ItemList and (control as ItemList).item_count == 0:
		return "没有可选对象：%s（当前没有符合条件的对象）" % label
	if control is ItemList:
		return "请至少选择一项：%s" % label
	return "缺少参数：%s" % label


## 「这个参数算不算没填」必须按类型判，不能拿 `== ""` 和任意值比：
## 卡牌 id、席位 id、步数都是整数，`int == String` 会抛
## `Invalid operands 'int' and 'String' in operator '=='`，在编辑器里表现为点执行直接断点，
## 而且异常会把整段提交中断，卡牌根本没搬。0 与 false 都是合法取值，只有空串、空数组与 null 算没填。
func _is_empty_value(value) -> bool:
	if value == null:
		return true
	if value is String:
		return (value as String).strip_edges() == ""
	if value is Array:
		return (value as Array).is_empty()
	if value is Dictionary:
		return (value as Dictionary).is_empty()
	return false


func _read_control(control) -> Variant:
	if control == null:
		return null
	if control is OptionButton:
		var picker := control as OptionButton
		if picker.item_count == 0:
			return null
		var index:int = picker.selected
		if index < 0:
			index = 0
		return picker.get_item_metadata(index)
	if control is ItemList:
		var list := control as ItemList
		var picked:Array = []
		for index in list.get_selected_items():
			picked.append(list.get_item_metadata(index))
		return picked
	if control is SpinBox:
		return (control as SpinBox).value
	if control is CheckBox:
		return (control as CheckBox).button_pressed
	if control.has_meta("optional_check"):
		var check := control.get_meta("optional_check") as CheckBox
		if check == null or !check.button_pressed:
			return null
		var value_spin := control.get_meta("optional_value") as SpinBox
		return value_spin.value if value_spin != null else null
	if control is Label:
		return null
	return null
