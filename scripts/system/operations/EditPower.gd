class_name EditPower
extends RefCounted

#可选尾参只透传创建方原来源；旧三参调用仍由PowerSources继承已验函数帧。
func exec(set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0), player_id:int = -1, context:Variant = null):

	var id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.find_player_data(id)
	#未知主体不改威力，也不登记来源；来源标签不能代替成员资格。
	if player_data.is_empty():
		return
	var power = player_data["power"] as BaseNumber
	var before = power.number
	#就地改写玩家自己的数字，避免把效果自带的数字对象挂到玩家身上
	if set_num != null:
		power.set_num(set_num)
	power.add(vary_num)
	#记下这次合计威力变化来自哪类对象（局势/事件/御主/令咒/他人的牌……），
	#供"排除局势与事件影响后的合计威力"这类查询按来源统计，不给玩家加字段
	PowerSources.record(id, "power", power.number - before, null, context)
