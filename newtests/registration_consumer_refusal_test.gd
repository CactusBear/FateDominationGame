extends Node

const UNKNOWN:int = 990024
var checks:int = 0
var failures:Array = []
var cases:int = 0
var case_name:String = ""
var context:SessionContext = null
var caller:BaseEffect = null

func _ready() -> void:
	call_deferred("run")

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok: failures.append(case_name + ":" + label)
	print("CHECK ", case_name, ":", label, " ", ok)

func setup(label:String) -> void:
	case_name = label
	cases += 1
	check(GameData.reset_game_session([0,1]).get("ok",false), "public reset")
	# This existing lifecycle boundary supplies the original context, not a current fallback.
	context = GameProgress.reset_progress(false).get("context")
	caller = trusted_effect("registration_fixture_caller", true)
	# A real wait root must have an actual member owner, even with null card source.
	EffectManager.register_effect(caller,1)
	GameLog.reset()
	GameData.player_id = 1
	check(not GameData.player_data_library.has(UNKNOWN), "missing member absent")

func options() -> Array:
	return [{"shown_option_name":"合法选项", "funcs":[{"func_name":"store_value","parameters":["chosen"],"var_index":0}]}]

# Fixture producer only: declarations use the actual trusted LoadHelper factory.
# Null card source remains null; session provenance is a separate original handle.
func trusted_effect(effect_name:String, passive:bool, choice:bool = false) -> BaseEffect:
	var declaration:Dictionary = {"effect_name":effect_name,"time_points":[TimePoints.GAME_START],
		"priority":0,"is_pure_passive":passive,"is_residue":false,"need_activate":false,
		"effect_numbers":[],"funcs":[]}
	if choice: declaration["options"] = options()
	var produced:Array = LoadHelper.load_effects([declaration],null,context)
	return produced[0] if produced.size() == 1 else null

func option_effect() -> BaseEffect:
	return trusted_effect("registration_consumer",false,true)

# Ask has no direct-context ABI: the real descriptor executor supplies its verified frame.
# It does not set activating_eff, so empty-source/default-local-player semantics are retained.
func ask_in_frame(shown_name:String, id:int) -> BaseEffect:
	var result:Array = EffectManager.run_func_descriptor({"func_name":"ask_player_option",
		"parameters":[options(),shown_name,id]},caller,context)
	return result[1] if result.size() == 2 else null

# Read-only snapshots: refusal must not publish objects, choices, context or attempt metadata.
func snapshot() -> Dictionary:
	var members:Dictionary = {}
	for id in GameData.player_data_library:
		members[id] = GameData.player_data_library[id].self_effects.duplicate()
	var had_attempts:bool = EffectManager.has_meta(ActivateEffect.REGISTRATION_ATTEMPTS)
	return {"objects":GameData.objects.duplicate(), "effects":GameData.effects.duplicate(),
		"pool":EffectManager.effect_pool.duplicate(), "members":members,
		"matched":EffectManager.matched_time_points.duplicate(), "resolved":EffectManager.resolved_effects.duplicate(),
		"pending":EffectManager.get("_pending_choices").duplicate(), "decision":EffectManager.decision_queue.duplicate(),
		"activation":EffectManager.activation_pool.duplicate(), "waiting":EffectManager.is_waiting_for_choice(),
		"had_attempts":had_attempts,
		"attempts":EffectManager.get_meta(ActivateEffect.REGISTRATION_ATTEMPTS).duplicate(true) if had_attempts else {}}

func unchanged(before:Dictionary) -> void:
	var after:Dictionary = snapshot()
	for key in before:
		check(before[key] == after[key], "refusal preserves " + str(key))
	check(not EffectManager.runtime_guard_status().get("paused",false), "ordinary rejection is not audit pause")
	check(not GameData.player_data_library.has(UNKNOWN), "refusal does not create member")

func test_ask_missing() -> void:
	setup("ask_missing")
	var before:Dictionary = snapshot()
	check(AskPlayerOption.new().exec(options(),"missing",UNKNOWN) == null, "missing registration returns null")
	unchanged(before)

func test_activate_missing(owned:bool) -> void:
	setup("activate_clone_missing" if owned else "activate_missing")
	var effect:BaseEffect = option_effect()
	if owned: check(EffectManager.register_effect(effect,0), "source registered to member zero")
	var original_owner:int = effect._trigger_player_id
	var original_trigger:Array = effect._trigger_time_points
	var original_meta:Array = effect.get_meta_list()
	EffectManager.matched_time_points[effect] = ["prior_match"]
	EffectManager.resolved_effects[effect] = true
	var before:Dictionary = snapshot()
	check(ActivateEffect.new().exec(effect,UNKNOWN) == null, "missing registration returns null")
	unchanged(before)
	check(effect._trigger_player_id == original_owner, "owner unchanged")
	check(is_same(effect._trigger_time_points,original_trigger), "trigger reference unchanged")
	check(effect.get_meta_list() == original_meta, "effect metadata unchanged")

