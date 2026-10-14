extends "res://tests/rule_guard_continuation_test.gd"

const OBSERVER = preload("res://newtests/c0-observer_trace.gd")
var observer_source:SessionContext
var observer_body:Array = []
var observer_points:Array = []
var observer_after:int = 0

func fresh_observation(ids:Array, config:Dictionary) -> void:
	GameStart.end_session()
	var prepared:Dictionary = GameData.reset_game_session(ids)
	check(prepared.ok, "观察夹具由真实生命周期创建来源")
	observer_source = prepared.context
	GameLog.reset()
	MapData.areas.clear()
	LoadSituation.climax_situations = {}
	for id in ids: GameData.player_data_library[id].is_out = false
	samples.clear()
	outside = 0
	check(EffectManager.configure_runtime_guard(config), "观察夹具保留原预算配置")
	observer_after = OBSERVER.cutoff()
	print("USER_DIR ", OS.get_user_data_dir())

func observation_declaration(funcs:Array, points:Array, name:String = "native-tail-test") -> Dictionary:
	return {"effect_name":name,"time_points":points,"priority":0,"is_pure_passive":true,"need_activate":false,"is_residue":false,"effect_numbers":[],"funcs":funcs}

func sampling_declaration(body:Array, points:Array) -> Dictionary:
	observer_body = body
	observer_points = points
	return observation_declaration([{"func_name":"while_func","parameters":[body,true,3],"var_index":0}],points)

func event_data(name:String, effects:Array = []) -> Dictionary:
	return {"card_name":name,"card_img":"","score":{"number":0,"can_change":true,"is_pure_number":true},"effects":effects}

func situation_data(name:String, magic:int, effects:Array = []) -> Dictionary:
	return {"card_name":name,"card_img":"","magic":{"number":magic,"can_change":true,"is_pure_number":true},"effects":effects}

func finish_observation(state:Dictionary) -> void:
	var attempts:int = 0
	# 原 complete 的 20 次上限不变；真实 process_frame 让 resolver 的 await 尾部推进。
	while attempts < 20 and (EffectManager.runtime_guard_status().paused or not state.get("completed", false)):
		if EffectManager.runtime_guard_status().paused:
			EffectManager.resume_runtime_guard()
		await get_tree().process_frame
		attempts += 1
	check(not EffectManager.runtime_guard_status().paused, "有限诊断循环完成")
	check(state.get("ok",false) and state.get("completed",false), "原动作成功且异步尾部真实完成")
	var observed:Dictionary = OBSERVER.samples(observer_after,observer_body,observer_points)
	check(observed.issues.is_empty() and observed.paths == [0,1,2], "三轮终端查询来源与路径完整")
	samples = observed.values
	print("OBSERVER_TRACE ", JSON.stringify({"samples":observed,"calls":GameLog.all_func_calls()}))
