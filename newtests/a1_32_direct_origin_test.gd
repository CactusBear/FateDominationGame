extends Node

var checks:int = 0
var failures:Array = []
var hits:int = 0
var reentry_hits:int = 0
var reset_marker:bool = false:
	set(value):
		reset_marker = value
		if value:
			reentry_hits += 1
			GameData.reset_game_session([0, 1])
			GameLog.reset()
			GameData.player_data_library[0].dynamic_time_points = ["a1_32_reenter"]
			GameData.player_data_library[0].current_time_points = ["a1_32_reenter"]
var listener_marker:bool = false:
	set(value):
		listener_marker = value
		if value: hits += 1

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func start(ids:Array = [0, 1]) -> SessionContext:
	var result:Dictionary = GameData.reset_game_session(ids)
	check(result.ok, "PRE reset")
	GameData.player_id = 0
	GameLog.reset()
	TimePointChecker.phase_time_points = []
	return result.context

# 改前保原 arity，改后显式原句柄；业务 oracle 不变，不以参数错误作 RED。
func arguments(target:Object, method:String, values:Array, context:Variant) -> Array:
	for info in target.get_method_list():
		if info.name == StringName(method) and info.args.size() > values.size():
			return values + [context]
	return values

func invoke(target:Object, method:String, values:Array, context:Variant = null):
	return target.callv(method, arguments(target, method, values, context))

func saved(target:Object, method:String, values:Array, context:Variant) -> Callable:
	return Callable(target, method).bindv(arguments(target, method, values, context))

func effect(context:SessionContext, points:Array = [], funcs:Array = []) -> BaseEffect:
	var loaded:Array = LoadHelper.load_effects([{"effect_name":"a1-32-listener", "time_points":points,"priority":0,"is_pure_passive":true,"is_residue":false,"effect_numbers":[],"funcs":funcs}], null, context)
	check(loaded.size() == 1, "PRE effect factory")
	return loaded[0]

func buff(context:SessionContext) -> BaseBuff:
	var result:BaseBuff = BaseBuff.new("a1-32-buff", "")
	check(SessionGeneration.bind_origin(result, context.token(), &"a1_32_fixture").ok, "PRE explicit buff producer")
	result._effects = [effect(context)]
	result._effects[0].from = result
	return result

func seat(id:int):
	var loc:BaseLocation = MapData.miyama0
	loc._players = [id]
	GameData.player_data_library[id].location = loc
	return loc

func mutate_chain(kind:String) -> void:
	if kind == "progress": GameProgress.reset_progress()
	elif kind == "game": GameData.reset_game_session([0, 1])
	elif kind == "runtime": EffectManager.reset_runtime()
	elif kind == "release":
		GameData.release_game_objects()
		GameData.reset_game_session([0, 1])
	else:
		GameStart.end_session()
		GameData.reset_game_session([0, 1])
	GameLog.reset()
	TimePointChecker.phase_time_points = []

func creation() -> void:
	var context:SessionContext = start()
	var op:AddPlayer = AddPlayer.new()
	var count:int = GameData.player_data_library.size()
	invoke(op, "exec", [-2, [], {}])
	check(GameData.player_data_library.size() == count, "creation missing frame no member")
	context = start()
	var created = invoke(op, "exec", [-2, [], {"player_name":"NPC"}], context)
	check(created is int and GameData.player_data_library.has(created), "legal explicit creation")
	check(GameData.player_data_library[created].controller == -2, "NPC sentinel preserved")
	context = start()
	created = invoke(op, "exec", [0, ["score"], {}], context)
	check(is_same(GameData.player_data_library[created].score, GameData.player_data_library[0].score), "legal shared data identity")
	var old:Callable = saved(op, "exec", [-2, [], {}], context)
	start()
	count = GameData.player_data_library.size()
	old.call()
	check(GameData.player_data_library.size() == count, "old creation callable no new member")

