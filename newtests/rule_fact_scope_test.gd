extends Node

const Log = preload("res://scripts/system/global/game_log.gd")
const Audit = preload("res://scripts/match/match_journal.gd")
const Generation = preload("res://scripts/system/session_generation.gd")
var checks:int = 0
var failures:Array = []
var sync_count:int = 0
var sync_sizes:Array = []
var delivered:Array = []

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func supports(script:Script, name:StringName) -> bool:
	for method in script.get_script_method_list():
		if method.name == name: return true
	return false

func observe_sync(_entry:Dictionary, journal:EventJournal) -> void:
	sync_count += 1
	sync_sizes.append(journal.query({}, 1, null).size())

func _ready() -> void:
	await get_tree().process_frame
	var journal = EventJournal.new()
	journal.recorded.connect(observe_sync.bind(journal))
	journal.record({"round":1, "type":"same", "data":{"value":7}})
	var root:Array = journal.entries
	var parent:Dictionary = root[0]
	var parent_data:Dictionary = parent.data
	var has_scope:bool = journal.has_method("capture_rule_state")
	var state:Variant = journal.capture_rule_state() if has_scope else null
	journal.record({"round":1, "type":"same", "data":{"value":7}})
	journal.record({"round":1, "type":"child_only"})
	check(sync_count == 3 and sync_sizes == [1, 2, 3], "recorded_remains_synchronous_with_query")
	var restored:bool = journal.restore_rule_state(state) if has_scope else false
	check(restored, "child_refusal_restores_fact_scope")
	check(is_same(root, journal.entries) and root.size() == 1 and is_same(root[0], parent) and is_same(parent.data, parent_data), "same_content_parent_identity_order_preserved")
	check(journal.query({"type":"same"}, 1, null).size() == 1 and journal.query({"type":"child_only"}, 1, null).is_empty(), "only_child_query_facts_disappear")
	check(sync_count == 3, "restore_does_not_reemit_or_erase_external_observation")
	if has_scope:
		check(not journal.restore_rule_state(state), "consumed_state_cannot_restore_again")
		var outer = journal.capture_rule_state()
		journal.record({"round":1, "type":"parent_new"})
		var inner = journal.capture_rule_state()
		journal.record({"round":1, "type":"child_new"})
		check(not journal.restore_rule_state(outer) and root.size() == 3, "out_of_order_restore_has_no_writes")
		check(journal.release_rule_state(inner), "child_success_only_releases_private_state")
		check(journal.query({"type":"child_new"}, 1, null).size() == 1, "success_preserves_child_fact")
		check(journal.restore_rule_state(outer) and root.size() == 1, "parent_can_restore_successful_child_with_own_scope")
		state = journal.capture_rule_state()
		parent_data.value = 99
		parent_data["extra"] = true
		journal.trim_rounds(2)
		check(journal.restore_rule_state(state) and is_same(root[0], parent) and parent_data == {"value":7}, "trim_and_nested_data_restore_in_place")
		state = journal.capture_rule_state()
		journal.reset()
		journal.record({"round":1, "type":"new_session"})
		check(not journal.restore_rule_state(state) and journal.query({}, 1, null)[0].type == "new_session", "journal_reset_revokes_old_state")
		var ordered = EventJournal.new()
		ordered.record({"round":1, "type":"same"})
		ordered.record({"round":1, "type":"middle"})
		ordered.record({"round":1, "type":"same"})
		var order:Array = ordered.entries.duplicate()
		state = ordered.capture_rule_state()
		ordered.record({"round":1, "type":"same"})
		check(ordered.restore_rule_state(state) and ordered.entries.size() == 3 and is_same(ordered.entries[0], order[0]) and is_same(ordered.entries[1], order[1]) and is_same(ordered.entries[2], order[2]), "multiple_equal_parents_keep_exact_identity_and_order")
		state = ordered.capture_rule_state()
		var late_listener:Callable = func(_entry:Dictionary): pass
		ordered.recorded.connect(late_listener)
		ordered.record({"round":1, "type":"connection_child"})
		check(not ordered.restore_rule_state(state) and ordered.entries.size() == 4, "listener_drift_restore_fails_before_writes")
		ordered.recorded.disconnect(late_listener)
		check(ordered.restore_rule_state(state) and ordered.entries.size() == 3, "listener_drift_removed_same_state_restores")
		var frozen:Array = []
		frozen.make_read_only()
		ordered.entries[0]["borrowed_readonly"] = frozen
		check(ordered.capture_rule_state() == null, "readonly_container_fails_capture_without_partial_state")
		ordered.entries[0].erase("borrowed_readonly")
	else:
		check(false, "nested_scope_adapter_required")

	var log:Variant = Log
	var audit:Variant = Audit
	var has_log:bool = supports(Log, &"capture_rule_facts") and supports(Audit, &"audit_boundary")
	check(has_log, "game_log_and_audit_adapters_present")
	if has_log:
		var generation:Dictionary = Generation.begin_generation(&"rule_fact_test")
		var context = Generation.derive_context(generation.token, &"rule_fact_test.scope").context
		Log.reset()
		Log.set_context(4, "parent")
		Log.record("parent_fact")
		var execution:int = Log.begin_execution()
		var call_id:int = Log.begin_func_call(null, "parent_call", [], [])
		var before:Dictionary = audit.audit_boundary()
		check(log.capture_rule_facts(null) == null and audit.audit_boundary() == before, "missing_origin_capture_passive_rejection")
		var scope = log.capture_rule_facts(context)
		check(scope != null and audit.audit_boundary() == before, "capture_does_not_allocate_audit_identity")
		Log.end_func_call(call_id, 9, "completed")
		Log.set_context(5, "child")
		Log.record("child_fact")
		var audit_id:int = Audit.next_audit_identity()
		check(Audit.audit_event("start", {"root_id":audit_id}), "real_nonrollbackable_audit_written")
		var after_audit:Dictionary = audit.audit_boundary()
		check(log.restore_rule_facts(scope), "game_log_restores_fact_trace_context")
		check(Log.current_round == 4 and Log.current_phase == "parent" and Log.query({"type":"parent_fact"}, null).size() == 1 and Log.query({"type":"child_fact"}, null).is_empty(), "game_log_restores_query_and_context")
		check(Log.all_func_calls().size() == 1 and Log.all_func_calls()[0].status == "running", "parent_running_trace_entry_restored")
		check(audit.audit_boundary() == after_audit, "refusal_does_not_rollback_audit_identity_or_records")
		scope = log.capture_rule_facts(context)
		Log.record("success_fact")
		before = audit.audit_boundary()
		check(log.release_rule_facts(scope) and audit.audit_boundary() == before, "success_release_does_not_allocate_audit_number")
		check(Log.query({"type":"success_fact"}, null).size() == 1, "success_fact_kept")
		Log.end_func_call(call_id, null, "completed")
		Log.end_execution(execution)
		var live_listener:Callable = func(entry:Dictionary): delivered.append(entry)
		Log.observe_facts(live_listener)
		Log.record("live_before_shadow")
		await get_tree().process_frame
		await get_tree().process_frame
		var live_facts:Array = Log.query({}, null)
		var live_delivered:int = delivered.size()
		var audit_path:String = "user://rule-fact-shadow-" + str(Time.get_ticks_usec()) + ".journal"
		var writer = Audit.begin_audit(audit_path)
		check(writer != null, "real_live_audit_writer_open")
		var writer_id:int = Audit.next_audit_identity()
		check(Audit.audit_event("start", {"root_id":writer_id}), "real_live_audit_writer_seeded")
		var disk_before:PackedByteArray = FileAccess.get_file_as_bytes(audit_path)
		before = audit.audit_boundary()
		var shadow = log.new_shadow_sink()
		shadow.set_context(4, "shadow")
		var shadow_sync:Array = []
		shadow.journal.recorded.connect(func(entry:Dictionary): shadow_sync.append(entry))
		shadow.record("shadow_private_fact", -1, -1, "", null, [], {"n":7})
		var shadow_audit = audit.new_shadow_sink()
		var shadow_id:int = shadow_audit.next_audit_identity()
		check(shadow_audit.audit_event("child", {"root_id":shadow_id, "effect_id":shadow_id}), "shadow_audit_private_memory_sink")
		await get_tree().process_frame
		await get_tree().process_frame
		check(shadow.query({"type":"shadow_private_fact"}, null).size() == 1 and shadow_sync.size() == 1, "shadow_query_and_recorded_are_private_synchronous")
		check(Log.query({}, null) == live_facts and delivered.size() == live_delivered and audit.audit_boundary() == before, "shadow_never_reaches_live_facts_delivery_audit_or_writer")
		check(FileAccess.get_file_as_bytes(audit_path) == disk_before, "shadow_leaves_real_live_audit_file_byte_identical")
		Audit.end_audit(writer)
		scope = log.capture_rule_facts(context)
		Generation.begin_generation(&"next_rule_fact_test")
		Log.record("new_generation")
		var fresh:Array = Log.query({}, null)
		check(not log.restore_rule_facts(scope) and Log.query({}, null) == fresh, "old_origin_cannot_restore_into_new_generation")
		Log.unobserve_facts(live_listener)
		Log.reset()
	print("RESULT ", JSON.stringify({"suite":"rule_fact_scope", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
