extends Node

const Sessions = preload("res://scripts/system/session_generation.gd")
var checks:int = 0
var failures:Array = []

func check(label:String, ok:bool) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func fresh(clear:bool = true) -> SessionContext:
	var generation:Dictionary = Sessions.begin_generation(&"em13.fixture")
	var context:SessionContext = Sessions.derive_context(generation.token, &"em13.fixture").context
	if clear:
		check("same domain fixture cleanup", EffectManager.clear_runtime_in_context(context).ok)
	return context

func descriptor(points:Array = [], funcs:Array = []) -> Dictionary:
	return {"effect_name":"em13_same_id", "time_points":points, "priority":0,
		"is_pure_passive":true, "is_residue":false, "effect_numbers":[], "funcs":funcs}

func runtime(context:SessionContext, points:Array = [], funcs:Array = [], numbers:Array = []) -> BaseEffect:
	var spec:Dictionary = descriptor(points, funcs)
	spec.effect_numbers = numbers
	var effects:Array = LoadHelper.load_effects([spec], null, context)
	check("trusted factory produces bound effect", effects.size() == 1)
	return effects[0] if not effects.is_empty() else null

func snapshot() -> Dictionary:
	var players:Dictionary = {}
	for id in GameData.player_data_library:
		var data:Dictionary = GameData.player_data_library[id]
		players[id] = {"score":data.score.number, "magic":data.magic.number, "power":data.power.number,
			"self_effects":data.self_effects.duplicate(), "current":data.current_time_points.duplicate(), "dynamic":data.dynamic_time_points.duplicate()}
	return {"pool":EffectManager.effect_pool.duplicate(), "decision":EffectManager.decision_queue.duplicate(),
		"activation":EffectManager.activation_pool.duplicate(), "resolved":EffectManager.resolved_effects.duplicate(),
		"matched":EffectManager.matched_time_points.duplicate(true), "closed":EffectManager.closed_time_points.duplicate(true),
		"logs":GameLog.query({}, null).duplicate(true), "messages":EffectManager.messages.duplicate(true),
		"results":EffectManager.effect_results.duplicate(true), "announcements":EffectManager.pending_announcements_snapshot(),
		"transaction":EffectManager.capture_transaction_state(), "serial":EffectManager.latest_allocated_message_serial(),
		"members":GameData.player_data_library.keys(), "token":Sessions.current_token().token, "players":players, "guard":EffectManager.runtime_guard_status()}

func preflight_case() -> void:
	var old:BaseEffect = runtime(fresh())
	old._trigger_player_id = 0
	var current:SessionContext = fresh()
	var before:Dictionary = snapshot()
	check("preflight alone rejects never registered old source", not EffectManager.can_register_effect(old, 0) and snapshot() == before)
	var good:BaseEffect = runtime(current)
	check("preflight alone accepts new same id source", EffectManager.can_register_effect(good, 0))

func registration_case() -> void:
	var old_context:SessionContext = fresh()
	var old:BaseEffect = runtime(old_context)
	old._trigger_player_id = 0
	var current:SessionContext = fresh()
	var before:Dictionary = snapshot()
	check("old never-registered source preflight rejects", not EffectManager.can_register_effect(old, 0))
	check("old never-registered source registration rejects", not EffectManager.register_effect(old, 0))
	check("old registration first side effect blocked", snapshot() == before and not old.has_meta(&"effect_registration_subject"))
	var template:BaseEffect = LoadHelper.load_effects([descriptor()], null)[0]
	check("template is not runtime qualification", not EffectManager.register_effect(template, 0) and template.runtime_context() == null and not Sessions.origin_of(template).ok)
	var good:BaseEffect = runtime(current)
	before = snapshot()
	check("mixed batch preflights before first owner write", not EffectManager.register_effects([good, old], 0) and snapshot() == before and GameData.player_data_library[0].self_effects.is_empty())
	var loaded:Array = GameData.effects
	GameData.effects = [good, old, template]
	EffectManager.sync_loaded_effect_pool()
	check("loaded pool is not a provenance credential", snapshot() == before)
	GameData.effects = loaded
	check("same id new runtime registration positive", EffectManager.register_effect(good, 0) and EffectManager.can_register_effect(good, 0))
	check("different owner stays rejected", not EffectManager.register_effect(good, 1))
	var data:Dictionary = GameData.player_data_library[0]
	GameData.player_data_library[0] = GameData.new_player_data()
	check("same session member replacement rejected", not EffectManager.can_register_effect(good, 0))
	GameData.player_data_library[0] = data
	EffectManager.unregister_effect(good)
	EffectManager.unregister_effect(good)
	check("legal unregister idempotent", not EffectManager.effect_pool.has(good) and not data.self_effects.has(good))

