class_name AddSkill
extends RefCounted

func exec(skill:BaseSkill, player_id:int = -1, ignore_limit:bool = false,  power:BaseNumber = skill._power):

	var id = EffectManager.resolve_player_id(player_id)
	var player_data = GameDataManager.get_player_data(id)
	var pl_magic = player_data["magic"] as BaseNumber
	#技能区的卡需要足够魔力才能打出，门槛取自规则数字而非写死
	if pl_magic.number < GameData.skill_zone_magic_limit.number:
		if !ignore_limit and !skill._ignore_limit:
			#show_lack_of_magic()
			return
	var pl_power = player_data["power"] as BaseNumber
	pl_power.add(power)

	skill._is_activating = true

	var playered_cards_arr = player_data["played_cards"] as Array
	playered_cards_arr.append(skill)

	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], id)
