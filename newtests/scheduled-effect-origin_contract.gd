extends "res://tests/command_spell_test.gd"

func run() -> void:
	Observer.reset()
	_setup()
	_test_delayed_battle_reward()
	_setup()
	_test_delayed_reward_expires()
	_setup()
	_test_once_and_owners()
	_setup()
	_test_independent_owners()
	_setup()
	_test_no_frame()
	_setup()
	_test_factory_branches()
	_setup()
	_test_old_root()
	Observer.finish(get_tree())

func _scheduled() -> Array:
	return EffectManager.effect_pool.filter(func(e): return e is BaseEffect and e._name == "scheduled_effect")

func _test_once_and_owners() -> void:
	var first := _command_effect()
	check(first != null and _choose(first, 1), "real command root schedules reward")
	var before:int = GameDataManager.get_player_data(0).score.number
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], 1, null, fixture_context)
	check(GameDataManager.get_player_data(0).score.number == before, "different player cannot claim original reward")
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], 0, null, fixture_context)
	check(GameDataManager.get_player_data(0).score.number == before + 2, "original player receives reward")
	check(_scheduled().is_empty(), "trigger removes one-shot delayed effect")
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], 0, null, fixture_context)
	check(GameDataManager.get_player_data(0).score.number == before + 2, "repeat timepoint does not replay reward")

func _test_independent_owners() -> void:
	var first := _command_effect()
	check(first != null and _choose(first, 1), "first owner accepts real command")
	var second:BaseEffect = null
	for template in LoadCommandSpell.command_spells.values():
		if template != null and template._name == "normal_command_spell":
			var card = _runtime_template(template)
			keepalive.append(card)
			second = card._effects[0]
			break
	check(second != null and EffectManager.register_effect(second, 1), "second owner uses independent trusted card instance")
	GameProgress.current_player_id = 1
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX], 1, null, fixture_context)
	check(second != null and EffectManager.request_manual_activation(second, 1) and EffectManager.submit_option_choice(second, [1]), "second owner accepts real command")
	var scheduled:Array = _scheduled()
	check(scheduled.size() == 2 and not is_same(scheduled[0], scheduled[1]), "two owners retain independent delayed identities")
	# 从来源活表移除原牌/原效果，延迟已承接的能力不靠新来源卡补票。
	EffectManager.unregister_effect(first)
	if first.from is WeakRef:
		var card = first.from.get_ref()
		if card != null:
			card.del()
	elif first.from is BaseObject:
		first.from.del()
	var before0:int = GameDataManager.get_player_data(0).score.number
	var before1:int = GameDataManager.get_player_data(1).score.number
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], 0, null, fixture_context)
	check(GameDataManager.get_player_data(0).score.number == before0 + 2 and GameDataManager.get_player_data(1).score.number == before1, "removed source does not redirect original owner reward")
	check(_scheduled().size() == 1, "one owner trigger leaves the other delayed effect intact")
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], 1, null, fixture_context)
	check(GameDataManager.get_player_data(1).score.number == before1 + 2 and _scheduled().is_empty(), "second owner independently receives exactly one reward")

func _test_no_frame() -> void:
	var source := _command_effect()
	var effects:int = GameData.effects.size()
	var objects:int = GameData.objects.size()
	# 仅 activating_eff 不能签发帧；此负例故意赋值，正例均走真实 pipeline。
	EffectManager.activating_eff = source
	check(ScheduleEffectOnTimePoint.new().exec(["probe"], []) == null, "missing validated frame refuses creation")
	check(GameData.effects.size() == effects and GameData.objects.size() == objects and _scheduled().is_empty(), "missing frame leaves zero success objects")
	EffectManager.activating_eff = null

func _root() -> BaseEffect:
	var produced:Array = LoadHelper.load_effects([{
		"effect_name":"scheduled_origin_root", "time_points":[], "priority":0,
		"is_pure_passive":true, "is_residue":false, "effect_numbers":[], "funcs":[]
	}], null, fixture_context)
	check(produced.size() == 1, "root uses trusted runtime effect factory")
	if produced.size() != 1:
		return null
	var root:BaseEffect = produced[0]
	root._shown_name = "原延迟来源"
	root._using_numbers = [BaseNumber.new(7)]
	root.numbers = [BaseNumber.new(9)]
	check(EffectManager.register_effect(root, 0), "root registration succeeds")
	return root

