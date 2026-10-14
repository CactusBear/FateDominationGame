extends "res://newtests/card_audit/00003_matou_shinji_audit_test.gd"

func sakura_fixture(isolated:bool = true):
	setup()
	var m = master("matou_sakura")
	servant("medusa")
	servant("sasaki_kojirou", 1)
	servant("emiya", 2)
	start()
	if isolated:
		print("DIAG 隔离夹具预置本局角色已创建的未激活黑泥与圣杯；不视为开局获得路径通过。")
		seed_buff("corrupted_grail")
		seed_buff("black_mud")
	return m

func prepare():
	GameProgress.current_phase_index = 0
	GameProgress.current_player_id = 0
	GameLog.set_context(GameProgress.current_round, "prepare")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.PREPARE_PHASE], ctx)
	TimePointChecker.dynamic_time_point([TimePoints.PREPARE_PHASE], 0, null, ctx)

func mud_use(e):
	var offered = EffectManager.waiting_effect == e or EffectManager.request_manual_activation(e, 0)
	check(offered, "黑泥准备阶段真实发动询问存在")
	if offered:
		check(EffectManager.submit_active_choice(e, true), "黑泥正式确认入口支付并执行")

func activate_grail():
	var m = sakura_fixture()
	GameData.player_data_library[0].magic.number = 0
	day_end(8)
	return m

func attacks(n:int) -> Array:
	var cards:Array = []
	for i in range(n):
		var c = make_hand_card("strength:5")
		check(c != null and c._cost.number == 1, "圣杯夹具使用真实一魔力费用的基础攻击")
		GameData.player_data_library[0].hand_cards.append(c)
		cards.append(c)
	return cards

func battle_place():
	var area = GetMapAreaByName.new().exec("深山町")
	SetLocation.new().exec(area._locations[0], 0, false, true, true, ctx)
	GameProgress.current_phase_index = 2
	GameLog.set_context(GameProgress.current_round, "action")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE], ctx)

func corrosion_fixture(grail_active:bool = true):
	var m = activate_grail() if grail_active else sakura_fixture()
	GameProgress.current_round = 4
	GameLog.set_context(4, "action")
	var skill = m._upgrade_skill[0]
	check(AwakenSkill.new().exec(skill, 0, ctx), "腐蚀第四回合真实解锁入口接受")
	# 分层诊断：显式登记原来源并派发真实觉醒时点，不把它算作调试入口已贯通。
	RegisterObjectEffects.new().exec(skill, 0, ctx)
	TimePointChecker.dynamic_time_point([TimePoints.SKILL_AWAKENED], 0, skill, ctx)
	check(buff("corrosion") != null, "腐蚀原来源显式觉醒派发绑定附带能力")
	if buff("corrosion") == null:
		print("DIAG 觉醒绑定失败；仅隔离腐蚀能力效果体，预置本局已觉醒角色创建的buff。")
		seed_buff("corrosion")
	return buff("corrosion")

func stolen_skill(id:int, key:String = "ichi_no_tachi"):
	var tpl = named(named(GameData.loaded_servants, "sasaki_kojirou")._specials.SKILLS, key)
	var card = FixtureClone.clone_template(tpl, ctx)
	GameData.player_data_library[id].servant_skills.append(card)
	RegisterObjectEffects.new().exec(card, id, ctx)
	return card

