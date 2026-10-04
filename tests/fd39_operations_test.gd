extends Node
# FD3.9 新增 operation 与框架改造的专项回归。
# 每一项都经真实加载器（LoadHelper.load_effects）解析 JSON、经 EffectManager 真实结算，
# 条件型改动同时验正例与反例（反例要求不留任何副作用）。

var failures:Array[String] = []
var checks:int = 0


func check(ok:bool, label:String) -> void:
	checks += 1
	if !ok: failures.append(label)
	print("CHECK ", label, " ", ok)


func _ready() -> void:
	call_deferred("run")


func setup(count:int = 2) -> void:
	EffectManager.reset_runtime()
	GameLog.reset()
	GameData.player_data_library.clear()
	for i in count:
		var d:Dictionary = GameData.new_player_data()
		d.is_out = false
		d.order.set_num(BaseNumber.new(i))
		GameData.player_data_library[i] = d
	for area in MapData.areas:
		area._battle_override = {}
		area._events.clear()
		for loc in area._locations:
			loc._players.clear()


func num(n) -> Dictionary:
	return {"number": n, "can_change": true, "is_pure_number": true}


func effect_data(name:String, funcs:Array, numbers:Array = [], time_points:Array = ["game_start"], extra:Dictionary = {}) -> Dictionary:
	var d := {"effect_name": name, "time_points": time_points, "priority": 0,
		"is_pure_passive": true, "is_residue": false, "effect_numbers": numbers, "funcs": funcs}
	d.merge(extra, true)
	return d


# 挂在一张临时攻击牌上、登记给玩家 id，返回宿主牌
func host_with(effects:Array, id:int = 0) -> BaseAttack:
	var host := BaseAttack.new("probe_host", "", [])
	host._effects = LoadHelper.load_effects(effects, host)
	EffectManager.register_effects(host._effects, id)
	return host


func run_effect(effect:BaseEffect) -> void:
	EffectManager.add_to_activation_pool(effect)
	EffectManager.run_pipeline()


func pd(id:int) -> Dictionary:
	return GameDataManager.get_player_data(id)


func run() -> void:
	test_registry()
	test_map_data_and_dictionary()
	test_pending_cancel_and_edit()
	test_zone_time_points()
	test_before_card_remove()
	test_ask_number()
	test_secret_option()
	test_show_cards()
	test_build_and_activate_effect()
	test_flip_card_face()
	test_text_disabled_and_alias()
	test_battle_result()
	test_end_game()
	test_add_map_area()
	test_player_limits()
	test_power_breakdown()
	test_real_card_json()
	print("RESULT checks=%d failures=%s" % [checks, str(failures)])
	get_tree().quit()


# 新增的 14 个 operation 都登记进注册表，磁盘文件与表项一一对应
func test_registry() -> void:
	var names := ["get_map_data_value", "set_dictionary_value", "get_player_power_breakdown", "ask_player_number",
		"ask_players_secret_option", "show_cards", "build_effect", "activate_effect", "flip_card_face",
		"cancel_pending_action", "edit_pending_action", "set_battle_result", "end_game", "add_map_area"]
	var missing:Array = []
	for n in names:
		if AllOperations.get_class_name_of(n) == "" or !ResourceLoader.exists("res://scripts/system/operations/%s.gd" % LoadHelper.func_name_to_class_name(n)):
			missing.append(n)
	check(missing.is_empty(), "new operations registered and on disk " + str(missing))
	var files:Array = []
	for f in DirAccess.get_files_at("res://scripts/system/operations"):
		if f.ends_with(".gd"):
			files.append(f.get_basename())
	var classes:Array = []
	for k in AllOperations.TABLE:
		classes.append(AllOperations.TABLE[k]["class"])
	files.sort(); classes.sort()
	check(files == classes, "operation files equal registry entries %d/%d" % [files.size(), classes.size()])


