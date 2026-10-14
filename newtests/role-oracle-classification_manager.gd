extends "res://newtests/role_factory_origin_test.gd"

func run() -> void:
	# 正例调用原夹具，不复制来源实现或放宽原判据。
	manager_cases("master", MasterManager, "bind_master_effects")
	manager_cases("servant", ServantManager, "bind_servant_effects")
	for kind in ["master", "servant"]:
		var source:SessionContext = reset_fixture()
		failure_role = fixture_role(kind)
		seen.clear()
		prepare_registration_failure()
		var template:BaseObject = prepare_manager_conflict(kind, source)
		var manager:Node = MasterManager if kind == "master" else ServantManager
		var method:String = "bind_master_effects" if kind == "master" else "bind_servant_effects"
		var prepared:Dictionary = MasterManager.prepare_role_runtime(failure_role, source)
		check(prepared.ok and is_same(prepared.object, failure_role), kind + " manager consumes exact conflicting runtime identity")
		check(seen.bound and seen.registered and EffectManager.can_register_effect(seen.effect, 1) and not EffectManager.can_register_effect(seen.effect, 0), kind + " conflict owner gate is real and current")
		var pool:Array = EffectManager.effect_pool.duplicate()
		var owned:Array = GameDataManager.find_player_data(0).self_effects.duplicate()
		var facts:Array = GameLog.query({"type":"time_point", "tags":[TimePoints.GAME_START]}, null)
		var round_before:int = GameProgress.current_round
		check(rejected(bind(manager, method, 0, source)), kind + " manager returns real registration false")
		check(is_same(GameDataManager.find_player_data(0)[kind], failure_role) and EffectManager.effect_pool == pool and GameDataManager.find_player_data(0).self_effects == owned, kind + " refusal preserves runtime and registration collections")
		check(EffectManager.can_register_effect(seen.effect, 1) and not EffectManager.can_register_effect(seen.effect, 0), kind + " refusal leaves conflicting ownership unchanged")
		check(not GameStart._started and GameProgress.current_round == round_before and GameLog.query({"type":"time_point", "tags":[TimePoints.GAME_START]}, null) == facts and SessionGeneration.validate_context(source).ok, kind + " manager refusal has no startup tail or source renewal")
		# 同一合法模板的新 identity 不继承旧对象的登记主体，但必须继承原来源。
		var legal:Dictionary = MasterManager.prepare_role_runtime(template, source)
		check(legal.ok and not is_same(legal.object, failure_role) and not is_same(legal.object._effects[0], seen.effect), kind + " legal template makes independent runtime identity")
		GameDataManager.find_player_data(0)[kind] = legal.object
		check(accepted(bind(manager, method, 0, source)), kind + " legal independent clone registration stays green")
		check(is_same(GameDataManager.find_player_data(0)[kind], legal.object) and EffectManager.effect_pool.has(legal.object._effects[0]) and is_same(legal.object._effects[0].runtime_context().token(), source.token()), kind + " positive registered clone retains original provenance")
		failure_role = null
		seen.clear()
	GameStart.end_session()
	GameData.release_game_objects()
	print("RESULT ", JSON.stringify({"suite":"role-oracle-classification_manager", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
