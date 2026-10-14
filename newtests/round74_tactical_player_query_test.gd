extends Node

# 仅隔离旧界面的启动/逐帧驱动；三个被测展示函数保持真实实现。
class QueryBoard:
	extends "res://scripts/game_scene/tactical_board_ui.gd"
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass

const Random = preload("res://scripts/match/rule_random.gd")
const UNKNOWN_IDS := [999, 2147483647]
var checks := 0
var failures: Array = []
var trace: Dictionary = {}
var board: QueryBoard
var target: Control

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

# 每次单独测键集合；RED 清掉意外创建的席位，防止下一项被污染。
func pure_query(query: Callable, label: String):
	var before: Array = GameData.player_data_library.keys()
	var result = query.call()
	check(GameData.player_data_library.keys() == before, label + " preserves player keys")
	for id in GameData.player_data_library.keys():
		if not before.has(id):
			GameData.player_data_library.erase(id)
	return result

func configure_prompt(pid: int, card: BaseCard) -> void:
	board._ai_play_prompt_player_id = pid
	board._ai_play_prompt_card = card
	board._ai_play_prompt_round = GameProgress.current_round
	target.set_meta("turn_order_player_id", pid)

func prompt_trace() -> Dictionary:
	var prompt: Control = board._ai_play_prompt_node
	return {
		"title": prompt.get_node("Title").text,
		"count": prompt.get_node("CardsScroll/Cards").get_child_count(),
		"visible": prompt.visible,
		"pid": prompt.get_meta("ai_prompt_player_id"),
	}

func run() -> void:
	print("USER_DIR ", OS.get_user_data_dir())
	GameStart.reset()
	Random.start_seed(20261010)
	check(GameStart.game_start([0, 1]), "real two-seat match starts")
	if not failures.is_empty():
		finish()
		return
	var initial_keys: Array = GameData.player_data_library.keys()
	board = QueryBoard.new()
	add_child(board)
	board._local_player_id = 0
	# 只建被测函数所需的真实 Control 层级；不装配旧布局、不补未知玩家数据。
	var parent: Node = board
	for part in str(board.ORDER_BOX_PATH).split("/"):
		var node: Control = HBoxContainer.new() if part == "OrderHBox" else Control.new()
		node.name = part
		parent.add_child(node)
		parent = node
	target = Control.new()
	target.name = "P2_QueryTarget"
	target.custom_minimum_size = Vector2(120, 80)
	parent.add_child(target)
	GameProgress.current_player_id = 1
	var data: Dictionary = GameDataManager.find_player_data(1)
	var servant = data.get("servant")
	check(is_instance_valid(servant), "real loaded servant exists")
	var cards: Array = data.get("hand_cards", [])
	check(not cards.is_empty(), "real loaded hand card exists")
	if not failures.is_empty():
		board.queue_free()
		finish()
		return
	var card: BaseCard = cards[0]
	# 真实日志入口模拟有历史公开记录但当前无席位的 id，穿过 class 的可见性分支。
	GameLog.record("true_name_release", 1)
	var shown: String = pure_query(func(): return board._class_shown(1), "existing class")
	check(shown == str(servant.get("_servant_class")), "existing class value unchanged")
	trace["existing_class"] = shown
	trace["existing_name"] = board._player_shown_name(1)
	check(trace["existing_name"] == EffectManager.player_shown_name(1), "name uses existing public query")
	check(board._player_shown_name_by_id(1) == trace["existing_name"], "report name uses same public query")
	var old_played: Array = data.get("played_cards", [])
	# 展示夹具仅使用本局真实牌对象；不为未知 id 制造规则对象或占位牌。
	data["played_cards"] = [card]
	configure_prompt(1, card)
	pure_query(func(): board._refresh_ai_play_prompt(), "existing prompt refresh")
	trace["existing_prompt"] = prompt_trace()
	check(trace["existing_prompt"].count == 1, "existing prompt renders same real card count")
	check(trace["existing_prompt"].title == "已出牌 · 点击查看", "existing prompt title unchanged")
	pure_query(func(): board._update_ai_play_prompt_geometry(), "existing prompt geometry")
	data["played_cards"] = []
	pure_query(func(): board._refresh_ai_play_prompt(), "empty existing prompt")
	trace["empty_prompt"] = prompt_trace()
	check(trace["empty_prompt"].count == 0 and not trace["empty_prompt"].visible, "empty data remains empty and hidden")
	check(trace["empty_prompt"].title == "已出牌 · 点击查看", "empty data title unchanged")
	data["played_cards"] = old_played
	for pid in UNKNOWN_IDS:
		check(not GameData.player_data_library.has(pid), "fixture unknown id %d" % pid)
		var hidden: String = pure_query(func(): return board._class_shown(pid), "hidden class %d" % pid)
		check(hidden == "???", "unrevealed unknown class fallback unchanged")
		GameLog.record("true_name_release", pid)
		check(GameDataManager.can_see_servant_class(0, pid), "historical unknown id enters visible class branch")
		for repeat in range(3):
			shown = pure_query(func(): return board._class_shown(pid), "unknown class %d repeat %d" % [pid, repeat])
			check(shown == "???", "visible unknown class fallback unchanged")
			var name: String = pure_query(func(): return board._player_shown_name(pid), "unknown name %d repeat %d" % [pid, repeat])
			check(name == "玩家 %d" % pid, "unknown name fallback unchanged")
			configure_prompt(pid, card)
			pure_query(func(): board._refresh_ai_play_prompt(), "unknown prompt refresh %d repeat %d" % [pid, repeat])
			var value: Dictionary = prompt_trace()
			check(value.count == 0 and not value.visible, "unknown prompt keeps empty hidden fallback")
			check(value.title == "已出牌 · 点击查看", "unknown prompt title unchanged")
			# 独立命中逐帧路径：即使已有提示节点显现，未知玩家仍只能隐藏，不能建席位。
			board._ai_play_prompt_node.show()
			pure_query(func(): board._update_ai_play_prompt_geometry(), "unknown geometry %d repeat %d" % [pid, repeat])
			check(not board._ai_play_prompt_node.visible, "unknown geometry hides existing node")
		trace["unknown_%d" % pid] = {"class": shown, "name": board._player_shown_name(pid), "prompt": prompt_trace()}
	check(GameData.player_data_library.keys() == initial_keys, "all repeated display queries preserve original seats")
	check(is_same(GameDataManager.find_player_data(1), data), "existing player dictionary identity unchanged")
	board.queue_free()
	finish()

func finish() -> void:
	print("COMPARE ", JSON.stringify(trace))
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
