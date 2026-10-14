extends "res://tests/masters_audit_fix_test.gd"

func fresh(with_servant:bool = true):
	var m = setup("kotomine_kirei")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE], ctx)
	if with_servant: SetPlayerData.new().exec("servant", FixtureClone.clone_template(GameData.loaded_servants[0], ctx), 0, ctx)
	SetPlayerData.new().exec("servant", FixtureClone.clone_template(GameData.loaded_servants[1], ctx), 1, ctx)
	check(MasterManager.bind_master_effects(0, ctx), "夹具正式御主绑定")
	TimePointChecker.global_time_point([TimePoints.GAME_START], null, ctx)
	print("OBS 身份附带物数量=", GameData.player_data_library[0].buffs.size(), " 监督者来源=", SessionGeneration.origin_of(named(m._specials.BUFFS, "overseer")))
	return m

func identity(key:String) -> bool:
	var b = named(GameData.player_data_library[0].buffs, key)
	return b != null and b._is_active

func phase(index:int):
	GameProgress.current_phase_index = index
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE if index == 2 else TimePoints.BATTLE_PHASE], ctx)

func neutral(m):
	var e = named(named(m._specials.BUFFS, "overseer")._effects, "overseer_neutral_move")
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE], 0, null, ctx)
	return EffectManager.waiting_effect == e and EffectManager.submit_option_choice(e, [0])

func awake(m) -> bool:
	var session = DebugSession.new(null, ctx)
	var result = session.execute_action("skill.awaken", {"player":0, "card_id":m._upgrade_skill[0].get_instance_id()})
	session.shutdown()
	print("OBS 觉醒回执=", result, " 效果池=", EffectManager.effect_pool.size())
	return result.get("ok", false)

