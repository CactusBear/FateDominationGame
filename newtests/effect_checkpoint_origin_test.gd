extends Node

const Checkpoint = preload("res://scripts/match/effect_checkpoint.gd")
const Generation = preload("res://scripts/system/session_generation.gd")
const RandomStream = preload("res://scripts/match/rule_random.gd")
var checks:int = 0
var failures:Array = []

class ObservedRule extends RefCounted:
	static var writes:int = 0
	var value:int = 4:
		set(next):
			writes += 1
			value = next
	var handles:Array = []
	func accept(_token, _context):
		return value

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func has_origin_constructor() -> bool:
	var script:Script = Checkpoint
	for method in script.get_script_method_list():
		if method.name == &"_init": return method.args.size() >= 3
	return false

func construct(effect, enabled:bool, context):
	# Only adapt the original constructor arity; never fabricate a ready checkpoint.
	var script:Script = Checkpoint
	return script.callv("new", [effect, enabled, context]) if has_origin_constructor() else script.new(effect, enabled)

func effect_for(token):
	var effect = BaseEffect.new("origin_probe", [], 0, false, false)
	var bound:Dictionary = Generation.bind_origin(effect, token, &"probe.effect_checkpoint")
	check(bound.ok and effect.bind_runtime_context(bound.context), "trusted_runtime_bound")
	return effect

func external_state() -> Dictionary:
	return {"identity":MatchJournal._audit_identity, "revision":MatchJournal.audit_revision,
		"audit":MatchJournal.audit_records.duplicate(true), "error":MatchJournal.audit_error,
		"journal":GameLog._journal.entries.duplicate(true), "trace":GameLog._trace.calls.duplicate(true),
		"rng":RandomStream.snapshot(), "transactions":EffectManager.capture_transaction_state(),
		"guard":EffectManager.runtime_guard_status(), "guard_effect":EffectManager.runtime_guard_effect(),
		"broadcast":GameProgress.battle_broadcast_requires_confirm,
		"batch":GameProgress.battle_broadcast_batch_id(),
		"scope":EffectManager.active_transaction_root(), "score":GameDataManager.find_player_data(0).get("score"),
		"progress":GameProgress.current_round, "players":GameData.player_data_library.keys(),
		"issued":Generation._issued_tokens.duplicate(), "contexts":Generation._contexts.duplicate(),
		"bindings":Generation._bindings.duplicate(), "current":Generation.current_token().get("token")}

func graph_state(cp) -> Dictionary:
	# Observe every captured field/collection and signal without capture/restore writes.
	var objects:Dictionary = {}
	for object in cp._objects:
		var fields:Dictionary = {}
		for field in cp._objects[object].fields:
			var value = object.get(field)
			fields[field] = value.duplicate(true) if value is Array or value is Dictionary else value
		var connections:Dictionary = {}
		for name in cp._objects[object].connections:
			connections[name] = Signal(object, name).get_connections().duplicate(true)
		objects[object] = {"fields":fields, "connections":connections}
	var collections:Array = []
	for record in cp._collections:
		collections.append({"target":record.target, "items":record.target.duplicate(true)})
	return {"objects":objects, "collections":collections}

func capture_legacy_boundary(cp, effect, context) -> void:
	# A1-04 already rejects old two-argument capture. Supply its real public third
	# argument only to exercise downstream original restore/audit, not to hide RED.
	var captured:bool = cp.ready
	if not has_origin_constructor():
		captured = cp.capture([GameData, GameProgress, MapData, TimePointChecker, GameStart, EffectManager, effect, cp.statics],
			{GameProgress:["_battle_broadcast_consumer", "battle_broadcast_requires_confirm", "_battle_broadcast_batch_serial"],
			EffectManager:["_message_serial", "_guard_continuations", "_guard_transactions", "_transaction_scope", "_continuation_transactions", "_batch_transactions", "_runtime_guard", "_guard_run", "_guard_frames", "_resume_frames"]}, context)
	check(captured, "legacy_real_capture_boundary")

