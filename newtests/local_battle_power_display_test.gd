extends Node

const BoardScene = preload("res://assets/scenes/game_scene/battle_board_v2.tscn")
const Sections = preload("res://scripts/game_scene/battle_io/shared_view_sections.gd")

# 只停用场景启动/推进；被测 formatter 与 _open_game_log 均继承真实生产实现。
class BoardProbe extends "res://scripts/game_scene/battle_board_v2.gd":
	func _ready() -> void:
		set_process(false)
	func _exit_tree() -> void:
		pass

class ProjectionSource extends RefCounted:
	var snapshot: Dictionary
	func _init(value: Dictionary) -> void:
		snapshot = value
	func read_view() -> Dictionary:
		return snapshot

var failures: Array[String] = []
var checks: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
	print("CHECK ", label, " ", "true" if condition else "false")

func _ready() -> void:
	# 独立固定 golden：12.75 和 -2.75 是批准显示修正，不更新 round74 历史 expected。
	var players: Array = [
		{"id": 1, "master": {"name": "御主甲"}},
		{"id": 2, "master": {"name": "御主乙"}},
		{"id": 3, "player_name": "玩家丙"},
		{"id": 4, "master": {"name": ""}, "player_name": "不能顶替空御主名"},
		{"id": 1, "master": {"name": "不能替换首个匹配"}}
	]
	var summary: Dictionary = {
		"无需": {"needs_win": false, "winners": [404], "highest_power": 99.25},
		"无胜": {"winners": [], "highest_power": 7.5},
		"整数": {"winners": [2, 1, 2], "highest_power": 12.0},
		"正小数": {"winners": [1], "highest_power": 12.75},
		"负小数": {"winners": [1], "highest_power": -2.75},
		"未知": {"winners": [404]},
		"名字回退": {"winners": [3, 4, 1], "highest_power": 0},
		"缺字段": {},
		"浮点零": {"winners": [1], "highest_power": 0.0},
		"负整数": {"winners": [1], "highest_power": -2},
		"合法负数文本": {"winners": [1], "highest_power": "-2.75"}
	}
	var expected: Array[String] = [
		"【无需】无需战斗，在场者共同获得战果",
		"【无胜】无人可获胜，战区战果保留",
		"【整数】胜者：御主乙、御主甲、御主乙，最高威力 12",
		"【正小数】胜者：御主甲，最高威力 12.75",
		"【负小数】胜者：御主甲，最高威力 -2.75",
		"【未知】胜者：，最高威力 0",
		"【名字回退】胜者：玩家丙、、御主甲，最高威力 0",
		"【缺字段】无人可获胜，战区战果保留",
		"【浮点零】胜者：御主甲，最高威力 0",
		"【负整数】胜者：御主甲，最高威力 -2",
		"【合法负数文本】胜者：御主甲，最高威力 -2.75"
	]
	var before := summary.duplicate(true)
	var board = BoardScene.instantiate()
	board.set_script(BoardProbe)
	board._source = ProjectionSource.new({"players": players})
	add_child(board)
	var actual: Array[String] = []
	var network: Array[String] = Sections.public_battle_result_lines(summary, players)
	var index: int = 0
	for area in summary:
		var line: String = board._battle_result_line(str(area), summary[area])
		actual.append(line)
		check(line == expected[index], "fixed_formatter_" + str(area))
		var detail: Dictionary = summary[area]
		if detail.get("needs_win", true) and not detail.get("winners", []).is_empty():
			check(line.get_slice("最高威力 ", 1) == network[index].get_slice("最高威力 ", 1), "network_numeric_parity_" + str(area))
			check(line.get_slice("最高威力 ", 1) == BaseNumber.display_text(detail.get("highest_power", 0)), "existing_precision_policy_" + str(area))
		index += 1
	check(board._battle_result_lines({"details_by_area": summary}, "原标题") == ["原标题"] + expected, "header_and_area_order_fixed")
	check(board._battle_result_lines({}, "原标题").is_empty(), "empty_summary_no_header")
	# 保存/恢复真实 autoload 状态；通过原本地日志入口写入正式场景 RichTextLabel。
	var previous_result: Dictionary = GameProgress.last_battle_result
	GameProgress.last_battle_result = {"details_by_area": summary}
	board.get_node("LogBrowser").hide()
	board.get_node("EventDiscardMenu").show()
	var expected_log := PackedStringArray(["══ 本次战斗结算 ══"] + expected + ["", "══ 对局历史日志 ══"])
	var logs: Array = GameLog.query({}, null, -1)
	for i in range(logs.size() - 1, -1, -1):
		var history_line: String = board._format_game_log_line(logs[i])
		if not history_line.is_empty():
			expected_log.append(history_line)
	board._open_game_log()
	var entries := board.get_node("LogBrowser/Panel/Entries") as RichTextLabel
	check(entries.text == "\n\n".join(expected_log), "real_local_log_exact_fixed_golden")
	check(board.get_node("LogBrowser").visible and not board.get_node("EventDiscardMenu").visible, "real_local_log_node_state")
	check(entries.text.contains(expected[3]), "real_local_log_positive_decimal")
	check(entries.text.contains(expected[4]), "real_local_log_negative_decimal")
	check(entries.text.contains(expected[2]) and entries.text.contains(expected[6]), "real_local_log_integral_12_and_zero")
	check(not expected[1].contains("最高威力") and not expected[0].contains("最高威力"), "no_winner_and_needs_win_false_wording_preserved")
	check(summary == before, "input_values_not_mutated")
	for area in summary:
		if summary[area].has("highest_power"):
			check(typeof(summary[area].highest_power) == typeof(before[area].highest_power), "input_type_preserved_" + str(area))
	GameProgress.last_battle_result = previous_result
	print("GOLDEN ", JSON.stringify({"local": actual, "network": network, "rendered_log": entries.text, "approved_display_corrections": ["12.75 instead of 12", "-2.75 instead of -2"]}))
	board.free()
	print("RESULT ", JSON.stringify({"test": "local_battle_power_display", "checks": checks, "failures": failures, "passed": failures.is_empty()}))
	get_tree().quit(0 if failures.is_empty() else 1)
