extends Node
const Plan = preload("res://scripts/system/atomic_action_plan.gd")
const Domain = preload("res://scripts/system/atomic_execution_domain.gd")
var checks:int = 0
var failures:Array = []
func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)
func _thread_query(binding:Variant, domain_identity:Variant, context:Variant) -> Dictionary:
	return {"validation":Plan.validate_execution_binding(binding,context).status, "issuance":Plan.execution_binding(domain_identity,context).status}

func finish() -> void:
	print("RESULT ", JSON.stringify({"suite":"a4-core-e2_binding", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

class Probe extends RefCounted:
	var host:Node
	var context:Variant
	var domain:RefCounted
	var plan:RefCounted
	var registration:RefCounted
	var association:Variant
	var frame_binding:Variant
	var old_binding:Variant
	var marker:Variant
	var old_marker:Variant
	var mode:String = "normal"
	var source_mode:String = "valid"
	var continuation:RefCounted = RefCounted.new()
	var foreign:Variant
	var foreign_domain:RefCounted
	var validations:int = 0
	var validations_at_seal:int = 0
	func _init(owner:Node, source:Variant) -> void:
		host = owner
		context = source
	func validate_original_context(value:Variant) -> Variant:
		validations += 1
		if source_mode == "malformed": return {"status":7}
		if source_mode == "reason_malformed": return {"status":"COMPLETED", "reason":[]}
		if source_mode == "unknown": return {"status":"PENDING"}
		if source_mode == "recursive":
			var recursive:Dictionary = Plan.validate_execution_binding(association, context)
			host.check(recursive.status == "FAULT", "recursive validator inner query FAULT")
			return {"status":"COMPLETED"} # 吞掉递归故障也不能让外层成功。
		return {"status":"COMPLETED" if is_same(value, context) and SessionGeneration.validate_original_context(value).get("ok", false) else "REJECTED", "reason":"source_invalid"}
	func open_domain(d, _ctx:Variant, _closure:Variant, _support:Dictionary) -> Dictionary:
		domain = d
		var a:Dictionary = Plan.execution_binding(d.identity(), context)
		if mode == "missing_proof":
			host.check(a.status == "UNSUPPORTED", "OPEN missing readonly version proof unsupported")
			return {"status":"COMPLETED"}
		host.check(a.status == "COMPLETED" and a.phase == "OPEN" and a.state == "PREPARING", "OPEN association minted by authenticated dispatch")
		association = a.binding
		host.envelope(a, self, "OPEN")
		host.check(a.binding_kind == "ASSOCIATION" and a.frame_marker == null and a.receipt == null and a.continuation == null, "OPEN association is not execution or commit receipt")
		host.check(Plan.execution_binding(d.identity(), context, RefCounted.new()).status == "REJECTED", "OPEN cannot mint FRAME from fake marker")
		return {"status":"COMPLETED"}
	func frame_checks(d, ctx:Variant, resuming:bool) -> void:
		var frame:Dictionary = Domain.current_frame()
		plan = frame.plan_identity
		marker = frame.marker
		var phase:String = "RESUME" if resuming else "PREPARE"
		var exact:Dictionary = Plan.execution_binding(d.identity(), ctx, marker)
		host.check(exact.status == "COMPLETED" and exact.binding_kind == "FRAME" and exact.phase == phase, phase+" exact Core FRAME minted")
		frame_binding = exact.binding
		host.envelope(exact, self, phase)
		host.check(is_same(Plan.validate_execution_binding(frame_binding, ctx, marker).binding, frame_binding), phase+" validator preserves original handle")
		var null_result:Dictionary = Plan.execution_binding(d.identity(), ctx)
		host.check(null_result.status == "COMPLETED" and null_result.binding_kind == "ASSOCIATION" and null_result.frame_marker == null, phase+" null marker never captures current FRAME")
		host.check(Plan.validate_execution_binding(frame_binding, ctx).status == "REJECTED", phase+" FRAME cannot downgrade through null")
		host.check(Plan.validate_execution_binding(association, ctx, marker).status == "REJECTED", phase+" association cannot upgrade to FRAME")
		host.check(Plan.validate_execution_binding(association, ctx).phase == phase, phase+" OPEN association readonly revalidation")
		host.check(Plan.validate_execution_binding(association, foreign).status == "REJECTED", phase+" association exact context rejected")
		if foreign_domain != null:
			host.check(Plan.execution_binding(foreign_domain.identity(), ctx, marker).status == "REJECTED", phase+" true other plan domain cannot reuse root marker")
		host.check(Plan.validate_execution_binding(exact, ctx, marker).status == "REJECTED", phase+" whole envelope not handle")
		host.check(Plan.validate_execution_binding(frame_binding, foreign, marker).status == "REJECTED", phase+" cross context rejected")
		host.check(Plan.execution_binding(d.identity(), foreign, marker).status == "REJECTED", phase+" domain with different context rejected")
		var same_token:SessionContext = SessionContext.new(ctx.token(), ctx.origin())
		host.check(Plan.execution_binding(d.identity(), same_token, marker).status == "REJECTED", phase+" unissued same token context rejected")
		var another = Domain.new()
		host.check(Plan.execution_binding(another.identity(), ctx, marker).status == "REJECTED", phase+" unowned domain rejected")
		host.check(Plan.execution_binding(d, ctx, marker).status == "REJECTED", phase+" Domain object is not domain identity")
		var nested:Dictionary = d.enter_frame(plan, ctx)
		host.check(nested.status == "COMPLETED", phase+" manual same P D context nested frame exists")
		host.check(Plan.execution_binding(d.identity(), ctx, nested.frame_marker).status == "REJECTED", phase+" manual marker not Core authorized")
		host.check(Plan.validate_execution_binding(frame_binding, ctx, nested.frame_marker).status == "REJECTED", phase+" parent permit does not bless manual marker")
		host.check(Plan.validate_execution_binding(frame_binding, ctx, marker).status == "REJECTED", phase+" parent FRAME not current during manual nesting")
		host.check(Domain.leave_frame(nested.frame_marker).status == "COMPLETED", phase+" manual nested leave")
		host.check(Plan.validate_execution_binding(frame_binding, ctx, marker).status == "COMPLETED", phase+" parent restored only exact Core marker")
		if resuming:
			host.check(not is_same(marker, old_marker) and not is_same(frame_binding, old_binding), "RESUME new invocation marker and binding")
			host.check(Plan.validate_execution_binding(old_binding, ctx, old_marker).status == "REJECTED", "RESUME old FRAME never resurrects")
			host.check(Plan.execution_binding(d.identity(), ctx, old_marker).status == "REJECTED", "RESUME old marker cannot mint")
		else:
			old_binding = frame_binding
			old_marker = marker
	func prepare(d, _closure:Variant, ctx:Variant) -> Dictionary:
		if mode == "missing_proof": return {"status":"COMPLETED"}
		if mode == "quiet": return {"status":"PENDING", "continuation":continuation}
		frame_checks(d, ctx, false)
		if mode == "leave":
			host.check(Domain.leave_frame(marker).status == "COMPLETED", "participant manually leaves actual Core marker")
			host.check(Plan.validate_execution_binding(frame_binding,ctx,marker).status == "REJECTED", "already popped Core marker rejected before dispatch return")
			return {"status":"COMPLETED"}
		if mode == "abort":
			Plan.abort(plan, "inside_abort")
			host.check(Plan.validate_execution_binding(frame_binding, ctx, marker).status == "REJECTED", "ABORT inside dispatch revokes FRAME before return")
			return {"status":"COMPLETED"}
		if mode == "discard":
			d.discard()
			host.check(Plan.validate_execution_binding(association, ctx).status == "REJECTED", "domain discard revokes association")
			host.check(Plan.execution_binding(d.identity(), ctx, marker).status == "REJECTED", "domain discard prevents fresh FRAME")
			return {"status":"REJECTED", "reason":"discard_test"}
		if mode == "fault": return {"status":5}
		return {"status":"PENDING", "continuation":continuation}
	func resume(d, owned:Variant, input:Variant, ctx:Variant) -> Dictionary:
		host.check(is_same(owned, continuation) and input == "approved", "RESUME original owned continuation and authenticated input")
		frame_checks(d, ctx, true)
		return {"status":"COMPLETED"}
	func seal(_d, ctx:Variant) -> Dictionary:
		if mode == "missing_proof": return {"status":"COMPLETED"}
		var a:Dictionary = Plan.validate_execution_binding(association, ctx)
		host.check(a.status == "COMPLETED" and a.phase == "SEAL" and a.frame_marker == null, "SEAL readonly association allowed")
		host.check(Plan.execution_binding(domain.identity(), ctx).status == "REJECTED", "SEAL does not sign new association")
		host.check(Plan.validate_execution_binding(frame_binding, ctx, marker).status == "REJECTED", "SEAL old FRAME rejected")
		host.check(a.receipt == null and a.continuation == null, "SEAL not action completion")
		validations_at_seal = validations
		return {"status":"COMPLETED"}

func register(probe:Probe, proof:bool=true) -> void:
	var support:Dictionary = {"abi_version":1, "status":"supported", "proof":"owner_registered_closed_domain", "required_roots":["diagnostic"], "required_adapters":["probe"], "state_domains":["control"], "participants":["probe"]}
	if proof: support.source_validation = {"abi_version":1, "read_only":true, "validator_script":probe.get_script()}
	var registered:Dictionary = Plan.register_participant_manifest({"adapter":probe, "support_manifest":support})
	check(registered.status == "COMPLETED", "participant registered "+probe.mode)
	probe.registration = registered.participant_manifest
	var created:Dictionary = Plan.begin(probe.context, {}, probe.registration)
	check(created.state == "NEW", "real NEW plan "+probe.mode)
	probe.plan = created.plan_identity

func envelope(result:Dictionary, probe:Probe, phase:String) -> void:
	for key in ["status","plan_identity","original_context","reason","continuation","receipt","state","binding","binding_kind","domain_identity","participant_manifest","phase","frame_marker","abi_version"]:
		check(result.has(key), phase+" envelope field "+key)
	check(result.is_read_only() and result.abi_version == 1, phase+" readonly versioned envelope")
	check(is_same(result.original_context, probe.context) and is_same(result.domain_identity, probe.domain.identity()) and is_same(result.participant_manifest, probe.registration), phase+" exact registered context domain participant")
	if phase != "OPEN": check(is_same(result.plan_identity, probe.plan) and is_same(result.frame_marker, probe.marker), phase+" exact plan and marker")

func _ready() -> void:
	var reset:Dictionary = GameData.reset_game_session([0,1])
	check(reset.get("ok",false), "real source lifecycle")
	if not reset.get("ok",false): finish(); return
	var ctx:Variant = reset.context
	var foreign:Variant = SessionGeneration.derive_context(ctx, &"e2_foreign_probe").context
	# 保留原来源的真实发行身份；foreign 也由发行服务提供，而非自造票。
	var library:Dictionary = GameData.player_data_library
	var member:Dictionary = library[0]
	var location:Variant = member.location
	var magic:Variant = member.magic.number
	var facts:Array = GameLog.query({},null)
	var peer:Probe = Probe.new(self,ctx)
	peer.mode = "quiet"
	register(peer)
	check(Plan.prepare(peer.plan).state == "PENDING", "second real same context plan holds independent domain")
	var probe:Probe = Probe.new(self, ctx)
	probe.foreign = foreign
	probe.foreign_domain = peer.domain
	register(probe)
	var domain_new = Domain.new()
	check(Plan.execution_binding(domain_new.identity(),ctx).status == "REJECTED", "unowned NEW domain rejected")
	for fake in [null, "proof", {}, RefCounted.new(), probe.plan, probe.registration, domain_new]:
		var bad:Dictionary = Plan.validate_execution_binding(fake, ctx)
		check(bad.status == "REJECTED" and bad.plan_identity == null and bad.original_context == null and not bad.has("state"), "forged handle is not authenticated "+str(typeof(fake)))
		check(Plan.execution_binding(fake, ctx).status == "REJECTED", "forged domain identity rejected "+str(typeof(fake)))
	check(Plan.prepare(probe.plan).state == "PENDING", "PREPARE returns original PENDING")
	var pending:Dictionary = Plan.validate_execution_binding(probe.association,ctx)
	check(pending.status == "COMPLETED" and pending.phase == "PENDING" and pending.state == "PENDING" and pending.continuation == null and pending.receipt == null, "PENDING readonly association no continuation disclosure")
	check(Plan.validate_execution_binding(probe.old_binding,ctx,probe.old_marker).status == "REJECTED" and Plan.validate_execution_binding(probe.old_binding,ctx,probe.old_marker).reason == "execution_binding_revoked", "PENDING prior FRAME revoked on leave")
	check(Plan.execution_binding(probe.domain.identity(),ctx).status == "REJECTED", "PENDING cannot freshly sign association")
	check(Plan.execution_binding(probe.domain.identity(),ctx,probe.old_marker).status == "REJECTED", "PENDING cannot reuse old marker")
	var validator_count:int = probe.validations
	var worker:Thread = Thread.new()
	check(worker.start(_thread_query.bind(probe.association,probe.domain.identity(),ctx)) == OK, "real off-main-thread query starts")
	var thread_result:Dictionary = worker.wait_to_finish()
	check(thread_result.validation == "REJECTED" and thread_result.issuance == "REJECTED" and probe.validations == validator_count, "off-main-thread rejects without owner validation")
	var manual:Dictionary = probe.domain.enter_frame(probe.plan,ctx)
	check(Plan.execution_binding(probe.domain.identity(),ctx,manual.frame_marker).status == "REJECTED", "manual PENDING frame cannot wash permission")
	Domain.leave_frame(manual.frame_marker)
	for protocol in ["malformed","reason_malformed","unknown","recursive"]:
		probe.source_mode = protocol
		check(Plan.validate_execution_binding(probe.association,ctx).status == "FAULT", "validator "+protocol+" is explicit FAULT")
		check(Plan.inspect(probe.plan).state == "PENDING", "query fault does not abort plan "+protocol)
	probe.source_mode = "valid"
	check(Plan.resume(probe.plan,"approved",ctx).state == "PREPARED", "RESUME completes to PREPARED")
	check(Plan.validate_execution_binding(probe.association,ctx).phase == "PREPARED", "PREPARED association only")
	check(Plan.execution_binding(probe.domain.identity(),ctx).status == "REJECTED", "PREPARED cannot sign fresh binding")
	check(Plan.validate_execution_binding(probe.frame_binding,ctx,probe.marker).status == "REJECTED", "PREPARED FRAME retired")
	var committed:Dictionary = Plan.commit(probe.plan)
	check(committed.state == "COMMITTED" and committed.status == "COMPLETED", "original single commit still succeeds")
	check(probe.validations == probe.validations_at_seal, "INSTALL never calls source validator")
	var terminal:Dictionary = Plan.validate_execution_binding(probe.association,ctx)
	check(terminal.status == "REJECTED" and terminal.phase == "TERMINAL" and is_same(terminal.receipt,Plan.inspect(probe.plan).receipt), "COMMITTED binding rejects and references original receipt")
	check(not is_same(probe.association,committed.receipt) and not is_same(pending,committed.receipt), "certification never action COMMITTED receipt")
	check(is_same(Plan.commit(probe.plan).receipt,committed.receipt), "commit replay preserves same receipt")
	check(Plan.execution_binding(probe.domain.identity(),ctx).status == "REJECTED", "COMMITTED never resurrects association")
	for mode in ["abort","discard","fault","leave","missing_proof"]:
		var other:Probe = Probe.new(self,ctx)
		other.mode = mode
		other.foreign = foreign
		register(other,mode != "missing_proof")
		var prepared:Dictionary = Plan.prepare(other.plan)
		if mode == "missing_proof":
			check(prepared.state == "PREPARED", "old seven methods work without E2 source proof")
			Plan.abort(other.plan,"done")
		else:
			check(prepared.state == ("FAULT" if mode in ["fault","leave"] else "ABORTED"), mode+" original terminal state sticky")
			var terminal_validations:int = other.validations
			check(Plan.validate_execution_binding(other.association,ctx).status == "REJECTED", mode+" association terminal rejects")
			check(other.validations == terminal_validations, mode+" terminal query cannot reenter source owner")
			check(Plan.execution_binding(other.domain.identity(),ctx).status == "REJECTED", mode+" terminal cannot sign")
	check(is_same(GameData.player_data_library,library) and is_same(library[0],member) and is_same(member.location,location) and is_same(member.magic.number,magic), "all query paths preserve live model identity position and payment")
	check(GameLog.query({},null) == facts, "certification emits no live action facts")
	Plan.abort(peer.plan,"peer_cleanup")
	var revoked:Probe = Probe.new(self,ctx)
	revoked.foreign = foreign
	register(revoked)
	Plan.prepare(revoked.plan)
	var newer:Dictionary = GameData.reset_game_session([0,1])
	check(newer.get("ok",false) and not SessionGeneration.validate_context(ctx).get("ok",false), "real issuance source revoked one way")
	check(Plan.validate_execution_binding(revoked.association,ctx).status == "REJECTED", "original source revocation invalidates binding")
	check(Plan.execution_binding(revoked.domain.identity(),newer.context).status == "REJECTED", "new source cannot wash old plan")
	check(Plan.inspect(revoked.plan).state == "PENDING", "source query rejection is not implicit abort")
	Plan.abort(revoked.plan,"cleanup")
	check(Domain.current_frame().status == "REJECTED" and not Domain.publication_is_open(), "all frames and windows retired")
	finish()
