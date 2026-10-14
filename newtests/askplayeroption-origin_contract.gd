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
	if not check(reset.ok, "trusted lifecycle supplies original context"): return false
	context = reset.context
	GameData.player_data_library[0] = GameData.new_player_data()
	return check(not GameDataManager.find_player_data(0).is_empty(), "real owner exists")

func snapshot() -> Array:
	return [GameData.objects.duplicate(), GameData.effects.duplicate(),
		GameLog.query({}, null, -1).duplicate(true), EffectManager.get_pending_active_effect(),
		EffectManager.is_waiting_for_choice(), EffectManager.is_running]

func options() -> Array:
	return [
		{"shown_option_name":"first", "funcs":[{"func_name":"store_value", "parameters":[{"self_var":0}], "var_index":5}]},
		{"shown_option_name":"second", "max_uses":2, "tags":["declared"], "funcs":[
			{"func_name":"store_value", "parameters":[{"self_var":0}], "var_index":5},
			{"func_name":"store_value", "parameters":["second"], "var_index":7}]}
	]

func parent(max_choices:Variant = null, owner:int = -1) -> BaseEffect:
	var args:Array = [options()]
	if max_choices != null: args.append_array(["explicit", owner, max_choices])
	var declaration:Dictionary = {"effect_name":"original_parent", "shown_effect_name":"parent shown",
		"time_points":[], "priority":0, "is_pure_passive":true, "is_residue":false,
		"need_activate":false, "effect_numbers":[], "funcs":[
			{"func_name":"store_value", "parameters":["retained value"], "var_index":0},
			{"func_name":"ask_player_option", "parameters":args, "var_index":1},
			{"func_name":"store_value", "parameters":[{"self_var":5}], "var_index":6}
		]}
	var produced:Array = LoadHelper.load_effects([declaration], null, context)
	if not check(produced.size() == 1, "parent created by trusted original-context factory"): return null
	var effect:BaseEffect = produced[0]
	retained.append(effect)
	effect.set_numbers([BaseNumber.new(7)])
	effect._using_numbers = effect.numbers
	effect._trigger_time_points = ["original_trigger"]
	if not check(EffectManager.register_effects([effect], 0), "real parent registered"): return null
	return effect

func valid(max_choices:Variant = null) -> void:
	if not setup(): return
	var root:BaseEffect = parent(max_choices, 0)
	if root == null: return
	var original:SessionContext = root.runtime_context()
	var binding:Dictionary = SessionGeneration.origin_of(root)
	check(binding.ok and is_same(binding.context, original), "parent canonical original context captured before execution")
	EffectManager.activate_effect(root)
	var child:BaseEffect = EffectManager.get_pending_active_effect()
	if not check(child != null and child.has_options(), "original-context child really pauses parent"): return
	var child_origin:Dictionary = SessionGeneration.origin_of(child)
	check(child_origin.ok and child.runtime_source_status().ok, "child source publicly verifiable")
	check(is_same(child_origin.context, child.runtime_context()), "child runtime context is canonical binding")
	check(is_same(child.runtime_context().token(), original.token()), "child retains original parent token")
	check(child.runtime_context().origin() == original.origin(), "child retains original parent origin not a hardcoded factory label")
	check(is_same(root.runtime_context(), original), "parent original handle was not replaced")
	check(child._name == "original_parent_choice" and child._trigger_player_id == 0, "name and resolved owner unchanged")
	check(child._shown_name == ("parent shown" if max_choices == null else "explicit"), "shown-name fallback and override unchanged")
	check(child._max_choices == (1 if max_choices == null else max_choices), "default and unlimited maximum unchanged")
	check(not child._need_activate and child._remove_after_trigger, "choice lifetime flags unchanged")
	check(is_same(child.numbers, root.numbers) and is_same(child._using_numbers, root._using_numbers), "original number containers shared")
	check(child._trigger_time_points == root._trigger_time_points and not is_same(child._trigger_time_points, root._trigger_time_points), "trigger values copied without alias")
	check(child._options.size() == 2 and child._options[0].shown_option_name == "first" and child._options[1].shown_option_name == "second", "option collection and order preserved")
	check(child._options[0].max_uses == -1 and child._options[1].max_uses == 2 and child._options[1].tags == ["declared"], "option defaults and declarations preserved")
	var functions_ok:bool = true
	for option in child._options:
		for function:BaseFunc in option.funcs:
			var origin:Dictionary = SessionGeneration.origin_of(function)
			functions_ok = functions_ok and origin.ok and is_same(origin.context.token(), original.token()) and origin.context.origin() == original.origin() and function.runtime_source_status(child, original).ok
	check(functions_ok, "every option function inherits original source")
	check(root._self_vars.size() < 7, "parent tail suspended before answer")
	check(EffectManager.submit_option_choice(child, [1] if max_choices == null else [0, 1]), "public selection accepted")
	check(root._self_vars.size() > 7 and root._self_vars[5] == "retained value" and root._self_vars[6] == "retained value" and root._self_vars[7] == "second", "option and parent continuation share original variables")
	check(not EffectManager.is_waiting_for_choice() and not EffectManager.is_running, "pipeline completed after answer")
	var before:Array = snapshot()
	check(not EffectManager.submit_option_choice(child, [1]), "duplicate completion refused")
	check(snapshot() == before, "duplicate completion has no side effects")

