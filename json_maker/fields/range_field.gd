extends RefCounted

# 数量范围 quantity_range = [最小, 最大]（整数）。没有这一键时只给「设置」；清除即删键。
# 格式不对的值不覆盖，只提示去右边 JSON 改，免得丢数据。

func build(ui, row:Control, obj:Dictionary, key:String, field:Dictionary) -> void:
	var box := HBoxContainer.new()
	box.name = "RangeBox"
	row.add_child(box)
	_paint(ui, box, obj, key)


func _paint(ui, box:HBoxContainer, obj:Dictionary, key:String) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	if not obj.has(key):
		box.add_child(ui._hint("未设：选项不要求额外选数量"))
		var set_btn := Button.new()
		set_btn.name = "RangeSet"
		set_btn.text = "设置"
		set_btn.pressed.connect(func():
			obj[key] = [1, 1]
			ui._changed()
			_paint(ui, box, obj, key))
		box.add_child(set_btn)
		return
	var cur = obj[key]
	if not (cur is Array and cur.size() == 2 and (cur[0] is int or cur[0] is float) and (cur[1] is int or cur[1] is float)):
		box.add_child(ui._hint("数量范围应为 [最小, 最大]，当前格式不对，请在右边 JSON 里改"))
		return
	var lo:SpinBox = ui._spin(float(cur[0]), false)
	var hi:SpinBox = ui._spin(float(cur[1]), false)
	lo.name = "RangeMin"
	hi.name = "RangeMax"
	# 最小超过最大时最大跟着走，反过来也一样，保证写回的一定是 最小<=最大
	lo.value_changed.connect(func(v):
		if v > hi.value:
			hi.value = v
		_store(ui, obj, key, lo, hi))
	hi.value_changed.connect(func(v):
		if v < lo.value:
			lo.value = v
		_store(ui, obj, key, lo, hi))
	box.add_child(lo)
	box.add_child(ui._label("～", 13, ui.HINT))
	box.add_child(hi)
	var clear := Button.new()
	clear.name = "RangeClear"
	clear.text = "清除"
	clear.pressed.connect(func():
		obj.erase(key)
		ui._changed()
		_paint(ui, box, obj, key))
	box.add_child(clear)


func _store(ui, obj:Dictionary, key:String, lo:SpinBox, hi:SpinBox) -> void:
	obj[key] = [int(lo.value), int(hi.value)]
	ui._changed()