func _ready() -> void:
	await get_tree().process_frame
	check(MatchJournal.reset_audit_memory(), "audit_memory_initialized")
	GameData.setup_players(2)
	RandomStream.start_seed(41)
	var first:Dictionary = Generation.begin_generation(&"effect_checkpoint_probe")
	var root = effect_for(first.token)
	var context = Generation.origin_of(root).context
	var initial:Dictionary = external_state()
	var missing = Checkpoint.new(root)
	check(not missing.ready and missing.transaction_id == 0 and missing.members.is_empty(), "missing_context_constructor_fail_closed")
	check(external_state() == initial, "missing_context_zero_external_writes")
	var malformed = construct(root, true, {"token":first.token})
	check(not malformed.ready and malformed.transaction_id == 0, "malformed_context_constructor_rejected")
	check(external_state() == initial, "malformed_context_zero_external_writes")
	var fresh_unbound = BaseEffect.new("unbound", [], 0, false, false)
	var unbound = construct(fresh_unbound, true, context)
	check(not unbound.ready and unbound.transaction_id == 0, "unbound_root_cannot_borrow_context")
	check(external_state() == initial, "unbound_root_zero_external_writes")

	var cp = construct(root, true, context)
	check(cp.ready, "constructor_captures_real_origin")
	capture_legacy_boundary(cp, root, context)
	check(cp.ready, "full_effect_guard_graph_captured")
	print("CAPTURE ready=", cp.ready, " error=", cp.error, " objects=", cp._objects.size(), " collections=", cp._collections.size())
	check(cp.audit("start"), "same_domain_start_audit_allowed")
	var child = effect_for(first.token)
	var registration = EffectManager.GuardContinuation.new(func(): pass)
	var parent_owner = construct(child, false, Generation.origin_of(child).context)
	var ownership:Dictionary = {"transaction_bindings":{child:parent_owner}, "batch_transactions":[{"transaction":parent_owner}], "continuation_queue":[registration], "continuation_transactions":{registration:parent_owner}}
	check(EffectManager.restore_transaction_state(ownership), "real_transaction_ownership_installed")
	# Capture with real original context after parent ownership has been installed.
	var owned = construct(root, true, context)
	capture_legacy_boundary(owned, root, context)
	check(owned.ready, "parent_ownership_guard_captured")
	var old_journal:Array = GameLog._journal.entries
	var old_trace:Array = GameLog._trace.calls
	var old_players:Dictionary = GameData.player_data_library
	var old_data:Dictionary = GameDataManager.find_player_data(0)
	var old_rng:Dictionary = RandomStream.snapshot()
	GameProgress.current_round = 22
	GameLog._journal.entries.append({"probe":true})
	GameLog._trace.calls.append({"probe":true})
	RandomStream.int_in_range(1, 6)
	check(EffectManager.restore_transaction_state({"transaction_bindings":{}, "batch_transactions":[], "continuation_queue":[], "continuation_transactions":{}}), "ownership_temporarily_changed")
	check(owned.restore(), "same_domain_guard_rollback_allowed")
	check(GameProgress.current_round != 22 and GameLog._journal.entries.is_empty() and GameLog._trace.calls.is_empty(), "same_domain_rule_logs_restored")
	check(is_same(GameLog._journal.entries, old_journal) and is_same(GameLog._trace.calls, old_trace) and is_same(GameData.player_data_library, old_players) and is_same(GameDataManager.find_player_data(0), old_data), "same_domain_original_graph_identity")
	check(RandomStream.snapshot() == old_rng, "same_domain_rng_restored")
	var restored:Dictionary = EffectManager.capture_transaction_state()
	check(is_same(restored.transaction_bindings.get(child), parent_owner) and is_same(restored.continuation_queue[0], registration) and is_same(restored.continuation_transactions.get(registration), parent_owner), "parent_and_ticket_original_identity")
	check(Generation.validate_context(context).ok and Generation.validate_token(first.token).ok, "same_domain_eligibility_preserved")
	check(owned.audit("pause", root, "step_budget"), "same_domain_guard_pause_audit_allowed")
	var action_checkpoint = construct(null, false, context)
	check(action_checkpoint.audit("start"), "same_domain_null_root_audit_allowed")

	# Public lifecycle changes only progress; original member/graph references survive.
	GameProgress.reset_progress()
	var second = Generation.current_token().token
	check(not is_same(first.token, second) and not Generation.validate_token(first.token).ok, "public_reset_invalidates_old_origin")
	var fresh = effect_for(second)
	var current_context = Generation.origin_of(fresh).context
	var baseline:Dictionary = external_state()
	var graph_before:Dictionary = graph_state(owned)
	var stale_construct = construct(root, true, context)
	check(not stale_construct.ready and stale_construct.transaction_id == 0, "stale_constructor_rejected")
	check(external_state() == baseline, "stale_constructor_zero_external_writes")
	check(not owned.audit("resume"), "old_guard_resume_audit_rejected")
	check(not owned.audit("rollback_intent", null, "host_skip"), "old_guard_skip_intent_rejected")
	check(not action_checkpoint.audit("commit"), "old_null_root_audit_rejected")
	check(owned.member_id(fresh) == 0, "old_checkpoint_member_registration_rejected")
	check(external_state() == baseline, "old_guard_audit_identity_logs_tickets_zero_writes")
	check(not owned.restore(), "old_guard_restore_rejected")
	check(external_state() == baseline, "old_guard_graph_rng_tickets_zero_writes")
	check(graph_state(owned) == graph_before, "old_guard_all_captured_fields_collections_connections_unchanged")

	# Real public skip path: a trusted fixture installs the captured old checkpoint
	# at the EM boundary. No source/member gate is removed or current ticket invented.
	var paused_ownership:Dictionary = EffectManager.capture_transaction_state()
	paused_ownership.transaction_bindings = {root:owned}
	check(EffectManager.restore_transaction_state(paused_ownership), "public_old_guard_ownership_installed")
	EffectManager.mark_guard_audit_failed(root)
	check(EffectManager.runtime_guard_status().paused and is_same(EffectManager.runtime_guard_effect(), root) and EffectManager.can_rollback_runtime_guard(), "public_real_guard_skip_boundary_ready")
	var skip_before:Dictionary = external_state()
	check(not EffectManager.skip_runtime_guard(), "public_old_guard_skip_rejected")
	check(external_state() == skip_before and is_same(EffectManager.capture_transaction_state().transaction_bindings.get(root), owned), "public_old_guard_skip_zero_external_writes")

	# Independent wrapper-restore gate: public inherited capture can re-capture a
	# small current graph but cannot replace the old wrapper's RNG/log/ownership origin.
	var observer = ObservedRule.new()
	observer.handles = [first.token, weakref(context), observer.accept.bind(first.token, context)]
	check(owned.capture([observer], {}, current_context), "current_base_recapture_real_boundary")
	observer.value = 71
	var writes:int = ObservedRule.writes
	var recapture_before:Dictionary = external_state()
	check(not owned.restore(), "old_wrapper_cannot_launder_through_base_recapture")
	check(ObservedRule.writes == writes and observer.value == 71 and external_state() == recapture_before, "wrapper_first_graph_log_rng_ticket_write_blocked")
	check(not owned._objects.has(first.token) and not owned._objects.has(context), "indirect_handles_reuse_A104_leaf_strategy")
	check(not Generation.validate_token(first.token).ok and is_same(Generation.current_token().token, second), "old_token_never_reactivated")

	var new_cp = construct(fresh, false, current_context)
	check(new_cp.transaction_id > 0 and not new_cp.ready and new_cp.audit("start"), "disabled_capture_legal_new_domain_audit")
	var mixed_before:Dictionary = external_state()
	check(not new_cp.audit("child", child), "current_checkpoint_rejects_old_child_audit")
	check(new_cp.member_id(child) == 0, "current_checkpoint_rejects_old_child_member")
	check(external_state() == mixed_before, "mixed_child_zero_audit_identity_writes")
	var null_cp = construct(null, true, current_context)
	check(null_cp.ready, "explicit_action_context_allows_null_effect_root")
	Generation.invalidate_generation(&"probe_close")
	var closed_before:Dictionary = external_state()
	check(not new_cp.audit("commit") and new_cp.member_id(fresh) == 0 and not null_cp.restore(), "closed_domain_checkpoint_entries_rejected")
	check(external_state() == closed_before, "closed_domain_zero_external_writes")

	# Same-domain public skip positive: use only lifecycle/ownership/guard public APIs.
	EffectManager.reset_runtime()
	var legal_domain:Dictionary = Generation.begin_generation(&"legal_skip_probe")
	var legal_root = effect_for(legal_domain.token)
	var legal_context = Generation.origin_of(legal_root).context
	var legal_checkpoint = construct(legal_root, true, legal_context)
	capture_legacy_boundary(legal_checkpoint, legal_root, legal_context)
	check(legal_checkpoint.ready and legal_checkpoint.audit("start"), "same_domain_skip_complete_checkpoint")
	var legal_ownership:Dictionary = {"transaction_bindings":{legal_root:legal_checkpoint}, "batch_transactions":[], "continuation_queue":[], "continuation_transactions":{}}
	check(EffectManager.restore_transaction_state(legal_ownership), "same_domain_skip_ownership_installed")
	EffectManager.mark_guard_audit_failed(legal_root)
	check(EffectManager.can_rollback_runtime_guard() and is_same(EffectManager.runtime_guard_effect(), legal_root), "same_domain_public_skip_boundary_ready")
	check(EffectManager.skip_runtime_guard(), "same_domain_public_skip_allowed")
	check(Generation.validate_context(legal_context).ok and Generation.validate_token(legal_domain.token).ok and EffectManager.resolved_effects.get(legal_root) == "skipped", "same_domain_skip_retains_eligibility_and_terminal")
	print("RESULT checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
