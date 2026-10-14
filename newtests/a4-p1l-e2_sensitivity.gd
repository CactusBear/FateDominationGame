extends Node
const Plan = preload("res://scripts/system/atomic_action_plan.gd")
const Domain = preload("res://scripts/system/atomic_execution_domain.gd")
var checks:int = 0
var failures:Array = []

# 有界单门诊断：非法帧只读 source_status；不执行 setter/reset/模型复制。
class Probe:
	extends RefCounted
	var host:Node
	var context:SessionContext
	var service:Variant
	var scope:bool
	func _init(owner:Node, original:SessionContext, reset_scope:bool):
		host = owner; context = original; scope = reset_scope
	func validate_original_context(candidate:Variant) -> Dictionary:
		return {"status":"COMPLETED", "reason":""} if is_same(candidate, context) and SessionGeneration.validate_original_context(candidate).ok else {"status":"REJECTED", "reason":"invalid_original"}
	func open_domain(d, original:Variant, _closure:Variant, _support:Dictionary) -> Dictionary:
		var opened:Dictionary = SessionGeneration.open_private_lifecycle(d, original)
		if opened.status == "COMPLETED": service = opened.service
		return opened
	func prepare(d, _closure:Variant, original:Variant) -> Dictionary:
		var frame:Dictionary = Domain.current_frame()
		host.check("real Core frame authorized", service.source_status(original).ok)
		if scope:
			host.check("real reset scope begins", service.begin_reset(&"begin", null).ok)
			host.check("revoked epoch same Core frame remains authorized", service.source_status(original).ok)
		var nested:Dictionary = d.enter_frame(frame.plan_identity, original)
		host.check("resetting manual frame denied" if scope else "manual equal P D context denied", not service.source_status(original).ok)
		Domain.leave_frame(nested.frame_marker)
		host.check("real Core parent remains authorized", service.source_status(original).ok)
		if scope: service.finish_reset(true)
		return {"status":"COMPLETED", "reason":""}
	func resume(_d, _continuation:Variant, _input:Variant, _original:Variant) -> Dictionary:
		return {"status":"UNSUPPORTED", "reason":"not_used"}
	func seal(_d, _original:Variant) -> Dictionary:
		return {"status":"UNSUPPORTED", "reason":"no_publication"}

func check(label:String, value:bool) -> void:
	checks += 1
	print("CHECK ",label," ",value)
	if not value: failures.append(label)

func _ready() -> void:
	var begun:Dictionary = SessionGeneration.begin_generation(&"a4-p1l-e2.bounded")
	var context:SessionContext = SessionGeneration.derive_context(begun.token, &"a4-p1l-e2.bounded.original").context
	for scope in [false,true]:
		var p := Probe.new(self,context,scope)
		var support:Dictionary = {"abi_version":1,"status":"supported","proof":"owner_registered_closed_domain","required_roots":["session_generation"],"required_adapters":["fixture"],"state_domains":["fixture"],"participants":["fixture"],"source_validation":{"abi_version":1,"read_only":true,"validator_script":p.get_script()}}
		var registered:Dictionary = Plan.register_participant_manifest({"adapter":p,"support_manifest":support})
		var plan:Dictionary = Plan.begin(context,{},registered.participant_manifest)
		var result:Dictionary = Plan.prepare(plan.plan_identity)
		check("scope aborts original plan" if scope else "normal reaches PREPARED",result.state == ("ABORTED" if scope else "PREPARED"))
		check("original L context retained",SessionGeneration.validate_original_context(context).ok)
		check("leave denies service",not p.service.source_status(context).ok)
		Plan.abort(plan.plan_identity,"fixture_cleanup")
	print("RESULT ",JSON.stringify({"suite":"A4-P1L-E2-bounded","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
