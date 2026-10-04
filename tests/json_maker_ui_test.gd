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
	var sections:Array = ui._palette_sections("")
	check(sections.size() == 2 and sections[0].shown == "取值积木" and sections[1].shown == "执行积木", "palette separates value and action blocks")
	check(_section_has_operation(sections[0], "get_current_round") and _section_has_operation(sections[0], "store_value"), "reporters include query and control reporter")
	check(_section_has_operation(sections[1], "edit_magic") and not _section_has_operation(sections[1], "store_value"), "actions exclude control reporter")
	check(ui.palette_section == "action" and ui.palette_box.get_node_or_null(ui._category_anchor("action", "控制流")) != null and ui.palette_box.get_node_or_null(ui._category_anchor("value", "控制流")) == null, "action tab shows only action categories")
	ui.value_tab.pressed.emit()
	check(ui.palette_section == "value" and ui.palette_box.get_node_or_null(ui._category_anchor("value", "控制流")) != null and ui.palette_box.get_node_or_null(ui._category_anchor("action", "控制流")) == null, "value tab shows only value categories")
	ui.action_tab.pressed.emit()
	check(ui.palette_section == "action" and ui.palette_hint.text.find("执行") != -1, "action tab restores action list and explanation")
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
	check(not ui.data.effects[0].is_pure_passive and ui.data.effects[0].need_activate, "新效果默认需要激活，不是自动被动")
	check(ui.data.effects[0].is_manual, "新效果默认由玩家点击发动")
	check(ui.data.effects[0].once_per_game and ui.data.effects[0].source_bound, "新效果默认每局一次且只受自身牌影响")
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

	# 变量小标签：有结果的积木末尾有「变量 n」，没人读时 JSON 不写 var_index；拖进空位后才写
	ui.effects_view[0].lists.funcs.clear()
	ui.effects_view[0].lists.funcs.append(ui._new_op("get_current_round"))
	ui.effects_view[0].lists.funcs.append(ui._new_op("edit_score"))
	ui._paint_scripts()
	await get_tree().process_frame
	var tag = ui.script_box.find_child("ResultTag", true, false)
	check(tag != null, "reporter block shows a result tag")
	check(_block_panel(ui.script_box, "edit_score").find_child("ResultTag", true, false) == null, "declared no-result op has no tag")
	ui._commit()
	check(int(ui.data.effects[0].funcs[0].get("var_index", -1)) == -1, "unused result tag writes no var_index " + JSON.stringify(ui.data.effects[0].funcs))
	var tag_n := int(ui.effects_view[0].lists.funcs[0].tag_var)
	var var_payload := {"new": {"kind": "var_ref", "slot": {"s": "var", "n": tag_n}}}
	var score_node:Dictionary = ui.effects_view[0].lists.funcs[1]
	var score_slot = null
	for c in _block_panel(ui.script_box, "edit_score").get_parent().find_children("*", "Control", true, false):
		if c.has_meta("drop") and str(c.get_meta("drop").kind) == "slot" and is_same(c.get_meta("drop").holder, score_node.params) and int(c.get_meta("drop").key) == 1:
			score_slot = c
	check(score_slot != null and ui._can_drop_on(Vector2.ZERO, var_payload, score_slot), "result tag can be dropped into a slot")
	ui._drop_on(Vector2.ZERO, var_payload, score_slot)
	await get_tree().process_frame
	ui._commit()
	var tagged:Array = ui.data.effects[0].funcs
	check(int(tagged[0].get("var_index", -1)) == tag_n and tagged[1].parameters[1] is Dictionary and int(tagged[1].parameters[1].get("self_var", -2)) == tag_n, "read tag var is written " + JSON.stringify(tagged))

	# 数字：数字空位直接是输入框，填了就是可更改的效果数字；▾ 里可改成固定数字（先弹警告）
	ui.effects_view[0].lists.funcs.clear()
	var magic_op:Dictionary = ui._new_op("edit_magic")
	magic_op.params[1] = {"s": "lit", "v": null}
	ui.effects_view[0].lists.funcs.append(magic_op)
	ui._paint_scripts()
	await get_tree().process_frame
	var new_num = ui.script_box.find_child("NewNumber", true, false)
	check(new_num != null, "empty number slot shows a number box")
	new_num.value = 3
	await get_tree().process_frame
	await get_tree().process_frame
	check(str(magic_op.params[1].get("s", "")) == "num", "typed number becomes an effect number")
	var nums:Array = ui.effects_view[0].effect.effect_numbers
	var num_rec:Dictionary = nums[int(magic_op.params[1].i)]
	check(int(num_rec.number) == 3 and bool(num_rec.can_change), "effect number defaults to changeable")
	var mode = ui.script_box.find_child("NumberMode", true, false)
	check(mode != null, "number shows its mode menu")
	mode.get_popup().id_pressed.emit(0)
	await get_tree().process_frame
	var confirm = ui.find_child("FixNumberConfirm", true, false)
	check(confirm != null and bool(num_rec.can_change), "fixing a number asks first")
	confirm.confirmed.emit()
	await get_tree().process_frame
	check(not bool(num_rec.can_change) and str(magic_op.params[1].get("s", "")) == "num", "BaseNumber slot stays an effect number, just fixed")

	# 加选项按钮必须追加选择，不能把已有步骤包进选项。
	var before_choice:Array = ui.effects_view[0].lists.funcs.duplicate()
	var add_choice:Button = null
	for button in ui.script_box.find_children("*", "Button", true, false):
		if button.text in ["改成让玩家选一项", "在下面加选项"]:
			add_choice = button
	check(add_choice != null, "add choice button exists")
	if add_choice != null:
		add_choice.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		ui._commit()
		var appended:Array = ui.effects_view[0].lists.funcs
		check(appended.size() == before_choice.size() + 1, "button appends choice after existing blocks")
		check(not ui.data.effects[0].has("options"), "button does not wrap existing blocks into effect options")
		if appended.size() == before_choice.size() + 1:
			check(is_same(appended[0], before_choice[0]), "existing block identity is preserved")
			check(appended.back().func == "ask_player_option" and appended.back().params[0].items[0].body.is_empty(), "new choice starts empty at the end")
			check(ui.data.effects[0].funcs.back().func_name == "ask_player_option", "export keeps choice last")
			if OS.get_cmdline_user_args().has("--capture-option-append"):
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("add-option-append.png"))
	# 恢复本段测试前的结构，后面的拖放测试独立运行。
	ui.effects_view[0].effect.erase("options")
	ui.effects_view[0].options.clear()
	ui.effects_view[0].lists.funcs = before_choice

	# 让玩家选：不必接在「当……时」后面，接在任何积木后面都行；选项里是一串积木
	ui.effects_view[0].lists.funcs.clear()
	ui.effects_view[0].lists.funcs.append(ui._new_op("get_current_round"))
	ui._paint_scripts()
	var ask_zone = _find_drop(ui.script_box, "stack", true)
	ui._drop_on(Vector2.ZERO, {"new": {"kind": "op", "func": "ask_player_option"}}, ask_zone)
	await get_tree().process_frame
	await get_tree().process_frame
	var ask_list:Array = ui.effects_view[0].lists.funcs
	check(ask_list.size() == 2 and ask_list[1].func == "ask_player_option", "ask block placed after another block")
	check(ui.script_box.find_child("AddOption", true, false) != null, "ask block shows its options")
	var add_requirement = ui.script_box.find_child("AddRequirement", true, false)
	check(add_requirement != null, "inline choice shows prerequisite editor")
	if add_requirement != null:
		add_requirement.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		var choice_item:Dictionary = ask_list[1].params[0].items[0]
		choice_item.opt.activation_requirements[0]["message"] = "需要满足条件"
		choice_item.reqs[0].append(ui._new_op("get_current_round"))
		ui._commit()
		var requirement_json:Dictionary = ui.data.effects[0].funcs[1].parameters[0][0].activation_requirements[0]
		check(requirement_json.message == "需要满足条件" and requirement_json.funcs[0].func_name == "get_current_round", "inline prerequisite blocks export")
		var restored:Array = ui.codec.decode_list(ui.data.effects[0].funcs)
		check(restored[1].params[0].items[0].reqs[0][0].func == "get_current_round", "inline prerequisite blocks reload")
	var opt_zone = null
	for c in ui.script_box.find_children("*", "Control", true, false):
		if c.has_meta("drop") and str(c.get_meta("drop").kind) == "stack" and str(c.get_meta("drop").get("context", "")) == "option":
			opt_zone = c
	check(opt_zone != null, "each option has a block stack")
	ui._drop_on(Vector2.ZERO, {"new": {"kind": "op", "func": "edit_score"}}, opt_zone)
	await get_tree().process_frame
	ui._commit()
	var ask_json:Dictionary = ui.data.effects[0].funcs[1]
	check(ask_json.func_name == "ask_player_option" and ask_json.parameters[0] is Array and ask_json.parameters[0][0].funcs[0].func_name == "edit_score", "ask block encodes options with their funcs " + JSON.stringify(ask_json))

	# 搜索下拉：属性名、内部名、玩家数据键都能搜，找不到可以直接打字
	var props:Array = ui.maker.object_property_groups()
	var prop_ids := []
	for g in props:
		for it in g.items:
			prop_ids.append(it.id)
	check(prop_ids.has("_other_things") and prop_ids.has("_cost") and prop_ids.has("from"), "property dropdown lists real object fields")
	ui._open_search_popup(ui, props, func(_v): pass, true)
	ui.tp_search.text = "附带"
	ui._fill_time_point_tree()
	var typed_first = ui.tp_tree.get_root().get_first_child()
	check(typed_first != null and str(typed_first.get_metadata(0)) == "附带", "typed text offered as fallback first")
	var found_other := false
	var grp = typed_first.get_next()
	while grp != null:
		var it = grp.get_first_child()
		while it != null:
			if str(it.get_metadata(0)) == "_other_things":
				found_other = true
			it = it.get_next()
		grp = grp.get_next()
	check(found_other, "search by chinese name finds _other_things")
	var picked_v := []
	ui.tp_pick = func(v): picked_v.append(v)
	ui.tp_search.text = "no_such_field_xyz"
	ui._fill_time_point_tree()
	ui._pick_first_time_point()
	check(picked_v == ["no_such_field_xyz"], "enter with no match uses typed text " + str(picked_v))
	ui.tp_popup.hide()

	# 所有空位都是「分类 + 搜索」下拉，打字兜底
	ui.effects_view[0].lists.funcs.clear()
	var cr_op:Dictionary = ui._new_op("can_gain_magic")
	var bm_op:Dictionary = ui._new_op("set_battle_result")
	ui.effects_view[0].lists.funcs.append(ui._new_op("get_current_round"))
	ui.effects_view[0].lists.funcs.append(cr_op)
	ui.effects_view[0].lists.funcs.append(bm_op)
	ui._paint_scripts()
	await get_tree().process_frame
	var pickers:Array = ui.script_box.find_children("SlotPicker", "Button", true, false)
	check(pickers.size() >= 5, "every literal slot has a dropdown " + str(pickers.size()))
	var plain:Array = []
	for c in ui.script_box.find_children("*", "LineEdit", true, false) + ui.script_box.find_children("*", "OptionButton", true, false):
		if c.get_parent() is SpinBox or not _in_block(c):
			continue
		plain.append(c.get_class() + " " + str(c.get("placeholder_text")))
	check(plain.is_empty(), "no bare text box or option menu left in blocks " + str(plain))
	var mode_groups:Array = ui._slot_groups("String", "battle_mode", "set_battle_result:mode", ui.effects_view[0].effect)
	var group_names := []
	for g in mode_groups:
		group_names.append(str(g.shown))
	check(str(mode_groups[0].shown) == "可选值" and mode_groups[0].items.size() == 3 and mode_groups[0].get("open", false), "declared choices listed first and opened " + str(group_names))
	check(group_names.has("特殊") and group_names.any(func(n): return str(n).begins_with("积木 · ")), "other relevant groups kept after declared choices " + str(group_names))
	var special_items:Array = mode_groups[group_names.find("特殊")].items
	check(special_items.any(func(it): return it.value is Dictionary and str(it.value.get("_pick", "")) == "loop"), "loop item offered for text slot")
	var bool_groups:Array = ui._slot_groups("bool", "", "unknown:flag", ui.effects_view[0].effect)
	check(bool_groups[0].items.size() == 2 and bool_groups[0].items[0].value is bool, "boolean slot offers boolean values first")
	var bool_blocks:Array = []
	for g in bool_groups:
		if str(g.shown).begins_with("积木 · "):
			for it in g.items:
				bool_blocks.append(str(it.id))
	check(not bool_blocks.is_empty() and bool_blocks.all(func(f): return str(ui.maker.operation_of(f).get("returns", "")) != "Array"), "boolean slot keeps blocks but drops declared array results")
	var buff_groups:Array = ui._slot_groups("String", "internal_name", "get_buff_by_name_fr_arr:buff_name", ui.effects_view[0].effect)
	var first_card_group := -1
	for i in buff_groups.size():
		if str(buff_groups[i].shown).find("攻击牌") != -1:
			first_card_group = i
			break
	check(first_card_group == -1 or str(buff_groups[first_card_group].shown).begins_with("其他 · "), "buff name puts unrelated card names under 其他")
	var card_groups:Array = ui._slot_groups("String", "internal_name", "get_cards_by_name_fr_arr:card_name", ui.effects_view[0].effect)
	check(str(card_groups[0].shown).find("攻击牌") != -1 or str(card_groups[0].shown).find("卡库里的") != -1, "card name lists cards first " + str(card_groups[0].shown))
	# 兜底：面板最后一项是「显示其他所有字段」，点它在原地展开其余来源，再点收起
	ui._open_search_popup(ui.script_box, mode_groups, func(_v): pass, true, Callable(), ui._all_field_groups)
	var more_row:TreeItem = null
	var row:TreeItem = ui.tp_tree.get_root().get_first_child()
	while row != null:
		if row.has_meta("more"):
			more_row = row
		row = row.get_next()
	check(more_row != null and more_row.get_next() == null, "fallback row is the last item in the dropdown")
	var groups_before:int = ui.tp_groups.size()
	ui._toggle_more_groups()
	check(ui.tp_extra.size() > 0 and ui.tp_extra.all(func(g): return str(g.shown).begins_with("其他 · ")), "fallback expands all other fields " + str(ui.tp_extra.size()))
	check(ui.tp_groups.size() == groups_before, "expanding the fallback leaves the main list alone")
	check(ui.tp_more.is_valid() and ui.tp_more_open, "fallback row stays expanded in dropdown")
	var fb_expanded_children:int = -1
	var fb_scan:TreeItem = ui.tp_tree.get_root().get_first_child()
	while fb_scan != null:
		if fb_scan.has_meta("more"):
			fb_expanded_children = fb_scan.get_child_count()
		fb_scan = fb_scan.get_next()
	check(fb_expanded_children > 0, "expanded fallback lists other fields")
	ui._toggle_more_groups()
	var fb_collapsed_children:int = -1
	var fb_still_last:bool = false
	var fb_scan2:TreeItem = ui.tp_tree.get_root().get_first_child()
	while fb_scan2 != null:
		if fb_scan2.has_meta("more"):
			fb_collapsed_children = fb_scan2.get_child_count()
			fb_still_last = fb_scan2.get_next() == null
		fb_scan2 = fb_scan2.get_next()
	check(not ui.tp_more_open and fb_collapsed_children == 0 and fb_still_last, "fallback collapses again and stays last")
	ui.tp_popup.hide()
	# 按结果类型筛：战区格只列给出战区的积木，玩家格不列给出牌的积木；被筛掉的在兜底里
	var area_groups:Array = ui._slot_groups("BaseMapArea", "", "get_map_area_score:map_area", ui.effects_view[0].effect)
	var area_blocks:Array = []
	for g in area_groups:
		if str(g.shown).begins_with("积木 · "):
			for it in g.items:
				area_blocks.append(str(it.id))
	check(area_blocks.has("get_location_map_area") and not area_blocks.has("get_player_name") and not area_blocks.has("get_player_deck"), "area slot lists only area results " + str(area_blocks))
	var area_more:Array = ui._slot_more_groups("BaseMapArea", "get_map_area_score:map_area", ui.effects_view[0].effect)
	check(area_more.any(func(g): return str(g.shown).begins_with("类型不符的积木 · ") and g.items.any(func(it): return str(it.id) == "get_player_name")), "filtered blocks kept in fallback")
	var num_blocks:Array = []
	for g in ui._slot_groups("BaseNumber", "", "edit_magic:vary_num", ui.effects_view[0].effect):
		if str(g.shown).begins_with("积木 · "):
			for it in g.items:
				num_blocks.append(str(it.id))
	check(num_blocks.has("get_current_round") and num_blocks.has("calculate_number") and not num_blocks.has("get_player_hand_cards"), "number slot lists number results " + str(num_blocks.size()))
	check(ui.maker.type_fits("Array[BaseCard]", "Array[BaseAttack]") and not ui.maker.type_fits("Array[player]", "Array[BaseCard]") and ui.maker.type_fits("int", "player"), "type fit follows class inheritance and arrays")
	# 每个空位都有兜底：数字格也不例外
	var num_pickers:Array = []
	ui.effects_view[0].lists.funcs.clear()
	ui.effects_view[0].lists.funcs.append(ui._new_op("edit_magic"))
	ui._paint_scripts()
	await get_tree().process_frame
	num_pickers = ui.script_box.find_children("SlotPicker", "Button", true, false)
	check(not num_pickers.is_empty(), "number slot has a dropdown")
	(num_pickers[0] as Button).pressed.emit()
	check(ui.tp_more.is_valid(), "number slot dropdown offers the show-all fallback")
	ui.tp_popup.hide()
	# 玩家数据键按用途筛：改数字项只列数字，不列带点路径
	var number_keys:Array = ui._kind_groups("player_number_key", "edit_data_number:key")[0].items.map(func(it): return str(it.id))
	check(number_keys.has("play_limit") and not number_keys.has("deck") and not number_keys.any(func(k): return k.find(".") != -1), "number key slot lists numeric keys only " + str(number_keys.size()))
	var zone_paths:Array = ui._kind_groups("player_zone_path", "hide_true_name:hidden_areas")[0].items.map(func(it): return str(it.id))
	check(zone_paths.has("side.skills") and zone_paths.has("master._specials.SKILLS") and not zone_paths.has("magic"), "zone path slot lists array paths " + str(zone_paths.size()))
	check(not ui._kind_groups("card_tag", "tag:tag_name").is_empty(), "tag names collected from card library")
	var used:Array = ui.maker.used_value_groups("log_field_values", "field")
	check(not used.is_empty() and used[0].items.size() >= 2, "values used in the card library offered " + str(used))
	var scoped:Array = ui._slot_groups("String", ui._slot_kind("log_field_values:field"), "log_field_values:field", ui.effects_view[0].effect)
	check(str(scoped[0].shown) == "可选值" and scoped[0].items.any(func(it): return str(it.id) == "winners"), "declared log fields listed first and cover used values")
	var unlisted:Array = ui._slot_groups("String", "", "show_message:message", ui.effects_view[0].effect)
	check(str(unlisted[0].shown) == "卡库里用过的", "unlisted field offers real used values first " + str(unlisted[0].shown))
	var bm_mode:int = ui._param_index(ui.maker.operation_of("set_battle_result"), "mode")
	ui._apply_pick(bm_op.params, bm_mode, "add", "String", ui.effects_view[0].effect)
	check(bm_op.params[bm_mode].v == "add", "picking a choice writes the value")
	ui._apply_typed(bm_op.params, bm_mode, "my_mode", "String", ui.effects_view[0].effect)
	check(bm_op.params[bm_mode].v == "my_mode", "typed text used as-is for text slots")
	var cr_player:int = ui._param_index(ui.maker.operation_of("can_gain_magic"), "player_id")
	ui._apply_pick(cr_op.params, cr_player, {"_pick": "var", "n": 4}, "int", ui.effects_view[0].effect)
	check(cr_op.params[cr_player].get("s") == "var" and int(cr_op.params[cr_player].n) == 4, "picking a result reads that variable")
	ui._apply_pick(cr_op.params, cr_player, {"_pick": "op", "func": "get_pl_id_using_eff"}, "int", ui.effects_view[0].effect)
	check(cr_op.params[cr_player].get("s") == "block" and cr_op.params[cr_player].b.func == "get_pl_id_using_eff", "picking a block nests it")
	ui._apply_typed(cr_op.params, cr_player, "abc", "int", ui.effects_view[0].effect)
	check(cr_op.params[cr_player].get("s") == "block", "invalid typed number is refused")
	ui._apply_typed(cr_op.params, cr_player, "2", "int", ui.effects_view[0].effect)
	check(cr_op.params[cr_player].get("v") is int and cr_op.params[cr_player].v == 2, "typed number converted " + str(cr_op.params[cr_player]))
	await get_tree().process_frame
	ui._commit()
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

	# 导出：命名规则按 data 现有结构；新选的图复制进 json 所在文件夹并按规则改名；打包 zip
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
	var op_path := "res://scripts/system/operations/JsonProbeOp.gd"
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


func _section_has_operation(section:Dictionary, func_name:String) -> bool:
	for entry in section.categories:
		for item in entry.items:
			if str(item.get("func", "")) == func_name:
				return true
	return false


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


# 是否画在某块积木里面（效果头部的原文、设置表单不算）
func _in_block(c:Node) -> bool:
	var p := c.get_parent()
	while p != null:
		if p.has_meta("block"):
			return true
		p = p.get_parent()
	return false


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