func run():
	var m = fresh()
	var d = GameData.player_data_library[0]
	check(identity("overseer") and not identity("executor"), "两幅面孔_从者真名隐藏时仅监督者激活")
	check(ReleaseTrueName.new().exec(0, ReleaseTrueName.DEFAULT_SHOWN_AREAS, ctx), "夹具真实真名解放")
	check(identity("executor") and not identity("overseer"), "两幅面孔_真名解放切换为执行者")
	check(HideTrueName.new().exec(0, HideTrueName.DEFAULT_HIDDEN_AREAS, ctx), "夹具真实重新隐藏真名")
	check(identity("overseer") and not identity("executor"), "两幅面孔_重新隐藏真名回监督者")
	m = fresh(false)
	check(identity("executor") and not identity("overseer"), "两幅面孔_没有从者时仅执行者激活")

	m = fresh()
	check(GameDataManager.can_see_servant_class(0, 1), "管理者_监督者可私下看到其他从者职阶")
	check(not GameDataManager.can_see_servant_class(2, 1), "管理者_不向第三方泄露职阶")
	ReleaseTrueName.new().exec(0, ReleaseTrueName.DEFAULT_SHOWN_AREAS, ctx)
	SetPlayerData.new().exec("servant", FixtureClone.clone_template(GameData.loaded_servants[2], ctx), 1, ctx)
	TimePointChecker.global_time_point([TimePoints.DAY_START], null, ctx)
	check(not GameDataManager.can_see_servant_class(0, 1), "管理者_执行者身份不获得新从者职阶")
	HideTrueName.new().exec(0, HideTrueName.DEFAULT_HIDDEN_AREAS, ctx)
	check(GameDataManager.can_see_servant_class(0, 1), "管理者_重新成为监督者知晓新从者职阶")

	m = fresh(); d = GameData.player_data_library[0]
	var before = d.magic.number
	check(neutral(m), "中立_交战中可发动真实阶段移动")
	print("OBS 中立移动位置=", d.location.get_from()._area_name, " 魔力=", d.magic.number)
	check(d.location == MapData.scout._locations[0] and d.magic.number == before - 2, "中立_忽视交战移至侦察精确支付2")
	m = fresh(); d = GameData.player_data_library[0]; d.magic.number = 1
	var origin = d.location
	check(not neutral(m) and d.location == origin and d.magic.number == 1, "中立_魔力不足不移动不扣款")
	m = fresh(); d = GameData.player_data_library[0]
	SetLocation.new().exec(MapData.scout._locations[0], 2, false, true, true, ctx)
	origin = d.location; before = d.magic.number
	neutral(m)
	check(d.location == origin and d.magic.number == before, "中立_侦察被占用不移动不扣款")
	m = fresh(); d = GameData.player_data_library[0]
	ReleaseTrueName.new().exec(0, ReleaseTrueName.DEFAULT_SHOWN_AREAS, ctx)
	origin = d.location; before = d.magic.number
	check(not neutral(m) and d.location == origin and d.magic.number == before, "中立_执行者身份不能使用监督者移动")

	m = fresh(); d = GameData.player_data_library[0]
	phase(3); TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], 0, null, ctx)
	check(d.total_power_bonus.number == 0, "执行者总威力_监督者战斗阶段不增加")
	m = fresh(false); d = GameData.player_data_library[0]
	phase(3); TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], 0, null, ctx)
	var boost = named(named(m._specials.BUFFS, "executor")._effects, "executor_total_power_boost")
	# 阶段能力是主动能力：派发时点不自动询问，由玩家经正式入口发动（与复仇者同一口径）。
	var offered:bool = EffectManager.waiting_effect != boost and active(boost)
	print("OBS 执行者战斗总加成=", d.total_power_bonus.number, " 主动阶段询问=", offered)
	check(offered and d.total_power_bonus.number == 2, "执行者总威力_执行者战斗阶段增加2")
	m = fresh(false); d = GameData.player_data_library[0]
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE], 0, null, ctx)
	check(d.total_power_bonus.number == 0, "执行者总威力_行动阶段不增加")

	m = fresh(); d = GameData.player_data_library[0]
	var e = named(m._upgrade_skill[0]._effects, "placeholder_evil_protector_true_name_defeat")
	phase(3)
	check(not EffectManager.request_manual_activation(e, 0), "恶的庇护者败北_未解锁不允许发动")
	check(awake(m), "恶的庇护者_真实调试觉醒")
	var started = active(e)
	check(started, "恶的庇护者败北_监督者战斗阶段可以选择目标")
	if started:
		# 非法目标提交即视为放弃本次（与选牌非法提交同一口径）；合法目标须重新发起一次。
		check(not EffectManager.submit_player_selection(e, [2]), "恶的庇护者败北_不能选择不同战场玩家")
		check(not ReleaseTrueName.is_released(0) and DefeatBuff.get_defeat_count(2) == 0, "恶的庇护者败北_非法目标不结算不解放")
		check(active(e) and EffectManager.submit_player_selection(e, [1]), "恶的庇护者败北_同战场目标提交成功")
	check(ReleaseTrueName.is_released(0) and DefeatBuff.get_defeat_count(1) == 1, "恶的庇护者败北_自己真名解放同场目标败北一次")
	check(not active(e), "恶的庇护者败北_真名解放成为执行者后不能重复使用")
	m = fresh(false); awake(m); phase(3)
	e = named(m._upgrade_skill[0]._effects, "placeholder_evil_protector_true_name_defeat")
	check(not active(e), "恶的庇护者败北_执行者不得发动监督者能力")

	m = fresh(false); d = GameData.player_data_library[0]; awake(m)
	var a = attack("strength:2"); var b = attack("magic:2")
	d.hand_cards.append_array([a,b])
	check(RegularPlay.submit_group(0, [a,b], [false,false], false, ctx), "恶的庇护者威力_真实同批基本攻击出牌")
	print("OBS 恶的庇护者基本攻击总威力=", d.power.number)
	check(d.power.number == 8, "恶的庇护者威力_执行者两张基本2威力各加2总计8")
	Defeat.new().exec(0, ctx)
	print("OBS 恶的庇护者执行者败北数=", DefeatBuff.get_defeat_count(0))
	check(DefeatBuff.get_defeat_count(0) == 0, "恶的庇护者无视败北_执行者免疫败北")
	m = fresh(); d = GameData.player_data_library[0]; awake(m)
	a = attack("strength:2"); b = attack("magic:2"); d.hand_cards.append_array([a,b])
	check(RegularPlay.submit_group(0, [a,b], [false,false], false, ctx) and d.power.number == 4, "恶的庇护者威力_监督者两张基本攻击不增加")
	Defeat.new().exec(0, ctx)
	check(DefeatBuff.get_defeat_count(0) == 1, "恶的庇护者无视败北_监督者不免疫败北")
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
