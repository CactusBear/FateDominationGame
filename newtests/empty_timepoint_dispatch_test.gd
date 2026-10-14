extends Node
const FixtureClone = preload("res://newtests/fixture_clone.gd")
# 本局原来源取自 reset_runtime 回执；夹具对 operation 显式传入，不从全局补票。
var ctx: SessionContext = null
func _reset_ctx() -> SessionContext:
	var reset: Dictionary = EffectManager.reset_runtime()
	return reset.get("context") if reset.get("ok", false) else null

# 空心时点补派发专项：只走正式效果池、时点检查器和回合推进器。
# 覆盖：美杜莎延迟 self_battle_phase_start、凛/葛木类 self_battle_phase_end
# （本测试用葛木真实效果），以及美狄亚 self_deploy；同时守住无 deploy 事实不误派。
var failures:Array = []
var checks:int = 0

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func _named(objects:Array, name:String):
	for object in objects:
		if object != null and object._name == name:
			return object
	return null

func _reset_fixture(player_count:int) -> void:
	ctx = _reset_ctx()
	GameLog.reset()
	GameData.effects.clear()
	GameData.player_data_library.clear()
	for area:BaseMapArea in MapData.areas:
		for location:BaseLocation in area._locations:
			(location._players as Array).clear()
	MapData.active_situation = null
	for id in range(player_count):
		var data:Dictionary = GameData.new_player_data()
		data["is_out"] = false
		data["order"] = BaseNumber.new(id)
		GameData.player_data_library[id] = data
	GameProgress.reset_progress()
	GameProgress.current_round = 1
	GameLog.set_context(1, "")

func _battle_area() -> BaseMapArea:
	for area:BaseMapArea in MapData.areas:
		if area._score_need_win and area._locations.size() >= 2:
			return area
	return null

func _place(player_id:int, location:BaseLocation) -> bool:
	return bool(SetLocation.new().exec(location, player_id, false, true, true, ctx))

func _has_time_point_fact(player_id:int, point:String) -> bool:
	for entry:Dictionary in GameLog.query({"type":"time_point", "actor":player_id}, null, -1):
		if (entry.get("tags", []) as Array).has(point):
			return true
	return false

func _effect(card, effect_name:String) -> BaseEffect:
	for effect:BaseEffect in card._effects:
		if effect._name == effect_name:
			return effect
	return null

func _medusa_battle_start_case() -> void:
	_reset_fixture(2)
	var area:BaseMapArea = _battle_area()
	check(area != null, "Medusa case has a battle area")
	if area == null:
		return
	var medusa = _named(GameData.loaded_servants, "medusa")
	check(medusa != null, "Medusa template is loaded")
	if medusa == null:
		return
	var medusa_skill = FixtureClone.clone_template(medusa._specials["SKILLS"][2], ctx)
	medusa_skill._is_activating = true
	GameData.player_data_library[0]["servant"] = medusa
	GameData.player_data_library[0]["servant_skills"] = [medusa_skill]
	RegisterObjectEffects.new().exec(medusa_skill, 0, ctx)
	check(_place(0, area._locations[0]), "Medusa is placed")
	check(_place(1, area._locations[1]), "opponent is placed")
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	GameLog.set_context(1, "action")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX])
	var medusa_effect:BaseEffect = _effect(medusa_skill, "petrification_defeat_if_no_magic_attack")
	check(medusa_effect != null, "Medusa carries the real petrification effect")
	if medusa_effect == null:
		return
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE], 0, null, ctx)
	check(EffectManager.get_pending_active_effect() == medusa_effect, "Medusa action effect reaches the real activation gate")
	if EffectManager.get_pending_active_effect() == medusa_effect:
		check(EffectManager.submit_active_choice(medusa_effect, true), "Medusa action effect is activated")
	check(EffectManager.has_player_time_point_listener(TimePoints.BATTLE_PHASE_START), "delayed self_battle_phase_start is registered")
	GameProgress.current_phase_index = 3
	GameProgress.current_phase_player_index = 0
	GameProgress.current_player_id = -1
	GameLog.set_context(1, "battle")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE, TimePoints.NON_CLIMAX])
	GameProgress.next_player_in_phase()
	check(_has_time_point_fact(0, TimePoints.BATTLE_PHASE_START), "self_battle_phase_start is really dispatched")
	check(DefeatBuff.is_defeated(1), "Medusa delayed effect really defeats the opponent")