func remove_and_data() -> void:
	for chain in ["progress", "game", "runtime", "release", "end_start"]:
		var context:SessionContext = start()
		var remove:RemoveFromBoard = RemoveFromBoard.new()
		var setter:SetPlayerData = SetPlayerData.new()
		var known:Dictionary = {"category":{"target":true}}
		var old_remove:Callable = saved(remove, "exec", [0], context)
		var old_set:Callable = saved(setter, "exec", ["known_info", known, 0], context)
		mutate_chain(chain)
		var loc = seat(0)
		var current:Dictionary = GameData.player_data_library[0]
		old_remove.call()
		check(current.location == loc and loc._players.has(0), "old same-ID seat preserved " + chain)
		old_set.call()
		check(not is_same(current.get("known_info"), known), "old knowledge reference refused " + chain)
		check(GameLog.query({}).is_empty(), "old direct operations no facts " + chain)
	var context:SessionContext = start()
	var loc = seat(0)
	invoke(RemoveFromBoard.new(), "exec", [0])
	check(GameData.player_data_library[0].location == loc and loc._players.has(0), "remove missing frame no seat write")
	var known:Dictionary = {"legal":true}
	invoke(SetPlayerData.new(), "exec", ["known_info", known, 0])
	check(not is_same(GameData.player_data_library[0].get("known_info"), known), "set missing frame no reference write")
	seat(0)
	check(invoke(RemoveFromBoard.new(), "exec", [0], context) == true, "legal removal")
	check(GameData.player_data_library[0].location == null and not loc._players.has(0), "legal removal updates precise seat")
	seat(0)
	check(invoke(RemoveFromBoard.new(), "exec", [0], context) == true, "same ID second legal removal not cached")
	context = start([0, 1, -9])
	seat(-9)
	check(invoke(RemoveFromBoard.new(), "exec", [-9], context) == true, "literal negative member removal")
	invoke(SetPlayerData.new(), "exec", ["known_info", known, -9], context)
	check(is_same(GameData.player_data_library[-9].known_info, known), "literal negative member keeps knowledge identity")
	invoke(SetPlayerData.new(), "exec", ["victory_override", 1, 0], context)
	check(GameData.player_data_library[0].victory_override == false, "existing type guard retained")
	var count:int = GameData.player_data_library.size()
	invoke(SetPlayerData.new(), "exec", ["known_info", {}, 999], context)
	check(GameData.player_data_library.size() == count, "setter unknown never creates")

func registration_and_buff() -> void:
	var context:SessionContext = start()
	var current:BaseBuff = buff(context)
	invoke(RegisterObjectEffects.new(), "exec", [current, 0])
	check(not EffectManager.effect_pool.has(current._effects[0]), "registration missing frame no pool write")
	invoke(RegisterObjectEffects.new(), "exec", [current, 0], context)
	check(EffectManager.effect_pool.has(current._effects[0]), "legal object registration")
	context = start()
	current = buff(context)
	invoke(ManageBuff.new(), "exec", [current, 0, true])
	check(not GameData.player_data_library[0].buffs.has(current), "buff missing frame no collection write")
	context = start()
	current = buff(context)
	check(invoke(ManageBuff.new(), "exec", [current, 0, true], context) == true, "legal buff add")
	check(GameData.player_data_library[0].buffs.has(current) and EffectManager.effect_pool.has(current._effects[0]), "legal buff and effect installed")
	check(invoke(ManageBuff.new(), "exec", [current, 0, false], context) == true, "legal buff remove")
	check(not GameData.player_data_library[0].buffs.has(current) and not EffectManager.effect_pool.has(current._effects[0]), "legal buff precise cleanup")
	var retained_manager:ManageBuff = ManageBuff.new()
	var old_add:Callable = saved(retained_manager, "exec", [current, 0, true], context)
	context = start()
	old_add.call()
	check(not GameData.player_data_library[0].buffs.has(current), "old buff callable no new collection write")
	invoke(ManageBuff.new(), "exec", [current, 0, true], context)
	check(not GameData.player_data_library[0].buffs.has(current), "old buff fresh context cannot wash runtime")
	var fresh:BaseBuff = buff(context)
	var count:int = GameData.player_data_library.size()
	invoke(ManageBuff.new(), "exec", [fresh, 999, true], context)
	check(GameData.player_data_library.size() == count, "buff unknown never creates")
	invoke(RegisterObjectEffects.new(), "exec", [fresh, 998], context)
	check(GameData.player_data_library.size() == count, "registration unknown never creates")

