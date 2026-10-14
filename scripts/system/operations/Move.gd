class_name Move
extends RefCounted

func exec(move_num:BaseNumber, player_id:int = -1, ignore_limit:bool = false, ignore_battle:bool = false, context:Variant = null):
	# 显式旧句柄不能被当前帧洗票；缺省只继承执行器已验的原函数帧。
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
	var magic:BaseNumber = player_data.get("magic") as BaseNumber
	if magic == null or move_num == null or not is_finite(move_num.number):
		return null
	#交战状态（与对手同处一处会发生战斗的战场）不能常规移动：判据在查询里，
	#不写死战区名。只判当前所站位置——规则允许常规移动"经过"已发生交战的战场。
	#ignore_engagement_for_move(如言峰监督者中立、以及"以令咒移动")让玩家无视交战状态移动，
	#不需要调用方额外传ignore_battle
	var ignore_engagement = player_data["ignore_engagement_for_move"] as bool
	if !ignore_battle and !ignore_engagement and IsEngaged.new().exec(player_id):
		EffectManager.push_message("处于交战状态，无法移动", player_id)
		return
	if not _origin_is_current(origin, magic, player_data.get("location")):
		return null
	var cost = MoveLocation.new().exec(move_num, player_id, ignore_limit, context)
	# MoveLocation 仍真落位；这里只拒绝失效尾部，不伪装成可回滚事务。
	if cost == null:
		return null
	var moved_location:BaseLocation = player_data.get("location") as BaseLocation
	# LEAVE/ENTER 可同步替换原 magic；有效 context 不授权同 ID 的新资源对象。
	if not _origin_is_current(origin, magic, moved_location):
		return false
	# 零费用/免疫沿用原空结果与无付款事实，不把 null 包装成支付完成。
	if player_data.get("is_magic_immune", false) or cost.number <= 0:
		return null
	# 最终支付原语显式消费创建时捕获的来源及两个 identity；不借当前帧重签。
	var paid:bool = PayMagic.new().exec(BaseNumber.new(max(0, cost.number)), player_id, "move", moved_location, true, false, context, player_data, magic)
	# 魔力扣款监听可同步换局/换对象，不能把旧支付返回当作新局完成。
	if not _origin_is_current(origin, magic, moved_location):
		return false
	return paid


# 沿用位置消费者的原图判据，额外认证本次支付锁定的原魔力对象。
# 不签新 context、不刷新快照、不读取执行器私有状态。
func _origin_is_current(origin:Dictionary, magic:BaseNumber, expected_location:BaseLocation) -> bool:
	return SetLocation.location_origin_is_current(origin, expected_location) \
		and is_same(origin.player.get("magic"), magic)
