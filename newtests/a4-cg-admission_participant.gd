extends RefCounted
## 受审有限诊断 participant：只组合原公开 Core/G/RNG/纯来源接口。
const Plan = preload("res://scripts/system/atomic_action_plan.gd")
const Domain = preload("res://scripts/system/atomic_execution_domain.gd")
const Graph = preload("res://scripts/match/graph_session.gd")
const Registry = preload("res://scripts/system/atomic_setter_registry.gd")
const Random = preload("res://scripts/match/rule_random.gd")
const Source = preload("res://scripts/system/session_generation.gd")
var registry:RefCounted
var graph:RefCounted
var domain:RefCounted
var plan:RefCounted
var context:RefCounted
var manifest:RefCounted
var registration:RefCounted
var owner_spec:Dictionary
var raw:Array = [{"x":3}]
var arguments:Array
var association:Variant
var factory_admission:Variant
var frame_binding:Variant
var execute_admission:Variant
var previous_binding:Variant
var previous_admission:Variant
var previous_spec:Dictionary
var samples:Array = []
var observations:Array = []
var mode:String = "success"
var before:Dictionary
var raw_private:Variant
var scope:Variant
var continuation:RefCounted = RefCounted.new()
# 仅负向故障输入：模拟已登记纯 validator 违约重入，绝不用于成功许可。
var reentry_enabled:bool = false
var reentry_result:Dictionary = {}

func observe(ok:bool, label:String) -> void:
	observations.append([ok,label])

func validate_original_context(original:Variant) -> Dictionary:
	var result:Dictionary = Source.validate_original_context(original)
	if reentry_enabled:
		reentry_enabled = false
		reentry_result = registry.admit_call(frame_binding,call_spec("EXECUTE"),graph.certificate()) if mode == "registry_recursive" else graph.authenticate(true)
	return {"status":"COMPLETED" if result.ok else "REJECTED","reason":"" if result.ok else "invalid_original_source"}

func call_spec(stage:String) -> Dictionary:
	var spec:Dictionary = owner_spec.duplicate(false)
	spec.merge({"owner_registration":registration,"graph":graph,"domain":domain,"original_context":context,"plan_identity":plan,"participant_manifest":manifest,"association":association,"arguments":arguments,"admission_kind":stage,"kind":"constructor" if stage == "FACTORY" else "method"},true)
	if stage == "SEAL_CHECK": spec["prepared_admission"] = execute_admission
	return spec

func open_domain(d:RefCounted, original:Variant, _closure:Variant, _support:Dictionary) -> Dictionary:
	domain = d
	context = original
	var bound:Dictionary = Plan.execution_binding(d.identity(),original)
	if bound.status != "COMPLETED": return bound
	plan = bound.plan_identity
	association = bound.binding
	graph = Graph.new()
	var configured:Dictionary = graph.configure(d,plan,original)
	if configured.status != "COMPLETED": return configured
	var associated:Dictionary = graph.associate(association)
	if associated.status != "COMPLETED": return associated
	var spec:Dictionary = call_spec("FACTORY")
	var permitted:Dictionary = registry.admit_call(association,spec,graph.certificate())
	observe(permitted.status == "COMPLETED","OPEN factory permit is genuine association, not FRAME")
	if permitted.status != "COMPLETED": return permitted
	factory_admission = permitted.admission
	observe(permitted.admission_kind == "FACTORY" and is_same(permitted.execution_binding,association) and is_same(permitted.plan_identity,plan) and is_same(permitted.original_context,original),"C public envelope retains authenticated exact identities")
	var attached:Dictionary = graph.attach_execution(association,registry,factory_admission,spec)
	if attached.status != "COMPLETED": return attached
	observe(registry.execute_random(factory_admission,association,spec).status != "COMPLETED","factory cannot execute sampler")
	observe(graph.resolve(raw).status != "COMPLETED","factory cannot resolve as execution")
	var forked:Dictionary = graph.fork_raw(raw)
	if forked.status != "COMPLETED": return forked
	raw_private = forked.value
	var stream:Dictionary = graph.fork_stream(Random.graph_stream_descriptor())
	if stream.status != "COMPLETED": return stream
	scope = stream.value
	var protection:Dictionary = graph.protect_edge(raw_private,0)
	if protection.status != "COMPLETED": return protection
	var locked:Dictionary = graph.lock_structure()
	if locked.status != "COMPLETED": return locked
	observe(graph.validate_certificate(graph.certificate()).status == "COMPLETED","independent structure certificate succeeds without execution admission")
	observe(Random.snapshot() == before,"OPEN L RNG unchanged")
	return d.bind_root(&"atomic_graph_session",graph)

