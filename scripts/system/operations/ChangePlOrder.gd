class_name ChangePlOrder
extends RefCounted

func exec(set_order:BaseNumber = null, vary_order:BaseNumber = BaseNumber.new(0), player_id = -1):

	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if set_order != null and set_order.number is int:
		var current_order = player_data["order"] as BaseNumber
		var pl_ids = GetAllPlayersId.new().exec()
		if set_order.number < current_order.number:
			for order in range(set_order.number,current_order.number + 1):
				for id in pl_ids:
					var pl_data = GameDataManager.get_player_data(id)
					var pl_order = pl_data["order"] as BaseNumber
					if pl_order.number == order:
						pl_order.add(BaseNumber.new(1))
					if pl_order.number >= GameData.player_num:
						pl_order.minus(BaseNumber.new(GameData.player_num))
			player_data["order"] = set_order
		elif set_order.number > current_order.number:
			for order in range(current_order.number,set_order.number + 1):
				for id in pl_ids:
					var pl_data = GameDataManager.get_player_data(id)
					var pl_order = pl_data["order"] as BaseNumber
					if pl_order.number == order:
						pl_order.minus(BaseNumber.new(1))
					if pl_order.number <= -1:
						pl_order.add(BaseNumber.new(GameData.player_num))
			player_data["order"] = set_order
			
	var pl_ids = GetAllPlayersId.new().exec()
	for id in pl_ids:
		var pl_data = GameDataManager.get_player_data(id)
		var pl_order = pl_data["order"] as BaseNumber
		pl_order.add(vary_order)
		if pl_order.number >= GameData.player_num:
			pl_order.minus(BaseNumber.new(GameData.player_num))
		if pl_order.number <= -1:
			pl_order.add(BaseNumber.new(GameData.player_num))
