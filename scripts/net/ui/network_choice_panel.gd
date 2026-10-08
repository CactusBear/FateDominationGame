extends PanelContainer

## 只消费会话视图，不持有或调用 EffectManager 等规则对象。
var _session
var _prompt: Dictionary = {}
var _sequence: int = 0
var _submitted: bool = false
var _submit_sequence: int = 0

func _ready() -> void:
	$Content/Actions/Confirm.pressed.connect(_submit.bind(true))
	$Content/Actions/Decline.pressed.connect(_submit.bind(false))
	$Content/Targets.multi_selected.connect(_protect_required)

func bind_session(session) -> void:
	_unbind()
	_prompt.clear()
	_submitted = false
	_submit_sequence = 0
	_session = session
	if _session != null:
		_session.changed.connect(_refresh)
		_session.request_rejected.connect(_rejected)
	_refresh()

func _refresh() -> void:
	if _session == null:
		hide()
		return
	var next_prompt: Dictionary = _session.read_pending()
	var rebuild: bool = next_prompt != _prompt
	_prompt = next_prompt
	var next_sequence: int = int(_session.read_match().get("seq", 0))
	if rebuild or next_sequence != _sequence:
		_submitted = false
		_submit_sequence = 0
	_sequence = next_sequence
	visible = _prompt.get("kind") in ["active_choice", "player_choice", "card_choice", "location_choice"]
	if not visible:
		return
	$Content/Title.text = str(_prompt.get("label", ""))
	var options: Array = _prompt.get("options", [])
	$Content/Actions/Confirm.disabled = false
	$Content/Actions/Decline.visible = bool(_prompt.get("allow_cancel", false))
	$Content/Actions/Decline.disabled = false
	$Content/Status.text = "请选择是否接受" if options.is_empty() else "填写所选分支的使用次数，未选分支保持 0"
	if rebuild:
		_build_options(options)
		_build_targets()
	$Content/Options.visible = _prompt.kind == "active_choice"
	$Content/Targets.visible = _prompt.kind != "active_choice"
	if _prompt.kind != "active_choice":
		$Content/Status.text = "选择目标地点" if _prompt.kind == "location_choice" else "选择数量 %s — %s" % [_prompt.get("min", 0), "不限" if _prompt.get("max", -1) == -1 else str(_prompt.max)]
	refresh_submission_availability()

## 不重建待答、不清除已选目标，也不重置等待主机确认的提交锁。
func refresh_submission_availability() -> void:
	if _session == null or not visible: return
	var available:bool = _session.match_commands_available()
	$Content/Actions/Confirm.disabled = not available or _submitted
	$Content/Actions/Decline.disabled = not available or _submitted
	if not available: $Content/Status.text = "等待对局恢复"

func _submit(activate: bool) -> void:
	if _session == null or _submitted or not visible or not _session.match_commands_available():
		return
	if not activate and not _prompt.get("allow_cancel", false):
		return
	var command := "active_choice"
	var args := {"effect": _prompt.effect, "activate": activate}
	if not activate:
		command = "cancel_choice"
		args = {"effect": _prompt.effect}
	elif _prompt.kind != "active_choice":
		var selected: Array = []
		for index in $Content/Targets.get_selected_items():
			selected.append($Content/Targets.get_item_metadata(index))
		command = _prompt.kind
		args = {"effect": _prompt.effect}
		if command == "location_choice":
			if selected.size() != 1:
				$Content/Status.text = "请选择目标地点"
				return
			args.area = selected[0]
		else:
			args["cards" if command == "card_choice" else "players"] = selected
	elif activate and not _prompt.get("options", []).is_empty():
		var choices: Array = []
		for option in _prompt.options:
			var row: HBoxContainer = $Content/Options.get_node("Row" + str(option.index))
			var count_text: String = row.get_node("Count").text
			if not count_text.is_valid_int() or int(count_text) < 0:
				$Content/Status.text = "次数必须是非负整数"
				return
			if int(count_text) == 0:
				continue
			var choice := {"index": option.index, "count": int(count_text)}
			if option.has("quantity_range"):
				var quantity_text: String = row.get_node("Quantity").text
				if not quantity_text.is_valid_int():
					$Content/Status.text = "数量必须是整数"
					return
				choice.quantity = int(quantity_text)
			choices.append(choice)
		if choices.is_empty():
			$Content/Status.text = "尚未选择分支"
			return
		command = "option_choice"
		args = {"effect": _prompt.effect, "choices": choices}
	_submitted = true
	$Content/Actions/Confirm.disabled = true
	$Content/Actions/Decline.disabled = true
	$Content/Status.text = "等待主机确认"
	var result: Error = _session.request("match_command", {"view_seq": _sequence, "command": command, "params": args}, _register_submit)
	if result != OK:
		_submitted = false
		_submit_sequence = 0
		_refresh()
		$Content/Status.text = error_string(result)

