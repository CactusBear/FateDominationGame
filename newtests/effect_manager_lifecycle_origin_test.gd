extends Node

const Sessions = preload("res://scripts/system/session_generation.gd")
var checks:int = 0
var failures:Array = []

class CleanupObserver extends RefCounted:
	var source:SessionContext
	var observations:Array
	func _init(context:SessionContext, output:Array) -> void:
		source = context
		observations = output
	func _notification(what:int) -> void:
		if what == NOTIFICATION_PREDELETE:
			observations.append(Sessions.validate_context(source).ok)

class RotateOnCleanup extends RefCounted:
	var observations:Dictionary
	func _init(output:Dictionary) -> void:
		observations = output
	func _notification(what:int) -> void:
		if what == NOTIFICATION_PREDELETE:
			observations.token = Sessions.begin_generation(&"lifecycle_test.reentrant_owner").token
			EffectManager.effect_results.append("new-owner-baseline")

func check(label:String, ok:bool) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func fresh() -> SessionContext:
	var generation:Dictionary = Sessions.begin_generation(&"lifecycle_test.fixture")
	return Sessions.derive_context(generation.token, &"lifecycle_test.fixture").context

func runtime_effect(context:SessionContext) -> BaseEffect:
	var effect := BaseEffect.new("lifecycle", [])
	var source:Dictionary = Sessions.bind_origin(effect, context.token(), &"lifecycle_test.effect")
	effect.bind_runtime_context(source.context)
	return effect

func reset_case() -> void:
	var context:SessionContext = fresh()
	var root:Dictionary = GameData.player_data_library
	var data:Dictionary = root[0]
	var effect:BaseEffect = runtime_effect(context)
	check("same-domain registration positive", EffectManager.register_effect(effect, 0))
	var observations:Array = []
	EffectManager.messages.append(CleanupObserver.new(context, observations))
	EffectManager.reset_runtime()
	check("old source revoked before actual cleanup callback", observations == [false])
	check("standalone reset invalidates old effect source", not Sessions.origin_of(effect).ok)
	check("same ID old registered effect rejected", not EffectManager.register_effect(effect, 0))
	check("old rejection leaves pool and self_effects empty", EffectManager.effect_pool.is_empty() and data.self_effects.is_empty())
	check("reset reuses original members without creating", is_same(root, GameData.player_data_library) and is_same(data, root[0]))
	var next:Dictionary = Sessions.current_token()
	check("standalone reset opens fresh shared token", next.ok and not is_same(next.token, context.token()))
	if next.ok:
		var child:SessionContext = Sessions.derive_context(next.token, &"lifecycle_test.new").context
		var current:BaseEffect = runtime_effect(child)
		check("same ID fresh runtime registration positive", EffectManager.register_effect(current, 0))

func composition_case() -> void:
	var context:SessionContext = fresh()
	var effect:BaseEffect = runtime_effect(context)
	check("same-domain prebound register", EffectManager.register_effect(effect, 0))
	var result:Dictionary = EffectManager.call("clear_runtime_in_context", context)
	check("same-domain cleanup accepts original context", result.ok and is_same(result.context, context))
	check("same-domain cleanup retains exact token and binding", is_same(Sessions.current_token().token, context.token()) and Sessions.origin_of(effect).ok)
	check("same-domain identity carrier survives cleanup", EffectManager.register_effect(effect, 0))
	var pool:Array = EffectManager.effect_pool.duplicate()
	var invalid:Array = [null, 5, {}, SessionContext.new()]
	for source in invalid:
		var refused:Dictionary = EffectManager.call("clear_runtime_in_context", source)
		check("invalid cleanup atomic type=" + str(typeof(source)), not refused.ok and EffectManager.effect_pool == pool and is_same(Sessions.current_token().token, context.token()))
	var old:SessionContext = context
	context = fresh()
	var refused:Dictionary = EffectManager.call("clear_runtime_in_context", old)
	check("stale cleanup does not rotate or clear", not refused.ok and EffectManager.effect_pool == pool and is_same(Sessions.current_token().token, context.token()))
	var closed_refusal:Dictionary = EffectManager.call("clear_runtime_after_invalidation")
	check("closed cleanup cannot clear open domain", not closed_refusal.ok and EffectManager.effect_pool == pool)
	Sessions.invalidate_generation(&"lifecycle_test.close")
	var closed:Dictionary = EffectManager.call("clear_runtime_after_invalidation")
	check("closed cleanup never reopens", closed.ok and not Sessions.current_token().ok and EffectManager.effect_pool.is_empty())
	check("closed cleanup repeat idempotent", EffectManager.call("clear_runtime_after_invalidation").ok and not Sessions.current_token().ok)
	var template := BaseEffect.new("lifecycle", [])
	check("closed registration refuses without lazy ticket", not EffectManager.register_effect(template, 0) and not Sessions.current_token().ok)

