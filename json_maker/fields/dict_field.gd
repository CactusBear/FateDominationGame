extends RefCounted

# 字典字段（values）：键是字符串，值可为 是否/数字/文字/JSON。空字典即删键。
# 改键名先删旧键再写新键；键名重复或 JSON 格式不对时不写回，免得丢值。

const TYPES := ["是否", "数字", "文字", "JSON"]


func build(ui, row:Control, obj:Dictionary, key:String, field:Dictionary) -> void:
	var box := VBoxContainer.new()
	box.name = "DictBox"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	if obj.has(key) and not obj[key] is Dictionary:
		box.add_child(ui._hint("自定义数值应为「键 → 值」字典，当前格式不对，请在右边 JSON 里改"))
		return
	_paint(ui, box, obj, key)


func _paint(ui, box:VBoxContainer, obj:Dictionary, key:String) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var d:Dictionary = obj[key] if obj.get(key) is Dictionary else {}
	var rows := VBoxContainer.new()
	rows.name = "DictRows"
	box.add_child(rows)
	for k in d.keys():
		_entry(ui, rows, obj, key, d, str(k), d[k])
	var add := Button.new()
	add.name = "DictAdd"
	add.text = "＋ 加一项"
	add.pressed.connect(func(): _entry(ui, rows, obj, key, d, "", false))
	box.add_child(add)


# 一行：键名 / 类型 / 值 / 删除 / 行内提示（子节点顺序固定，测试按序号取）
func _entry(ui, rows:VBoxContainer, obj:Dictionary, key:String, d:Dictionary, ks:String, val) -> void:
	var line := HBoxContainer.new()
	rows.add_child(line)
	var name_edit := LineEdit.new()
	name_edit.name = "DictKey"
	name_edit.placeholder_text = "键名"
	name_edit.text = ks
	name_edit.custom_minimum_size = Vector2(120, 0)
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_edit)
	var type_menu := OptionButton.new()
	type_menu.name = "DictType"
	for t in TYPES:
		type_menu.add_item(t)
	type_menu.selected = _type_index(val)
	line.add_child(type_menu)
	var holder := HBoxContainer.new()
	holder.name = "DictValue"
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(holder)
	var del := Button.new()
	del.name = "DictDel"
	del.text = "删除"
	line.add_child(del)
	var warn:Label = ui._hint("")
	warn.add_theme_color_override("font_color", ui.C_WARN)
	warn.visible = false
	line.add_child(warn)

	# st.ks = 当前写在 d 里的键名（空=尚未命名，暂不写入）；st.val = 当前值
	var st := {"ks": ks, "val": val}
	var set_val := func(v):
		st.val = v
		if st.ks != "":
			d[st.ks] = v
			_sync(ui, obj, key, d)
	_value_widget(ui, holder, _type_index(val), val, set_val, warn)

	type_menu.item_selected.connect(func(i):
		st.val = _default_of(i)
		_value_widget(ui, holder, i, st.val, set_val, warn)
		set_val.call(st.val))

	name_edit.text_changed.connect(func(t):
		t = t.strip_edges()
		if t == st.ks:
			return
		if t != "" and d.has(t):
			warn.text = "键名「" + t + "」已存在"
			warn.visible = true
			return
		warn.visible = false
		if st.ks != "":
			d.erase(st.ks)
		st.ks = t
		if t != "":
			d[t] = st.val
		_sync(ui, obj, key, d))

	del.pressed.connect(func():
		if st.ks != "":
			d.erase(st.ks)
			_sync(ui, obj, key, d)
		rows.remove_child(line)
		line.queue_free())


func _value_widget(ui, holder:HBoxContainer, type_i:int, val, set_val:Callable, warn:Label) -> void:
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
	warn.visible = false
	match type_i:
		0:
			var box := CheckBox.new()
			box.button_pressed = bool(val) if val is bool else false
			box.toggled.connect(func(v): set_val.call(v))
			holder.add_child(box)
		1:
			var spin:SpinBox = ui._spin(float(val) if val is int or val is float else 0.0, true)
			spin.value_changed.connect(func(v): set_val.call(int(v) if v == floor(v) else v))
			holder.add_child(spin)
		2:
			var edit := LineEdit.new()
			edit.text = str(val) if val is String else ""
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			edit.text_changed.connect(func(t): set_val.call(t))
			holder.add_child(edit)
		3:
			var edit := LineEdit.new()
			edit.text = JSON.stringify(val)
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			edit.text_changed.connect(func(t):
				var js := JSON.new()
				if js.parse(t) == OK:
					warn.visible = false
					set_val.call(js.data)
				else:
					warn.text = "JSON 格式不对，未写回"
					warn.visible = true)
			holder.add_child(edit)


func _type_index(val) -> int:
	if val is bool:
		return 0
	if val is int or val is float:
		return 1
	if val is String:
		return 2
	return 3


func _default_of(type_i:int):
	match type_i:
		0: return false
		1: return 0
		2: return ""
	return []


func _sync(ui, obj:Dictionary, key:String, d:Dictionary) -> void:
	if d.is_empty():
		obj.erase(key)
	else:
		obj[key] = d
	ui._changed()
