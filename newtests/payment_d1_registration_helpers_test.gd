extends "res://newtests/payment_d1_registration_test.gd"

func run() -> void:
	print("USER_DIR ", OS.get_user_data_dir())
	setup()
	var effect:BaseEffect = fixture(0, false)
	var old_match:Array = ["before"]
	var old_trigger:Array = ["before_trigger"]
	EffectManager.matched_time_points[effect] = old_match
	EffectManager.resolved_effects[effect] = "before_resolved"
	effect._trigger_time_points = old_trigger
	EffectManager.is_running = true
	Op.new().exec(effect, 0)
	var first_match = EffectManager.matched_time_points[effect]
	Op.new().exec(effect, 0)
	check((Op.registration_attempts()[effect] as Array).size() == 2, "same target attempts do not overwrite")
	check(Op.reject_registration(effect), "inner attempt compensates")
	check(EffectManager.effect_pool.has(effect) and GameDataManager.get_player_data(0).self_effects.has(effect) and is_same(EffectManager.matched_time_points[effect], first_match), "inner reject preserves outer registration/context")
	check(Op.reject_registration(effect), "outer attempt compensates")
	check(!EffectManager.effect_pool.has(effect) and !GameDataManager.get_player_data(0).self_effects.has(effect) and effect._trigger_player_id == -1, "outer reject restores unregistered owner")
	check(is_same(EffectManager.matched_time_points[effect], old_match) and is_same(effect._trigger_time_points, old_trigger) and EffectManager.resolved_effects[effect] == "before_resolved", "outer context identity restored")
	check(Op.registration_attempts().is_empty(), "attempt stack emptied")
	setup()
	effect = fixture(0, false)
	EffectManager.is_running = true
	Op.new().exec(effect, 0)
	EffectManager.resolved_effects[effect] = "nested_write"
	check(!Op.reject_registration(effect), "reject detects nested context write")
	check(EffectManager.resolved_effects[effect] == "nested_write" and EffectManager.effect_pool.has(effect), "conflict not blindly overwritten")
	Op.clear_registration_attempts()
	check(!EffectManager.has_meta(Op.REGISTRATION_ATTEMPTS), "explicit lifecycle clearing removes metadata")
	setup()
	effect = fixture(0, false)
	EffectManager.is_running = true
	Op.new().exec(effect, 0)
	EffectManager.mark_guard_audit_failed(effect)
	check(!Op.reject_registration(effect), "audit pause prevents local compensation")
	check(EffectManager.runtime_guard_status().paused and EffectManager.effect_pool.has(effect), "audit pause and transaction data retained")
	print("RESULT checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
