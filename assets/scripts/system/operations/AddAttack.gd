class_name AddAttack
extends RefCounted

func exec(attack:BaseAttack, player_id:int = -1, power:BaseNumber = attack._power):

	var id = EffectManager.resolve_player_id(player_id)
	var player_data = GameDataManager.get_player_data(id)

	attack._is_activating = true

	var playered_cards_arr = player_data["played_cards"] as Array
	playered_cards_arr.append(attack)

	#是否计入合计威力交给CardCountsPower判定，必须在入场后再判定
	if CardCountsPower.new().exec(attack, id):
		var pl_power = player_data["power"] as BaseNumber
		pl_power.add(power)

	GameLog.record("play", id, -1, "", attack, ["play", "extra"],
		{"card_name": attack._name, "card_type": "attack", "extra": true})
	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], id)
