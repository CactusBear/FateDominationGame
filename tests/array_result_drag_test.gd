extends Node

# 数组结果按索引展开，整组变量及单项均能直接拖入参数，并保持编解码语义。
var failures:Array = []
var checks := 0

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func slot_target(root:Node, holder:Array, key:int) -> Control:
	for node in root.find_children("*", "PanelContainer", true, false):
		if node.has_meta("drop"):
			var drop:Dictionary = node.get_meta("drop")
			if drop.get("kind") == "slot" and is_same(drop.get("holder"), holder) and drop.get("key") == key:
				return node
	return null

func drag(from:Vector2, to:Vector2) -> void:
	Input.warp_mouse(from)
	await get_tree().process_frame
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	down.global_position = from
	get_tree().root.push_input(down, true)
	await get_tree().process_frame
	for step in 1 + 8:
		var motion := InputEventMouseMotion.new()
		motion.position = from.lerp(to, float(step) / 8.0)
		motion.global_position = motion.position
		motion.relative = (to - from) / 8.0
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_tree().root.push_input(motion, true)
		await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = to
	up.global_position = to
	get_tree().root.push_input(up, true)
	await get_tree().process_frame

func run() -> void:
	var ui = load("res://json_maker/json_maker.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame
	check(str(ui.maker.operation_of("merge_arrays").get("returns")) == "Array", "array return reflected from operation")
	check(str(ui.maker.operation_of("get_current_round").get("returns")) != "Array", "non-array result is not expanded")
	ui._new_card()
	ui._add_effect()
	var view:Dictionary = ui.effects_view[0]
	var source:Dictionary = ui._new_op("merge_arrays")
	var consumer:Dictionary = ui._new_op("is_in_array")
	view.lists.funcs.clear()
	view.lists.funcs.append(source)
	view.lists.funcs.append(consumer)
	ui._paint_scripts()
	await get_tree().process_frame
	var toggles:Array = ui.script_box.find_children("*", "Button", true, false).filter(func(b): return b.text == "展开数组")
	check(toggles.size() == 1, "array result has expand button")
	var variable:int = int(source.get("tag_var", -1))
	check(variable >= 0, "array result exposes a draggable variable")
	if not toggles.is_empty():
		toggles[0].pressed.emit()
	await get_tree().process_frame
	var items:Array = ui.script_box.find_children("ArrayItemTag_*", "PanelContainer", true, false)
	check(items.size() == 1, "expanding shows first indexed item")
	var add:Array = ui.script_box.find_children("*", "Button", true, false).filter(func(b): return b.text == "＋ 下一项")
	if not add.is_empty():
		add[0].pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	items = ui.script_box.find_children("ArrayItemTag_*", "PanelContainer", true, false)
	check(items.size() == 2, "can add next index without guessing array length " + str(items.size()) + " state=" + str(source.get("array_items", -1)))
	var target := slot_target(ui.script_box, consumer.params, 0)
	check(target != null, "consumer parameter has a drop target")
	if target != null:
		var picker := target.find_child("SlotPicker", true, false)
		check(picker != null and ui._can_drop_on(Vector2.ZERO, {"new": {"kind": "array_item", "variable": variable, "index": 1}}, picker), "dropdown button accepts indexed item drag")
		if DisplayServer.get_name() != "headless" and picker != null:
			get_window().size = Vector2i(1600, 900)
			ui.script_scroll.ensure_control_visible(items[1])
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var shot := "res://reports/array_result_expanded.png"
			get_viewport().get_texture().get_image().save_png(shot)
			check(FileAccess.file_exists(shot), "expanded array screenshot captured")
			await drag(items[1].get_global_rect().get_center(), picker.get_global_rect().get_center())
			check(consumer.params[0].get("s") == "block", "physical drag from indexed tag onto parameter")
		if DisplayServer.get_name() == "headless":
			ui._drop_on(Vector2.ZERO, {"new": {"kind": "array_item", "variable": variable, "index": 1}}, picker)
	check(consumer.params[0].get("s") == "block" and consumer.params[0].b.func == "get_card_by_index_fr_arr", "drop constructs existing index operation")
	var arr_index:int = ui._param_index(ui.maker.operation_of("is_in_array"), "arr")
	target = slot_target(ui.script_box, consumer.params, arr_index)
	if target != null:
		if DisplayServer.get_name() != "headless":
			var tags:Array = ui.script_box.find_children("ResultTag", "PanelContainer", true, false)
			var matching:Array = tags.filter(func(t): return str(t.get_child(0).get("text")).ends_with(" " + str(variable)))
			check(not matching.is_empty(), "source result tag still exists after first drag")
			if matching.is_empty():
				print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
				get_tree().quit(1)
				return
			var variable_tag = matching.front()
			ui.script_scroll.ensure_control_visible(variable_tag)
			await get_tree().process_frame
			await drag(variable_tag.get_global_rect().get_center(), target.find_child("SlotPicker", true, false).get_global_rect().get_center())
			check(consumer.params[arr_index].get("s") == "var", "physical whole-variable drag onto parameter")
		else:
			ui._drop_on(Vector2.ZERO, {"new": {"kind": "var_ref", "slot": {"s": "var", "n": variable}}}, target)
	check(consumer.params[arr_index].get("s") == "var" and int(consumer.params[arr_index].n) == variable, "whole array variable drops directly into parameter")
	var output:Array = ui.codec.encode_effect_list(view.lists.funcs)
	check(output.size() == 3 and output[0].get("var_index") == variable and output[1].func_name == "get_card_by_index_fr_arr" and output[1].parameters[0] == 1 and output[1].parameters[1].self_var == variable and output[2].parameters[0].self_var == output[1].var_index, "encoded order reads array then indexed element " + JSON.stringify(output))
	check(GetCardByIndexFrArr.new().exec(1, ["first", "second"]) == "second", "runtime index operation returns chosen element")
	if DisplayServer.get_name() != "headless":
		var mode_groups:Array = ui._slot_groups("String", "battle_mode", "set_battle_result:mode", view.effect)
		ui._open_search_popup(ui.script_box, mode_groups, func(_v): pass, true, Callable(), ui._all_field_groups)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var picker_shot := "res://reports/legal_parameter_dropdown.png"
		get_viewport().get_texture().get_image().save_png(picker_shot)
		check(FileAccess.file_exists(picker_shot), "legal parameter dropdown screenshot captured")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
