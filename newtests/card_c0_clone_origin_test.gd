extends Node

var checks:int = 0
var failures:Array = []

class LateReject extends RefCounted:
	func clone_data(context):
		context.reject(&"injected_late_failure")
		return null

class TypedCarrier extends RefCounted:
	var items:Array = []
	func clone_data(context):
		var cloned := TypedCarrier.new()
		cloned.items = context.copy(items)
		return cloned

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func cards() -> Array:
	return [BaseCard.new(), BaseHandCard.new(), BaseAttack.new("attack", "", []), BaseSkill.new("skill", "", []), BaseEvent.new("event", ""), BaseSituation.new("situation", "")]

func start_source(label:StringName) -> SessionContext:
	var generation:Dictionary = SessionGeneration.begin_generation(label)
	return SessionGeneration.derive_context(generation.token, label).context

func bind(subject:Object, source:SessionContext) -> void:
	var result:Dictionary = SessionGeneration.bind_origin(subject, source.token(), source.origin())
	check(result.ok, "fixture_bind")
	if subject is BaseEffect or subject is BaseFunc:
		check(subject.bind_runtime_context(result.context), "fixture_runtime_bind")

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	print("ENV user=", OS.get_user_data_dir())
	for key in ["TMPDIR", "TEMP", "TMP", "APPDATA", "LOCALAPPDATA"]:
		check(OS.get_environment(key).begins_with("E:"), "environment_" + key)
	var source:SessionContext = start_source(&"C0.original")
	var unbound:Array = cards()
	for index in range(unbound.size()):
		var before:int = GameData.objects.size()
		var clone = CloneContext.new().copy(unbound[index])
		check(clone == null, "unbound_reject_%d" % index)
		check(GameData.objects.size() == before, "unbound_no_allocation_%d" % index)
	var runtime:Array = cards()
	for index in range(runtime.size()):
		bind(runtime[index], source)
		var clone = CloneObject.new().exec(runtime[index])
		check(clone != null and not is_same(clone, runtime[index]), "same_session_clone_%d" % index)
		var inherited:Dictionary = SessionGeneration.origin_of(clone)
		check(inherited.ok and inherited.context.origin() == source.origin() and is_same(inherited.context.token(), source.token()), "same_session_origin_%d" % index)
		var direct = runtime[index].clone_data(CloneContext.new())
		check(direct != null and SessionGeneration.origin_of(direct).ok, "direct_clone_origin_%d" % index)
	var parent:BaseEvent = runtime[4]
	parent._attached_cards = [unbound[0]]
	var before:int = GameData.objects.size()
	check(CloneContext.new().copy(parent) == null, "nested_unbound_reject")
	check(GameData.objects.size() == before, "nested_unbound_no_half_object")
	parent._attached_cards = []
	before = GameData.objects.size()
	var mixed = CloneContext.new().copy([runtime[4], unbound[4]])
	check(mixed == null or (mixed is Array and mixed.is_empty()), "array_failure_not_null_filled")
	check(GameData.objects.size() == before, "array_preflight_no_partial")
	var new_source:SessionContext = start_source(&"C0.new")
	for index in range(runtime.size()):
		before = GameData.objects.size()
		check(CloneObject.new().exec(runtime[index]) == null, "stale_reject_%d" % index)
		check(GameData.objects.size() == before, "stale_no_allocation_%d" % index)
	var number := BaseNumber.new(7)
	var pure = CloneObject.new().exec({"number":number, "array":[1, null, {"text":"same"}]})
	check(pure is Dictionary and pure.number is BaseNumber and pure.number.number == 7 and not is_same(pure.number, number) and pure.array == [1, null, {"text":"same"}], "pure_values_preserved")
	var buff := BaseBuff.new("ordinary", "")
	check(CloneObject.new().exec(buff) is BaseBuff, "noncard_unbound_preserved")
	var ctx := CloneContext.new()
	check(ctx.has_method("copy_result") and ctx.has_method("configure_template"), "frozen_ABI_present")
	if ctx.has_method("copy_result") and ctx.has_method("configure_template"):
		var foreign:Dictionary = ctx.call("copy_result", runtime[4], new_source)
		check(not foreign.ok and foreign.object == null and foreign.reason == &"stale_session", "new_context_cannot_wash_old")
		var factory := CloneContext.new()
		check(factory.call("configure_template", new_source, unbound), "explicit_template_factory")
		var result:Dictionary = factory.call("copy_result", unbound)
		check(result.ok and result.object.size() == 6, "six_template_runtime_classes")
		if result.ok:
			for card in result.object:
				check(SessionGeneration.origin_of(card).ok, "template_clone_bound")
		for card in unbound:
			check(SessionGeneration.origin_of(card).reason == &"unbound_origin", "template_unchanged")
		var denied := CloneContext.new()
		check(not denied.call("configure_template", new_source, runtime), "old_runtime_in_template_pool_rejected")
		var empty:Dictionary = CloneContext.new().call("copy_result", null)
		check(empty.ok and empty.object == null, "legal_null_distinguished")
		var trusted := BaseEvent.new("trusted", "")
		var attached := BaseSituation.new("attached", "")
		trusted._attached_cards = [attached]
		var effect := BaseEffect.new("copy-effect", [])
		var op := preload("res://scripts/system/operations/EditScore.gd").new()
		var func_data := BaseFunc.new(Callable(op, "exec"), [0, BaseNumber.new(0)])
		effect._funcs = [func_data]
		trusted._effects = [effect]
		factory = CloneContext.new()
		check(factory.call("configure_template", new_source, [trusted]), "nested_template_setup")
		result = factory.call("copy_result", trusted, new_source)
		check(result.ok, "nested_template_runtime")
		if result.ok:
			var event:BaseEvent = result.object
			check(SessionGeneration.origin_of(event._attached_cards[0]).ok, "nested_card_origin")
			check(event._effects[0].runtime_source_status().ok and event._effects[0]._funcs[0].runtime_source_status().ok, "nested_effect_func_origin")
			check(is_same(event._effects[0].from, event), "effect_owner_reindexed")
			var again:Dictionary = CloneContext.new().call("copy_result", event, new_source)
			check(again.ok and SessionGeneration.origin_of(again.object).context.origin() == new_source.origin(), "runtime_event_with_functions_inherit")
		var unknown := BaseEvent.new("not-authorized", "")
		factory = CloneContext.new()
		check(factory.call("configure_template", new_source, [trusted]), "identity_factory_setup")
		check(not factory.call("copy_result", unknown).ok, "unknown_identity_not_template")
		# 当前已绑 runtime 被显式模板池选中仍只能继承，不能改成 factory origin。
		var original_source:SessionContext = SessionGeneration.derive_context(new_source, &"C0.other_origin").context
		var existing := BaseEvent.new("existing-runtime", "")
		bind(existing, original_source)
		factory = CloneContext.new()
		check(factory.call("configure_template", new_source, [existing]), "current_runtime_pool_setup")
		result = factory.call("copy_result", existing)
		check(result.ok and SessionGeneration.origin_of(result.object).context.origin() == original_source.origin(), "current_runtime_pool_inherits_not_resigns")
		before = GameData.objects.size()
		check(existing.clone_data(CloneContext.new()) != null, "current_direct_clone")
		var stale_action:Dictionary = CloneContext.new().call("copy_result", existing, source)
		check(not stale_action.ok, "stale_action_current_card_rejected")
		var dictionary_failure = CloneContext.new().copy({"good":existing, "bad":unknown})
		check(dictionary_failure is Dictionary and dictionary_failure.is_empty(), "dictionary_failure_empty_not_partial")
		var carrier := TypedCarrier.new()
		carrier.items = [existing, unknown]
		before = GameData.objects.size()
		ctx = CloneContext.new()
		result = ctx.call("copy_result", carrier)
		check(not result.ok and result.object == null, "typed_array_child_failure_propagates")
		check(GameData.objects.size() == before, "typed_array_failure_no_registry_residue")
		check(ctx.copy(existing) == null, "failure_sticky_not_reused")
		var late_card := BaseEvent.new("late", "")
		var late_effect := BaseEffect.new("late-effect", [])
		late_effect._funcs = [LateReject.new()]
		late_card._effects = [late_effect]
		factory = CloneContext.new()
		check(factory.call("configure_template", new_source, [late_card]), "late_factory_setup")
		before = GameData.objects.size()
		var before_effects:int = GameData.effects.size()
		result = factory.call("copy_result", late_card)
		check(not result.ok and result.reason == &"injected_late_failure", "late_failure_reason")
		check(GameData.objects.size() == before and GameData.effects.size() == before_effects, "late_failure_all_registries_rolled_back")
		check(late_card.effect_numbers.is_empty(), "late_failure_source_indexes_unchanged")
		var role := BaseMaster.new("no-direct-effects", "", "", "", "")
		role._specials = {"ATTACKS":[BaseAttack.new("role-child", "", [])]}
		factory = CloneContext.new()
		check(factory.call("configure_template", new_source, [role]), "role_factory_identity_setup")
		result = factory.call("copy_result", role)
		check(result.ok and SessionGeneration.origin_of(result.object._specials.ATTACKS[0]).ok, "effectless_role_child_card_bound")
		var cycle:Array = []
		cycle.append(cycle)
		result = CloneContext.new().call("copy_result", cycle)
		check(not result.ok and result.reason == &"cyclic_clone_graph", "cyclic_graph_rejected_before_recursion")
		cycle.clear()
		for card in runtime:
			before = GameData.objects.size()
			check(card.clone_data(CloneContext.new()) == null and GameData.objects.size() == before, "stale_direct_clone_rejected_before_new")
		for card in unbound:
			before = GameData.objects.size()
			check(card.clone_data(CloneContext.new()) == null and GameData.objects.size() == before, "unbound_direct_clone_rejected_before_new")
	print("RESULT ", JSON.stringify({"suite":"card_c0_clone_origin", "checks":checks, "failed":failures.size(), "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
