extends Node

## 胜利播报回归：用真实引擎把一场有明确胜者的战斗结算出来，验证
## ① 战斗结算后 GameProgress.last_battle_result.details_by_area 字段齐备
## ② 有播报消费者（对局界面）时，结算后暂停、不立即进入下一回合
## ③ 播报层在结算后可见，且所有玩家确认（AI 自动 + 本地点「继续」）后才恢复推进
## 实现依赖：game_progress.gd 的战斗播报确认门，与 battle_board_v2.gd 的全屏播报层。

var failures: Array = []
var checks: int = 0
var board: Control = null


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)


func _ready() -> void:
	call_deferred("run")


func _label_text(node: Node) -> String:
	var text: String = node.text if node is Label else ""
	for child in node.get_children():
		text += "\n" + _label_text(child)
	return text


func run() -> void:
	# 初始状态：尚无任何播报消费者（无界面 / 旧界面路径不会阻塞推进）
	check(not GameProgress.has_battle_broadcast_consumer(), "no broadcast consumer at startup")

	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame
	# 界面每帧循环一跑起来就登记自己为播报消费者
	check(GameProgress.has_battle_broadcast_consumer(), "board registers broadcast consumer")

	# 构造一场有明确胜者的战斗：玩家 0、1 部署到深山町，玩家 0 出牌威力 20 胜出。
	# 清空事件牌避免随机牌效弹出确认窗口，只保留纯威力比较。
	for area: BaseMapArea in MapData.areas:
		area._events.clear()
		for loc in area._locations:
			loc._players.clear()
	# 复用正式席位模板，分别核对金色角标和下方席位说明。
	board.set_process(false)
	var benefit_loc: BaseLocation = null
	for area: BaseMapArea in MapData.areas:
		for loc: BaseLocation in area._locations:
			if loc._magic.number <= 0 and GetEffectiveLocationBenefit.current_benefit(loc) > 0:
				benefit_loc = loc
				break
		if benefit_loc != null:
			break
	check(benefit_loc != null, "fixture has a benefit seat")
	if benefit_loc != null:
		benefit_loc._players.append(0)
		var slot: Control = board._spawn("SeatSlot", board)
		slot.position = Vector2(600, 400)
		slot.size = Vector2(74, 92)
		var seat := slot.get_node("Seat") as Control
		board._bind_seat(seat, benefit_loc, true)
		var benefit := GetEffectiveLocationBenefit.current_benefit(benefit_loc)
		check(seat.get_node("Badge/Label").text == str(benefit), "gold badge contains only benefit number")
		check(seat.get_node("Label").text == "地利 %d" % benefit, "lower benefit label remains unchanged")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			check(image.get_region(Rect2i(580, 390, 120, 120)).save_png("user://benefit_number_badge.png") == OK, "benefit badge screenshot saved")
		benefit_loc._players.clear()
		slot.queue_free()
	board.set_process(true)
	for id in [0, 1]:
		var loc: BaseLocation = MapData.miyama._locations[id]
		check(SetLocation.new().exec(loc, id, false, true), "fixture places participant %d" % id)
	GameDataManager.get_player_data(0).power.number = 20

	# 直接进入战斗阶段结算（跳过准备/前哨/行动，与 battle_score_report_test 同源做法）
	GameProgress.current_phase_index = 3
	GameProgress.has_battle_resolved = false
	GameLog.set_context(GameProgress.current_round, "battle")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE])
	var ordered_ids: Array = GameProgress.get_ordered_player_ids()
	GameProgress.current_player_id = int(ordered_ids.back())
	GameProgress.current_phase_player_index = ordered_ids.size()
	check(GameProgress.end_current_player_action(), "last battle participant finishes through real progression entry")

	# ① 结算数据字段齐备，且胜负正确
	check(GameProgress.last_battle_result.has("details_by_area"), "battle result carries details_by_area")
	var details: Dictionary = GameProgress.last_battle_result.get("details_by_area", {})
	check(not details.is_empty(), "battle produced area details")
	var area_name: String = str(MapData.miyama._area_name)
	check(details.has(area_name), "battle detail exists for %s" % area_name)
	if details.has(area_name):
		var d: Dictionary = details[area_name]
		check(d.get("winners", []) == [0], "winner is player 0")
		check(d.get("players", []) == [0, 1], "both participants recorded")
		check(d.get("highest_power", -1) == 20, "highest power is 20")

	# ② 有消费者时结算后暂停，不立即进入下一回合
	check(GameProgress.is_battle_broadcast_pending(), "broadcast pending after battle resolve")
	check(GameProgress.current_phase_index == 3, "phase not advanced while pending")

	# ③ 正式逐帧循环等待三秒后才显示；等待期间不确认、不推进回合。
	var overlay: Control = board.get_node_or_null("BattleBroadcast")
	check(overlay != null and not overlay.visible, "broadcast overlay hidden immediately after resolve")
	var shown_early := false
	var progressed_early := false
	var confirmed_early := false
	for i in range(240):
		await get_tree().process_frame
		if board._broadcast_wait_elapsed < board.BROADCAST_OPEN_DELAY:
			shown_early = shown_early or overlay.visible
			progressed_early = progressed_early or GameProgress.current_phase_index != 3
			confirmed_early = confirmed_early or GameProgress.battle_broadcast_confirmed_count() > 0
		if overlay.visible:
			break
	check(not shown_early, "no settlement overlay before three-second delay")
	check(not progressed_early and not confirmed_early, "delay keeps phase paused and confirmations untouched")
	check(overlay.visible and board._broadcast_wait_elapsed >= 3.0, "broadcast overlay appears only after three seconds")
	print("BROADCAST_DELAY elapsed=", board._broadcast_wait_elapsed)
	if DisplayServer.get_name() != "headless":
		board.set_process(false)
		await get_tree().create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png("user://battle_broadcast_delayed.png") == OK, "delayed broadcast screenshot saved")
	var list := overlay.get_node("AreaScroll/List") as VBoxContainer
	check(list != null and list.get_child_count() == details.size(), "one area row per battlefield")
	var text: String = _label_text(overlay)
	check(text.contains(area_name), "overlay shows area name")
	check(text.contains("胜者："), "overlay shows winner")
	check(text.contains("出牌 20"), "overlay shows winner power breakdown")
	check(GameProgress.current_phase_index == 3, "still paused while overlay shown")

	# 「继续」按钮带 n/7 提示（手动亮起入场完成态以直接断言文案）
	board._broadcast_reveal_done = true
	board._queue_ai_confirmations()
	board._refresh_broadcast_continue()
	var btn := overlay.get_node("ContinueBtn") as Button
	var total: int = GameProgress.battle_broadcast_confirmers().size()
	check(btn != null and btn.visible, "continue button visible after reveal")
	check(btn.text.contains("已确认 0/%d" % total), "continue button shows 0/N hint")

	# 所有玩家确认后才放行：逐个确认，最后一个确认后引擎推进
	var confirmers: Array = GameProgress.battle_broadcast_confirmers()
	for i in range(confirmers.size()):
		GameProgress.confirm_battle_broadcast(int(confirmers[i]))
		if i < confirmers.size() - 1:
			check(GameProgress.is_battle_broadcast_pending(), "still pending after %d confirmation(s)" % (i + 1))
	check(not GameProgress.is_battle_broadcast_pending(), "pending cleared after all players confirm")
	check(GameProgress.current_round == 2, "all-confirm advances to next round")
	board._update_battle_broadcast(0.0)
	check(board._broadcast_wait_elapsed == 0.0, "cleared broadcast resets wait for next battle")

	print("RESULT checks=", checks, " failures=", failures)
	var f := FileAccess.open("res://battle_broadcast_result.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"checks": checks, "failures": failures}))
		f.close()
	get_tree().quit(0 if failures.is_empty() else 1)
