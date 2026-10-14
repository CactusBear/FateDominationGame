extends Node

# select_location 字段编辑器回归：加载库丘林（禁止去魔术工房）与美杜莎（只去无限格）的真实 JSON，
# 断言控件读出的现值，再改控件，断言写回到选项对象里（空值删键）。

const FieldScript = preload("res://json_maker/fields/select_location_field.gd")
const CU := "res://data/servants/00003_cu_chulainn/00003_cu_chulainn.json"
const MEDUSA := "res://data/servants/00004_medusa/00004_medusa.json"

var checks := 0
var failures:Array = []


func check(ok:bool, text:String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
	print("CHECK ", text, " ", ok)


func _ready() -> void:
	call_deferred("run")


# 在 JSON 里找到带 select_location 的选项对象（它本身就是要编辑的 obj）
func find_option(v):
	if v is Dictionary:
		if v.get("select_location") is Dictionary:
			return v
		for k in v:
			var r = find_option(v[k])
			if r != null:
				return r
	elif v is Array:
		for item in v:
			var r = find_option(item)
			if r != null:
				return r
	return null


func collect(node:Node, cls:String, out:Array = []) -> Array:
	if node.is_class(cls):
		out.append(node)
	for c in node.get_children():
		collect(c, cls, out)
	return out


# 整个选项设置区用真实入口 _paint_fields 画出来，再找到「挑地点」那一行
func paint(ui, option:Dictionary) -> Control:
	var parent := VBoxContainer.new()
	add_child(parent)
	ui._paint_fields(parent, option, ui.maker.item_spec("option"))
	for c in parent.get_children():
		if c is HBoxContainer and c.get_child_count() > 0 and c.get_child(0) is Label and str(c.get_child(0).text).begins_with("挑地点"):
			return c
	return null


func menu_of(row:Control) -> OptionButton:
	var menus := collect(row, "OptionButton")
	return menus[0] if not menus.is_empty() else null


# 第 list_index 组多选（0=只能从这些区域出发，1=不能去这些区域）里的某个区域框
func box_of(row:Control, text:String, list_index := 0) -> CheckBox:
	var flows := collect(row, "HFlowContainer")
	if list_index >= flows.size():
		return null
	for b in flows[list_index].get_children():
		if b is CheckBox and b.text == text:
			return b
	return null


# 模拟用户勾选：先看 toggled 是否由 button_pressed 自己触发，没有就补发（记录下来，便于判断）
var toggled_by_code := 0
var toggled_missing := 0
func click(box:CheckBox, on:bool) -> void:
	var fired := [false]
	var probe := func(_v): fired[0] = true
	box.toggled.connect(probe, CONNECT_ONE_SHOT)
	box.button_pressed = on
	if fired[0]:
		toggled_by_code += 1
	else:
		toggled_missing += 1
		box.toggled.emit(on)


func toggle_of(row:Control) -> Button:
	for b in collect(row, "Button"):
		if b.text == "不挑席位了" or b.text == "＋ 让玩家挑席位":
			return b
	return null


func run() -> void:
	var ui = load("res://json_maker/json_maker.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame
	var field_spec := {"key": "select_location", "control": "select_location"}

	# —— 库丘林：禁止去魔术工房，无 target_slot → 按容量 ——
	var cu_option = find_option(ui.maker.read_json(CU))
	check(cu_option != null, "cu_chulainn has select_location option")
	var row = paint(ui, cu_option)
	check(row != null, "cu row rendered with 挑地点 label")
	if row != null:
		check(toggle_of(row).text == "不挑席位了", "cu toggle shows 不挑席位了")
		check(menu_of(row).get_item_text(menu_of(row).selected) == "按容量", "cu target slot reads 按容量")
		check(box_of(row, "魔术工房", 1).button_pressed, "cu forbidden 魔术工房 is checked")
		check(not box_of(row, "新都").button_pressed and not box_of(row, "深山町").button_pressed, "cu other areas unchecked")
		check(box_of(row, "新都") != null and box_of(row, "侦察") != null and box_of(row, "深山町") != null, "cu area candidates are MapData areas")
		var allowed_boxes := 0
		for b in collect(row, "CheckBox"):
			if b.text == "魔术工房" or b.text == "新都" or b.text == "深山町" or b.text == "侦察":
				allowed_boxes += 1
		check(allowed_boxes == 8, "both lists each show the 4 areas (8 boxes) got " + str(allowed_boxes))
		# 写回：目标格改常规移动落点
		menu_of(row).select(2)
		menu_of(row).item_selected.emit(2)
		check(cu_option.select_location.get("target_slot") == "move_target", "cu writes target_slot=move_target")
		# 写回：去掉唯一的禁止区域 → 键删掉
		click(box_of(row, "魔术工房", 1), false)
		check(not cu_option.select_location.has("forbidden_target_areas"), "cu empty forbidden list erases key")
		# 写回：加一个出发区域
		click(box_of(row, "新都"), true)
		click(box_of(row, "深山町"), true)
		check(cu_option.select_location.get("allowed_origin_areas") == ["新都", "深山町"], "cu writes allowed_origin_areas")
		# 写回：目标格回到按容量 → 删 target_slot
		menu_of(row).select(0)
		menu_of(row).item_selected.emit(0)
		check(not cu_option.select_location.has("target_slot"), "back to 按容量 erases target_slot")

	# —— 美杜莎：只去无限格，无禁止区域 ——
	var medusa_option = find_option(ui.maker.read_json(MEDUSA))
	check(medusa_option != null, "medusa has select_location option")
	row = paint(ui, medusa_option)
	check(row != null, "medusa row rendered")
	if row != null:
		check(menu_of(row).get_item_text(menu_of(row).selected) == "只去无限格", "medusa target slot reads 只去无限格")
		var any_pressed := false
		for b in collect(row, "CheckBox"):
			any_pressed = any_pressed or b.button_pressed
		check(not any_pressed, "medusa no area checked")
		click(box_of(row, "魔术工房", 1), true)
		check(medusa_option.select_location.get("forbidden_target_areas") == ["魔术工房"], "medusa writes forbidden 魔术工房")
		check(medusa_option.select_location.get("target_slot") == "unlimited", "medusa keeps target_slot unchanged")
		menu_of(row).select(0)
		menu_of(row).item_selected.emit(0)
		check(not medusa_option.select_location.has("target_slot"), "medusa 按容量 erases target_slot")

	# —— 开关：没有键 → 打开得到 {}，再点关掉删键 ——
	var bare := {"shown_option_name": "x"}
	row = paint(ui, bare)
	check(row != null and toggle_of(row).text == "＋ 让玩家挑席位", "no key shows 让玩家挑席位")
	if row != null:
		toggle_of(row).pressed.emit()
		check(bare.get("select_location") is Dictionary and bare.select_location.is_empty(), "switch on writes empty {}")
		row = paint(ui, bare)
		toggle_of(row).pressed.emit()
		check(not bare.has("select_location"), "switch off erases select_location")

	# —— 未登记的目标格值：原样显示，不改写 ——
	var odd := {"select_location": {"target_slot": "mystery"}}
	row = paint(ui, odd)
	check(row != null and menu_of(row).get_item_text(menu_of(row).selected) == "mystery", "unknown target_slot shown as-is")

	print("INFO toggled_by_code=", toggled_by_code, " toggled_missing=", toggled_missing)
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
