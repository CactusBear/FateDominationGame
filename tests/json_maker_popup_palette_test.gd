extends Node

var failures:Array = []
var checks := 0

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)


# 兜底那一项：它在候选列表的最后，展开的其他字段挂在它下面。
func more_row(ui) -> TreeItem:
	var found:TreeItem = null
	var root_item:TreeItem = ui.tp_tree.get_root()
	var scan:TreeItem = root_item.get_first_child() if root_item != null else null
	while scan != null:
		if scan.has_meta("more"):
			found = scan
		scan = scan.get_next()
	return found


func _ready() -> void:
	var ui = load("res://json_maker/json_maker.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		# 无弹窗窗口：只验证候选拼接与折叠；真实鼠标选择在非 headless 分支验证。
		ui.tp_groups = ui._slot_groups("String", "", "show_message:message", null)
		ui.tp_more = func(): return ui._slot_more_groups("String", "show_message:message", null)
		ui._fill_time_point_tree()
		ui._toggle_more_groups()
	else:
		ui._open_search_popup(ui.search, ui._slot_groups("String", "", "show_message:message", null), func(_value): pass, true, Callable(), func(): return ui._slot_more_groups("String", "show_message:message", null))
		await get_tree().process_frame
		var tree:Tree = ui.tp_tree
		var more:TreeItem = more_row(ui)
		check(more != null, "兜底那一项在候选列表里")
		check(more != null and more.get_next() == null, "兜底那一项在列表最后")
		if more != null:
			tree.scroll_to_item(more, true)
			await get_tree().process_frame
			var at:Vector2 = Vector2(ui.tp_popup.position) + tree.get_global_rect().position + tree.get_item_area_rect(more).get_center()
			Input.warp_mouse(at)
			await get_tree().process_frame
			for pressed in [true, false]:
				var event := InputEventMouseButton.new()
				event.position = at
				event.global_position = at
				event.button_index = MOUSE_BUTTON_LEFT
				event.pressed = pressed
				Input.parse_input_event(event)
				await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var row_after:TreeItem = more_row(ui)
	check(ui.tp_more_open, "点兜底那一项展开其他字段")
	check(row_after != null and row_after.get_next() == null, "展开后兜底那一项仍在列表最后")
	check(row_after != null and row_after.get_child_count() > 0, "其他字段挂在兜底那一项下面")
	var heads_ok := row_after != null and row_after.get_child_count() > 0
	if row_after != null:
		for child in row_after.get_children():
			if not str((child as TreeItem).get_text(0)).begins_with("其他 · "):
				heads_ok = false
	check(heads_ok, "展开的都是其他 · 分组")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://json_maker_more_checked.png")
	# 再点一次收起
	ui._toggle_more_groups()
	var row_collapsed:TreeItem = more_row(ui)
	check(not ui.tp_more_open and row_collapsed != null and row_collapsed.get_child_count() == 0, "再点一次收起其他字段")
	check(row_collapsed != null and row_collapsed.get_next() == null and ui.tp_more.is_valid(), "收起后兜底那一项还在列表最后")
	ui.tp_popup.hide()
	# 选择区里的积木：空位自己就能点开候选，不再有单独的「参数」按钮
	ui.search.text = "edit_magic"
	ui._fill_palette()
	var slot_buttons:Array = ui.palette_box.find_children("PaletteSlot", "Button", true, false)
	var preview_nodes:Array = ui.palette_box.find_children("PaletteParamPreview", "VBoxContainer", true, false)
	var param_toggles:Array = ui.palette_box.find_children("PaletteParamToggle", "Button", true, false)
	check(not slot_buttons.is_empty(), "选择区里积木的空位是可点入口 " + str(slot_buttons.size()))
	check(preview_nodes.is_empty() and param_toggles.is_empty(), "没有单独的参数按钮或参数面板")
	check((slot_buttons[0] as Button).mouse_filter == Control.MOUSE_FILTER_STOP, "空位入口保留鼠标响应")
	var before_data = ui.data.duplicate(true) if ui.data is Dictionary else null
	var before_dirty:bool = ui.dirty
	# 真实点击：在积木区里点这一格应该弹出候选（用户报的「点参数没反应」）
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		var slot_at:Vector2 = (slot_buttons[0] as Button).get_global_rect().get_center()
		Input.warp_mouse(slot_at)
		await get_tree().process_frame
		for slot_pressed in [true, false]:
			var slot_event := InputEventMouseButton.new()
			slot_event.position = slot_at
			slot_event.global_position = slot_at
			slot_event.button_index = MOUSE_BUTTON_LEFT
			slot_event.pressed = slot_pressed
			Input.parse_input_event(slot_event)
			await get_tree().process_frame
		await get_tree().process_frame
		check(ui.tp_popup.visible, "真实点击选择区空位能打开候选菜单")
		ui.tp_popup.hide()
		# 按住拖动：空位仍然把整块积木拖出去，而不是弹菜单
		Input.warp_mouse(slot_at)
		await get_tree().process_frame
		var drag_press := InputEventMouseButton.new()
		drag_press.position = slot_at
		drag_press.global_position = slot_at
		drag_press.button_index = MOUSE_BUTTON_LEFT
		drag_press.pressed = true
		Input.parse_input_event(drag_press)
		await get_tree().process_frame
		for drag_step in 8:
			var drag_move := InputEventMouseMotion.new()
			drag_move.position = slot_at + Vector2(6 * (drag_step + 1), 3 * (drag_step + 1))
			drag_move.global_position = drag_move.position
			drag_move.relative = Vector2(6, 3)
			drag_move.button_mask = MOUSE_BUTTON_MASK_LEFT
			Input.parse_input_event(drag_move)
			await get_tree().process_frame
		check(ui.get_viewport().gui_is_dragging(), "在选择区空位上按住拖动仍然拖出积木")
		var drag_release := InputEventMouseButton.new()
		drag_release.position = slot_at + Vector2(48, 24)
		drag_release.global_position = drag_release.position
		drag_release.button_index = MOUSE_BUTTON_LEFT
		drag_release.pressed = false
		Input.parse_input_event(drag_release)
		await get_tree().process_frame
		await get_tree().process_frame
		check(not ui.tp_popup.visible, "拖动空位不会弹出候选菜单")
	(slot_buttons[0] as Button).pressed.emit()
	check(ui.tp_groups.size() > 0, "点空位就列出候选")
	check(ui.tp_more.is_valid(), "空位的候选带显示其他所有字段的兜底")
	if ui.tp_pick.is_valid():
		ui.tp_pick.call("hello")
	check(ui.data == before_data and ui.dirty == before_dirty, "选择区选候选不改动卡牌")
	check(str((slot_buttons[0] as Button).text).find("hello") != -1, "选择区选中的值显示在空位上 " + str((slot_buttons[0] as Button).text))
	ui.tp_popup.hide()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://json_maker_palette_checked.png")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
