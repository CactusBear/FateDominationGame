extends "res://tests/ichi_no_tachi_test.gd"

func setup() -> void:
	ctx = _reset_ctx()
	GameLog.reset()
	preload("res://scripts/match/rule_random.gd").start_seed(3304)
	GameData.player_data_library.clear()
	MapData.active_situation = null
	GameProgress.is_game_over = false
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	GameLog.set_context(1, "action")
	for id in range(3):
		var d = GameData.new_player_data()
		d.is_out = false
		d.order.number = id
		d.magic.number = 4
		d.score.number = 10 + id
		GameData.player_data_library[id] = d
	TimePointChecker.set_phase_time_points([], ctx)

func master(key:String, id:int = 0):
	var d = GameData.player_data_library[id]
	if d.master != null: UnregisterObjectEffects.new().exec(d.master)
	d.master = named(GameData.loaded_masters, key)
	GameLog.record("master_assigned", id, -1, "", d.master, ["master_assigned"], {})
	check(MasterManager.bind_master_effects(id, ctx), "御主夹具使用正式本局创建绑定入口")
	return d.master

func servant(key:String, id:int = 0):
	var d = GameData.player_data_library[id]
	d.servant = named(GameData.loaded_servants, key)
	GameLog.record("servant_assigned", id, -1, "", d.servant, ["servant_assigned"], {})
	check(ServantManager.bind_servant_effects(id, ctx), "从者夹具使用正式本局创建绑定入口")
	return d.servant

func seed_buff(key:String, id:int = 0):
	var d = GameData.player_data_library[id]
	var b = named(d.master._specials.BUFFS, key)
	if not d.buffs.has(b):
		d.buffs.append(b)
		EffectManager.register_effects(b._effects, id)
	return b

func start():
	TimePointChecker.global_time_point([TimePoints.GAME_START], null, ctx)

func day_end(round_num:int):
	GameProgress.current_round = round_num
	GameLog.set_context(round_num, "end")
	TimePointChecker.set_phase_time_points([], ctx)
	TimePointChecker.global_time_point([TimePoints.DAY_END], null, ctx)

func buff(key:String, id:int = 0):
	return named(GameData.player_data_library[id].buffs, key)

func fixture_book(sakura_present:bool = false):
	setup()
	var m = master("matou_shinji")
	servant("medusa")
	servant("artoria_pendragon", 1)
	servant("emiya", 2)
	if sakura_present: master("matou_sakura", 1)
	start()
	if buff("false_servant_book") == null:
		print("DIAG 开局伪臣之书未获得；以下从本局角色已创建的附带buff配置初始持有状态，仅隔离验证效果体。")
		seed_buff("false_servant_book")
	return m

func core_fixture():
	var m = fixture_book()
	var s = m._upgrade_skill[0]
	check(AwakenSkill.new().exec(s, 0, ctx), "圣杯核心调试解锁真实入口接受本人的升华技")
	RegisterObjectEffects.new().exec(s, 0, ctx)
	return s

