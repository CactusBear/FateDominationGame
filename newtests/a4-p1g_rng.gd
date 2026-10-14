extends Node
const RNG = preload("res://scripts/match/rule_random.gd")
const Domain = preload("res://scripts/system/atomic_execution_domain.gd")
const Graph = preload("res://scripts/match/graph_session.gd")
const Plan = preload("res://scripts/system/atomic_action_plan.gd")
class RawPublicationProbe extends RefCounted:
	var graph:RefCounted
	func _init(value:RefCounted) -> void: graph = value
	func validate_original_context(context:Variant) -> Dictionary:
		return {"status":"COMPLETED" if SessionGeneration.validate_context(context).ok else "REJECTED","reason":""}
	func open_domain(_domain,_context:Variant,_closure:Variant,_manifest:Dictionary) -> Dictionary:
		return {"status":"COMPLETED","reason":""}
	func prepare(_domain,_closure:Variant,_context:Variant) -> Dictionary:
		return {"status":"COMPLETED","reason":""}
	func resume(_domain,_continuation:Variant,_input:Variant,_context:Variant) -> Dictionary:
		return {"status":"REJECTED","reason":"no_continuation"}
	func seal(domain,_context:Variant) -> Dictionary:
		# 仅诊断有限 RNG raw 载体，不登记规则/Callable 闭包，也不充当生产聚合 adapter。
		var described:Dictionary = graph.random_publication_writes()
		if described.status != "COMPLETED": return described
		for write in described.value:
			var staged:Dictionary = domain.stage_slot(write.target,write.key,write.value,write.kind)
			if staged.status != "COMPLETED": return staged
		return {"status":"COMPLETED","reason":"","outbox":[]}