func matching_case() -> void:
	var context:SessionContext = fresh()
	var old:BaseEffect = runtime(context, ["em13_point"])
	old._trigger_player_id = 0
	GameData.player_data_library[0].current_time_points = ["em13_point"]
	check("matching current source positive", EffectManager.get_matched_time_points(old) == ["em13_point"])
	fresh()
	var before:Dictionary = snapshot()
	check("matching stale source rejected", EffectManager.get_matched_time_points(old).is_empty() and snapshot() == before)
	context = fresh()
	var missing:BaseEffect = runtime(context, ["em13_point"])
	missing._trigger_player_id = 0
	var data:Dictionary = GameData.player_data_library[0]
	GameData.player_data_library.erase(0)
	before = snapshot()
	check("matching removed member never creates", EffectManager.get_matched_time_points(missing).is_empty() and snapshot() == before)
	EffectManager.effect_pool.append(missing)
	missing._expire_time_points = ["em13_expire"]
	before = snapshot()
	EffectManager.collect_current_effects()
	check("collection removed member never creates or registers facts", snapshot() == before)
	EffectManager.effect_pool.erase(missing)
	before = snapshot()
	EffectManager.close_time_point("em13_point", 0)
	check("close unknown member never creates or closes", snapshot() == before)
	GameData.player_data_library[0] = data

func activate_case() -> void:
	var old:BaseEffect = runtime(fresh())
	old._trigger_player_id = 0
	old._self_vars = ["old-self-var"]
	fresh()
	var before:Dictionary = snapshot()
	EffectManager.activate_effect(old)
	check("direct stale activation rejects before variables logs guard facts", snapshot() == before and old._self_vars == ["old-self-var"])
	var current:BaseEffect = runtime(Sessions.derive_context(Sessions.current_token().token, &"em13.current").context)
	current._trigger_player_id = 0
	EffectManager.activate_effect(current)
	check("same id current direct activation positive", GameLog.query({}, null).any(func(record): return record.get("object") == current and record.get("type") == "effect"))

func pool_case() -> void:
	var old:BaseEffect = runtime(fresh())
	old._trigger_player_id = 0
	fresh()
	var before:Dictionary = snapshot()
	EffectManager.add_to_activation_pool(old)
	check("direct stale pool rejects before pool or guard registration", snapshot() == before)
	var current:BaseEffect = runtime(Sessions.derive_context(Sessions.current_token().token, &"em13.pool").context)
	current._trigger_player_id = 0
	EffectManager.add_to_activation_pool(current)
	check("same id current pool positive", EffectManager.activation_pool.has(current))

func resolve_case() -> void:
	var old:BaseEffect = runtime(fresh())
	old._trigger_player_id = 0
	fresh()
	# Public pool is intentionally the direct-consumer boundary: bypass add_to_activation_pool only.
	EffectManager.activation_pool.append(old)
	var before:Dictionary = snapshot()
	EffectManager.resolve_one()
	check("direct stale resolution rejects before dequeue resolved marker guard", snapshot() == before)
	EffectManager.activation_pool.clear()
	var current:BaseEffect = runtime(Sessions.derive_context(Sessions.current_token().token, &"em13.resolve").context)
	current._trigger_player_id = 0
	EffectManager.add_to_activation_pool(current)
	EffectManager.resolve_one()
	check("same id current resolve positive", EffectManager.activation_pool.is_empty() and GameLog.query({}, null).any(func(record): return record.get("object") == current and record.get("type") == "effect"))