func test_map_data_and_dictionary() -> void:
	setup()
	var host := host_with([effect_data("probe_map", [
		{"func_name": "get_map_data_value", "parameters": ["event_deck"], "var_index": 0},
		{"func_name": "get_eff_source_card", "parameters": [], "var_index": 1},
		{"func_name": "get_property", "parameters": [{"self_var": 1}, "_values"], "var_index": 2},
		{"func_name": "set_dictionary_value", "parameters": [{"self_var": 2}, "spirit", {"number_index": 0}], "var_index": -1},
		{"func_name": "get_dictionary_value", "parameters": [{"self_var": 2}, "spirit"], "var_index": 3},
		{"func_name": "edit_num_and_return", "parameters": [{"self_var": 3}, {"number_index": 1}], "var_index": -1},
		{"func_name": "get_map_data_value", "parameters": [""], "var_index": 4}
	], [num(2), num(3)])])
	run_effect(host._effects[0])
	var vars:Array = host._effects[0]._self_vars
	check(vars.size() > 0 and is_same(vars[0], MapData.event_deck), "get_map_data_value returns the real event deck array")
	check(host._values.has("spirit") and (host._values["spirit"] as BaseNumber).number == 5, "named counter written then increased via existing ops")
	check(vars.size() > 4 and vars[4] == null, "empty key reads nothing")
	var clone = CloneObject.new().exec(host)
	check(clone._values.has("spirit") and clone._values["spirit"] != host._values["spirit"] and clone._values["spirit"].number == 5, "clone copies named values by value")


func test_pending_cancel_and_edit() -> void:
	# 反例：没有监听时照常获得
	setup()
	EditScore.new().exec(null, BaseNumber.new(4), 0)
	check(pd(0).score.number == 4, "score gained normally without listeners")
	check(EffectManager.pending_actions.is_empty(), "pending stack empty afterwards")
	# 正例：减半（改写 amount）
	setup()
	host_with([effect_data("probe_half", [
		{"func_name": "edit_pending_action", "parameters": ["amount", {"number_index": 0}], "var_index": -1}
	], [num(2)], ["self_before_score_add"])])
	EditScore.new().exec(null, BaseNumber.new(4), 0)
	check(pd(0).score.number == 2, "before_score_add listener rewrote amount 4 -> 2: %d" % pd(0).score.number)
	EditScore.new().exec(null, BaseNumber.new(4), 1)
	check(pd(1).score.number == 4, "self_ listener does not touch other players' gains")
	EditScore.new().exec(null, BaseNumber.new(-1), 0)
	check(pd(0).score.number == 1, "losing score does not ask before_score_add")
	# 取消淘汰：失去生命到 0 但被取消 → 不出局，派发免于淘汰
	setup()
	host_with([effect_data("probe_avalon", [
		{"func_name": "cancel_pending_action", "parameters": [], "var_index": -1}
	], [], ["self_before_eliminate"])])
	var survived := host_with([effect_data("probe_survive", [
		{"func_name": "edit_score", "parameters": [null, {"number_index": 0}, -1], "var_index": -1}
	], [num(7)], ["self_survive_elimination"])])
	EditLives.new().exec(BaseNumber.new(0), BaseNumber.new(0), 0)
	check(!pd(0).is_out, "cancelled elimination keeps the player in")
	check(pd(0).score.number == 7, "survive_elimination fired after cancel")
	var cr := ClimaxResolver.new()
	check(!cr.eliminate_player(0) and !pd(0).is_out, "climax elimination honours the same cancel")
	check(cr.eliminate_player(1) and pd(1).is_out, "players without the listener are eliminated")
	# 取消败北
	setup()
	host_with([effect_data("probe_guard", [
		{"func_name": "cancel_pending_action", "parameters": [], "var_index": -1}
	], [], ["self_before_defeat"])])
	Defeat.new().exec(0)
	Defeat.new().exec(1)
	check(!DefeatBuff.is_defeated(0) and DefeatBuff.is_defeated(1), "before_defeat cancel only protects the listener")
	# 魔力获得被取消 / 改写不影响扣减
	setup()
	host_with([effect_data("probe_no_magic", [
		{"func_name": "cancel_pending_action", "parameters": [], "var_index": -1}
	], [], ["self_before_magic_add"])])
	var m0:int = pd(0).magic.number
	EditMagic.new().exec(null, BaseNumber.new(3), 0)
	check(pd(0).magic.number == m0, "magic gain cancelled")
	EditMagic.new().exec(null, BaseNumber.new(-1), 0)
	check(pd(0).magic.number == m0 - 1, "magic spending is not asked")
	check(CancelPendingAction.new().exec() == false and EditPendingAction.new().exec("amount", 1) == null, "no pending action outside before_* windows")


