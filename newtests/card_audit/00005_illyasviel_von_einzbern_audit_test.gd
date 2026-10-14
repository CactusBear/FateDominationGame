extends "res://tests/masters_audit_fix_test.gd"

func fresh(start:bool = true):
	var m = setup("illyasviel_von_einzbern")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE], ctx)
	check(MasterManager.bind_master_effects(0, ctx), "夹具正式御主效果绑定")
	print("OBS 御主登记 来源=", RegisterObjectEffects.source_is_current(ctx, m), " 池=", EffectManager.effect_pool.size())
	if start: TimePointChecker.global_time_point([TimePoints.GAME_START], null, ctx)
	return m

func awaken(m):
	var session = DebugSession.new(null, ctx)
	var result = session.execute_action("skill.awaken", {"player":0, "card_id":m._upgrade_skill[0].get_instance_id()})
	session.shutdown()
	print("OBS 觉醒回执=", result, " 效果池=", EffectManager.effect_pool.size())
	return result.get("ok", false)

func round_start(n:int):
	GameProgress.current_round = n
	GameLog.set_context(n, "prepare")
	TimePointChecker.global_time_point([TimePoints.DAY_START], null, ctx)

func play(keys:Array, flags:Array, id:int = 0) -> Array:
	var cards:Array = []
	keys = keys.duplicate(); flags = flags.duplicate()
	# 常规出牌至少两张；补一张真实暗置迅捷牌，不改变被审计攻击的威力/费用。
	if keys.size() == 1:
		keys.append("agility:2"); flags.append(true)
	if not flags.has(false): SetLocation.new().exec(MapData.magic_workshop._locations[id], id, false, true, true, ctx)
	GameProgress.current_player_id = id
	for key in keys:
		var c = attack(key)
		cards.append(c)
		GameData.player_data_library[id].hand_cards.append(c)
	check(RegularPlay.submit_group(id, cards, flags, false, ctx), "夹具常规出牌" + str(keys) + str(flags) + str(id))
	return cards

func end_round():
	TimePointChecker.global_time_point([TimePoints.DAY_END], null, ctx)

