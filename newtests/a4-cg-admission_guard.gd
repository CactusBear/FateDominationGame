extends Node
const Plan = preload("res://scripts/system/atomic_action_plan.gd")
const Domain = preload("res://scripts/system/atomic_execution_domain.gd")
const Graph = preload("res://scripts/match/graph_session.gd")
const Registry = preload("res://scripts/system/atomic_setter_registry.gd")
const Random = preload("res://scripts/match/rule_random.gd")
const Participant = preload("res://newtests/a4-cg-admission_participant.gd")
# 明示受审精确 Script→源文本对应；不是按 tests 路径或运行时新算摘要自动批准。
const REVIEW_SHA:Dictionary = {
	preload("res://scripts/system/atomic_setter_registry.gd"):"3480992bdd5c5085374a9b83a54bb9fce4237991bc134bca46b2bf5ab6583e16",
	preload("res://scripts/match/graph_session.gd"):"a9d4c072ff70ce4478413d396c3399f27a7d41d7177fcab894cb4b0336f0d261",
	preload("res://scripts/match/rule_random.gd"):"86e47ebb55b6de72c5e5faf464371742398eeb9844c3eb549ce5566590038acf",
	preload("res://scripts/system/atomic_action_plan.gd"):"c609fe36f7ccd8c23e1ee5fed7b2ce2dcc5bc95aa3fddf4be2cfcfadcf1ca523",
	preload("res://scripts/system/atomic_execution_domain.gd"):"b4be734cc4663341fec9facbad951daced0fa2898f8137cc4546f588b2b01b1e",
	preload("res://scripts/system/session_generation.gd"):"f21c8f10ee8669d1f69092a40019d5cfec153e523f6d174eb57e9129e69f4914",
	preload("res://scripts/system/session_context.gd"):"6d3cf9f9f9dcabad88d1dd26062cf53d26a4cefdcdaf9cea3f64b9bcb7384046",
	preload("res://scripts/system/session_token.gd"):"0b0a87d17d29c2afe72008bd03495189f036c39ddd4d7073dcbb6368ae65d48a",
	preload("res://newtests/a4-cg-admission_participant.gd"):"9c1e4b6f92d00ec93a298bd3e09e26b608af7282b0d99da530ee405eb4e000f4",
}
var checks:int = 0
var failures:Array = []
var callback_calls:int = 0
func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ",label," ",ok)
	if not ok: failures.append(label)
func unknown_callback() -> void:
	callback_calls += 1
func drain(p:RefCounted) -> void:
	for entry in p.observations: check(entry[0],p.mode+": "+entry[1])
	p.observations.clear()

