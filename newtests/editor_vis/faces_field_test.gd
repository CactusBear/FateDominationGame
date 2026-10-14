extends Node

# 其他面字段编辑器回归：构造一张带 faces 的攻击牌，通过界面按钮增删面，改某一面的威力，检查写回的数据。
var checks := 0
var failures:Array = []


func check(ok:bool, text:String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
	print("CHECK ", text, " ", ok)


func _ready() -> void:
	call_deferred("run")


# 在整棵子树里找按钮（按文字）
func _buttons(root:Node, text:String, out:Array = []) -> Array:
	if root is Button and root.text == text:
		out.append(root)
	for c in root.get_children():
		_buttons(c, text, out)
	return out


# 第 i 面的面板 = 「删掉这一面」按钮的父节点（按钮与该面字段同处一个框里）
func _face_box(ui, i:int) -> Node:
	return _buttons(ui.card_box, "删掉这一面")[i].get_parent()


# 某一面里「威力」那一行的 SpinBox
func _face_power_spin(ui, i:int) -> SpinBox:
	return _power_spin(_face_box(ui, i))


func _power_spin(root:Node) -> SpinBox:
	if root is HBoxContainer and root.get_child_count() > 1 and root.get_child(0) is Label and str(root.get_child(0).text).begins_with("威力") and root.get_child(1) is SpinBox:
		return root.get_child(1)
	for c in root.get_children():
		var hit := _power_spin(c)
		if hit != null:
			return hit
	return null


func _settle(ui) -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func run() -> void:
	var ui = load("res://json_maker/json_maker.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame

	# 构造攻击牌：取 luck.json 的基础字段，威力 4，无效果
	var base:Dictionary = ui.maker.read_json("res://data/attacks/basic/luck/luck.json")
	base.erase("faces")
	base.effects = []
	var tmp := "user://faces_probe_luck.json"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string(JSON.stringify(base, "\t"))
	f.close()
	ui.open_path(ProjectSettings.globalize_path(tmp))
	ui.card_kind = "attack"
	ui._paint_card()
	await _settle(ui)
	check(not ui.data.has("faces"), "start: no faces key")
	check(_buttons(ui.card_box, "删掉这一面").is_empty(), "start: no face panel")

	# 加一面：复制基础字段，威力也复制
	_buttons(ui.card_box, "＋ 加一面")[0].pressed.emit()
	await _settle(ui)
	check(ui.data.has("faces") and ui.data.faces.size() == 1, "add face: 1 face written")
	check(ui.data.faces[0].get("power", {}).get("number") == 4, "new face copies power 4")
	check(ui.data.faces[0].get("attack_name") == "luck", "new face copies identity field")
	check(not ui.data.faces[0].has("effects"), "new face does not copy effects")

	# 改第 1 面威力为 9，基础威力应保持 4
	check(_face_power_spin(ui, 0) != null, "face 1 has a power spin")
	_face_power_spin(ui, 0).value = 9
	await _settle(ui)
	check(ui.data.faces[0].power.number == 9, "face power written back: 9")
	check(ui.data.power.number == 4, "base power untouched: 4")

	# 再加一面，第二面威力改 7，两面互不影响
	_buttons(ui.card_box, "＋ 加一面")[0].pressed.emit()
	await _settle(ui)
	check(ui.data.faces.size() == 2, "second face added")
	check(ui.data.faces[1].power.number == 4, "second face copies base power 4 (not face 1's 9)")
	_face_power_spin(ui, 1).value = 7
	await _settle(ui)
	check(ui.data.faces[1].power.number == 7 and ui.data.faces[0].power.number == 9, "edit second face only")

	# 删掉第 1 面，剩第 2 面威力 7
	_buttons(ui.card_box, "删掉这一面")[0].pressed.emit()
	await _settle(ui)
	check(ui.data.faces.size() == 1 and ui.data.faces[0].power.number == 7, "remove face 1: remaining power 7")

	# 删掉最后一面，faces 键被删掉
	_buttons(ui.card_box, "删掉这一面")[0].pressed.emit()
	await _settle(ui)
	check(not ui.data.has("faces"), "remove last face erases faces key")
	check(_buttons(ui.card_box, "删掉这一面").is_empty(), "no face panel after removing all")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
