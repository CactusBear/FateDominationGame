class_name PlaySkill
extends RefCounted

func exec(skill:BaseSkill, player_id:int = -1, ignore_limit:bool = false, cost:BaseNumber = skill._cost, power:BaseNumber = skill._power):

	var id = EffectManager.resolve_player_id(player_id)
	var player_data = GameDataManager.get_player_data(id)
	#带有"无法打出卡牌"效果的buff(如【败北】)会阻止出牌，
	#但不影响已激活的牌和能力的其他使用。按效果名通用查询，不关心具体buff类型
	if PlayerBuffsHaveEffect.new().exec(CannotPlayCardsEffect.EFFECT_NAME, id):
		return
	#卡面声明的打出条件与"需追加打出"，与攻击牌共用同一套判断
	if !PlayRules.can_play(skill, player_data):
		return
	var pl_magic = player_data["magic"] as BaseNumber
	var is_magic_immune = player_data["is_magic_immune"] as bool
	var ignore_zone_limit = player_data["ignore_skill_zone_magic_limit"] as bool
	#技能区的卡需要足够魔力才能打出，门槛取自规则数字而非写死
	if !is_magic_immune and pl_magic.number < GameData.skill_zone_magic_limit.number:
		if !ignore_limit and !skill._ignore_limit and !ignore_zone_limit:
			#show_lack_of_magic()
			return
	if !is_magic_immune:
		pl_magic.minus(cost)

	skill._is_activating = true

	var playered_cards_arr = player_data["played_cards"] as Array
	playered_cards_arr.append(skill)

	#是否计入合计威力交给CardCountsPower判定，必须在入场后再判定
	if CardCountsPower.new().exec(skill, id):
		var pl_power = player_data["power"] as BaseNumber
		pl_power.add(power)

	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], id)
