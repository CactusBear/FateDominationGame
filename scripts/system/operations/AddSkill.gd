class_name AddSkill
extends RefCounted

func exec(skill:BaseSkill, player_id:int = -1, ignore_limit:bool = false, power:BaseNumber = null):
	if skill == null:
		return false
	if power == null:
		power = skill._power

	var id = EffectManager.resolve_player_id(player_id)
	var player_data = GameDataManager.get_player_data(id)
	var pl_magic = player_data["magic"] as BaseNumber
	if pl_magic.number < GameData.skill_zone_magic_limit.number:
		if !ignore_limit and !skill._ignore_limit:
			return false
	skill._is_activating = true

	var playered_cards_arr = player_data["played_cards"] as Array
	playered_cards_arr.append(skill)

	#是否计入合计威力交给CardCountsPower判定，必须在入场后再判定
	if CardCountsPower.new().exec(skill, id):
		var pl_power = player_data["power"] as BaseNumber
		pl_power.add(power)

	GameLog.record("play", id, -1, "", skill, ["play", "extra"],
		{"card_name": skill._name, "card_type": "skill", "extra": true})
	#词条规则在打出时点之前结算，理由同 PlayAttack
	ApplyCardKeywords.new().exec(skill, id)
	TimePointChecker.card_revealed(skill)
	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], id, skill)
	return true
