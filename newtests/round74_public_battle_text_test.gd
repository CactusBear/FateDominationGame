extends Node

const Sections = preload("res://scripts/game_scene/battle_io/shared_view_sections.gd")
const BoardScript = preload("res://scripts/game_scene/battle_board_v2.gd")

class PresenterProbe extends "res://scripts/net/ui/v2_view_presenter.gd":
	func _init(target: Control, source) -> void:
		board = target
		session = source

class ProjectionSource extends RefCounted:
	var snapshot: Dictionary
	var reads: int = 0
	func _init(view: Dictionary) -> void:
		snapshot = view
	func read_match() -> Dictionary:
		reads += 1
		return snapshot
	func read_view() -> Dictionary:
		return snapshot

class LogBoard extends Control:
	func _raise_modal(_panel: Control) -> void:
		pass

var failures: Array[String] = []
var checks: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
	print("CHECK ", label, " ", "true" if condition else "false")

func _ready() -> void:
	# 手写且固定的正负对照：不 capture、不重写 expected。
	var players: Array = [
		{"id": 1, "master": {"name": "御主甲"}, "player_name": "玩家甲"},
		{"id": 2, "master": {"name": "御主乙"}, "player_name": "玩家乙"},
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
		"缺字段": {}
	}
	var expected_network: Array[String] = [
		"【无需】无需战斗，在场者共同获得战果",
		"【无胜】无人可获胜，战区战果保留，最高威力 7.5",
		"【整数】胜者：御主乙、御主甲、御主乙，最高威力 12",
		"【正小数】胜者：御主甲，最高威力 12.75",
		"【负小数】胜者：御主甲，最高威力 -2.75",
		"【未知】胜者：，最高威力 0",
		"【名字回退】胜者：玩家丙、、御主甲，最高威力 0",
		"【缺字段】无人可获胜，战区战果保留，最高威力 0"
	]
	var expected_local: Array[String] = [
		"【无需】无需战斗，在场者共同获得战果",
		"【无胜】无人可获胜，战区战果保留",
		"【整数】胜者：御主乙、御主甲、御主乙，最高威力 12",
		# 批准差异：本地复用 BaseNumber.display_text，真实小数不截断；历史证据仍保留 12 / -2。
		"【正小数】胜者：御主甲，最高威力 12.75",
		"【负小数】胜者：御主甲，最高威力 -2.75",
		"【未知】胜者：，最高威力 0",
		"【名字回退】胜者：玩家丙、、御主甲，最高威力 0",
		"【缺字段】无人可获胜，战区战果保留"
	]
	var snapshot: Dictionary = {"players": players, "battle_result": summary, "public_log": ["较早日志", "较新日志"]}
	var source := ProjectionSource.new(snapshot)
	var local_board = BoardScript.new()
	local_board._source = source
	var local_lines: Array[String] = []
	for area in summary:
		local_lines.append(local_board._battle_result_line(str(area), summary[area]))
	check(local_lines == expected_local, "existing_local_golden_unchanged")
	check(local_board._battle_result_lines({"details_by_area": summary}, "原标题") == ["原标题"] + expected_local, "local_header_order_unchanged")
	local_board.free()
	var log_board := LogBoard.new()
	var browser := Control.new()
	browser.name = "LogBrowser"
	browser.hide()
	log_board.add_child(browser)
	var panel := Control.new()
	panel.name = "Panel"
	browser.add_child(panel)
	var entries := RichTextLabel.new()
	entries.name = "Entries"
	panel.add_child(entries)
	var presenter := PresenterProbe.new(log_board, source)
	presenter.open_log()
	var expected_log := "══ 公共对局日志 ══\n\n" + "\n\n".join(PackedStringArray(expected_network + ["", "较新日志", "较早日志"]))
	check(entries.text == expected_log, "real_presenter_open_log_exact_golden")
	check(browser.visible and not entries.bbcode_enabled, "existing_log_node_state")
	check(source.reads == 1, "single_authorized_snapshot_no_formatter_session_reads")
	var formatter := Sections.new()
	var migrated: bool = formatter.has_method("public_battle_result_lines")
	check(migrated, "shared_explicit_input_formatter_exists")
	check(not presenter.has_method("public_battle_result_lines"), "presenter_old_formatter_retired_no_compatibility_layer")
	if migrated:
		var before := snapshot.duplicate(true)
		var actual: Array = formatter.call("public_battle_result_lines", summary, players)
		check(actual == expected_network, "shared_network_exact_numeric_order_golden")
		check(snapshot == before, "input_projection_not_mutated")
		check(formatter.call("public_battle_result_lines", {}, players).is_empty(), "empty_summary_no_lines")
		check(formatter.call("public_battle_result_lines", {"空投影": {"winners": [1], "highest_power": 0.25}}, []) == ["【空投影】胜者：，最高威力 0.25"], "missing_authorized_player_no_rule_lookup")
	for index in range(summary.size()):
		# 批准的小数修正后，只有无赢家 / 缺字段仍与网络文案不同。
		check((expected_local[index] == expected_network[index]) == (index in [0, 2, 3, 4, 5, 6]), "semantic_same_or_different_%d" % index)
	print("GOLDEN ", JSON.stringify({"network": expected_network, "local": local_lines, "rendered_log": entries.text}))
	log_board.free()
	print("RESULT ", JSON.stringify({"test": "round74_public_battle_text", "checks": checks, "failures": failures, "passed": failures.is_empty()}))
	get_tree().quit(0 if failures.is_empty() else 1)
