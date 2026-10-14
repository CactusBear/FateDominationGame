extends Node
## 正式组合根与真实renderer；headless信号分发不是窗口验收。
var board: Control
var checks := 0
var failures: Array = []
var traces: Array = []

class ReadTrap extends RefCounted:
	var calls := 0
	func actions(_seat: int) -> Dictionary:
		calls += 1
		return {}
	func pending(_seat: int) -> Dictionary:
		calls += 1
		return {}
	func preview(_seat: int, _cards: Array, _hidden: Array) -> Dictionary:
		calls += 1
		return {}

class SourceSession extends RefCounted:
	signal changed
	var view: Dictionary = {}
	var rule_calls := 0
	func read_match() -> Dictionary:
		return view.duplicate(true)
	func read_actions() -> Dictionary:
		rule_calls += 1
		return {}
	func read_pending() -> Dictionary:
		rule_calls += 1
		return {}
	func request(_kind: String, _payload: Dictionary) -> void:
		rule_calls += 1

func check(ok: bool, label: String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func _ready() -> void:
	call_deferred("run")

func state() -> Array:
	var out: Array = [GameProgress.current_round, GameProgress.current_player_id,
		GameProgress.current_phase_index, GameProgress.is_game_over,
		GameLog.query({}, null, -1).duplicate(true), MapData.event_discard.duplicate(),
		MapData.situation_discard.duplicate(), MapData.active_situation,
		EffectManager.is_waiting_for_choice(), EffectManager.is_waiting_for_card_selection()]
	for pid in GameData.player_data_library:
		var data: Dictionary = GameData.player_data_library[pid]
		out.append([pid, data.magic.number, data.score.number, data.command_spell_count.number,
			data.order.number, data.hand_cards.duplicate(), data.deck.duplicate(), data.discard.duplicate(),
			data.played_cards.duplicate(), data.buffs.duplicate(), data.out_of_game.duplicate(true)])
	return out

func output() -> Dictionary:
	var rows: Array = []
	for row in board.get_node("Board/Rows").get_children():
		var image: Texture2D = row.get_node("Avatar/Img").texture
		rows.append({"rank":row.get_node("Rank").text, "name":row.get_node("Name").text,
			"class":row.get_node("Class").text, "score":row.get_node("Score").text,
			"variation":row.get_node("Name").theme_type_variation,
			"avatar":image.resource_path if image != null else "", "height":row.custom_minimum_size.y})
	return {"visible":board.get_node("Board").visible, "height":board.get_node("Board").size.y, "rows":rows}

func expect(view: Dictionary, label: String) -> void:
	var players: Array = view.get("players", []).duplicate()
	players.sort_custom(func(a, b): return a.get("score", 0) > b.get("score", 0))
	var result: Dictionary = output()
	check(result.visible and result.rows.size() == players.size(), label + " 可见及行数")
	for i in players.size():
		var player: Dictionary = players[i]
		var row: Dictionary = result.rows[i]
		check(row.rank == str(i + 1) and row.name == player.get("master", {}).get("name", player.get("player_name", ""))
			and row["class"] == player.get("servant_class", "") and row.score == BaseNumber.display_text(player.get("score", 0)), label + " 原排序文本 %d" % i)
		check(row.variation == ("Mana" if player.id == view.get("observer", -1) else "Text"), label + " observer样式 %d" % i)
	var row_height: float = result.rows[0].height if not result.rows.is_empty() else 0.0
	check(result.height == 52.0 + players.size() * row_height, label + " 原高度含empty")
	traces.append({"label":label,"output":result})

func press() -> void:
	board.get_node("Top/BoardButton").pressed.emit()

func owner(label: String) -> void:
	var connections: Array = board.get_node("Top/BoardButton").pressed.get_connections()
	check(connections.size() == 1, label + " 唯一生产连接")
	if connections.size() == 1:
		var callback: Callable = connections[0].callable
		check(callback.get_object() == board and callback.get_method() == &"_toggle_scoreboard", label + " 真实caller归属board共享入口")

func run() -> void:
	GameStart.reset()
	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	add_child(board)
	board.set_process(false)
	board.set_process_input(false)
	EffectManager.reset_runtime()
	GameLog.reset()
	GameData.player_data_library.clear()
	for pid in range(2):
		var data: Dictionary = GameData.new_player_data()
		data.player_name = "投影玩家%d" % pid
		data.order.set_num(BaseNumber.new(pid))
		data.score.set_num(BaseNumber.new(3 if pid == 0 else 8))
		GameData.player_data_library[pid] = data
	GameProgress.reset_progress()
	var builder = preload("res://scripts/match/view_builder.gd").new()
	var trap := ReadTrap.new()
	board._source = preload("res://scripts/game_scene/battle_io/local_battle_source.gd").new(0, builder, trap)
	board._source_is_local = true
	board.get_node("Board").hide()
	var before := state()
	var view: Dictionary = board._source.read_view()
	press()
	expect(view, "本地首次打开")
	press()
	check(not board.get_node("Board").visible, "本地第二次关闭")
	traces.append({"label":"本地关闭","output":output()})
	GameData.player_data_library[0].score.set_num(BaseNumber.new(11.5))
	GameData.player_data_library[0].player_name = "同ID更新"
	board._source.invalidate()
	view = board._source.read_view()
	before = state()
	press()
	expect(view, "本地同ID重新打开刷新")
	GameData.player_data_library[1].score.set_num(BaseNumber.new(18))
	board._source.invalidate()
	view = board._source.read_view()
	before = state()
	board._bind_board()
	expect(view, "本地可见榜单原刷新入口")
	check(state() == before and trap.calls == 0, "本地绘制无规则查询与状态变化")
	owner("本地")
	board.queue_free()
	await get_tree().process_frame

	var lobby = preload("res://scripts/net/session/lobby_session.gd").new()
	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	board.network_session = lobby
	add_child(board)
	board.set_process(false)
	board.set_process_input(false)
	board._source.close()
	var session := SourceSession.new()
	board._source = preload("res://scripts/game_scene/battle_io/network_battle_source.gd").new(session)
	board._network_presenter._mine = {"id":0,"score":999,"master":{"name":"不得读取旧mine"}}
	session.view = builder.build(0)
	# 会话投递与传输验证分层：受控会话投递真实builder快照。
	before = state()
	press()
	expect(session.view, "网络首次打开")
	press()
	check(not board.get_node("Board").visible, "网络第二次关闭")
	traces.append({"label":"网络关闭","output":output()})
	session.view.players[0].score = 31.25
	session.view.players[0].player_name = "网络同seq同ID新字段"
	press()
	expect(session.view, "网络同seq同ID重新打开刷新")
	session.view.players[1].score = 41
	session.view.observer = 1
	board._bind_board()
	expect(session.view, "网络可见榜单同seq换observer刷新")
	var filtered: Dictionary = session.view.duplicate(true)
	# 公共过滤已删姓名/职阶；不能按同ID回查本机真实player_name。
	filtered.players[0] = {"id":0,"score":51}
	filtered.observer = -1
	session.view = filtered
	board._bind_board()
	expect(filtered, "网络过滤字段不回补")
	check(board.get_node("Board/Rows").get_child(0).get_node("Name").text.is_empty(), "过滤空名不读取本机玩家")
	for empty in [{}, {"seq":session.view.seq,"observer":0,"players":[]}]:
		session.view = empty
		board._bind_board()
		expect(empty, "网络empty %d" % traces.size())
	session.view = filtered
	board._bind_board()
	expect(filtered, "网络empty后同ID恢复")
	board._source.close()
	board._bind_board()
	expect({}, "网络source关闭清空")
	check(state() == before and session.rule_calls == 0 and trap.calls == 0, "网络输入刷新过滤empty均不执行规则或改状态")
	owner("网络")
	check(not board._network_presenter.has_method("toggle_scoreboard"), "旧presenter无caller同义函数退休")
	print("TRACE ", JSON.stringify(traces))
	await finish()

func finish() -> void:
	board.queue_free()
	await get_tree().process_frame
	GameStart.reset()
	print("RESULT ", JSON.stringify({"suite":"round74_scoreboard_toggle","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