func run():
	var m = sakura_fixture(false)
	check(buff("corrupted_grail") != null and not buff("corrupted_grail")._is_active, "此世全部之恶开局圣杯存在但未激活")
	check(buff("black_mud") == null, "欠损容器回合结束前没有激活黑泥")
	day_end(1)
	check(buff("black_mud") != null and buff("black_mud")._is_active, "欠损容器战果严格低于全部他人且首御主樱时激活黑泥")
	m = sakura_fixture()
	GameData.player_data_library[0].score.number = 11
	day_end(1)
	check(buff("black_mud") != null and not buff("black_mud")._is_active, "欠损容器并列最低不激活黑泥")
	setup()
	master("matou_shinji")
	m = master("matou_sakura")
	start()
	seed_buff("corrupted_grail")
	seed_buff("black_mud")
	day_end(1)
	check(buff("black_mud") != null and not buff("black_mud")._is_active, "欠损容器第一名御主慎二时不激活黑泥")

	m = sakura_fixture()
	day_end(7)
	check(not buff("corrupted_grail")._is_active, "此世全部之恶第七回合不激活圣杯")
	day_end(8)
	check(buff("corrupted_grail")._is_active, "此世全部之恶第八回合非第一名激活圣杯")
	check(GameData.player_data_library[0].is_magic_immune and RegularPlay.limit(0, ctx) == 3, "圣杯激活设置无限魔力并增加一张常规攻击额度")
	day_end(9)
	check(RegularPlay.limit(0, ctx) == 3, "圣杯第九回合不再叠加常规攻击额度")
	m = sakura_fixture()
	GameData.player_data_library[0].score.number = 12
	day_end(8)
	check(not buff("corrupted_grail")._is_active, "此世全部之恶并列第一不激活圣杯")
	check(not GameData.player_data_library[0].is_magic_immune and RegularPlay.limit(0, ctx) == 2, "圣杯未激活不提供无限魔力或额外攻击")
	m = sakura_fixture()
	day_end(9)
	check(not buff("corrupted_grail")._is_active, "此世全部之恶只有第八回合而非任意八回合之后")

	m = sakura_fixture()
	day_end(1)
	var d = GameData.player_data_library[0]
	var e = buff("black_mud")._effects[0]
	d.magic.number = 4
	prepare()
	mud_use(e)
	check(d.magic.number == 2 and d.score.number == 12, "黑泥支付二魔力精确获得二战果")
	print("OBS 黑泥 magic=", d.magic.number, " score=", d.score.number)
	if d.score.number == 12:
		TimePointChecker.dynamic_time_point([TimePoints.PREPARE_PHASE], 0, null, ctx)
		check(EffectManager.waiting_effect != e and d.score.number == 12, "黑泥同回合准备阶段能力不得重复使用")
	else:
		print("UNTESTED 黑泥成功发动后的同回合第二次：首次发动失败。")
	m = sakura_fixture()
	day_end(1)
	d = GameData.player_data_library[0]
	e = buff("black_mud")._effects[0]
	d.magic.number = 1
	prepare()
	var low = EffectManager.waiting_effect == e or EffectManager.request_manual_activation(e, 0)
	if low: EffectManager.submit_active_choice(e, true)
	check(d.magic.number == 1 and d.score.number == 10, "黑泥魔力不足二点拒绝且无半扣费或战果")
	m = sakura_fixture()
	GameData.player_data_library[0].score.number = 12
	day_end(1)
	e = buff("black_mud")._effects[0]
	prepare()
	check(not EffectManager.request_manual_activation(e, 0), "黑泥尚未激活不得发动")
	m = activate_grail()
	d = GameData.player_data_library[0]
	e = buff("black_mud")._effects[0]
	prepare()
	var req = EffectManager.waiting_effect == e or EffectManager.request_manual_activation(e, 0)
	if req: EffectManager.submit_active_choice(e, true)
	check(d.score.number == 10, "黑泥被污染圣杯已激活时不获得战果")
	GameProgress.current_phase_index = 2
	TimePointChecker.set_phase_time_points([TimePoints.ACTION_PHASE], ctx)
	check(not EffectManager.request_manual_activation(e, 0), "黑泥不是准备阶段不得发动")

	m = activate_grail()
	d = GameData.player_data_library[0]
	d.magic.number = 4
	EditMagic.new().exec(null, BaseNumber.new(5), 0, "", null, ctx)
	check(d.magic.number == 4, "被污染圣杯无限魔力状态无法获得魔力")
	EditMagic.new().exec(null, BaseNumber.new(-2), 0, "", null, ctx)
	check(d.magic.number == 4, "被污染圣杯无限魔力状态无法失去魔力")
	d.magic.number = 0
	battle_place()
	var cards = attacks(3)
	check(RegularPlay.submit_group(0, cards, [false, false, false], false, ctx), "被污染圣杯零余额真实打出三张有费常规攻击")
	check(d.played_cards.size() == 3 and d.magic.number == 0, "被污染圣杯三张攻击实际入场且无限魔力不扣余额")
	m = activate_grail()
	battle_place()
	cards = attacks(4)
	check(not RegularPlay.submit_group(0, cards, [false, false, false, false], false, ctx), "被污染圣杯仅多一张拒绝四张常规攻击")
	m = sakura_fixture()
	d = GameData.player_data_library[0]
	d.magic.number = 0
	battle_place()
	cards = attacks(2)
	check(not RegularPlay.submit_group(0, cards, [false, false], false, ctx), "被污染圣杯未激活零余额不能支付常规攻击")

	m = sakura_fixture()
	var skill = m._upgrade_skill[0]
	GameProgress.current_round = 5
	check(not AwakenSkill.new().exec(skill, 0, ctx) and not skill._is_awakened, "腐蚀第五回合不能解锁")
	GameProgress.current_round = 4
	check(AwakenSkill.new().exec(skill, 0, ctx), "腐蚀第四回合允许解锁")
	check(buff("corrosion") != null, "腐蚀真实调试解锁后立即绑定能力")
	check(not AwakenSkill.new().exec(skill, 0, ctx), "腐蚀已解锁不能重复解锁")
	print("OBS 腐蚀直接解锁 awakened=", skill._is_awakened, " buff=", buff("corrosion"))
	var token = corrosion_fixture()
	if token != null:
		e = token._effects[0]
		var a = stolen_skill(1)
		var b = stolen_skill(1, "ni_no_tachi")
		GameData.player_data_library[1].servant_skills.erase(b)
		GameData.player_data_library[1].played_cards.append(b)
		b._is_concealed = false
		b._is_activating = true
		GameData.player_data_library[1].power.number = b._power.number
		var not_chosen = stolen_skill(1, "tsubame_gaeshi")
		ClimaxResolver.new().eliminate_player(1, ctx)
		check(EffectManager.waiting_effect == e, "腐蚀他人真实淘汰且圣杯激活才询问")
		check(EffectManager.submit_option_choice(e, [0]), "腐蚀真实选择入口开始任选技能")
		var offered:Array = EffectManager.get_pending_card_selection().get("cards", [])
		check(offered.has(a) and offered.has(b), "腐蚀提供被淘汰者拥有的从者技能")
		check(EffectManager.submit_card_selection(e, [a, b]), "腐蚀一次选择任意两张技能")
		check(GameData.player_data_library[0].servant_skills.has(a) and GameData.player_data_library[0].servant_skills.has(b), "腐蚀将选中的两张技能真正加入自己技能区")
		check(not GameData.player_data_library[1].servant_skills.has(a) and GameData.player_data_library[1].servant_skills.has(not_chosen), "腐蚀原拥有者移除选中牌并保留未选牌")
		check(not GameData.player_data_library[1].played_cards.has(b) and not b._is_activating and GameData.player_data_library[1].power.number == 0, "腐蚀收取已打出技能移除原打出区清除激活及威力")
		check(a._effects[0]._trigger_player_id == 0 and b._effects[0]._trigger_player_id == 0, "腐蚀所取技能效果归属必须转给自己")
		print("OBS 腐蚀 transfer a=", GameData.player_data_library[0].servant_skills.has(a), " b=", GameData.player_data_library[0].servant_skills.has(b), " effect_owner=", a._effects[0]._trigger_player_id)
		ClimaxResolver.new().eliminate_player(2, ctx)
		check(not EffectManager.is_waiting_for_choice(), "腐蚀每局限一次第二名玩家淘汰不再询问")
	token = corrosion_fixture(false)
	if token != null:
		ClimaxResolver.new().eliminate_player(1, ctx)
		check(not EffectManager.is_waiting_for_choice(), "腐蚀圣杯未激活时他人淘汰不能获得技能")
	m = activate_grail()
	stolen_skill(1)
	ClimaxResolver.new().eliminate_player(1, ctx)
	check(not EffectManager.is_waiting_for_choice(), "腐蚀未解锁即使圣杯激活也不触发")
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
