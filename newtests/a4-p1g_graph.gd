extends Node
const Domain = preload("res://scripts/system/atomic_execution_domain.gd")
var checks:int = 0
class Tripwire extends RefCounted:
	var reads:int = 0
	var hidden:int:
		get:
			reads += 1
			return 1
	func run(_value:Variant) -> void:
		reads += 100
var failures:Array = []
func check(label:String, ok:bool) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", label, " ", ok)
func _ready() -> void:
	check("plan-local GraphSession exists", ResourceLoader.exists("res://scripts/match/graph_session.gd"))
	var manifest:Dictionary = preload("res://scripts/match/rule_state.gd").support_manifest()
	check("manifest stays unknown", manifest.status == "unknown" and manifest.proof == "not_complete")
	check("manifest combines graph local view", manifest.get("local_adapters",{}).has("graph"))
	check("C0 reverse-only seam exists", CloneContext.new().has_method("reverse_rebind"))
	if ResourceLoader.exists("res://scripts/match/graph_session.gd"):
		var graph = load("res://scripts/match/graph_session.gd").new()
		var domain = Domain.new()
		check("structural graph configured", graph.configure(domain,RefCounted.new(),RefCounted.new()).status == "COMPLETED")
		var member:Dictionary = {"number":7}
		var equal_member:Dictionary = {"number":7}
		var array:Array = [member,member,equal_member]
		array.append(array)
		var root:Dictionary = {"a":array,"b":member}
		var built:Dictionary = graph.fork_raw(root)
		check("two-stage raw graph succeeds", built.status == "COMPLETED")
		if built.status == "COMPLETED":
			var private:Dictionary = built.value
			check("alias cross roots shared", is_same(private.a[0],private.b) and is_same(private.a[1],private.b))
			check("equal identities not folded", not is_same(private.a[0],private.a[2]))
			check("cycle filled after reservation", is_same(private.a[3],private.a))
			check("private identity not live", not is_same(private.b,member))
			check("reverse memo returns exact live", is_same(graph.reverse(private.b).value,member))
			if CloneContext.new().has_method("reverse_rebind"):
				check("C0 reverse seam preserves proven identity", is_same(CloneContext.reverse_rebind(graph,private.b).value,member))
			check("unknown D reference is not published", graph.reverse({}).status == "UNSUPPORTED")
			check("mutable L==D remains rejected", domain.bind_dependency(member,member).status == "REJECTED")
			check("different live cannot fold private", graph.reserve(equal_member,private.b).status == "REJECTED")
			check("protected raw edge registered", graph.protect_edge(private,"b").status == "COMPLETED")
			var old:Dictionary = private.b
			graph.write_edge(private,"b",{})
			graph.write_edge(private,"b",old)
			check("restored root identity cannot revive", is_same(private.b,old) and graph.validate_graph().status == "REJECTED")
			check("each protected write has ledger", graph.ledger().size() == 2)
			check("forged evidence cannot execute", graph.resolve(member).status != "COMPLETED")
			private.a.clear()
		array.clear()
		root.clear()
		graph.close()
		var leaf_graph = load("res://scripts/match/graph_session.gd").new()
		var lifecycle:Dictionary = GameData.reset_game_session([])
		leaf_graph.configure(Domain.new(),RefCounted.new(),lifecycle.context)
		var immutable:Array = [true,7,"name"]
		immutable.make_read_only()
		var leaf:Dictionary = leaf_graph.prove_immutable(immutable)
		check("recursive immutable opaque proof", leaf.status == "COMPLETED" and leaf.value is RefCounted)
		check("leaf identity preserved structurally", is_same(leaf_graph.validate_leaf(immutable,leaf.value).value,immutable))
		check("string cannot forge leaf proof", leaf_graph.validate_leaf(immutable,"supported").status == "REJECTED")
		var mutable_nested:Array = [[]]
		mutable_nested.make_read_only()
		check("shallow read-only is insufficient", leaf_graph.prove_immutable(mutable_nested).status == "UNSUPPORTED")
		var provenance:Dictionary = leaf_graph.prove_provenance(lifecycle.context)
		check("issued context retained exact", provenance.status == "COMPLETED" and is_same(leaf_graph.validate_leaf(lifecycle.context,provenance.value).value,lifecycle.context))
		check("generation service is not provenance", leaf_graph.prove_provenance(SessionGeneration).status == "UNSUPPORTED")
		var tripwire = Tripwire.new()
		var callback:Callable = Callable(tripwire,"run").bind(immutable)
		var rebuilt:Callable = Callable(callback.get_object(),callback.get_method()).bindv(callback.get_bound_arguments())
		check("callable can be rebuilt but not admitted", rebuilt == callback and leaf_graph.prove_callable(callback,RefCounted.new(),{}).status != "COMPLETED")
		var weak:WeakRef = weakref(tripwire)
		check("weak handle reconstruction is not execution proof", leaf_graph.prove_weak(weak,RefCounted.new(),{}).status != "COMPLETED")
		check("unknown getter not probed", leaf_graph.fork_raw([tripwire]).status == "UNSUPPORTED" and tripwire.reads == 0)
		check("partial inventory failure stays closed", leaf_graph.fork_raw([7]).status == "UNSUPPORTED")
		leaf_graph.close()
	print("RESULT ",JSON.stringify({"suite":"A4-P1G-Graph","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
