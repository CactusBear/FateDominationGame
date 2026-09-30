extends Node
var checks := 0
var failures:Array = []

func check(ok:bool, text:String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
	print("CHECK ", text, " ", ok)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var ui = load("res://json_maker/json_maker.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame
	var source:Array = [ui._new_op("get_current_round")]
	ui.context_target = {"node": source[0], "where": {"list": source, "index": 0}}
	ui._context_pressed(1)
	check(source.size() == 1, "copy does not insert a clone")
	check(not ui.dirty, "copy does not mark document dirty")
	check(ui.clipboard is Dictionary and not is_same(ui.clipboard, source[0]), "copy stores independent clipboard snapshot")
	var dest:Array = []
	var zone = ui._gap(dest, 0, "funcs", true)
	ui.add_child(zone)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	zone.gui_input.emit(ev)
	check(ui.context_menu.get_item_index(2) >= 0, "placeholder right click offers paste")
	if ui.context_menu.get_item_index(2) >= 0:
		ui.context_menu.hide()
		ui._context_pressed(2)
		check(dest.size() == 1 and dest[0].func == "get_current_round", "paste inserts at placeholder")
		check(not is_same(dest[0], ui.clipboard), "paste creates independent node")
	var stack = ui._stack_view(source, "funcs")
	ui.add_child(stack)
	check(stack.get_child(stack.get_child_count() - 1).get_child_count() > 0, "nonempty stack retains visible paste placeholder")
	ui._open_context(source[0], {"list": source, "index": 0}, Vector2.ZERO)
	check(ui.context_menu.get_item_index(2) < 0, "block menu no longer offers paste")
	ui.context_menu.hide()
	if DisplayServer.get_name() != "headless":
		ui._new_card()
		ui._add_effect()
		await get_tree().process_frame
		ui.effects_view[0].lists.funcs.append(ui._fresh_copy(ui.clipboard))
		ui._paint_scripts()
		await get_tree().process_frame
		await get_tree().process_frame
		var target:Control = null
		for control in ui.script_box.find_children("*", "Control", true, false):
			if control.has_meta("drop") and control.get_meta("drop").get("context", "") == "funcs" and control.get_meta("drop").get("index", -1) == 1:
				target = control
		check(target != null, "rendered stack has paste destination")
		if target != null:
			var at:Vector2 = target.get_global_rect().get_center()
			Input.warp_mouse(at)
			for pressed in [true, false]:
				var click := InputEventMouseButton.new()
				click.position = at
				click.global_position = at
				click.button_index = MOUSE_BUTTON_RIGHT
				click.pressed = pressed
				Input.parse_input_event(click)
				await get_tree().process_frame
			check(ui.context_menu.visible and ui.context_menu.get_item_index(2) >= 0, "actual right click opens paste menu")
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("clipboard-placeholder.png"))
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