func time_points() -> void:
	var context:SessionContext = start()
	invoke(TimePointChecker, "global_time_point", [["a1_32_global"], null])
	check(GameLog.query({}).is_empty(), "global missing frame no fact")
	check(GameData.player_data_library[0].dynamic_time_points.is_empty(), "global missing frame no table write")
	invoke(TimePointChecker, "dynamic_time_point", [["a1_32_dynamic"], 0, null])
	check(GameData.player_data_library[0].dynamic_time_points.is_empty(), "dynamic missing frame no table write")
	var listener:BaseEffect = effect(context, ["a1_32_global"], [{"func_name":"set_property","parameters":[self,"listener_marker",true]}])
	check(EffectManager.register_effect(listener, 0), "PRE real global listener registered")
	hits = 0
	invoke(TimePointChecker, "global_time_point", [["a1_32_global"], null], context)
	check(hits == 1, "legal global real listener survives")
	check(GameData.player_data_library.size() == 2 and not GameData.player_data_library.has(-1), "global sentinel never creates local member")
	var old:Callable = saved(TimePointChecker, "global_time_point", [["a1_32_old"], null], context)
	context = start()
	old.call()
	check(GameLog.query({}).is_empty() and GameData.player_data_library[0].dynamic_time_points.is_empty(), "old global callable no new fact or table")
	invoke(TimePointChecker, "global_time_point", [["a1_32_old_runtime"], listener], context)
	check(GameLog.query({}).is_empty(), "old time-point runtime fresh context refused")
	listener = effect(context, ["self_a1_32_player"], [{"func_name":"set_property","parameters":[self,"listener_marker",true]}])
	check(EffectManager.register_effect(listener, 0), "PRE real player listener")
	hits = 0
	invoke(TimePointChecker, "player_time_point", [["a1_32_player"], 0, null], context)
	check(hits == 1, "legal player variant listener")
	var count:int = GameData.player_data_library.size()
	invoke(TimePointChecker, "dynamic_time_point", [["bad-member"], -1, null], context)
	check(GameData.player_data_library.size() == count and GameLog.query({"tags":["bad-member"]}).is_empty(), "dynamic literal minus-one never borrows local")

