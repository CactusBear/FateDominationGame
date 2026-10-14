extends RefCounted

# 其他面：每一面是一份完整卡面字典，用本卡同类的卡面字段渲染（fields 里去掉 faces 自身，lists 效果不进来，避免递归）。
# 面上的效果积木仍在右边 JSON 里改。
# shortcut: 「加一面」只复制卡面 fields 的值（效果/分组不复制），需要时在右边 JSON 补，升级时改为复制整份面的全部子列表。
func build(ui, row:Control, obj:Dictionary, key:String, field:Dictionary) -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	var spec:Dictionary = ui._focus_spec().duplicate(true)
	spec.erase("identity")
	spec.fields = spec.get("fields", []).filter(func(f): return str(f.key) != key)
	var faces:Array = obj[key] if obj.get(key) is Array else []
	if faces.is_empty():
		box.add_child(ui._hint("还没有其他面。"))
	for i in faces.size():
		if not faces[i] is Dictionary:
			continue
		var idx := i
		var face:Dictionary = faces[i]
		var fold = ui._fold_box(box, ui._owner_name(face, "第 %d 面" % (i + 1)), false)
		ui._paint_fields(fold, face, spec)
		var remove := Button.new()
		remove.text = "删掉这一面"
		remove.pressed.connect(func():
			obj[key].remove_at(idx)
			if obj[key].is_empty():
				obj.erase(key)
			ui._changed()
			ui.call_deferred("focus_to", ui.focus_path, ui.focus_item))
		fold.add_child(remove)
	box.add_child(ui._hint("面上的效果积木请在右边 JSON 里改；翻面效果按下标切换。"))
	var add := Button.new()
	add.text = "＋ 加一面"
	add.pressed.connect(func():
		var face := {}
		for f in spec.fields:
			var v = obj.get(f.key)
			if v != null:
				face[f.key] = v.duplicate(true) if v is Dictionary or v is Array else v
		if not obj.get(key) is Array:
			obj[key] = []
		obj[key].append(face)
		ui._changed()
		ui.call_deferred("focus_to", ui.focus_path, ui.focus_item))
	box.add_child(add)
