class_name MoveLocation
extends RefCounted

func exec(move_num:BaseNumber, player_id:int = -1, ignore_limit:bool = false):

	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	var location:BaseLocation = player_data["location"]
	var area:BaseMapArea
	for a:BaseMapArea in MapData.areas:
		if a._locations.has(location):
			area = a
			break
	if area == null:
		#show("玩家所处位置不位于地图上")
		return BaseNumber.new(0)
	var origin_area:BaseMapArea = area

	var total_cost:BaseNumber = BaseNumber.new(0)
	if move_num.number > 0:
		for n in move_num.number:
			if area._linked_map_area != null:
				total_cost.add(area._move_cost)
				area = area._linked_map_area
	elif move_num.number < 0:
		var steps:int = 0 - move_num.number
		for n in steps:
			var area_arr:Array = []
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

	#常规移动只会落在该区域内标记为_will_move_to的Location上(工房区有多个同级点位)，
	#按顺序取第一个还有空位的；ignore_limit时忽略人数限制，取第一个标记点位
	var target_location:BaseLocation = null
	for loc:BaseLocation in area._locations:
		if !loc._will_move_to:
			continue
		if ignore_limit or loc._pl_num_limit == -1 or loc._players.size() < loc._pl_num_limit:
			target_location = loc
			break
	if target_location == null:
		#show("目标位置已满")
		return BaseNumber.new(0)

	if location != null:
		(location._players as Array).erase(player_id)
	(target_location._players as Array).append(player_id)
	player_data["location"] = target_location

	#从魔术工房离开时应用玩家层折扣(葛木局外人等)，折扣不会让费用变成负数
	if origin_area == MapData.magic_workshop:
		var discount = (player_data["move_cost_discount_from_workshop"] as BaseNumber).number
		total_cost.number = max(0, total_cost.number - discount)

	return total_cost
