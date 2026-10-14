class_name EditDataNumber
extends RefCounted

#通用BaseNumber字段编辑器：player_data里所有BaseNumber类型的字段(play_limit、
#total_power_bonus、attack_cost_discount、move_cost_discount_from_workshop、
#command_spell_count等)都可以用同一个operation改写，不需要为每个字段各写一个
#Set/EditXxx.gd。用法与EditMagic/EditScore/EditLives一致：set_num覆盖，vary_num叠加
func exec(key:String, set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0), player_id:int = -1, min_value = null, max_value = null):

	# 只承接已验证函数帧的原来源；无帧或旧帧须在动态目标/字段首读前拒绝。
	var execution:Dictionary = EffectManager.execution_context()
	if not execution.get("ok", false):
		return
	player_id = EffectManager.resolve_player_id(player_id)
	#执行时只查询当前成员；未知主体或错误字段保持原有void/no-op返回。
	var player_data:Dictionary = GameDataManager.find_player_data(player_id)
	if player_data.is_empty():
		return
	if !(player_data.get(key) is BaseNumber):
		return
	var num = player_data[key] as BaseNumber
	var before = num.number
	if set_num != null:
		num.set_num(set_num)
	num.add(vary_num)
	if min_value != null:
		var low = min_value.number if min_value is BaseNumber else min_value
		if num.number < low:
			num.set_num(BaseNumber.new(low))
	if max_value != null:
		var high = max_value.number if max_value is BaseNumber else max_value
		if num.number > high:
			num.set_num(BaseNumber.new(high))
	#合计威力加成与出牌威力一样按来源记账（其它字段不属于合计威力，不记）
	if key == "total_power_bonus":
		PowerSources.record(player_id, key, num.number - before)
	notify_changed(player_id, key, before, num.number, execution.context)

#数值变化的事实广播：只记「哪个字段从几变成几」，不认识任何具体规则（「令咒第一次清零」等由卡效据此判断）。
#其它直接改玩家数值字段的入口（如令咒支付）也调这里，保证同一口径。
static func notify_changed(player_id:int, key:String, before:int, after:int, context:Variant = null) -> void:
	if before == after:
		return
	GameLog.record("player_number_changed", player_id, -1, "", null, ["player_number_changed"], {"key": key, "before": before, "after": after})
	TimePointChecker.dynamic_time_point([TimePoints.PLAYER_NUMBER_CHANGED], player_id, null, context)