func test_activate_stale(clone:bool) -> void:
	setup("activate_stale_clone" if clone else "activate_stale")
	var effect:BaseEffect = option_effect()
	check(EffectManager.register_effect(effect,0), "old source registered")
	check(GameData.reset_game_session([0,1]).get("ok",false), "second public reset")
	var before:Dictionary = snapshot()
	check(ActivateEffect.new().exec(effect,1 if clone else 0) == null, "existing registration identity refusal returns null")
	unchanged(before)
	check(effect._trigger_player_id == 0, "old source owner preserved")

func test_ask_member(default_owner:bool) -> void:
	setup("ask_default_empty_source" if default_owner else "ask_member_empty_source")
	check(EffectManager.activating_eff == null, "legal empty source")
	var effect:BaseEffect = ask_in_frame("legal",-1 if default_owner else 0)
	check(effect != null, "legal request returns effect")
	if effect == null: return
	check(effect.from == null, "empty source is retained")
	check(effect._trigger_player_id == (1 if default_owner else 0), "existing default owner resolution")
	check(EffectManager.effect_pool.has(effect), "legal registration retained")
	check(EffectManager.get("_pending_choices").has(effect), "legal request queued")

func test_ask_pipeline(id:int, default_owner:bool = false) -> void:
	setup("ask_pipeline_default" if default_owner else ("ask_pipeline_missing" if id == UNKNOWN else "ask_pipeline_member"))
	var host := BaseAttack.new("registration_pipeline_host","",[])
	var paras:Array = [options(),"pipeline"] if default_owner else [options(),"pipeline",id]
	host._effects = LoadHelper.load_effects([{"effect_name":"registration_parent","time_points":[TimePoints.GAME_START],"priority":0,
		"is_pure_passive":true,"is_residue":false,"effect_numbers":[],"funcs":[
			{"func_name":"ask_player_option","parameters":paras,"var_index":0},
			{"func_name":"store_value","parameters":["tail"],"var_index":1}]}],host,context)
	var parent:BaseEffect = host._effects[0]
	check(EffectManager.register_effect(parent,0), "real parent registered")
	var object_count:int = GameData.objects.size()
	var effect_count:int = GameData.effects.size()
	EffectManager.add_to_activation_pool(parent)
	EffectManager.run_pipeline()
	var pending:BaseEffect = EffectManager.get_pending_active_effect()
	if id == UNKNOWN and not default_owner:
		check(pending == null and not EffectManager.is_waiting_for_choice(), "refused child never waits")
		check(EffectManager.get("_pending_choices").is_empty() and EffectManager.decision_queue.is_empty(), "refused child not queued")
		check(GameData.objects.size() == object_count and GameData.effects.size() == effect_count, "refused child never published")
		check(parent._self_vars == [null,"tail"], "null result preserved and parent tail executes")
	else:
		check(pending != null and EffectManager.is_waiting_for_choice(), "legal child waits")
		if pending == null: return
		check(pending._trigger_player_id == 0, "parent owner wins over local player default")
		check(EffectManager.submit_option_choice(pending,[0]), "public choice submission accepted")
		check(not EffectManager.is_waiting_for_choice(), "legal choice ends waiting")
		check(parent._self_vars == ["chosen","tail"], "option body shares variables and resumes parent")
	var tails:int = 0
	var asks:Array = []
	for call in GameLog.all_func_calls():
		if call.func_name == "store_value" and call.resolved_parameters == ["tail"]: tails += 1
		if call.func_name == "ask_player_option": asks.append(call)
	check(tails == 1, "parent tail called exactly once")
	check(asks.size() == 1 and asks[0].status == "executed", "original script call status contract")
	if id == UNKNOWN: check(asks.size() == 1 and asks[0].return_value == null, "script observes null refusal result")
	check(not EffectManager.runtime_guard_status().get("paused",false), "pipeline not audit paused")

