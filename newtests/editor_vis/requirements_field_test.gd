extends Node

# 打出条件字段（json_maker/fields/requirements_field.gd）headless 测试：
# 读出 min_magic / extra_with_batch，改 value/count 写回，未知类型原样保留，删空删键，「＋」新增。
var checks := 0
var failures:Array = []
const EMIYA := "res://data/masters/00001_emiya_shirou/00001_emiya_shirou.json"
const SASAKI := "res://data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json"
const FieldScript = preload("res://json_maker/fields/requirements_field.gd")
const FIELD := {"key": "play_requirements", "shown": "打出条件", "control": "requirements"}


func check(ok:bool, text:String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
	print("CHECK ", text, " ", ok)


func _ready() -> void:
	call_deferred("run")


# 按类型在 row 子树里找控件
func _all(node:Node, cls:String, out:Array = []) -> Array:
	if node.get_class() == cls:
		out.append(node)
	for c in node.get_children():
		_all(c, cls, out)
	return out


func _button(node:Node, text:String) -> Button:
	for b in _all(node, "Button"):
		if b.text == text:
			return b
	return null


func _build(ui, obj:Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	add_child(row)
	var field = FieldScript.new()
	field.build(ui, row, obj, "play_requirements", FIELD)
	return row


func run() -> void:
	var ui = load("res://json_maker/json_maker.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame
	var decl:Dictionary = ui.maker.types.get("requirement_types", {})
	check(decl.has("min_magic") and decl.has("extra_with_batch"), "types.json declares both requirement types")

	# 1. 卫宫士郎：min_magic value=8 读出并可改
	var emiya:Dictionary = ui.maker.read_json(EMIYA)["specials"]["SKILLS"][0]
	var row := _build(ui, emiya)
	var spins := _all(row, "SpinBox")
	check(emiya.play_requirements[0].type == "min_magic", "emiya read min_magic")
	check(spins.size() == 1 and spins[0].value == 8, "emiya value spin shows 8")
	spins[0].value = 9
	check(emiya.play_requirements[0].value == 9 and emiya.play_requirements[0].type == "min_magic", "emiya value written back 9")

	# 2. 小次郎：extra_with_batch 属性复选框 + count 数字
	var sasaki:Dictionary = ui.maker.read_json(SASAKI)["specials"]["SKILLS"][2]
	var srow := _build(ui, sasaki)
	var boxes := _all(srow, "CheckBox")
	var agi = null
	for b in boxes:
		if b.text == ui.maker.attributes.filter(func(a): return a.id == "agility")[0].shown:
			agi = b
	check(agi != null and agi.button_pressed, "sasaki agility checkbox shows checked")
	var cspins := _all(srow, "SpinBox")
	check(cspins.size() == 1 and cspins[0].value == 2, "sasaki count spin shows 2")
	cspins[0].value = 3
	check(sasaki.play_requirements[0].count == 3, "sasaki count written back 3")
	agi.button_pressed = false
	check(sasaki.play_requirements[0].attributes.is_empty(), "sasaki attribute unchecked removed")
	agi.button_pressed = true
	check(sasaki.play_requirements[0].attributes == ["agility"], "sasaki attribute re-added")

	# 3. 未知类型：原样保留，只读；增删其他条目后仍在；JSON 往返不丢
	var mix := {"play_requirements": [{"type": "min_magic", "value": 4}, {"type": "future_rule", "x": [1, "a"]}]}
	var mrow := _build(ui, mix)
	check(mix.play_requirements.size() == 2 and mix.play_requirements[1] == {"type": "future_rule", "x": [1, "a"]}, "unknown entry kept as-is on build")
	check(_all(mrow, "SpinBox").size() == 1, "only known entry has editable spin")
	var texts := _all(mrow, "Label")
	var shown_json := false
	for l in texts:
		if l.text.find("future_rule") != -1:
			shown_json = true
	check(shown_json, "unknown entry shown read-only as JSON text")
	# 删已知条目 -> 未知条目还在
	_button(mrow, "删除").pressed.emit()
	check(mix.play_requirements.size() == 1 and mix.play_requirements[0].type == "future_rule", "deleting known entry keeps unknown")
	var back = JSON.parse_string(JSON.stringify(mix))
	var bx = back.play_requirements[0].x
	check(back.play_requirements[0].type == "future_rule" and bx.size() == 2 and bx[0] == 1 and bx[1] == "a", "unknown entry survives JSON round-trip")

	# 4. 「＋」新增一条（默认第一种类型）
	var empty := {"play_requirements": []}
	var erow := _build(ui, empty)
	_button(erow, "＋ 加一条打出条件").pressed.emit()
	check(empty.play_requirements.size() == 1 and empty.play_requirements[0].type == "min_magic" and empty.play_requirements[0].value == 0, "add button creates min_magic with defaults")

	# 5. 删空 -> 键被删掉
	_button(erow, "删除").pressed.emit()
	check(not empty.has("play_requirements"), "emptied array removes play_requirements key")

	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
