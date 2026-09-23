extends Node

# 积木编辑器界面回归：打开每一张卡、渲染积木、提交回 JSON，未改动时必须与原文语义一致；
# 再模拟拖一块新积木进空位与缝隙，检查生成的 JSON。
const Codec = preload("res://json_maker/json_codec.gd")

var checks := 0
var failures:Array = []


func check(ok:bool, text:String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
	print("CHECK ", text, " ", ok)


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var ui = load("res://json_maker/json_maker.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame
	check(ui.palette_box.get_child_count() > 50, "palette filled " + str(ui.palette_box.get_child_count()))
	var opened := 0
	var subs := 0
	var bad:Array = []
	for k in ui.kind_button.item_count:
		ui.kind_button.select(k)
		ui._select_kind(k)
		for i in ui.file_list.item_count:
			var path := str(ui.file_list.get_item_metadata(i))
			var original = ui.maker.read_json(path)
			ui.open_path(path)
			ui._paint_scripts()
			ui._commit()
			# 逐个进入子牌，同样不改动就提交
			for e in range(1, ui.sub_entries.size()):
				ui._focus_entry(e)
				subs += 1
			ui._commit()
			opened += 1
			if not Codec.same(ui.data, original):
				bad.append(path)
				if bad.size() == 1:
					_diff(original, ui.data, "")
	check(opened > 60, "opened every card " + str(opened))
	check(subs > 50, "visited sub cards " + str(subs))
	check(bad.is_empty(), "untouched cards commit unchanged " + str(bad.slice(0, 5)))

	# 新建一张攻击牌，加效果，把「魔力加 N」拖进去，再把「还在场的玩家」这种报告积木拖进空位
	var idx := -1
	for k in ui.kind_button.item_count:
		if str(ui.kind_button.get_item_metadata(k)) == "attack":
			idx = k
	ui._select_kind(idx)
	ui._new_card()
	ui._add_effect()
	ui._paint_scripts()
	var view:Dictionary = ui.effects_view[0]
	var zone = _find_drop(ui.script_box, "stack")
	check(zone != null, "empty stack shows a drop zone")
	var payload := {"new": {"kind": "op", "func": "edit_magic"}}
	check(ui._can_drop_on(Vector2.ZERO, payload, zone), "stack accepts a new block")
	ui._drop_on(Vector2.ZERO, payload, zone)
	await get_tree().process_frame
	await get_tree().process_frame
	check(view.lists.funcs.size() == 1 and view.lists.funcs[0].func == "edit_magic", "block placed in stack")
	var slot = _find_drop(ui.script_box, "slot")
	check(slot != null, "block exposes slots")
	var rep := {"new": {"kind": "op", "func": "get_current_round"}}
	check(ui._can_drop_on(Vector2.ZERO, rep, slot), "slot accepts reporter")
	ui._drop_on(Vector2.ZERO, rep, slot)
	await get_tree().process_frame
	ui._commit()
	var funcs:Array = ui.data.effects[0].funcs
	check(funcs.size() == 2 and funcs[0].func_name == "get_current_round", "reporter hoisted before its user")
	check(funcs[1].func_name == "edit_magic" and funcs[1].parameters[2] is Dictionary and funcs[1].parameters[2].has("self_var"), "user reads reporter var " + JSON.stringify(funcs))
	check(funcs[1].parameters[1] is Dictionary and funcs[1].parameters[1].has("number_index"), "skipped optional number slot gets its default as an effect number")
	check(ui.data.effects[0].effect_numbers.size() == 1 and float(ui.data.effects[0].effect_numbers[0].number) == 0.0, "default number recorded")
	# 插到两块积木中间：先在末尾再接一块，然后把第三块拖到第二块积木的上半截
	var tail_zone = _find_drop(ui.script_box, "stack", true)
	ui._drop_on(Vector2.ZERO, {"new": {"kind": "op", "func": "edit_score"}}, tail_zone)
	await get_tree().process_frame
	await get_tree().process_frame
	var mid_list:Array = ui.effects_view[0].lists.funcs
	check(mid_list.size() == 2 and mid_list[1].func == "edit_score", "second block appended " + str(mid_list.map(func(n): return n.get("func"))))
	var second_block = _block_panel(ui.script_box, "edit_score")
	check(second_block != null and second_block.has_meta("drop_fn"), "a placed block accepts drops itself")
	var mid_payload := {"new": {"kind": "op", "func": "edit_power"}}
	check(ui._can_drop_on(Vector2(4, 1), mid_payload, second_block), "upper half of a block accepts insertion")
	check(ui.drop_marker.visible, "insertion line shows while hovering")
	ui._drop_on(Vector2(4, 1), mid_payload, second_block)
	check(not ui.drop_marker.visible, "insertion line hides after drop")
	await get_tree().process_frame
	await get_tree().process_frame
	mid_list = ui.effects_view[0].lists.funcs
	check(mid_list.size() == 3 and mid_list[1].func == "edit_power" and mid_list[2].func == "edit_score", "block inserted between two blocks " + str(mid_list.map(func(n): return n.get("func"))))
	# 拖已有积木到别的积木下半截：换位置
	var first_block = _block_panel(ui.script_box, "edit_magic")
	var last_block = _block_panel(ui.script_box, "edit_score")
	for _i in 10:
		if last_block.size.y > 0:
			break
		await get_tree().process_frame
	check(last_block.size.y > 0, "placed block laid out " + str(last_block.size))
	ui._drop_on(Vector2(4, last_block.size.y - 1), {"node": mid_list[0], "from": {"list": mid_list, "index": 0}}, last_block)
	await get_tree().process_frame
	await get_tree().process_frame
	mid_list = ui.effects_view[0].lists.funcs
	check(mid_list.map(func(n): return n.get("func")) == ["edit_power", "edit_score", "edit_magic"], "moving onto lower half puts block after target " + str(mid_list.map(func(n): return n.get("func"))))
	# 每块积木都显示删除键，点了就删
	var del_btn = _delete_button_of(ui.script_box, "edit_power")
	check(del_btn != null and del_btn.visible, "placed block shows a delete button")
	check(_delete_button_of(ui.palette_box, "edit_power") == null, "palette blocks have no delete button")
	del_btn.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	mid_list = ui.effects_view[0].lists.funcs
	check(mid_list.map(func(n): return n.get("func")) == ["edit_score", "edit_magic"], "delete button removes the block " + str(mid_list.map(func(n): return n.get("func"))))
	var inner_del = _delete_button_of(ui.script_box, "get_current_round")
	check(inner_del != null, "block inside a slot also shows a delete button")
	inner_del.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var magic_node:Dictionary = ui.effects_view[0].lists.funcs[1]
	check(str(magic_node.params[2].get("s", "")) == "lit" and magic_node.params[2].get("v") == null, "deleting a nested block empties its slot")
	ui.effects_view[0].lists.funcs.clear()
	ui._paint_scripts()
	# 如果 积木
	var zone2 = _find_drop(ui.script_box, "stack")
	ui._drop_on(Vector2.ZERO, {"new": {"kind": "if"}}, zone2)
	await get_tree().process_frame
	check(ui.effects_view[0].lists.funcs.size() == 1 and ui.effects_view[0].lists.funcs[0].t == "if", "if block added")
	var issues:Array = ui._collect_issues()
	var has_if_issue := false
	for s in issues:
		if str(s).find("如果") != -1:
			has_if_issue = true
	check(has_if_issue, "empty if condition is reported")
	# 保存：打开一张真实卡、不改动，另存到临时目录，字节必须与原文件一致（缩进与换行照原样）
	for k in ui.kind_button.item_count:
		if str(ui.kind_button.get_item_metadata(k)) == "master":
			ui._select_kind(k)
	var src := "res://data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json"
	ui.open_path(src)
	var tmp := "res://reports/json_save_probe/json_save_probe.json"
	ui._save_to(ProjectSettings.globalize_path(tmp))
	check(FileAccess.file_exists(tmp), "save wrote file")
	check(Codec.same(ui.maker.read_json(tmp), ui.maker.read_json(src)), "saved copy keeps meaning")
	check(FileAccess.get_file_as_string(tmp).begins_with("{\r\n  \""), "saved copy keeps original indent and line endings")
	var before := FileAccess.get_file_as_bytes(src)
	ui._select_kind(0)
	ui.open_path(src)
	check(ui.card_kind == "master", "card kind follows the file, not the dropdown")
	ui._save_to(ProjectSettings.globalize_path(src))
	check(FileAccess.get_file_as_bytes(src) == before and ui.status.text.find("没有改动") != -1, "saving an untouched card does not rewrite it")
	check(FileAccess.file_exists("res://reports/json_save_probe/00002_tohsaka_rin_header.png"), "save as elsewhere carries images beside json")
	OS.move_to_trash(ProjectSettings.globalize_path("res://reports/json_save_probe"))
	# 真实点击：积木区点一块 → 右边说明变成这块的说明
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		var block:Control = null
		for c in ui.palette_box.get_children():
			if c is HBoxContainer and c.get_child_count() > 0:
				block = c.get_child(0)
				break
		var r := block.get_global_rect()
		await _click(r.position + Vector2(8, r.size.y * 0.5))
		check(ui.help_title.text != "怎么用", "clicking palette block shows its help: " + ui.help_title.text)
	# 子牌编辑：进入远坂凛的一张附带物，改名字、加一条效果，只落在那张子牌上
	ui.open_path(src)
	var target_entry := -1
	for e in ui.sub_entries.size():
		if ui.sub_entries[e].path.size() == 2 and str(ui.sub_entries[e].path[0]) == "other_master_things":
			target_entry = e
			break
	check(target_entry > 0, "sub list lists attached things")
	ui._focus_entry(target_entry)
	var sub_obj:Dictionary = ui._focus_obj()
	var before_effects:int = (sub_obj.get("effects", []) as Array).size()
	var body_effects:int = ui.data.effects.size()
	ui._add_effect()
	await get_tree().process_frame
	check((sub_obj.effects as Array).size() == before_effects + 1 and ui.data.effects.size() == body_effects, "effect added to the focused sub card only")
	check(ui.card_box.get_child_count() > 0 and ui.effects_view.size() == before_effects + 1, "card panel and scripts follow the sub card")
	ui.focus_to([], "")
	check(ui.effects_view.size() == body_effects, "back to body shows body effects")

	# 修改记录：改两次 → 撤回 → 重做 → 点记录回到起点
	ui.open_path(src)
	check(ui.history.size() == 1 and ui.undo_button.disabled, "opening starts a fresh history")
	var name_before = ui.data.get("shown_master_name")
	ui.data["shown_master_name"] = "改名一"
	ui._changed()
	ui.data["effects"] = []
	ui._changed()
	check(ui.history.size() == 3 and ui.history_view.item_count == 3, "each distinct change is a history node " + str(ui.history.size()))
	ui.undo()
	check(ui.data.get("shown_master_name") == "改名一" and not ui.redo_button.disabled, "undo restores previous node")
	ui.redo()
	check((ui.data.effects as Array).is_empty(), "redo reapplies change")
	ui._restore_history(0)
	check(ui.data.get("shown_master_name") == name_before and not ui.dirty, "jump to a history node restores it and clears dirty at saved node")
	check(ui.history.size() == 3, "jumping back keeps later nodes for redo")

	# 导出：命名规则按 data 现有结构；新选的图搬进 json 所在文件夹并按规则改名；打包 zip
	check(ui.maker.folder_for("master", {"master_name": "tohsaka_rin"}) == "00002_tohsaka_rin", "existing serial reused")
	check(ui.maker.folder_for("master", {"master_name": "new_probe_master"}).ends_with("_new_probe_master") and ui.maker.folder_for("master", {"master_name": "new_probe_master"}).length() == 5 + 1 + 16, "new master gets next 5-digit serial")
	check(ui.maker.suggest_path("attack", {"attack_name": "probe_x", "category": "basic"}) == "res://data/attacks/basic/probe_x/probe_x.json", "attack folder follows category")
	check(ui.maker.suggest_path("event", {"card_name": "probe_e"}) == "res://data/events/origin/probe_e/probe_e.json", "event folder uses declared default pack")
	var exp_root := "res://reports/export_probe/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(exp_root))
	var card := {"master_name": "probe_m", "header_img": ProjectSettings.globalize_path("res://icon.svg"), "specials": {"SKILLS": [{"skill_name": "probe_skill", "skill_card_img": ProjectSettings.globalize_path("res://icon.svg")}]}}
	var folder := exp_root + "00009_probe_m"
	var placed:Dictionary = ui.maker.place_images(card, "master", folder, "")
	check(placed.missing.is_empty() and card.header_img == "00009_probe_m_header.svg" and card.specials.SKILLS[0].skill_card_img == "00009_probe_m_probe_skill.svg", "picked images renamed like existing data " + JSON.stringify(card))
	check(FileAccess.file_exists(folder + "/00009_probe_m_header.svg") and FileAccess.file_exists(folder + "/00009_probe_m_probe_skill.svg"), "images copied beside json")
	var lost := {"master_name": "probe_m", "header_img": "no_such.png"}
	check(not ui.maker.place_images(lost, "master", folder, "").missing.is_empty(), "missing image is reported")
	ui.maker.save_file(folder + "/00009_probe_m.json", card, "master")
	var zipped:Dictionary = ui.maker.zip_files(ui.maker.card_files(card, "master", folder + "/00009_probe_m.json"), exp_root + "probe.zip", "res://")
	var reader := ZIPReader.new()
	reader.open(ProjectSettings.globalize_path(exp_root + "probe.zip"))
	var entries := Array(reader.get_files()).filter(func(e): return not str(e).ends_with("/"))
	reader.close()
	check(zipped.ok and entries.size() == 3 and entries.has("reports/export_probe/00009_probe_m/00009_probe_m.json"), "zip keeps project-relative layout " + str(entries))
	# 用户导出设置：改根目录、文件夹与图片命名、zip 层级，只在设置里，不动 types.json
	var saved_overrides:Dictionary = ui.maker.export_overrides.duplicate(true)
	ui.maker.export_overrides = {}
	ui.maker.set_export("master", "root", "reports/export_probe/my_masters")
	ui.maker.set_export("master", "folder_name", "{identity}")
	ui.maker.set_export_image("master", "header_img", "{identity}_avatar")
	ui.maker.set_export("master", "zip_layout", "flat")
	check(ui.maker.suggest_path("master", {"master_name": "probe_u"}) == "res://reports/export_probe/my_masters/probe_u/probe_u.json", "user root and folder naming " + ui.maker.suggest_path("master", {"master_name": "probe_u"}))
	var ucard := {"master_name": "probe_u", "header_img": ProjectSettings.globalize_path("res://icon.svg")}
	var ufolder := "res://reports/export_probe/my_masters/probe_u"
	ui.maker.place_images(ucard, "master", ufolder, "")
	check(ucard.header_img == "probe_u_avatar.svg", "user image naming " + str(ucard.header_img))
	check(ui.maker.zip_base("master", ufolder + "/probe_u.json") == ufolder, "flat zip layout")
	ui.maker.set_export("master", "zip_layout", "root")
	check(ui.maker.zip_base("master", ufolder + "/probe_u.json") == "res://reports/export_probe/my_masters", "root zip layout")
	check(ui.maker.item_spec("master").get("root") == "data/masters", "types.json spec untouched")
	var cfg := "res://reports/export_probe/export.cfg"
	check(ui.maker.save_export_settings(cfg), "export settings saved")
	ui.maker.export_overrides = {}
	ui.maker.load_export_settings(cfg)
	check(str(ui.maker.export_overrides.get("master", {}).get("folder_name", "")) == "{identity}", "export settings reload")
	ui.open_export_settings()
	await get_tree().process_frame
	check(ui.export_window.visible and ui.export_form.get_child_count() > 4 and ui.export_preview.text.find("my_masters") != -1, "export settings window shows form and preview: " + ui.export_preview.text)
	ui.export_window.hide()
	ui.maker.export_overrides = saved_overrides
	OS.move_to_trash(ProjectSettings.globalize_path(exp_root))
	# 新 operation 自动加入：放一个新脚本进 operations 目录，扫描后出现在积木区；删掉后消失
	var op_path := "res://assets/scripts/system/operations/JsonProbeOp.gd"
	var f := FileAccess.open(op_path, FileAccess.WRITE)
	f.store_string("extends RefCounted\n\n# 临时探针：给某人加一点东西\nfunc exec(amount:int, player_id:int = -1):\n\treturn amount\n")
	f.close()
	ui._check_catalog()
	var op:Dictionary = ui.maker.operation_of("json_probe_op")
	check(not op.is_empty() and op.params.size() == 2 and str(op.category) == "未登记", "new operation scanned without registering " + JSON.stringify(op))
	check(_palette_has(ui, "临时探针"), "new operation shows in palette")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(op_path))
	ui._check_catalog()
	check(ui.maker.operation_of("json_probe_op").is_empty(), "removed operation disappears")

	# 拖动光标：放不下的位置不显示禁止图标
	var splits_ok := true
	for sp in ui.splits:
		if not sp is SplitContainer:
			splits_ok = false
	check(ui.splits.size() >= 7 and splits_ok, "every area has a draggable splitter " + str(ui.splits.size()))
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)