func test_zone_time_points() -> void:
	setup()
	host_with([effect_data("probe_to_discard", [
		{"func_name": "edit_score", "parameters": [null, {"number_index": 0}, -1], "var_index": -1}
	], [num(1)], ["self_card_to_discard"])])
	var card := BaseAttack.new("probe_card", "", [])
	pd(0).hand_cards.append(card)
	DrawCardByCard.new().exec(card, pd(0).hand_cards, pd(0).discard)
	check(pd(0).discard.has(card) and pd(0).score.number == 1, "card_to_discard fired for the owner")
	var other := BaseAttack.new("probe_card2", "", [])
	pd(1).hand_cards.append(other)
	DrawCardByCard.new().exec(other, pd(1).hand_cards, pd(1).discard)
	check(pd(0).score.number == 1, "others moving cards does not fire self_card_to_discard")
	var loose:Array = [BaseAttack.new("probe_loose", "", [])]
	var sink:Array = []
	DrawCardByIndex.new().exec(loose, sink, 0)
	check(sink.size() == 1 and pd(0).score.number == 1, "arrays outside player zones move without time points")
	# 抽牌：card_drawn + 离开牌库
	setup()
	host_with([effect_data("probe_draw", [
		{"func_name": "edit_score", "parameters": [null, {"number_index": 0}, -1], "var_index": -1}
	], [num(10)], ["self_card_drawn"]), effect_data("probe_leave", [
		{"func_name": "edit_score", "parameters": [null, {"number_index": 0}, -1], "var_index": -1}
	], [num(1)], ["self_card_leave_deck"])])
	pd(0).deck.append(BaseAttack.new("probe_deck", "", []))
	DrawCardFromPlDeckToHand.new().exec(0, 0)
	check(pd(0).score.number == 11, "draw fires card_drawn and card_leave_deck %d" % pd(0).score.number)
	# 进入/离开地点
	setup()
	host_with([effect_data("probe_enter", [
		{"func_name": "edit_score", "parameters": [null, {"number_index": 0}, -1], "var_index": -1}
	], [num(1)], ["self_enter_location"]), effect_data("probe_leave_loc", [
		{"func_name": "edit_score", "parameters": [null, {"number_index": 0}, -1], "var_index": -1}
	], [num(100)], ["self_leave_location"])])
	var loc_a:BaseLocation = MapData.miyama._locations[0]
	var loc_b:BaseLocation = MapData.shinto._locations[0]
	SetLocation.new().exec(loc_a, 0, false)
	SetLocation.new().exec(loc_b, 0, false)
	RemoveFromBoard.new().exec(0)
	check(pd(0).score.number == 202, "enter x2 and leave x2 (move + remove) %d" % pd(0).score.number)


func test_before_card_remove() -> void:
	setup()
	host_with([effect_data("probe_keep", [
		{"func_name": "cancel_pending_action", "parameters": [], "var_index": -1}
	], [], ["self_before_card_remove"])])
	var card := BaseAttack.new("probe_rm", "", [])
	pd(0).hand_cards.append(card)
	DrawCardByCard.new().exec(card, pd(0).hand_cards, pd(0).out_of_game.attacks)
	check(pd(0).hand_cards.has(card) and !pd(0).out_of_game.attacks.has(card), "removal cancelled: card stays in hand")
	var card2 := BaseAttack.new("probe_rm2", "", [])
	pd(1).hand_cards.append(card2)
	DrawCardByCard.new().exec(card2, pd(1).hand_cards, pd(1).out_of_game.attacks)
	check(pd(1).out_of_game.attacks.has(card2), "removal of other players' cards is not cancelled")


