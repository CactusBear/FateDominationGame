extends RefCounted

# 图片放大方式 zoom_kind：可选值来自 types.json 顶层 zoom_kinds；第 0 项「未设」= 删键。
# 当前值不在列表里时保留原值显示，不擅自改掉。
func build(ui, row:Control, obj:Dictionary, key:String, field:Dictionary) -> void:
	var kinds:Array = ui.maker.types.get("zoom_kinds", ["card", "avatar", "token"])
	var cur := str(obj.get(key, ""))
	var menu := OptionButton.new()
	menu.name = "ZoomKindMenu"
	menu.add_item("未设（不填等于还没选图）")
	menu.set_item_metadata(0, "")
	for k in kinds:
		menu.add_item(str(k))
		menu.set_item_metadata(menu.item_count - 1, str(k))
	if cur != "" and not kinds.has(cur):
		menu.add_item(cur + "（未知值）")
		menu.set_item_metadata(menu.item_count - 1, cur)
	for i in menu.item_count:
		if str(menu.get_item_metadata(i)) == cur:
			menu.selected = i
	menu.item_selected.connect(func(i):
		var v := str(menu.get_item_metadata(i))
		if v == "":
			obj.erase(key)
		else:
			obj[key] = v
		ui._changed())
	row.add_child(menu)
