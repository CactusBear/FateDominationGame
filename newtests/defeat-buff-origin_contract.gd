extends "res://tests/card_effect_runtime_test.gd"

func lose_count(id:int) -> int:
	return GameLog.query({"type":"time_point", "actor":id, "tags":[TimePoints.BATTLE_LOSE]}, null).size()

func installed(buff:DefeatBuff, id:int) -> bool:
	if buff == null or not SessionGeneration.origin_of(buff).get("ok", false): return false
	var data:Dictionary = GameDataManager.find_player_data(id)
	if data.is_empty() or data.buffs.count(buff) != 1 or buff._effects.size() != 2: return false
	var origin:SessionContext = SessionGeneration.origin_of(buff).context
	if not is_same(origin.token(),fixture_context.token()) or origin.origin() != fixture_context.origin(): return false
	for effect:BaseEffect in buff._effects:
		if not effect.runtime_source_status().ok or not is_same(effect.from,buff): return false
		if not is_same(effect.runtime_context().token(),fixture_context.token()) or effect.runtime_context().origin() != fixture_context.origin(): return false
		if effect._trigger_player_id != id or not EffectManager.can_register_effect(effect,id): return false
		if EffectManager.effect_pool.count(effect) != 1 or data.self_effects.count(effect) != 1 or GameData.effects.count(effect) != 1 or GameData.objects.count(effect) != 1: return false
	return GameData.objects.count(buff) == 1

func gone(buff:DefeatBuff, data:Dictionary) -> bool:
	if buff == null or data.buffs.has(buff) or GameData.objects.has(buff): return false
	for effect:BaseEffect in buff._effects:
		if GameData.objects.has(effect) or GameData.effects.has(effect) or EffectManager.effect_pool.has(effect) or data.self_effects.has(effect): return false
	return true

func call_defeat(parameters:Array) -> Dictionary:
	var operation:Dictionary = GameProgress.start_progress_operation("defeat",parameters,fixture_context)
	check(operation.get("ok",false), "defeat root accepts arity %d" % parameters.size())
	var receipt:Dictionary = await GameProgress.wait_progress_operation(operation,false)
	check(receipt.get("ok",false) and receipt.get("completed",false), "defeat root completes arity %d" % parameters.size())
	return receipt

func stack_remove() -> void:
	setup(3)
	GameData.player_id = 0
	var receipt:Dictionary = await call_defeat([])
	check(receipt.get("value") == true and DefeatBuff.get_defeat_count(0) == 1, "zero-argument Defeat installs local layer")
	receipt = await call_defeat([1])
	check(receipt.get("value") == true and DefeatBuff.get_defeat_count(1) == 1, "one-argument Defeat installs target layer")
	var data:Dictionary = GameDataManager.find_player_data(1)
	var a:DefeatBuff = data.buffs[0] if data.buffs.size() == 1 else null
	check(installed(a,1), "defeat graph original source owner each registration exactly once")
	await call_defeat([1])
	var b:DefeatBuff = data.buffs[1] if data.buffs.size() == 2 else null
	check(a != null and b != null and not is_same(a,b) and DefeatBuff.get_defeat_count(1) == 2, "two actual defeats stack distinct layers")
	check(installed(b,1), "second layer owns distinct legal builtin graph")
	check(not data.get("is_battle_lose",false) and not data.get("is_battle_win",false), "special defeat never writes battle flags")
	check(lose_count(1) == 2, "each installed defeat emits one lose fact")
	var attack:BaseAttack = LoadAttack.resolve("agility:2",fixture_context)
	data.hand_cards.append(attack)
	var played:Dictionary = await GameProgress.wait_progress_operation(GameProgress.start_progress_operation("play_attack",[attack,1],fixture_context),false)
	check(played.get("value") == false and data.hand_cards.has(attack) and data.played_cards.is_empty(), "defeated target cannot play real hand card")
	check(not DefeatBuff.remove(1) and installed(a,1) and DefeatBuff.get_defeat_count(1) == 2, "missing remove context keeps complete graph")
	var removed:Dictionary = await GameProgress.wait_progress_operation(GameProgress.start_progress_operation("remove_defeat",[1],fixture_context),false)
	check(removed.get("value") == true and DefeatBuff.get_defeat_count(1) == 0, "real RemoveDefeat removes all target layers")
	check(gone(a,data) and gone(b,data), "successful removal deletes original child graphs")
	check(DefeatBuff.get_defeat_count(0) == 1, "single-target removal preserves other target")
	var c:DefeatBuff = DefeatBuff.apply(2,fixture_context)
	var local:DefeatBuff = GameDataManager.find_player_data(0).buffs[0] if DefeatBuff.get_defeat_count(0) == 1 else null
	check(installed(c,2), "explicit original-source apply installs graph")
	check(DefeatBuff.clear_all(), "no-frame clear consumes installed original sources")
	check(gone(local,GameDataManager.find_player_data(0)) and gone(c,GameDataManager.find_player_data(2)), "multi-target clear deletes each graph")

