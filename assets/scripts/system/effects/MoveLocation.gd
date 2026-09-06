class_name MoveLocation
extends RefCounted

func exec(move_num:BaseNumber, player_id:int = GameData.player_id, ignore_limit:bool = false):

	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	var location:BaseLocation = player_data["location"]
	var area:BaseMapArea
	for a:BaseMapArea in MapData.areas:
		var arr = area._locations as Array
		if !arr.has(location): 
			#show("玩家所处位置不位于地图上")
			return BaseNumber.new(0)
		area = a
	
	var total_cost:BaseNumber = BaseNumber.new(0)
	if move_num.number > 0:
		for n in move_num.number:
			if area._linked_map_area != null:
				total_cost.add(area._move_cost)
				area = area._linked_map_area
	elif move_num.number < 0:
		move_num.set_num(BaseNumber.new(0 - move_num.number))
		for n in move_num.number:
			var area_arr:Array
			for a:BaseMapArea in MapData.areas:
				if a._linked_map_area == area:
					area_arr.append(a)
			if area_arr.size() > 1:
				#area = choose_where_to_go()
				continue
			if area_arr.size() == 1:
				area = area_arr[0]
	else:
		return BaseNumber.new(0)
	
	if area._can_move_to == false:
		#show("无法移动至此区域")
		return BaseNumber.new(0)
	if ignore_limit:
		for loc:BaseLocation in area._locations:
			if loc._pl_num_limit == -1:
				var arr = loc._players as Array
				arr.append(player_id)
				player_data["location"] = loc
				return total_cost
	else :
		for loc:BaseLocation in area._locations:
			if loc._pl_num_limit <= loc._players.size():
				#show("目标位置已满")
				return BaseNumber.new(0)
			if loc._pl_num_limit > loc._players.size() and loc._will_move_to:
				var arr = loc._players as Array
				arr.append(player_id)
				player_data["location"] = loc
				return total_cost
				
	return BaseNumber.new(0)