func run():
	setup()
	var m = master("matou_shinji")
	check(buff("false_servant_book") == null, "无用之人开局前没有伪臣之书")
	start()
	check(buff("false_servant_book") != null, "无用之人游戏开始获得伪臣之书")
	check(GameData.player_data_library[0].buffs.size() == 1, "无用之人仅获得一张伪臣之书")
	var d = GameData.player_data_library[0]
	var area = GetMapAreaByName.new().exec("深山町")
	check(SetLocation.new().exec(area._locations[0], 0, false, true, true, ctx), "吸魔命令实际进入深山町入口")
	check(d.magic.number == 5, "吸魔命令进入深山町精确获得一点魔力")
	var other = GetMapAreaByName.new().exec("新都")
	SetLocation.new().exec(other._locations[0], 0, false, true, true, ctx)
	check(d.magic.number == 5, "吸魔命令进入新都不获得魔力")
	SetLocation.new().exec(area._locations[0], 1, false, true, true, ctx)
	check(d.magic.number == 5, "吸魔命令他人进入深山町不奖励自己")
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], 0, null, ctx)
	check(d.command_spell_count.number == 3, "小丑战胜不失去令咒")
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_LOSE], 0, null, ctx)
	check(d.command_spell_count.number == 2, "小丑自己战败精确失去一枚令咒")
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_LOSE], 1, null, ctx)
	check(d.command_spell_count.number == 2, "小丑他人战败不失去令咒")
	for i in range(3): TimePointChecker.dynamic_time_point([TimePoints.BATTLE_LOSE], 0, null, ctx)
	check(d.command_spell_count.number == 0, "小丑令咒不足时下限为零")

	m = fixture_book()
	d = GameData.player_data_library[0]
	day_end(1)
	check(d.master == m and d.command_spell_count.number == 3, "替代品尚有令咒时不替换御主")
	d.magic.number = 9
	# 第 2 回合内战败清零、同回合结束结算（与真实对局同一回合）
	GameProgress.current_round = 2; GameLog.set_context(2, "battle")
	for i in range(3): TimePointChecker.dynamic_time_point([TimePoints.BATTLE_LOSE], 0, null, ctx)
	check(d.master == m, "替代品失去所有令咒不立即替换")
	day_end(2)
	check(d.master != null and d.master._name == "matou_sakura", "替代品该回合结束御主替换为间桐樱")
	check(d.magic.number == 4 and d.command_spell_count.number == 2 and d.score.number == 10, "替代品重置四魔力获得二令咒保持战果")
	check(buff("false_servant_book") == null, "替代品替换后移除伪臣之书")
	print("OBS 替代品 master=", d.master._name, " magic=", d.magic.number, " cs=", d.command_spell_count.number, " score=", d.score.number)
	var after = d.master
	d.command_spell_count.number = 0
	day_end(3)
	check(d.master == after and d.command_spell_count.number == 0, "替代品首次之后不再次替换或发令咒")

	m = fixture_book()
	d = GameData.player_data_library[0]
	for i in range(3): TimePointChecker.dynamic_time_point([TimePoints.BATTLE_LOSE], 0, null, ctx)
	SetPlayerData.new().exec("command_spell_count", BaseNumber.new(1), 0, ctx)
	day_end(1)
	check(d.master != m and d.master._name == "matou_sakura", "替代品首次清零后同回合恢复令咒仍应回合结束替换")
	check(d.used_once_effects.has("false_servant_book_master_replace"), "替代品首次清零事件必须锁存即使结束时已有令咒")
	print("OBS 清零后恢复 master=", d.master._name, " cs=", d.command_spell_count.number, " consumed=", d.used_once_effects)

	m = fixture_book(true)
	d = GameData.player_data_library[0]
	var old_servant = d.servant
	day_end(1)
	check(d.servant == old_servant, "契约再续尚有令咒不替换从者")
	GameProgress.current_round = 2; GameLog.set_context(2, "battle")
	for i in range(3): TimePointChecker.dynamic_time_point([TimePoints.BATTLE_LOSE], 0, null, ctx)
	day_end(2)
	check(d.master == m and d.servant != old_servant, "契约再续樱在场只替换从者不替换御主")
	check(d.command_spell_count.number == 3, "契约再续精确重新获得三令咒")
	var used_names:Array = [old_servant._name, GameData.player_data_library[1].servant._name, GameData.player_data_library[2].servant._name]
	check(d.servant != null and not used_names.has(d.servant._name), "契约再续随机从者必须未被使用")
	print("OBS 契约再续 servant=", d.servant._name if d.servant != null else "null", " used=", used_names, " cs=", d.command_spell_count.number)
	var replacement = d.servant
	d.command_spell_count.number = 0
	day_end(3)
	check(d.servant == replacement and d.command_spell_count.number == 0, "契约再续每局首次之后不再次替换")

	m = fixture_book(true)
	d = GameData.player_data_library[0]
	# 把正式池中的每名从者分配给真实成员，检查没有未使用从者的边界。
	for i in range(GameData.loaded_servants.size()):
		var id = i + 3
		var pl = GameData.new_player_data()
		pl.is_out = false
		pl.order.number = id
		GameData.player_data_library[id] = pl
		servant(GameData.loaded_servants[i]._name, id)
	old_servant = d.servant
	# 26B 口径：本局分配过的从者（按名字，含已替换/已淘汰）都算已使用；候选由卡效数据自己算，下面验结果。
	for i in range(3): TimePointChecker.dynamic_time_point([TimePoints.BATTLE_LOSE], 0, null, ctx)
	day_end(1)
	check(d.servant == old_servant and d.command_spell_count.number == 0, "契约再续池内全部从者已被使用时不能替换或补令咒")
	print("OBS 全池已用 servant=", d.servant._name if d.servant != null else "null", " cs=", d.command_spell_count.number)

	var core = core_fixture()
	d = GameData.player_data_library[0]
	check(not core._values.active, "圣杯核心解锁本身不提前生效")
	day_end(7)
	check(not core._values.active and buff("false_servant_book") != null, "圣杯核心第七回合不生效不移除伪臣之书")
	day_end(8)
	check(not core._values.active and buff("false_servant_book") != null, "圣杯核心第八回合但从者不是莎士比亚不生效")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE], ctx)
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], 0, null, ctx)
	check(d.power.number == 0, "圣杯核心未生效不能获得十二合计威力")
	check(d.score.number == 10, "圣杯核心未生效不能获得八点战果")
	SetLocation.new().exec(area._locations[1], 1, false, true, true, ctx)
	var score_action = await preload("res://newtests/keyword_frame_fixture.gd").execute("edit_score", [null, BaseNumber.new(3), 0], ctx)
	check(score_action.get("ok", false) and d.score.number == 13, "圣杯核心反例用真实战果操作增加三点战果")
	check(GameData.player_data_library[1].score.number == 11, "圣杯核心未生效加分时点不吸取对手战果")
	check(named(GameData.loaded_servants, "shakespeare") != null, "圣杯核心正例所需莎士比亚必须在正式从者池存在")
	print("UNTESTED 圣杯核心四条效果的满足条件正例：正式数据未提供莎士比亚，不伪造从者。")
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
