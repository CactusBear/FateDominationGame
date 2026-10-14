extends Node
const Plan = preload("res://scripts/system/atomic_action_plan.gd")
const Domain = preload("res://scripts/system/atomic_execution_domain.gd")
var checks:int = 0
var failures:Array = []

class Participant extends RefCounted:
	var source:RefCounted = RefCounted.new()
	var continuation:RefCounted = RefCounted.new()
	var object:RefCounted = RefCounted.new()
	var mode:String = "success"
	var stale:bool = false
	var calls:int = 0
	var seals:int = 0
	var resumes:int = 0
	var preparing:bool = false
	var window_before_write:bool = false
	var facts:Array = ["old"]
	var index:Dictionary = {"old":1}
	var rule:Dictionary = {"amount":9}
	func validate_original_context(context:Variant) -> Dictionary:
		return {"status":"COMPLETED" if is_same(context, source) and not stale else "REJECTED", "reason":"stale_source"}
	func open_domain(_domain, _context:Variant, _closure:Variant, _manifest:Dictionary) -> Dictionary:
		return {"status":"COMPLETED"}
	func prepare(_domain, _closure:Variant, _context:Variant) -> Variant:
		calls += 1
		preparing = Plan.inspect(Domain.current_frame().plan_identity).state == "PREPARING"
		if mode == "pending": return {"status":"PENDING", "continuation":continuation}
		if mode == "reject": return {"status":"REJECTED", "reason":"diagnostic_reject"}
		if mode == "fault": return null
		return {"status":"COMPLETED"}
	func resume(_domain, owned:Variant, input:Variant, context:Variant) -> Dictionary:
		resumes += 1
		if not is_same(owned, continuation) or not is_same(context, source) or not (input is Dictionary) or input.get("authenticated") != true:
			return {"status":"REJECTED", "reason":"unauthenticated"}
		return {"status":"COMPLETED"}
	func seal(domain, _context:Variant) -> Dictionary:
		seals += 1
		window_before_write = Domain.publication_is_open() and facts == ["old"] and rule.amount == 9 and index == {"old":1}
		# 只预建/暂存；真实安装及唯一回执仍由 P0 负责。
		var staged:Dictionary = domain.stage_slot(rule, "amount", 6, &"rule")
		if staged.status != "COMPLETED": return staged
		staged = domain.stage_container_contents(facts, ["old", object, "new"], &"journal")
		if staged.status != "COMPLETED": return staged
		staged = domain.stage_container_contents(index, {"new":object}, &"runtime")
		if staged.status != "COMPLETED": return staged
		if mode == "ignored_failure":
			# 故意忽略 owner staging 拒绝，core seal 仍必须挡住全写集。
			domain.stage_container_contents([], {}, &"journal")
		if mode == "outbox_object": return {"status":"COMPLETED", "outbox":[object]}
		return {"status":"COMPLETED", "outbox":[{"kind":"diagnostic_complete"}]}

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func created(adapter:Participant) -> Dictionary:
	var registration:Dictionary = Plan.register_participant_manifest({"adapter":adapter, "support_manifest":{
		"abi_version":1, "status":"supported", "proof":"owner_registered_closed_domain",
		"required_roots":["diagnostic"], "required_adapters":["raw_contents"], "state_domains":["rule/facts/runtime"], "participants":["core2_fixture"]}})
	check(registration.status == "COMPLETED", "trusted diagnostic manifest registered")
	return Plan.begin(adapter.source, {}, registration.participant_manifest)

