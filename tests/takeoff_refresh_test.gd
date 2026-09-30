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

## 在 board 的场景树里找 card 对应的出牌槽位
func _find_slot(board: Control, card) -> Control:
	var strips: Control = board.get_node_or_null("Strips")
	if strips == null:
		return null
	for strip in strips.get_children():
		var list := strip.get_node_or_null("Main/Groups/List") as Control
		if list == null:
			continue
		for grp in list.get_children():
			var row := (grp as Control).get_node_or_null("Cards/Row") as Control
			if row == null:
				continue
			for slot in row.get_children():
				if (slot as Control).get_meta("card", null) == card:
					return slot as Control
	return null

func run() -> void:
	seed(9173)
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	board.set_script(load("res://tests/takeoff_refresh_board.gd"))
	get_tree().root.add_child(board)
	board.set_process(false)
	await get_tree().create_timer(0.6).timeout
	var ids: Array = GameData.player_data_library.keys()
	var areas: Array = MapData.areas
	check(areas.size() >= 2 and ids.size() >= 2, "fixture has two battlefields and players")
	for id in ids:
		GameData.player_data_library[id].played_cards.clear()
	# 两个玩家分别部署到两个战场；先空刷新一次让 _fly_armed 就位，
	# 这样之后打出的牌都走"入队飞行"路径，不依赖首次刷新的时序
	for i in range(2):
		var loc = areas[i]._locations.filter(func(item): return item._pl_num_limit < 0)[0]
		SetLocation.new().exec(loc, ids[i], false)
	board._select_scroll(0)
	board.refresh_all_ui()
	await get_tree().create_timer(0.3).timeout
	# 两个战场各打一张牌：战场 0 是当前显示，战场 1 是关闭的
	var hidden_card = null
	for i in range(2):
		var pl: Dictionary = GameData.player_data_library[ids[i]]
		pl.played_cards.append(pl.hand_cards.pop_back())
	hidden_card = GameData.player_data_library[ids[1]].played_cards[0]
	board.refresh_all_ui()
	# 关闭战场的牌也立即登记并进入自己的飞行队列（后台并行飞），不再等战场展开
	check(board._takeoff_done.has(hidden_card.get_instance_id()), "closed battlefield card registers takeoff in background")
	var bg_queue: Array = board._fly_queues.get(1, [])
	check(not bg_queue.is_empty() or board._fly_busy.get(1, false), "closed battlefield card enters its own fly queue")
	board.refresh_calls = 0
	for i in range(8):
		board._process(0.0)
		await get_tree().process_frame
	check(board.refresh_calls == 0, "closed battlefield never causes full UI refresh per frame")
	# 等飞行完成：后台战场的牌在用户没看它时已经落位（队列清空、泵停止）
	await get_tree().create_timer(1.0).timeout
	var bg_queue_after: Array = board._fly_queues.get(1, [])
	check(bg_queue_after.is_empty() and not board._fly_busy.get(1, false), "background fly pump drains without the battlefield being opened")
	# 切到该战场：牌已经是打好的状态（槽位可见、不重飞）
	board._select_scroll(1)
	await get_tree().create_timer(0.6).timeout
	board.refresh_all_ui()
	var slot := _find_slot(board, hidden_card)
	check(slot != null and is_instance_valid(slot) and slot.modulate.a > 0.5, "card slot is landed when switching to its battlefield")
	var q_sw: Array = board._fly_queues.get(1, [])
	check(q_sw.is_empty(), "no re-takeoff when switching to a drained battlefield")
	# freed slot 测试：队列里塞进已释放的槽位，泵应丢弃而不是卡住
	var dead_slot := Control.new()
	get_tree().root.add_child(dead_slot)
	var dead_queue: Array = board._fly_queues.get(1, [])
	dead_queue.append({"slot": dead_slot, "card": hidden_card, "pid": ids[1]})
	board._fly_queues[1] = dead_queue
	dead_slot.free()
	board._pump_fly_queue(1)
	await get_tree().create_timer(0.2).timeout
	var q_after: Array = board._fly_queues.get(1, [])
	check(q_after.is_empty() and not board._fly_busy.get(1, false), "freed queued slot is discarded without wedging queue")
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
