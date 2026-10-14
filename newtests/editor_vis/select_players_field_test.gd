extends Node

# 挑玩家字段编辑器回归：找到美狄亚「万符必应破戒」的挑玩家选项，断言控件、改 min 写回、保存往返 candidates 等价。
const Codec = preload("res://json_maker/json_codec.gd")
const MEDEA := "res://data/servants/00005_medea/00005_medea.json"

var checks := 0
var failures:Array = []


func check(ok:bool, text:String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
	print("CHECK ", text, " ", ok)


func _ready() -> void:
	call_deferred("run")


func _find_named(root:Node, node_name:String) -> Node:
	var found := root.find_children(node_name, "", true, false)
	return found[0] if not found.is_empty() else null


func run() -> void:
	var ui = load("res://json_maker/json_maker.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame
	ui.open_path(MEDEA)
	await get_tree().process_frame
	var original = ui.maker.read_json(MEDEA)
	var skill_path := ["specials", "SKILLS", 1]
	var target := -1
	for e in ui.sub_entries.size():
		if ui.sub_entries[e].path == skill_path:
			target = e
	check(target >= 0, "found 万符必应破戒 sub entry")
	ui._focus_entry(target)
	await get_tree().process_frame
	var opt:Dictionary = ui.data.specials.SKILLS[1].effects[0].options[0]
	check(opt.get("select_players") is Dictionary, "破戒选项有 select_players")
	var toggle := _find_named(ui.script_box, "SelectPlayersToggle") as Button
	check(toggle != null and toggle.text == "不挑目标了", "toggle shows 不挑目标了 when declared")
	var min_spin := _find_named(ui.script_box, "SelectPlayersMin") as SpinBox
	var max_spin := _find_named(ui.script_box, "SelectPlayersMax") as SpinBox
	check(min_spin != null and max_spin != null, "min/max spin boxes exist")
	if min_spin == null or max_spin == null:
		_finish()
		return
	check(int(min_spin.value) == 1 and int(max_spin.value) == 1, "spins show declared min/max 1/1")
	check(min_spin.min_value == -1, "min spin allows -1 = 不限")
	var orig_cands = original.specials.SKILLS[1].effects[0].options[0].select_players.candidates

	# 改 min 写回
	min_spin.value = 2
	await get_tree().process_frame
	ui._commit()
	check(int(opt.select_players.min) == 2, "changing min writes back to data")
	min_spin.value = 1
	await get_tree().process_frame
	ui._commit()

	# 保存往返：导出文本再解析，candidates 与原文等价
	var text:String = ui.maker.export_text(ui.data, ui.style)
	var reparsed = JSON.parse_string(text)
	check(reparsed is Dictionary, "exported text parses back")
	if reparsed is Dictionary:
		var rsp = reparsed.specials.SKILLS[1].effects[0].options[0].select_players
		check(Codec.same(rsp.get("candidates"), orig_cands), "candidates round trip equivalent after save")
		check(int(rsp.min) == 1 and int(rsp.max) == 1, "min/max round trip")
	check(Codec.same(ui.data.specials.SKILLS[1].effects[0].options[0].select_players.candidates, orig_cands), "in-memory candidates unchanged")

	# 开关：关掉后 select_players 消失，再打开得到默认 1/1 空候选
	toggle.pressed.emit()
	await get_tree().process_frame
	check(not opt.has("select_players"), "不挑目标了 removes select_players")
	ui._refresh_scripts()
	await get_tree().process_frame
	await get_tree().process_frame
	toggle = _find_named(ui.script_box, "SelectPlayersToggle") as Button
	check(toggle != null and toggle.text == "＋ 让玩家挑目标", "toggle shows ＋ when undeclared")
	if toggle != null:
		toggle.pressed.emit()
		await get_tree().process_frame
		check(opt.get("select_players") is Dictionary and int(opt.select_players.min) == 1, "让玩家挑目标 adds default select_players")

	_finish()


func _finish() -> void:
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
