class_name EditPower
extends RefCounted

func exec(set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0), player_id:int = -1):

	var id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	var power = player_data["power"] as BaseNumber
	var before = power.number
	#就地改写玩家自己的数字，避免把效果自带的数字对象挂到玩家身上
	if set_num != null:
		power.set_num(set_num)
	power.add(vary_num)
	#记下这次合计威力变化来自哪类对象（局势/事件/御主/令咒/他人的牌……），
	#供"排除局势与事件影响后的合计威力"这类查询按来源统计，不给玩家加字段
	PowerSources.record(id, "power", power.number - before)
