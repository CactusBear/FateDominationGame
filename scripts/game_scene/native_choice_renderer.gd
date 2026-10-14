extends RefCounted

const ChoiceFormatter := preload("res://scripts/ui/text/choice_text.gd")

## 单人与联机共用预置 EffectModal；此处只展示声明，不读取规则。
static func active(board: Control, prompt: Dictionary, pick: Callable, pick_quantity: Callable) -> void:
	if board._effect_modal == null:
		return
	var desc_lbl := board._effect_modal.get_node_or_null("Box/Desc") as Label
	var options_row := board._effect_modal.get_node_or_null("Box/OptionsRow") as VBoxContainer
	var btn_confirm := board._effect_modal.get_node_or_null("Box/ButtonsRow/BtnConfirm") as Button
	var btn_cancel := board._effect_modal.get_node_or_null("Box/ButtonsRow/BtnCancel") as Button
	if desc_lbl == null:
		return
	var eff_name: String = str(prompt.get("label", "未知效果"))
	for button in [btn_confirm, btn_cancel]:
		if button == null: continue
		for key in ["choice_disabled", "active_choice_disabled"]:
			if button.has_meta(key): button.remove_meta(key)
		button.disabled = false
	if btn_cancel:
		btn_cancel.visible = bool(prompt.get("allow_cancel", false))
	if not prompt.get("options", []).is_empty():
		var is_multi: bool = bool(prompt.get("multi", false))
		desc_lbl.text = _cost_line("发动【%s】\n%s" % [eff_name, ("请选择要发动的效果，可多选" if is_multi else "请选择要发动的效果")], prompt)
		if options_row:
			board._clear(options_row)
			options_row.visible = true
			for i in range(prompt.options.size()):
				var opt: Dictionary = prompt.options[i]
				var opt_name: String = str(opt.get("label", "选项%d" % (i + 1)))
				var available: bool = bool(opt.get("available", false))
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
					cb.toggled.connect(func(_checked: bool) -> void: board._refresh_effect_confirm_state(options_row, btn_confirm))
					row.add_child(cb)
					if has_qty and available:
						row.add_child(board._build_quantity_spinbox(opt["quantity_range"], i))
					options_row.add_child(row)
				elif has_qty:
					# 单选带数量：选好数量再点确认，不是点了就走
					var row := HBoxContainer.new()
					row.name = "OptRow_%d" % i
					var lbl := Label.new()
					lbl.text = opt_name
					row.add_child(lbl)
					var spin: SpinBox = board._build_quantity_spinbox(opt["quantity_range"], i)
					row.add_child(spin)
					var confirm_btn := Button.new()
					confirm_btn.text = "确认"
					confirm_btn.disabled = not available
					confirm_btn.pressed.connect(_quantity_pick.bind(pick_quantity,i,weakref(spin)))
					row.add_child(confirm_btn)
					options_row.add_child(row)
				else:
					var opt_btn := Button.new()
					opt_btn.text = opt_name
					opt_btn.custom_minimum_size = Vector2(0, 38)
					opt_btn.disabled = not available
					opt_btn.pressed.connect(pick.bind(i))
					options_row.add_child(opt_btn)
		if btn_confirm:
			btn_confirm.visible = is_multi
			btn_confirm.text = "确认发动"
			board._refresh_effect_confirm_state(options_row, btn_confirm)
	else:
		if options_row:
			options_row.visible = false
			board._clear(options_row)
		if btn_confirm:
			btn_confirm.visible = true
			btn_confirm.disabled = false
			btn_confirm.text = "确认发动"
		desc_lbl.text = _cost_line("发动【%s】" % eff_name, prompt)
	board._open_confirmation_panel(board._effect_modal)

