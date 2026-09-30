extends Node

## 临时探针：轮次变更期间连续截帧，用于原生视觉检查"重叠"。

func _ready() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://tests/runtime_reports")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join("round_" + name + ".png"))

func run() -> void:
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	await get_tree().process_frame
	board.set_process(false)   # 停 AI 推进，只看轮次变更动画本身
	await get_tree().process_frame
	var rules: Array = board._ordered_ids()
	# 模拟最后一个玩家行动完（当前行动者 = 末位）
	GameProgress.current_player_id = int(rules.back())
	board.refresh_all_ui()
	await get_tree().create_timer(0.95).timeout
	# 触发轮次变更
	ChangePlOrder.new().exec(null, BaseNumber.new(-1))
	GameProgress.current_round += 1
	GameProgress.current_player_id = int(board._ordered_ids()[0])
	board.refresh_all_ui()
	var marks := {0: "a_f00", 12: "b_f12", 24: "c_f24", 36: "d_f36", 44: "e_f44", 56: "f_f56", 68: "g_f68", 80: "h_f80", 92: "i_f92", 104: "j_f104", 118: "k_f118"}
	for i in range(124):
		await get_tree().process_frame
		if marks.has(i):
			await shot(marks[i])
	print("DONE")
	get_tree().quit()
