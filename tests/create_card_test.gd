extends Node
# 生成牌：编辑器「生成牌」搭出的 JSON，经真实加载器与效果结算，能按内部名新建牌并放进指定区，
# 归属默认是发动效果的那张牌，也可以另行指定；create_card 自己不放进任何区。
const Codec = preload("res://json_maker/json_codec.gd")

var failures:Array[String] = []
var checks:int = 0


func check(ok:bool, label:String) -> void:
	checks += 1
	if !ok: failures.append(label)
	print("CHECK ", label, " ", ok)


func _ready() -> void:
	call_deferred("run")


func setup() -> void:
	EffectManager.reset_runtime()
	GameData.player_data_library.clear()
	var d:Dictionary = GameData.new_player_data()
	d.is_out = false
	GameData.player_data_library[0] = d


# 用编辑器同一套积木生成效果 JSON，挂到一张临时攻击牌上结算
func run_generated(ui, card_name:String, card_type:String, zone:String, count:int) -> BaseAttack:
	var effect := {"effect_name": "probe_generate", "time_points": ["game_start"], "priority": 0,
		"is_pure_passive": true, "is_residue": false, "effect_numbers": []}
	var nodes:Array = ui.generate_blocks(card_name, card_type, zone, count, effect)
	effect["funcs"] = ui.codec.encode_effect_list(nodes)
	var host := BaseAttack.new("probe_host", "", [])
	host._effects = LoadHelper.load_effects([effect], host)
	EffectManager.register_effects(host._effects, 0)
	# 与正式结算入口一致：结算期间 activating_eff 指向这条效果，「发动效果的玩家」才能解析
	EffectManager.activating_eff = host._effects[0]
	EffectManager.activate_effect(host._effects[0])
	EffectManager.activating_eff = null
	return host


