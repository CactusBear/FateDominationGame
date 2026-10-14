extends Node

const Router = preload("res://scripts/system/operation_router.gd")
var router_script:Script = Router
var checks:int = 0
var failures:Array = []

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", label, " ", ok)

# 改前二参 ABI 也能跑同一业务 oracle；不以 arity/解析错误充当 RED。
func route(name:String, parameters:Array, context:Variant) -> Variant:
	for method in router_script.get_script_method_list():
		if method.name == "exec_registered" and method.args.size() >= 3:
			return Callable(Router, "exec_registered").callv([name, parameters, context])
	return Router.exec_registered(name, parameters)

func runtime(funcs:Array, context:SessionContext) -> BaseEffect:
	var effects:Array = LoadHelper.load_effects([{
		"effect_name":"a1_30_runtime", "time_points":[], "priority":0,
		"is_pure_passive":true, "is_residue":false, "need_activate":false, "effect_numbers":[],
		"funcs":funcs
	}], null, context)
	check(effects.size() == 1, "LoadHelper_runtime_created")
	return effects[0] if effects.size() == 1 else null

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	print("USER_PATH ", OS.get_user_data_dir())
	var setup:Dictionary = GameData.reset_game_session([0, 1])
	check(setup.ok, "session_setup")
	if not setup.ok:
		finish()
		return
	var context:SessionContext = setup.context
	var data:Dictionary = GameDataManager.find_player_data(0)
	var other:Dictionary = GameDataManager.find_player_data(1)
	var power:BaseNumber = data.power
	var keys:Array = GameData.player_data_library.keys()
	power.set_num(BaseNumber.new(13))
	check(not EffectManager.execution_context().ok, "no_executor_frame")
	check(Router.exec_registered("sync_power", [0]) == null, "missing_source_null")
	check(power.number == 13, "missing_source_no_write")
	route("sync_power", [0], {"token":"forged"})
	check(power.number == 13, "malformed_source_no_write")
	route("sync_power", [0], SessionContext.new())
	check(power.number == 13, "unissued_source_no_write")
	route("sync_power", [0], context)
	check(power.number == 0, "explicit_current_business_write")
	check(GameData.player_data_library.keys() == keys, "source_gate_no_player_creation")

	var buff:BaseBuff = BaseBuff.new("a1_30_buff", "")
	buff.add_buff_effect(BaseEffect.new("a1_30_buff_effect", []))
	data.buffs.append(buff)
	check(AllOperations.get_entry("player_buffs_have_effect").get("class") == "PlayerBuffsHaveEffect", "A7_buff_TABLE")
	check(route("player_buffs_have_effect", ["a1_30_buff_effect", 0], context) == true, "A7_buff_registered_true")
	check(route("player_buffs_have_effect", ["absent", 0], context) == false, "A7_buff_registered_false")
	check(AllOperations.get_entry("emit_time_point").get("class") == "EmitTimePoint", "A7_emit_TABLE")
	route("emit_time_point", ["a1_30_registered", -1, context], context)
	check(GameLog.query({"type":"time_point", "tags":"a1_30_registered"}, null, -1).size() == 1, "A7_emit_registered_business")

	var effect:BaseEffect = runtime([
		{"func_name":"player_buffs_have_effect", "parameters":["a1_30_buff_effect", 0]},
		{"func_name":"emit_time_point", "parameters":["a1_30_loader", -1]}
	], context)
	if effect != null:
		check(effect._funcs.size() == 2, "A7_LoadHelper_two_registered_funcs")
		if effect._funcs.size() == 2:
			var queried:Array = EffectManager.run_base_func(effect._funcs[0], effect, effect.runtime_context())
			check(queried[0] and queried[1] == true, "A7_LoadHelper_buff_business")
			var emitted:Array = EffectManager.run_base_func(effect._funcs[1], effect, effect.runtime_context())
			check(emitted[0] and GameLog.query({"type":"time_point", "tags":"a1_30_loader"}, null, -1).size() == 1, "A7_LoadHelper_emit_business")

	# 正式 CloseCard 的旧二参嵌套路由，在真实已验 BaseFunc 帧内继承来源。
	var card:BaseAttack = BaseAttack.new("a1_30_attack", "", [], BaseNumber.new(0), BaseNumber.new(3))
	# 夹具是新卡生产者；显式登记来源，不在路由/翻面消费口补票。
	check(SessionGeneration.bind_origin(card, context.token(), &"a1_30.new_card").ok, "fresh_card_explicit_origin")
	data.played_cards.append(card)
	power.set_num(BaseNumber.new(3))
	var closer:BaseEffect = runtime([{"func_name":"close_card", "parameters":[card, 0]}], context)
	if closer != null and not closer._funcs.is_empty():
		var closed:Array = EffectManager.run_base_func(closer._funcs[0], closer, closer.runtime_context())
		check(closed[0] and card._is_closed and card._is_concealed, "legacy_two_args_in_verified_frame")
		check(power.number == 0, "legacy_nested_business_unchanged")
	check(not EffectManager.execution_context().ok, "executor_frame_not_leaked")

	# 保存时捕获第三参；消费时不领新票，不增设另一套派发入口。
	var saved:Callable = Callable(Router, "exec_registered").bind("sync_power", [0], context)
	var generation:Dictionary = SessionGeneration.begin_generation(&"a1_30_same_dictionary")
	var fresh:Dictionary = SessionGeneration.derive_context(generation.token, &"a1_30_new_action")
	check(fresh.ok and not SessionGeneration.validate_context(context).ok, "old_context_revoked")
	check(is_same(data, GameDataManager.find_player_data(0)), "same_id_dictionary_retained")
	power.set_num(BaseNumber.new(19))
	route("sync_power", [0], context)
	check(power.number == 19, "stale_explicit_no_new_session_write")
	# baseline 二参脚本不调用不兼容 Callable；旧业务 RED 已由 stale_explicit 观察。
	for method in router_script.get_script_method_list():
		if method.name == "exec_registered" and method.args.size() >= 3:
			check(saved.call() == null and power.number == 19, "saved_callable_original_source_rejected")
	Router.exec_registered("sync_power", [0])
	check(power.number == 19, "missing_source_not_refreshed_to_current")
	route("emit_time_point", ["a1_30_stale", -1], context)
	check(GameLog.query({"type":"time_point", "tags":"a1_30_stale"}, null, -1).is_empty(), "stale_emit_no_fact")
	check(route("player_buffs_have_effect", ["a1_30_buff_effect", 0], context) == null, "stale_buff_not_success")
	route("sync_power", [0], fresh.context)
	check(power.number == 0, "new_context_same_id_legal")
	# CloseCard 留暗置牌，不计威力，正常重算应为0。
	check(card._is_concealed, "old_frame_card_still_concealed")
	if OS.get_cmdline_user_args().has("unknown"):
		check(route("a1_30_unknown", [], fresh.context) == null, "unknown_route_original_null")
	finish()

func finish() -> void:
	print("RESULT ", JSON.stringify({"checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
