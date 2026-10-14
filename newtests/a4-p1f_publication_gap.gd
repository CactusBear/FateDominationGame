extends Node
## 阻断诊断，不是 P1-F 实现验收：冻结 P0 不能表达保留原根的事实追加。
const Domain = preload("res://scripts/system/atomic_execution_domain.gd")
const Plan = preload("res://scripts/system/atomic_action_plan.gd")
var checks:int = 0
var failures:Array = []

class GapParticipant extends RefCounted:
	var original:RefCounted
	var journal:EventJournal
	var unrelated:Dictionary = {"value":0}
	var seal_calls:int = 0
	func _init(context:RefCounted, target:EventJournal):
		original = context
		journal = target
	func validate_original_context(context:Variant) -> Dictionary:
		return {"status":"COMPLETED" if is_same(context, original) else "REJECTED"}
	func open_domain(_domain, _context:Variant, _closure:Variant, _support:Dictionary) -> Dictionary:
		return {"status":"COMPLETED"}
	func prepare(domain, _closure:Variant, _context:Variant) -> Dictionary:
		return domain.stage_slot(unrelated, "value", 7, &"rule")
	func resume(_domain, _continuation:Variant, _input:Variant, _context:Variant) -> Dictionary:
		return {"status":"UNSUPPORTED", "reason":"no_pending"}
	func seal(domain, _context:Variant) -> Dictionary:
		seal_calls += 1
		return domain.stage_slot(journal.entries, journal.entries.size(), {"type":"new"}, &"journal")

func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var journal := EventJournal.new()
	journal.record({"type":"old", "round":1})
	var root:Array = journal.entries
	var original_entry:Dictionary = root[0]
	var domain = Domain.new()
	var append_result:Dictionary = domain.stage_slot(root, root.size(), {"type":"new"}, &"journal")
	check(append_result.status == "REJECTED", "P0 rejects journal tail append")
	check(append_result.reason == "unsupported_backing_slot", "append has precise carrier reason")
	check(root.size() == 1 and is_same(root[0], original_entry), "append rejection leaves old identity and size")
	check(domain.stage_slot(journal, "entries", [{"type":"new"}], &"journal").status == "REJECTED", "P0 rejects journal Object root replacement")
	check(is_same(root, journal.entries), "root remains original after rejected replacement")
	var trace := ExecutionTrace.new()
	check(domain.stage_slot(trace, "next_call_id", 1, &"runtime").status == "REJECTED", "P0 rejects trace Object counter assignment")
	check(domain.stage_slot(trace.calls, 0, {"call_id":1}, &"runtime").status == "REJECTED", "P0 rejects empty trace calls append")
	check(trace.next_call_id == 0 and trace.calls.is_empty(), "trace rejects with no live change")
	check(domain.stage_slot(root, 0, {"type":"replacement"}, &"journal").status == "COMPLETED", "P0 supports existing raw array slot control")
	check(is_same(root[0], original_entry), "staging supported slot remains private")
	check(domain.discard().status == "COMPLETED", "discard staged slot succeeds")
	check(is_same(root[0], original_entry), "discard never installs staged slot")
	var participant := GapParticipant.new(RefCounted.new(), journal)
	var registered:Dictionary = Plan.register_participant_manifest({"adapter":participant, "support_manifest":{
		"abi_version":1, "status":"supported", "proof":"owner_registered_closed_domain",
		"required_roots":["diagnostic"], "required_adapters":["diagnostic"], "state_domains":["diagnostic"], "participants":["diagnostic"]}})
	check(registered.status == "COMPLETED", "diagnostic participant registration")
	var begun:Dictionary = Plan.begin(participant.original, null, registered.participant_manifest)
	check(begun.plan_identity is RefCounted, "uses opaque P0 plan identity")
	check(Plan.prepare(begun.plan_identity).state == "PREPARED", "other write stages successfully")
	check(participant.unrelated.value == 0, "prepared other write not live")
	var committed:Dictionary = Plan.commit(begun.plan_identity)
	check(committed.status == "REJECTED" and committed.state == "ABORTED", "append failure aborts before all installs")
	check(committed.reason == "unsupported_backing_slot", "commit preserves actual append failure reason")
	check(participant.unrelated.value == 0, "no half rule batch on fact refusal")
	check(root.size() == 1 and is_same(root[0], original_entry), "no half journal batch on refusal")
	check(not Domain.publication_is_open(), "refusal releases publication window")
	check(Plan.commit(begun.plan_identity).state == "ABORTED", "replay cannot resurrect aborted plan")
	check(participant.seal_calls == 1, "replay cannot rerun seal")
	check(committed.receipt.state == "ABORTED", "abort receipt is never action completion")
	GameLog.reset()
	GameLog.set_context(4, "diagnostic")
	var shadow = GameLog.new_shadow_sink()
	shadow.record("shadow_only")
	GameLog.record("static_only")
	check(shadow.query({"type":"shadow_only"}).size() == 1, "explicit ShadowSink writes private instance")
	check(shadow.query({"type":"static_only"}).is_empty(), "ShadowSink does not intercept static GameLog record")
	check(GameLog.query({"type":"static_only"}).size() == 1, "static call still reaches live journal counterexample")
	check(GameLog.query({"type":"shadow_only"}).is_empty(), "private sink fact absent live")
	GameLog.begin_fact_transaction(901)
	GameLog.record("display_transaction_fact")
	GameLog.abort_fact_transaction(901)
	check(GameLog.query({"type":"display_transaction_fact"}).size() == 1, "display abort cannot isolate or undo rule history")
	check(GameLog.fact_transaction_status(901).status == GameLog.FactTransactionStatus.NOT_PENDING, "NOT_PENDING is not commit proof")
	GameLog.reset()
	print("RESULT ", JSON.stringify({"suite":"A4-P1F-publication-gap", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
