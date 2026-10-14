extends "res://tests/command_spell_test.gd"

var observed_effect:BaseEffect = null

func _command_effect() -> BaseEffect:
	observed_effect = super._command_effect()
	return observed_effect

func _choose(effect:BaseEffect, option_index:int) -> bool:
	var accepted:bool = super._choose(effect, option_index)
	_observe("choice-" + str(option_index), effect)
	return accepted

func _test_delayed_battle_reward() -> void:
	super._test_delayed_battle_reward()
	_observe("delayed-reward", observed_effect)
	for effect in GameData.effects:
		if effect is BaseEffect and effect._name == "scheduled_effect":
			print("ORIGIN_OBSERVATION ", JSON.stringify({"label":"scheduled-created", "id":effect.get_instance_id(),
				"source":effect.runtime_source_status(), "in_pool":EffectManager.effect_pool.has(effect),
				"func_sources":_func_sources(effect._funcs)}))

func _test_waiting_preserves_following_timepoint() -> void:
	super._test_waiting_preserves_following_timepoint()
	_observe("fifo-after", observed_effect)
	for effect in EffectManager.effect_pool:
		if effect is BaseEffect and effect._name.begins_with("queued_day_"):
			print("ORIGIN_OBSERVATION ", JSON.stringify({"label":"fifo-sentinel", "name":effect._name,
				"source":effect.runtime_source_status(), "func_sources":_func_sources(effect._funcs)}))

func _test_free_targeted_move() -> void:
	super._test_free_targeted_move()
	_observe("move-after", observed_effect)

func _test_move_tip_and_announcement() -> void:
	await super._test_move_tip_and_announcement()
	_observe("move-ui-after", observed_effect)

func _func_sources(funcs:Array) -> Array:
	var sources:Array = []
	for function in funcs:
		sources.append({"name":function._name, "context_valid":SessionGeneration.validate_context(function.runtime_context()).ok,
			"capability":function.execution_capability_status()})
	return sources

func _observe(label:String, effect:BaseEffect) -> void:
	var data:Dictionary = GameDataManager.find_player_data(0)
	print("ORIGIN_OBSERVATION ", JSON.stringify({"label":label, "context":SessionGeneration.validate_context(fixture_context),
		"source":effect.runtime_source_status() if effect != null else {}, "in_pool":EffectManager.effect_pool.has(effect),
		"pending_location":EffectManager.get_pending_location_selection(), "target_limit":MapData.magic_workshop0._pl_num_limit, "target_is_current":SetLocation.current_map_location(MapData.magic_workshop0), "target_area":MapData.magic_workshop0.get_from()._area_name, "waiting_location":EffectManager.waiting_location == effect,
		"waiting_effect":EffectManager.waiting_effect == effect, "frame":EffectManager.execution_context(),
		"can_pay":EffectManager.can_pay_effect_cost(effect) if effect != null else false,
		"calls":GameLog.all_func_calls(), "location":data.get("location"), "spells":data.command_spell_count.number,
		"audit_error":MatchJournal.audit_error, "guard":EffectManager.runtime_guard_status()}))
