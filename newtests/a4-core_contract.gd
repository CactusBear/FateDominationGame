extends Node
const Plan = preload("res://scripts/system/atomic_action_plan.gd")
const Domain = preload("res://scripts/system/atomic_execution_domain.gd")
var checks:int = 0
var failures:Array = []

class Participant extends RefCounted:
	var mode:String = "success"
	var source:RefCounted = RefCounted.new()
	var calls:int = 0
	var resumes:int = 0
	var seals:int = 0
	var live:Dictionary = {"balance":9, "writes":0, "journal":[], "runtime":"old"}
	var private_state:Dictionary = {}
	var continuation:RefCounted = RefCounted.new()
	var state_during_prepare:String = ""
	var frame_correct:bool = false
	var before_install:bool = false
	var abort_inside:bool = false
	var stale:bool = false
	func validate_original_context(context:Variant) -> Dictionary:
		return {"status":"COMPLETED" if is_same(source, context) and not stale else "REJECTED", "reason":"stale_origin"}
	func open_domain(domain, _context:Variant, _closure:Variant, _manifest:Dictionary) -> Dictionary:
		private_state = live.duplicate(true)
		domain.bind_root(&"model", private_state)
		domain.bind_dependency(live, private_state)
		return {"status":"COMPLETED"}
	func prepare(domain, _closure:Variant, _context:Variant) -> Variant:
		calls += 1
		var frame:Dictionary = Domain.current_frame()
		state_during_prepare = Plan.inspect(frame.plan_identity).state
		frame_correct = is_same(Domain.resolve_root(&"model").value, private_state) and is_same(Domain.rebind_dependency(live).value, private_state)
		private_state.balance -= 3
		private_state.writes += 1
		private_state.journal.append("payment")
		private_state.journal.append("action")
		private_state.runtime = "new"
		if abort_inside:
			Plan.abort(frame.plan_identity, "abort_inside_prepare")
		if mode == "pending": return {"status":"PENDING", "continuation":continuation}
		if mode == "reject": return {"status":"REJECTED", "reason":"private_rule_rejection"}
		if mode == "fault": return null
		if mode == "unknown": return {"status":"unknown"}
		return {"status":"COMPLETED"}
	func resume(_domain, owned:Variant, authenticated_input:Variant, context:Variant) -> Dictionary:
		resumes += 1
		if not is_same(owned, continuation) or not is_same(context, source) or not (authenticated_input is Dictionary) or authenticated_input.get("authenticated") != true:
			return {"status":"REJECTED", "reason":"unauthenticated_input"}
		return {"status":"COMPLETED"}
	func seal(domain, _context:Variant) -> Dictionary:
		seals += 1
		before_install = live.balance == 9 and live.writes == 0 and live.journal.is_empty() and Domain.publication_is_open()
		if mode == "seal_reject": return {"status":"REJECTED", "reason":"changed_read_version"}
		if mode == "outbox_object": return {"status":"COMPLETED", "outbox":[source]}
		if mode == "outbox_cycle":
			var cyclic:Array = []
			cyclic.append(cyclic)
			return {"status":"COMPLETED", "outbox":cyclic}
		# journal 的载体是整批，窗口内不发信号。不能用真实规则运行替身冒称 RA-10 绿。
		for key in ["balance", "writes", "journal", "runtime"]:
			var kind:StringName = &"journal" if key == "journal" else (&"runtime" if key == "runtime" else &"rule")
			var staged:Dictionary = domain.stage_slot(live, key, private_state[key], kind)
			if staged.status != "COMPLETED": return staged
		return {"status":"COMPLETED", "outbox":[{"kind":"complete_batch", "facts":["payment", "action"]}]}

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func manifest(adapter:Participant) -> Variant:
	var registered:Dictionary = Plan.register_participant_manifest({"adapter":adapter, "support_manifest":{
		"abi_version":1, "status":"supported", "proof":"owner_registered_closed_domain",
		"required_roots":["model"], "required_adapters":["raw_slots"], "state_domains":["model/facts/runtime"], "participants":["diagnostic_fixture"]}})
	check(registered.status == "COMPLETED", "PRE trusted fixture adapter registered")
	return registered.participant_manifest

