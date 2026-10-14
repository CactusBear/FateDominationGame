extends Node
# 只使用真实生命周期、可信工厂及公开函数执行帧；不伪造战斗或帧栈。
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
	if not check(reset.ok, "original lifecycle context"): return false
	context = reset.context
	for id in range(3):
		var data:Dictionary = GameData.new_player_data()
		data.order.number = id
		GameData.player_data_library[id] = data
	return true

func root() -> BaseEffect:
	var declaration:Dictionary = {"effect_name":"queue_origin_parent", "time_points":[], "priority":0,
		"is_pure_passive":true, "is_residue":false, "need_activate":false, "effect_numbers":[], "funcs":[]}
	var produced:Array = LoadHelper.load_effects([declaration], null, context)
	if not check(produced.size() == 1, "trusted parent factory"): return null
	var effect:BaseEffect = produced[0]
	retained.append(effect)
	effect.set_numbers([BaseNumber.new(7)])
	effect._using_numbers = effect.numbers
	if not check(EffectManager.register_effect(effect, 0), "parent registration"): return null
	return effect

func snapshot() -> Array:
	return [GameData.objects.duplicate(), GameData.effects.duplicate(), EffectManager.effect_pool.duplicate(),
		EffectManager.decision_queue.duplicate(), GameLog.query({}, null, -1).duplicate(true), EffectManager.get_pending_active_effect()]

func options() -> Array:
	return [{"shown_option_name":"first", "funcs":[{"func_name":"store_value", "parameters":[{"number_index":0}], "var_index":0}]},
		{"shown_option_name":"second", "max_uses":2, "tags":["declared"], "funcs":[]}]

func invoke(parent:BaseEffect, players:Array, funcs:Array, opts:Array = []) -> Array:
	# activating_eff 仅用于原数字环境；来源资格由 run_func_descriptor 真正建立的函数帧提供。
	EffectManager.activating_eff = parent
	var outcome:Array = EffectManager.run_func_descriptor({"func_name":"queue_optional_effect_for_players",
		"parameters":[players, funcs, "shown", "queued_origin_choice", opts]}, parent, parent.runtime_context())
	EffectManager.activating_eff = null
	return outcome

func no_frame() -> void:
	if not setup(): return
	var parent:BaseEffect = root()
	if parent == null: return
	EffectManager.activating_eff = parent
	var before:Array = snapshot()
	check(QueueOptionalEffectForPlayers.new().exec([1,2], [], "shown", "missing", options()).is_empty(), "no verified frame returns zero queued")
	check(snapshot() == before, "no frame allocates registers or queues nothing")
	check(not EffectManager.is_waiting_for_choice(), "assigned parent does not publish a wait")
	EffectManager.activating_eff = null

func valid(kind:String) -> void:
	if not setup(): return
	var parent:BaseEffect = root()
	if parent == null: return
	var funcs:Array = []
	var supplied:BaseFunc = null
	var descriptor:Dictionary = {"func_name":"store_value", "parameters":[{"number_index":0}], "var_index":0}
	if kind == "dictionary": funcs = [descriptor]
	if kind == "basefunc":
		var loaded:Array = LoadHelper.load_funcs([descriptor], parent, context)
		if not check(loaded.size() == 1, "supplied BaseFunc uses trusted factory"): return
		supplied = loaded[0]
		retained.append(supplied)
		funcs = [supplied]
	var outcome:Array = invoke(parent, [1,99,2], funcs, options() if kind == "options" else [])
	var children:Array = outcome[1] if outcome[1] is Array else []
	if not check(bool(outcome[0]) and children.size() == 2, kind + ": real frame returns two independent choices"): return
	check(EffectManager.decision_queue == children and not EffectManager.is_waiting_for_choice(), kind + ": only queues without immediate single-player pause")
	check(children[0] != children[1] and children[0]._trigger_player_id == 1 and children[1]._trigger_player_id == 2, kind + ": unknown member skipped and original order kept")
	check(not GameData.player_data_library.has(99), kind + ": unknown member never creates data")
	for child:BaseEffect in children:
		var origin:Dictionary = SessionGeneration.origin_of(child)
		check(origin.ok and child.runtime_source_status().ok and is_same(origin.context, child.runtime_context()), kind + ": canonical child source")
		check(is_same(child.runtime_context().token(), parent.runtime_context().token()) and child.runtime_context().origin() == parent.runtime_context().origin(), kind + ": original token and origin inherited")
		check(EffectManager.effect_pool.has(child) and GameDataManager.find_player_data(child._trigger_player_id).self_effects.has(child), kind + ": published only after real registration")
		check(child._name == "queued_origin_choice" and child._shown_name == "shown" and not child._need_activate and child._remove_after_trigger and child._trigger_time_points.is_empty(), kind + ": names flags trigger semantics preserved")
		check(is_same(child.numbers,parent.numbers) and is_same(child._using_numbers,parent._using_numbers), kind + ": original numeric containers shared")
		var functions:Array = child._funcs
		if kind == "options":
			check(child._options.size() == 2 and child._options[0].shown_option_name == "first" and child._options[1].shown_option_name == "second" and child._options[1].max_uses == 2 and child._options[1].tags == ["declared"], "options fields and order preserved")
			functions = child._options[0].funcs
		if not check(functions.size() == 1, kind + ": parser or cloner delivers complete function"): continue
		var function:BaseFunc = functions[0]
		check(function.runtime_source_status(child,context).ok and function.execution_capability_status().ok, kind + ": parsed or cloned function has original source and capability")
		var function_origin:Dictionary = SessionGeneration.origin_of(function)
		check(function_origin.ok and is_same(function_origin.context.token(), context.token()) and function_origin.context.origin() == parent.runtime_context().origin(), kind + ": public function clone or factory domain is registered")
		if supplied != null:
			check(function != supplied and is_same(function.runtime_context(), supplied.runtime_context()), "BaseFunc public clone preserves exact original context")
		var executed:Array = EffectManager.run_base_func(function, child, child.runtime_context())
		check(bool(executed[0]) and child._self_vars.size() == 1 and is_same(child._self_vars[0], parent.numbers[0]), kind + ": real function resolves original number environment")
	check(not is_same(children[0]._funcs, children[1]._funcs) and not is_same(children[0]._options,children[1]._options), kind + ": per-player collections do not alias")
	children[0]._chosen_selection = {0:1}
	check(children[1]._chosen_selection.is_empty(), kind + ": choice answers never leak across players")