func _battle_end_case() -> void:
	_reset_fixture(1)
	var kuzuki = _named(GameData.loaded_masters, "kuzuki_souichirou")
	check(kuzuki != null, "Kuzuki template is loaded")
	if kuzuki == null:
		return
	GameData.player_data_library[0]["master"] = kuzuki
	MasterManager.bind_master_effects(0)
	var effect:BaseEffect = null
	for candidate:BaseEffect in GameData.player_data_library[0]["self_effects"]:
		if candidate._name == "outsider_battle_phase_score_gain":
			effect = candidate
			break
	check(effect != null, "Kuzuki carries the real self_battle_phase_end effect")
	check(EffectManager.has_player_time_point_listener(TimePoints.BATTLE_PHASE_END), "self_battle_phase_end listener is registered")
	var workshop:BaseMapArea = MapData.magic_workshop
	check(workshop != null and not workshop._locations.is_empty(), "magic workshop exists")
	if effect == null or workshop == null or workshop._locations.is_empty():
		return
	check(_place(0, workshop._locations[0]), "Kuzuki is placed in the workshop")
	GameProgress.current_phase_index = 3
	GameProgress.current_phase_player_index = 0
	GameProgress.current_player_id = -1
	GameProgress.has_battle_resolved = false
	GameProgress.battle_broadcast_requires_confirm = false
	GameLog.set_context(1, "battle")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE, TimePoints.NON_CLIMAX])
	var score_before:int = GameData.player_data_library[0]["score"].number
	GameProgress.end_phase()
	check(_has_time_point_fact(0, TimePoints.BATTLE_PHASE_END), "self_battle_phase_end is really dispatched")
	check(GameData.player_data_library[0]["score"].number == score_before + 2, "Kuzuki end-phase effect really grants workshop score")

func _rin_battle_end_case() -> void:
	_reset_fixture(1)
	var rin = _named(GameData.loaded_masters, "tohsaka_rin")
	check(rin != null, "Rin template is loaded")
	if rin == null:
		return
	GameData.player_data_library[0]["master"] = rin
	GameData.player_data_library[0]["magic"].set_num(BaseNumber.new(10))
	MasterManager.bind_master_effects(0)
	check(EffectManager.has_player_time_point_listener(TimePoints.BATTLE_PHASE_END), "Rin self_battle_phase_end listener is registered")
	GameLog.record("magic_add", 0, -1, "", null, ["command_spell_gain_magic"], {"delta": 5})
	GameProgress.current_phase_index = 3
	GameProgress.current_phase_player_index = 0
	GameProgress.current_player_id = -1
	GameProgress.has_battle_resolved = false
	GameLog.set_context(1, "battle")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE, TimePoints.NON_CLIMAX])
	GameProgress.end_phase()
	check(_has_time_point_fact(0, TimePoints.BATTLE_PHASE_END), "Rin self_battle_phase_end is really dispatched")
	check(GameData.player_data_library[0]["magic"].number == 6, "Rin end-phase effect really removes four magic")