func refusal() -> void:
	setup(2)
	var objects:Array = GameData.objects.duplicate(); var effects:Array = GameData.effects.duplicate()
	check(DefeatBuff.apply(1) == null and not Defeat.new().exec(1), "missing source refuses rather than returning uninstalled buff")
	check(GameData.objects == objects and GameData.effects == effects and lose_count(1) == 0, "missing source no graph or fake lose residue")
	var unsigned := SessionContext.new()
	check(DefeatBuff.create_runtime(unsigned) == null and DefeatBuff.apply(1,unsigned) == null and not Defeat.new().exec(1,unsigned), "unsigned source rejected before graph creation")
	check(GameData.objects == objects and GameData.effects == effects and lose_count(1) == 0, "unsigned source no residue")
	check(DefeatBuff.apply(902711,fixture_context) == null and not Defeat.new().exec(902711,fixture_context), "unknown target refused before creation")
	check(GameDataManager.find_player_data(902711).is_empty() and GameData.objects == objects and GameData.effects == effects, "unknown target no member or graph creation")
	var template := DefeatBuff.new()
	check(not SessionGeneration.origin_of(template).ok and template._effects.size() == 2, "legacy new remains unbound template")
	check(not template._effects[0].runtime_source_status().ok and not template._effects[1].runtime_source_status().ok and is_same(template._effects[0].from,template), "template children preserve ownership without tickets")
	check(not ManageBuff.new().exec(template,1,true,fixture_context), "consumer refuses template without reticketing")
	for effect:BaseEffect in template._effects: effect.del()
	template.del()
	check(GameData.objects == objects and GameData.effects == effects, "template cleanup returns exact object arrays")
	var old:SessionContext = fixture_context
	setup(2)
	objects = GameData.objects.duplicate(); effects = GameData.effects.duplicate()
	check(DefeatBuff.create_runtime(old) == null and DefeatBuff.apply(1,old) == null and not Defeat.new().exec(1,old), "expired source rejected in same-ID next session")
	check(GameData.objects == objects and GameData.effects == effects and lose_count(1) == 0, "expired source no new residue")
	var original:Dictionary = GameDataManager.find_player_data(1)
	var buff:DefeatBuff = DefeatBuff.apply(1,fixture_context)
	check(installed(buff,1), "replacement precondition real original installation")
	var replacement:Dictionary = GameData.new_player_data()
	replacement.is_out = false; replacement.buffs = original.buffs
	GameData.player_data_library[1] = replacement
	objects = GameData.objects.duplicate(); effects = GameData.effects.duplicate()
	check(not DefeatBuff.remove(1,fixture_context) and not DefeatBuff.clear_all(), "same-ID replacement refuses original registration owner")
	check(GameData.objects == objects and GameData.effects == effects and replacement.buffs.has(buff) and original.self_effects.has(buff._effects[0]), "replacement rejection no half-delete or new graph")
	GameData.player_data_library[1] = original
	check(DefeatBuff.remove(1,fixture_context) and gone(buff,original), "restored exact original owner positive removal")