func create(mode:String = "success"):
	var p = Participant.new()
	p.mode = mode
	if mode == "unknown": p.raw.append(Callable(self,"unknown_callback"))
	p.arguments = [10,9999,p.raw]
	p.before = Random.snapshot()
	var versions:Array = []
	for script in REVIEW_SHA:
		var text:String = script.get_source_code()
		check(text.sha256_text() == REVIEW_SHA[script],"audited runtime source correspondence "+script.resource_path)
		if text.sha256_text() != REVIEW_SHA[script]: return null
		versions.append({"script":script,"reviewed_source":text,"source_sha256":REVIEW_SHA[script]})
	var chain:Array = []
	var script:Script = Random
	while script != null:
		chain.append(script); script = script.get_base_script()
	var stream:Dictionary = Random.graph_stream_descriptor()
	var manifest:Dictionary = Plan.register_participant_manifest({"adapter":p,"support_manifest":{"abi_version":1,"status":"supported","proof":"owner_registered_closed_domain","required_roots":[&"raw_arguments",&"random_stream"],"required_adapters":[&"G_raw_RNG_E3"],"state_domains":[&"D"],"participants":[&"finite_raw_RNG_probe"],"source_validation":{"abi_version":1,"read_only":true,"validator_script":Participant}}})
	p.manifest = manifest.participant_manifest
	p.owner_spec = {"target_script":Random,"source_sha256":REVIEW_SHA[Random],"inheritance_chain":chain,"native_base":(Random as Script).get_instance_base_type(),"property_or_method":{"kind":"method","name":&"int_in_range","parameters":[TYPE_INT,TYPE_INT],"return":TYPE_INT},"receiver":Random,"adapter":p,"adapter_script":Participant,"abi_version":1,"prepare_kind":"domain_service","participants":[p],"participant_manifest":p.manifest,"readable_roots":[{"name":&"raw_arguments","identity":p.raw,"mutable":true,"version":1},{"name":&"random_stream","identity":stream.identity,"mutable":true,"version":1}],"writable_roots":[{"name":&"random_stream","identity":stream.identity,"domain":"D","version":1}],"publish_adapter":{"abi_version":1,"mechanism":&"G_stage_random_Core_raw_slots","callback_free":true},"mechanism":Registry.MECHANISM,"reviewed_versions":versions,"native_version":Engine.get_version_info(),"baseline_rng":stream.backing.duplicate(false)}
	p.registry = Registry.new([{"owner":p,"spec":p.owner_spec}])
	var registered:Dictionary = p.registry.register_owner(p,p.owner_spec)
	check(registered.status == "COMPLETED","reviewed owner exact registration")
	if registered.status != "COMPLETED":
		print("REGISTRATION_DIAGNOSTIC ",registered)
		return null
	p.registration = registered.owner_registration
	check(p.registry.register_owner(RefCounted.new(),p.owner_spec).status != "COMPLETED","fake owner cannot register")
	check(Registry.new().register_owner(p,p.owner_spec).status != "COMPLETED","field-complete spec cannot self-approve on another registry")
	var missing:Dictionary = p.owner_spec.duplicate(false)
	missing.erase("publish_adapter")
	check(p.registry.register_owner(p,missing).status != "COMPLETED","missing publisher cannot register")

	return p

func cleanup(p:RefCounted) -> void:
	p.registry.close()
	if p.graph != null: p.graph.close()
	p.owner_spec.clear()
	p.previous_spec.clear()
	p.arguments.clear()
	p.raw.clear()

func begin(p:RefCounted, context:Variant) -> Dictionary:
	var started:Dictionary = Plan.begin(context,{},p.manifest)
	p.plan = started.plan_identity
	return started

func positive(context:Variant, pending:bool) -> void:
	Random.start_seed(719)
	var expected = Random.fork_scope()
	var first:Variant = expected.int_in_range(10,9999)
	var second:Variant = expected.int_in_range(10,9999) if pending else null
	var next:Variant = expected.int_in_range(10,9999)
	var p = create("pending" if pending else "success")
	if p == null: return
	begin(p,context)
	var prepared:Dictionary = Plan.prepare(p.plan)
	drain(p)
	check(prepared.status == ("PENDING" if pending else "COMPLETED"),"real Core prepare reaches intended state")
	if prepared.status not in ["PENDING","COMPLETED"]:
		print("PREPARE_DIAGNOSTIC ",prepared)
		cleanup(p)
		return
	check(Random.snapshot() == p.before,"L RNG unchanged after PREPARE")
	check(p.samples.size() == 1 and p.samples[0] == first,"first original D draw matches declared real sequence")
	check(p.registry.validate_admission(p.execute_admission,p.frame_binding,p.call_spec("EXECUTE")).status != "COMPLETED","retired permit cannot execute outside frame")
	check(p.graph.stage_random().status != "COMPLETED","stage_random outside SEAL refused")
	var premature:Dictionary = p.registry.admit_call(p.association,p.call_spec("SEAL_CHECK"),p.graph.certificate())
	check(premature.status != "COMPLETED","SEAL permit cannot be issued in PREPARED or PENDING")
	if premature.status == "COMPLETED":
		var attached:Dictionary = p.graph.attach_execution(p.association,p.registry,premature.admission,p.call_spec("SEAL_CHECK"))
		check(attached.status != "COMPLETED" or p.graph.stage_random().status != "COMPLETED","phase withdrawal must not permit actual premature staging")
	if pending:
		var resumed:Dictionary = Plan.resume(p.plan,p.continuation,context)
		drain(p)
		check(resumed.status == "COMPLETED","real RESUME new Core marker executes")
		if resumed.status != "COMPLETED":
			cleanup(p); return
		check(p.samples.size() == 2 and p.samples[1] == second,"RESUME uses existing private stream without rerun")
		check(Random.snapshot() == p.before,"L RNG unchanged after RESUME")
	var committed:Dictionary = Plan.commit(p.plan)
	drain(p)
	check(committed.status == "COMPLETED" and committed.get("state") == "COMMITTED","original Core commit is sole publication point")
	if committed.get("state") != "COMMITTED":
		print("COMMIT_DIAGNOSTIC ",committed)
		cleanup(p)
		return
	check(is_same(committed.receipt,Plan.inspect(p.plan).receipt),"true preserved commit receipt identity")
	var installed:Dictionary = Random.snapshot()
	check(is_same(Plan.commit(p.plan).receipt,committed.receipt) and Random.snapshot() == installed,"commit replay neither draws nor installs twice")
	check(Random.int_in_range(10,9999) == next,"next L sampler hydrates committed E3 terminal sequence")
	check(p.graph.validate_certificate(p.graph.certificate()).status != "COMPLETED","terminal graph association cannot revive")
	cleanup(p)