func _deploy_case() -> void:
	_reset_fixture(1)
	var medea = _named(GameData.loaded_servants, "medea")
	check(medea != null, "Medea template is loaded")
	if medea == null:
		return
	var skill = FixtureClone.clone_template(medea._specials["SKILLS"][0], ctx)
	skill._is_activating = true
	GameData.player_data_library[0]["servant"] = medea
	GameData.player_data_library[0]["servant_skills"] = [skill]
	RegisterObjectEffects.new().exec(skill, 0, ctx)
	var workshop:BaseMapArea = MapData.magic_workshop
	check(workshop != null and not workshop._locations.is_empty(), "Medea case has a workshop")
	if workshop == null or workshop._locations.is_empty():
		return
	GameProgress.current_phase_index = 1
	#next_player_in_phase 的游标指向下一位；唯一玩家已开始行动，故下一位为 1。
	GameProgress.current_phase_player_index = 1
	GameProgress.current_player_id = 0
	GameLog.set_context(1, "outpost")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.OUTPOST_PHASE, TimePoints.NON_CLIMAX])
	var magic_before:int = GameData.player_data_library[0]["magic"].number
	var score_before:int = GameData.player_data_library[0]["score"].number
	check(DeployRules.deploy_to_area(workshop, 0) != null, "real deploy succeeds")
	var after_deploy_magic:int = GameData.player_data_library[0]["magic"].number
	var after_deploy_score:int = GameData.player_data_library[0]["score"].number
	check(not _has_time_point_fact(0, TimePoints.DEPLOY), "deploy is not emitted before action completion")
	check(GameProgress.end_current_player_action(), "action completion accepts the successful deploy")
	check(_has_time_point_fact(0, TimePoints.DEPLOY), "self_deploy is really dispatched")
	check(GameData.player_data_library[0]["magic"].number == after_deploy_magic + 1, "Medea deploy effect grants one magic")
	check(GameData.player_data_library[0]["score"].number == after_deploy_score + 2, "Medea deploy effect grants two score")
	check(after_deploy_magic >= magic_before and after_deploy_score == score_before, "base deploy only changes its declared resource before self_deploy")
	#保留同一成功部署事实及去重账本，只复位公开行动游标和阶段窗口。
	#两次都让唯一玩家完成前哨阶段并进入行动阶段，不能靠被拒绝/续行短路证明去重。
	var deploy_round:int = GameProgress.current_round
	check(GameProgress.current_phase_index == 2 and GameProgress.current_player_id == 0, "first deploy completion really finishes the outpost phase")
	var deploy_facts_before:int = 0
	for entry:Dictionary in GameLog.query({"type":"time_point", "actor":0, "round":deploy_round}, null, -1):
		if (entry.get("tags", []) as Array).has(TimePoints.DEPLOY):
			deploy_facts_before += 1
	check(deploy_facts_before == 1, "first completion records exactly one DEPLOY time-point fact")
	GameProgress.current_phase_index = 1
	GameProgress.current_phase_player_index = 1
	GameProgress.current_player_id = 0
	GameLog.set_context(deploy_round, "outpost")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.OUTPOST_PHASE, TimePoints.NON_CLIMAX])
	var magic_after:int = GameData.player_data_library[0]["magic"].number
	check(GameProgress.end_current_player_action(), "same player's same-round action completion is accepted again")
	check(GameProgress.current_round == deploy_round and GameProgress.current_phase_index == 2 and GameProgress.current_player_id == 0, "second completion really finishes the same-round outpost phase again")
	var deploy_facts_after:int = 0
	for entry:Dictionary in GameLog.query({"type":"time_point", "actor":0, "round":deploy_round}, null, -1):
		if (entry.get("tags", []) as Array).has(TimePoints.DEPLOY):
			deploy_facts_after += 1
	print("DEPLOY_FACTS round=", deploy_round, " actor=0 before=", deploy_facts_before, " after=", deploy_facts_after)
	check(deploy_facts_after == 1, "same player's same-round DEPLOY time-point fact is recorded exactly once")
	check(GameData.player_data_library[0]["magic"].number == magic_after, "the same deploy fact is not dispatched twice")

func run() -> void:
	_medusa_battle_start_case()
	_battle_end_case()
	_rin_battle_end_case()
	_deploy_case()
	print("RESULT empty_timepoint_dispatch checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
