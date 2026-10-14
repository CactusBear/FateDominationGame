extends Node

var checks:int = 0
var failures:Array = []

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func source_context(label:StringName) -> SessionContext:
	var generation:Dictionary = SessionGeneration.begin_generation(label)
	if not generation.ok:
		return null
	return SessionGeneration.derive_context(generation.token, label).context

func effect_data() -> Array:
	return [{
		"effect_name":"card_l0_effect",
		"time_points":[],
		"priority":0,
		"is_pure_passive":false,
		"is_residue":false,
		"effect_numbers":[],
		"funcs":[{"func_name":"do_nothing", "parameters":[]}]
	}]

func event_data() -> Dictionary:
	return {
		"card_name":"l0_event",
		"card_img":"event.png",
		"score":{"number":1, "can_change":true, "is_pure_number":true},
		"effects":effect_data()
	}

func situation_data() -> Dictionary:
	return {
		"card_name":"l0_situation",
		"card_img":"situation.png",
		"magic":{"number":1, "can_change":true, "is_pure_number":true},
		"effects":effect_data()
	}

func attack_data() -> Dictionary:
	return {
		"attack_name":"l0_attack",
		"attack_card_img":"attack.png",
		"attributes":["strength"],
		"cost":{"number":1, "can_change":true, "is_pure_number":true},
		"power":{"number":2, "can_change":true, "is_pure_number":true},
		"effects":effect_data(),
		"_dir_path":"res://"
	}

func skill_data() -> Dictionary:
	return {
		"skill_name":"l0_skill",
		"skill_card_img":"skill.png",
		"attributes":[],
		"cost":{"number":1, "can_change":true, "is_pure_number":true},
		"power":{"number":0, "can_change":true, "is_pure_number":true},
		"ignore_limit":false,
		"effects":effect_data()
	}

func other_data() -> Dictionary:
	return {
		"thing_name":"l0_thing",
		"card_img":"thing.png",
		"effects":effect_data()
	}

func command_data() -> Dictionary:
	return {
		"card_name":"l0_command_spell",
		"effects":effect_data()
	}

func assert_runtime_card(card, label:String, context:SessionContext) -> void:
	check(card != null, label + "_exists")
	if card == null:
		return
	var card_origin:Dictionary = SessionGeneration.origin_of(card)
	check(card_origin.ok and is_same(card_origin.context.token(), context.token()), label + "_card_origin")
	check(card._effects.size() == 1, label + "_effects_count")
	if card._effects.is_empty():
		return
	var effect:BaseEffect = card._effects[0]
	var effect_origin:Dictionary = effect.runtime_source_status()
	check(effect_origin.ok and is_same(effect.runtime_context().token(), context.token()), label + "_effect_origin")
	check(is_same(effect.from, card), label + "_effect_owner")
	check(effect._funcs.size() == 1, label + "_func_count")
	if effect._funcs.size() == 1:
		var func_data:BaseFunc = effect._funcs[0]
		var func_origin:Dictionary = func_data.runtime_source_status()
		check(func_origin.ok and func_data.runtime_context() != null and is_same(func_data.runtime_context().token(), context.token()), label + "_func_origin")

func run() -> void:
	var context:SessionContext = source_context(&"card_l0.test")
	check(context != null, "source_context")
	if context == null:
		_finish()
		return

	check(LoadEvent.events.size() > 0, "formal_event_templates_loaded")
	check(LoadSituation.situations.size() > 0, "formal_situation_templates_loaded")
	check(LoadCommandSpell.command_spells.size() > 0, "formal_command_templates_loaded")
	check(LoadAttack._attack_datas.size() > 0, "formal_attack_data_loaded")
	if not LoadEvent.events.is_empty():
		check(SessionGeneration.origin_of(LoadEvent.events[0]).reason == &"unbound_origin", "formal_event_template_unbound")
		if not LoadEvent.events[0]._effects.is_empty():
			check(LoadEvent.events[0]._effects[0].runtime_context() == null, "formal_event_effect_unbound")
	if not LoadSituation.situations.is_empty():
		check(SessionGeneration.origin_of(LoadSituation.situations[0]).reason == &"unbound_origin", "formal_situation_template_unbound")
	if not LoadCommandSpell.command_spells.is_empty():
		var command_template:BaseCard = LoadCommandSpell.command_spells.values()[0]
		check(SessionGeneration.origin_of(command_template).reason == &"unbound_origin", "formal_command_template_unbound")

	var template_event:BaseEvent = LoadEvent.build_event(event_data(), "res://", null)
	check(template_event != null, "event_template_exists")
	if template_event != null:
		check(SessionGeneration.origin_of(template_event).reason == &"unbound_origin", "event_template_unbound")
		check(template_event._effects[0].runtime_context() == null, "template_effect_unbound")
		check(template_event._effects[0]._funcs[0].runtime_context() == null, "template_func_unbound")

	assert_runtime_card(LoadEvent.build_event(event_data(), "res://", context), "event_runtime", context)
	assert_runtime_card(LoadSituation.build_situation(situation_data(), "res://", context), "situation_runtime", context)
	assert_runtime_card(LoadCommandSpell.build_command_spell(command_data(), "res://", context), "command_runtime", context)

	var owner := BaseCard.new()
	var skills:Array = LoadGame.load_skills([skill_data()], "res://", owner, "skill", context)
	check(skills.size() == 1, "load_game_skill_count")
	if skills.size() == 1:
		assert_runtime_card(skills[0], "load_game_skill", context)
	var attacks:Array = LoadGame.load_attacks([attack_data()], "res://", owner, [], context)
	check(attacks.size() == 1, "load_game_attack_count")
	if attacks.size() == 1:
		assert_runtime_card(attacks[0], "load_game_attack", context)
	var things:Array = LoadGame.load_other_master_things([other_data()], "res://", owner, context)
	check(things.size() == 1, "load_game_thing_count")
	if things.size() == 1:
		assert_runtime_card(things[0], "load_game_thing", context)
	var events:Array = LoadGame.load_events([event_data()], "res://", owner, context)
	check(events.size() == 1, "load_game_event_count")
	if events.size() == 1:
		assert_runtime_card(events[0], "load_game_event", context)

	LoadAttack._attack_datas = [attack_data()]
	var resolved:BaseAttack = LoadAttack.resolve("special:l0_attack", context)
	assert_runtime_card(resolved, "string_attack_resolve", context)

	var unbound := SessionContext.new()
	check(LoadEvent.build_event(event_data(), "res://", unbound) == null, "unbound_context_rejected")
	var old_context:SessionContext = context
	var next:SessionContext = source_context(&"card_l0.next")
	check(LoadEvent.build_event(event_data(), "res://", old_context) == null, "expired_context_rejected")
	check(LoadAttack.resolve("special:l0_attack", old_context) == null, "expired_string_attack_rejected")
	check(SessionGeneration.origin_of(template_event).reason == &"unbound_origin", "template_stays_unbound")
	_finish()

func _finish() -> void:
	print("RESULT ", JSON.stringify({"suite":"card_l0_loader_origin", "checks":checks, "failed":failures.size(), "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _ready() -> void:
	call_deferred("run")