func _register_submit(sequence: int) -> void:
	_submit_sequence = sequence

func _rejected(sequence: int, reason: String) -> void:
	if sequence <= 0 or not _submitted or sequence != _submit_sequence:
		return
	_submitted = false
	_submit_sequence = 0
	_refresh()
	$Content/Status.text = reason

func _unbind() -> void:
	if _session != null:
		if _session.changed.is_connected(_refresh):
			_session.changed.disconnect(_refresh)
		if _session.request_rejected.is_connected(_rejected):
			_session.request_rejected.disconnect(_rejected)
	_session = null

func _exit_tree() -> void:
	_unbind()

func _build_options(options: Array) -> void:
	for child in $Content/Options.get_children():
		$Content/Options.remove_child(child)
		child.queue_free()
	for option in options:
		var row := HBoxContainer.new()
		row.name = "Row" + str(option.index)
		var label := Label.new()
		label.text = str(option.label)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var count := LineEdit.new()
		count.name = "Count"
		count.text = "0"
		count.placeholder_text = "次数"
		count.custom_minimum_size.x = 100
		count.editable = bool(option.available)
		row.add_child(count)
		if option.has("quantity_range"):
			var quantity := LineEdit.new()
			quantity.name = "Quantity"
			quantity.text = str(option.quantity_range[0])
			quantity.tooltip_text = "数量范围 %s — %s" % [option.quantity_range[0], option.quantity_range[1]]
			quantity.custom_minimum_size.x = 100
			quantity.editable = bool(option.available)
			row.add_child(quantity)
		$Content/Options.add_child(row)

func _build_targets() -> void:
	var list: ItemList = $Content/Targets
	list.clear()
	list.select_mode = ItemList.SELECT_SINGLE if _prompt.kind == "location_choice" else ItemList.SELECT_MULTI
	var ids: Array = _prompt.get("cards", _prompt.get("players", _prompt.get("areas", [])))
	for id in ids:
		list.add_item(_target_label(id))
		var index := list.item_count - 1
		list.set_item_metadata(index, id)
		if _prompt.get("required", []).has(id):
			list.select(index, false)
			list.set_item_tooltip(index, "必选")

func _protect_required(index: int, selected: bool) -> void:
	if not selected and _prompt.get("required", []).has($Content/Targets.get_item_metadata(index)):
		$Content/Targets.select(index, false)

func _target_label(id: int) -> String:
	var view: Dictionary = _session.read_match()
	if _prompt.kind == "location_choice":
		for area in view.get("areas", []):
			if area.id == id:
				return str(area.name)
		return "地点"
	for player in view.get("players", []):
		if _prompt.kind == "player_choice" and player.id == id:
			return str(player.player_name)
		if _prompt.kind == "card_choice":
			for zone in ["hand_cards", "discard", "played_cards", "master_skills", "servant_skills"]:
				for card in player.get(zone, []):
					if card.get("id") == id and card.get("visible", false):
						return str(card.get("name", "未公开卡牌"))
	return "未公开卡牌" if _prompt.kind == "card_choice" else "玩家"
