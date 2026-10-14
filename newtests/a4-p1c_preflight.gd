extends Node
## E2 前置诊断，不是生产能力注册者，不签 admission，不运行 setter。
## 缺 Core 公共认证时保留 RED；禁止以 current_frame/inspect 结构洗票。
const Plan = preload("res://scripts/system/atomic_action_plan.gd")
const Domain = preload("res://scripts/system/atomic_execution_domain.gd")
var checks:int = 0
var failures:Array = []

func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)

class ReadProbe extends RefCounted:
	var source:SessionContext
	var owner_domain:RefCounted
	var observed:Dictionary = {}
	func _init(context:SessionContext) -> void:
		source = context
	func validate_original_context(context:Variant) -> Dictionary:
		return {"status":"COMPLETED" if is_same(context, source) and SessionGeneration.validate_context(source).get("ok", false) else "REJECTED", "reason":"diagnostic_source_only"}
	func open_domain(domain, _context:Variant, _closure:Variant, _manifest:Dictionary) -> Dictionary:
		owner_domain = domain
		return {"status":"COMPLETED", "reason":"read_probe_no_rule_roots"}
	func prepare(domain, _closure:Variant, context:Variant) -> Dictionary:
		var real:Dictionary = Domain.current_frame()
		var inspected:Dictionary = Plan.inspect(real.plan_identity)
		observed["real"] = real.status == "COMPLETED" and inspected.state == "PREPARING" and is_same(real.original_context, context) and is_same(real.domain, domain) and is_same(domain, owner_domain)
		# 同一真实 P/D/context 仍能 public enter 手工嵌套；不可自动追认。
		var nested:Dictionary = domain.enter_frame(real.plan_identity, context)
		observed["nested_entered"] = nested.status == "COMPLETED"
		if nested.status == "COMPLETED":
			var manual:Dictionary = Domain.current_frame()
			var manual_inspect:Dictionary = Plan.inspect(manual.plan_identity)
			observed["same_public_association"] = is_same(manual.plan_identity, real.plan_identity) and is_same(manual.domain, real.domain) and is_same(manual.original_context, real.original_context) and manual_inspect.state == "PREPARING"
			observed["different_marker"] = not is_same(manual.marker, real.marker)
			observed["manual_entry_rejected"] = not BaseFunc.interpreter_entry_status("array_length").get("ok", false)
			observed["manual_left"] = Domain.leave_frame(nested.frame_marker).status == "COMPLETED"
			observed["real_restored"] = is_same(Domain.current_frame().marker, real.marker)
		return {"status":"REJECTED", "reason":"missing_core_execution_binding_no_admission_issued"}
	func resume(_domain, _owned:Variant, _input:Variant, _context:Variant) -> Dictionary:
		return {"status":"REJECTED", "reason":"diagnostic_has_no_continuation"}
	func seal(_domain, _context:Variant) -> Dictionary:
		return {"status":"REJECTED", "reason":"diagnostic_never_publishes"}

func _ready() -> void:
	var reset:Dictionary = GameData.reset_game_session([0, 1])
	check(reset.get("ok", false), "PRE real lifecycle source")
	if not reset.get("ok", false):
		finish()
		return
	var source:SessionContext = reset.context
	check(SessionGeneration.validate_context(source).get("ok", false), "PRE issued original context")
	var library:Dictionary = GameData.player_data_library
	var member:Dictionary = library[0]
	var location:Variant = member.location
	var magic:Variant = member.magic.number
	var facts:Array = GameLog.query({}, null)
	var script:Script = Plan
	check(script.has_method("execution_binding"), "E2 Core must implement execution_binding before C admission")
	check(script.has_method("validate_execution_binding"), "E2 Core must implement validate_execution_binding before C admission")
	check(LoadHelper.registered_script("array_length") != null, "PRE exact registered interpreter inventory")
	BaseFunc.seal_capability_domain()
	check(not BaseFunc.interpreter_entry_status("array_length").get("ok", false), "sealed entry without admission remains rejected")
	check(not BaseFunc.interpreter_entry_status("unregistered_probe").get("ok", false), "exact registration gate remains prior to sealed gate")
	var op:RefCounted = LoadHelper.registered_script("array_length").new()
	check(not BaseFunc._callable_capability_valid(Callable(op, "exec"), []), "sealed Callable without admission remains rejected")
	var probe:ReadProbe = ReadProbe.new(source)
	# P0 的固定字符串是既有 manifest 接线格式；不是图/执行能力 proof。
	var registered:Dictionary = Plan.register_participant_manifest({"adapter":probe, "support_manifest":{
		"abi_version":1, "status":"supported", "proof":"owner_registered_closed_domain",
		"required_roots":["diagnostic_reads_only"], "required_adapters":["read_probe"],
		"state_domains":["diagnostic"], "participants":["read_probe_not_production"]}})
	check(registered.status == "COMPLETED", "PRE P0 diagnostic participant registration")
	var created:Dictionary = Plan.begin(source, {"kind":"diagnostic_reads_only"}, registered.participant_manifest)
	check(created.status == "COMPLETED" and created.state == "NEW", "PRE real P0 plan identity")
	var result:Dictionary = Plan.prepare(created.plan_identity)
	check(probe.observed.get("real", false), "PRE actual Core prepare frame")
	check(probe.observed.get("nested_entered", false), "public Domain can create manual nested frame")
	check(probe.observed.get("same_public_association", false), "manual frame passes same public P D context state association")
	check(probe.observed.get("different_marker", false), "manual marker is distinct and cannot inherit Core authority")
	check(probe.observed.get("manual_entry_rejected", false), "manual matching frame does not unlock sealed entry")
	check(probe.observed.get("manual_left", false) and probe.observed.get("real_restored", false), "manual frame leaves cleanly and restores real frame")
	check(result.status == "REJECTED" and result.state == "ABORTED", "missing proof explicitly aborts diagnostic plan")
	check(result.reason == "missing_core_execution_binding_no_admission_issued", "specific missing Core binding reason retained")
	check(result.receipt.state != "COMMITTED", "no certification outcome is a committed action")
	check(Domain.current_frame().status == "REJECTED" and not Domain.publication_is_open(), "diagnostic exits all frames without publication window")
	check(is_same(GameData.player_data_library, library) and is_same(library[0], member) and is_same(member.location, location) and member.magic.number == magic, "no live identity position or payment mutation")
	check(GameLog.query({}, null) == facts, "no live action facts published")
	check(SessionGeneration.validate_context(source).get("ok", false), "original source not refreshed revoked or rebound")
	var env:Dictionary = {"user":OS.get_user_data_dir()}
	for key in ["TMPDIR", "TEMP", "TMP", "APPDATA", "LOCALAPPDATA"]: env[key] = OS.get_environment(key)
	print("ENV_DETAIL ", JSON.stringify(env))
	finish()

func finish() -> void:
	print("RESULT ", JSON.stringify({"checks":checks, "failures":failures, "suite":"a4-p1c_preflight"}))
	get_tree().quit(0 if failures.is_empty() else 1)