func run() -> void:
	var ui = load("res://json_maker/json_maker.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame
	check(not ui.maker.operation_of("create_card").is_empty(), "create_card scanned into palette")

	setup()
	var host := run_generated(ui, "surveil", "attack", "hand_cards", 1)
	var hand:Array = GameDataManager.get_player_data(0).hand_cards
	check(hand.size() == 1 and hand[0] is BaseAttack and hand[0]._name == "surveil", "special attack generated into hand " + str(hand.map(func(c): return c._name)))
	check(hand.size() == 1 and hand[0].from == host, "owner defaults to the activating card")

	setup()
	run_generated(ui, "strength:2", "attack", "deck", 3)
	var deck:Array = GameDataManager.get_player_data(0).deck
	check(deck.size() == 3 and deck.all(func(c): return c is BaseAttack and "strength" in c._attributes), "deck ref x3 generated into deck")
	check(deck.size() == 3 and deck[0] != deck[1], "each generated card is its own instance")

	setup()
	var event_name := str((LoadEvent.events[0] as BaseEvent)._name) if not LoadEvent.events.is_empty() else ""
	run_generated(ui, event_name, "", "discard", 1)
	var discard:Array = GameDataManager.get_player_data(0).discard
	check(discard.size() == 1 and discard[0] is BaseEvent and discard[0] != LoadEvent.events[0], "empty type searches libraries, event cloned not template")

	# 自定义新牌：整张牌写在积木里，走真实加载函数建牌，放进手牌并让它自己的效果生效
	setup()
	var custom:Dictionary = ui.blank_custom_card("attack")
	custom["attack_name"] = "probe_custom_attack"
	custom["shown_attack_name"] = "自定义攻击"
	custom["attributes"] = ["magic"]
	custom["power"] = {"number": 7, "can_change": true, "is_pure_number": true}
	custom["attack_card_img"] = "probe.png"
	custom["effects"] = [{"effect_name": "probe_custom_gain", "time_points": ["played_card"], "priority": 0,
		"is_pure_passive": true, "is_residue": false, "effect_numbers": [{"number": 2, "can_change": true, "is_pure_number": true}],
		"funcs": [{"func_name": "edit_magic", "parameters": [null, {"number_index": 0}], "var_index": -1}]}]
	var item := {"type": "attack", "kind": "attack", "back_type": "attack"}
	var ceffect := {"effect_name": "probe_build", "time_points": ["game_start"], "priority": 0, "is_pure_passive": true, "is_residue": false, "effect_numbers": []}
	ui.effects_view.clear()
	var cnodes:Array = ui.generate_custom_blocks(custom, item, "hand_cards", 2, true, ceffect)
	ceffect["funcs"] = ui.codec.encode_effect_list(cnodes)
	var one:Array = ui.generate_custom_blocks(ui.blank_custom_card("attack"), item, "hand_cards", 1, true, {})
	check(one.size() == 3 and one.all(func(n): return n.func != "for_func"), "one custom card lays out flat without a loop")
	var chost := BaseAttack.new("probe_host2", "res://data/attacks/basic/luck/luck.png", [])
	chost._effects = LoadHelper.load_effects([ceffect], chost)
	EffectManager.register_effects(chost._effects, 0)
	EffectManager.activating_eff = chost._effects[0]
	EffectManager.activate_effect(chost._effects[0])
	EffectManager.activating_eff = null
	var chand:Array = GameDataManager.get_player_data(0).hand_cards
	check(chand.size() == 2 and chand.all(func(c): return c is BaseAttack and c._name == "probe_custom_attack" and c._power.number == 7 and "magic" in c._attributes), "custom attack x2 built from data " + str(chand.map(func(c): return c._name)))
	check(chand.size() == 2 and chand[0] != chand[1] and chand[0]._effects[0] != chand[1]._effects[0], "each custom card has its own effects")
	check(chand.size() == 2 and chand[0].from == chost and chand[0]._card_img == "res://data/attacks/basic/luck/probe.png", "custom card owner and image dir default to activating card " + (str(chand[0]._card_img) if chand.size() > 0 else ""))
	check(chand.size() == 2 and chand[0]._card_back_img.ends_with("attack_card_back.png"), "custom card uses declared card back")
	check(chand.size() == 2 and chand[0]._effects[0]._trigger_player_id == 0, "custom card effects registered for the player")
	var mag_before:float = GameDataManager.get_player_data(0).magic.number
	EffectManager.activating_eff = chand[0]._effects[0]
	EffectManager.activate_effect(chand[0]._effects[0])
	EffectManager.activating_eff = null
	check(GameDataManager.get_player_data(0).magic.number == mag_before + 2, "custom card's own effect runs with its own numbers")
	check(custom.get("effects")[0].has("effect_name") and not custom.has("_dir_path"), "building does not touch the data written in the block")
	var buff = BuildCard.new().exec({"buff_name": "probe_buff", "is_active": true, "buff_level": {"number": 3, "can_change": true, "is_pure_number": true}, "effects": []}, "buff")
	check(buff is BaseBuff and buff._buff_level.number == 3, "custom buff built")
	var ev = BuildCard.new().exec({"card_name": "probe_ev", "card_img": "x.png", "score": {"number": 1, "can_change": true, "is_pure_number": true}}, "event", null, "res://data/events")
	check(ev is BaseEvent and ev._card_img == "res://data/events/x.png", "custom event with explicit image dir")

	setup()
	var owner := BaseAttack.new("probe_owner", "", [])
	var made = CreateCard.new().exec("surveil", "attack", owner)
	check(made != null and made.from == owner, "explicit owner overrides default")
	check(CreateCard.new().exec("no_such_card_x", "attack") == null, "unknown name gives nothing")
	check(GameDataManager.get_player_data(0).hand_cards.is_empty(), "create_card alone places nothing")

	# 编辑器：生成牌按钮、威力计算删除、时机搜索、内部名检查
	for k in ui.kind_button.item_count:
		if str(ui.kind_button.get_item_metadata(k)) == "attack":
			ui._select_kind(k)
	ui._new_card()
	ui._add_effect()
	ui._paint_scripts()
	var view:Dictionary = ui.effects_view[0]
	ui.open_generate(view)
	ui.gen_mode.select(1)
	ui._show_generate_mode()
	check(ui.gen_window.visible and ui.gen_list.item_count > 5, "generate window lists library cards " + str(ui.gen_list.item_count))
	ui.gen_list.select(0)
	ui.gen_list.item_selected.emit(0)
	ui.gen_count.value = 2
	ui._apply_generate()
	await get_tree().process_frame
	ui._commit()
	var funcs:Array = ui.data.effects[0].funcs
	var names := funcs.map(func(f): return f.func_name)
	check(names.has("for_func") and JSON.stringify(funcs).find("create_card") != -1 and JSON.stringify(funcs).find("add_to_array") != -1, "generate writes existing operations " + str(names))
	ui.gen_window.hide()
	# 自定义新牌：弹窗默认就是自定义，加进去后自动打开那张牌；写的卡面落在积木里，保存检查也覆盖它
	ui.effects_view[0].lists.funcs.clear()
	view = ui.effects_view[0]
	ui.open_generate(view)
	check(ui.gen_mode.selected == 0 and ui.gen_custom.visible and not ui.gen_library.visible and ui.gen_register.button_pressed, "generate window defaults to custom card with effects on")
	for t in ui.gen_custom_type.item_count:
		if str(ui.gen_custom_type.get_item_metadata(t).type) == "skill":
			ui.gen_custom_type.select(t)
	ui._apply_generate()
	await get_tree().process_frame
	await get_tree().process_frame
	ui.gen_window.hide()
	var focused = ui._focus_obj()
	check(ui.focus_item == "skill" and focused is Dictionary and focused.has("skill_name") and focused.has("effects"), "custom card opens in its own page " + str(ui.focus_path))
	check(ui.sub_entries.any(func(e): return str(e.shown).find("自定义") != -1), "custom card listed with sub cards")
	focused["skill_name"] = "Bad Custom"
	ui._changed()
	check(ui._collect_issues().any(func(x): return str(x).find("Bad Custom") != -1 and str(x).find("格式不对") != -1), "custom card checked like a sub card")
	focused["skill_name"] = "probe_custom_skill"
	ui._add_effect()
	ui._commit()
	check((focused.effects as Array).size() == 1, "effect added onto the custom card")
	ui.focus_to([], "")
	ui._commit()
	var saved_json := JSON.stringify(ui.data.effects[0])
	check(saved_json.find("build_card") != -1 and saved_json.find("probe_custom_skill") != -1 and saved_json.find("register_object_effects") != -1, "custom card data lives inside the block")
	check(not ui.data.has("custom_cards") and not ui.data.has("specials"), "no extra field written to the card")
	ui.effects_view[0].lists.funcs.clear()
	ui.effects_view[0].effect["funcs"] = []
	view = ui.effects_view[0]

	view.lists["power_query"] = []
	view.effect["power_query"] = []
	ui._paint_scripts()
	var del = ui.script_box.find_child("DeletePowerQuery", true, false)
	check(del != null, "power query shows a delete button")
	del.pressed.emit()
	await get_tree().process_frame
	ui._commit()
	check(not ui.data.effects[0].has("power_query") and not view.lists.has("power_query"), "power query removed from model and json")

	ui._open_time_point_popup(ui, func(_p): pass)
	ui.tp_search.text = "战果"
	ui._fill_time_point_tree()
	var hits := 0
	var groups := 0
	var head = ui.tp_tree.get_root().get_first_child()
	while head != null:
		groups += 1
		var it = head.get_first_child()
		while it != null:
			hits += 1
			check(str(it.get_text(0)).find("战果") != -1 or str(head.get_text(0)).find("战果") != -1, "search hit " + it.get_text(0))
			it = it.get_next()
		head = head.get_next()
	check(hits >= 6 and groups >= 1, "search filters time points " + str(hits))
	var picked := []
	ui.tp_pick = func(p): picked.append(p)
	ui._pick_first_time_point()
	check(picked.size() == 1 and ui.maker.time_point_shown(str(picked[0])).find("战果") != -1, "enter picks first match " + str(picked))
	var all_groups:Array = ui.maker.time_point_groups()
	var total := 0
	for g in all_groups:
		total += g.points.size()
	check(total == ui.maker.time_points.size() and all_groups.size() > 5, "every time point grouped once " + str(total))

	ui.data["attack_name"] = "Bad Name"
	var issues:Array = ui._collect_issues()
	check(issues.any(func(s): return str(s).find("格式不对") != -1), "bad internal name reported")
	ui.data.effects.append(ui.data.effects[0].duplicate(true))
	ui._load_effects()
	issues = ui._collect_issues()
	check(issues.any(func(s): return str(s).find("重名") != -1), "duplicate effect name reported")
	ui._show_welcome()
	check(ui.help_body.text.find("命名规范") != -1 and ui.help_body.text.find("{serial}_{identity}") != -1, "welcome explains naming")

	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