func test_ask_number() -> void:
	setup()
	var host := host_with([effect_data("probe_number", [
		{"func_name": "ask_player_number", "parameters": [{"number_index": 0}, {"number_index": 1}, -1, "选数"], "var_index": 0},
		{"func_name": "edit_score", "parameters": [{"self_var": 0}, null, -1], "var_index": -1}
	], [num(1), num(3)])])
	run_effect(host._effects[0])
	var pending := EffectManager.get_pending_active_effect()
	check(pending != null and pending.has_options() and pending._options[0].get("quantity_range") == [1, 3], "number choice reuses quantity_range")
	pending.set_option_quantity(0, 3)
	EffectManager.submit_option_choice(pending, [0])
	check(pd(0).score.number == 3, "later step reads the picked number %d" % pd(0).score.number)
	# 放弃：保持下限
	setup()
	host = host_with([effect_data("probe_number2", [
		{"func_name": "ask_player_number", "parameters": [{"number_index": 0}, {"number_index": 1}, -1, ""], "var_index": 0},
		{"func_name": "edit_score", "parameters": [{"self_var": 0}, null, -1], "var_index": -1}
	], [num(2), num(5)])])
	run_effect(host._effects[0])
	EffectManager.submit_active_choice(EffectManager.get_pending_active_effect(), false)
	check(pd(0).score.number == 2, "declined number keeps the lower bound")
	# 上下限相同不询问
	setup()
	host = host_with([effect_data("probe_number3", [
		{"func_name": "ask_player_number", "parameters": [4, 4, -1, ""], "var_index": 0},
		{"func_name": "edit_score", "parameters": [{"self_var": 0}, null, -1], "var_index": -1}
	])])
	run_effect(host._effects[0])
	check(!EffectManager.is_waiting_for_choice() and pd(0).score.number == 4, "fixed range answers without asking")


func test_secret_option() -> void:
	setup(3)
	var opts := [{"shown_option_name": "石头", "funcs": []}, {"shown_option_name": "布", "funcs": []}]
	var host := host_with([effect_data("probe_secret", [
		{"func_name": "ask_players_secret_option", "parameters": [[0, 1, 2], opts, "猜拳", true], "var_index": 0},
		{"func_name": "array_length", "parameters": [{"self_var": 0}], "var_index": 1},
		{"func_name": "calculate_number", "parameters": [{"self_var": 1}, "+", 0], "var_index": 2},
		{"func_name": "edit_score", "parameters": [{"self_var": 2}, null, -1], "var_index": -1}
	])])
	run_effect(host._effects[0])
	var answered := 0
	for pick in [1, 0]:
		var pending := EffectManager.get_pending_active_effect()
		if pending != null:
			EffectManager.submit_option_choice(pending, [pick])
			answered += 1
	var last := EffectManager.get_pending_active_effect()
	if last != null:
		EffectManager.submit_active_choice(last, false)
	var results:Dictionary = host._effects[0]._self_vars[0]
	check(answered == 2 and results.get(0) == 1 and results.get(1) == 0 and !results.has(2), "each player answered separately, decline left out " + str(results))
	check(pd(0).score.number == 2, "later steps ran after everyone answered")
	var shown := GameLog.query({"type": "option_used", "tags": ["secret_choice"]}, null)
	check(shown.size() == 2, "secret picks recorded with secret_choice tag")
	var msgs:Array = EffectManager.pop_messages(0)
	var revealed := false
	for m in msgs:
		if str(m).find("猜拳") != -1:
			revealed = true
	check(revealed, "reveal=true announces the results after all answered")


func test_show_cards() -> void:
	setup()
	var a := BaseAttack.new("probe_show", "", [])
	a._shown_name = "展示甲"
	a._is_concealed = true
	var shown:Array = ShowCards.new().exec([a], [1], "看牌")
	check(shown == [a] and a._is_concealed, "show_cards does not flip the card")
	check(EffectManager.pop_messages(0).is_empty() and EffectManager.pop_messages(1).size() == 1, "only listed viewers get the message")
	check(GameLog.query({"type": "show_cards"}, null).size() == 1, "show fact is logged")


