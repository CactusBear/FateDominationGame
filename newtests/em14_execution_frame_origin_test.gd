extends Node
const SG = preload("res://scripts/system/session_generation.gd")
var checks:int = 0
var failures:Array = []
var reset_hits:int = 0
var reset_baseline:Dictionary = {}
var callback_hits:int = 0
var others_hits:int = 0
var callback_reset_ok:bool = false
var reset_loop_state:Dictionary = {}
var reset_callback_frame:Dictionary = {}
# 使用已登记 SetProperty.exec 触发同步原生 setter；不塞未声明任意 Callable。
var reset_marker:bool = false:
	set(value):
		reset_marker = value
		if value: reset_during_before()
var others_marker:bool = false:
	set(value):
		others_marker = value
		if value: others_hits += 1

func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)

func new_session() -> SessionContext:
	var result:Dictionary = GameData.reset_game_session([0, 1])
	check(result.get("ok", false), "PRE session reset accepted")
	GameLog.reset()
	return result.get("context")

func make_effect(name:String, funcs:Array, context:SessionContext, points:Array = []) -> BaseEffect:
	var loaded:Array = LoadHelper.load_effects([{"effect_name":name,"time_points":points,"priority":0,"is_pure_passive":true,"is_residue":false,"effect_numbers":[],"funcs":funcs}], null, context)
	check(loaded.size() == 1, "PRE runtime factory creates " + name)
	if loaded.is_empty(): return null
	var effect:BaseEffect = loaded[0]
	check(EffectManager.register_effect(effect, 0), "PRE runtime effect registers " + name)
	return effect

func reset_during_before():
	reset_hits += 1
	if EffectManager.has_method("execution_runtime_snapshot"):
		var snapshot:Dictionary = EffectManager.call("execution_runtime_snapshot")
		if not snapshot.functions.is_empty(): reset_callback_frame = snapshot.functions.back()
		for frame in snapshot.functions:
			if frame.has("loop") and frame.loop.get("kind") == "foreach": reset_loop_state = frame.loop
	var result:Dictionary = GameData.reset_game_session([0, 1])
	callback_reset_ok = result.get("ok", false)
	GameLog.reset()
	reset_baseline = {"p0":GameData.player_data_library[0].score.number,"p1":GameData.player_data_library[1].score.number}
	make_effect("new-others", [{"func_name":"set_property","parameters":[self,"others_marker",true]}], result.get("context"), ["others_" + TimePoints.SCORE_ADD])

func direct_old_function() -> void:
	var context:SessionContext = new_session()
	var old_known:Dictionary = {"servant_class":{}}
	GameData.player_data_library[0]["known_info"] = old_known
	var old:BaseEffect = make_effect("old-knowledge", [{"func_name":"get_player_data_value","parameters":["known_info"],"var_index":0},{"func_name":"set_player_data","parameters":["known_info",{"self_var":0}],"var_index":-1}], context)
	EffectManager.activating_eff = old
	var getter:Array = execute_func(old._funcs[0], old, context)
	check(getter[0] and is_same(old._self_vars[0], old_known), "PRE legal getter saves original knowledge reference")
	var old_f:BaseFunc = old._funcs[1]
	var old_context:SessionContext = old_f.runtime_context()
	var next:SessionContext = new_session()
	check(not SG.validate_context(old_context).get("ok", false), "PRE old BaseFunc context is genuinely stale")
	var current:Dictionary = GameData.player_data_library[0]
	var baseline_calls:int = GameLog.all_func_calls().size()
	EffectManager.activating_eff = old
	var outcome:Array = execute_func(old_f, old, old_context)
	print("OBS direct_old invoked=", outcome[0], " new_known_is_old=", is_same(current.get("known_info"), old_known), " call_delta=", GameLog.all_func_calls().size()-baseline_calls)
	check(not outcome[0] and outcome[1] == null, "RED old runtime BaseFunc is rejected before invocation")
	check(GameLog.all_func_calls().size() == baseline_calls, "RED old runtime BaseFunc leaves no function fact")
	check(not is_same(current.get("known_info"), old_known), "old captured Callable does not attach old knowledge")
	var fresh:BaseEffect = make_effect("new-mixed-effect", [], next)
	baseline_calls = GameLog.all_func_calls().size()
	EffectManager.activating_eff = fresh
	outcome = execute_func(old_f, fresh, next)
	check(not outcome[0], "RED old BaseFunc plus fresh same-ID effect is rejected")
	check(GameLog.all_func_calls().size() == baseline_calls, "RED mixed source leaves no function fact")
	EffectManager.activating_eff = null

