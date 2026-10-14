extends "res://newtests/payment_d1_registration_test.gd"

func run() -> void:
	print("USER_DIR ", OS.get_user_data_dir())
	#真实延迟付款路径；此套是未接线边界守卫，不用手动调用补偿冒充接线通过。
	for mode in range(3):
		setup()
		var effect:BaseEffect = fixture(mode, false)
		var pool:Array = EffectManager.effect_pool.duplicate()
		var own0:Array = GameDataManager.get_player_data(0).self_effects.duplicate()
		var owner:int = effect._trigger_player_id
		var target = Op.new().exec(effect, 0)
		check(target != null and EffectManager.waiting_effect == target, "delayed real wait %s" % mode)
		GameDataManager.get_player_data(0).command_spell_count.number = 0
		check(!EffectManager.submit_active_choice(target, true), "delayed actual payment rejects %s" % mode)
		check(EffectManager.effect_pool == pool, "delayed no added pool member %s" % mode)
		check(GameDataManager.get_player_data(0).self_effects == own0, "delayed no added self member %s" % mode)
		check(effect._trigger_player_id == owner, "delayed original owner restored %s" % mode)
		check(Op.registration_attempts().is_empty(), "delayed rejected attempt released %s" % mode)
		check(bodies == 0, "delayed body not run %s" % mode)
	setup()
	var effect:BaseEffect = fixture(0, false)
	var target = Op.new().exec(effect, 0)
	check(EffectManager.submit_active_choice(target, true), "delayed success actually paid")
	check(Op.registration_attempts().is_empty(), "delayed successful attempt released")
	EffectManager.reset_runtime()
	check(Op.registration_attempts().is_empty(), "reset releases manager registration records")
	print("RESULT checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
