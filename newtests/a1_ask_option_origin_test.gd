extends Node

var checks:int = 0
var failures:Array = []
var context:SessionContext = null
var retained:Array = []

func check(ok:bool, label:String) -> bool:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)
	return ok

func setup() -> bool:
	GameStart.end_session()
	var reset:Dictionary = GameData.reset_game_session([])
	if not check(reset.ok, "real session creates original context"): return false
	context = reset.context
	# 本守卫只测试选择来源，成员数据与已有比较夹具使用同一公开构造器。
	GameData.player_data_library[0] = GameData.new_player_data()
	return check(not GameDataManager.find_player_data(0).is_empty(), "known owner fixture exists")

func options() -> Array:
	return [
		{"shown_option_name":"A", "funcs":[{"func_name":"store_value", "parameters":[{"self_var":0}], "var_index":5}]},
		{"shown_option_name":"B", "max_uses":2, "tags":["chosen-b"], "funcs":[
			{"func_name":"store_value", "parameters":[{"self_var":0}], "var_index":5},
			{"func_name":"store_value", "parameters":["B"], "var_index":7}]}
	]

func parent_with_choice(max_choices = null) -> BaseEffect:
	var parameters:Array = [options()]
	if max_choices != null: parameters.append_array(["explicit", 0, max_choices])
	var declaration:Dictionary = {"effect_name":"origin_parent", "shown_effect_name":"parent shown",
		"time_points":[], "priority":0, "is_pure_passive":true, "is_residue":false,
		"need_activate":false, "effect_numbers":[], "funcs":[
			{"func_name":"store_value", "parameters":["seed"], "var_index":0},
			{"func_name":"ask_player_option", "parameters":parameters, "var_index":1},
			{"func_name":"store_value", "parameters":[{"self_var":5}], "var_index":6}
		]}
	var produced:Array = LoadHelper.load_effects([declaration], null, context)
	if not check(produced.size() == 1, "parent trusted runtime factory"): return null
	var parent:BaseEffect = produced[0]
	retained.append(parent)
	parent.set_numbers([BaseNumber.new(7)])
	parent._using_numbers = parent.numbers
	parent._trigger_time_points = ["origin_probe"]
	if not check(EffectManager.register_effects([parent], 0), "parent frozen public registration ABI"): return null
	return parent

func no_frame() -> void:
	if not setup(): return
	var parent:BaseEffect = parent_with_choice()
	if parent == null: return
	EffectManager.activating_eff = parent
	var before:Array = [GameData.objects.size(), GameData.effects.size(), GameLog.query({},null,-1).duplicate(true)]
	check(AskPlayerOption.new().exec(options(), "", 0) == null, "fresh activating effect cannot mint missing frame origin")
	check(before == [GameData.objects.size(), GameData.effects.size(), GameLog.query({},null,-1)], "missing frame rejection has no allocations or facts")
	check(not EffectManager.is_waiting_for_choice(), "missing frame cannot publish choice")
	EffectManager.activating_eff = null

