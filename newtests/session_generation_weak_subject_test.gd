extends Node

const SG = preload("res://scripts/system/session_generation.gd")
var checks:int = 0
var failures:Array[String] = []

func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value:
		failures.append(label)

func rejected(result:Dictionary, reason:StringName, label:String) -> void:
	check(result == {"ok":false, "context":null, "reason":reason}, label)
	check(not SG.validate_context(result.context).ok, label + " no usable context")

func _ready() -> void:
	var generation:Dictionary = SG.begin_generation(&"weak_subject_test.first")
	check(generation.ok, "public begin succeeds")
	var token:SessionToken = generation.token
	var actual:Object = Object.new()
	var first:WeakRef = weakref(actual)
	var second:WeakRef = weakref(actual)
	var bound:Dictionary = SG.bind_origin(first, token, &"test.weak")
	check(bound.ok and bound.context != null, "live wrapper bind succeeds")
	check(SG.validate_context(bound.context).ok, "live wrapper context validates")
	var direct:Dictionary = SG.origin_of(actual)
	var wrapped:Dictionary = SG.origin_of(first)
	check(direct.ok and is_same(direct.context, bound.context), "actual query returns bound context")
	check(wrapped.ok and is_same(wrapped.context, bound.context), "wrapper query returns bound context")
	var again:Dictionary = SG.bind_origin(second, token, &"test.weak")
	check(again.ok and is_same(again.context, bound.context), "two wrappers same actual idempotent")
	var direct_bind:Dictionary = SG.bind_origin(actual, token, &"test.weak")
	check(direct_bind.ok and is_same(direct_bind.context, bound.context), "actual after wrapper bind idempotent")
	rejected(SG.bind_origin(second, token, &"test.other"), &"origin_rebind_denied", "different origin cannot rebind actual through wrapper")
	first = null
	second = null
	check(is_same(SG.origin_of(actual).context, bound.context), "wrapper release retains actual binding")

	var never_bound:Object = Object.new()
	var dead:WeakRef = weakref(never_bound)
	never_bound.free()
	check(dead.get_ref() == null, "unbound target actually died")
	rejected(SG.bind_origin(dead, token, &"test.dead"), &"unbound_origin", "dead unbound target rejected")
	rejected(SG.origin_of(dead), &"unbound_origin", "dead target query unbound")
	rejected(SG.derive_context(dead, &"test.dead.child"), &"unbound_origin", "dead target cannot derive")

	var doomed:Object = Object.new()
	var doomed_wrapper:WeakRef = weakref(doomed)
	var doomed_bound:Dictionary = SG.bind_origin(doomed_wrapper, token, &"test.doomed")
	check(doomed_bound.ok, "live doomed wrapper initially binds")
	doomed.free()
	check(doomed_wrapper.get_ref() == null, "bound target actually died")
	rejected(SG.bind_origin(doomed_wrapper, token, &"test.doomed"), &"unbound_origin", "dead previously bound target rejected")
	rejected(SG.origin_of(doomed_wrapper), &"unbound_origin", "dead bound target query unbound")

	var ordinary:Object = Object.new()
	var ordinary_bound:Dictionary = SG.bind_origin(ordinary, token, &"test.ordinary")
	check(ordinary_bound.ok and SG.validate_context(ordinary_bound.context).ok, "ordinary Object binding works")
	check(is_same(SG.origin_of(ordinary).context, ordinary_bound.context), "ordinary Object query works")
	var next:Dictionary = SG.begin_generation(&"weak_subject_test.next")
	check(next.ok and not is_same(next.token, token), "public begin rotates token")
	var replacement:WeakRef = weakref(actual)
	rejected(SG.bind_origin(replacement, next.token, &"test.weak"), &"origin_rebind_denied", "fresh wrapper cannot wash live old actual")
	rejected(SG.origin_of(actual), &"stale_session", "old actual query remains stale")
	rejected(SG.origin_of(replacement), &"stale_session", "replacement wrapper query remains stale")
	check(not SG.validate_context(bound.context).ok, "old bound context remains stale")
	rejected(SG.bind_origin(ordinary, next.token, &"test.ordinary"), &"origin_rebind_denied", "ordinary old Object cannot rebind")
	var fresh:Object = Object.new()
	var fresh_wrapper:WeakRef = weakref(fresh)
	var fresh_bound:Dictionary = SG.bind_origin(fresh_wrapper, next.token, &"test.weak")
	check(fresh_bound.ok and SG.validate_context(fresh_bound.context).ok, "new actual new generation accepted")
	check(is_same(SG.origin_of(fresh).context, fresh_bound.context), "new actual query returns new context")
	check(is_same(SG.origin_of(fresh_wrapper).context, fresh_bound.context), "new wrapper query returns new context")
	actual.free()
	ordinary.free()
	fresh.free()
	SG.invalidate_generation(&"weak_subject_test.done")
	print("RESULT ", JSON.stringify({"suite":"session_generation_weak_subject", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
