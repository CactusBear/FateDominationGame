extends RefCounted

# 「挑玩家」字段编辑器：obj[key] = {"candidates":[积木描述...], "min":N, "max":N}；有此键即开启挑人，无则不挑。
# 候选积木用 ui.field_stack 缓存、ui._commit 统一写回，这里不直接改 candidates。
func build(ui, row:Control, obj:Dictionary, key:String, field:Dictionary) -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	var toggle := Button.new()
	toggle.name = "SelectPlayersToggle"
	box.add_child(toggle)
	if not obj.get(key) is Dictionary:
		toggle.text = "＋ 让玩家挑目标"
		toggle.pressed.connect(func():
			obj[key] = {"candidates": [], "min": 1, "max": 1}
			ui._refresh_scripts())
		box.add_child(ui._hint("不挑目标时这一项直接生效。"))
		return
	toggle.text = "不挑目标了"
	toggle.pressed.connect(func():
		obj.erase(key)
		ui._refresh_scripts())
	var sp:Dictionary = obj[key]
	var nums := HBoxContainer.new()
	box.add_child(nums)
	nums.add_child(ui._label("最少", 13))
	nums.add_child(_count_spin(ui, sp, "min", "SelectPlayersMin"))
	nums.add_child(ui._label("最多", 13))
	nums.add_child(_count_spin(ui, sp, "max", "SelectPlayersMax"))
	nums.add_child(ui._hint("-1 = 不限"))
	box.add_child(ui._label("候选玩家（积木算出玩家编号；最少 > 0 且候选为空时这一项不可选）", 13))
	box.add_child(ui._stack_view(ui.field_stack(sp, "candidates"), "candidates"))


# 人数框：只允许 -1（不限）及以上整数
func _count_spin(ui, sp:Dictionary, k:String, node_name:String) -> SpinBox:
	var spin:SpinBox = ui._spin(float(sp.get(k, 1)), false)
	spin.name = node_name
	spin.allow_lesser = false
	spin.allow_greater = false
	spin.min_value = -1
	spin.max_value = 99
	spin.value_changed.connect(func(v):
		sp[k] = int(v)
		ui._changed())
	return spin
