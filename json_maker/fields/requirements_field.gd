extends RefCounted

# 打出条件（play_requirements）编辑器：每条一行「类型下拉 + 参数控件 + 删除」，末尾「＋」。
# 类型与参数全部来自 types.json 的 requirement_types；未知 type 的条目原样保留，只读显示 JSON。
# 数组删空时删掉键（加载器对缺键与空数组都当没有条件）。

var _ui
var _box:VBoxContainer
var _obj:Dictionary
var _key:String


func build(ui, row:Control, obj:Dictionary, key:String, field:Dictionary) -> void:
	_ui = ui
	_obj = obj
	_key = key
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_box)
	_paint()


func _decl() -> Dictionary:
	return _ui.maker.types.get("requirement_types", {})


func _paint() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var reqs = _obj.get(_key)
	if reqs is Array:
		for i in reqs.size():
			_box.add_child(_entry_row(i))
	var add := Button.new()
	add.text = "＋ 加一条打出条件"
	add.pressed.connect(func():
		var keys := _decl().keys()
		if keys.is_empty():
			return
		if not (_obj.get(_key) is Array):
			_obj[_key] = []
		var entry := {}
		_reset(entry, str(keys[0]))
		_obj[_key].append(entry)
		_edited())
	_box.add_child(add)


func _entry_row(i:int) -> Control:
	var entry = _obj[_key][i]
	var line := VBoxContainer.new()
	var top := HBoxContainer.new()
	line.add_child(top)
	var decl := _decl()
	var type := str(entry.get("type", "")) if entry is Dictionary else ""
	if not (entry is Dictionary) or not decl.has(type):
		# 未知条目：保留原样，只读显示
		top.add_child(_ui._label("未知条件（原样保留）", 13, _ui.HINT))
		var text:Label = _ui._hint(JSON.stringify(entry))
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
	else:
		var types := decl.keys()
		var menu := OptionButton.new()
		for t in types:
			menu.add_item(str(decl[t].get("shown", t)))
		menu.selected = types.find(type)
		menu.item_selected.connect(func(idx):
			_reset(entry, str(types[idx]))
			_edited())
		top.add_child(menu)
		for p in decl[type].get("params", []):
			top.add_child(_ui._label(str(p.get("shown", p.key)), 13, _ui.HINT))
			top.add_child(_param_control(entry, p))
	var del := Button.new()
	del.text = "删除"
	del.pressed.connect(func():
		var reqs:Array = _obj[_key]
		reqs.remove_at(i)
		if reqs.is_empty():
			_obj.erase(_key)
		_edited())
	top.add_child(del)
	return line


# 数字用 SpinBox，属性用复选框（与 json_maker_ui 的 attributes 控件同一写法）
func _param_control(entry:Dictionary, p:Dictionary) -> Control:
	var k := str(p.key)
	if str(p.get("control", "int")) == "attributes":
		var flow := HFlowContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for attr in _ui.maker.attributes:
			var cb := CheckBox.new()
			cb.text = str(attr.shown)
			var cur = entry.get(k, [])
			cb.button_pressed = cur is Array and cur.has(attr.id)
			cb.toggled.connect(func(on, id = attr.id):
				if not (entry.get(k) is Array):
					entry[k] = []
				if on and not entry[k].has(id):
					entry[k].append(id)
				elif not on:
					entry[k].erase(id)
				_ui._changed())
			flow.add_child(cb)
		return flow
	var spin:SpinBox = _ui._spin(float(entry.get(k, _default(p))), false)
	spin.value_changed.connect(func(v): entry[k] = int(v); _ui._changed())
	return spin


func _default(p:Dictionary):
	if str(p.get("control", "int")) == "attributes":
		return []
	return int(p.get("default", 0))


# 换类型或新建：清空条目，写入类型与该类型声明的默认参数
func _reset(entry:Dictionary, type:String) -> void:
	entry.clear()
	entry["type"] = type
	for p in _decl()[type].get("params", []):
		entry[p.key] = _default(p)


func _edited() -> void:
	_ui._changed()
	_paint()
