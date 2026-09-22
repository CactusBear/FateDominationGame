extends Node
# A09/A10/A11 are exercised through live GDScript rule entrances.
var failures:Array = []
var checks:int = 0
func check(ok:bool, label:String):
	checks += 1
	if !ok: failures.append(label)
	print("CHECK ", label, " ", ok)
func setup():
	EffectManager.reset_runtime()
	GameLog.reset()
	GameLog.set_context(1, "action")
	GameData.player_data_library.clear()
	for id in range(2):
		GameData.player_data_library[id] = GameData.new_player_data()
		var d:Dictionary = GameData.player_data_library[id]
		d.is_out = false
		d.order.number = id
		if d.has("buffs"): d.buffs.clear()
	GameProgress.is_game_over = false
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX])
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX], 0)
func named(pool:Array, key:String):
	for item in pool:
		if item != null and item._name == key: return item
	return null
func _ready(): call_deferred("run")
func run():
	test_cost_timing()
	test_cost_calculation_is_source_bound()
	test_regular_play_cost_timing()
	test_simultaneous_true_name_cost()
	test_current_true_name_history()
	test_first_master_history()
	test_false_servant_book_failed_then_eligible()
	var f = FileAccess.open("res://card_history_result.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures}))
	f.close()
	print("RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
func test_cost_timing():
	setup()
	var artoria = named(GameData.loaded_servants, "artoria_pendragon")
	var source = named(artoria._specials.get("SKILLS", []), "wind_barrier")
	var skill:BaseSkill = CloneObject.new().exec(source)
	var d:Dictionary = GameDataManager.get_player_data(0)
	d.magic.number = 2
	RegisterObjectEffects.new().exec(skill, 0)
	TimePointChecker.dynamic_time_point([TimePoints.CARD_COST_CALCULATED], 0, skill)
	TimePointChecker.dynamic_time_point([TimePoints.CARD_COST_CALCULATED], 0, skill)
	check(skill._cost.number == 2, "A09 repeated cost calculation keeps Wind Barrier at two")
	check(ReleaseTrueName.new().exec(0), "A09 true-name release succeeds")
	check(skill._cost.number == 4, "A09 true-name release restores Wind Barrier printed cost")
	check(HideTrueName.new().exec(0), "A09 true-name can be hidden for play fixture")
	d.magic.number = 2
	check(PlaySkill.new().exec(skill, 0, true), "A09 PlaySkill accepts after cost-calculation discount")
	check(d.magic.number == 0, "A09 deducted discounted cost in the same play")

func test_cost_calculation_is_source_bound():
	setup()
	var artoria = named(GameData.loaded_servants, "artoria_pendragon")
	var wind:BaseSkill = CloneObject.new().exec(named(artoria._specials.get("SKILLS", []), "wind_barrier"))
	var unrelated := BaseAttack.new("unrelated", "", [], BaseNumber.new(0), BaseNumber.new(0))
	RegisterObjectEffects.new().exec(wind, 0)
	TimePointChecker.dynamic_time_point([TimePoints.CARD_COST_CALCULATED], 0, unrelated)
	check(wind._cost.number == 4, "unrelated card cost calculation does not change Wind Barrier")
	var messages:String = "\n".join(EffectManager.pop_messages(0))
	check(not messages.contains("风王结界"), "unplayed Wind Barrier produces no unrelated effect prompt")
	TimePointChecker.dynamic_time_point([TimePoints.CARD_COST_CALCULATED], 0, wind)
	check(wind._cost.number == 2, "Wind Barrier still calculates its own hidden-name discount")
func test_regular_play_cost_timing():
	setup()
	var artoria = named(GameData.loaded_servants, "artoria_pendragon")
	var source = named(artoria._specials.get("SKILLS", []), "wind_barrier")
	var skill:BaseSkill = CloneObject.new().exec(source)
	var d:Dictionary = GameDataManager.get_player_data(0)
	d.magic.number = 4
	d.hand_cards = [skill, BaseAttack.new("regular_filler", "", [], BaseNumber.new(0), BaseNumber.new(0))]
	RegisterObjectEffects.new().exec(skill, 0)
	check(RegularPlay.add(0, skill, false), "A12 RegularPlay accepts after cost-calculation discount")
	check(d.magic.number == 2, "A12 RegularPlay deducts adjusted cost once")

func test_simultaneous_true_name_cost():
	setup()
	var artoria = named(GameData.loaded_servants, "artoria_pendragon")
	var wind:BaseSkill = CloneObject.new().exec(named(artoria._specials.get("SKILLS", []), "wind_barrier"))
	var release_card:BaseSkill = CloneObject.new().exec(named(artoria._specials.get("SKILLS", []), "excalibur"))
	var d:Dictionary = GameDataManager.get_player_data(0)
	d.magic.number = 12
	d.servant_skills = [wind, release_card]
	RegisterObjectEffects.new().exec(wind, 0)
	RegisterObjectEffects.new().exec(release_card, 0)
	TimePointChecker.dynamic_time_point([TimePoints.CARD_COST_CALCULATED], 0, wind)
	check(wind._cost.number == 2, "simultaneous fixture starts with hidden-name Wind Barrier discount")
	check(RegularPlay.submit_group(0, [wind, release_card], [false, false]),
		"Wind Barrier and true-name card submit as one group")
	check(ReleaseTrueName.is_released(0), "simultaneous true-name card releases before group settlement")
	check(wind._cost.number == 4 and d.magic.number == 0,
		"simultaneous release restores Wind Barrier cost before paying the group")

func test_current_true_name_history():
	setup()
	check(ReleaseTrueName.new().exec(0), "A10 first release")
	check(HideTrueName.new().exec(0), "A10 hide changes current state")
	check(!ReleaseTrueName.is_released(0), "A10 latest hide overrides historical release")
	check(ReleaseTrueName.new().exec(0), "A10 release again after hide")
	check(ReleaseTrueName.is_released(0), "A10 latest release restores current state")
func test_first_master_history():
	setup()
	var sakura_template = named(GameData.loaded_masters, "matou_sakura")
	var shinji_template = named(GameData.loaded_masters, "matou_shinji")
	var sakura:BaseMaster = CloneObject.new().exec(sakura_template)
	var d:Dictionary = GameDataManager.get_player_data(0)
	d.master = sakura
	d.buffs = sakura._specials.get("BUFFS", []).duplicate()
	var black_mud = named(sakura._specials.get("BUFFS", []), "black_mud")
	var effect = named(sakura._effects, "deficient_vessel_black_mud")
	GameLog.record("master_assigned", 0, -1, "", sakura, ["master_assigned"], {"effect_name":""})
	GameDataManager.get_player_data(0).score.number = 0
	GameDataManager.get_player_data(1).score.number = 1
	EffectManager.register_effect(effect, 0)
	TimePointChecker.global_time_point([TimePoints.DAY_END])
	check(black_mud._is_active, "A11 non-Shinji first master activates black mud")
	setup()
	sakura = CloneObject.new().exec(sakura_template)
	d = GameDataManager.get_player_data(0)
	d.master = sakura
	d.buffs = sakura._specials.get("BUFFS", []).duplicate()
	black_mud = named(sakura._specials.get("BUFFS", []), "black_mud")
	effect = named(sakura._effects, "deficient_vessel_black_mud")
	GameLog.record("master_assigned", 0, -1, "", shinji_template, ["master_assigned"], {"effect_name":""})
	GameLog.record("master_assigned", 0, -1, "", sakura, ["master_assigned"], {"effect_name":"false_servant_book_master_replace"})
	GameDataManager.get_player_data(0).score.number = 0
	GameDataManager.get_player_data(1).score.number = 1
	EffectManager.register_effect(effect, 0)
	TimePointChecker.global_time_point([TimePoints.DAY_END])
	check(!black_mud._is_active, "A11 Shinji first master blocks black mud after replacement")
func test_false_servant_book_failed_then_eligible():
	setup()
	var shinji:BaseMaster = CloneObject.new().exec(named(GameData.loaded_masters, "matou_shinji"))
	var d:Dictionary = GameDataManager.get_player_data(0)
	d.master = shinji
	var book = named(shinji._specials.get("BUFFS", []), "false_servant_book")
	var effect = named(book._effects, "false_servant_book_master_replace")
	d.buffs = [book]
	EffectManager.register_effect(effect, 0)
	TimePointChecker.global_time_point([TimePoints.DAY_END])
	check(!d.get("used_once_effects", []).has(effect._name), "A13 failed DAY_END does not consume false servant book")
	d.command_spell_count.number = 0
	TimePointChecker.global_time_point([TimePoints.DAY_END])
	check(d.master._name == "matou_sakura", "A13 later eligible DAY_END replaces master")
	check(d.get("used_once_effects", []).has(effect._name), "A13 successful replacement consumes false servant book")
