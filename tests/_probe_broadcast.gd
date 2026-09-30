extends Node

## 临时探针：非 headless 下构造一场战斗并弹出胜利播报，截图到 runtime_reports/broadcast_overlay.png
## 供原生读图核对播报层无异常色块/布局、分块内容与数据一致。运行：不加 --headless。

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("HEADLESS 无画面，跳过截图")
		get_tree().quit()
		return
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame
	# 冻结 AI 推进：手动构造战斗，不让界面自动驱动整局
	board._turn_read_remaining = 1e9
	# 非 headless 帧序抖动时首帧 _process 可能未及注册，这里显式补齐，保证会暂停
	if not GameProgress.has_battle_broadcast_consumer():
		board._broadcast_registered = true
		GameProgress.register_battle_broadcast_consumer(board)
	for area: BaseMapArea in MapData.areas:
		area._events.clear()
		for loc in area._locations:
			loc._players.clear()
	# 深山町：玩家 0 威力 20 胜玩家 1 威力 5
	for id in [0, 1]:
		SetLocation.new().exec(MapData.miyama._locations[id], id, false, true)
	GameDataManager.get_player_data(0).power.number = 20
	GameDataManager.get_player_data(1).power.number = 5
	# 新都：玩家 2、3 威力同为 10 → 平局
	for i in range(2):
		SetLocation.new().exec(MapData.shinto._locations[i], 2 + i, false, true)
	GameDataManager.get_player_data(2).power.number = 10
	GameDataManager.get_player_data(3).power.number = 10
	# 进入战斗阶段结算
	GameProgress.current_phase_index = 3
	GameProgress.has_battle_resolved = false
	GameLog.set_context(GameProgress.current_round, "battle")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE])
	GameProgress.end_phase()
	print("pending=", GameProgress.is_battle_broadcast_pending())
	# 入场动画中途一张（标题已出、战场块淡入中）
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	await _shot("broadcast_mid")
	# 放完后一张（全屏播报 + 「继续（已确认 n/7）」按钮，AI 确认中）
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	await _shot("broadcast_overlay")
	print("DONE")
	get_tree().quit()


func _shot(name: String) -> void:
	var dir := ProjectSettings.globalize_path("res://tests/runtime_reports")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("SCREENSHOT ", path)
