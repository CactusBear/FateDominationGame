extends Node

var failures: Array[String] = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func _card(row: Control, id: int) -> Control:
	for child in row.get_children():
		if int(child.get_meta("turn_order_player_id", -1)) == id:
			return child as Control
	return null

## 当前有多少对顺位卡的矩形互相相交（任何一对重叠都算问题）
func _overlap_pairs(row: Control) -> int:
	var cards: Array = []
	for child in row.get_children():
		cards.append(child as Control)
	var n := 0
	for i in cards.size():
		for j in range(i + 1, cards.size()):
			var a := cards[i] as Control
			var b := cards[j] as Control
			if a.get_global_rect().intersects(b.get_global_rect()):
				n += 1
	return n

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://tests/runtime_reports")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))

func run() -> void:
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	board.set_process(false)
	await get_tree().process_frame
	var row := board.get_node("Rivals") as Control
	var rules: Array = board._ordered_ids()
	var first := int(rules[0])
	var second := int(rules[1])
	var last := int(rules.back())
	# 模拟最后玩家行动完：当前行动者 = 末位，顶栏变为 [last, first, ...]
	GameProgress.current_player_id = last
	board.refresh_all_ui()
	await get_tree().create_timer(board.GOLD_FRAME_FLY_SECONDS + board.RIVAL_SHIFT_SECONDS + 0.2).timeout
	# 触发轮次变更：order 顺时针轮转（原第二位成为首位）+ 回合号 +1 + 新首位行动者
	ChangePlOrder.new().exec(null, BaseNumber.new(-1))
	GameProgress.current_round += 1
	GameProgress.current_player_id = int(board._ordered_ids()[0])
	board.refresh_all_ui()
	await get_tree().process_frame
	var last_card := _card(row, last)
	var first_card := _card(row, first)
	var second_card := _card(row, second)
	check(last_card != null and first_card != null and second_card != null, "fixture players present")
	# 阶段1：整体左移补位，最后行动者（last）从队首左出绕到队尾
	check(board._rival_shift_tween != null, "round change starts conveyor stage")
	var last_min_x := last_card.position.x
	var first_min_x := first_card.position.x
	var stage1_overlaps := 0
	for i in range(32):
		await get_tree().process_frame
		last_min_x = minf(last_min_x, last_card.position.x)
		first_min_x = minf(first_min_x, first_card.position.x)
		stage1_overlaps += _overlap_pairs(row)
		# 真实对局每 0.5 秒全屏刷新一次：动画中途也必须不重排、不重叠
		if i % 8 == 4:
			board.refresh_all_ui()
		if i == 10:
			await shot("round_change_stage1")
	check(last_min_x < 0.0, "last actor exits left during stage 1")
	check(first_min_x < 1.0, "first-of-round slides to left edge during stage 1")
	check(stage1_overlaps == 0, "no card overlaps during stage 1")
	# 阶段1 结束：首位在最左
	await get_tree().create_timer(board.RIVAL_SHIFT_SECONDS + 0.1).timeout
	check(first_card.position.x < 1.0, "first-of-round reaches left edge after stage 1")
	# 阶段2：首位下抽离开横列，其余左移补位，首位从下方绕到末位
	var drop_observed := false
	var drop_shot := false
	var stage2_overlaps := 0
	for i in range(100):
		await get_tree().process_frame
		if first_card.position.y > 1.0:
			drop_observed = true
		# 抽到过半时再截，起步那一帧看不出动作
		if not drop_shot and first_card.position.y > first_card.size.y * board.ROUND_DROP_RATIO * 0.55:
			drop_shot = true
			await shot("round_change_stage2_drop")
		stage2_overlaps += _overlap_pairs(row)
		if i % 12 == 5:
			board.refresh_all_ui()
	check(drop_observed, "first-of-round drops out of the row")
	check(stage2_overlaps == 0, "no card overlaps during stage 2")
	# 阶段2 结束：第二位成为首位，原首位落到末位
	await get_tree().create_timer(board.ROUND_DROP_SECONDS * 3.0 + board.ROUND_SLIDE_SECONDS + 0.3).timeout
	check(second_card.position.x < 1.0, "second player becomes first after round change")
	check(first_card.position.y < 0.5, "first-of-round settles back into the row")
	check(first_card.position.x > second_card.position.x, "first-of-round lands at right tail")
	check(row.get_child(0) == second_card, "new first player sits at left edge")
	# 规则顺位与显示一致：原第二位成为首位
	var rotated: Array = board._ordered_ids()
	check(rotated[0] == second and rotated.back() == first, "rule order rotates clockwise (second becomes first)")
	await shot("round_change_end")
	board.queue_free()
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
