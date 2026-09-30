extends Node

## 临时探针：逐帧打印换人交接时顺位卡的 position 与行顺序，定位"闪烁"。
## 不 set_process(false)，走真实刷新路径。

func _ready() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://tests/runtime_reports")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join("handoff_" + name + ".png"))

func _ids(row: Control) -> Array:
	var r: Array = []
	for c in row.get_children():
		r.append(int(c.get_meta("turn_order_player_id", -1)))
	return r

func _dump(row: Control, tag: String) -> void:
	var line := "%s order=%s" % [tag, str(_ids(row))]
	for c in row.get_children():
		line += " |%d %.0f,%.0f" % [int(c.get_meta("turn_order_player_id", -1)), (c as Control).position.x, (c as Control).position.y]
	print(line)

func run() -> void:
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame
	var row := board.get_node("Rivals") as Control
	board._fade_debug = true
	var rules: Array = board._ordered_ids()
	var next_id := int(rules[1])
	print("=== rules=", rules, " next=", next_id)
	_dump(row, "BEFORE      ")
	await shot("a_before")
	GameProgress.current_player_id = next_id
	board.refresh_all_ui()
	_dump(row, "AFTER-REFR  ")
	var marks := {0: "b_f00", 8: "c_f08", 16: "d_f16", 19: "e_f19", 21: "f_f21", 26: "g_f26", 32: "h_f32", 34: "i_f34", 44: "j_f44"}
	for i in range(45):
		await get_tree().process_frame
		if marks.has(i):
			_dump(row, "f%02d        " % i)
			await shot(marks[i])
	print("DONE")
	get_tree().quit()