func prepare(_domain:RefCounted, _closure:Variant, original:Variant) -> Dictionary:
	var result:Dictionary = run_frame(original)
	if result.status != "COMPLETED": return result
	if mode == "pending":
		previous_binding = frame_binding
		previous_admission = execute_admission
		previous_spec = call_spec("EXECUTE")
		return {"status":"PENDING","continuation":continuation}
	return result

func resume(_domain:RefCounted, owned:Variant, input:Variant, original:Variant) -> Dictionary:
	if not is_same(owned,continuation) or not is_same(input,continuation): return {"status":"REJECTED","reason":"wrong_owned_input"}
	observe(registry.validate_admission(previous_admission,previous_binding,previous_spec).status != "COMPLETED","RESUME old invocation permit rejected")
	return run_frame(original)

func run_frame(original:Variant) -> Dictionary:
	var frame:Dictionary = Domain.current_frame()
	var binding:Dictionary = Plan.execution_binding(domain.identity(),original,frame.marker)
	if binding.status != "COMPLETED": return binding
	frame_binding = binding.binding
	var spec:Dictionary = call_spec("EXECUTE")
	observe(Plan.validate_execution_binding(frame_binding,original).status != "COMPLETED","FRAME cannot downgrade to association")
	observe(Plan.validate_execution_binding(association,original,frame.marker).status != "COMPLETED","association cannot upgrade to FRAME")
	var wrong:Dictionary = spec.duplicate(false)
	wrong.receiver = RefCounted.new()
	observe(registry.admit_call(frame_binding,wrong,graph.certificate()).status != "COMPLETED","wrong receiver rejected before sampler")
	wrong = spec.duplicate(false); wrong.kind = "property"
	observe(registry.admit_call(frame_binding,wrong,graph.certificate()).status != "COMPLETED","binding accessor kind cannot change")
	wrong = spec.duplicate(false); wrong.target_script = Graph
	observe(registry.admit_call(frame_binding,wrong,graph.certificate()).status != "COMPLETED","wrong exact Script rejected")
	wrong = spec.duplicate(false); wrong.arguments = [arguments[0],arguments[1],raw.duplicate(true)]
	observe(registry.admit_call(frame_binding,wrong,graph.certificate()).status != "COMPLETED","equal raw argument with wrong identity rejected")
	wrong = spec.duplicate(false); wrong.participant_manifest = RefCounted.new()
	observe(registry.admit_call(frame_binding,wrong,graph.certificate()).status != "COMPLETED","wrong participant manifest rejected")
	wrong = spec.duplicate(false); wrong.original_context = SessionContext.new(original.token(),original.origin())
	observe(registry.admit_call(frame_binding,wrong,graph.certificate()).status != "COMPLETED","unissued same token context rejected")
	observe(registry.admit_call(binding,spec,graph.certificate()).status != "COMPLETED","whole binding envelope is not permit")
	wrong = spec.duplicate(false); wrong.domain = Domain.new()
	observe(registry.admit_call(frame_binding,wrong,graph.certificate()).status != "COMPLETED","same plan wrong domain rejected")
	wrong = spec.duplicate(false); wrong.erase("publish_adapter")
	observe(registry.admit_call(frame_binding,wrong,graph.certificate()).status != "COMPLETED","missing publisher rejected")
	observe(registry.admit_call(frame_binding,spec,{"status":"COMPLETED"}).status != "COMPLETED","same-shaped graph certificate rejected")
	observe(registry.admit_call(frame_binding,spec,RefCounted.new()).status != "COMPLETED","foreign graph certificate rejected")
	var nested:Dictionary = domain.enter_frame(plan,original)
	var forged:Dictionary = Plan.execution_binding(domain.identity(),original,nested.frame_marker)
	observe(forged.status != "COMPLETED","manual same P D context marker never authorized")
	observe(registry.admit_call(frame_binding,spec,graph.certificate()).status != "COMPLETED","manual child marker cannot consume parent binding")
	Domain.leave_frame(nested.frame_marker)
	if mode == "topology":
		raw.append(4)
		var denied:Dictionary = registry.admit_call(frame_binding,spec,graph.certificate())
		observe(denied.status != "COMPLETED","live raw topology drift blocks new execution")
		return denied
	if mode == "protected":
		var old = raw_private[0]
		graph.write_edge(raw_private,0,{"x":3})
		graph.write_edge(raw_private,0,old)
		var denied:Dictionary = registry.admit_call(frame_binding,spec,graph.certificate())
		observe(denied.status != "COMPLETED" and graph.ledger().size() == 2,"protected identity change then back remains revoked")
		return denied
	if mode == "unknown":
		var denied:Dictionary = registry.admit_call(frame_binding,spec,graph.certificate())
		observe(denied.status != "COMPLETED","unknown callback closure cannot get permit")
		return denied
	if mode == "registry_recursive":
		reentry_enabled = true
		var denied:Dictionary = registry.admit_call(frame_binding,spec,graph.certificate())
		observe(denied.status == "FAULT" and reentry_result.get("reason") == "recursive_capability_validation","registry recursion is rejected without swallowed outer success")
		return denied
	var admitted:Dictionary = registry.admit_call(frame_binding,spec,graph.certificate())
	observe(admitted.status == "COMPLETED","EXECUTE C admission under exact real Core marker")
	if admitted.status != "COMPLETED": return admitted
	execute_admission = admitted.admission
	observe(registry.validate_admission({"status":"COMPLETED"},frame_binding,spec).status != "COMPLETED","same-shaped admission rejected")
	observe(registry.validate_admission(RefCounted.new(),frame_binding,spec).status != "COMPLETED","opaque foreign handle rejected")
	var stranger = Registry.new()
	observe(stranger.validate_admission(execute_admission,frame_binding,spec).status != "COMPLETED","cross-registry admission rejected")
	observe(stranger.admit_call(frame_binding,spec,graph.certificate()).status != "COMPLETED","cross-registry registration rejected")
	wrong = spec.duplicate(false); wrong.arguments = arguments.duplicate(false)
	observe(registry.validate_admission(execute_admission,frame_binding,wrong).status != "COMPLETED","same-shaped argument shell rejected after signing")
	if mode == "graph_recursive": reentry_enabled = true
	var hold:Dictionary = graph.attach_execution(frame_binding,registry,execute_admission,spec)
	if mode == "graph_recursive":
		observe(hold.status == "FAULT" and reentry_result.get("reason") == "recursive_graph_authentication","graph recursion is rejected without swallowed outer success")
		return hold
	observe(hold.status != "COMPLETED","mere permit possession not active execution scope")
	observe(Random.int_in_range(10,9999) == null,"static draw without active execution scope rejected")
	var executed:Dictionary = registry.execute_random(execute_admission,frame_binding,spec)
	observe(executed.status == "COMPLETED","original static D RNG sampler genuinely executes")
	if executed.status != "COMPLETED": return executed
	samples.append(executed.value)
	observe(is_same(executed.mapped_argument,raw_private),"Graph.resolve argument uses the same memo")
	observe(is_same(graph.reverse(raw_private).value,raw),"reverse M retains original root identity")
	observe(Random.graph_stream_descriptor().backing.duplicate(false) == before_backing(),"PREPARE original L RNG backing unchanged")
	observe(registry.execute_random(execute_admission,frame_binding,spec).status != "COMPLETED","single execution permit cannot draw twice")
	return {"status":"COMPLETED","reason":""}

