extends Node
#词条机制与合计威力查询的回归。
#用户现象："仍然不能真名解放"、"用了真名解放牌之后没有真名解放"。
#根因：ReleaseTrueName 能派时点，但全项目没有任何地方调用它——
#【真名解放】只以卡面文案的形式存在，没有结构化声明，引擎无从得知哪张牌带词条。
#修法（方案A）：BaseCard 加显式 _keywords，JSON 用 keywords 声明；
#新增 ApplyCardKeywords 把"词条 -> 规则动作"集中一处，四个出牌入口
#(PlayAttack/PlaySkill/AddAttack/AddSkill) 在派 PLAYED_CARD 之前各调一次。
#规则本体只有一份，不去扫文案里的【xx】字样，也不在 11 张牌里复制同一段规则。
var failures:Array=[]
var checks:=0
var fixture_context:SessionContext = null
const KeywordFrameFixture = preload("res://newtests/keyword_frame_fixture.gd")
func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)

func setup() -> void:
	var reset:Dictionary = EffectManager.reset_runtime()
	fixture_context = reset.get("context") if reset.get("ok", false) else null
	check(reset.get("ok", false), "fixture reset returns original source")
	GameLog.reset(); GameLog.set_context(1,"action")
	GameProgress.is_game_over=false
	GameData.player_data_library.clear()
	for i in range(3):
		GameData.player_data_library[i]=GameData.new_player_data()
		var d=GameData.player_data_library[i]
		d.is_out=false
		d.order.set_num(BaseNumber.new(i))
		d.magic.number=30
		d.location=null
	for area in MapData.areas:
		for loc in area._locations:
			(loc._players as Array).clear()

# 只转换调用方明确选出的 loaded 模板或本测试的显式声明模板；不修改模板、不在消费口补票。
# configure_template/copy_result 与现有 command_spell_test 使用同一工厂契约。
func clone_loaded_template(template):
	var factory := CloneContext.new()
	var configured:bool = factory.configure_template(fixture_context, [template])
	check(configured, "fixture authorizes selected loaded template")
	if not configured:
		return null
	var copied:Dictionary = factory.copy_result(template, fixture_context)
	check(copied.ok, "fixture runtime clone receipt: %s" % copied.reason)
	return copied.object if copied.ok else null

# helper 只消费真实进度根的回执；不写执行器字段，不把拒绝当业务成功。
func run_rule(key:String, parameters:Array, value_required:bool = false):
	var original:SessionContext = fixture_context
	var completed:Dictionary = await KeywordFrameFixture.execute(key, parameters, original, value_required)
	check(completed.get("ok", false), "fixture progress operation %s: %s" % [key, completed.get("reason", "completed")])
	return completed.get("value") if completed.get("ok", false) else false

func _ready(): call_deferred("run")