func valid_choice(max_choices = null) -> void:
	if not setup(): return
	var parent:BaseEffect = parent_with_choice(max_choices)
	if parent == null: return
	EffectManager.activate_effect(parent)
	var child:BaseEffect = EffectManager.get_pending_active_effect()
	if not check(child != null and child.has_options(), "real child choice pauses parent"): return
	check(child.runtime_source_status().ok, "child runtime source is verifiable")
	var origin:Dictionary = SessionGeneration.origin_of(child)
	check(origin.ok and is_same(origin.context, child.runtime_context()), "child has canonical bound provenance")
	check(is_same(child.runtime_context().token(), context.token()), "child inherits original session token")
	check(child.runtime_context().origin() == parent.runtime_context().origin(), "child inherits original source provenance")
	check(child._trigger_player_id == 0 and child._name == "origin_parent_choice", "owner and name unchanged")
	check(child._shown_name == ("parent shown" if max_choices == null else "explicit"), "shown name fallback and override unchanged")
	check(child._max_choices == (1 if max_choices == null else max_choices), "default single and explicit unlimited unchanged")
	check(not child._need_activate and child._remove_after_trigger, "choice lifetime flags unchanged")
	check(is_same(child.numbers,parent.numbers) and is_same(child._using_numbers,parent._using_numbers), "parent child number containers shared")
	check(child._trigger_time_points == parent._trigger_time_points and not is_same(child._trigger_time_points,parent._trigger_time_points), "trigger values copied without alias")
	check(child._options.size() == 2 and child._options[0].shown_option_name == "A" and child._options[1].shown_option_name == "B", "option set and declaration order unchanged")
	check(child._options[0].max_uses == -1 and child._options[1].max_uses == 2 and child._options[1].tags == ["chosen-b"], "option defaults and declared fields unchanged")
	var sources_ok:bool = true
	for opt in child._options:
		for f:BaseFunc in opt.funcs:
			sources_ok = sources_ok and f.runtime_source_status(child, context).ok
	check(sources_ok, "all child option functions retain original source")
	check(parent._self_vars.size() < 7, "tail not executed before answer")
	check(EffectManager.submit_option_choice(child, [1] if max_choices == null else [0,1]), "public selection accepted")
	check(parent._self_vars.size() > 7 and parent._self_vars[5] == "seed" and parent._self_vars[6] == "seed" and parent._self_vars[7] == "B", "selected functions and parent tail share original variable table")
	check(not EffectManager.is_waiting_for_choice() and not EffectManager.is_running, "answer resumes pipeline exactly to completion")
	var facts:Array = GameLog.query({},null,-1).duplicate(true)
	check(not EffectManager.submit_option_choice(child,[1]) and facts == GameLog.query({},null,-1), "duplicate answer rejected without new facts")

func stale() -> void:
	if not setup(): return
	var parent:BaseEffect = parent_with_choice()
	if parent == null: return
	EffectManager.activate_effect(parent)
	var old_child:BaseEffect = EffectManager.get_pending_active_effect()
	if not check(old_child != null, "stale probe starts from real waiting child"): return
	var old_context:SessionContext = context
	var old_function:BaseFunc = parent._funcs[1]
	if not setup(): return
	var fresh:BaseEffect = parent_with_choice()
	if fresh == null: return
	EffectManager.activate_effect(fresh)
	var fresh_child:BaseEffect = EffectManager.get_pending_active_effect()
	if not check(fresh_child != null, "new session owns independent same-id choice"): return
	var before:Array = [GameData.objects.size(), GameData.effects.size(), GameLog.query({},null,-1).duplicate(true)]
	check(not SessionGeneration.validate_context(old_context).ok and not old_child.runtime_source_status().ok, "old context and child remain stale")
	var outcome:Array = EffectManager.run_base_func(old_function, fresh, old_context)
	check(not bool(outcome[0]), "old ask function cannot borrow new parent source")
	EffectManager.activating_eff = parent
	check(AskPlayerOption.new().exec(options(), "", 0) == null, "old activating effect cannot borrow current session")
	EffectManager.activating_eff = null
	check(not EffectManager.submit_option_choice(old_child,[0]), "old child answer rejected")
	check(is_same(EffectManager.get_pending_active_effect(),fresh_child), "stale rejection preserves exact new waiting choice")
	check(before == [GameData.objects.size(), GameData.effects.size(), GameLog.query({},null,-1)], "stale rejection creates no objects or facts")
	check(EffectManager.submit_option_choice(fresh_child,[1]), "new same-id choice still answers normally")

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	no_frame()
	valid_choice()
	valid_choice(-1)
	stale()
	print("RESULT ", JSON.stringify({"suite":"a1_ask_option_origin", "checks":checks, "failures":failures}))
	GameStart.end_session()
	get_tree().quit(0 if failures.is_empty() else 1)
