extends "res://newtests/a4-p1l3_lifecycle.gd"
const Source = preload("res://scripts/system/session_generation.gd")

# 受信专项 participant 只证明 L↔Core 调度边界，不签 C admission/完整图。
class Probe:
	extends RefCounted
	var host:Node
	var context:SessionContext
	var other_context:SessionContext
	var mode:String
	var service:Variant
	var domain:Variant
	var plan:RefCounted
	var association:RefCounted
	var frame_binding:RefCounted
	var marker:RefCounted
	var prior_binding:RefCounted
	var prior_marker:RefCounted
	var gp:Dictionary
	var target:Dictionary
	var source_calls:int = 0
	var receiver:Node
	var continuation:RefCounted = RefCounted.new()
	func _init(owner:Node, selected:String, original:SessionContext, other:SessionContext):
		host = owner; mode = selected; context = original; other_context = other
	func validate_original_context(candidate:Variant) -> Dictionary:
		source_calls += 1
		# 固定纯来源入口：绝不调用 validate_context/attach 或 service.source_status。
		if not is_same(candidate, context) or not Source.validate_original_context(candidate).ok:
			return {"status":"REJECTED", "reason":"invalid_original"}
		return {"status":"COMPLETED", "reason":""}
	func open_domain(d, original:Variant, _closure:Variant, _support:Dictionary) -> Dictionary:
		domain = d
		var associated:Dictionary = Plan.execution_binding(d.identity(), original)
		if mode == "missing_proof": return Source.open_private_lifecycle(d, original)
		host.check(mode+" OPEN exact association", associated.status == "COMPLETED" and associated.binding_kind == "ASSOCIATION" and associated.phase == "OPEN")
		if associated.status != "COMPLETED": return associated
		association = associated.binding; plan = associated.plan_identity
		host.check(mode+" OPEN cannot execute", not Source.in_private_frame())
		var opened:Dictionary = Source.open_private_lifecycle(d, original)
		host.check(mode+" OPEN L service bound", opened.status == "COMPLETED")
		if opened.status != "COMPLETED": return opened
		service = opened.service
		host.check(mode+" OPEN association not service execution", not service.attach_current_plan().ok and not service.source_status(original).ok)
		host.check(mode+" OPEN original identity", is_same(service.original_context, original))
		target = GameProgress.publication_backing()
		gp = host.copy_plain(target)
		return GameProgress.bind_domain_model(d, gp)
	func consume(phase:String) -> void:
		var frame:Dictionary = Domain.current_frame()
		marker = frame.marker
		var issued:Dictionary = Plan.execution_binding(domain.identity(), context, marker)
		host.check(phase+" explicit Core FRAME", issued.status == "COMPLETED" and issued.binding_kind == "FRAME" and is_same(issued.frame_marker, marker))
		frame_binding = issued.binding
		host.check(phase+" L attach authenticates", service.attach_current_plan().ok)
		host.check(phase+" normal source accepted", Source.validate_context(context).ok and service.source_status(context).ok)
		host.check(phase+" repeated read accepted", service.source_status(context).ok)
		host.check(phase+" pure original source still accepted", Source.validate_original_context(context).ok)
		host.check(phase+" association cannot upgrade", Plan.validate_execution_binding(association, context, marker).status == "REJECTED")
		host.check(phase+" FRAME cannot omit marker", Plan.validate_execution_binding(frame_binding, context).status == "REJECTED")
		host.check(phase+" same shape source rejected", not service.source_status(SessionContext.new(context.token(), context.origin())).ok)
		host.check(phase+" dictionary source rejected", not service.source_status({"token":context.token(),"origin":context.origin()}).ok)
		host.check(phase+" other issued source rejected", not service.source_status(other_context).ok)
		var nested:Dictionary = domain.enter_frame(plan, context)
		host.check(phase+" manual identical P D context rejected", not service.attach_current_plan().ok and not Source.validate_context(context).ok)
		host.check(phase+" manual reset rejected before clearing", not GameProgress.reset_progress().ok)
		host.check(phase+" nested rejection leaves GP unchanged", gp.current_round == target.current_round)
		Domain.leave_frame(nested.frame_marker)
		host.check(phase+" original FRAME restored", service.attach_current_plan().ok)
		var wrong_domain = Domain.new()
		var wrong:Dictionary = wrong_domain.enter_frame(plan, context)
		host.check(phase+" wrong domain rejected", not service.source_status(context).ok and not Source.validate_context(context).ok)
		Domain.leave_frame(wrong.frame_marker); wrong_domain.discard()
		wrong = domain.enter_frame(RefCounted.new(), context)
		host.check(phase+" wrong plan rejected", not service.attach_current_plan().ok)
		Domain.leave_frame(wrong.frame_marker)
		wrong = domain.enter_frame(plan, other_context)
		host.check(phase+" wrong frame context rejected", not service.attach_current_plan().ok)
		Domain.leave_frame(wrong.frame_marker)
		host.check(phase+" original context resumed after negative inputs", service.source_status(context).ok)
	func prepare(d, _closure:Variant, _original:Variant) -> Dictionary:
		consume(mode+" PREPARE")
		if mode == "pending":
			prior_binding = frame_binding; prior_marker = marker
			return {"status":"PENDING", "continuation":continuation}
		if mode == "reset":
			host.seed_progress(gp)
			receiver = ResetReceiver.new(); receiver.mode = "reset"; receiver.original_context = context
			receiver.trigger = 1
			host.check("reset true original Node setter once", receiver.calls == 1)
			host.check("reset true clear returned original source", receiver.receipt.ok and is_same(receiver.receipt.context, context))
			host.check("reset all seeded scalar fields cleared", gp.current_round == 0 and gp.current_phase_index == -1 and gp.current_player_id == -1 and gp._session_serial == 72)
			host.check("reset original L source stays valid", Source.validate_original_context(context).ok)
			host.check("reset old P already ABORTED", Plan.inspect(plan).state == "ABORTED")
			host.check("reset old service no execution", not service.attach_current_plan().ok)
			host.check("reset original sequence", service.diagnostic_status().steps == [&"authenticate_original",&"revoke_private_epoch",&"allocate_private_epoch",&"clear_progress_values",&"abort_old_plan"])
			receiver.free()
		elif mode == "reset_scope":
			host.check("scope begin authenticates", service.begin_reset(&"begin", null).ok)
			host.check("scope own revoked epoch still permits original clear frame", Source.validate_context(context).ok)
			var nested:Dictionary = d.enter_frame(plan, context)
			host.check("scope resetting not a manual-frame bypass", not service.source_status(context).ok and not Source.validate_context(context).ok)
			host.check("scope nested reset fails", not service.begin_reset(&"begin", null).ok)
			service.finish_reset(true)
			host.check("scope illegal finish cannot abort owner", Plan.inspect(plan).state == "PREPARING")
			Domain.leave_frame(nested.frame_marker)
			host.check("scope real frame remains authorized", Source.validate_context(context).ok)
			GameProgress.current_round = 0
			host.check("scope property clear after revocation works", gp.current_round == 0)
			host.check("scope same-frame recursive reset refused", not service.begin_reset(&"begin", null).ok)
			service.finish_reset(true)
			host.check("scope finish invalidates old P", Plan.inspect(plan).state == "ABORTED")
		elif mode == "discard":
			d.discard()
			host.check("discard service rejects current old frame", not service.source_status(context).ok)
		else:
			GameProgress.current_round = 43
		return {"status":"COMPLETED", "reason":""}
	func resume(_d, _continuation:Variant, _input:Variant, _original:Variant) -> Dictionary:
		host.check("RESUME prior FRAME rejected", Plan.validate_execution_binding(prior_binding, context, prior_marker).status == "REJECTED")
		consume("RESUME")
		host.check("RESUME new marker and handle", not is_same(marker, prior_marker) and not is_same(frame_binding, prior_binding))
		return {"status":"COMPLETED", "reason":""}
	func seal(d, original:Variant) -> Dictionary:
		var valid:Dictionary = validate_original_context(original)
		if valid.status != "COMPLETED": return valid
		host.check("SEAL service has no execution", not service.source_status(context).ok)
		return d.stage_slot(target, "current_round", gp.current_round, &"rule")