func test_build_and_activate_effect() -> void:
	setup()
	var granted := effect_data("granted_bonus", [
		{"func_name": "edit_score", "parameters": [null, {"number_index": 0}, -1], "var_index": -1}
	], [num(5)])
	var target := BaseAttack.new("probe_target", "", [])
	var host := host_with([effect_data("probe_grant", [
		{"func_name": "build_effect", "parameters": [granted, null], "var_index": 0},
		{"func_name": "activate_effect", "parameters": [{"self_var": 0}, 1], "var_index": 1}
	])])
	run_effect(host._effects[0])
	var built = host._effects[0]._self_vars[0]
	check(built is BaseEffect and built._name == "granted_bonus" and built.from == host, "build_effect owner defaults to source card")
	check(pd(1).score.number == 5 and pd(0).score.number == 0, "activate_effect resolved it for player 1")
	# 失去文字的效果不能被 activate
	setup()
	var blocked := host_with([granted], 0)
	blocked._text_disabled = true
	check(ActivateEffect.new().exec(blocked._effects[0], 0) == null and pd(0).score.number == 0, "text-disabled effect cannot be activated")
	# 已归属他人的效果：复制一份，原效果归属不变
	setup()
	var owned := host_with([granted], 0)
	var used = ActivateEffect.new().exec(owned._effects[0], 1)
	check(used != owned._effects[0] and owned._effects[0]._trigger_player_id == 0 and pd(1).score.number == 5, "activating another's effect uses a copy")


func test_flip_card_face() -> void:
	setup()
	var face_b := {"attack_name": "form_b", "shown_attack_name": "第二形态", "attack_card_img": "", "attributes": ["magic"],
		"cost": num(1), "power": num(7), "effects": [effect_data("form_b_bonus", [
			{"func_name": "edit_score", "parameters": [null, {"number_index": 0}, -1], "var_index": -1}], [num(9)], ["self_card_face_flipped"])]}
	var face_a := {"attack_name": "form_a", "attack_card_img": "", "attributes": ["strength"],
		"cost": num(2), "power": num(3), "effects": []}
	var data := face_a.duplicate(true)
	data["faces"] = [face_a, face_b]
	var cards:Array = LoadGame.load_attacks([data], "res://data", null)
	var card:BaseAttack = cards[0]
	check(card._faces.size() == 2, "faces loaded from JSON")
	pd(0).played_cards.append(card)
	card._is_activating = true
	pd(0).power.set_num(BaseNumber.new(3))
	RegisterObjectEffects.new().exec(card, 0)
	var cost_ref:BaseNumber = card._cost
	FlipCardFace.new().exec(card)
	check(card._name == "form_b" and card._attributes == ["magic"] and card._face_index == 1, "flipped to the next face")
	check(card._power.number == 7 and is_same(card._cost, cost_ref) and card._cost.number == 1, "numbers rewritten in place")
	check(pd(0).power.number == 7, "on-board power synced with the new face %d" % pd(0).power.number)
	check(pd(0).score.number == 9, "new face effect registered and heard card_face_flipped")
	check(card._is_activating and pd(0).played_cards.has(card), "flipping keeps board state")
	var single := BaseAttack.new("probe_single", "", [])
	check(FlipCardFace.new().exec(single) == null and single._name == "probe_single", "single-faced card is untouched")


func test_text_disabled_and_alias() -> void:
	setup()
	var host := host_with([effect_data("probe_text", [
		{"func_name": "edit_score", "parameters": [null, {"number_index": 0}, -1], "var_index": -1}], [num(1)])])
	host._text_disabled = true
	check(!EffectManager.card_state_allows(host._effects[0]), "text disabled blocks the card's effects")
	host._text_disabled = false
	host._effects[0]._disabled = true
	check(!EffectManager.card_state_allows(host._effects[0]), "disabled effect is blocked")
	host._effects[0]._disabled = false
	check(EffectManager.card_state_allows(host._effects[0]), "restored effect works again")
	var alias := BaseAttack.new("probe_alias", "", [])
	alias._alias_names = ["goddess_core"]
	check(GetCardsByNameFrArr.new().exec("goddess_core", [alias]) == [alias] and GetObjectsByNameFrArr.new().exec("probe_alias", [alias]) == [alias], "name queries match aliases and real names")
	check(GetCardsByNameFrArr.new().exec("nobody", [alias]).is_empty(), "unrelated names still miss")


