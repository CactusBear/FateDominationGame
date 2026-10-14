extends Node
# 回归：效果上一次等待留下的前态过期后（如持有者已移动），重新进入决策队列不能让 run_pipeline 空转卡死。
var checks:int = 0
var failures:Array = []

func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)

func _ready() -> void:
	var started:Dictionary = GameData.reset_game_session([0, 1])
	check(started.ok, "PRE reset session")
	GameLog.reset()
	for id in [0, 1]: GameData.player_data_library[id].location = MapData.magic_workshop0
	var desc:Dictionary = {"effect_name":"drain-stale-probe","priority":0,"time_points":[],"is_pure_passive":false,"is_residue":false,"effect_numbers":[],"funcs":[]}
	var loaded:Array = LoadHelper.load_effects([desc], null, started.context)
	check(loaded.size() == 1 and EffectManager.register_effect(loaded[0], 0), "PRE factory and register")
	var effect:BaseEffect = loaded[0]
	EffectManager.decision_queue.append(effect)
	EffectManager.run_pipeline()
	check(EffectManager.get_pending_active_effect() == effect, "first entry waits for answer")
	check(EffectManager.submit_active_choice(effect, false), "declining the first wait succeeds")
	# 持有者离开原位置：上次等待保存的前态从此不再成立
	GameData.player_data_library[0].location = null
	EffectManager.resolved_effects.erase(effect)
	EffectManager.decision_queue.append(effect)
	var began:int = Time.get_ticks_msec()
	EffectManager.run_pipeline()
	check(Time.get_ticks_msec() - began < 5000, "re-entry returns instead of spinning")
	check(EffectManager.get_pending_active_effect() == effect, "re-entry waits again with a fresh origin")
	print("RESULT checks=%d failures=%s" % [checks, JSON.stringify(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