func direct_old_callable() -> void:
	var context:SessionContext = new_session()
	var old:BaseEffect = make_effect("old-callable", [{"func_name":"edit_score","parameters":[null,BaseNumber.new(2),1]}], context)
	var f:BaseFunc = old._funcs[0]
	EffectManager.activating_eff = old
	var valid:Array = execute_func(f, old, context)
	check(valid[0] and GameData.player_data_library[1].score.number == 2, "PRE same-domain captured Callable really executes")
	new_session()
	var calls:int = GameLog.all_func_calls().size()
	EffectManager.activating_eff = old
	var result:Array = execute_func(f, old, context)
	print("OBS stale_callable invoked=", result[0], " new_score=", GameData.player_data_library[1].score.number, " call_delta=", GameLog.all_func_calls().size()-calls)
	check(GameData.player_data_library[1].score.number == 0, "existing BaseFunc Callable leaf guard already refuses old receiver")
	check(not result[0], "RED executor must not report stale Callable invoked")
	check(GameLog.all_func_calls().size() == calls, "RED stale Callable rejected before game call logging")
	EffectManager.activating_eff = null

func old_effect_descriptor() -> void:
	var context:SessionContext = new_session()
	var old:BaseEffect = make_effect("old-descriptor-owner", [], context)
	new_session()
	var current:Dictionary = GameData.player_data_library[1]
	var before = current.score.number
	EffectManager.activating_eff = old
	var result:Array = execute_descriptor({"func_name":"edit_score","parameters":[null,BaseNumber.new(2),1]}, old, context)
	print("OBS stale_descriptor invoked=", result[0], " score_delta=", current.score.number-before)
	check(not result[0], "RED descriptor on old same-ID effect must be rejected")
	check(current.score.number == before, "RED old descriptor must not reward same-ID new member")
	EffectManager.activating_eff = null

func synchronous_foreach() -> void:
	var context:SessionContext = new_session()
	var body:Dictionary = {"func_name":"edit_score","parameters":[null,BaseNumber.new(2),null]}
	var outer:BaseEffect = make_effect("same-domain-foreach", [{"func_name":"foreach_func","parameters":[body,[0,1],2]}], context)
	EffectManager.activate_effect(outer)
	check(GameData.player_data_library[0].score.number == 2 and GameData.player_data_library[1].score.number == 2, "PRE same-domain real foreach rewards declared targets")
	context = new_session()
	make_effect("reset-before", [{"func_name":"set_property","parameters":[self,"reset_marker",true]}], context, ["self_" + TimePoints.BEFORE_SCORE_ADD])
	var root:BaseEffect = make_effect("old-sync-foreach", [{"func_name":"foreach_func","parameters":[body,[0,1],2]}], context)
	var old_context:SessionContext = root.runtime_context()
	EffectManager.activate_effect(root)
	check(reset_hits == 1 and callback_reset_ok, "PRE real BEFORE listener resets exactly once")
	check(not SG.validate_context(old_context).get("ok", false), "PRE synchronous old root qualification invalidated")
	print("OBS foreach_reset baseline=", JSON.stringify(reset_baseline), " current0=", GameData.player_data_library[0].score.number, " current1=", GameData.player_data_library[1].score.number, " others_hits=", others_hits)
	check(GameData.player_data_library[0].score.number == reset_baseline.p0 and GameData.player_data_library[1].score.number == reset_baseline.p1, "RED old synchronous foreach adds nothing after reset baseline")
	check(GameLog.query({"type":"score_add"}).is_empty(), "RED no post-reset old foreach score fact")
	check(others_hits == 0, "RED no real new-session others listener from old foreach")
	check(GameData.player_data_library.keys().size() == 2, "same-ID foreach does not create extra members")
	if EffectManager.has_method("execution_runtime_snapshot"):
		check(not reset_loop_state.is_empty(), "PRE captured actual synchronous foreach cursor")
		check(reset_loop_state.get("iteration", -1) == 0 and reset_loop_state.get("body_index", -1) == 0 and reset_loop_state.get("item", -1) == 0, "source rejection stops before next iteration first item read")
		check(not EffectManager.runtime_guard_status().paused, "source rejection does not become resumable guard pause")
		check(not reset_callback_frame.is_empty() and reset_callback_frame.get("stage") == "call" and not reset_callback_frame.has("result"), "callback return rejects before frame result self-var or executed log")