func _place(id:int, loc:BaseLocation, power:int) -> void:
	Deploy.new().exec(loc, id, true)
	pd(id).power.set_num(BaseNumber.new(power))


func test_battle_result() -> void:
	var area:BaseMapArea = MapData.miyama
	# 反例：不改写时按威力
	setup(3)
	_place(0, area._locations[2], 5)
	_place(1, area._locations[2], 9)
	var res:Dictionary = BattleResolver.new().exec([0, 1])
	check(res.winners_by_area.get(area._area_name) == [1], "no override: highest power wins")
	# replace
	setup(3)
	_place(0, area._locations[2], 5)
	_place(1, area._locations[2], 9)
	SetBattleResult.new().exec(area, [0], "replace")
	res = BattleResolver.new().exec([0, 1])
	check(res.winners_by_area.get(area._area_name) == [0], "replace names the winner")
	check(area._battle_override.is_empty(), "override cleared after resolution")
	# add（共享胜利）
	setup(3)
	_place(0, area._locations[2], 5)
	_place(1, area._locations[2], 9)
	SetBattleResult.new().exec(area, [0], "add")
	res = BattleResolver.new().exec([0, 1])
	var winners:Array = res.winners_by_area.get(area._area_name, [])
	winners.sort()
	check(winners == [0, 1], "add shares the win")
	# losers_only：败北者中比威力
	setup(3)
	_place(0, area._locations[2], 5)
	_place(1, area._locations[2], 9)
	_place(2, area._locations[2], 7)
	DefeatBuff.apply(1)
	DefeatBuff.apply(2)
	SetBattleResult.new().exec(area, [], "losers_only")
	res = BattleResolver.new().exec([0, 1, 2])
	check(res.winners_by_area.get(area._area_name) == [1], "losers_only picks the strongest defeated player")
	DefeatBuff.clear_all()
	check(SetBattleResult.new().exec(area, [0], "unknown") == null and area._battle_override.is_empty(), "unknown mode writes nothing")
	# 非参战者不计入
	setup(3)
	_place(0, area._locations[2], 5)
	SetBattleResult.new().exec(area, [2], "replace")
	res = BattleResolver.new().exec([0])
	check(!res.winners_by_area.get(area._area_name, []).has(2), "players outside the battle cannot be named winners")


func test_end_game() -> void:
	setup()
	GameProgress.is_game_over = false
	check(EndGame.new().exec([1]), "end_game ends the match")
	check(GameProgress.is_game_over and pd(1).is_victory and !pd(0).is_victory, "winner flags written")
	check(GameLog.query({"type": "game_end"}, null).size() == 1, "game end recorded through the normal end_game path")
	check(!EndGame.new().exec([0]) and pd(1).is_victory, "already ended: second call ignored")
	GameProgress.is_game_over = false


func test_add_map_area() -> void:
	setup()
	var before:int = MapData.areas.size()
	var old_link:BaseMapArea = MapData.scout._linked_map_area
	var area = AddMapArea.new().exec({"area_name": "deep_space", "score": num(2), "move_cost": num(1), "can_deploy": false,
		"linked_map_area_name": "", "locations": [{"magic": num(0), "benefit": num(1), "player_num_limit": -1, "will_move_to": true}]},
		MapData.scout, null)
	check(area is BaseMapArea and MapData.areas.size() == before + 1 and MapData.areas.has(area), "new area appended to the map")
	check(MapData.scout._linked_map_area == area and area._locations[0].get_from() == area, "linked from scout, locations point back")
	check(SetLocation.new().exec(area._locations[0], 0, false) and GetPlayersInMapArea.new().exec(area).has(0), "players can be placed in the new area")
	RemoveFromBoard.new().exec(0)
	MapData.areas.erase(area)
	MapData.scout._linked_map_area = old_link
	check(AddMapArea.new().exec({}) == null and MapData.areas.size() == before, "empty data adds nothing")


