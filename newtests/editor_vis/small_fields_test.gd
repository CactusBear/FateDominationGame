extends Node

# 小控件（范围 / 放大方式 / 字典）headless 测试：开编辑器拿真 ui 与 types，用真实樱与 luck 数据验读值、改写回、空值删键。
var checks := 0
var failures:Array = []


func check(ok:bool, text:String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
	print("CHECK ", text, " ", ok)


func _ready() -> void:
	call_deferred("run")


func _json(path:String):
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func run() -> void:
	var ui = load("res://json_maker/json_maker.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame

	# ---------- range ----------
	var range_field = preload("res://json_maker/fields/range_field.gd").new()
	var obj := {}
	var row := HBoxContainer.new()
	add_child(row)
	range_field.build(ui, row, obj, "quantity_range", {})
	var box:HBoxContainer = row.get_node("RangeBox")
	check(not obj.has("quantity_range") and box.find_child("RangeSet", true, false) != null, "range: 未设时只显示「设置」且不写键")
	box.find_child("RangeSet", true, false).pressed.emit()
	check(obj.get("quantity_range") == [1, 1], "range: 点设置写 [1,1] " + str(obj.get("quantity_range")))
	var lo:SpinBox = box.find_child("RangeMin", true, false)
	var hi:SpinBox = box.find_child("RangeMax", true, false)
	check(lo != null and hi != null and lo.value == 1 and hi.value == 1, "range: 读出两端 1/1")
	lo.value = 0
	hi.value = 4
	check(obj.get("quantity_range") == [0, 4], "range: 修改写回 [0,4] " + str(obj.get("quantity_range")))
	lo.value = 6
	check(obj.get("quantity_range") == [6, 6] and hi.value == 6, "range: 最小超过最大时最大跟随 " + str(obj.get("quantity_range")))
	box.find_child("RangeClear", true, false).pressed.emit()
	check(not obj.has("quantity_range"), "range: 清除删键")
	obj["quantity_range"] = "bad"
	var row2 := HBoxContainer.new()
	add_child(row2)
	range_field.build(ui, row2, obj, "quantity_range", {})
	check(row2.get_node("RangeBox").find_child("RangeMin", true, false) == null and obj["quantity_range"] == "bad", "range: 格式不对不显示控件且不覆盖原值")

	# ---------- zoom_kind (luck 攻击牌 zoom_kind=card) ----------
	var zoom_field = preload("res://json_maker/fields/zoom_kind_field.gd").new()
	var luck:Dictionary = _json("res://data/attacks/basic/luck/luck.json")
	var zrow := HBoxContainer.new()
	add_child(zrow)
	zoom_field.build(ui, zrow, luck, "zoom_kind", {})
	var menu:OptionButton = zrow.get_node("ZoomKindMenu")
	check(menu.get_item_text(menu.selected) == "card" and luck.zoom_kind == "card", "zoom: 读出现值 card")
	check(menu.item_count == 4, "zoom: 选项=未设+card/avatar/token 共4，实际 " + str(menu.item_count))
	menu.select(2)
	menu.item_selected.emit(2)
	check(luck.zoom_kind == "avatar", "zoom: 改为 avatar 写回")
	menu.select(0)
	menu.item_selected.emit(0)
	check(not luck.has("zoom_kind"), "zoom: 选未设删键")
	var odd := {"zoom_kind": "foo"}
	var zrow2 := HBoxContainer.new()
	add_child(zrow2)
	zoom_field.build(ui, zrow2, odd, "zoom_kind", {})
	var menu2:OptionButton = zrow2.get_node("ZoomKindMenu")
	check(menu2.get_item_text(menu2.selected) == "foo（未知值）" and odd.zoom_kind == "foo", "zoom: 未知值保留显示且不被覆盖")

	# ---------- dict (樱 upgrade_skill[0].values) ----------
	var dict_field = preload("res://json_maker/fields/dict_field.gd").new()
	var sakura:Dictionary = _json("res://data/masters/00004_matou_sakura/00004_matou_sakura.json")
	var skill:Dictionary = sakura.upgrade_skill[0]
	var drow := HBoxContainer.new()
	add_child(drow)
	dict_field.build(ui, drow, skill, "values", {})
	var dbox:VBoxContainer = drow.get_node("DictBox")
	var rows:VBoxContainer = dbox.get_node("DictRows")
	check(rows.get_child_count() == 2, "dict: 樱技能 values 显示 2 行 " + str(rows.get_child_count()))
	var r0:HBoxContainer = rows.get_child(0)
	var r1:HBoxContainer = rows.get_child(1)
	check(r0.get_node("DictKey").text == "awaken_last_round" and r0.get_node("DictType").selected == 1, "dict: 键名与数字类型读出")
	var spin:SpinBox = r0.get_node("DictValue").get_child(0)
	check(spin.value == 4, "dict: 数字值读出 4")
	spin.value = 6
	check(skill.values.awaken_last_round == 6, "dict: 改数字写回 6")
	check(r1.get_node("DictType").selected == 2, "dict: 文字值类型为文字")
	var txt:LineEdit = r1.get_node("DictValue").get_child(0)
	check(txt.text == "corrosion", "dict: 文字值读出 corrosion")
	txt.text = "rust"
	txt.text_changed.emit("rust")
	check(skill.values.ability_buff == "rust", "dict: 改文字写回")
	# 改键名
	var kedit:LineEdit = r1.get_node("DictKey")
	kedit.text = "x"
	kedit.text_changed.emit("x")
	check(skill.values.keys().has("x") and not skill.values.has("ability_buff"), "dict: 改键名 先删旧键写新键 " + str(skill.values.keys()))
	# 重复键名不写回
	kedit.text = "awaken_last_round"
	kedit.text_changed.emit("awaken_last_round")
	check(skill.values.has("x") and skill.values.awaken_last_round == 6, "dict: 键名重复不覆盖已有键")
	# 加一项 + 是否
	dbox.get_node("DictAdd").pressed.emit()
	check(rows.get_child_count() == 3, "dict: 加一项新增一行")
	var r2:HBoxContainer = rows.get_child(2)
	r2.get_node("DictKey").text = "active"
	r2.get_node("DictKey").text_changed.emit("active")
	check(skill.values.get("active") == false, "dict: 新项默认是否=false，命名后写入")
	r2.get_node("DictType").select(0)
	r2.get_node("DictType").item_selected.emit(0)
	var cb:CheckBox = r2.get_node("DictValue").get_child(0)
	cb.button_pressed = true
	cb.toggled.emit(true)
	check(skill.values.active == true, "dict: 是否勾选写回 true")
	# JSON 类型
	r2.get_node("DictType").select(3)
	r2.get_node("DictType").item_selected.emit(3)
	var je:LineEdit = r2.get_node("DictValue").get_child(0)
	je.text = "[1,2]"
	je.text_changed.emit("[1,2]")
	check(skill.values.active is Array and skill.values.active.size() == 2, "dict: JSON 类型写回数组")
	je.text = "[1,"
	je.text_changed.emit("[1,")
	check(skill.values.active is Array and skill.values.active.size() == 2, "dict: JSON 不合法时不写回")
	# 删除全部 → 删键
	for r in [r0, r1, r2]:
		r.get_node("DictDel").pressed.emit()
	check(not skill.has("values"), "dict: 全部删除后删键")
	dbox.get_node("DictAdd").pressed.emit()
	check(not skill.has("values") and rows.get_child_count() == 1, "dict: 空字典未命名前不写键")
	# 格式不对的字段不覆盖
	var bad := {"values": 3}
	var brow := HBoxContainer.new()
	add_child(brow)
	dict_field.build(ui, brow, bad, "values", {})
	check(bad.values == 3 and brow.get_node("DictBox").get_child_count() == 1, "dict: 非字典值只提示不覆盖")

	var total := checks
	print("RESULT checks=", total, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