func rollback_case() -> void:
	var context:SessionContext = fresh()
	var effect:BaseEffect = runtime_effect(context)
	check("rollback fixture registration", EffectManager.register_effect(effect, 0))
	var rules:Dictionary = {"value":1, "context":context}
	var checkpoint = preload("res://scripts/match/rule_checkpoint.gd").new()
	check("real rule checkpoint captures explicit source", checkpoint.capture([rules], {}, context))
	rules.value = 2
	check("same-domain rule rollback preserves qualification", checkpoint.restore() and rules.value == 1 and Sessions.validate_context(context).ok)
	var subjects:Array = EffectManager.get_meta(&"effect_payment_bindings")
	var transactions:Dictionary = EffectManager.capture_transaction_state()
	# Legacy metadata may be restored by callers; it must never be an issuer/current pointer.
	EffectManager.set_meta(&"effect_payment_session", context.token())
	EffectManager.reset_runtime()
	var current:SessionToken = Sessions.current_token().token
	rules.value = 3
	check("old rule restore refuses before write or ticket revival", not checkpoint.restore() and rules.value == 3 and is_same(Sessions.current_token().token, current))
	EffectManager.set_meta(&"effect_payment_session", context.token())
	EffectManager.set_meta(&"effect_payment_bindings", subjects)
	check("transaction rollback accepted without rotating shared session", EffectManager.restore_transaction_state(transactions) and is_same(Sessions.current_token().token, current))
	check("metadata rollback never resurrects old qualification", not Sessions.validate_context(context).ok and not EffectManager.register_effect(effect, 0))
	var new_context:SessionContext = Sessions.derive_context(current, &"lifecycle_test.after_rollback").context
	var new_effect:BaseEffect = runtime_effect(new_context)
	check("restored legacy token cannot contaminate fresh registration", EffectManager.register_effect(new_effect, 0) and EffectManager.can_register_effect(new_effect, 0))
	EffectManager.remove_meta(&"effect_payment_session")
	check("removing legacy metadata never issues a token", is_same(Sessions.current_token().token, current))

func reentry_case() -> void:
	for kind in ["public", "same-domain", "closed"]:
		var context:SessionContext = fresh()
		EffectManager.call("clear_runtime_in_context", context)
		var observations:Dictionary = {}
		EffectManager.messages.append(RotateOnCleanup.new(observations))
		var result:Dictionary
		if kind == "public": result = EffectManager.reset_runtime()
		elif kind == "same-domain": result = EffectManager.call("clear_runtime_in_context", context)
		else:
			Sessions.invalidate_generation(&"lifecycle_test.closed_reentry")
			result = EffectManager.call("clear_runtime_after_invalidation")
		check("reentry rejects interrupted cleanup " + kind, not result.ok and observations.has("token"))
		check("reentry preserves new owner baseline " + kind, EffectManager.effect_results == ["new-owner-baseline"])
		check("reentry preserves new owner token " + kind, is_same(Sessions.current_token().token, observations.get("token")))

func member_case() -> void:
	var context:SessionContext = fresh()
	EffectManager.call("clear_runtime_in_context", context)
	var good:BaseEffect = runtime_effect(context)
	var bad:BaseEffect = runtime_effect(context)
	bad._trigger_player_id = 999999
	var ids:Array = GameData.player_data_library.keys()
	check("batch member refusal before any registration", not EffectManager.register_effects([good, bad]) and EffectManager.effect_pool.is_empty() and GameData.player_data_library[0].self_effects.is_empty())
	check("batch member refusal never creates", GameData.player_data_library.keys() == ids)
	check("public qualification remains pure and member gated", not EffectManager.can_register_effect(bad, 999999) and GameData.player_data_library.keys() == ids and not bad.has_meta(&"effect_registration_subject"))
	check("member positive still registers", EffectManager.register_effect(good, 0) and EffectManager.can_register_effect(good, 0))
	check("different owner remains refused", not EffectManager.can_register_effect(good, 1) and not EffectManager.register_effect(good, 1))
	var original:Dictionary = GameData.player_data_library[0]
	GameData.player_data_library[0] = GameData.new_player_data()
	check("same ID dictionary replacement remains refused", not EffectManager.can_register_effect(good, 0) and not EffectManager.register_effect(good, 0) and GameData.player_data_library[0].self_effects.is_empty())
	GameData.player_data_library[0] = original

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	print("PATH_PROOF ", JSON.stringify({"pid":OS.get_process_id(), "user":OS.get_user_data_dir(), "tmp":OS.get_environment("TMPDIR")}))
	var mode:String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "all"
	if mode in ["reset", "all"]: reset_case()
	if mode in ["composition", "all"]: composition_case()
	if mode in ["rollback", "all"]: rollback_case()
	if mode in ["reentry", "all"]: reentry_case()
	if mode in ["member", "all"]: member_case()
	print("RESULT ", JSON.stringify({"suite":"effect_manager_lifecycle_origin", "checks":checks, "failures":failures}))
	# Avoid old GameData release calling the public resetting ABI during exit; the owner must rewire it.
	get_tree().quit(0 if failures.is_empty() else 1)