func _execute_schedule(root:BaseEffect, body:Array) -> void:
	root.tags = body
	root._funcs = LoadHelper.load_funcs([
		{"func_name":"get_activating_eff", "parameters":[], "var_index":0},
		{"func_name":"get_property", "parameters":[{"self_var":0}, "tags"], "var_index":1},
		{"func_name":"schedule_effect_on_time_point", "parameters":[["origin_probe"], {"self_var":1}, 3, true, ["origin_expire"]], "var_index":2}
	], root, fixture_context)
	check(root._funcs.size() == 3, "root loads registered scheduling function")
	TimePointChecker.global_time_point(["origin_root_tick"], null, fixture_context)
	EffectManager.add_to_activation_pool(root)
	EffectManager.run_pipeline()

func _test_factory_branches() -> void:
	var root := _root()
	var dictionary:Dictionary = {"func_name":"edit_score", "parameters":[null, {"number_index":0}, -1], "var_index":-1}
	_execute_schedule(root, [dictionary])
	var delayed:BaseEffect = root._self_vars[2] if root._self_vars.size() > 2 else null
	check(delayed != null and EffectManager.effect_pool.has(delayed), "Dictionary branch publishes registered effect")
	if delayed != null:
		check(delayed.runtime_source_status().ok, "created effect keeps validated origin")
		check(delayed._funcs.size() == 1 and delayed._funcs[0].runtime_source_status(delayed, fixture_context).ok, "Dictionary function inherits original context")
		check(is_same(delayed._using_numbers, root._using_numbers) and is_same(delayed.numbers, root.numbers), "complete loader numeric environment preserves both arrays")
		check(delayed._priority == 3 and delayed._time_points_require_all and delayed._expire_time_points == ["origin_expire"] and delayed._remove_after_trigger, "generic priority require-all expiry one-shot declarations survive")
		EffectManager.unregister_effect(delayed)
	var funcs:Array = LoadHelper.load_funcs([dictionary], root, fixture_context)
	_execute_schedule(root, funcs)
	delayed = root._self_vars[2] if root._self_vars.size() > 2 else null
	check(delayed != null and EffectManager.effect_pool.has(delayed), "BaseFunc branch publishes registered effect")
	if delayed != null:
		check(delayed._funcs.size() == 1 and not is_same(delayed._funcs[0], funcs[0]) and delayed._funcs[0].runtime_source_status(delayed, fixture_context).ok, "public clone preserves runtime function origin and fresh identity")
		EffectManager.unregister_effect(delayed)
	var effects:int = GameData.effects.size()
	var objects:int = GameData.objects.size()
	_execute_schedule(root, [{"func_name":"unregistered_scheduled_origin_probe", "parameters":[]}])
	check(root._self_vars.size() > 2 and root._self_vars[2] == null, "Dictionary parse rejection returns no usable effect")
	check(GameData.effects.size() == effects and GameData.objects.size() == objects and _scheduled().is_empty(), "Dictionary rejection leaves no unpublished effect")
	var unbound := BaseFunc.new(Callable(), [])
	_execute_schedule(root, [unbound])
	check(root._self_vars.size() > 2 and root._self_vars[2] == null, "unbound BaseFunc source is refused")
	check(GameData.effects.size() == effects and GameData.objects.size() == objects and _scheduled().is_empty(), "BaseFunc rejection leaves no unpublished effect")
	# 保存真实旧来源函数，再重置代际，不能将旧 runtime 当模板补票。
	var old:BaseFunc = funcs[0]
	_setup()
	root = _root()
	effects = GameData.effects.size()
	objects = GameData.objects.size()
	_execute_schedule(root, [old])
	check(root._self_vars.size() > 2 and root._self_vars[2] == null, "stale BaseFunc origin is refused in a current real frame")
	check(GameData.effects.size() == effects and GameData.objects.size() == objects and _scheduled().is_empty(), "stale function rejection leaves no unpublished effect")

func _test_old_root() -> void:
	var old := _command_effect()
	_setup()
	var effects:int = GameData.effects.size()
	var objects:int = GameData.objects.size()
	check(not _choose(old, 1), "old command root cannot schedule into new generation")
	check(GameData.effects.size() == effects and GameData.objects.size() == objects and _scheduled().is_empty(), "old root leaves zero success objects")
