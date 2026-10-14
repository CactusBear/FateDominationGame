extends Node

# A1-26 只验 CanGainMagic 的来源查询边界；不代替资源消费者做支付或写入。
var checks:int = 0
var failures:Array = []

func _ready():
	call_deferred("run")

func check(ok:bool, label:String):
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok:
		failures.append(label)

func fresh() -> Dictionary:
	var reset:Dictionary = GameData.reset_game_session([])
	check(reset.get("ok", false), "fresh session starts")
	var id:int = AddPlayer.new().exec(-1, [], {"player_name":"A1-26"}, reset.context)
	GameData.player_id = id
	var token:Dictionary = SessionGeneration.current_token()
	var context_result:Dictionary = SessionGeneration.derive_context(token.token, &"A1-26.query")
	check(context_result.get("ok", false), "fresh query context derives")
	return {"id":id, "context":context_result.get("context")}

func make_frame(context:SessionContext, player_id:int) -> Dictionary:
	var effect:BaseEffect = BaseEffect.new("a1_26_query", [], 0, true, false)
	var effect_binding:Dictionary = SessionGeneration.bind_origin(effect, context.token(), &"A1-26.effect")
	check(effect_binding.get("ok", false), "query effect origin binds")
	var effect_context:SessionContext = effect_binding.get("context")
	check(effect.bind_runtime_context(effect_context), "query effect keeps bound context")

	var operation := CanGainMagic.new()
	var function:BaseFunc = BaseFunc.new(Callable(operation, "exec"), ["", player_id])
	var function_binding:Dictionary = SessionGeneration.bind_origin(function, context.token(), &"A1-26.function")
	check(function_binding.get("ok", false), "query function origin binds")
	var function_context:SessionContext = function_binding.get("context")
	check(function.bind_runtime_context(function_context), "query function keeps bound context")
	# effect/function 各自保留由同一当前 token 派生的来源句柄；执行器按 token 复核，不要求句柄对象相同。
	return {"effect":effect, "function":function, "operation":operation, "context":function_context}

func run_query(frame:Dictionary, context:SessionContext) -> Array:
	return EffectManager.run_base_func(frame.function, frame.effect, context)

func no_source_is_explicit_rejection(fixture:Dictionary):
	GameLog.reset()
	var before_keys:Array = GameData.player_data_library.keys()
	var before_logs:int = GameLog.query({}, null).size()
	var result = CanGainMagic.new().exec("", fixture.id)
	check(result == null, "query without captured source returns explicit null")
	check(GameData.player_data_library.keys() == before_keys, "source rejection does not create players")
	check(GameLog.query({}, null).size() == before_logs, "source rejection does not write logs")

func legal_query_stays_a_query(fixture:Dictionary):
	var frame:Dictionary = make_frame(fixture.context, fixture.id)
	var player_data:Dictionary = GameDataManager.find_player_data(fixture.id)
	var before_magic:int = player_data.magic.number
	var before_keys:Array = GameData.player_data_library.keys()
	var output:Array = run_query(frame, frame.context)
	check(output.size() == 2 and output[0] and output[1] == true, "same-session no-ban query remains true")
	check(GameData.player_data_library.keys() == before_keys, "legal query does not change player collection")
	check(GameDataManager.find_player_data(fixture.id).magic.number == before_magic, "legal query does not change magic")

func unknown_member_is_not_consumer_authority(fixture:Dictionary):
	var unknown_id:int = 987654
	var frame:Dictionary = make_frame(fixture.context, unknown_id)
	var before_keys:Array = GameData.player_data_library.keys()
	var output:Array = run_query(frame, frame.context)
	check(output.size() == 2 and output[0] and output[1] == true, "unknown member keeps query bool semantics")
	check(not GameData.player_data_library.has(unknown_id), "query does not create unknown member")
	check(GameData.player_data_library.keys() == before_keys, "unknown query leaves member collection unchanged")
	# true 只表示没有禁令；资源消费者仍须自行认证成员并决定是否支付/写入。

func stale_source_is_rejected(fixture:Dictionary):
	var old_frame:Dictionary = make_frame(fixture.context, fixture.id)
	var old_context:SessionContext = old_frame.context
	var reset:Dictionary = GameData.reset_game_session([])
	check(reset.get("ok", false), "new session starts for stale query")
	var new_id:int = AddPlayer.new().exec(-1, [], {"player_name":"A1-26-new"}, reset.context)
	GameData.player_id = new_id
	GameLog.reset()
	var before_keys:Array = GameData.player_data_library.keys()
	var before_logs:int = GameLog.query({}, null).size()
	var before_magic:int = GameDataManager.find_player_data(new_id).magic.number
	var output:Array = run_query(old_frame, old_context)
	check(output.size() == 2 and not output[0] and output[1] == null, "stale source is rejected before query body")
	check(GameData.player_data_library.keys() == before_keys, "stale rejection does not create or remove players")
	check(GameDataManager.find_player_data(new_id).magic.number == before_magic, "stale rejection does not change magic")
	check(GameLog.query({}, null).size() == before_logs, "stale rejection does not write logs")

func run():
	print("ENV ", JSON.stringify({"user":OS.get_user_data_dir(), "res":ProjectSettings.globalize_path("res://"), "pid":OS.get_process_id()}))
	var fixture:Dictionary = fresh()
	no_source_is_explicit_rejection(fixture)
	legal_query_stays_a_query(fixture)
	unknown_member_is_not_consumer_authority(fixture)
	stale_source_is_rejected(fixture)
	print("RESULT ", JSON.stringify({"suite":"a1_26_cangainmagic_origin", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