func negative(context:Variant, mode:String) -> void:
	Random.start_seed(719)
	var p = create(mode)
	if p == null: return
	begin(p,context)
	var outcome:Dictionary = Plan.prepare(p.plan)
	drain(p)
	check(outcome.status != "COMPLETED" and outcome.get("state") == ("FAULT" if mode in ["registry_recursive","graph_recursive"] else "ABORTED"),mode+": whole plan rejected before sampler")
	check(p.samples.is_empty() and Random.snapshot() == p.before,mode+": no D sampler and no L RNG write")
	check(callback_calls == 0,mode+": first unknown callback never invoked")
	cleanup(p)

func _ready() -> void:
	var reset:Dictionary = GameData.reset_game_session([])
	check(reset.ok,"issued original source from existing session lifecycle")
	if not reset.ok:
		finish(); return
	var context:Variant = reset.context
	positive(context,false)
	positive(context,true)
	for mode in ["topology","protected","unknown","registry_recursive","graph_recursive"]: negative(context,mode)
	for fault in ["owner_revoke","publisher_drift","rng_version_drift"]:
		Random.start_seed(719)
		var candidate = create(fault)
		if candidate == null: continue
		begin(candidate,context)
		var prepared_fault:Dictionary = Plan.prepare(candidate.plan)
		drain(candidate)
		check(prepared_fault.status == "COMPLETED",fault+": actual prepared closure exists")
		match fault:
			"owner_revoke": candidate.registry.revoke_owner(candidate.registration)
			"publisher_drift": candidate.owner_spec.publish_adapter = {}
			"rng_version_drift": Random.int_in_range(10,9999)
		var current_live:Dictionary = Random.snapshot()
		var refused:Dictionary = Plan.commit(candidate.plan)
		drain(candidate)
		check(refused.status != "COMPLETED" and Random.snapshot() == current_live,fault+": reject before L install")
		cleanup(candidate)
	Random.start_seed(719)
	var p = create()
	if p != null:
		begin(p,context)
		var prepared:Dictionary = Plan.prepare(p.plan)
		drain(p)
		check(prepared.status == "COMPLETED","source rollover probe genuinely prepared")
		var old:Dictionary = Random.snapshot()
		SessionGeneration.begin_generation(&"external-rollover")
		var committed:Dictionary = Plan.commit(p.plan)
		drain(p)
		check(committed.status != "COMPLETED" and Random.snapshot() == old,"external source generation rollover rejects before installation")
		cleanup(p)
	BaseFunc.seal_capability_domain()
	check(not BaseFunc.interpreter_entry_status(&"set_property").ok,"existing sealed rule entry stays closed")
	finish()
func finish() -> void:
	print("RESULT ",JSON.stringify({"suite":"a4-cg-admission","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
