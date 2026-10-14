extends RefCounted

# 选项的「挑牌」字段：option.select_cards = {candidates:[积木串], mandatory_candidates:[积木串，可选], min, max(-1=不限)}。
# 积木串由 ui.field_stack 缓存、ui._commit 统一写回；这里只管界面与增删结构。

func build(ui, row:Control, obj:Dictionary, key:String, field:Dictionary) -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	if not obj.get(key) is Dictionary:
		var add := Button.new()
		add.name = "SelectCardsAdd"
		add.text = "＋ 让玩家挑牌"
		add.pressed.connect(func():
			obj[key] = {"candidates": [], "min": 1, "max": 1}
			ui._refresh_scripts())
		box.add_child(add)
		return
	var spec:Dictionary = obj[key]
	var off := Button.new()
	off.name = "SelectCardsRemove"
	off.text = "不挑牌了"
	off.pressed.connect(func():
		obj.erase(key)
		_forget(ui, spec, "")
		ui._refresh_scripts())
	box.add_child(off)
	# 最少/最多：最多 -1 表示不限
	var counts := HBoxContainer.new()
	box.add_child(counts)
	counts.add_child(ui._label("最少张", 13, ui.HINT))
	var lo:SpinBox = ui._spin(float(spec.get("min", 1)), false)
	lo.name = "SelectCardsMin"
	lo.min_value = 0
	lo.allow_lesser = false   # 张数不能为负，_spin 默认允许越界
	lo.value_changed.connect(func(v): spec["min"] = int(v); ui._changed())
	counts.add_child(lo)
	counts.add_child(ui._label("最多张（-1 不限）", 13, ui.HINT))
	var hi:SpinBox = ui._spin(float(spec.get("max", 1)), false)
	hi.name = "SelectCardsMax"
	hi.min_value = -1
	hi.allow_lesser = false   # -1 以下没有意义
	hi.value_changed.connect(func(v): spec["max"] = int(v); ui._changed())
	counts.add_child(hi)
	# 候选牌：积木算出能挑的牌，最后一块给出的列表即候选
	box.add_child(ui._hint("候选牌：一串积木，最后一块给出的列表就是能挑的牌。"))
	box.add_child(ui._stack_view(ui.field_stack(spec, "candidates"), "requirement"))
	# 必须选中的牌：可选，关掉即删除该键
	var has_mandatory:bool = spec.has("mandatory_candidates")
	var toggle := CheckBox.new()
	toggle.name = "SelectCardsMandatory"
	toggle.text = "必须选中的牌（可选）"
	toggle.button_pressed = has_mandatory
	toggle.toggled.connect(func(on):
		if on:
			spec["mandatory_candidates"] = []
		else:
			spec.erase("mandatory_candidates")
			_forget(ui, spec, "mandatory_candidates")
		ui._refresh_scripts())
	box.add_child(toggle)
	if has_mandatory:
		box.add_child(ui._stack_view(ui.field_stack(spec, "mandatory_candidates"), "requirement"))


# 删掉缓存的积木串（结构已删），否则 _commit 会把它写回已经去掉的键。
func _forget(ui, holder:Dictionary, key:String) -> void:
	for i in range(ui.field_stacks.size() - 1, -1, -1):
		var entry:Dictionary = ui.field_stacks[i]
		if is_same(entry.holder, holder) and (key == "" or entry.key == key):
			ui.field_stacks.remove_at(i)