func run():
	#——数据层：词条必须显式声明，且只声明在真正自带词条的牌上——
	var declared:int = 0
	var by_servant:Dictionary = {}
	for sv in GameData.loaded_servants:
		if sv == null: continue
		for sk in ((sv._specials.get("SKILLS") if sv._specials != null else []) as Array):
			if sk is BaseSkill and sk.has_keyword(ApplyCardKeywords.TRUE_NAME_RELEASE):
				declared += 1
				by_servant[sv.get_shown_name()] = int(by_servant.get(sv.get_shown_name(), 0)) + 1
	check(declared > 0, "some skill cards declare the true-name keyword (%d)" % declared)
	print("   声明分布: ", by_servant)

	#条件触发型（"若…则【真名解放】"）不是牌自带词条，不该被声明
	var wrongly:Array = []
	for sv in GameData.loaded_servants:
		if sv == null: continue
		for sk in ((sv._specials.get("SKILLS") if sv._specials != null else []) as Array):
			if !(sk is BaseSkill): continue
			if !sk.has_keyword(ApplyCardKeywords.TRUE_NAME_RELEASE): continue
			#带词条的牌，其效果文案应明确印有该词条；词条可独占一行或作为效果正文前缀。
			var starts:bool = false
			for eff in sk._effects:
				if str(eff.get_shown_name()).contains("【真名解放】"):
					starts = true
					break
			if !starts:
				wrongly.append("%s / %s" % [sv.get_shown_name(), sk.get_shown_name()])
	check(wrongly.is_empty(), "keyword only on cards that actually carry it (%s)" % str(wrongly))

	#——克隆要带上词条：实战用的是克隆体，丢了声明就等于没声明——
	var template = null
	for sv in GameData.loaded_servants:
		if sv == null: continue
		for sk in ((sv._specials.get("SKILLS") if sv._specials != null else []) as Array):
			if sk is BaseSkill and sk.has_keyword(ApplyCardKeywords.TRUE_NAME_RELEASE):
				template = sk
				break
		if template != null: break
	check(template != null, "found a keyword-carrying template")
	var supplemental_templates:Array = KeywordFrameFixture.supplemental_templates()
	# 首次克隆早于 setup；在此建立自己的生命周期并保留原回执，不领取 current。
	var initial:Dictionary = EffectManager.reset_runtime()
	fixture_context = initial.get("context") if initial.get("ok", false) else null
	check(initial.get("ok", false), "fixture initial lifecycle returns original source")
	if template != null:
		var cloned = clone_loaded_template(template)
		check(cloned != null and cloned.has_keyword(ApplyCardKeywords.TRUE_NAME_RELEASE),
			"clone keeps the keyword")

	#——行为层：结算词条就会真名解放，并派发时点——
	setup()
	check(!ReleaseTrueName.is_released(0), "not released before playing")
	if template != null:
		var card = clone_loaded_template(template)
		await run_rule("apply_card_keywords", [card, 0])
		check(ReleaseTrueName.is_released(0), "keyword triggers true-name release")
		check(!GameLog.query({"type":"true_name_release","actor":0}, null).is_empty(),
			"release is recorded as a fact")
		check(not GameLog.query({"type":"time_point","actor":0,"tags":[TimePoints.TRUE_NAME_RELEASE]},0).is_empty(),
			"release time point is dispatched")
		check(not GameDataManager.get_player_data(0)["current_time_points"].has(TimePoints.TRUE_NAME_RELEASE),
			"release event does not remain as a lasting window")
		#别人不该被连带解放
		check(!ReleaseTrueName.is_released(1), "other players are unaffected")
		# 真名解放须覆盖实际技能区和御主附带技能展示区；未觉醒升华技不在范围内。
		setup()
		# 同一已加载模板，本代重新创建；旧 card 不得跨 reset 复用。
		card = clone_loaded_template(template)
		var supplemental:Array = clone_loaded_template(supplemental_templates)
		var owner:BaseMaster = supplemental[0]
		var extra_skill:BaseSkill = owner._specials.SKILLS[0]
		var servant_skill:BaseSkill = supplemental[1]
		var upgrade:BaseSkill = owner._upgrade_skill[0]
		extra_skill._is_concealed=true; servant_skill._is_concealed=true; upgrade._is_concealed=true
		upgrade._is_awakened=false
		owner._specials={"SKILLS":[extra_skill]}; owner._upgrade_skill=[upgrade]
		var owner_data:Dictionary=GameDataManager.get_player_data(0)
		owner_data.master=owner; owner_data.servant_skills=[servant_skill]
		check((await run_rule("release_true_name", [0], true)) and not extra_skill._is_concealed and not servant_skill._is_concealed,
			"release reveals both servant and master supplemental skills")
		check(upgrade._is_concealed and not upgrade._is_awakened,"release does not awaken an upgrade skill")
		var before:int = GameLog.query({"type":"true_name_release","actor":0}, null).size()
		await run_rule("apply_card_keywords", [card, 0])
		check(GameLog.query({"type":"true_name_release","actor":0}, null).size() == before,
			"already-released player is not released twice")
		check((await run_rule("hide_true_name", [0], true)) and extra_skill._is_concealed and servant_skill._is_concealed,
			"hide covers both supplemental and servant skills")

	#没有词条的牌不该解放
	setup()
	var plain = null
	var plain_template = null
	for sv in GameData.loaded_servants:
		if sv == null: continue
		for sk in ((sv._specials.get("SKILLS") if sv._specials != null else []) as Array):
			if sk is BaseSkill and !sk.has_keyword(ApplyCardKeywords.TRUE_NAME_RELEASE):
				plain_template = sk
				plain = clone_loaded_template(plain_template)
				break
		if plain != null: break
	if plain != null:
		await run_rule("apply_card_keywords", [plain, 0])
		check(!ReleaseTrueName.is_released(0), "a card without the keyword releases nothing")

	#未识别的词条不做任何事，也不报错（加新词条不必改老数据）
	setup()
	if plain_template != null:
		plain = clone_loaded_template(plain_template)
	if plain != null:
		plain._keywords = ["some_future_keyword_not_implemented_yet"]
		await run_rule("apply_card_keywords", [plain, 0])
		check(!ReleaseTrueName.is_released(0), "unknown keyword is a no-op")

	#整组常规出牌视为同时发生：依赖真名状态的牌即使排在词条牌之前，
	#其费用计算条件也必须读到已解放；暗置词条牌不触发。
	for keyword_hidden in [false, true]:
		setup()
		GameProgress.current_round = 1
		GameProgress.current_phase_index = 2
		GameProgress.current_player_id = 0
		TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX], fixture_context)
		TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX], 0, null, fixture_context)
		var d:Dictionary = GameDataManager.get_player_data(0)
		var batch:Array = KeywordFrameFixture.simultaneous_cards(fixture_context)
		check(batch.size() == 2, "fixture loads both simultaneous runtime cards")
		var conditional:BaseAttack = batch[0]
		var release_card:BaseAttack = batch[1]
		d.hand_cards = [conditional, release_card]
		await run_rule("register_object_effects", [conditional, 0, fixture_context])
		# 保留真实整组入口；它无法装进现有注册执行器，具体帧缺口在交接报告中列明。
		check(RegularPlay.submit_group(0, [conditional, release_card], [false, keyword_hidden], false, fixture_context),
			"simultaneous group submits with keyword hidden=%s" % keyword_hidden)
		check(ReleaseTrueName.is_released(0) == not keyword_hidden,
			"only a face-up simultaneous keyword releases true name hidden=%s" % keyword_hidden)
		check(((d.power as BaseNumber).number > 0) == not keyword_hidden,
			"true-name-dependent card sees simultaneous release hidden=%s" % keyword_hidden)

	#——合计威力查询：结算与界面共用同一份公式——
	setup()
	var d0 = GameDataManager.get_player_data(0)
	(d0["power"] as BaseNumber).set_num(BaseNumber.new(7))
	(d0["total_power_bonus"] as BaseNumber).set_num(BaseNumber.new(2))
	var brk:Dictionary = GetPlayerTotalPower.breakdown(0)
	check(int(brk["power"]) == 7, "breakdown reports played-card power")
	check(int(brk["bonus"]) == 2, "breakdown reports total-power bonus")
	check(int(brk["total"]) == 7 + 2 + int(brk["location_benefit"]),
		"total equals power + bonus + location benefit")
	check(GetPlayerTotalPower.new().exec(0) == int(brk["total"]), "exec matches breakdown total")

	#加成一改，查询立刻反映（"影响威力的效果要马上算出来"靠的就是这条）
	(d0["total_power_bonus"] as BaseNumber).add(BaseNumber.new(3))
	check(GetPlayerTotalPower.new().exec(0) == int(brk["total"]) + 3,
		"a bonus change is reflected immediately")

	#部署到地利位置后，地利立刻计入合计威力，不必等战斗阶段
	var before_pw:int = GetPlayerTotalPower.new().exec(0)
	var seat = DeployRules.pick_location(MapData.miyama)
	if seat != null and (seat._printed_benefit as BaseNumber).number > 0:
		await run_rule("deploy", [seat, 0, false, fixture_context], true)
		check(GetPlayerTotalPower.new().exec(0) > before_pw,
			"location benefit counts the moment you deploy (%d -> %d)" % [before_pw, GetPlayerTotalPower.new().exec(0)])
		check(GameLog.query({"type":"battle"}, null).is_empty(), "no battle was needed for that")

	#不存在的玩家返回全 0，不报错
	var none:Dictionary = GetPlayerTotalPower.breakdown(9999)
	check(int(none["total"]) == 0, "missing player yields zeros")

	print("RESULT checks=",checks," failures=",failures)
	var f=FileAccess.open("res://card_keyword_result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures})); f.close()
	get_tree().quit(0 if failures.is_empty() else 1)
