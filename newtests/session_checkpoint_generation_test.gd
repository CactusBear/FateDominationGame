extends Node

const Checkpoint = preload("res://scripts/match/rule_checkpoint.gd")
const State = preload("res://scripts/match/rule_state.gd")
const Ids = preload("res://scripts/match/net_ids.gd")
const Generation = preload("res://scripts/system/session_generation.gd")
const Context = preload("res://scripts/system/session_context.gd")
const Token = preload("res://scripts/system/session_token.gd")
var checks:int = 0
var failures:Array = []

class RuleObject extends RefCounted:
	signal observed
	static var writes:int = 0
	var score:int = 4:
		set(value):
			writes += 1
			score = value
	var direct:Variant
	var indirect:Variant
	var callback:Callable
	var items:Array = []
	var rng:RandomNumberGenerator = RandomNumberGenerator.new()
	func accept(_token, _context):
		return score

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func capture_with(cp, roots:Array, context) -> bool:
	# Original implementation is exercised without inventing a missing API.
	for method in cp.get_method_list():
		if method.name == &"capture" and method.args.size() >= 3:
			return cp.capture(roots, {}, context)
	return cp.capture(roots)

func project(ids, roots:Dictionary, graph:bool = true) -> Dictionary:
	var projector = State.new()
	if projector.has_method("project"):
		return projector.call("project", ids, roots, graph)
	return ids.snapshot_graph(roots) if graph else ids.snapshot(roots)

func graph_for(token, context) -> Dictionary:
	var object = RuleObject.new()
	object.direct = context
	object.indirect = weakref(token)
	object.callback = object.accept.bind(token, context)
	object.items = [context, token, weakref(context)]
	object.rng.seed = 41
	var typed:Array[Token] = [token]
	return {"rule":object, "token":token, "context":context, "typed":typed, "service":Generation.new()}