func begin_probe(p:Probe, proof:bool = true) -> Dictionary:
	var support:Dictionary = {"abi_version":1,"status":"supported","proof":"owner_registered_closed_domain","required_roots":["fixture-gp"],"required_adapters":["fixture-only"],"state_domains":["fixture"],"participants":["fixture"]}
	if proof: support.source_validation = {"abi_version":1,"read_only":true,"validator_script":p.get_script()}
	var registered:Dictionary = Plan.register_participant_manifest({"adapter":p,"support_manifest":support})
	return Plan.begin(p.context, {}, registered.participant_manifest)

func _ready() -> void:
	print("USER_DATA_DIR ",OS.get_user_data_dir())
	check("physical E user path", OS.get_user_data_dir().replace("\\","/").begins_with("E:/"))
	var context:SessionContext = source()
	var other:SessionContext = Source.derive_context(context,&"a4-p1l-e2.other").context
	var baseline:Dictionary = GameProgress.publication_backing().duplicate()
	var metadata:Dictionary = Source.lifecycle_diagnostics()
	check("manual domain OPEN association rejected", Source.open_private_lifecycle(Domain.new(),context).status == "REJECTED")
	var missing := Probe.new(self,"missing_proof",context,other)
	var mp:Dictionary = begin_probe(missing,false)
	check("missing trusted source proof refuses OPEN", Plan.prepare(mp.plan_identity).state == "ABORTED" and missing.service == null)
	for mode in ["normal","pending","reset","reset_scope","discard"]:
		var p := Probe.new(self,mode,context,other)
		var begun:Dictionary = begin_probe(p)
		var prepared:Dictionary = Plan.prepare(begun.plan_identity)
		check(mode+" service unavailable after leave", not p.service.source_status(context).ok)
		check(mode+" old frame credential revoked", Plan.validate_execution_binding(p.frame_binding,context,p.marker).status == "REJECTED")
		check(mode+" source issuance unchanged", Source.lifecycle_diagnostics() == metadata)
		check(mode+" zero live GP writes before commit", GameProgress.publication_backing() == baseline)
		if mode == "pending":
			check("PENDING actual state", prepared.state == "PENDING")
			var manual:Dictionary = p.domain.enter_frame(begun.plan_identity,context)
			check("PENDING old frame cannot be reconstructed", not p.service.attach_current_plan().ok)
			Domain.leave_frame(manual.frame_marker)
			check("RESUME prepare completed", Plan.resume(begun.plan_identity,{},context).state == "PREPARED")
			Plan.abort(begun.plan_identity,"fixture_cleanup")
		elif mode == "normal":
			check("normal prepared not completed action", prepared.state == "PREPARED" and prepared.receipt == null)
			var calls:int = p.source_calls
			var committed:Dictionary = Plan.commit(begun.plan_identity)
			check("normal unified commit receipt", committed.state == "COMMITTED" and is_same(committed.receipt, Plan.inspect(begun.plan_identity).receipt))
			check("INSTALL no owner source callback", p.source_calls == calls+2)
			check("normal original raw slot installed", GameProgress.current_round == 43)
			check("terminal binding refused", Plan.validate_execution_binding(p.association,context).status == "REJECTED")
			check("terminal replay same receipt", is_same(committed.receipt,Plan.commit(begun.plan_identity).receipt))
			baseline = GameProgress.publication_backing().duplicate()
		elif mode in ["reset","reset_scope"]:
			check(mode+" old P sticky ABORTED", prepared.state == "ABORTED" and Plan.commit(begun.plan_identity).state == "ABORTED")
			check(mode+" L original still validates", Source.validate_original_context(context).ok)
		else:
			check("discard no association reuse", Plan.validate_execution_binding(p.association,context).status == "REJECTED")
			Plan.abort(begun.plan_identity,"fixture_cleanup")
	var waiting := Probe.new(self,"pending",context,other)
	var wp:Dictionary = begin_probe(waiting)
	check("L generation waiting actual PENDING",Plan.prepare(wp.plan_identity).state == "PENDING")
	var newer:SessionContext = source()
	check("L generation barrier immediate old P abort",Plan.inspect(wp.plan_identity).state == "ABORTED")
	check("L generation rejects saved association",Plan.validate_execution_binding(waiting.association,context).status == "REJECTED")
	check("L generation original source invalid",not Source.validate_original_context(context).ok and Source.validate_original_context(newer).ok)
	check("L generation cannot resume under new source",Plan.resume(wp.plan_identity,{},newer).state == "ABORTED")
	finish()

func finish() -> void:
	print("RESULT ",JSON.stringify({"suite":"A4-P1L-E2","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