func test_player_limits() -> void:
	setup()
	var saved:int = GameData.magic_limit.number
	GameData.magic_limit.set_num(BaseNumber.new(12))
	pd(0).magic_limit = BaseNumber.new(16)
	EditMagic.new().exec(BaseNumber.new(20), null, 0)
	EditMagic.new().exec(BaseNumber.new(20), null, 1)
	check(pd(0).magic.number == 16 and pd(1).magic.number == 12, "per-player magic limit overrides the global one")
	GameData.magic_limit.set_num(BaseNumber.new(saved))
	pd(0).hand_limit = BaseNumber.new(4)
	check(GameData.player_hand_limit(0).number == 4 and GameData.player_hand_limit(1) == GameData.hand_limit, "hand limit falls back to global")
	for i in 6:
		pd(0).deck.append(BaseAttack.new("probe_h%d" % i, "", []))
	RefillHand.new().exec(0, GameData.player_hand_limit(0))
	check(pd(0).hand_cards.size() == 4, "refill uses the per-player hand limit")
	# 战果下限
	EditScore.new().exec(BaseNumber.new(1), null, 0)
	EditScore.new().exec(null, BaseNumber.new(-5), 0)
	check(pd(0).score.number == -4, "no score floor by default")
	pd(1).score_min = BaseNumber.new(0)
	EditScore.new().exec(BaseNumber.new(1), null, 1)
	EditScore.new().exec(null, BaseNumber.new(-5), 1)
	check(pd(1).score.number == 0, "declared score floor clamps")
	# 基础地利加成只在享有地利时生效
	setup()
	var loc:BaseLocation = MapData.miyama._locations[0]
	Deploy.new().exec(loc, 0, true)
	pd(0).location_benefit_bonus = BaseNumber.new(2)
	check(GetEffectiveLocationBenefit.new().exec(0) == GetEffectiveLocationBenefit.current_benefit(loc) + 2, "benefit bonus adds to deployed benefit")
	RemoveFromBoard.new().exec(0)
	SetLocation.new().exec(MapData.miyama._locations[1], 0, false)
	check(GetEffectiveLocationBenefit.new().exec(0) == 0, "bonus does not apply without deployed benefit")
	RemoveFromBoard.new().exec(0)
	# 每段移动减免
	setup()
	SetLocation.new().exec(MapData.miyama._locations[2], 0, false)
	pd(0).move_cost_discount_per_step = BaseNumber.new(1)
	var cost = MoveLocation.new().exec(BaseNumber.new(1), 0)
	check(cost is BaseNumber and cost.number == maxi(0, MapData.miyama._move_cost.number - 1), "per-step discount applied")
	RemoveFromBoard.new().exec(0)


func test_power_breakdown() -> void:
	setup()
	var situation := BaseSituation.new("probe_situation", "", BaseNumber.new(0))
	situation._effects = LoadHelper.load_effects([effect_data("sit_bonus", [
		{"func_name": "edit_power", "parameters": [null, {"number_index": 0}, 0], "var_index": -1}], [num(3)])], situation)
	EffectManager.register_effects(situation._effects, 0)
	run_effect(situation._effects[0])
	var own := host_with([effect_data("own_bonus", [
		{"func_name": "edit_data_number", "parameters": ["total_power_bonus", null, {"number_index": 0}, -1], "var_index": -1}], [num(2)])], 0)
	run_effect(own._effects[0])
	var other := host_with([effect_data("other_bonus", [
		{"func_name": "edit_power", "parameters": [null, {"number_index": 0}, 0], "var_index": -1}], [num(4)])], 1)
	run_effect(other._effects[0])
	var q := GetPlayerPowerBreakdown.new()
	var total:int = GetPlayerTotalPower.new().exec(0)
	check(total == 9, "total power includes all three sources %d" % total)
	check(q.exec(0).number == total, "no filter equals total power")
	check(q.exec(0, [], ["situation"]).number == 6, "excluding situation removes 3")
	check(q.exec(0, [], ["others"]).number == 5, "excluding other players' abilities removes 4")
	check(q.exec(0, ["self"]).number == 2, "include self counts only own ability")
	check(q.exec(0, ["attack"]).number == 6, "include attack sources (own+other hosts) %d" % q.exec(0, ["attack"]).number)


