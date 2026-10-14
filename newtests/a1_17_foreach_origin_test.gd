extends "res://newtests/em14_execution_frame_origin_test.gd"

var helper_result:Variant = null
var medusa_seed:bool = false:
	set(value):
		medusa_seed = value
		if value:
			var effect:BaseEffect = EffectManager.activating_eff
			effect._self_vars.resize(27)
			effect._self_vars[7] = 1
			effect._self_vars[8] = MapData.miyama2
			effect._self_vars[16] = MapData.miyama2._players
			effect._self_vars[17] = [0,7]
			effect._self_vars[24] = MapData.shinto2
var helper_calls:int = 0
var helper_marker:bool = false:
	set(value):
		helper_marker = value
		if value:
			helper_calls += 1
			helper_result = ForeachFunc.new().exec({"func_name":"set_property","parameters":[self,"progress_marker",null]}, [true, true], 2)
var progress_marker:bool = false:
	set(value):
		progress_marker = value
		if value:
			var result:Dictionary = GameProgress.reset_progress()
			check(result.get("ok", false), "PRE synchronous progress-only reset succeeds")

func explicit_rejection() -> void:
	var context:SessionContext = new_session()
	var fresh:BaseEffect = make_effect("no-frame", [], context)
	EffectManager.activating_eff = fresh
	# 空体/空列表也不能靠 activating_eff 授权；旧实现返回 null，不抛缺键。
	EffectManager.activating_eff = null
	var result = ForeachFunc.new().exec([], [])
	check(result is Dictionary and not result.get("ok", true) and result.get("reason") == &"unbound_origin", "no-frame direct/default returns explicit rejection")
	EffectManager.activating_eff = fresh
	# 有有效 activating_eff 也不补函数帧。只在已实现显式拒绝时继续，避免旧空游标缺键污染业务RED。
	if result is Dictionary:
		result = ForeachFunc.new().exec([], [0, 1])
		check(result is Dictionary and not result.get("ok", true), "fresh activating_eff cannot authorize no-frame loop")
	EffectManager.activating_eff = null

func synchronous_helper_rejection() -> void:
	var context:SessionContext = new_session()
	var root:BaseEffect = make_effect("native-helper-loop", [{"func_name":"set_property","parameters":[self,"helper_marker",true]}], context)
	var old0:Dictionary = GameData.player_data_library[0]
	EffectManager.activate_effect(root)
	check(helper_calls == 1, "PRE helper loop enters through actual registered native setter")
	check(is_same(old0, GameData.player_data_library[0]), "progress-only reset reuses actual member dictionary")
	check(helper_result is Dictionary and not helper_result.get("ok", true) and helper_result.get("reason") == &"stale_session", "synchronous helper callback returns explicit original-context rejection")
	check(GameData.player_data_library[0].score.number == 0 and GameData.player_data_library[1].score.number == 0, "old helper has no new-domain reward")

func empty_loop_resume() -> void:
	var context:SessionContext = new_session()
	var root:BaseEffect = make_effect("empty-body-budget", [{"func_name":"foreach_func","parameters":[[],[0,1,2]],"var_index":0}], context)
	check(EffectManager.configure_runtime_guard({"enabled":true,"steps":1,"seconds":0.0}), "PRE empty loop guard enabled")
	EffectManager.activate_effect(root)
	check(EffectManager.runtime_guard_status().paused, "empty body still has cooperative checkpoint")
	var resumes:int = 0
	while EffectManager.runtime_guard_status().paused and resumes < 8:
		check(EffectManager.resume_runtime_guard(), "empty body same-domain resume accepted")
		resumes += 1
	check(not EffectManager.runtime_guard_status().paused and GameLog.query({"type":"effect"}).size() == 1, "empty body completes original cursor once")
	check(EffectManager.configure_runtime_guard({"enabled":false,"steps":0,"seconds":0.0}), "PRE empty guard disabled")

func stale_guard_rejection() -> void:
	var context:SessionContext = new_session()
	var body:Dictionary = {"func_name":"edit_score","parameters":[null,BaseNumber.new(2),null]}
	var root:BaseEffect = make_effect("old-paused-foreach", [{"func_name":"foreach_func","parameters":[body,[0,1],2]}], context)
	check(EffectManager.configure_runtime_guard({"enabled":true,"steps":2,"seconds":0.0}), "PRE old-loop guard enabled")
	EffectManager.activate_effect(root)
	check(EffectManager.runtime_guard_status().paused, "PRE actual foreach pauses after first body")
	var before0 = GameData.player_data_library[0].score.number
	var before1 = GameData.player_data_library[1].score.number
	check(before0 == 2 and before1 == 0, "PRE saved loop is after first declared reward")
	var state:Dictionary = EffectManager.execution_runtime_snapshot().suspended_functions[0].loop
	var iteration = state.iteration
	var body_index = state.body_index
	var reset:Dictionary = GameProgress.reset_progress()
	check(reset.get("ok", false), "PRE paused loop progress-only reset accepted")
	check(not EffectManager.resume_runtime_guard(), "stale saved foreach guard refuses resume")
	check(GameData.player_data_library[0].score.number == before0 and GameData.player_data_library[1].score.number == before1, "old saved list never rewards after progress-only reset")
	check(state.iteration == iteration and state.body_index == body_index, "stale saved cursor not advanced")
	# 拒旧恢复不会承诺清除诊断暂停；显式公开重置仅用于用例收尾。
	check(EffectManager.reset_runtime().get("ok", false), "PRE stale guard explicitly cleaned through public reset")
	check(EffectManager.configure_runtime_guard({"enabled":false,"steps":0,"seconds":0.0}), "PRE stale guard disabled")

