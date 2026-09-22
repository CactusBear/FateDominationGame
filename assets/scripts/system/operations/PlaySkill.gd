class_name PlaySkill
extends RefCounted

func exec(skill:BaseSkill, player_id:int = -1, ignore_limit:bool = false, cost:BaseNumber = null, power:BaseNumber = null):
	if skill == null:
		return false
	if cost == null:
		cost = skill._cost
	if power == null:
		power = skill._power

	if not ignore_limit and EffectManager.activating_eff == null:
		return false
	var id = EffectManager.resolve_player_id(player_id)
	var player_data = GameDataManager.get_player_data(id)
	#带有"无法打出卡牌"效果的buff(如【败北】)会阻止出牌，
	#但不影响已激活的牌和能力的其他使用。按效果名通用查询，不关心具体buff类型
	if PlayerBuffsHaveEffect.new().exec(CannotPlayCardsEffect.EFFECT_NAME, id):
		return false
	#卡面声明的打出条件与"需追加打出"，与攻击牌共用同一套判断
	if !PlayRules.can_play(skill, player_data):
		return false
	#局面级禁令与攻击牌同一套：宝具是技能卡的属性，禁令声明在局势牌/事件牌上，
	#出牌入口只按效果名查询
	if skill._attributes.has(Attributes.NOBLE_PHANTASM) and BoardHasEffect.new().exec(ForbidNoblePhantasmEffect.EFFECT_NAME):
		return false
	if skill._attributes.has(Attributes.SPECIAL) and BoardHasEffect.new().exec(ForbidSpecialAttackEffect.EFFECT_NAME):
		return false
	var pl_magic = player_data["magic"] as BaseNumber
	var is_magic_immune = player_data["is_magic_immune"] as bool
	var ignore_zone_limit = player_data["ignore_skill_zone_magic_limit"] as bool
	#技能区的卡需要足够魔力才能打出，门槛取自规则数字而非写死
	if !is_magic_immune and pl_magic.number < GameData.skill_zone_magic_limit.number:
		if !ignore_limit and !skill._ignore_limit and !ignore_zone_limit:
			#show_lack_of_magic()
			return false
	# 费用计算时点必须先于最终费用与可支付性判断；卡面减费才影响本次出牌。
	TimePointChecker.dynamic_time_point([TimePoints.CARD_COST_CALCULATED], id, skill)
	if !is_magic_immune and pl_magic.number < cost.number:
		return false
	if !is_magic_immune:
		var magic_before = pl_magic.number
		pl_magic.minus(cost)
		#扣费与 EditMagic 同一套记录口径（本操作不派 MAGIC_DECREASE 时点，保持原有行为）
		GameLog.record_resource_change("magic", id, magic_before, pl_magic.number)

	skill._is_activating = true

	var playered_cards_arr = player_data["played_cards"] as Array
	playered_cards_arr.append(skill)

	#是否计入合计威力交给CardCountsPower判定，必须在入场后再判定
	if CardCountsPower.new().exec(skill, id):
		var pl_power = player_data["power"] as BaseNumber
		pl_power.add(power)

	GameLog.record("play", id, -1, "", skill, ["play"],
		{"card_name": skill._name, "card_type": "skill", "extra": true})
	#词条规则在打出时点之前结算，理由同 PlayAttack
	ApplyCardKeywords.new().exec(skill, id)
	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], id, skill)
	return true
