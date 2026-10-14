extends "res://newtests/a1_06_regular_origin_test.gd"

# 只验证 A 档准入；原恢复契约保留的图外审计/确认令牌不能由 AI 擅自撤销。
func run() -> void:
	var source:SessionContext = setup()
	if source == null:
		finish()
		return
	preload("res://scripts/match/rule_random.gd").start_seed(610612)
	TimePointChecker.set_phase_time_points([TimePoints.ACTION_PHASE], source)
	var effects:Array = LoadHelper.load_effects([{
		"effect_name":"ai-checkpoint-power", "priority":0,
		"time_points":[TimePoints.SELF_PREFIX + TimePoints.ACTION_PHASE],
		"is_pure_passive":false, "is_residue":false, "is_manual":true,
		"need_activate":false, "effect_numbers":[],
		"funcs":[{"func_name":"edit_power", "parameters":[null, BaseNumber.new(5), 0]}]
	}], null, source)
	check("runtime effect created with original source", effects.size() == 1)
	if effects.is_empty():
		finish()
		return
	var effect:BaseEffect = effects[0]
	held.append(effect)
	check("runtime effect registered", EffectManager.register_effect(effect, 0))
	var before:Dictionary = snapshot()
	var audit_before:Dictionary = MatchJournal.audit_boundary()
	var batch_before:int = GameProgress.battle_broadcast_batch_id()
	var checkpoint = Effects.new(null, true, source)
	check("existing full checkpoint available", checkpoint.ready)
	if not checkpoint.ready:
		print("AI_A_TIER_UNAVAILABLE ", checkpoint.error)
		finish()
		return
	check("real manual effect activation accepted", EffectManager.request_manual_activation(effect, 0))
	check("real effect trial executed", EffectManager.submit_active_choice(effect, true))
	check("real trial changes total power", GetPlayerTotalPower.breakdown(0).total == 5)
	check("existing full checkpoint restores", checkpoint.restore())
	var after:Dictionary = snapshot()
	var unchanged:Dictionary = {}
	for field in before:
		unchanged[field] = before[field] == after[field]
		check("rollback rule field unchanged " + str(field), unchanged[field])
	var audit_after:Dictionary = MatchJournal.audit_boundary()
	var batch_after:int = GameProgress.battle_broadcast_batch_id()
	check("A tier cannot promise unchanged graph-external state", audit_after != audit_before or batch_after != batch_before)
	print("AI_A_TIER_EVIDENCE ", JSON.stringify({
		"rule_fields_unchanged":unchanged,
		"audit_before":audit_before, "audit_after":audit_after,
		"batch_before":batch_before, "batch_after":batch_after,
		"tier":"B", "reason":"audit_identity_is_not_rollback_state"
	}))
	finish()

func finish() -> void:
	print("RESULT ", JSON.stringify({"suite":"ai_checkpoint_feasibility", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
