extends Node

var checks:int = 0
var failures:Array = []

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func setup() -> SessionContext:
	var result:Dictionary = GameData.reset_game_session([0,1])
	check(result.get("ok",false), "PRE reset")
	GameLog.reset()
	return result.get("context")

func target(context:SessionContext, id:int = 0) -> BaseEffect:
	var effects:Array = LoadHelper.load_effects([{"effect_name":"a1-31-target","time_points":[TimePoints.GAME_START],"priority":0,"is_pure_passive":false,"is_residue":false,"effect_numbers":[],"funcs":[],"options":[{"shown_option_name":"use","funcs":[{"func_name":"store_value","parameters":["used"],"var_index":0}]}]}],null,context)
	check(effects.size() == 1,"PRE trusted factory")
	var effect:BaseEffect = effects[0]
	check(EffectManager.register_effect(effect,id),"PRE registration")
	return effect

# The original implementation has no context parameter. Exercise its real two-argument
# path for RED, not an invalid-argument SCRIPT ERROR.
func activate(effect:BaseEffect, id:int, context:SessionContext):
	var operation := ActivateEffect.new()
	var accepts_context:bool = false
	for method in operation.get_method_list():
		if method.name == "exec": accepts_context = method.args.size() >= 3
	return operation.call("exec",effect,id,context) if accepts_context else operation.exec(effect,id)