## 只将已声明可用的勾选项转为命令参数；count=一次勾选，不把quantity当次数。
static func active_choices(board: Control, prompt: Dictionary) -> Array:
	var choices: Array = []
	var rows: Control = board._effect_modal.get_node("Box/OptionsRow")
	for i in prompt.options.size():
		var option: Dictionary = prompt.options[i]
		if not option.available or i >= rows.get_child_count(): continue
		var row: Node = rows.get_child(i)
		var check: CheckBox = row.get_node_or_null("Opt_%d" % i)
		if check == null or not check.button_pressed: continue
		var choice := {"index":option.index, "count":1}
		if option.has("quantity_range"):
			var spin: SpinBox = row.get_node_or_null("Qty_%d" % i)
			if spin == null: return []
			spin.apply()
			var quantity: int = int(spin.value)
			if quantity < option.quantity_range[0] or quantity > option.quantity_range[1]: return []
			choice["quantity"] = quantity
		choices.append(choice)
	return choices

static func _cost_line(base: String, prompt: Dictionary) -> String:
	var line := str(prompt.get("cost_text", ""))
	return base if line.is_empty() else base + "\n" + line

static func players(board: Control, prompt: Dictionary, names: Dictionary, submit: Callable, cancel: Callable) -> void:
	var panel: Control = board._player_select_panel
	panel.get_node("Box/Title").text = prompt.label
	var row: Control = panel.get_node("Box/NameRow")
	board._clear(row)
	var confirm: Button = panel.get_node("Box/ButtonsRow/Confirm")
	var decline: Button = panel.get_node("Box/ButtonsRow/Cancel")
	for button in [confirm, decline]:
		if button.has_meta("player_choice_disabled"): button.remove_meta("player_choice_disabled")
		if button.has_meta("choice_disabled"): button.remove_meta("choice_disabled")
	decline.disabled = false
	for connection in confirm.pressed.get_connections(): confirm.pressed.disconnect(connection.callable)
	for connection in decline.pressed.get_connections(): decline.pressed.disconnect(connection.callable)
	var instant: bool = prompt.min == 1 and prompt.max == 1
	confirm.visible = not instant
	confirm.disabled = prompt.min > 0
	decline.visible = bool(prompt.allow_cancel)
	decline.pressed.connect(cancel)
	var selected: Array = []
	for pid in prompt.players:
		var button := Button.new()
		button.custom_minimum_size = Vector2(120,44)
		button.text = str(names.get(pid,"玩家"))
		button.toggle_mode = not instant
		button.pressed.connect(func() -> void:
			if instant:
				submit.call([pid])
				return
			if selected.has(pid): selected.erase(pid)
			else: selected.append(pid)
			confirm.disabled = selected.size() < prompt.min or (prompt.max != -1 and selected.size() > prompt.max)
		)
		row.add_child(button)
	confirm.pressed.connect(func() -> void: submit.call(selected.duplicate()))
	panel.show()
	var vp: Vector2 = board.get_viewport_rect().size
	panel.position = Vector2(maxf(0.0,(vp.x-520.0)*0.5),vp.y*0.2)
	board._raise_modal(panel)

static func choice_card(board: Control, slot: TextureRect, card) -> void:
	if card is Dictionary and card.get("visible",false):
		# Presentation copy only: local choice panels show authorized own faces even when concealed.
		var face: Dictionary = card.duplicate(true)
		face.concealed = false
		board._render_card_face(slot,face,true)
		board._sync_overlay(slot,bool(card.get("concealed",false)),"ConcealOverlay",board.CONCEAL_COLOR,board.CONCEAL_ICON)
	else:
		board._render_card_face(slot,card,true)

static func location(board: Control, label: String, allow_cancel: bool, cancel: Callable) -> void:
	var hint: Control = board.get_node("Hint")
	hint.show()
	var sub: Label = hint.get_node("Sub")
	sub.text = label + " · 请选择目标地点"
	sub.clip_text = true
	sub.offset_right = 380.0 if allow_cancel else 476.0
	var button: Button = hint.get_node("LocationCancel")
	button.visible = allow_cancel
	if not button.pressed.is_connected(cancel):
		for connection in button.pressed.get_connections(): button.pressed.disconnect(connection.callable)
		button.pressed.connect(cancel)

static func _quantity_pick(callback: Callable, index: int, spin_ref: WeakRef) -> void:
	callback.call(index,spin_ref.get_ref())

static func card_confirm(verb: String, option_label: String) -> String:
	return ChoiceFormatter.card_confirm(verb, option_label)