func run():
	var m = fresh()
	var d = GameData.player_data_library[0]
	check(d.magic.number == 6, "人工生命体_开局魔力精确为6")
	check(GameData.player_data_library[1].magic.number == 12, "人工生命体_不改变其他玩家魔力")
	d.magic.number = 3
	round_start(2)
	check(d.magic.number == 3, "人工生命体_非开局不重置魔力")
	var robe = named(d.buffs, "heavenly_robe")
	check(robe != null and not robe._is_active, "圣杯容器_开局天之衣未激活")
	if robe != null:
		round_start(7)
		check(not robe._is_active, "圣杯容器_第七回合不激活")
		round_start(8)
		check(robe._is_active, "圣杯容器_第八回合开始激活")
		round_start(9)
		check(robe._is_active, "圣杯容器_第九回合仍然激活")
	else:
		print("未测 圣杯容器第7/8/9回合：正式开局未能安装天之衣")

	fresh(); d = GameData.player_data_library[0]
	var before = d.magic.number
	var cards = play(["strength:5"], [false])
	check(d.magic.number == before - max(0, cards[0]._cost.number - 1), "小圣杯降费_明置攻击精确少付1")
	check(GameData.player_data_library[1].attack_cost_discount.number == 0, "小圣杯降费_其他玩家无折扣")
	fresh(); d = GameData.player_data_library[0]; d.magic.number = 0
	cards = [attack("strength:9"), attack("agility:2")]; d.hand_cards.append_array(cards)
	check(not RegularPlay.submit_group(0, cards, [false, true], false, ctx) and d.magic.number == 0 and d.hand_cards.has(cards[0]), "小圣杯降费_仍不足费用拒绝且不透支")
	fresh(); d = GameData.player_data_library[0]; d.magic.number = 0
	cards = play(["strength:5"], [false])
	check(d.magic.number == 0, "小圣杯降费_一费攻击降至0不倒送魔力")

	fresh(); d = GameData.player_data_library[0]
	play(["strength:2", "agility:2"], [true, true])
	before = d.magic.number; end_round()
	check(d.magic.number == before + 1, "小圣杯回魔_自己的攻击全暗置获得1")
	fresh(); d = GameData.player_data_library[0]
	play(["strength:2", "agility:2"], [true, false])
	before = d.magic.number; end_round()
	check(d.magic.number == before, "小圣杯回魔_混有明置攻击不获得魔力")
	fresh(); d = GameData.player_data_library[0]
	play(["strength:2"], [true]); play(["agility:2"], [false], 1)
	before = d.magic.number; end_round()
	check(d.magic.number == before + 1, "小圣杯回魔_对手明置不影响自己全暗置")
	fresh(); d = GameData.player_data_library[0]
	cards = play(["strength:2"], [false])
	SetCardConcealed.new().exec(cards[0], true, 0, ctx)
	before = d.magic.number; end_round()
	print("OBS 明置打出后改暗_回魔=", d.magic.number - before)
	check(d.magic.number == before, "小圣杯回魔_曾明置打出随后暗置仍不满足全暗置")

	m = fresh(); d = GameData.player_data_library[0]
	var str_hand = attack("strength:2"); var str_deck = attack("strength:3"); var str_discard = attack("strength:4")
	var keep = attack("magic:2")
	d.hand_cards.append_array([str_hand, keep]); d.deck.append(str_deck); d.discard.append(str_discard)
	check(not m._upgrade_skill[0]._is_awakened and d.hand_cards.has(str_hand), "第三法移除_正常开局未觉醒不移除")
	check(awaken(m), "第三法移除_真实调试觉醒成功")
	check(not d.hand_cards.has(str_hand) and not d.deck.has(str_deck) and not d.discard.has(str_discard) and d.out_of_game.attacks.has(str_hand) and d.out_of_game.attacks.has(str_deck) and d.out_of_game.attacks.has(str_discard), "第三法移除_手牌牌库弃牌三处力量牌全部移出游戏")
	check(d.hand_cards.has(keep), "第三法移除_非力量牌保留")
	check(not awaken(m), "第三法移除_拒绝重复解锁")
	m = fresh(); d = GameData.player_data_library[0]; awaken(m)
	cards = play(["magic:2"], [false])
	print("OBS 第三法单魔术_总威力=", d.power.number, " 卡威力=", cards[0]._power.number)
	check(d.power.number == 4, "第三法威力_单张魔术2威力增加到4")
	m = fresh(); d = GameData.player_data_library[0]; awaken(m)
	cards = play(["magic:2", "special:luck"], [false, false])
	print("OBS 第三法双牌_总威力=", d.power.number)
	check(d.power.number == 10, "第三法威力_同批魔术特殊各加2总计10不重复")
	m = fresh(); d = GameData.player_data_library[0]; awaken(m)
	play(["agility:2"], [false])
	check(d.power.number == 2, "第三法威力_非魔术非特殊不增加")
	m = fresh(); d = GameData.player_data_library[0]; awaken(m)
	play(["magic:2", "agility:2"], [false, false])
	print("OBS 第三法魔术与迅捷_总威力=", d.power.number)
	check(d.power.number == 6, "第三法威力_同批无关属性不重复加成旧魔术")
	m = fresh(); d = GameData.player_data_library[0]
	play(["magic:2"], [false])
	check(d.power.number == 2, "第三法威力_未觉醒不增加")

	m = fresh(); awaken(m)
	TimePointChecker.global_time_point([TimePoints.SITUATION_ACTIVATED], null, ctx)
	check(not GameProgress.is_game_over, "第三法天之杯_没有天之杯不结束对局")
	var situation = FixtureClone.clone_template(named(LoadSituation.climax_situations.values(), "heavens_feel"), ctx)
	check(situation != null, "第三法天之杯_正式局势模板存在")
	GameData.player_data_library[2].is_out = true
	MapData.situations.append(situation)
	TimePointChecker.global_time_point([TimePoints.SITUATION_ACTIVATED], situation, ctx)
	check(GameProgress.is_game_over and GameData.player_data_library[0].is_victory and GameData.player_data_library[1].is_victory and not GameData.player_data_library[2].is_victory, "第三法天之杯_未淘汰者全部获胜淘汰者不获胜")
	m = fresh(); MapData.situations.append(FixtureClone.clone_template(named(LoadSituation.climax_situations.values(), "heavens_feel"), ctx))
	TimePointChecker.global_time_point([TimePoints.SITUATION_ACTIVATED], null, ctx)
	check(not GameProgress.is_game_over, "第三法天之杯_技能未解锁即使天之杯出现也不获胜")
	check(awaken(m) and GameProgress.is_game_over, "第三法天之杯_天之杯已在场解锁立即获胜")

	for out_same_area in [false, true]:
		m = fresh(); d = GameData.player_data_library[0]; round_start(8)
		GameProgress.current_phase_index = 3; GameLog.set_context(8, "battle")
		var result = BattleResolver.new(ctx).exec()
		if out_same_area: check(ClimaxResolver.new().eliminate_player(1, ctx), "归于虚无_同场战斗后真实淘汰目标")
		var history = GameLog.query({"type":"battle", "actor":0}, 0)
		print("OBS 天之衣_同场淘汰=", out_same_area, " 战斗日志=", history, " 战报=", result.get("winners_by_area"))
		before = d.score.number; round_start(9)
		print("OBS 天之衣_次回合战果增量=", d.score.number - before)
		check(d.score.number == before + (2 if out_same_area else 0), "归于虚无_同场" + ("有淘汰玩家下回合获得2" if out_same_area else "无淘汰玩家下回合不获得"))
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
