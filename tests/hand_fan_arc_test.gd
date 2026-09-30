extends Node

var board: Control
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func _ready() -> void:
	call_deferred("run")

func settle() -> void:
	for i in range(90):
		await get_tree().process_frame
		board._update_held_cards(1.0 / 60.0)

func hand_slots() -> Array:
	var slots: Array = board.get_node("Hand").get_children().filter(func(s): return s.get_meta("held_group", "") == "hand")
	slots.sort_custom(func(a, b): return (a.get_meta("rest_position") as Vector2).x < (b.get_meta("rest_position") as Vector2).x)
	return slots

func verify_fan() -> void:
	var slots := hand_slots()
	var left: Vector2 = slots.front().get_meta("rest_position")
	var right: Vector2 = slots.back().get_meta("rest_position")
	check(is_equal_approx(left.y, right.y), "fan edges share height")
	if slots.size() > 2:
		check((slots[slots.size() / 2].get_meta("rest_position") as Vector2).y < left.y - 1.0, "fan center rises above edges")
	var previous := -INF
	for slot: Control in slots:
		check(slot.rotation >= previous, "angles increase from left to right")
		check(absf(slot.rotation - float(slot.get_meta("rest_rotation"))) < 0.002, "rotation settles with layout")
		previous = slot.rotation

func run() -> void:
	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	add_child(board)
	board.set_process(false)
	await get_tree().process_frame
	get_viewport().warp_mouse(Vector2(10, 400))
	var pl: Dictionary = GameDataManager.get_player_data(GameData.player_id)
	var model = pl.hand_cards.front()
	pl.hand_cards.clear()
	for i in range(5):
		pl.hand_cards.append(CloneObject.new().exec(model))
	board.refresh_all_ui()
	await settle()
	verify_fan()
	pl.hand_cards.remove_at(1)
	pl.hand_cards.remove_at(2)
	board.refresh_all_ui()
	await settle()
	verify_fan()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/hand_fan_arc.png")
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
