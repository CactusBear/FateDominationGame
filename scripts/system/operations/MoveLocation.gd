class_name MoveLocation
extends RefCounted

#沿地图链计算落点与费用，实际调用 SetLocation 落位；不扣魔力（扣款由 Move 负责）。
func exec(move_num:BaseNumber, player_id:int = -1, ignore_limit:bool = false, context:Variant = null):
	context = RegisterObjectEffects.captured_context(context)
	if not RegisterObjectEffects.source_is_current(context):
		return null
	var resolved:Dictionary = RegisterObjectEffects.resolved_player_id(player_id, context)
	if not resolved.ok:
		return null
	player_id = resolved.id
	var origin:Dictionary = SetLocation.capture_location_origin(player_id, context)
	if origin.is_empty():
		return null
	var player_data:Dictionary = origin.player
	var location:BaseLocation = player_data["location"]
	if location != null and not SetLocation.current_map_location(location):
		return null
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
	#每经过一段的费用减免（玩家级，默认 0），每段单独减、不减成负数
	var step_discount:int = step_cost_discount(player_data)
	if move_num.number > 0:
		for n in move_num.number:
			if area._linked_map_area == null:
				return null
			total_cost.add(BaseNumber.new(maxi(0, int(area._move_cost.number) - step_discount)))
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
	#战区锁只看出发地与落点：被锁战区不能离开也不能进入，但可以途经。
	#在算费与落位之前拦下，拒绝时不扣任何资源；判据与 SetLocation 落位共用一处
	var locked:BaseMapArea = SetLocation.locked_area_for_move(player_id, area)
	if locked != null:
		EffectManager.push_message(("无法离开【%s】" if locked == origin_area else "无法移动至【%s】") % locked._area_name, player_id)
		return null

	#常规移动只会落在该区域内标记为_will_move_to的Location上(工房区有多个同级点位)。
	#"挑哪个点位"与界面提示共用 GetMoveTargetLocation：落点规则只实现一处
	var target_location:BaseLocation = GetMoveTargetLocation.new().exec(area, ignore_limit)
	if target_location == null:
		EffectManager.push_message("【%s】的常规落点已满" % area._area_name, player_id)
		return null

	#先确定折扣后的费用并校验余额，拒绝时不能先落位再部分扣费。
	if origin_area == MapData.magic_workshop:
		var discount = (player_data["move_cost_discount_from_workshop"] as BaseNumber).number
		total_cost.number = max(0, total_cost.number - discount)
	if not player_data.get("is_magic_immune", false) and player_data.magic.number < total_cost.number:
		EffectManager.push_message("魔力不足，无法移动", player_id)
		return null
	if not SetLocation.location_origin_is_current(origin, location):
		return null
	var placed:bool = SetLocation.new().exec(target_location, player_id, true, ignore_limit, true, context)
	#SetLocation 可同步派发效果；旧链不能把拒绝当报价成功，也不向新局写拒绝消息。
	if not SetLocation.location_origin_is_current(origin, target_location if placed else location):
		return null
	if not placed:
		EffectManager.push_message("无法在【%s】落位" % area._area_name, player_id)
		return null

	return total_cost


#玩家每段移动费用的减免数。界面估算与真实移动共用这一处读法
static func step_cost_discount(player_data:Dictionary) -> int:
	var d = player_data.get("move_cost_discount_per_step")
	return int(d.number) if d is BaseNumber else 0
