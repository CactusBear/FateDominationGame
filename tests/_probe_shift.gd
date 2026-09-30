extends Node

## 临时探针：逐帧记录传送带期间所有卡片 position，最后统一打印（避免逐帧 print 掉帧）。
## 用于定位"传送带上所有玩家信息一瞬间错位"。

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame
	var row := board.get_node("Rivals") as Control
	var rules: Array = board._ordered_ids()
	GameProgress.current_player_id = int(rules[1])
	board.refresh_all_ui()
	var prev: Dictionary = {}
	var jumps: Array = []
	var frames := 0
	for i in range(90):
		await get_tree().process_frame
		frames += 1
		for c in row.get_children():
			var id := int(c.get_meta("turn_order_player_id", -1))
			var x := (c as Control).position.x
			if prev.has(id):
				var d: float = absf(x - float(prev[id]))
				if d > 12.0:
					jumps.append("f%02d id%d jumped %.1f  (%.1f -> %.1f)" % [i, id, d, prev[id], x])
			prev[id] = x
	print("=== JUMPS(%d) over %d frames:" % [jumps.size(), frames])
	for j in jumps:
		print(j)
	print("DONE")
	get_tree().quit()
