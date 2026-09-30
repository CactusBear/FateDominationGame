extends Node

## 临时探针：连续多次换人（间隔短于动画时长，强制打断），逐帧检测位置跳变与顺序错乱。

func _ready() -> void:
	call_deferred("run")

func _ids(row: Control) -> Array:
	var r: Array = []
	for c in row.get_children():
		r.append(int(c.get_meta("turn_order_player_id", -1)))
	return r

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://tests/runtime_reports")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join("multi_" + name + ".png"))

func run() -> void:
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame
	var row := board.get_node("Rivals") as Control
	var rules: Array = board._ordered_ids()
	var prev: Dictionary = {}
	var jumps: Array = []
	var order_log: Array = []
	var k := 1
	for i in range(150):
		await get_tree().process_frame
		if i % 20 == 5:
			GameProgress.current_player_id = int(rules[k % rules.size()])
			board.refresh_all_ui()
			order_log.append("f%03d switch->%d order=%s" % [i, int(rules[k % rules.size()]), str(_ids(row))])
			await shot("sw%02d_after" % k)
			k += 1
		elif i % 20 == 12:
			await shot("sw%02d_mid" % (k - 1))
		for c in row.get_children():
			var id := int(c.get_meta("turn_order_player_id", -1))
			var x := (c as Control).position.x
			if prev.has(id):
				var d: float = absf(x - float(prev[id]))
				if d > 12.0:
					jumps.append("f%03d id%d jumped %.1f (%.1f -> %.1f)" % [i, id, d, prev[id], x])
			prev[id] = x
	print("=== SWITCHES:")
	for o in order_log:
		print(o)
	print("=== JUMPS(%d):" % jumps.size())
	for j in jumps:
		print(j)
	print("DONE")
	get_tree().quit()