func missing_frame() -> void:
	if not setup(): return
	var root:BaseEffect = parent()
	if root == null: return
	EffectManager.activating_eff = root
	var before:Array = snapshot()
	check(AskPlayerOption.new().exec(options(), "", 0) == null, "assigning fresh parent does not create source frame")
	check(snapshot() == before, "missing source refuses before allocations facts or waits")
	EffectManager.activating_eff = null

func stale() -> void:
	if not setup(): return
	var old_root:BaseEffect = parent()
	if old_root == null: return
	var original:SessionContext = old_root.runtime_context()
	EffectManager.activate_effect(old_root)
	var old_child:BaseEffect = EffectManager.get_pending_active_effect()
	if not check(old_child != null, "old generation has real pending choice"): return
	var old_function:BaseFunc = old_root._funcs[1]
	if not setup(): return
	var fresh_root:BaseEffect = parent()
	if fresh_root == null: return
	EffectManager.activate_effect(fresh_root)
	var fresh_child:BaseEffect = EffectManager.get_pending_active_effect()
	if not check(fresh_child != null, "new generation has independent same-owner choice"): return
	check(not SessionGeneration.validate_context(original).ok and not old_child.runtime_source_status().ok, "original parent and child source revoked by lifecycle")
	var before:Array = snapshot()
	var outcome:Array = EffectManager.run_base_func(old_function, fresh_root, original)
	check(not bool(outcome[0]), "old function cannot borrow fresh parent or generation")
	check(snapshot() == before, "old source rejection leaves current objects facts and pending identity unchanged")
	EffectManager.activating_eff = old_root
	check(AskPlayerOption.new().exec(options(), "", 0) == null, "old assigned parent cannot obtain current source")
	check(snapshot() == before, "old assigned parent rejection has no effects")
	EffectManager.activating_eff = null
	check(not EffectManager.submit_option_choice(old_child, [0]), "old completion rejected")
	check(snapshot() == before, "old completion preserves fresh pending and facts")
	check(EffectManager.submit_option_choice(fresh_child, [1]), "fresh original-context choice still works")

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	print("USER_PATH ", OS.get_user_data_dir())
	missing_frame()
	valid()
	valid(-1)
	stale()
	print("RESULT ", JSON.stringify({"suite":"askplayeroption-origin", "checks":checks, "failures":failures}))
	GameStart.end_session()
	get_tree().quit(0 if failures.is_empty() else 1)