func created(adapter:Participant) -> Dictionary:
	return Plan.begin(adapter.source, {"kind":"diagnostic_only"}, manifest(adapter))

func envelope(result:Dictionary, label:String) -> void:
	for key in ["status", "plan_identity", "original_context", "reason", "continuation", "receipt"]:
		check(result.has(key), label + " explicit " + key)

func terminal_checks(handle:Variant, state:String, label:String) -> void:
	for outcome in [Plan.prepare(handle), Plan.resume(handle, {"authenticated":true}, Plan.inspect(handle).original_context), Plan.commit(handle), Plan.abort(handle, "again")]:
		check(outcome.state == state, label + " terminal remains " + state)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var adapter:Participant = Participant.new()
	var started:Dictionary = created(adapter)
	envelope(started, "begin")
	check(started.state == "NEW", "NEW initially")
	var handle:Variant = started.plan_identity
	check(handle is RefCounted and not (handle is Dictionary), "opaque object identity")
	var prepared:Dictionary = Plan.prepare(handle)
	envelope(prepared, "prepare")
	check(prepared.status == "COMPLETED" and prepared.state == "PREPARED" and prepared.receipt == null, "PREPARED is not committed completion")
	check(adapter.state_during_prepare == "PREPARING", "PREPARING observable only through coordinator")
	check(adapter.frame_correct, "facade D roots and dependency mapping")
	check(Domain.current_frame().status == "REJECTED", "private frame unwound synchronously")
	check(adapter.live.balance == 9 and adapter.live.writes == 0 and adapter.live.journal.is_empty(), "prepare no live writes charges or facts")
	var committed:Dictionary = Plan.commit(handle)
	envelope(committed, "commit")
	check(committed.state == "COMMITTED" and committed.status == "COMPLETED", "COMMITTED receipt")
	check(adapter.before_install, "all seal checks inside exclusive window before writes")
	check(adapter.live.balance == 6 and adapter.live.writes == 1 and adapter.live.journal == ["payment", "action"] and adapter.live.runtime == "new", "complete rule journal runtime batch installed")
	check(not Domain.publication_is_open(), "window released after complete installation")
	check(committed.receipt.is_read_only(), "stored receipt cannot be edited")
	check(committed.receipt.outbox.is_read_only() and committed.receipt.outbox[0].is_read_only() and committed.receipt.outbox[0].facts.is_read_only(), "notification carrier recursively frozen")
	for i in range(5):
		var replay:Dictionary = Plan.commit(handle)
		check(is_same(replay.receipt, committed.receipt), "commit replay identical stored receipt " + str(i))
	terminal_checks(handle, "COMMITTED", "consumed")
	check(adapter.calls == 1 and adapter.seals == 1 and adapter.live.writes == 1 and adapter.live.balance == 6, "single consumption no second rules graph log or charge")
	var fresh:Participant = Participant.new()
	var fresh_handle:Variant = created(fresh).plan_identity
	check(not is_same(fresh_handle, handle), "handle never reused after consumption")
	var fake:Dictionary = {"plan_identity":handle, "state":"PREPARED", "original_context":adapter.source, "_session_serial":1}
	for imposter in [fake, fake.duplicate(true), RefCounted.new(), 1, null]:
		check(Plan.commit(imposter).reason == "invalid_plan_identity", "forged same-shape handle rejected")
		check(Plan.prepare(imposter).status == "REJECTED", "forged prepare rejected")
	check(Plan.begin(adapter.source, {}, {"adapter":adapter}).status == "UNSUPPORTED", "unregistered manifest dictionary cannot authorize")
	var waiting:Participant = Participant.new()
	waiting.mode = "pending"
	var pending_handle:Variant = created(waiting).plan_identity
	var pending:Dictionary = Plan.prepare(pending_handle)
	envelope(pending, "pending")
	check(pending.status == "PENDING" and pending.state == "PENDING" and is_same(pending.continuation, waiting.continuation), "PENDING owns explicit continuation")
	check(waiting.live.balance == 9 and not Domain.publication_is_open(), "pending holds neither live writes nor window")
	var resumed:Dictionary = Plan.resume(pending_handle, {"authenticated":true}, waiting.source)
	envelope(resumed, "resume")
	check(resumed.state == "PREPARED" and waiting.calls == 1 and waiting.resumes == 1, "resume continues once not reprepare")
	check(Plan.commit(pending_handle).state == "COMMITTED" and waiting.live.balance == 6, "pending then commit pays once")
	for mode in ["reject", "seal_reject", "fault", "unknown"]:
		var failed:Participant = Participant.new()
		failed.mode = mode
		var failed_handle:Variant = created(failed).plan_identity
		var outcome:Dictionary = Plan.prepare(failed_handle)
		if mode == "seal_reject": outcome = Plan.commit(failed_handle)
		var expected:String = "FAULT" if mode in ["fault", "unknown"] else "ABORTED"
		check(outcome.state == expected, mode + " explicit terminal")
		terminal_checks(failed_handle, expected, mode)
		check(failed.live.balance == 9 and failed.live.writes == 0 and failed.live.journal.is_empty(), mode + " zero live effects")
	var canceled:Participant = Participant.new()
	var cancel_handle:Variant = created(canceled).plan_identity
	envelope(Plan.abort(cancel_handle, "user_cancel"), "abort")
	terminal_checks(cancel_handle, "ABORTED", "cancel NEW")
	check(canceled.calls == 0, "abort before rule execution")
	var bad_input:Participant = Participant.new()
	bad_input.mode = "pending"
	var bad_handle:Variant = created(bad_input).plan_identity
	Plan.prepare(bad_handle)
	check(Plan.resume(bad_handle, {"authenticated":false}, bad_input.source).state == "ABORTED", "unauthenticated input terminates")
	terminal_checks(bad_handle, "ABORTED", "bad input")
	var wrong_source:Participant = Participant.new()
	wrong_source.mode = "pending"
	var wrong_handle:Variant = created(wrong_source).plan_identity
	Plan.prepare(wrong_handle)
	check(Plan.resume(wrong_handle, {}, RefCounted.new()).reason == "original_context_identity_mismatch", "same-epoch different provenance forbidden")
	terminal_checks(wrong_handle, "ABORTED", "wrong source")
	var stale:Participant = Participant.new()
	var stale_handle:Variant = created(stale).plan_identity
	Plan.prepare(stale_handle)
	stale.stale = true
	check(Plan.commit(stale_handle).state == "ABORTED" and stale.live.balance == 9 and stale.seals == 0, "seal revalidates original source before first write")
	var reentrant:Participant = Participant.new()
	reentrant.abort_inside = true
	var reentrant_handle:Variant = created(reentrant).plan_identity
	check(Plan.prepare(reentrant_handle).state == "ABORTED", "abort inside prepare cannot be resurrected by completed callback")
	terminal_checks(reentrant_handle, "ABORTED", "reentrant abort")
	for phase in ["NEW", "PENDING", "PREPARED"]:
		var aborted:Participant = Participant.new()
		if phase == "PENDING": aborted.mode = "pending"
		var aborted_handle:Variant = created(aborted).plan_identity
		if phase != "NEW": Plan.prepare(aborted_handle)
		check(Plan.abort(aborted_handle, "explicit_cancel").state == "ABORTED", "abort from " + phase)
		terminal_checks(aborted_handle, "ABORTED", "abort " + phase)
		check(aborted.live.writes == 0 and aborted.live.balance == 9, "abort " + phase + " no live effects")
	for mode in ["outbox_object", "outbox_cycle"]:
		var unsafe:Participant = Participant.new()
		unsafe.mode = mode
		var unsafe_handle:Variant = created(unsafe).plan_identity
		Plan.prepare(unsafe_handle)
		check(Plan.commit(unsafe_handle).reason == "unsupported_outbox_carrier", mode + " refused before first live write")
		check(unsafe.live.writes == 0 and not Domain.publication_is_open(), mode + " leaves neither writes nor lock")
	var misuse:Participant = Participant.new()
	var misuse_handle:Variant = created(misuse).plan_identity
	check(Plan.commit(misuse_handle).state == "ABORTED", "commit NEW rejects terminally")
	terminal_checks(misuse_handle, "ABORTED", "bad transition")
	check(Plan.register_participant_manifest({"adapter":misuse, "support_manifest":{"abi_version":1, "status":99}}).status == "UNSUPPORTED", "malformed owner manifest type fails closed")
	check(Plan.register_participant_manifest({"adapter":misuse, "support_manifest":{"abi_version":1, "status":"supported", "proof":"unknown"}}).status == "UNSUPPORTED", "unknown closure proof fails closed")
	Plan.abort(fresh_handle, "unused")
	domain_checks()
	abi_checks()
	print("RESULT ", JSON.stringify({"suite":"A4-core", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func domain_checks() -> void:
	var d = Domain.new()
	var live:Dictionary = {"amount":9}
	var draft:Dictionary = {"amount":6}
	check(d.bind_root(&"model", draft).status == "COMPLETED", "domain root registered")
	check(d.bind_dependency(live, live).status == "REJECTED", "live alias refused")
	check(d.bind_dependency(live, draft).status == "COMPLETED", "reference rebinding")
	var frame:Dictionary = d.enter_frame(RefCounted.new(), RefCounted.new())
	check(frame.status == "COMPLETED", "opaque frame entered")
	check(Domain.leave_frame({"marker":frame.frame_marker}).status == "REJECTED", "same-shaped frame forged rejected")
	var child:Dictionary = d.enter_frame(RefCounted.new(), RefCounted.new())
	check(Domain.leave_frame(frame.frame_marker).status == "REJECTED", "frame strict LIFO")
	check(Domain.leave_frame(child.frame_marker).status == "COMPLETED", "inner frame left")
	check(Domain.resolve_root(&"absent").status == "REJECTED", "undeclared root fails closed")
	check(Domain.rebind_dependency({"amount":9}).status == "REJECTED", "same-shaped dictionary not reference identity")
	check(Domain.acquire_publication_window().status == "REJECTED", "no publication while private execution frame exists")
	Domain.leave_frame(frame.frame_marker)
	check(Domain.resolve_root(&"model").status == "REJECTED", "domain outside controlled frame unavailable")
	check(is_same(live, live) and live.amount == 9, "live backing never substituted")
	check(d.stage_slot(RefCounted.new(), "value", 1, &"rule").status == "REJECTED", "Object setter publication forbidden")
	var typed:Array[int] = [1]
	check(d.stage_slot(typed, 0, "wrong", &"rule").status == "REJECTED", "typed slot unsupported before install")
	check(d.stage_slot(live, "amount", 6, &"rule").status == "COMPLETED", "primitive backing slot staged")
	check(d.stage_slot(live, "amount", 3, &"rule").status == "REJECTED", "duplicate write refused")
	var window:Dictionary = Domain.acquire_publication_window()
	check(window.status == "COMPLETED", "window acquired")
	check(Domain.acquire_publication_window().status == "REJECTED", "exclusive window")
	check(d.seal(window.window).status == "COMPLETED", "domain sealed")
	check(d.stage_slot(live, "amount", 4, &"rule").status == "REJECTED", "sealed carrier immutable")
	check(d.install_sealed(window.window).status == "COMPLETED" and live.amount == 6, "raw backing installed")
	check(d.install_sealed(window.window).status == "FAULT" and live.amount == 6, "domain installation single consumption")
	check(Domain.release_publication_window(RefCounted.new()).status == "REJECTED", "forged window cannot unlock")
	Domain.release_publication_window(window.window)

func abi_checks() -> void:
	var expected:Dictionary = {"begin":["original_context", "declared_action_closure", "participant_manifest"],
		"prepare":["plan"], "resume":["plan", "authenticated_input", "original_context"],
		"commit":["prepared_plan"], "abort":["plan", "reason"]}
	for method in Plan.new().get_script().get_script_method_list():
		if expected.has(method.name):
			var actual:Array = []
			for arg in method.args: actual.append(str(arg.name))
			check(actual == expected[method.name], "design section4.1 ABI literal " + str(method.name))
			expected.erase(method.name)
	check(expected.is_empty(), "all five design ABI signatures present")
	check(Plan.State.keys() == ["NEW", "PREPARING", "PENDING", "PREPARED", "COMMITTED", "ABORTED", "FAULT"], "all seven states literal design")
