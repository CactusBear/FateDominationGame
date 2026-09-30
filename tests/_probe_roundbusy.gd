extends Node

## 临时探针：轮次变更动画期间读条应冻结、动画代际不应被新动画顶掉（AI 不应推进）。

func _ready() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://tests/runtime_reports")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join("busy_" + name + ".png"))

func run() -> void:
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame
	var rules: Array = board._ordered_ids()
	GameProgress.current_player_id = int(rules.back())
	board.refresh_all_ui()
	await get_tree().create_timer(0.95).timeout
	ChangePlOrder.new().exec(null, BaseNumber.new(-1))
	GameProgress.current_round += 1
	GameProgress.current_player_id = int(board._ordered_ids()[0])
	board.refresh_all_ui()
	var gen0: int = board._rival_anim_generation
	var logs: Array = []
	for i in range(140):
		await get_tree().process_frame
		if i % 10 == 0:
			logs.append("f%03d busy=%s read=%.3f genShift=%d actor=%d round=%d" % [i, str(board._rival_anim_busy), board._turn_read_remaining, board._rival_anim_generation - gen0, GameProgress.current_player_id, GameProgress.current_round])
		if i in [12, 40, 75, 100, 116, 128]:
			await shot("%03d" % i)
	for l in logs:
		print(l)
	print("DONE")
	get_tree().quit()
