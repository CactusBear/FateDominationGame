extends "res://tests/post_battle_choice_test.gd"
# 只观察原套件的真实边界，不新增规则回调或替代后半场景。
func _check_wait_boundary(event:BaseEvent, label:String) -> void:
	super._check_wait_boundary(event, label)
	if not label.ends_with(": after settlement"):
		return
	var calls:Array = []
	for entry in GameLog.all_func_calls():
		if entry.get("func_name") == "queue_optional_effect_for_players":
			calls.append(entry)
	var choices:Array = []
	for effect in GameData.effects:
		if effect is BaseEffect and effect._name == CHOICE_NAME:
			var status:Dictionary = effect.runtime_source_status()
			choices.append({"id":effect.get_instance_id(),"winner":effect._trigger_player_id,
				"options":effect._options.size(),"runtime_source":status,
				"can_register":EffectManager.can_register_effect(effect,effect._trigger_player_id),
				"in_pool":EffectManager.effect_pool.has(effect)})
	print("OBSERVATION ", JSON.stringify({"label":label,"original_context_valid":SessionGeneration.validate_context(fixture_context).ok,
		"calls":calls,"choices":choices,"phase":GameProgress.get_current_phase(),
		"round":GameProgress.current_round,"waiting":EffectManager.is_waiting_for_choice(),
		"event_source":SessionGeneration.origin_of(event),"event_on_board":MapData.miyama._events.has(event)}))
