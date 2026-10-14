class_name DeployRules
extends RefCounted

const operation_router = preload("res://scripts/system/operation_router.gd")

#前哨阶段部署的规则判定。与 PlayRules / RegularPlay 同类：只做规则，不碰界面节点。
#这些判定原先只存在于 tactical_board_ui.gd 里，导致任何不经界面的推进
#（headless 验证、AI 推演、回放）全员都不部署——没人在版图上就没有战斗、
#没有战果，七人同分，高潮日按"并列都不淘汰"一个人都淘汰不掉。
#所以判定必须住在规则层，界面只是调用方之一。


#某战区当前可供常规部署的席位。
#"能不能被常规部署选中"由席位自己声明（_can_deploy），
#与"容量"（_pl_num_limit）和"能不能常规移动进入"（_will_move_to）是三件不同的事
static func open_locations(area:BaseMapArea) -> Array:
	var open:Array = []
	if area == null or !area._can_deploy:
		return open
	for loc:BaseLocation in area._locations:
		#额外席位：容量可能不限，但那是给效果放置用的，不参与常规部署
		if !loc._can_deploy:
			continue
		if loc._pl_num_limit != -1 and loc._players.size() >= loc._pl_num_limit:
			continue
		open.append(loc)
	return open


#席位的收益分：充能席给魔力、地利席给地利，都按席位印刷的数字算。
#不写死"哪一类席位更优先"——数字大的就是该先被占的那一档
static func slot_score(loc:BaseLocation) -> int:
	if loc == null:
		return -1
	return int((loc._magic as BaseNumber).number) + int((loc._benefit as BaseNumber).number)


#从可用席位里挑一个：先把收益最高的那一档占满才能用下一档；
#同一档内按席位顺序依次取（同档之间没有先后，但不能跳着占，否则看起来像跳过了席位）
static func pick_location(area:BaseMapArea) -> BaseLocation:
	var open:Array = open_locations(area)
	if open.is_empty():
		return null
	var best:int = -1
	for loc in open:
		var s:int = slot_score(loc)
		if s > best:
			best = s
	for loc in open:
		if slot_score(loc) == best:
			return loc
	return null


#部署即刻获得的收益（充能席给魔力）。数字读席位自己的声明，不写死战区名与数值；
#地利不在部署时给，战力结算时由 GetEffectiveLocationBenefit 读取。
#没有真正落位（席位满/被拒）就不给——落位成功才会把玩家记进席位的 _players。
#返回实际给出的魔力数
# 旧 int ABI 只报告本次实际已完成的正收益，不再把印刷数字当到账回执。
static func apply_benefit(loc:BaseLocation, player_id:int, context:Variant = null) -> int:
	var result:Dictionary = apply_benefit_result(loc, player_id, context)
	return int(result.actual_delta) if result.status == "COMPLETED" and result.actual_delta > 0 else 0


# 独立收益入口：控制结果与实际 delta 分离，免疫/取消/封顶归零不是拒绝。
static func apply_benefit_result(loc:BaseLocation, player_id:int, context:Variant = null) -> Dictionary:
	context = CanGainMagic.captured_context(context)
	if not CanGainMagic.source_is_current(context):
		return {"status":"REJECTED", "actual_delta":0.0, "reason":"source_rejected", "wrote":false}
	if not GameData.player_data_library.has(player_id) or loc == null or not loc._players.has(player_id):
		return {"status":"REJECTED", "actual_delta":0.0, "reason":"not_placed", "wrote":false}
	var gain:BaseNumber = loc._magic as BaseNumber
	if gain == null or gain.number == 0:
		return {"status":"COMPLETED", "actual_delta":0.0, "reason":"zero_gain", "wrote":false}
	# 来源名来自战区数据，资格来自原 context，两者不能互相代替。
	var area := loc.get_from() as BaseMapArea
	var source:String = area._magic_source if area != null else ""
	var allowed:Variant = CanGainMagic.new().exec(source, player_id, context)
	if allowed == null:
		return {"status":"REJECTED", "actual_delta":0.0, "reason":"query_source_rejected", "wrote":false}
	if allowed == false:
		return {"status":"COMPLETED", "actual_delta":0.0, "reason":"gain_disabled", "wrote":false}
	# 仍是同一个 EditMagic 职责/Script，只选择显式完整结果入口；不新增卡牌 operation。
	return EditMagic.new().exec_result(null, BaseNumber.new(gain.number), player_id, "", null, context)


#部署到某战区的完整动作：挑席位 → 落位 → 结算部署收益。
#落位与收益是两个独立原语（Deploy / apply_benefit），这里只负责按规则把它们串起来，
#让界面、AI、效果推演共用同一条路径。返回真正落位的席位，没能部署时返回 null
static func deploy_to_area(area:BaseMapArea, player_id:int, context:Variant = null) -> BaseLocation:
	var result:Dictionary = deploy_to_area_result(area, player_id, context)
	return result.location if result.status == "COMPLETED" else null


# 位置已经提交而收益失败/待续时保留位置，只在补充结果中报告部分完成。
# 旧位置 ABI 不能表达这种边界，返回 null 不意味着已落位会被回滚。
static func deploy_to_area_result(area:BaseMapArea, player_id:int, context:Variant = null) -> Dictionary:
	context = CanGainMagic.captured_context(context)
	if not CanGainMagic.source_is_current(context):
		return {"status":"REJECTED", "placed":false, "location":null, "benefit":{}}
	var loc:BaseLocation = pick_location(area)
	if loc == null:
		return {"status":"REJECTED", "placed":false, "location":null, "benefit":{}}
	if operation_router.exec_registered("deploy", [loc, player_id, false, context], context) != true:
		return {"status":"REJECTED", "placed":false, "location":null, "benefit":{}}
	var benefit:Dictionary = apply_benefit_result(loc, player_id, context)
	var status:String = "COMPLETED" if benefit.status in ["COMPLETED", "CANCELLED"] else ("PENDING" if benefit.status == "PENDING" else "PARTIAL")
	return {"status":status, "placed":true, "location":loc, "benefit":benefit}


#该玩家此刻可以常规部署的战区列表（有空席位的那些）。
#AI 与界面的可点提示共用它，避免两边各写一套"哪里能部署"
static func deployable_areas() -> Array:
	var areas:Array = []
	for area:BaseMapArea in MapData.areas:
		if !open_locations(area).is_empty():
			areas.append(area)
	return areas
