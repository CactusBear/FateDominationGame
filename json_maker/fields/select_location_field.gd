extends RefCounted

# 挑席位（选项里的 select_location 对象）：开关 + 目标格下拉 + 两组区域多选。
# 开关开着保留 {}（仍是挑席位，只是不限制）；空串 / 空数组一律删键。
const SLOTS := [["按容量", ""], ["只去无限格", "unlimited"], ["常规移动落点", "move_target"]]
const AREA_LISTS := [["allowed_origin_areas", "只能从这些区域出发"], ["forbidden_target_areas", "不能去这些区域"]]


func build(ui, row:Control, obj:Dictionary, key:String, field:Dictionary) -> void:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(wrap)
	var toggle := Button.new()
	toggle.text = "不挑席位了" if obj.has(key) else "＋ 让玩家挑席位"
	toggle.pressed.connect(func():
		if obj.has(key):
			obj.erase(key)
		else:
			obj[key] = {}
		ui._refresh_scripts())  # 增删整段结构，重画
	wrap.add_child(toggle)
	if not obj.has(key):
		return
	if not obj[key] is Dictionary:
		wrap.add_child(ui._hint("这一项不是对象，请在右边 JSON 里改"))
		return
	var spec:Dictionary = obj[key]

	# 数据里出现未登记的目标格值：原样列出，不替它改写
	var slots:Array = SLOTS.duplicate()
	var slot := str(spec.get("target_slot", ""))
	if not slots.any(func(s): return s[1] == slot):
		slots.append([slot, slot])
	var menu := OptionButton.new()
	for i in slots.size():
		menu.add_item(slots[i][0], i)
		if slots[i][1] == slot:
			menu.select(i)
	menu.item_selected.connect(func(i):
		if slots[i][1] == "":
			spec.erase("target_slot")
		else:
			spec["target_slot"] = slots[i][1]
		ui._changed())
	wrap.add_child(ui._label("目标格", 13, ui.HINT))
	wrap.add_child(menu)

	# 区域候选复用编辑器已有来源 ui._area_groups()（MapData 的战区名）
	var areas:Array = []
	for group in ui._area_groups():
		for item in group.items:
			areas.append(str(item.id))
	for pair in AREA_LISTS:
		var list:String = pair[0]
		var picked:Array = spec.get(list) if spec.get(list) is Array else []
		var choices := areas.duplicate()
		for n in picked:
			if not choices.has(str(n)):
				choices.append(str(n))  # 数据里有候选之外的区域名：也列出来，免得看不见
		wrap.add_child(ui._label(pair[1], 13, ui.HINT))
		var flow := HFlowContainer.new()
		for n in choices:
			var box := CheckBox.new()
			box.text = str(n)
			box.button_pressed = picked.has(str(n))
			# 闭包不能绑到本脚本的方法上：build 返回后实例即释放，绑定的回调会失效
			box.toggled.connect(func(on): _set_area(on, ui, spec, list, str(n)))
			flow.add_child(box)
		wrap.add_child(flow)


# 区域多选的增删；列表空了就删键。
static func _set_area(on:bool, ui, spec:Dictionary, list:String, id:String) -> void:
	var arr:Array = (spec.get(list) as Array).duplicate() if spec.get(list) is Array else []
	if on and not arr.has(id):
		arr.append(id)
	elif not on:
		arr.erase(id)
	if arr.is_empty():
		spec.erase(list)
	else:
		spec[list] = arr
	ui._changed()