func registration_rejection() -> void:
	if not setup(): return
	var parent:BaseEffect = root()
	if parent == null: return
	# 保留原 library.has 成员语义，登记 owner 公共契约仍拒绝空记录。
	GameData.player_data_library[9] = {}
	var before:Array = snapshot()
	var outcome:Array = invoke(parent, [9], [])
	check(bool(outcome[0]) and outcome[1] is Array and outcome[1].is_empty(), "registration refusal is never successful queued")
	check(EffectManager.decision_queue.is_empty() and EffectManager.effect_pool == before[2], "registration refusal publishes no choice")
	check(GameData.objects == before[0] and GameData.effects == before[1], "ordinary refusal discards only unpublished object")
	check(GameData.player_data_library[9].is_empty(), "registration refusal never repairs owner data")
	# 恢复仅此负向夹具制造的空 owner，避免下个生命周期清理读取缺失字段。
	GameData.player_data_library.erase(9)

func stale() -> void:
	if not setup(): return
	var old:BaseEffect = root()
	if old == null: return
	var loaded:Array = LoadHelper.load_funcs([{"func_name":"queue_optional_effect_for_players", "parameters":[[1,2], [], "stale", "old", options()]}],old,context)
	if not check(loaded.size() == 1, "old queue function captured by trusted factory"): return
	var old_function:BaseFunc = loaded[0]
	var old_context:SessionContext = old.runtime_context()
	retained.append(old_function)
	if not setup(): return
	var fresh:BaseEffect = root()
	if fresh == null: return
	var before:Array = snapshot()
	check(not SessionGeneration.validate_context(old_context).ok, "original source revoked by lifecycle")
	var outcome:Array = EffectManager.run_base_func(old_function, fresh, old_context)
	check(not bool(outcome[0]), "expired original frame cannot borrow fresh parent")
	check(snapshot() == before, "expired original source publishes nothing")
	EffectManager.activating_eff = old
	check(QueueOptionalEffectForPlayers.new().exec([1,2], []).is_empty(), "stale assigned parent cannot obtain current frame")
	check(snapshot() == before, "stale direct refusal preserves fresh collections")
	EffectManager.activating_eff = null

func audit_rejection() -> void:
	if not setup(): return
	var parent:BaseEffect = root()
	if parent == null: return
	# 真实登记审计拒绝门，不修改 EffectManager、不安装伪规则回调。
	MatchJournal.audit_error = "queue-origin deliberate audit refusal"
	var outcome:Array = invoke(parent, [1,2], [])
	check(not bool(outcome[0]) and outcome[1] == null, "audit refusal cannot report completed queue result")
	check(EffectManager.runtime_guard_status().paused, "audit refusal belongs to existing runtime guard")
	check(EffectManager.decision_queue.is_empty(), "audit registration refusal never publishes unregistered choice")
	var unpublished:Array = []
	for effect in GameData.effects:
		if effect is BaseEffect and effect._name == "queued_origin_choice": unpublished.append(effect)
	check(unpublished.size() == 1, "audit pending stops before creating next player and retains owner object")
	if unpublished.size() == 1:
		check(EffectManager.runtime_guard_effect() == unpublished[0] and not EffectManager.effect_pool.has(unpublished[0]), "audit pending retains exact owner and no success registration")
	# 仅撤掉本夹具注入的审计错误；公开 resume 仍不能消费缺少原生尾部记录的暂停。
	MatchJournal.audit_error = ""
	check(not EffectManager.resume_runtime_guard(), "audit recovery lacks supported queue native-tail continuation ABI")
	check(EffectManager.runtime_guard_status().paused and EffectManager.decision_queue.is_empty(), "unsupported audit recovery stays pending without publishing success")
	# 不自造恢复逻辑；测试结束交给已有 lifecycle 清理。

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	print("USER_PATH ", OS.get_user_data_dir())
	no_frame()
	valid("options")
	valid("dictionary")
	valid("basefunc")
	registration_rejection()
	stale()
	audit_rejection()
	print("RESULT ", JSON.stringify({"suite":"queue_optional_origin", "checks":checks, "failures":failures}))
	GameStart.end_session()
	get_tree().quit(0 if failures.is_empty() else 1)
