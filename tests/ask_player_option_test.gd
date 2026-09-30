extends Node
# 执行到一半让玩家选：ask_player_option 这一步之前的步骤先做完，停下等选择；
# 选完做选中那一项，再从下一步接着做。放弃选择也要接着做后面的步骤。
# 选项里与后面的步骤都能读同一张变量表。

var failures:Array[String] = []
var checks:int = 0


func check(ok:bool, label:String) -> void:
	checks += 1
	if !ok: failures.append(label)
	print("CHECK ", label, " ", ok)


func _ready() -> void:
	call_deferred("run")


func setup() -> void:
	EffectManager.reset_runtime()
	GameData.player_data_library.clear()
	var d:Dictionary = GameData.new_player_data()
	d.is_out = false
	GameData.player_data_library[0] = d


func magic() -> int:
	return int((GameDataManager.get_player_data(0).score as BaseNumber).number)


# 战果 +1 → 让玩家选（+10 / +100，选项里把结果记进变量 5）→ 战果 +1000
func start() -> BaseEffect:
	var effect := {"effect_name": "probe_mid_choice", "time_points": ["game_start"], "priority": 0,
		"is_pure_passive": true, "is_residue": false,
		"effect_numbers": [
			{"number": 1, "can_change": true, "is_pure_number": true},
			{"number": 10, "can_change": true, "is_pure_number": true},
			{"number": 100, "can_change": true, "is_pure_number": true},
			{"number": 1000, "can_change": true, "is_pure_number": true}],
		"funcs": [
			{"func_name": "edit_score", "parameters": [null, {"number_index": 0}], "var_index": -1},
			{"func_name": "ask_player_option", "parameters": [[
				{"shown_option_name": "加十", "funcs": [{"func_name": "store_value", "parameters": ["ten"], "var_index": 5}, {"func_name": "edit_score", "parameters": [null, {"number_index": 1}]}]},
				{"shown_option_name": "加百", "funcs": [{"func_name": "store_value", "parameters": ["hundred"], "var_index": 5}, {"func_name": "edit_score", "parameters": [null, {"number_index": 2}]}]}
			], "选一项"], "var_index": -1},
			{"func_name": "store_value", "parameters": [{"self_var": 5}], "var_index": 6},
			{"func_name": "edit_score", "parameters": [null, {"number_index": 3}]}]}
	var host := BaseAttack.new("probe_host", "", [])
	host._effects = LoadHelper.load_effects([effect], host)
	EffectManager.register_effects(host._effects, 0)
	EffectManager.add_to_activation_pool(host._effects[0])
	EffectManager.run_pipeline()
	return host._effects[0]


func run() -> void:
	setup()
	var base := magic()
	var parent := start()
	var pending := EffectManager.get_pending_active_effect()
	check(magic() == base + 1, "steps before the choice already ran " + str(magic() - base))
	check(pending != null and pending.has_options() and pending._options.size() == 2, "effect paused on a choice")
	check(pending != null and pending._shown_name == "选一项", "choice carries its shown name")
	EffectManager.submit_option_choice(pending, [1])
	check(magic() == base + 1 + 100 + 1000, "picked option ran, then the rest " + str(magic() - base))
	check(parent._self_vars.size() > 6 and str(parent._self_vars[6]) == "hundred", "later steps read vars set inside the option " + str(parent._self_vars))
	check(not EffectManager.is_waiting_for_choice(), "nothing left waiting")
	check(not EffectManager.effect_pool.has(pending), "choice removed after it resolved")

	setup()
	base = magic()
	start()
	pending = EffectManager.get_pending_active_effect()
	EffectManager.submit_active_choice(pending, false)
	check(magic() == base + 1 + 1000, "declining still runs the remaining steps " + str(magic() - base))
	check(not EffectManager.is_waiting_for_choice(), "nothing waiting after decline")
	check(EffectManager._paused_runs.is_empty(), "no paused run left behind")

	print("RESULT checks=%d failures=%d" % [checks, failures.size()])
	for f in failures:
		print("FAIL ", f)
	get_tree().quit(1 if failures.size() > 0 else 0)