# 真实卡牌 JSON：从 data 目录读出效果原文，经真实加载器与结算验证本轮改写的接线
func _real_effect(rel_path:String, effect_name:String, id:int) -> BaseAttack:
	var f := FileAccess.open(LoadHelper.resolve_path("data".path_join(rel_path)), FileAccess.READ)
	check(f != null, "read " + rel_path)
	if f == null:
		return null
	var data = JSON.parse_string(f.get_as_text())
	var found:Array = []
	_collect_effect(data, effect_name, found)
	check(found.size() == 1, "found effect %s once in %s" % [effect_name, rel_path])
	if found.is_empty():
		return null
	return host_with([found[0]], id)


func _collect_effect(value, effect_name:String, out:Array) -> void:
	if value is Dictionary:
		if str(value.get("effect_name", "")) == effect_name:
			out.append(value)
		for v in value.values():
			_collect_effect(v, effect_name, out)
	elif value is Array:
		for v in value:
			_collect_effect(v, effect_name, out)


func test_real_card_json() -> void:
	# 远离尘世的理想乡：首次被淘汰时取消淘汰并失去所有魔力；第二次正常出局
	setup()
	_real_effect("masters/00001_emiya_shirou/00001_emiya_shirou.json", "avalon", 0)
	(pd(0).magic as BaseNumber).set_num(BaseNumber.new(7))
	var cr := ClimaxResolver.new()
	check(!cr.eliminate_player(0) and !pd(0).is_out, "avalon cancels the first elimination")
	check((pd(0).magic as BaseNumber).number == 0, "avalon loses all magic when it saves you")
	(pd(0).magic as BaseNumber).set_num(BaseNumber.new(5))
	check(cr.eliminate_player(0) and pd(0).is_out, "avalon does not save a second time")
	check((pd(0).magic as BaseNumber).number == 5, "second elimination leaves magic untouched")
	check(cr.eliminate_player(1) and pd(1).is_out, "avalon only protects its owner")
	# 生命归零路径与高潮淘汰走同一个即将淘汰询问
	setup()
	_real_effect("masters/00001_emiya_shirou/00001_emiya_shirou.json", "avalon", 0)
	EditLives.new().exec(BaseNumber.new(0), BaseNumber.new(0), 0)
	check(!pd(0).is_out, "avalon also cancels elimination by losing all lives")
	# 旧写法开局多给一条命，改写后不应再改生命
	setup()
	var before_lives:int = (pd(0).lives as BaseNumber).number
	_real_effect("masters/00001_emiya_shirou/00001_emiya_shirou.json", "avalon", 0)
	TimePointChecker.global_time_point([TimePoints.GAME_START])
	check((pd(0).lives as BaseNumber).number == before_lives, "avalon no longer grants an extra life at game start")

	# 吸魔命令：进入深山町（部署、移动、效果搬运都算）获得魔力，进入别处不获得
	setup()
	_real_effect("masters/00003_matou_shinji/00003_matou_shinji.json", "absorb_magic_command", 0)
	var miyama:BaseMapArea = MapData.miyama
	var other_area:BaseMapArea = null
	for area in MapData.areas:
		if area != miyama and !area._locations.is_empty():
			other_area = area
			break
	(pd(0).magic as BaseNumber).set_num(BaseNumber.new(0))
	SetLocation.new().exec(other_area._locations[0], 0, false, true)
	check((pd(0).magic as BaseNumber).number == 0, "entering another area gives no magic")
	SetLocation.new().exec(miyama._locations[0], 0, false, true)
	check((pd(0).magic as BaseNumber).number == 1, "effect relocation into miyama gives 1 magic")
	SetLocation.new().exec(miyama._locations[1], 0, false, true)
	check((pd(0).magic as BaseNumber).number == 2, "entering a new miyama location counts as entering again")
	RemoveFromBoard.new().exec(0)
	Deploy.new().exec(miyama._locations[0], 0)
	check((pd(0).magic as BaseNumber).number == 3, "deploying into miyama gives 1 magic")