func test_activate_member(clone:bool, default_owner:bool = false) -> void:
	setup("activate_clone_member" if clone else ("activate_default_empty_source" if default_owner else "activate_member_empty_source"))
	var effect:BaseEffect = option_effect()
	if clone: check(EffectManager.register_effect(effect,0), "original member zero registered")
	var returned = ActivateEffect.new().exec(effect,-1 if default_owner else (1 if clone else 0),context)
	check(returned != null, "legal activation returns effect")
	if returned == null: return
	check((returned != effect) == clone, "legal clone decision preserved")
	check(returned._trigger_player_id == (1 if clone or default_owner else 0), "legal activation owner")
	check(returned.from == null, "legal empty source remains allowed")
	check(EffectManager.get_pending_active_effect() == returned, "legal activation actually waits")
	check(EffectManager.submit_option_choice(returned,[0]), "public activation choice accepted")
	check(returned._self_vars == ["chosen"], "declared activation body executed")
	check(not EffectManager.is_waiting_for_choice(), "activation completes waiting")
	if clone:
		check(effect._trigger_player_id == 0 and EffectManager.effect_pool.has(effect), "original remains registered to original owner")
		check(effect._option_use_counts.is_empty(), "original option use counts unchanged")

func test_activate_descriptor(id:int) -> void:
	setup("activate_descriptor_missing" if id == UNKNOWN else "activate_descriptor_member")
	var parent:BaseEffect = trusted_effect("descriptor_parent",true)
	check(EffectManager.register_effect(parent,0), "descriptor parent registered")
	var target:BaseEffect = option_effect()
	var result:Array = EffectManager.run_func_descriptor({"func_name":"activate_effect", "parameters":[target,id]},parent,context)
	check(result.size() == 2 and result[0], "descriptor reports callable execution, not business success")
	var calls:Array = GameLog.all_func_calls()
	check(calls.size() == 1 and calls[0].status == "executed", "activation script status contract retained")
	if id == UNKNOWN:
		check(result.size() == 2 and result[1] == null, "descriptor returns true-null on ordinary refusal")
		check(calls.size() == 1 and calls[0].return_value == null, "activation trace records null refusal")
		check(not EffectManager.is_waiting_for_choice() and EffectManager.decision_queue.is_empty(), "descriptor refusal never queues")
	else:
		check(result.size() == 2 and result[1] == target, "descriptor returns actual legal target")
		check(EffectManager.submit_option_choice(target,[0]), "descriptor target accepts public choice")
		check(target._self_vars == ["chosen"] and not EffectManager.is_waiting_for_choice(), "descriptor legal target completes")

func test_audit_refusal(ask:bool) -> void:
	setup("ask_audit_pause" if ask else "activate_audit_pause")
	var target:BaseEffect = null if ask else option_effect()
	var before:Dictionary = snapshot()
	MatchJournal.audit_error = "registration_consumer_refusal_test injection"
	var returned = ask_in_frame("audit",0) if ask else ActivateEffect.new().exec(target,0,context)
	check(returned == null, "actual registration false never returns success")
	var guard:Dictionary = EffectManager.runtime_guard_status()
	check(guard.get("paused",false) and guard.get("reason","") == "audit_write_failed", "audit failure remains paused with original reason")
	check(EffectManager.get("_pending_choices").is_empty() and EffectManager.decision_queue.is_empty(), "audit failure never queues decision")
	check(target == null or not EffectManager.matched_time_points.has(target), "audit failure never writes match")
	var after:Dictionary = snapshot()
	check(before.had_attempts == after.had_attempts and before.attempts == after.attempts, "failed registration has no successful compensation record")
	check(GameData.effects.has(EffectManager.runtime_guard_effect()), "audit recovery object is retained, not ordinarily rolled back")
	# Public reset owns audit recovery; this injection does not claim ordinary rollback.
	MatchJournal.audit_error = ""

func run() -> void:
	print("ENV ",JSON.stringify({"user_data_dir":OS.get_user_data_dir(),"pid":OS.get_process_id(),"tmp":OS.get_environment("TMP"),"localappdata":OS.get_environment("LOCALAPPDATA")}))
	test_ask_missing()
	test_activate_missing(false)
	test_activate_missing(true)
	test_activate_stale(false)
	test_activate_stale(true)
	test_ask_member(false)
	test_ask_member(true)
	test_ask_pipeline(UNKNOWN)
	test_ask_pipeline(0)
	test_ask_pipeline(0,true)
	test_activate_member(false)
	test_activate_member(false,true)
	test_activate_member(true)
	test_activate_descriptor(UNKNOWN)
	test_activate_descriptor(0)
	test_audit_refusal(true)
	test_audit_refusal(false)
	print("RESULT ",JSON.stringify({"suite":"registration_consumer_refusal","cases":cases,"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