func dynamic_list() -> void:
	var result:Dictionary = GameData.reset_game_session([0,1,7])
	check(result.get("ok", false), "PRE declared additional member exists")
	for id in [0,1,7]: GameData.player_data_library[id].is_out = false
	GameLog.reset()
	var body:Dictionary = {"func_name":"edit_score","parameters":[null,BaseNumber.new(2),null]}
	var root:BaseEffect = make_effect("dynamic-three-members", [{"func_name":"get_active_players_id","parameters":[],"var_index":0},{"func_name":"foreach_func","parameters":[body,{"self_var":0},2]}], result.context)
	EffectManager.activate_effect(root)
	print("OBS dynamic scores=", [GameData.player_data_library[0].score.number,GameData.player_data_library[1].score.number,GameData.player_data_library[7].score.number], " vars=", root._self_vars, " source=", EffectManager.execution_source_status())
	check(GameData.player_data_library[0].score.number == 2 and GameData.player_data_library[1].score.number == 2 and GameData.player_data_library[7].score.number == 2, "dynamic list includes formally declared additional member")
	check(body.parameters[2] == null, "body parameter template not polluted")

func medusa_original(reset_sync:bool = false, guard_reset:bool = false) -> void:
	var begun:Dictionary = GameData.reset_game_session([0,1,7])
	check(begun.get("ok", false), "PRE Medusa session accepted")
	var context:SessionContext = begun.context
	var setup:BaseEffect = make_effect("medusa-location-setup", [{"func_name":"set_location","parameters":[MapData.miyama2,0,false,true,false]},{"func_name":"set_location","parameters":[MapData.miyama2,7,false,true,false]}], context)
	EffectManager.activate_effect(setup)
	check(GameData.player_data_library[0].location == MapData.miyama2 and GameData.player_data_library[7].location == MapData.miyama2, "PRE two actual members share Medusa origin seat")
	var data:Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/servants/00004_medusa/00004_medusa.json"))
	var desc:Dictionary = data.specials.SKILLS[1].effects[0].options[0].funcs[10].parameters[0][3]
	check(desc.func_name == "foreach_func" and desc.parameters[0][6].func_name == "set_location", "PRE exact formal Medusa inner foreach descriptor")
	if reset_sync:
		make_effect("medusa-reset-on-leave", [{"func_name":"set_property","parameters":[self,"progress_marker",true]}], context, ["self_" + TimePoints.LEAVE_LOCATION])
	var root:BaseEffect = make_effect("formal-medusa-inner-loop", [{"func_name":"set_property","parameters":[self,"medusa_seed",true]},desc], context)
	if guard_reset:
		check(EffectManager.configure_runtime_guard({"enabled":true,"steps":9,"seconds":0.0}), "PRE Medusa guard enabled")
	EffectManager.activate_effect(root)
	if guard_reset:
		check(EffectManager.runtime_guard_status().paused, "PRE real Medusa loop saved after body")
		print("OBS medusa guard member0_at_destination=", GameData.player_data_library[0].location == MapData.shinto2, " member7_at_origin=", GameData.player_data_library[7].location == MapData.miyama2)
		check(GameData.player_data_library[0].location == MapData.shinto2 and GameData.player_data_library[7].location == MapData.miyama2, "PRE Medusa guard is after first relocation before next member")
		var before:BaseLocation = GameData.player_data_library[7].location
		check(GameProgress.reset_progress().get("ok", false), "PRE Medusa paused progress-only reset")
		check(not EffectManager.resume_runtime_guard() and GameData.player_data_library[7].location == before, "formal Medusa stale saved loop cannot relocate next member")
		check(EffectManager.reset_runtime().get("ok", false), "PRE Medusa guard cleanup")
		check(EffectManager.configure_runtime_guard({"enabled":false,"steps":0,"seconds":0.0}), "PRE Medusa guard disabled")
	elif reset_sync:
		check(not SessionGeneration.validate_context(context).ok, "PRE formal Medusa LEAVE really changes generation")
		check(GameData.player_data_library[7].location == MapData.miyama2, "formal Medusa sync reset leaves next original-list member unmoved")
	else:
		check(GameData.player_data_library[0].location == MapData.shinto2 and GameData.player_data_library[7].location == MapData.shinto2, "formal Medusa same-domain original foreach relocates declared members")

func _ready() -> void:
	print("ENV user_dir=", OS.get_user_data_dir(), " pid=", OS.get_process_id())
	var mode:String = str(OS.get_cmdline_user_args()[0]) if not OS.get_cmdline_user_args().is_empty() else "all"
	if mode in ["all", "local"]:
		explicit_rejection()
		synchronous_helper_rejection()
	if mode in ["all", "loop"]:
		synchronous_foreach()
		same_domain_loop_resume()
		empty_loop_resume()
		stale_guard_rejection()
		dynamic_list()
	if mode in ["all", "medusa"]:
		medusa_original()
		medusa_original(true)
		medusa_original(false,true)
	EffectManager.activating_eff = null
	GameData.release_game_objects()
	print("RESULT ", JSON.stringify({"suite":"a1_17_foreach_origin","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