func _palette_has(ui, text:String) -> bool:
	for label in ui.palette_box.find_children("*", "Label", true, false):
		if str(label.text).find(text) != -1:
			return true
	return false


func _click(at:Vector2) -> void:
	Input.warp_mouse(at)
	await get_tree().process_frame
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		get_tree().root.push_input(ev, true)
		await get_tree().process_frame


func _diff(a, b, where:String) -> void:
	if a is Dictionary and b is Dictionary:
		for k in b:
			if not a.has(k):
				print("DIFF added ", where, "/", k, " = ", JSON.stringify(b[k]).left(200))
			else:
				_diff(a[k], b[k], where + "/" + str(k))
		for k in a:
			if not b.has(k):
				print("DIFF removed ", where, "/", k)
	elif a is Array and b is Array and a.size() == b.size():
		for i in a.size():
			_diff(a[i], b[i], where + "/" + str(i))
	elif not Codec.same(a, b):
		print("DIFF changed ", where, " ", JSON.stringify(a).left(200), " -> ", JSON.stringify(b).left(200))


func _find_drop(root:Node, kind:String, last := false):
	var found = null
	for child in root.get_children():
		if child is Control and child.has_meta("drop") and str(child.get_meta("drop").kind) == kind:
			if not last:
				return child
			found = child
		var inner = _find_drop(child, kind, last)
		if inner != null:
			if not last:
				return inner
			found = inner
	return found


# 脚本区里画出来的某块积木（按 operation 名找）
func _block_panel(root:Node, func_name:String):
	for c in root.find_children("*", "Control", true, false):
		if c.has_meta("block") and str(c.get_meta("block").get("func", "")) == func_name:
			return c
	return null


func _delete_button_of(root:Node, func_name:String):
	var panel = _block_panel(root, func_name)
	if panel == null:
		return null
	return panel.find_child("DeleteBlock", true, false)