func cancellation() -> void:
	setup(2)
	var d:Dictionary = {"effect_name":"before_defeat_cancel","time_points":[TimePoints.BEFORE_DEFEAT],"priority":0,"is_pure_passive":true,"is_residue":false,"need_activate":false,"effect_numbers":[],"funcs":[{"func_name":"cancel_pending_action","parameters":[]}]}
	var loaded:Array = LoadHelper.load_effects([d],null,fixture_context)
	check(loaded.size() == 1 and EffectManager.register_effect(loaded[0],1), "real BEFORE_DEFEAT canceller source registered")
	var before:Array = GameData.objects.duplicate()
	var receipt:Dictionary = await call_defeat([1])
	check(receipt.get("value") == false and DefeatBuff.get_defeat_count(1) == 0 and lose_count(1) == 0, "BEFORE cancellation installs nothing emits no lose")
	var residue:bool = false
	for object in GameData.objects:
		if not before.has(object) and (object is DefeatBuff or object is CannotPlayCardsEffect or object is ExcludedFromBattleWinEffect): residue = true
	check(not residue, "cancelled defeat leaves no builtin graph residue")

func registration_failure() -> void:
	setup(2)
	var objects:Array = GameData.objects.duplicate(); var effects:Array = GameData.effects.duplicate()
	MatchJournal.audit_error = "defeat registration refusal diagnostic"
	var accepted:bool = Defeat.new().exec(1,fixture_context)
	MatchJournal.audit_error = ""
	check(not accepted and DefeatBuff.get_defeat_count(1) == 0, "registration refusal never reports installed defeat")
	check(GameData.objects == objects and GameData.effects == effects and GameDataManager.find_player_data(1).self_effects.is_empty(), "unpublished refused graph fully discarded")
	check(lose_count(1) == 0, "registration failure never emits fake BATTLE_LOSE")
	setup(2)
	check(Defeat.new().exec(1,fixture_context) and DefeatBuff.get_defeat_count(1) == 1, "registration restored legal positive control")
	check(DefeatBuff.clear_all(), "registration positive cleanup")

func active_child_registration_failure() -> void:
	setup(2)
	var path:String = OS.get_user_data_dir().path_join("defeat-origin-child-refusal-%d.log" % OS.get_process_id())
	var writer = MatchJournal.begin_audit(path)
	check(writer != null, "actual file-backed child audit writer")
	if writer == null: return
	# header + start + first builtin child; second child hits the real capacity gate.
	writer.max_records = 3
	var operation:Dictionary = GameProgress.start_progress_operation("defeat",[1],fixture_context)
	check(operation.get("ok",false), "actual defeat root accepted before child audit refusal")
	check(EffectManager.runtime_guard_status().paused and not MatchJournal.audit_error.is_empty(), "second builtin actual audit refusal preserves native guard boundary")
	check(DefeatBuff.get_defeat_count(1) == 0 and lose_count(1) == 0, "paused native registration never installs defeat or fake lose")
	var residue:bool = false
	for effect in GameData.effects:
		if effect is CannotPlayCardsEffect or effect is ExcludedFromBattleWinEffect:
			if effect.runtime_source_status().ok: residue = true
	check(not residue and GameDataManager.find_player_data(1).self_effects.is_empty(), "failed second-child registration leaves no new runtime builtin graph")
	print("NATIVE_DEFEAT_BOUNDARY ", EffectManager.runtime_guard_status())
	MatchJournal.end_audit(writer)
	setup(2)

func round_tail() -> void:
	var reset:Dictionary = GameData.reset_game_session([0,1])
	check(reset.get("ok",false), "round tail public session reset")
	fixture_context = reset.context
	check(GameProgress.reset_progress(false,fixture_context).get("ok",false), "round tail preserves original progress source")
	for id in [0,1]: GameDataManager.find_player_data(id).is_out = false
	GameProgress.current_round = 1
	var a:DefeatBuff = DefeatBuff.apply(0,fixture_context); var b:DefeatBuff = DefeatBuff.apply(1,fixture_context)
	check(installed(a,0) and installed(b,1), "round tail actual multi-target installed graphs")
	var ad:Dictionary = GameDataManager.find_player_data(0); var bd:Dictionary = GameDataManager.find_player_data(1)
	await GameProgress.end_round(fixture_context)
	check(gone(a,ad) and gone(b,bd), "actual GameProgress ROUND tail removes graphs without function frame")
	check(GameLog.query({"type":"time_point","actor":-1,"tags":[TimePoints.DAY_END]},null).size() == 1, "actual round end time point reached")

func run() -> void:
	await stack_remove()
	refusal()
	await cancellation()
	registration_failure()
	await test_pierce_heart_defeat()
	await test_rule_breaker()
	await round_tail()
	print("RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
