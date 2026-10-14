extends Node

# B06 行为探针：公开加载器 -> 开局发牌 -> UI/AI 手动候选 -> 真实资源结算。
# 不读效果池、触发玩家字段或卡牌私有效果数组；同声明未登记牌作对照。
const POINT:String = "b06_initial_registration_probe"
var failures:Array = []
var checks:int = 0

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func number_data(value:int) -> Dictionary:
	return {"number":value, "can_change":true, "is_pure_number":true}

func attack_data() -> Dictionary:
	return {
		"attack_name":"b06_initial_card", "attack_card_img":"", "attributes":[],
		"cost":number_data(0), "power":number_data(0),
		"initial_zone":"out_of_game.attacks", "initial_count":2,
		"effects":[{
			"effect_name":"b06_gain_magic", "time_points":[POINT], "priority":0,
			"is_pure_passive":false, "is_residue":false, "is_manual":true,
			"need_activate":false, "effect_numbers":[number_data(1)],
			"funcs":[{"func_name":"edit_magic", "parameters":[null, {"number_index":0}]}]
		}]
	}

func candidates_for(card, player_id:int) -> Array:
	var result:Array = []
	for effect:BaseEffect in EffectManager.manual_activations(player_id):
		if is_same(effect.get_from(), card):
			result.append(effect)
	return result

func open_window() -> void:
	for id in [0, 1, 2]:
		GameDataManager.get_player_data(id)["current_time_points"] = [POINT]

func run() -> void:
	var lifecycle:Dictionary = EffectManager.reset_runtime()
	var progress:Dictionary = GameProgress.reset_progress(false, lifecycle.context)
	var fixture_context:SessionContext = progress.context
	GameLog.reset()
	GameData.player_data_library.clear()
	for id in [0, 1, 2]:
		var player:Dictionary = GameDataManager.get_player_data(id)
		player["is_out"] = false
		player["order"] = BaseNumber.new(id)
		player["magic"].set_num(BaseNumber.new(0))
	open_window()

	# 一个御主模板被两位玩家共用，真实开局入口负责逐张克隆、入区、登记。
	var masters:Array = LoadGame.load_masters([{
		"master_name":"b06_master", "shown_master_name":"B06 probe",
		"header_img":"", "master_card_img":"", "command_spell_img":"",
		"effects":[], "tags":[], "specials":{"ATTACKS":[attack_data()]}
	}], "", null)
	check(masters.size() == 1, "fixture public loader supplies one master")
	if masters.size() != 1:
		finish()
		return

	# 创建侧明确声明加载池 identity；消费端只验原来源，不补票。
	GameData.loaded_masters.append(masters[0])
	# 对照只做同声明的加载、克隆及入区，明确不调用登记。
	var control_templates:Array = LoadGame.load_attacks([attack_data()], "", null)
	var control_factory := CloneContext.new()
	control_factory.configure_template(fixture_context, control_templates)
	var control = control_factory.copy_result(control_templates[0], fixture_context).object
	(GameDataManager.get_player_data(2)["out_of_game"]["attacks"] as Array).append(control)
	check(candidates_for(control, 2).is_empty(), "control cloned card without registration has no manual candidate")
	check(EffectManager.manual_activations(2).is_empty(), "control owner has no registered manual activation")

	var cards:Array = []
	var effects:Array = []
	for id in [0, 1]:
		GameDataManager.get_player_data(id)["master"] = masters[0]
		MasterManager.deal_initial_master_cards(id, fixture_context)
		var zone:Array = GameDataManager.get_player_data(id)["out_of_game"]["attacks"]
		check(zone.size() == 2, "p%d initial zone contains exactly two cards" % id)
		check(EffectManager.manual_activations(id).size() == 2, "p%d startup exposes exactly two registered manual candidates" % id)
		for index in range(zone.size()):
			var card = zone[index]
			var label:String = "p%d clone%d" % [id, index]
			check(card is BaseCard and card.has_name("b06_initial_card"), label + " is the declared card")
			check(not cards.has(card) and not is_same(card, control), label + " has independent card identity")
			cards.append(card)
			var own:Array = candidates_for(card, id)
			check(own.size() == 1, label + " has exactly one registered candidate owned by its player")
			check(candidates_for(card, 1 - id).is_empty() and candidates_for(card, 2).is_empty(), label + " is absent from other players' candidates")
			if own.size() == 1:
				var effect:BaseEffect = own[0]
				check(not effects.has(effect), label + " has independent effect identity")
				check(EffectManager.effect_fact_actor_id(effect) == id, label + " public effect actor is its owner")
				effects.append(effect)
	check(cards.size() == 4 and effects.size() == 4, "all four startup clones are independently registered and owned")

	# 同一个真实克隆：只注销登记，不改卡、玩家、时点或断言谓词。
	if not effects.is_empty():
		var effect:BaseEffect = effects[0]
		var card = effect.get_from()
		EffectManager.unregister_effect(effect)
		check(candidates_for(card, 0).is_empty(), "unregister same clone removes its public manual candidate")
		check((GameDataManager.get_player_data(0)["out_of_game"]["attacks"] as Array).has(card), "unregister leaves the same card in its startup zone")
		EffectManager.register_effect(effect, 0)
		check(candidates_for(card, 0).size() == 1, "register same clone restores its public manual candidate")

	# 每张牌实际询问并发动，效果默认玩家参数必须解析到登记玩家。
	for effect:BaseEffect in effects:
		open_window()
		var id:int = EffectManager.effect_fact_actor_id(effect)
		var other_id:int = 1 - id
		var before = GameDataManager.get_player_data(id)["magic"].number
		var other_before = GameDataManager.get_player_data(other_id)["magic"].number
		var label:String = "activation%d owner%d" % [effects.find(effect), id]
		check(EffectManager.request_manual_activation(effect, id), label + " is accepted by the real activation gate")
		check(is_same(EffectManager.get_pending_active_effect(), effect), label + " awaits choice for the exact cloned effect")
		check(EffectManager.submit_active_choice(effect, true), label + " submits the real choice")
		check(GameDataManager.get_player_data(id)["magic"].number == before + 1, label + " grants one magic to its owner")
		check(GameDataManager.get_player_data(other_id)["magic"].number == other_before, label + " leaves the other player's magic unchanged")
	check(GameDataManager.get_player_data(0)["magic"].number == 2 and GameDataManager.get_player_data(1)["magic"].number == 2, "all cloned effects settle on their two distinct owners")
	check(GameDataManager.get_player_data(2)["magic"].number == 0 and candidates_for(control, 2).is_empty(), "unregistered control still has neither candidate nor resource effect")
	finish()

func finish() -> void:
	print("RESULT b06_initial_card_registration_probe checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
