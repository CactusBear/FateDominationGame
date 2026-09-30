extends Node

var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok:
		failures.append(label)

func _ready() -> void:
	call_deferred("run")

func click(button: Button) -> void:
	if DisplayServer.get_name() == "headless":
		button.pressed.emit()
	else:
		var point := button.get_global_rect().get_center()
		get_viewport().warp_mouse(point)
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = point
			event.global_position = point
			event.pressed = pressed
			get_viewport().push_input(event, true)
			await get_tree().process_frame

func run() -> void:
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	await get_tree().process_frame
	board.set_process(false)
	var button := board.get_node_or_null("Top/LogButton") as Button
	check(button != null and button.is_visible_in_tree(), "log button visible on board")
	if button != null:
		check(board.get_rect().encloses(button.get_global_rect()), "log button inside viewport")
		check(not button.get_global_rect().intersects(board.get_node("Top/BoardButton").get_global_rect()), "log and scoreboard buttons do not overlap")
		var before := GameLog.query({}, null, -1).size()
		await click(button)
		var modal: Control = board.get_node("LogBrowser")
		var text: RichTextLabel = modal.get_node("Panel/Entries")
		check(modal.visible, "click opens log")
		check(not text.text.is_empty() and text.text.contains("回合"), "real game history shown")
		check(not text.bbcode_enabled, "log content displayed as plain text")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/battle_log_open.png")
		await click(modal.get_node("Panel/Close"))
		check(not modal.visible, "close button closes log")
		await click(button)
		check(modal.visible, "log can reopen")
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		get_viewport().push_input(escape, true)
		await get_tree().process_frame
		check(not modal.visible, "escape closes log")
		check(GameLog.query({}, null, -1).size() == before, "viewing log has no game side effects")
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