func coordinator() -> void:
	for mode in ["success", "pending", "reject", "fault", "ignored_failure", "outbox_object", "stale", "abort"]:
		var p:Participant = Participant.new()
		p.mode = mode
		var alias:Array = p.facts
		var index_alias:Dictionary = p.index
		var began:Dictionary = created(p)
		check(began.state == "NEW", mode + " NEW")
		var handle:Variant = began.plan_identity
		var result:Dictionary = Plan.prepare(handle)
		check(p.preparing, mode + " PREPARING")
		check(p.facts == ["old"] and p.rule.amount == 9 and p.index == {"old":1}, mode + " prepare zero live writes")
		if mode == "pending":
			check(result.state == "PENDING" and not Domain.publication_is_open(), "PENDING no publication window")
			result = Plan.resume(handle, {"authenticated":true}, p.source)
			check(p.resumes == 1 and p.calls == 1, "pending continues original once")
		if mode not in ["reject", "fault"]:
			check(result.state == "PREPARED" and result.receipt == null, mode + " PREPARED not committed")
			if mode == "stale": p.stale = true
			result = Plan.abort(handle, "cancel") if mode == "abort" else Plan.commit(handle)
		var state:String = "COMMITTED" if mode in ["success", "pending"] else ("FAULT" if mode == "fault" else "ABORTED")
		check(result.state == state, mode + " terminal " + state)
		check(not Domain.publication_is_open(), mode + " window closed after saved receipt")
		if state == "COMMITTED":
			check(p.window_before_write and p.rule.amount == 6 and p.facts.size() == 3 and p.index.size() == 1, "unified slot container complete install before receipt")
			check(is_same(alias, p.facts) and is_same(index_alias, p.index) and is_same(p.facts[1], p.object) and is_same(p.index.new, p.object), "committed fact identities preserved")
			check(result.receipt.is_read_only() and result.receipt.outbox.size() == 1 and not result.receipt.has("prepared"), "Object facts not leaked in receipt outbox")
		else:
			check(p.facts == ["old"] and p.index == {"old":1} and p.rule.amount == 9, mode + " rejection zero full batch install")
			if mode == "ignored_failure": check(result.reason.begins_with("container_write_set_failed:"), "ignored owner staging error core rejection")
		for replay in [Plan.commit(handle), Plan.prepare(handle), Plan.resume(handle, {}, p.source), Plan.abort(handle, "again")]:
			check(replay.state == state and is_same(replay.receipt, result.receipt), mode + " sticky single receipt")
		check(p.calls == 1 and p.seals <= 1, mode + " no rerun or owner install callback")
		for fake in [{"plan_identity":handle, "state":"PREPARED"}, RefCounted.new(), null]:
			check(Plan.commit(fake).reason == "invalid_plan_identity", "forged container plan cannot install")

func domain_edges() -> void:
	var d = Domain.new()
	var target:Array = [1]
	check(d.install_sealed(RefCounted.new()).status == "FAULT", "unsealed install native boundary FAULT")
	check(d.stage_container_contents(target, [2], &"rule").status == "COMPLETED", "boundary contents staged")
	check(d.seal(RefCounted.new()).status == "REJECTED", "forged seal window rejected")
	var w:Dictionary = Domain.acquire_publication_window()
	check(d.seal(w.window).status == "COMPLETED", "boundary seal")
	check(d.stage_container_contents(target, [3], &"rule").status == "REJECTED", "sealed contents staging closed")
	check(d.stage_slot(target, 0, 3, &"rule").status == "REJECTED", "sealed slots staging closed")
	check(d.install_sealed(RefCounted.new()).status == "FAULT" and target == [1], "forged install window FAULT zero write")
	check(d.install_sealed(w.window).status == "COMPLETED" and target == [2], "postseal rejected append cannot poison frozen set")
	check(d.discard().status == "REJECTED", "sealed set cannot discard")
	Domain.release_publication_window(w.window)
	var discarded = Domain.new()
	check(discarded.stage_container_contents([], [], &"rule").status == "COMPLETED", "discardable contents staged")
	check(discarded.discard().status == "COMPLETED", "unsealed contents discarded")
	check(discarded.stage_container_contents([], [], &"rule").status == "REJECTED", "discarded contents cannot revive")
	var distinct = Domain.new()
	var a:Array = [1]
	var b:Array = [1]
	var ta:Array[int] = [2, 3]
	var td:Dictionary[String, int] = {"x":2}
	var dictionary:Dictionary = {}
	check(distinct.stage_container_contents(a, ta, &"rule").status == "COMPLETED", "typed prepared Array allowed for raw target")
	check(distinct.stage_container_contents(b, [4], &"journal").status == "COMPLETED", "equal but distinct target not duplicate")
	check(distinct.stage_container_contents(dictionary, td, &"runtime").status == "COMPLETED", "typed prepared Dictionary allowed for raw target")
	w = Domain.acquire_publication_window()
	check(distinct.seal(w.window).status == "COMPLETED" and distinct.install_sealed(w.window).status == "COMPLETED", "distinct containers install unified")
	check(a == [2, 3] and b == [4] and dictionary == {"x":2} and not a.is_typed() and not dictionary.is_typed(), "raw target identity and type retained")
	Domain.release_publication_window(w.window)

func _ready() -> void:
	coordinator()
	domain_edges()
	print("RESULT ", JSON.stringify({"suite":"A4-core2-coordinator", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