func _ready() -> void:
	await get_tree().process_frame
	var handle_noise:Array = []
	if OS.get_cmdline_user_args().has("handle_noise"):
		for i in range(13): handle_noise.append(Token.new())
	var first:Dictionary = Generation.begin_generation(&"checkpoint_probe")
	var subject = RuleObject.new()
	var bound:Dictionary = Generation.bind_origin(subject, first.token, &"probe.root")
	check(first.ok and bound.ok, "trusted_context_created")
	var context = bound.context
	var decoy = Context.new(first.token, &"opaque.initial")
	var graph:Dictionary = graph_for(first.token, decoy)
	var rule = graph.rule
	var listener = RuleObject.new()
	var signal_callback:Callable = listener.accept.bind(first.token, decoy)
	rule.observed.connect(signal_callback)
	var cp = Checkpoint.new()
	check(capture_with(cp, [graph], context), "capture_real_indirect_graph")
	check(not cp._objects.has(first.token), "token_leaf_not_object_record")
	check(not cp._objects.has(decoy), "context_leaf_not_object_record")
	check(not cp._objects.has(graph.service), "service_metadata_outside_graph")
	var original_items:Array = rule.items
	var original_rng:int = rule.rng.state
	rule.score = 19
	rule.items.append(93)
	rule.rng.randi()
	rule.observed.disconnect(signal_callback)
	listener.score = 22
	# This unissued shape is data, not authority. Restore must never rewrite it.
	decoy._source_origin = &"opaque.changed"
	check(cp.restore(), "same_generation_rollback_allowed")
	check(rule.score == 4 and is_same(rule.items, original_items) and rule.items.size() == 3, "rollback_values_and_collection_identity")
	check(rule.rng.state == original_rng, "rollback_declared_rng")
	check(rule.observed.is_connected(signal_callback) and listener.score == 4, "signal_callable_bound_handles_and_target_rollback")
	check(decoy.origin() == &"opaque.changed", "context_internals_never_restored")
	check(Generation.validate_context(context).ok and Generation.validate_token(first.token).ok, "rollback_preserves_current_eligibility")
	check(rule.callback.call() == 4 and is_same(rule.callback.get_bound_arguments()[0], first.token), "real_callable_preserves_bound_handle")
	check(is_same(rule.indirect.get_ref(), first.token), "real_weakref_preserves_handle")
	var second:Dictionary = Generation.begin_generation(&"probe_new_generation")
	rule.score = 71
	rule.items.append(44)
	rule.rng.randi()
	var before_rng:int = rule.rng.state
	var before_writes:int = RuleObject.writes
	check(not cp.restore(), "new_generation_old_checkpoint_rejected")
	check(rule.score == 71 and rule.items.size() == 4 and rule.rng.state == before_rng and RuleObject.writes == before_writes, "cross_generation_zero_rule_rng_setter_writes")
	check(is_same(Generation.current_token().token, second.token), "restore_cannot_revive_old_current")
	check(not Generation.origin_of(subject).ok, "restore_cannot_erase_old_origin_binding")
	var absent = Checkpoint.new()
	check(not capture_with(absent, [graph], null), "missing_capture_context_fail_closed")
	var stale = Checkpoint.new()
	check(not capture_with(stale, [graph], context), "stale_capture_context_fail_closed")
	Generation.invalidate_generation(&"probe_close")
	before_writes = RuleObject.writes
	check(not cp.restore() and RuleObject.writes == before_writes, "closed_generation_rejects_without_writes")
	var third:Dictionary = Generation.begin_generation(&"projection_a")
	var context_a = Generation.derive_context(third.token, &"projection.root").context
	var graph_a:Dictionary = graph_for(third.token, context_a)
	var ids = Ids.new()
	# Preexisting process-local handle IDs must not influence rule projection.
	ids.id_for(Token.new())
	ids.id_for(third.token)
	ids.id_for(context_a)
	var size_before:int = ids._objects.size()
	var projected_a:Dictionary = project(ids, {"token":third.token, "context":context_a})
	check(ids._objects.size() == size_before and ids.error.is_empty(), "projection_does_not_allocate_handle_ids")
	var fourth:Dictionary = Generation.begin_generation(&"projection_b")
	var context_b = Generation.derive_context(fourth.token, &"projection.root").context
	var projected_b:Dictionary = project(Ids.new(), {"token":fourth.token, "context":context_b})
	check(var_to_bytes(projected_a) == var_to_bytes(projected_b), "different_process_handle_history_same_projection")
	var other_context = Generation.derive_context(fourth.token, &"projection.other").context
	check(var_to_bytes(projected_b) != var_to_bytes(project(Ids.new(), {"token":fourth.token, "context":other_context})), "declared_origin_remains_in_projection")
	check(var_to_bytes(project(Ids.new(), {"a":fourth.token, "b":fourth.token})) != var_to_bytes(project(Ids.new(), {"a":fourth.token, "b":Token.new()})), "handle_alias_relation_remains_in_projection")
	var fields:Array = []
	var full:Dictionary = project(Ids.new(), graph_a)
	for definition in full.objects: fields.append(definition.script)
	check(not fields.has("res://scripts/system/session_token.gd") and not fields.has("res://scripts/system/session_context.gd") and not fields.has("res://scripts/system/session_generation.gd"), "projection_indirect_handles_and_service_are_leaves")
	var stable:Dictionary = graph_for(fourth.token, context_b)
	var baseline:Dictionary = project(Ids.new(), stable)
	check(var_to_bytes(baseline) == var_to_bytes(project(Ids.new(), stable)), "same_graph_projection_recomputes")
	stable.rule.score += 1
	check(var_to_bytes(baseline) != var_to_bytes(project(Ids.new(), stable)), "business_state_changes_projection")
	check(var_to_bytes(project(Ids.new(), {"token":third.token, "context":context_a}, false)) == var_to_bytes(project(Ids.new(), {"token":fourth.token, "context":context_b}, false)), "replay_snapshot_uses_same_handle_projection")
	var passive:Dictionary = State.capture_passive({}, {"max_capture_collections":-1})
	check(passive.status == "unknown" and not passive.error.is_empty(), "ra00_invalid_budget_unknown_preserved")
	var projection:Dictionary = project(ids, {"token":fourth.token, "context":context_b, "callback":stable.rule.accept.bind(fourth.token, context_b), "weak":weakref(context_b)})
	# Cross-process comparison excludes ordinary business IDs intentionally seeded above.
	var process_projection:Dictionary = project(Ids.new(), {"token":fourth.token, "context":context_b, "weak":weakref(context_b)})
	print("PROCESS_PROJECTION ", var_to_bytes(process_projection).hex_encode())
	print("PROCESS_HANDLE ", fourth.token.get_instance_id())
	print("USER_PATH ", OS.get_user_data_dir())
	var graph_hash = HashingContext.new()
	graph_hash.start(HashingContext.HASH_SHA256)
	var process_graph:Dictionary = graph_for(fourth.token, context_b)
	graph_hash.update(var_to_bytes(project(Ids.new(), process_graph)))
	process_graph.rule.callback = Callable()
	print("PROCESS_GRAPH_SHA ", graph_hash.finish().hex_encode())
	formal_passive_probe()
	graph.rule.callback = Callable()
	graph_a.rule.callback = Callable()
	stable.rule.callback = Callable()
	print("RESULT checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func formal_passive_probe() -> void:
	# Re-run RA-00's real formal graph on this A1-03/A1-04 freeze, never restore live.
	GameStart.end_session()
	MatchJournal.reset_audit_memory()
	var random_stream = preload("res://scripts/match/rule_random.gd")
	random_stream.start_seed(742901)
	GameData.player_id = 0
	check(GameStart.game_start([0, 1]), "formal_two_player_graph_created")
	check(not GameData.objects.is_empty() and not GameData.effects.is_empty(), "formal_registry_effects_nonempty")
	var source = Generation.derive_context(Generation.current_token().token, &"probe.formal.capture")
	check(source.ok, "formal_capture_explicit_trusted_context")
	var runtime:Dictionary = EffectManager.execution_context()
	var statics:Dictionary = {"journal":GameLog._journal, "trace":GameLog._trace,
		"restrictions":AbilityRestrictions.entries, "attributes":Attributes.custom_attributes,
		"templates":[LoadAttack._attack_datas, LoadEvent.events, LoadSituation.situations,
		LoadSituation.climax_situations, LoadCommandSpell.command_spells], "ai":DummyBot.capture_attempts()}
	var checkpoint = Checkpoint.new()
	var exclusions:Dictionary = {GameProgress:["_battle_broadcast_consumer", "battle_broadcast_requires_confirm", "_battle_broadcast_batch_serial"],
		EffectManager:["_message_serial", "_guard_continuations", "_guard_transactions", "_transaction_scope", "_continuation_transactions",
		"_batch_transactions", "_runtime_guard", "_guard_run", "_guard_frames", "_resume_frames"]}
	var captured:bool
	for method in checkpoint.get_method_list():
		if method.name == &"capture":
			captured = checkpoint.call("capture", [GameData, GameProgress, MapData, TimePointChecker, GameStart, EffectManager, statics], exclusions, source.context) if method.args.size() >= 3 else checkpoint.capture([GameData, GameProgress, MapData, TimePointChecker, GameStart, EffectManager, statics], exclusions)
	check(captured, "formal_checkpoint_capture_with_source")
	print("REAL_GRAPH ", JSON.stringify({"captured":captured,"error":checkpoint.error,"objects":checkpoint._objects.size(),"collections":checkpoint._collections.size(),"values":checkpoint._values,"support":"unknown"}))
	var live_ids = Ids.new()
	live_ids.id_for(GameData.player_data_library[0].magic)
	var ids_before:Dictionary = live_ids._by_instance.duplicate()
	var objects_before:Array = live_ids._objects.duplicate()
	var audit_before:Array = [MatchJournal._audit_identity, MatchJournal.audit_revision, MatchJournal.audit_records.duplicate(true), MatchJournal.audit_error, MatchJournal.audit_writer]
	var logs_before:Array = [GameLog.query({},null), GameLog.all_func_calls()]
	var random_before:Dictionary = random_stream.snapshot()
	var service_before:Array = [Generation._current, Generation._issued_tokens.duplicate(), Generation._contexts.duplicate(), Generation._bindings.duplicate()]
	seed(742902)
	var expected:int = randi()
	seed(742902)
	var first:Dictionary = State.capture_passive(runtime, {"max_capture_comparisons":100000000})
	var second:Dictionary = State.capture_passive(runtime, {"max_capture_comparisons":100000000})
	check(first.status == "unknown" and second.status == "unknown" and State.support_manifest().status == "unknown", "formal_passive_cannot_admit")
	check(first.error.is_empty() and second.error.is_empty(), "formal_passive_export_no_error")
	check(var_to_bytes(first.export) == var_to_bytes(second.export), "formal_passive_export_recomputes")
	check(live_ids._by_instance == ids_before and live_ids._objects == objects_before, "formal_passive_live_netids_unchanged")
	check([MatchJournal._audit_identity, MatchJournal.audit_revision, MatchJournal.audit_records, MatchJournal.audit_error, MatchJournal.audit_writer] == audit_before, "formal_passive_audit_unchanged")
	check([GameLog.query({},null), GameLog.all_func_calls()] == logs_before, "formal_passive_logs_trace_unchanged")
	check(random_stream.snapshot() == random_before and randi() == expected, "formal_passive_declared_rng_and_global_sentinel")
	check([Generation._current, Generation._issued_tokens, Generation._contexts, Generation._bindings] == service_before, "formal_passive_issuance_binding_current_unchanged")
	var graph_ok:bool = captured
	for row in checkpoint._collections:
		graph_ok = graph_ok and row.target.size() == row.items.size()
		if row.target is Array:
			for i in row.items.size(): graph_ok = graph_ok and is_same(row.target[i], row.items[i])
		else:
			graph_ok = graph_ok and row.target.keys() == row.items.keys()
			for key in row.items: graph_ok = graph_ok and row.target.has(key) and is_same(row.target.get(key), row.items[key])
	for object in checkpoint._objects:
		var row:Dictionary = checkpoint._objects[object]
		for key in row.fields: graph_ok = graph_ok and is_same(object.get(key), row.fields[key])
		for signal_name in row.connections: graph_ok = graph_ok and Signal(object,signal_name).get_connections() == row.connections[signal_name]
	check(graph_ok, "formal_passive_full_checkpoint_prestate_unchanged")
	var no_handles:bool = true
	for definition in first.export.objects:
		no_handles = no_handles and definition.script not in ["res://scripts/system/session_token.gd", "res://scripts/system/session_context.gd", "res://scripts/system/session_generation.gd"]
	check(no_handles, "formal_export_session_metadata_not_object_definitions")
	var replay_projection:Dictionary = State.capture(Ids.new())
	var replay_hash = HashingContext.new()
	replay_hash.start(HashingContext.HASH_SHA256)
	replay_hash.update(var_to_bytes(replay_projection))
	print("FORMAL_REPLAY_SHA ", replay_hash.finish().hex_encode())
	print("PASSIVE_EXPORT ", JSON.stringify({"first_error":first.error,"second_error":second.error,"objects":first.export.objects.size(),"collections":first.export.get("collections",[]).size(),"support":"unknown"}))