func pipeline_case() -> void:
	var old:BaseEffect = runtime(fresh())
	old._trigger_player_id = 0
	fresh()
	check("pipeline budget fixture enabled", EffectManager.configure_runtime_guard({"enabled":true, "steps":0, "seconds":0.0}))
	var prime:BaseEffect = runtime(Sessions.derive_context(Sessions.current_token().token, &"em13.prime").context, [], [{"func_name":"do_nothing", "parameters":[]}])
	prime._trigger_player_id = 0
	EffectManager.activate_effect(prime)
	check("pipeline budget fixture has real completed step", EffectManager.runtime_guard_status().completed == 1 and not EffectManager.runtime_guard_status().paused)
	EffectManager.decision_queue.append(old)
	var before:Dictionary = snapshot()
	EffectManager.run_pipeline()
	check("direct stale pipeline rejects before queue running budget facts", snapshot() == before and not EffectManager.is_running)
	EffectManager.decision_queue.clear()
	var context:SessionContext = Sessions.derive_context(Sessions.current_token().token, &"em13.pipeline").context
	var current:BaseEffect = runtime(context)
	check("pipeline positive registers", EffectManager.register_effect(current, 0))
	EffectManager.decision_queue.append(current)
	EffectManager.run_pipeline()
	check("same id current pipeline positive", EffectManager.resolved_effects.has(current) and EffectManager.activation_pool.is_empty() and EffectManager.decision_queue.is_empty() and not EffectManager.is_running)
	check("pipeline budget fixture disabled", EffectManager.configure_runtime_guard({"enabled":false, "steps":0, "seconds":0.0}))

func cleanup_case() -> void:
	var old:BaseEffect = runtime(fresh())
	check("old cleanup fixture registers", EffectManager.register_effect(old, 0))
	var old_data:Dictionary = GameData.player_data_library[0]
	# Replace the member through its public library, retaining the precise previous owner.
	GameData.player_data_library[0] = GameData.new_player_data()
	var context:SessionContext = fresh(false)
	var current:BaseEffect = runtime(context)
	check("new owner same id registers", EffectManager.register_effect(current, 0))
	EffectManager.unregister_effect(old)
	check("old unregister clears only exact old owner", not old_data.self_effects.has(old) and GameData.player_data_library[0].self_effects.has(current) and EffectManager.effect_pool.has(current))
	EffectManager.unregister_effect(old)
	check("old unregister idempotent keeps new owner", GameData.player_data_library[0].self_effects == [current])
	old._trigger_player_id = 999999
	var before:Dictionary = snapshot()
	EffectManager.unregister_effect(old)
	check("unregister unknown member does not create", snapshot() == before)
	EffectManager.clear_runtime_in_context(context)

func close_case() -> void:
	var old:BaseEffect = runtime(fresh())
	old._trigger_player_id = 0
	fresh()
	GameData.player_data_library[0].current_time_points = ["em13_point"]
	EffectManager.activating_eff = old
	var before:Dictionary = snapshot()
	EffectManager.close_time_point("em13_point", 0)
	check("stale activating source cannot close new time point", snapshot() == before and GameData.player_data_library[0].current_time_points == ["em13_point"])
	EffectManager.activating_eff = null
	EffectManager.close_time_point("em13_point", 0)
	check("declared direct close without effect positive", EffectManager.is_time_point_closed("em13_point", 0) and GameData.player_data_library[0].current_time_points.is_empty())

func guard_case() -> void:
	var context:SessionContext = fresh()
	check("guard enabled", EffectManager.configure_runtime_guard({"enabled":true, "steps":0, "seconds":0.0}))
	var current:BaseEffect = runtime(context)
	current._trigger_player_id = 0
	EffectManager.activate_effect(current)
	check("current checkpoint receives original source", not EffectManager.runtime_guard_status().paused and GameLog.query({}, null).any(func(record): return record.get("object") == current and record.get("type") == "effect"))
	check("guard disabled", EffectManager.configure_runtime_guard({"enabled":false, "steps":0, "seconds":0.0}))