var checks:int = 0
var failures:Array = []
func check(label:String, ok:bool) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", label, " ", ok)
func _ready() -> void:
	RNG.start_seed(987654321)
	var initial:Dictionary = RNG.snapshot()
	var scope = RNG.fork_scope()
	check("version API exists", scope.has_method("stream_version"))
	if scope.has_method("stream_version"):
		var v:int = scope.stream_version()
		var before:Dictionary = scope.snapshot()
		scope.int_in_range(0, 100)
		scope.restore(before)
		check("consume restore monotonically invalidates", scope.stream_version() > v)
	var domain = Domain.new()
	var entered:Dictionary = domain.enter_frame(RefCounted.new(), RefCounted.new())
	check("manual frame cannot sample live static", RNG.int_in_range(0, 100) == null)
	check("manual frame cannot claim known live static", not RNG.is_known())
	var untouched:Array = [1,2,3]
	check("manual frame cannot shuffle live input", not RNG.shuffle(untouched) and untouched == [1,2,3])
	check("manual frame cannot pick live reference", RNG.pick(untouched) == null)
	check("manual frame cannot sample float", RNG.float_in_range(0,1) == null)
	check("manual frame cannot fork live static", RNG.fork_scope() == null)
	check("manual frame cannot borrow explicit scope", scope.int_in_range(0,100) == null and RNG.fork_scope(scope) == null)
	check("manual frame cannot restore scopes", not RNG.restore_scope(scope,initial))
	check("manual frame cannot restore static", not RNG.restore(initial))
	check("manual frame cannot change mode", not RNG.set_capability_mode("none"))
	RNG.declare_capability({"mode":"known_stream","seed":42,"state":43})
	RNG.stop_tracking()
	RNG.start_seed(42)
	Domain.leave_frame(entered.frame_marker)
	check("manual reseed never touches live", RNG.snapshot() == initial)
	var expected:RandomNumberGenerator = RandomNumberGenerator.new()
	expected.seed = initial.seed.to_int()
	expected.state = initial.state.to_int()
	for index in range(32):
		check("native int sequence %d" % index, RNG.int_in_range(-19,93) == expected.randi_range(-19,93))
		check("native float sequence %d" % index, RNG.float_in_range(-2.5,8.25) == expected.randf_range(-2.5,8.25))
	check("raw terminal equals native real state", RNG.snapshot().state == str(expected.state))
	var lifecycle:Dictionary = GameData.reset_game_session([])
	RNG.start_seed(987654321)
	var graph = Graph.new()
	graph.configure(Domain.new(),RefCounted.new(),lifecycle.context)
	var descriptor:Dictionary = RNG.graph_stream_descriptor()
	var forked:Dictionary = graph.fork_stream(descriptor)
	check("same-flow memo initial structural fork", forked.status == "COMPLETED")
	if forked.status == "COMPLETED":
		var private_scope = forked.value
		check("same-flow memo aliases one scope", is_same(private_scope,graph.fork_stream(descriptor).value))
		var unchanged:Dictionary = RNG.snapshot()
		private_scope.int_in_range(0,100)
		private_scope.float_in_range(0,1)
		var terminal:Dictionary = private_scope.snapshot()
		check("independent structural sample never advances live", RNG.snapshot() == unchanged)
		check("separate native caches", not is_same(descriptor.native_cache,private_scope.graph_stream_descriptor().native_cache))
		check("private stream reverse exact identity", is_same(graph.reverse(private_scope).value,descriptor.identity))
		var private_native = descriptor.native_cache
		var before_version:int = RNG.stream_version()
		var manifest:Dictionary = {"abi_version":1,"status":"supported","proof":"owner_registered_closed_domain","required_roots":["random_diagnostic"],"required_adapters":["finite_rng_raw_probe"],"state_domains":["runtime"],"participants":["diagnostic_only"]}
		var registered:Dictionary = Plan.register_participant_manifest({"adapter":RawPublicationProbe.new(graph),"support_manifest":manifest})
		var started:Dictionary = Plan.begin(lifecycle.context,{},registered.participant_manifest)
		var prepared:Dictionary = Plan.prepare(started.plan_identity)
		check("raw-carrier probe prepared zero live writes", prepared.state == "PREPARED" and RNG.snapshot() == unchanged)
		var committed:Dictionary = Plan.commit(started.plan_identity)
		check("raw-carrier probe single COMMITTED receipt", committed.state == "COMMITTED" and is_same(committed.receipt,Plan.inspect(started.plan_identity).receipt))
		check("E3 authority installs real computed native terminal", RNG.snapshot() == terminal)
		check("commit preserves stream/cache identities", is_same(RNG.graph_stream_descriptor().identity,descriptor.identity) and is_same(RNG.graph_stream_descriptor().native_cache,private_native))
		check("commit increments live version once", RNG.stream_version() == before_version+1)
		Plan.commit(started.plan_identity)
		check("receipt replay consumes no second draw", RNG.stream_version() == before_version+1 and RNG.snapshot() == terminal)
		expected.seed = terminal.seed.to_int()
		expected.state = terminal.state.to_int()
		check("next sampler hydrates same original native cache", RNG.int_in_range(0,1000) == expected.randi_range(0,1000))
		check("E3 cache catches authoritative state before use", str(private_native.state) == RNG.snapshot().state)
	graph.close()
	RNG.start_seed(222)
	var version_graph = Graph.new()
	version_graph.configure(Domain.new(),RefCounted.new(),lifecycle.context)
	var saved:Dictionary = RNG.snapshot()
	check("version baseline opens", version_graph.fork_stream(RNG.graph_stream_descriptor()).status == "COMPLETED")
	RNG.int_in_range(0,100)
	RNG.restore(saved)
	check("state roundtrip stays invalidated by version", RNG.snapshot() == saved and version_graph.validate_graph().status == "REJECTED")
	version_graph.close()
	var equal_scope_a = RNG.fork_scope()
	var equal_scope_b = RNG.fork_scope()
	var explicit_graph = Graph.new()
	explicit_graph.configure(Domain.new(),RefCounted.new(),lifecycle.context)
	var explicit_a:Dictionary = explicit_graph.fork_stream(equal_scope_a.graph_stream_descriptor())
	var explicit_b:Dictionary = explicit_graph.fork_stream(equal_scope_b.graph_stream_descriptor())
	check("equal-state streams stay different identities", explicit_a.status == "COMPLETED" and explicit_b.status == "COMPLETED" and not is_same(explicit_a.value,explicit_b.value))
	check("explicit scope aliases reuse same M", is_same(explicit_a.value,explicit_graph.fork_stream(equal_scope_a.graph_stream_descriptor()).value))
	explicit_graph.close()
	var exhausted = RNG.fork_scope()
	var exhaustion:Dictionary = exhausted.graph_stream_descriptor()
	exhaustion.backing.version = RNG.MAX_VERSION
	var exhaustion_state:Dictionary = exhausted.snapshot()
	check("version exhaustion refuses sample without wrapping", exhausted.int_in_range(0,100) == null and exhausted.stream_version() == RNG.MAX_VERSION)
	check("version exhaustion refuses restore", not exhausted.restore(exhaustion_state) and exhausted.stream_version() == RNG.MAX_VERSION)
	RNG.stop_tracking()
	for items in [[],[1],[1,2,3]]:
		var before:Array = items.duplicate()
		check("unknown shuffle rejects every size", not RNG.shuffle(items) and items == before)
	check("unknown never forks a fabricated seed", RNG.fork_scope() == null)
	print("RESULT ", JSON.stringify({"suite":"A4-P1G-RNG", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