func extra_boundaries() -> void:
	#畸形/未签句柄逐入口正常拒绝，不用类型异常充当来源门。
	for bad in [{"token":"fake"}, SessionContext.new()]:
		var context:SessionContext = start()
		var current:BaseBuff = buff(context)
		var loc = seat(0)
		invoke(AddPlayer.new(), "exec", [-2, [], {}], bad)
		invoke(SetPlayerData.new(), "exec", ["probe_key", true, 0], bad)
		invoke(RemoveFromBoard.new(), "exec", [0], bad)
		invoke(ManageBuff.new(), "exec", [current, 0, true], bad)
		invoke(RegisterObjectEffects.new(), "exec", [current, 0], bad)
		invoke(TimePointChecker, "global_time_point", [["bad-context"], null], bad)
		check(GameData.player_data_library.size() == 2, "bad context creation closed")
		check(not GameData.player_data_library[0].has("probe_key"), "bad context assignment closed")
		check(GameData.player_data_library[0].location == loc and loc._players.has(0), "bad context seat closed")
		check(GameData.player_data_library[0].buffs.is_empty(), "bad context buff closed")
		check(not EffectManager.effect_pool.has(current._effects[0]), "bad context registration closed")
		check(GameLog.query({}).is_empty(), "bad context time-point no facts")
	var context:SessionContext = start()
	var source:BaseEffect = effect(context)
	check(EffectManager.register_effect(source, 1), "PRE default source owner")
	EffectManager.activating_eff = source
	invoke(SetPlayerData.new(), "exec", ["probe_key", true, -1], context)
	check(GameData.player_data_library[1].get("probe_key", false) and not GameData.player_data_library[0].has("probe_key"), "S02 effect default precedes local")
	EffectManager.activating_eff = null
	invoke(SetPlayerData.new(), "exec", ["local_probe", true, -1], context)
	check(GameData.player_data_library[GameData.player_id].get("local_probe", false), "S02 absent effect declared local fallback")
	context = start()
	EffectManager.activating_eff = source
	invoke(SetPlayerData.new(), "exec", ["old_default", true, -1], context)
	check(not GameData.player_data_library[1].has("old_default"), "stale activating effect never supplies default owner")
	EffectManager.activating_eff = null
	#真实函数帧中的原缺省 ABI 保留；不靠把activating_eff当票据。
	var known:Dictionary = {"frame":true}
	var runtime:BaseEffect = effect(context, [], [{"func_name":"set_player_data","parameters":["known_info",known,0]}])
	check(EffectManager.register_effect(runtime, 0), "PRE frame setter registered")
	var ran:Array = EffectManager.run_base_func(runtime._funcs[0], runtime, context)
	check(ran[0] and is_same(GameData.player_data_library[0].get("known_info"), known), "real frame default ABI writes original knowledge")
	var old_function:BaseFunc = runtime._funcs[0]
	context = start()
	ran = EffectManager.run_base_func(old_function, runtime, old_function.runtime_context())
	check(not ran[0] and not is_same(GameData.player_data_library[0].get("known_info"), known), "old BaseFunc knowledge cannot attach new session")
	#阶段门只接来源；持续窗口匹配和消费仍使用原注册表语义。
	TimePointChecker.phase_time_points = ["kept"]
	invoke(TimePointChecker, "set_phase_time_points", [["missing"]])
	check(TimePointChecker.phase_time_points == ["kept"], "phase missing frame does not replace table")
	var old_phase:Callable = saved(TimePointChecker, "set_phase_time_points", [["old-phase"]], context)
	context = start()
	TimePointChecker.phase_time_points = ["new-phase"]
	old_phase.call()
	check(TimePointChecker.phase_time_points == ["new-phase"], "old phase callable no table replacement")
	invoke(TimePointChecker, "set_phase_time_points", [["legal-phase"]], context)
	check(TimePointChecker.phase_time_points == ["legal-phase"] and GameData.player_data_library[0].current_time_points == ["legal-phase"], "legal phase table propagated")
	#整批buff来源预检先于append；EM叶子门不是buff容器源门的替代品。
	var stale:BaseEffect = effect(context)
	context = start()
	var mixed:BaseBuff = buff(context)
	mixed._effects.append(stale)
	invoke(ManageBuff.new(), "exec", [mixed, 0, true], context)
	check(not GameData.player_data_library[0].buffs.has(mixed) and not EffectManager.effect_pool.has(mixed._effects[0]), "mixed buff preflight no partial registration")
	#显式来源同步监听换局后，global旧尾部不得erase新局同名事件。
	context = start()
	var listener:BaseEffect = effect(context, ["a1_32_reenter"], [{"func_name":"set_property","parameters":[self,"reset_marker",true]}])
	check(EffectManager.register_effect(listener, 0), "PRE reentry listener")
	var event_source:BaseEffect = effect(context)
	reentry_hits = 0
	invoke(TimePointChecker, "global_time_point", [["a1_32_reenter"], event_source], context)
	check(reentry_hits == 1, "PRE real synchronous time-point reset")
	check(GameData.player_data_library[0].dynamic_time_points.has("a1_32_reenter"), "old global tail never erases new table")
	check(GameData.player_data_library[0].current_time_points.has("a1_32_reenter"), "old global tail never updates new table")

func _ready() -> void:
	print("ENV ", OS.get_user_data_dir())
	creation()
	remove_and_data()
	registration_and_buff()
	time_points()
	extra_boundaries()
	print("RESULT ", JSON.stringify({"suite":"a1_32_direct_origin","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
