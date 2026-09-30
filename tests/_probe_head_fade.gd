extends Node

## 采样出牌组头像的 alpha：组被重建后，头像应从 0 渐变到 1
var board: Control
var t := 0.0
var phase := 0
var _placed := false
var samples: Array = []
var grp_count := 0
var _joined := 0
var _joined_ids: Array = []
var _joined_frame := -1

func _ready() -> void:
	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child.call_deferred(board)

func _process(delta: float) -> void:
	if board == null or not board.is_inside_tree():
		return
	t += delta
	if phase == 0 and t > 1.0:
		phase = 1
		board._select_scroll(-1)
		_setup_first()
		return
	if phase == 1 and t > 2.4:
		board._select_scroll(MapData.areas.find(MapData.miyama))
		print("OPEN now")
		phase = 2
		# 把组拆掉（玩家离场），再放回来，逼它重建
		board._select_scroll(MapData.areas.find(MapData.miyama))
		print("OPEN now")
		return
	if phase == 2:
		var a := _head_alpha()
		var op := _openness()
		if a >= 0.0:
			samples.append([snappedf(op, 0.01), snappedf(a, 0.01)])
			if op < 0.99 and a > 0.02:
				print("LEAK during open: openness=", op, " alpha=", a)
		if t > 7.5 and samples.size() > 0:
			phase = 3
			var leaks := 0
			var faded_after_open := false
			for e in samples:
				if float(e[0]) < 0.99 and float(e[1]) > 0.02:
					leaks += 1
				if float(e[0]) >= 0.99 and float(e[1]) < 0.9:
					faded_after_open = true
			print("HEAD_ALPHA n=", samples.size(), " LEARKS_during_open=", leaks, " faded_after_open=", faded_after_open)
			print("  first=", samples[0] if samples.size()>0 else [], " last=", samples[-1] if samples.size()>0 else [])
			var ok := leaks == 0 and faded_after_open
			print("OPEN_THEN_FADE_OK=", ok)
			get_tree().quit(0 if ok else 1)

func _reset_groups() -> void:
	# 清掉"已出生/已用过头像"的标记，让下一次绑定重新播淡入
	for grp in board._play_group_nodes():
		var who := (grp as Control).get_node_or_null("Who") as Control
		var av := who.get_node_or_null("Avatar") as Control
		if av != null:
			if av.has_meta("last_head"):
				av.remove_meta("last_head")
			av.modulate.a = 1.0
		if (grp as Control).has_meta("born"):
			(grp as Control).remove_meta("born")
		if (grp as Control).has_meta("born_at"):
			(grp as Control).remove_meta("born_at")
		(grp as Control).modulate.a = 1.0
	board.refresh_all_ui()
	print("RESET done groups=", board._play_group_nodes().size())

func _setup_first() -> void:
	var pid: int = board._local_player_id
	MapData.active_situation = null
	var area: BaseMapArea = MapData.miyama
	var unlimited: BaseLocation = area._locations.filter(func(loc): return loc._pl_num_limit < 0)[0]
	SetLocation.new().exec(unlimited, pid, false)
	var pl: Dictionary = board._pl(pid)
	if not (pl.get("hand_cards", []) as Array).is_empty():
		pl.played_cards.append(pl.hand_cards.pop_back())
	board._select_scroll(MapData.areas.find(area))
	board.refresh_all_ui()
	_joined = 0
	print("SETUP groups=", board._play_group_nodes().size())

func _join_one() -> void:
	var unlimited: BaseLocation = MapData.miyama._locations.filter(func(loc): return loc._pl_num_limit < 0)[0]
	var ids: Array = GameData.player_data_library.keys()
	ids.sort()
	for pid_v in ids:
		var pid: int = int(pid_v)
		if pid == board._local_player_id:
			continue
		if not _joined_ids.has(pid):
			SetLocation.new().exec(unlimited, pid, false)
			_joined_ids.append(pid)
			_joined += 1
			board.refresh_all_ui()
			print("JOIN pid=", pid, " groups=", board._play_group_nodes().size())
			return

func _openness() -> float:
	var strips := board.get_node_or_null("Strips")
	if strips == null or board._main_area_index < 0:
		return 0.0
	var strip := strips.get_child(board._main_area_index) as Node
	var content := strip.get_node_or_null("Main") as CanvasItem
	if content == null:
		return 0.0
	return content.modulate.a

func _head_alpha() -> float:
	for grp in board._play_group_nodes():
		var who := (grp as Control).get_node_or_null("Who") as Control
		return (grp as Control).modulate.a
	return -1.0

func _place_and_play() -> void:
	var pid: int = board._local_player_id
	MapData.active_situation = null
	var area: BaseMapArea = MapData.miyama
	var unlimited: BaseLocation = area._locations.filter(func(loc): return loc._pl_num_limit < 0)[0]
	SetLocation.new().exec(unlimited, pid, false)
	var pl: Dictionary = board._pl(pid)
	if not (pl.get("hand_cards", []) as Array).is_empty():
		pl.played_cards.append(pl.hand_cards.pop_back())
	board._select_scroll(MapData.areas.find(area))
	board.refresh_all_ui()
	print("SETUP groups=", board._play_group_nodes().size())
