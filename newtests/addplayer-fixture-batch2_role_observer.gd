extends "res://newtests/role_factory_origin_test.gd"

# 原 73 条 CHECK 逐字运行，只加公开观察，八条红交主代理裁定。
func check(ok:bool, label:String) -> void:
	super.check(ok,label)
	if not (label.ends_with("manager returns real registration false") or label.ends_with("GameStart consumes registration refusal") or label.ends_with("startup refusal keeps domain closed") or label.ends_with("startup refusal has no first dispatch")):
		return
	var kind:String = "master" if label.begins_with("master ") else "servant"
	var runtime = GameDataManager.find_player_data(0).get(kind)
	var original = seen.get("effect")
	var current = runtime._effects[0] if runtime != null and not runtime._effects.is_empty() else null
	var observation:Dictionary = {"label":label, "original_check":ok,
		"runtime_role_distinct":runtime != null and not is_same(runtime,failure_role),
		"runtime_effect_distinct":current != null and not is_same(current,original),
		"original_registered_to_1":original != null and EffectManager.can_register_effect(original,1),
		"original_can_register_to_0":original != null and EffectManager.can_register_effect(original,0),
		"clone_registered_to_0":current != null and EffectManager.can_register_effect(current,0),
		"clone_source_current":current != null and current.runtime_source_status().ok,
		"same_token":original != null and current != null and is_same(original.runtime_context().token(),current.runtime_context().token()),
		"callback_bound":seen.get("bound",false), "callback_registered":seen.get("registered",false),
		"round":GameProgress.current_round, "domain_open":SessionGeneration.current_token().ok,
		"game_start_facts":GameLog.query({"type":"time_point", "tags":[TimePoints.GAME_START]},null).size()}
	print("ORACLE_OBSERVATION ",JSON.stringify(observation))
