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
func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)

func setup() -> void:
	EffectManager.reset_runtime(); GameLog.reset(); GameLog.set_context(1,"action")
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
	if template != null:
		var cloned = CloneObject.new().exec(template)
		check(cloned != null and cloned.has_keyword(ApplyCardKeywords.TRUE_NAME_RELEASE),
			"clone keeps the keyword")

	#——行为层：结算词条就会真名解放，并派发时点——
	setup()
	check(!ReleaseTrueName.is_released(0), "not released before playing")
	if template != null:
		var card = CloneObject.new().exec(template)
		ApplyCardKeywords.new().exec(card, 0)
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
		var owner:=BaseMaster.new("owner","owner","","","")
		var extra_skill:=BaseSkill.new("extra_skill","",[],BaseNumber.new(0),BaseNumber.new(2))
		var servant_skill:=BaseSkill.new("servant_skill","",[],BaseNumber.new(0),BaseNumber.new(2))
		var upgrade:=BaseSkill.new("upgrade","",[],BaseNumber.new(0),BaseNumber.new(2))
		extra_skill._is_concealed=true; servant_skill._is_concealed=true; upgrade._is_concealed=true
		upgrade._is_awakened=false
		owner._specials={"SKILLS":[extra_skill]}; owner._upgrade_skill=[upgrade]
		var owner_data:Dictionary=GameDataManager.get_player_data(0)
		owner_data.master=owner; owner_data.servant_skills=[servant_skill]
		check(ReleaseTrueName.new().exec(0) and not extra_skill._is_concealed and not servant_skill._is_concealed,
			"release reveals both servant and master supplemental skills")
		check(upgrade._is_concealed and not upgrade._is_awakened,"release does not awaken an upgrade skill")
		var before:int = GameLog.query({"type":"true_name_release","actor":0}, null).size()
		ApplyCardKeywords.new().exec(card, 0)
		check(GameLog.query({"type":"true_name_release","actor":0}, null).size() == before,
			"already-released player is not released twice")
		check(HideTrueName.new().exec(0) and extra_skill._is_concealed and servant_skill._is_concealed,
			"hide covers both supplemental and servant skills")

	#没有词条的牌不该解放
	setup()
	var plain = null
	for sv in GameData.loaded_servants:
		if sv == null: continue
		for sk in ((sv._specials.get("SKILLS") if sv._specials != null else []) as Array):
			if sk is BaseSkill and !sk.has_keyword(ApplyCardKeywords.TRUE_NAME_RELEASE):
				plain = CloneObject.new().exec(sk)
				break
		if plain != null: break
	if plain != null:
		ApplyCardKeywords.new().exec(plain, 0)
		check(!ReleaseTrueName.is_released(0), "a card without the keyword releases nothing")

	#未识别的词条不做任何事，也不报错（加新词条不必改老数据）
	setup()
	if plain != null:
		plain._keywords = ["some_future_keyword_not_implemented_yet"]
		ApplyCardKeywords.new().exec(plain, 0)
		check(!ReleaseTrueName.is_released(0), "unknown keyword is a no-op")

	#整组常规出牌视为同时发生：依赖真名状态的牌即使排在词条牌之前，
	#其费用计算条件也必须读到已解放；暗置词条牌不触发。
	for keyword_hidden in [false, true]:
		setup()
		GameProgress.current_round = 1
		GameProgress.current_phase_index = 2
		GameProgress.current_player_id = 0
		TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX])
		TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX], 0)
		var d:Dictionary = GameDataManager.get_player_data(0)
		var conditional := BaseAttack.new("conditional", "", [], BaseNumber.new(0), BaseNumber.new(0))
		var release_card := BaseAttack.new("release", "", [], BaseNumber.new(0), BaseNumber.new(0))
		release_card._keywords = [ApplyCardKeywords.TRUE_NAME_RELEASE]
		var condition_effect := BaseEffect.new("requires_true_name", [TimePoints.SELF_CARD_COST_CALCULATED], 0, true)
		condition_effect.from = conditional
		condition_effect._funcs = LoadHelper.load_funcs([
			{"func_name":"is_true_name_released", "parameters":[-1], "var_index":0},
			{"func_name":"edit_power", "parameters":[null, BaseNumber.new(1), 0], "var_index":-1,
				"condition":{"self_var":0}}
		], condition_effect)
		conditional._effects = [condition_effect]
		d.hand_cards = [conditional, release_card]
		RegisterObjectEffects.new().exec(conditional, 0)
		check(RegularPlay.submit_group(0, [conditional, release_card], [false, keyword_hidden]),
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
		Deploy.new().exec(seat, 0)
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
