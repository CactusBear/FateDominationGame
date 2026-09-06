class_name PlayAttack
extends RefCounted

func exec(attack:BaseAttack, player_id:int = -1, cost:BaseNumber = attack._cost, power:BaseNumber = attack._power):

	var id = EffectManager.resolve_player_id(player_id)
	var player_data = GameDataManager.get_player_data(id)
	var pl_magic = player_data["magic"] as BaseNumber
	pl_magic.minus(cost)
	var pl_power = player_data["power"] as BaseNumber
	pl_power.add(power)

	attack._is_activating = true

	var playered_cards_arr = player_data["played_cards"] as Array
	playered_cards_arr.append(attack)

	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], id)
