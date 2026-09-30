extends Node

## 临时探针：轮次变更期间检测"抢跳"（远大于缓动正常位移的跳变），阈值 50px。

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	await get_tree().process_frame
	board.set_process(false)   # 隔离动画本身
	await get_tree().process_frame
	var row := board.get_node("Rivals") as Control
	var rules: Array = board._ordered_ids()
	GameProgress.current_player_id = int(rules.back())
	board.refresh_all_ui()
	await get_tree().create_timer(0.95).timeout
	ChangePlOrder.new().exec(null, BaseNumber.new(-1))
	GameProgress.current_round += 1
	GameProgress.current_player_id = int(board._ordered_ids()[0])
	board.refresh_all_ui()
	var prev: Dictionary = {}
	var jumps: Array = []
	for i in range(130):
		await get_tree().process_frame
		for c in row.get_children():
			var id := int(c.get_meta("turn_order_player_id", -1))
			var x := (c as Control).position.x
			if prev.has(id):
				var d: float = absf(x - float(prev[id]))
				if d > 50.0:
					jumps.append("f%03d id%d jumped %.1f (%.1f -> %.1f)" % [i, id, d, prev[id], x])
			prev[id] = x
	print("=== ROUND JUMPS(%d):" % jumps.size())
	for j in jumps:
		print(j)
	print("DONE")
	get_tree().quit()
