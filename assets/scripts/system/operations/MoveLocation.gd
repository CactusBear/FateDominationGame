class_name MoveLocation
extends RefCounted

#沿地图链算出移动后的落点并返回总费用，不扣魔力（扣魔力由 Move 负责）。
#只做"算目标区域 + 算费用"这件事：落地（改变 location、同步落点 _players）交给
#SetLocation，与部署/效果搬运共用同一份落地逻辑，不在这里重复实现。
func exec(move_num:BaseNumber, player_id:int = -1, ignore_limit:bool = false):

	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	var location:BaseLocation = player_data["location"]
	if location == null:
		EffectManager.push_message("当前位置不在任何战区上，无法移动", player_id)
		return null
	#所在区域从 location 自己的 from 取，不遍历 MapData.areas 反查
	var area := location.get_from() as BaseMapArea
	if area == null:
		EffectManager.push_message("当前位置不在任何战区上，无法移动", player_id)
		return null
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
		return null

	if area._can_move_to == false:
		EffectManager.push_message("无法移动至【%s】" % area._area_name, player_id)
		return null

	#常规移动只会落在该区域内标记为_will_move_to的Location上(工房区有多个同级点位)。
	#"挑哪个点位"与界面提示共用 GetMoveTargetLocation：落点规则只实现一处
	var target_location:BaseLocation = GetMoveTargetLocation.new().exec(area, ignore_limit)
	if target_location == null:
		EffectManager.push_message("【%s】的常规落点已满" % area._area_name, player_id)
		return null

	if !SetLocation.new().exec(target_location, player_id, true, ignore_limit):
		EffectManager.push_message("无法在【%s】落位" % area._area_name, player_id)
		return null

	#从魔术工房离开时应用玩家层折扣(葛木局外人等)，折扣不会让费用变成负数
	if origin_area == MapData.magic_workshop:
		var discount = (player_data["move_cost_discount_from_workshop"] as BaseNumber).number
		total_cost.number = max(0, total_cost.number - discount)

	return total_cost
