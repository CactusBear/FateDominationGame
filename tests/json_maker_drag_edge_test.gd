extends Node

# 真实窗口拖放：从积木选择区拖取值积木，放在参数按钮左上边缘。
var failures:Array = []

func check(ok:bool, label:String) -> void:
	print("DRAG ", label, " ", ok)
	if not ok:
		failures.append(label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var ui = load("res://json_maker/json_maker.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame
	ui._clear(ui.palette_box)
	ui._clear(ui.script_box)
	var source:Control = ui._palette_block({"kind": "op", "func": "is_true_name_released"})
	ui.palette_box.add_child(source)
	var slots := [{"s": "lit", "v": null}]
	var slot:Control = ui._slot_widget(slots, 0, "条件", "bool", "", true)
	ui.script_box.add_child(slot)
	ui.palette_scroll.scroll_vertical = 0
	ui.script_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var picker:Control = slot.find_child("SlotPicker", true, false)
	check(picker != null, "parameter picker exists")
	check(slot.size.x >= 96 and slot.size.y >= 36, "slot has enlarged hitbox")
	if DisplayServer.get_name() != "headless":
		var start:Vector2 = source.get_global_rect().get_center()
		var end:Vector2 = picker.get_global_rect().position + Vector2(3, 3)
		check(get_viewport().get_visible_rect().has_point(start) and get_viewport().get_visible_rect().has_point(end), "both drag endpoints onscreen")
		Input.warp_mouse(start)
		await get_tree().process_frame
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.position = start
		press.global_position = start
		press.pressed = true
		Input.parse_input_event(press)
		await get_tree().process_frame
		for i in range(1, 21):
			var motion := InputEventMouseMotion.new()
			motion.position = start.lerp(end, float(i) / 20.0)
			motion.global_position = motion.position
			motion.relative = (end - start) / 20.0
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
			Input.parse_input_event(motion)
			await get_tree().process_frame
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.position = end
		release.global_position = end
		release.pressed = false
		Input.parse_input_event(release)
		await get_tree().process_frame
		await get_tree().process_frame
		check(slots[0] is Dictionary and str(slots[0].get("s", "")) == "block", "real drag fills slot at picker edge")
	ui.queue_free()
	await get_tree().process_frame
	print("RESULT checks=", 4 if DisplayServer.get_name() != "headless" else 2, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