# 同一oracle兼容改前二参与候选三参；context均在换局前捕获，绝不消费时补票。
func execute_func(f:BaseFunc, effect:BaseEffect, context:SessionContext) -> Array:
	for method in EffectManager.get_method_list():
		if method.name == &"run_base_func" and method.args.size() >= 3:
			return EffectManager.call("run_base_func", f, effect, context)
	return EffectManager.run_base_func(f, effect)

func execute_descriptor(desc, effect:BaseEffect, context:SessionContext) -> Array:
	for method in EffectManager.get_method_list():
		if method.name == &"run_func_descriptor" and method.args.size() >= 3:
			return EffectManager.call("run_func_descriptor", desc, effect, context)
	return EffectManager.run_func_descriptor(desc, effect)

func additional_boundaries() -> void:
	var context:SessionContext = new_session()
	var fresh:BaseEffect = make_effect("fresh-direct-boundaries", [{"func_name":"get_player_data_value","parameters":["known_info"],"var_index":0}], context)
	var known:Dictionary = {"servant_class":{}}
	GameData.player_data_library[0]["known_info"] = known
	EffectManager.activating_eff = fresh
	check(not EffectManager.execution_context().get("ok", false), "no frame is not authorized by fresh activating_eff")
	var before:int = GameLog.all_func_calls().size()
	check(not EffectManager.run_base_func(fresh._funcs[0], fresh)[0], "no-frame direct BaseFunc requires explicit captured context")
	check(GameLog.all_func_calls().size() == before, "missing context rejects before function facts")
	check(execute_func(fresh._funcs[0], fresh, context)[0] and is_same(fresh._self_vars[0], known), "fresh same-ID BaseFunc preserves knowledge identity")
	var old_f:BaseFunc = fresh._funcs[0]
	GameProgress.reset_progress()
	before = GameLog.all_func_calls().size()
	check(not execute_func(old_f, fresh, context)[0], "progress-only reset rejects old direct BaseFunc with reused dictionaries")
	check(GameLog.all_func_calls().size() == before, "progress-only old direct has no call fact")
	check(not EffectManager.call("check_condition", old_f, fresh, context), "stale direct condition rejects before null-condition success")
	var placeholder:Array = EffectManager.call("resolve_placeholder", {"self_var":0}, fresh, context)
	check(not placeholder[0] and placeholder[1] == null, "stale placeholder refuses captured knowledge read")
	context = new_session()
	var root:BaseEffect = make_effect("mixed-root-must-stop", [{"func_name":"edit_score","parameters":[null,BaseNumber.new(3),1]}], context)
	root._funcs.push_front(old_f)
	before = GameLog.all_func_calls().size()
	EffectManager.activate_effect(root)
	check(GameData.player_data_library[1].score.number == 0, "source rejection is root terminal not condition-false fallthrough")
	check(GameLog.all_func_calls().size() == before, "mixed root rejects before first function log")
	check(GameLog.query({"type":"effect"}).is_empty(), "rejected root never publishes effect-completed fact")
	if EffectManager.has_method("execution_source_status"):
		check(not EffectManager.call("execution_source_status").ok, "public source diagnostic retains root rejection")
	else:
		check(false, "public source diagnostic retains root rejection")
	EffectManager.activating_eff = null