func snapshot() -> Dictionary:
	var metadata:Dictionary = {}
	for key in EffectManager.get_meta_list():
		var value = EffectManager.get_meta(key)
		metadata[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	var members:Dictionary = {}
	for id in GameData.player_data_library:
		members[id] = GameData.player_data_library[id].self_effects.duplicate()
	return {"objects":GameData.objects.duplicate(),"effects":GameData.effects.duplicate(),"pool":EffectManager.effect_pool.duplicate(),"matched":EffectManager.matched_time_points.duplicate(),"resolved":EffectManager.resolved_effects.duplicate(),"decision":EffectManager.decision_queue.duplicate(),"activation":EffectManager.activation_pool.duplicate(),"members":members,"metadata":metadata}

func rejected(effect:BaseEffect, id:int, context:SessionContext, label:String) -> void:
	var before:Dictionary = snapshot()
	var owner:int = effect._trigger_player_id
	var trigger:Array = effect._trigger_time_points
	check(activate(effect,id,context) == null,label + " returns null")
	check(snapshot() == before,label + " no registration/clone/match/queue/metadata")
	check(effect._trigger_player_id == owner and is_same(effect._trigger_time_points,trigger),label + " original owner and trigger preserved")

func stale_caller() -> void:
	var old_context:SessionContext = setup()
	var current:SessionContext = setup()
	var effect:BaseEffect = target(current)
	rejected(effect,0,old_context,"old caller to fresh same-ID target")

func stale_object() -> void:
	var context:SessionContext = setup()
	var effect:BaseEffect = target(context)
	var new_context:SessionContext = setup()
	rejected(effect,0,new_context,"old object new context")
	rejected(effect,1,new_context,"old object cannot clone to another owner")

func same_id_replacement() -> void:
	var context:SessionContext = setup()
	var effect:BaseEffect = target(context)
	GameData.player_data_library[0] = GameData.new_player_data()
	rejected(effect,0,context,"same-ID owner replacement")
	rejected(effect,1,context,"same-ID owner replacement cannot clone")

func legal_activation(clone:bool) -> void:
	var context:SessionContext = setup()
	var effect:BaseEffect = target(context)
	var original:Dictionary = GameData.player_data_library[0]
	var returned = activate(effect,1 if clone else 0,context)
	check(returned != null,"legal returns actual target")
	if returned == null: return
	check((returned != effect) == clone,"legal clone identity")
	var attempts:Dictionary = ActivateEffect.registration_attempts()
	check(attempts.has(returned),"pending activation retains its attempt")
	var state:Dictionary = attempts[returned].back()
	var real_owner:Dictionary = GameData.player_data_library[1 if clone else 0]
	check(state.has("owner_data") and is_same(state.get("owner_data"),real_owner),"metadata owns actual target dictionary")
	check(state.has("context") and is_same(state.get("context"),context),"metadata retains captured context")
	check(EffectManager.submit_option_choice(returned,[0]),"legal choice accepted")
	check(returned._self_vars == ["used"],"legal body executed")
	check(not ActivateEffect.registration_attempts().has(returned),"completion consumes only target attempt")
	check(is_same(GameData.player_data_library[0],original) and effect._trigger_player_id == 0,"original owner retained")

func stale_attempt() -> void:
	var context:SessionContext = setup()
	var effect:BaseEffect = target(context)
	EffectManager.is_running = true
	check(activate(effect,0,context) == effect,"PRE queued attempt")
	EffectManager.is_running = false
	var attempts:Dictionary = ActivateEffect.registration_attempts()
	var before:Dictionary = snapshot()
	SessionGeneration.invalidate_generation(&"a1-31-stale-attempt")
	check(not ActivateEffect.reject_registration(effect),"stale attempt cannot restore rule state")
	check(snapshot() == before,"stale rejection retains original metadata")
	ActivateEffect.accept_registration(effect)
	check(is_same(ActivateEffect.registration_attempts(),attempts) and attempts.has(effect),"stale acceptance cannot consume metadata")

func empty_noop() -> void:
	var context:SessionContext = setup()
	var effect:BaseEffect = target(context)
	check(not EffectManager.has_meta(ActivateEffect.REGISTRATION_ATTEMPTS),"PRE attempts absent")
	check(ActivateEffect.reject_registration(effect),"no attempt rejection is no-op")
	ActivateEffect.accept_registration(effect)
	check(not EffectManager.has_meta(ActivateEffect.REGISTRATION_ATTEMPTS),"no-op does not publish attempt metadata")

func nested_scopes() -> void:
	var context:SessionContext = setup()
	var parent:BaseEffect = target(context)
	var child:BaseEffect = target(context,1)
	EffectManager.is_running = true
	check(activate(parent,0,context) == parent,"PRE parent pending")
	var attempts:Dictionary = ActivateEffect.registration_attempts()
	var parent_state:Dictionary = attempts[parent].back()
	check(activate(child,1,context) == child,"PRE child pending")
	ActivateEffect.accept_registration(child)
	check(not attempts.has(child) and is_same(attempts[parent].back(),parent_state),"child success retains exact parent metadata")
	check(activate(child,1,context) == child,"PRE second child pending")
	check(ActivateEffect.reject_registration(child),"child rejection restores its own scope")
	check(not attempts.has(child) and is_same(attempts[parent].back(),parent_state),"child refusal retains exact parent metadata")
	check(activate(parent,0,context) == parent,"PRE same target reentry")
	check(attempts[parent].size() == 2,"same target has two LIFO attempts")
	check(ActivateEffect.reject_registration(parent),"inner same-target refusal succeeds")
	check(attempts[parent].size() == 1 and is_same(attempts[parent].back(),parent_state),"inner refusal restores exact outer scope")
	check(ActivateEffect.reject_registration(parent),"outer scope remains rejectable")
	check(not attempts.has(parent),"outer completion consumes final scope")
	EffectManager.is_running = false

func frame_activation() -> void:
	var context:SessionContext = setup()
	var parent:BaseEffect = target(context)
	var child:BaseEffect = target(context,1)
	EffectManager.is_running = true
	var result:Array = EffectManager.run_func_descriptor({"func_name":"activate_effect","parameters":[child,1],"var_index":0},parent,context)
	check(result.size() == 2 and result[0] and is_same(result[1],child),"real descriptor keeps actual child return")
	var attempts:Dictionary = ActivateEffect.registration_attempts()
	check(attempts.has(child) and is_same(attempts[child].back().get("context"),context),"real descriptor keeps original frame context")
	check(ActivateEffect.reject_registration(child),"descriptor attempt rejects in its actual owner scope")
	EffectManager.is_running = false

func rule_refusal() -> void:
	var context:SessionContext = setup()
	var parent:BaseEffect = target(context)
	var child:BaseEffect = target(context,1)
	EffectManager.is_running = true
	check(activate(parent,0,context) == parent,"PRE parent before rule refusal")
	var attempts:Dictionary = ActivateEffect.registration_attempts()
	var parent_state:Dictionary = attempts[parent].back()
	child._disabled = true
	var before:Dictionary = snapshot()
	check(activate(child,0,context) == null,"disabled clone ordinary refusal returns null")
	var after:Dictionary = snapshot()
	for key in before:
		if before[key] != after[key]: print("DIFFERENCE ",key," BEFORE=",before[key]," AFTER=",after[key])
	check(after == before,"disabled clone refusal no queue/match/clone/attempt residue")
	check(is_same(attempts[parent].back(),parent_state),"disabled clone refusal does not clear parent metadata")
	EffectManager.is_running = false

func invalid_sources() -> void:
	var context:SessionContext = setup()
	var effect:BaseEffect = target(context)
	var before:Dictionary = snapshot()
	var operation := ActivateEffect.new()
	var accepts_context:bool = false
	for method in operation.get_method_list():
		if method.name == "exec": accepts_context = method.args.size() >= 3
	for invalid in [SessionContext.new(context.token(),context.origin()), weakref(context), {}, "same-ID"]:
		var returned = operation.call("exec",effect,0,invalid) if accepts_context else operation.exec(effect,0)
		check(returned == null,"unissued or non-context input returns null")
		check(snapshot() == before,"invalid context publishes no state")

func audit_refusal() -> void:
	var context:SessionContext = setup()
	var effect:BaseEffect = target(context)
	var before:Dictionary = snapshot()
	MatchJournal.audit_error = "a1-31 audit injection"
	check(activate(effect,0,context) == null,"actual register audit false returns null")
	check(EffectManager.runtime_guard_status().get("paused",false) and EffectManager.runtime_guard_status().get("reason","") == "audit_write_failed","actual audit failure retains pause contract")
	check(snapshot() == before,"audit registration false leaves no match/queue/attempt metadata")
	MatchJournal.audit_error = ""

func missing_context() -> void:
	var context:SessionContext = setup()
	var effect:BaseEffect = target(context)
	for spoof in [false,true]:
		if spoof: EffectManager.activating_eff = effect
		var before:Dictionary = snapshot()
		check(ActivateEffect.new().exec(effect,0) == null,"direct call requires explicit caller context")
		check(snapshot() == before,"activating_eff cannot supply missing caller provenance")
	EffectManager.activating_eff = null

func _ready() -> void:
	print("ENV ",JSON.stringify({"user_dir":OS.get_user_data_dir(),"executable":OS.get_executable_path(),"TMPDIR":OS.get_environment("TMPDIR"),"TMP":OS.get_environment("TMP"),"TEMP":OS.get_environment("TEMP"),"APPDATA":OS.get_environment("APPDATA"),"LOCALAPPDATA":OS.get_environment("LOCALAPPDATA")}))
	stale_caller()
	stale_object()
	same_id_replacement()
	legal_activation(false)
	legal_activation(true)
	stale_attempt()
	empty_noop()
	nested_scopes()
	frame_activation()
	rule_refusal()
	invalid_sources()
	audit_refusal()
	missing_context()
	GameData.release_game_objects()
	print("RESULT ",JSON.stringify({"suite":"a1_31_activate_origin","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