func others_case() -> void:
	var original:SessionContext = fresh()
	var funcs:Array = [{"func_name":"emit_time_point", "parameters":["em13_signal", 0]}]
	var old:BaseEffect = runtime(original, [], funcs)
	check("old emitter registered in original domain", EffectManager.register_effect(old, 0))
	var current:SessionContext = fresh()
	var observer:BaseEffect = runtime(current, ["others_em13_signal"], [{"func_name":"edit_score", "parameters":[null, {"number_index":0}, 1]}], [{"number":1, "can_change":true, "is_pure_number":true}])
	check("real others observer registered", EffectManager.register_effect(observer, 1))
	var before:Dictionary = snapshot()
	EffectManager.activate_effect(old)
	check("stale emitter cannot dispatch or reward real other member", snapshot() == before)
	EffectManager.add_to_activation_pool(old)
	check("old registered emitter cannot repool", snapshot() == before)
	check("old registered emitter cannot re-register", not EffectManager.register_effect(old, 0) and snapshot() == before)
	var clone:BaseEffect = CloneObject.new().exec(old)
	check("old runtime clone retains source and cannot wash registration", clone.runtime_context() == old.runtime_context() and not EffectManager.register_effect(clone, 0) and snapshot() == before)
	var good:BaseEffect = runtime(current, [], funcs)
	check("same id new emitter registers", EffectManager.register_effect(good, 0))
	var score = GameData.player_data_library[1].score
	var initial = score.number
	EffectManager.activate_effect(good)
	check("same id current emitter reaches real others observer", score.number == initial + 1 and GameLog.query({}, null).any(func(record): return record.get("object") == observer and record.get("type") == "effect"))

func collection_case() -> void:
	var old:BaseEffect = runtime(fresh(), ["em13_point"])
	old._expire_time_points = ["em13_point"]
	old._trigger_player_id = 0
	fresh()
	GameData.player_data_library[0].current_time_points = ["em13_point"]
	EffectManager.effect_pool.append(old)
	var before:Dictionary = snapshot()
	EffectManager.collect_current_effects()
	check("collection stale candidate rejects before phase trigger or queue", snapshot() == before)
	EffectManager.effect_pool.erase(old)
	EffectManager.decision_queue.append(old)
	before = snapshot()
	EffectManager.drain_decision_queue()
	check("direct stale decision drain preserves queue", snapshot() == before)
	EffectManager.decision_queue.clear()
	var current:BaseEffect = runtime(Sessions.derive_context(Sessions.current_token().token, &"em13.collect").context, ["em13_point"])
	check("current collection candidate registers", EffectManager.register_effect(current, 0))
	EffectManager.collect_current_effects()
	check("same id current collection matches and queues", EffectManager.decision_queue == [current] and EffectManager.matched_time_points.get(current) == ["em13_point"])

func _ready() -> void:
	print("PATH_PROOF ", JSON.stringify({"pid":OS.get_process_id(), "user":OS.get_user_data_dir(), "env": [OS.get_environment("TMPDIR"), OS.get_environment("TEMP"), OS.get_environment("TMP"), OS.get_environment("APPDATA"), OS.get_environment("LOCALAPPDATA")]}))
	var mode:String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "all"
	if mode in ["preflight", "all"]: preflight_case()
	if mode in ["registration", "all"]: registration_case()
	if mode in ["matching", "all"]: matching_case()
	if mode in ["activate", "all"]: activate_case()
	if mode in ["pool", "all"]: pool_case()
	if mode in ["resolve", "all"]: resolve_case()
	if mode in ["pipeline", "all"]: pipeline_case()
	if mode in ["cleanup", "all"]: cleanup_case()
	if mode in ["close", "all"]: close_case()
	if mode in ["guard", "all"]: guard_case()
	if mode in ["others", "all"]: others_case()
	if mode in ["collection", "all"]: collection_case()
	print("RESULT ", JSON.stringify({"suite":"effect_registration_origin", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
