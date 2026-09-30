extends Node

# 新手教程回归：教程文件能被找到；正式的阿尔托莉雅满足每一步的数据条件，空白从者不满足；
# 入口能打开面板、翻页、关闭；「对每一个」嘴里没填的可选填入位置保存成空。
var checks := 0
var failures:Array = []

const ARTORIA := "res://data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json"


func check(ok:bool, text:String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
	print("CHECK ", text, " ", ok)


# 把所有积木体去掉，只留效果/选项架子（时机、卡面文字、开关、选项名、前置条件的提示）。
# 效果数字也去掉：编辑器里效果数字只在往积木空位填数时才产生，没拖积木就不会有。
# 用来验证：还没拖积木时，只靠字段就能判定的那几条必须已经变绿。
func _strip_blocks(value) -> void:
	if value is Array:
		for item in value:
			_strip_blocks(item)
		return
	if not value is Dictionary:
		return
	for key in ["funcs", "power_query", "effect_numbers"]:
		value.erase(key)
	for key in value.keys():
		_strip_blocks(value[key])


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var ui = load("res://json_maker/json_maker.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame
	var list:Array = ui.maker.list_tutorials()
	check(list.size() >= 1, "tutorial folder has a tutorial")
	var wind:Dictionary = {}
	for entry in list:
		if str(entry.path).get_file() == "artoria_pendragon.json":
			wind = entry.data
	check(not wind.is_empty(), "artoria tutorial found")
	var steps:Array = wind.get("steps", [])
	check(steps.size() >= 8, "tutorial has steps " + str(steps.size()))
	# 三张技能牌都要教到：每张牌名至少出现在一条完成条件里
	var taught := JSON.stringify(steps)
	for skill_name in ["风王结界", "对魔力", "誓约胜利之剑"]:
		check(taught.contains("\"shown_skill_name\":\"" + skill_name + "\""), "tutorial teaches " + skill_name)

	# 正式数据满足每一条数据条件；空白从者一条都不满足
	var artoria = ui.maker.read_json(ARTORIA)
	var blank = ui.maker.blank("servant")
	var data_checks := 0
	for step in steps:
		check(str(step.get("title", "")) != "" and str(step.get("body", "")) != "", "step has title and body")
		for c in step.get("checks", []):
			if str(c.get("from", "data")) == "state":
				continue
			data_checks += 1
			check(ui.maker.tutorial_check(c, artoria, {}), "artoria passes: " + str(c.text))
			check(not ui.maker.tutorial_check(c, blank, {}), "blank servant fails: " + str(c.text))
		var image := str(step.get("image", ""))
		if image != "":
			check(LoadHelper.texture_exists(image), "step image exists " + image)
	check(data_checks >= 20, "data checks counted " + str(data_checks))

	# 标签类型检查只看类型，不依赖标签名；名字列表仍独立检查。
	var tag_progress:Dictionary = ui.maker.blank("servant")
	tag_progress["tags"] = [{"tag": "", "type": "servant_tag", "name_list": []}]
	check(ui.maker.tutorial_check(steps[4].checks[0], tag_progress, {}), "tag type ticks before tag name is filled")
	check(not ui.maker.tutorial_check(steps[4].checks[1], tag_progress, {}), "empty tag name list stays unfinished")
	ui.data = tag_progress
	ui.card_kind = "servant"
	ui._load_effects()
	ui._refresh_all()
	ui.tutorial = wind
	ui.tutorial_panel.visible = true
	ui._go_tutorial_step(4)
	check(ui.tutorial_results() == [true, false], "tag step UI ticks only type when name fields are empty")
	check(ui.tutorial_checks.get_child(0).get_theme_color("font_color") == Color("#2E9E4F"), "tag type task is rendered green")
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("tutorial-tag-fixed.png"))
	ui.close_tutorial()
	tag_progress.tags[0].type = ""
	tag_progress.tags[0].tag = "servant_tag"
	check(not ui.maker.tutorial_check(steps[4].checks[0], tag_progress, {}), "tag name cannot substitute for tag type")

	# 没有 has 的判定默认只要求「取到值」，空字符串也能过：这类「填好/照抄」必须显式写 not_empty
	for step in steps:
		for c in step.get("checks", []):
			if c.has("has") or str(c.get("from", "data")) == "state":
				continue
			check(bool(c.get("not_empty", false)), "空白判定写了 not_empty: " + str(c.text))
	# 行为验证：内部名清空后，「填好内部名」不再算过
	var hollow = artoria.duplicate(true)
	for skill in hollow.specials.SKILLS:
		if str(skill.get("shown_skill_name", "")) == "誓约胜利之剑":
			skill["skill_name"] = ""
			check(not ui.maker.tutorial_check(steps[17].checks[1], hollow, {}), "内部名清空后不算填好")

	# 「取最大」保持默认不写出 true：学员不动它时「取魔力消耗最大的」也要能过
	var default_max = artoria.duplicate(true)
	for skill in default_max.specials.SKILLS:
		if str(skill.get("shown_skill_name", "")) == "对魔力":
			for effect in skill.effects:
				for option in effect.get("options", []):
					for req in option.get("activation_requirements", []):
						for f in req.funcs:
							if str(f.func_name) == "get_extreme_by_property":
								f.parameters.resize(2)
	var max_check:Dictionary = {}
	for c in steps[15].checks:
		if str(c.text) == "取魔力消耗最大的":
			max_check = c
	check(not max_check.is_empty() and ui.maker.tutorial_check(max_check, default_max, {}), "取最大保持默认时判定仍能过")
	var fresh_extreme:Dictionary = ui._new_op("get_extreme_by_property")
	check(ui.codec.encode_effect_list([fresh_extreme])[0].parameters.size() == 2, "新拖的「……最大的」保持默认时不写出取最大")
	# 第 17 步让学员复制战果积木：副本必须与原块共用同一个效果数字，才能得到正式卡的 [1, 4]
	var score_nodes:Array = ui.codec.decode_list([{"func_name": "edit_score", "parameters": [null, {"number_index": 0}, -1], "var_index": -1}])
	var pasted:Array = ui.codec.encode_effect_list([score_nodes[0], ui._fresh_copy(score_nodes[0])])
	check(pasted.size() == 2 and pasted[1].parameters[1] == {"number_index": 0}, "复制的战果积木共用原来的效果数字 " + JSON.stringify(pasted))

	# 入口、翻页、状态条件
	ui.open_tutorial_menu()
	if ui.tutorials.size() > 1:
		ui._on_tutorial_menu_pressed(0)
	await get_tree().process_frame
	check(ui.tutorial_panel.visible, "tutorial panel opens")
	check(ui.tutorial_step_label.text.begins_with("第 1 /"), "starts at step 1")
	check(ui.tutorial_prev_button.disabled, "prev disabled on first step")
	check(ui.tutorial_practice and ui.data == null, "tutorial opens practice without building the card for the learner")
	check(ui.tutorial_results() == [false], "first step waits for the learner")
	check(ui.tutorial_checks.get_child_count() == 1 and ui.tutorial_checks.get_child(0).text.begins_with("○"), "unfinished check line is shown")
	var servant_index := -1
	for k in ui.kind_button.item_count:
		if str(ui.kind_button.get_item_metadata(k)) == "servant":
			servant_index = k
	check(servant_index >= 0, "servant kind in kind menu")
	ui._select_kind(servant_index)
	check(ui.kind_id == "servant", "learner picks the servant kind first")
	await get_tree().process_frame
	check(ui.tutorial_results() == [false], "picking the kind alone does not finish the step")
	ui._new_card()
	check(ui.tutorial_practice and ui.path == "" and ui.data is Dictionary, "learner builds it inside the practice copy")
	await get_tree().process_frame
	check(ui.tutorial_results() == [true], "first step done after the learner adds the servant")
	check(ui.tutorial_checks.get_child_count() == 1 and ui.tutorial_checks.get_child(0).text.begins_with("✔"), "check line shows done")
	ui.tutorial_next()
	check(ui.tutorial_index == 1 and not ui.tutorial_prev_button.disabled, "next moves to step 2")
	check(ui.tutorial_results() == [false, false], "step 2 unfinished on blank servant")
	ui.data["shown_servant_name"] = "练习"
	ui.data["servant_class"] = "saber"
	ui._changed()
	check(ui.tutorial_results() == [true, true], "step 2 ticks after filling fields")
	ui.tutorial_prev()
	check(ui.tutorial_index == 0, "prev moves back")
	ui._go_tutorial_step(steps.size() - 1)
	check(ui.tutorial_next_button.text == "完成", "last step shows finish")
	check(ui.tutorial_results() == [false] and not ui.tutorial_state().saved, "unfinished practice does not count as ready or saved")
	ui.tutorial_next()
	check(not ui.tutorial_panel.visible and ui.tutorial.is_empty(), "finish closes tutorial")
	check(ui.tutorial_practice, "closing tutorial keeps practice unsavable")

	# 循环填入位置：嘴里的积木「玩家」一格没填（可选空位），保存必须是 null 而不是默认值
	var codec = ui.codec
	var nodes:Array = codec.decode_list([
		{"func_name": "get_players_in_same_area", "parameters": [], "var_index": 0},
		{"func_name": "foreach_func", "parameters": [[
			{"func_name": "zero_attribute_power", "parameters": [null, ["strength"]], "var_index": -1}
		], {"self_var": 0}], "var_index": -1},
	])
	var loop_node:Dictionary = {}
	for n in nodes:
		if n is Dictionary and str(n.get("func", "")) == "foreach_func":
			loop_node = n
	check(not loop_node.is_empty(), "loop block decoded")
	var body:Array = []
	for p in loop_node.params:
		if p is Dictionary and str(p.get("s", "")) == "script":
			body = p.body
	check(body.size() == 1, "loop body decoded")
	var inner:Dictionary = body[0]
	var zero_op:Dictionary = ui.maker.operation_of("zero_attribute_power")
	inner.params[0] = ui._omit_for(zero_op, 0)
	ui._mark_loop_items(loop_node, ui.maker.operation_of("foreach_func"), body)
	check(inner.params[0].get("loop", false), "omitted fill slot is marked as loop item")
	var encoded:Array = codec.encode_effect_list(nodes)
	var inner_json = {}
	for f in encoded:
		if str(f.get("func_name", "")) == "foreach_func":
			inner_json = f.parameters[0][0]
	check(inner_json.get("parameters", []).size() == 2 and inner_json.parameters[0] == null, "omitted fill slot saves as null " + JSON.stringify(inner_json))

	# 选项的「发动前必须满足」能在编辑器里看到、加一条、写回 JSON
	ui.close_tutorial()
	ui.data = ui.maker.read_json(ARTORIA)
	ui.card_kind = "servant"
	ui.focus_to(["specials", "SKILLS", 0], "skill")
	await get_tree().process_frame
	await get_tree().process_frame
	var bloom_view:Dictionary = {}
	for view in ui.effects_view:
		if str(view.effect.get("effect_name", "")) == "np_bloom_score":
			bloom_view = view
	check(not bloom_view.is_empty() and bloom_view.options[0].reqs.size() == 1, "existing requirement decoded into the view")
	var req_boxes:Array = ui.script_box.find_children("Requirements", "", true, false)
	check(not req_boxes.is_empty(), "requirement editor is drawn under options")
	var option_layout = ui._options_view(bloom_view)
	ui.add_child(option_layout)
	await get_tree().process_frame
	await get_tree().process_frame
	var connection = option_layout.get_child(0)
	check(connection is VBoxContainer, "option header and blocks share a connected stack")
	if connection is VBoxContainer:
		var header = connection.get_child(0)
		var stack = connection.get_child(1)
		var first_block = stack.get_child(1)
		check(is_equal_approx(header.global_position.x, first_block.global_position.x), "option notch aligns horizontally")
		check(is_equal_approx(first_block.global_position.y, header.get_global_rect().end.y - ui.Shape.NOTCH_D), "option notch joins header without gap")
		check(option_layout.get_child(1) is Button and option_layout.get_child(1).text.contains("选项的限制"), "option settings follow the whole stack")
	option_layout.queue_free()
	var shows_message := false
	for box in req_boxes:
		for edit in box.find_children("", "LineEdit", true, false):
			if (edit as LineEdit).text == "本回合未打出魔力消耗最高的宝具攻击":
				shows_message = true
	check(shows_message, "requirement message is editable")
	var adds:Array = ui.script_box.find_children("AddRequirement", "Button", true, false)
	check(not adds.is_empty(), "add requirement button exists")
	if not bloom_view.is_empty() and not adds.is_empty():
		var before:int = bloom_view.options[0].option.activation_requirements.size()
		# 找属于宝具绽放那一项的按钮：它所在折叠框里有那句提示
		for box in req_boxes:
			var mine := false
			for edit in box.find_children("", "LineEdit", true, false):
				if (edit as LineEdit).text == "本回合未打出魔力消耗最高的宝具攻击":
					mine = true
			if mine:
				(box.find_child("AddRequirement", true, false) as Button).pressed.emit()
		await get_tree().process_frame
		ui._commit()
		var reqs:Array = bloom_view.options[0].option.activation_requirements
		check(reqs.size() == before + 1 and reqs.back().has("funcs") and bloom_view.options[0].reqs.size() == before + 1, "adding a requirement writes it back")
		check(reqs[0].funcs.size() == 11, "existing requirement blocks survive the round trip " + str(reqs[0].funcs.size()))

	# 逐步变绿：效果架子（时机、卡面文字、开关、效果数字）搭好、积木还没拖时，
	# 只靠字段就能判定完成的判定必须已经变绿——判定不能要求同一大步里最后才拖的那块积木，
	# 否则学员做完整段架子却看到满屏红勾，会以为教程坏了。
	var skeleton = artoria.duplicate(true)
	_strip_blocks(skeleton)
	ui.open_tutorial_menu()
	await get_tree().process_frame
	ui.data = skeleton
	var progressive := [
		[12, [true, true, true, true, true, true], "对魔力卡面全靠字段"],
		[13, [true, true, true, true, true, true, false, false], "魔术抗性：架子逐项先绿，积木最后"],
		[14, [true, true, true, true, true, true], "宝具绽放：架子与前置条件提示全靠字段"],
		[15, [false, false, false, false, false], "找出最贵的宝具：整步都在拖积木"],
		[16, [false, false, false, false, false, false], "获得战果：整步都在拖积木，效果数字随积木产生"],
		[17, [true, true, true, true, true, true, true], "誓约胜利之剑卡面全靠字段"],
		[18, [true, true, true, true, true, true, false, false], "高潮+4：架子逐项先绿，数字随合计威力那块出现"],
		[19, [true, true, true, false, false, false], "第 11 回合：开关先绿，数字随积木出现"],
	]
	for row in progressive:
		var index:int = int(row[0])
		ui._go_tutorial_step(index)
		await get_tree().process_frame
		var got:Array = ui.tutorial_results()
		check(got == row[1], "step " + str(index + 1) + " 逐步变绿 " + str(row[2]) + " got " + str(got))
	ui.close_tutorial()
	ui.data = null

	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