func same_domain_guard_resume() -> void:
	var context:SessionContext = new_session()
	var known:Dictionary = {"servant_class":{}}
	GameData.player_data_library[0].known_info = known
	var root:BaseEffect = make_effect("knowledge-real-resume", [{"func_name":"get_player_data_value","parameters":["known_info"],"var_index":0},{"func_name":"set_player_data","parameters":["known_info",{"self_var":0}]}], context)
	check(EffectManager.configure_runtime_guard({"enabled":true,"steps":1,"seconds":0.0}), "PRE configure real one-step guard")
	EffectManager.activate_effect(root)
	check(EffectManager.runtime_guard_status().paused, "same-domain root genuinely pauses between getter and setter")
	check(root._self_vars.size() == 1 and is_same(root._self_vars[0], known), "paused getter retains original knowledge reference")
	check(EffectManager.resume_runtime_guard(), "same-domain actual guard resume succeeds")
	check(not EffectManager.runtime_guard_status().paused and is_same(GameData.player_data_library[0].known_info, known), "resumed setter keeps knowledge type and identity")
	check(GameLog.query({"type":"effect"}).size() == 1, "same-domain resumed root completes once")
	check(EffectManager.configure_runtime_guard({"enabled":false,"steps":0,"seconds":0.0}), "PRE disable guard after real resume")
	EffectManager.activating_eff = null

func same_domain_loop_resume() -> void:
	var context:SessionContext = new_session()
	var known:Dictionary = {"servant_class":{}}
	GameData.player_data_library[0]["known_info"] = known
	var body:Dictionary = {"func_name":"edit_score","parameters":[null,BaseNumber.new(2),null]}
	var root:BaseEffect = make_effect("foreach-real-resume", [{"func_name":"foreach_func","parameters":[body,[0,1],2],"var_index":0},{"func_name":"get_player_data_value","parameters":["known_info"],"var_index":1}], context)
	check(EffectManager.configure_runtime_guard({"enabled":true,"steps":1,"seconds":0.0}), "PRE configure real looping guard")
	EffectManager.activate_effect(root)
	check(EffectManager.runtime_guard_status().paused, "real foreach pauses within saved loop frame")
	var resumes:int = 0
	while EffectManager.runtime_guard_status().paused and resumes < 8:
		check(EffectManager.resume_runtime_guard(), "real foreach resume accepted")
		resumes += 1
	check(not EffectManager.runtime_guard_status().paused, "real foreach eventually completes saved cursor")
	check(GameData.player_data_library[0].score.number == 2 and GameData.player_data_library[1].score.number == 2, "real foreach resume rewards each item exactly once")
	check(root._self_vars.size() == 2 and is_same(root._self_vars[1], known), "loop resume preserves following self-var reference")
	check(GameLog.query({"type":"effect"}).size() == 1, "loop resume completes root once")
	check(EffectManager.configure_runtime_guard({"enabled":false,"steps":0,"seconds":0.0}), "PRE disable looping guard")

func _ready() -> void:
	print("ENV user_dir=", OS.get_user_data_dir(), " pid=", OS.get_process_id())
	var mode:String = str(OS.get_cmdline_user_args()[0]) if not OS.get_cmdline_user_args().is_empty() else "all"
	if mode in ["all", "legacy44", "direct"]:
		direct_old_function()
		direct_old_callable()
		old_effect_descriptor()
	if mode in ["all", "legacy44", "loop"]:
		synchronous_foreach()
	if mode in ["all", "extra"]:
		additional_boundaries()
		same_domain_guard_resume()
		same_domain_loop_resume()
	EffectManager.activating_eff = null
	GameData.release_game_objects()
	print("RESULT ", JSON.stringify({"suite":"em14_execution_frame_origin","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