func before_backing() -> Dictionary:
	return owner_spec.get("baseline_rng",{})

func seal(_domain:RefCounted, original:Variant) -> Dictionary:
	var spec:Dictionary = call_spec("SEAL_CHECK")
	observe(Plan.execution_binding(domain.identity(),original).status != "COMPLETED","SEAL does not mint new Core binding")
	observe(Plan.validate_execution_binding(frame_binding,original,RefCounted.new()).status != "COMPLETED","retired FRAME rejected at SEAL")
	var admitted:Dictionary = registry.admit_call(association,spec,graph.certificate())
	if mode in ["owner_revoke","publisher_drift","rng_version_drift"]:
		observe(admitted.status != "COMPLETED","SEAL rejects invalidated reviewed closure before stage_random")
		return admitted
	observe(admitted.status == "COMPLETED","SEAL revalidates existing executed closure and association")
	if admitted.status != "COMPLETED": return admitted
	var attached:Dictionary = graph.attach_execution(association,registry,admitted.admission,spec)
	if attached.status != "COMPLETED": return attached
	observe(registry.execute_random(admitted.admission,association,spec).status != "COMPLETED","SEAL cannot execute or draw")
	var staged:Dictionary = graph.stage_random()
	observe(staged.status == "COMPLETED","legitimate stage_random only inside SEAL")
	observe(Random.graph_stream_descriptor().backing.duplicate(false) == before_backing(),"SEAL stages without installing L RNG")
	return {"status":"COMPLETED","outbox":[]} if staged.status == "COMPLETED" else staged
