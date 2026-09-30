extends Node

## 临时探针：横幅淡入淡出 + 节奏自适应——慢节奏恢复基准时长、快节奏连切时缩短。

func _ready() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://tests/runtime_reports")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join("banner_" + name + ".png"))

func run() -> void:
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	await get_tree().process_frame
	board.set_process(false)
	await get_tree().process_frame
	var rules: Array = board._ordered_ids()
	var log: Array = []
	# 1) 慢节奏：等横幅演完再切
	GameProgress.current_player_id = int(rules[0])
	board.refresh_all_ui()
	await get_tree().create_timer(1.8).timeout
	log.append("slow      pace=%.3f visible=%s alpha=%.2f" % [board._banner_pace, str(board._banner.visible), board._banner.modulate.a])
	# 2) 快节奏：连续切换，不等横幅演完
	for k in [1, 2, 3]:
		GameProgress.current_player_id = int(rules[k])
		board.refresh_all_ui()
		await get_tree().create_timer(0.05).timeout
		log.append("fast%d     pace=%.3f visible=%s alpha=%.2f" % [k, board._banner_pace, str(board._banner.visible), board._banner.modulate.a])
		await shot("fast%d" % k)
		await get_tree().create_timer(0.30).timeout
		await shot("fast%d_settled" % k)
	# 3) 再慢一次：应恢复基准
	await get_tree().create_timer(1.8).timeout
	GameProgress.current_player_id = int(rules[4])
	board.refresh_all_ui()
	log.append("recovered pace=%.3f visible=%s alpha=%.2f" % [board._banner_pace, str(board._banner.visible), board._banner.modulate.a])
	for l in log:
		print(l)
	print("DONE")
	get_tree().quit()
