extends Node

var checks:int = 0
var failures:Array = []
var cards := DebugCardAdapter.new()
var board := DebugBoardAdapter.new()

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func begin(label:StringName) -> SessionContext:
	var generation:Dictionary = SessionGeneration.begin_generation(label)
	return SessionGeneration.derive_context(generation.token, label).context

func bound_origin(object, origin:StringName) -> bool:
	var found:Dictionary = SessionGeneration.origin_of(object)
	return found.ok and found.context.origin() == origin

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	print("ENV user=", OS.get_user_data_dir())
	for key in ["TMPDIR", "TEMP", "TMP", "APPDATA", "LOCALAPPDATA"]:
		check(OS.get_environment(key).begins_with("E:"), "environment_" + key)
	EffectManager.reset_runtime()
	GameData.player_data_library.clear()
	GameData.player_data_library[710] = {"out_of_game":{"reserve":[]}, "hand_cards":[], "self_effects":[], "played_cards":[], "power":BaseNumber.new(0)}
	var source:SessionContext = begin(&"D0.fixture")
	var event := BaseEvent.new("D0-event", "")
	var child := BaseAttack.new("D0-child", "", [])
	var effect := BaseEffect.new("D0-effect", [])
	var op := preload("res://scripts/system/operations/EditScore.gd").new()
	effect._funcs = [BaseFunc.new(Callable(op, "exec"), [0, BaseNumber.new(0)])]
	event._attached_cards = [child]
	event._effects = [effect]
	LoadEvent.events = [event]
	LoadSituation.situations = []
	LoadSituation.climax_situations = {}
	var objects_before:int = GameData.objects.size()
	var effects_before:int = GameData.effects.size()
	check(is_same(cards.find_card_template(event._name), event), "card_query_identity")
	check(cards.is_template(event), "card_query_template_membership")
	check(SessionGeneration.origin_of(event).reason == &"unbound_origin" and SessionGeneration.origin_of(child).reason == &"unbound_origin", "card_queries_do_not_bind")
	check(GameData.objects.size() == objects_before and GameData.effects.size() == effects_before, "card_queries_do_not_register")
	var result:Dictionary = cards.add_clone(710, event._name, "out_of_game.reserve")
	check(result.ok and result.changed, "card_new_action_template_success")
	var zone:Array = cards.zone_by_path(710, "out_of_game.reserve")
	var clone = zone.back() if not zone.is_empty() else null
	check(clone is BaseEvent and not is_same(clone, event), "card_runtime_fresh_identity")
	check(bound_origin(clone, &"DebugCardAdapter.add_clone"), "card_explicit_action_origin")
	check(clone != null and SessionGeneration.origin_of(clone._attached_cards[0]).ok, "card_attached_origin")
	check(clone != null and clone._effects[0].runtime_source_status().ok and clone._effects[0]._funcs[0].runtime_source_status().ok, "card_effect_func_origin")
	check(SessionGeneration.origin_of(event).reason == &"unbound_origin" and SessionGeneration.origin_of(child).reason == &"unbound_origin" and effect.runtime_context() == null, "card_source_template_unchanged")
	result = cards.add_clone(710, event._name, "hand_cards")
	check(result.ok, "card_registered_zone_success")
	var hand:Array = cards.zone_by_path(710, "hand_cards")
	var registered = hand.back() if not hand.is_empty() else null
	check(registered != null and GameData.player_data_library[710].self_effects.has(registered._effects[0]) and EffectManager.effect_pool.has(registered._effects[0]), "card_registered_with_captured_action")
	check(registered != null and registered._effects[0]._trigger_player_id == 710 and is_same(registered._effects[0].from, registered), "card_registered_owner_identity")
	objects_before = GameData.objects.size()
	result = cards.add_clone(710, event._name, "nonexistent.zone")
	check(not result.ok and not result.changed and GameData.objects.size() == objects_before, "card_invalid_zone_no_allocation")
	objects_before = GameData.objects.size()
	var size_before:int = zone.size()
	result = cards.add_clone(710, "D0-not-loaded", "out_of_game.reserve")
	check(not result.ok and not result.changed and zone.size() == size_before and GameData.objects.size() == objects_before, "unknown_template_no_mutation")
	var runtime := BaseEvent.new("D0-runtime", "")
	check(SessionGeneration.bind_origin(runtime, source.token(), source.origin()).ok, "runtime_fixture_bound")
	LoadEvent.events.append(runtime)
	result = cards.add_clone(710, runtime._name, "out_of_game.reserve")
	check(result.ok, "card_runtime_pool_clone_success")
	check(result.ok and bound_origin(zone.back(), source.origin()) and bound_origin(runtime, source.origin()), "card_runtime_pool_inherits_not_resigns")
	var situation := BaseSituation.new("D0-situation", "")
	LoadSituation.situations = [situation]
	GameData.player_data_library.clear()
	MapData.active_situation = null
	MapData.situation_discard.clear()
	objects_before = GameData.objects.size()
	check(is_same(board._find_situation_template(situation._name), situation), "board_query_identity")
	check(SessionGeneration.origin_of(situation).reason == &"unbound_origin" and GameData.objects.size() == objects_before, "board_query_readonly")
	result = board.replace_situation(situation._name)
	check(result.ok and result.changed, "board_new_action_template_success")
	check(MapData.active_situation is BaseSituation and not is_same(MapData.active_situation, situation), "board_runtime_fresh_identity")
	check(bound_origin(MapData.active_situation, &"DebugBoardAdapter.replace_situation"), "board_explicit_action_origin")
	check(SessionGeneration.origin_of(situation).reason == &"unbound_origin", "board_template_unchanged")
	var active = MapData.active_situation
	var board_runtime := BaseSituation.new("D0-bound-situation", "")
	check(SessionGeneration.bind_origin(board_runtime, source.token(), source.origin()).ok, "board_runtime_fixture_bound")
	LoadSituation.climax_situations[999] = board_runtime
	result = board.replace_situation(str(board_runtime.get_instance_id()))
	check(result.ok and bound_origin(MapData.active_situation, source.origin()), "board_runtime_pool_inherits_not_resigns")
	check(not result.ok or MapData.situation_discard.has(active), "board_success_clears_after_clone")
	active = MapData.active_situation
	var next_source:SessionContext = begin(&"D0.next-session")
	check(SessionGeneration.validate_context(source).reason == &"stale_session", "old_fixture_context_stale")
	GameData.player_data_library[710] = {"out_of_game":{"reserve":[]}, "self_effects":[]}
	zone = cards.zone_by_path(710, "out_of_game.reserve")
	objects_before = GameData.objects.size()
	result = cards.add_clone(710, runtime._name, "out_of_game.reserve")
	check(not result.ok and not result.changed and zone.is_empty() and GameData.objects.size() == objects_before, "card_stale_pool_reject_no_publish")
	check(SessionGeneration.origin_of(runtime).reason == &"stale_session", "card_stale_pool_not_washed")
	var discarded_before:int = MapData.situation_discard.size()
	result = board.replace_situation(board_runtime._name)
	check(not result.ok and not result.changed, "board_stale_pool_reject")
	check(is_same(MapData.active_situation, active) and MapData.situation_discard.size() == discarded_before and GameData.objects.size() == objects_before, "board_reject_preserves_active")
	check(SessionGeneration.origin_of(board_runtime).reason == &"stale_session", "board_stale_pool_not_washed")
	event._attached_cards = [runtime]
	result = cards.add_clone(710, event._name, "out_of_game.reserve")
	check(not result.ok and zone.is_empty() and GameData.objects.size() == objects_before, "card_template_with_stale_child_reject")
	event._attached_cards = [child]
	situation._attached_cards = [runtime]
	result = board.replace_situation(situation._name)
	check(not result.ok and is_same(MapData.active_situation, active) and MapData.situation_discard.size() == discarded_before and GameData.objects.size() == objects_before, "board_template_with_stale_child_preserves_active")
	situation._attached_cards = []
	result = cards.add_clone(710, event._name, "out_of_game.reserve")
	check(result.ok and bound_origin(zone.back(), &"DebugCardAdapter.add_clone") and is_same(SessionGeneration.origin_of(zone.back()).context.token(), next_source.token()), "new_action_reused_adapter_new_session")
	SessionGeneration.invalidate_generation(&"D0.no-session")
	objects_before = GameData.objects.size()
	size_before = zone.size()
	result = cards.add_clone(710, event._name, "out_of_game.reserve")
	check(not result.ok and not result.changed and zone.size() == size_before and GameData.objects.size() == objects_before, "card_missing_action_source_reject")
	active = MapData.active_situation
	discarded_before = MapData.situation_discard.size()
	result = board.replace_situation(situation._name)
	check(not result.ok and not result.changed, "board_missing_action_source_reject")
	check(is_same(MapData.active_situation, active) and MapData.situation_discard.size() == discarded_before, "board_missing_source_preserves_active")
	print("RESULT ", JSON.stringify({"suite":"card_d0_template_action", "checks":checks, "failed":failures.size(), "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
