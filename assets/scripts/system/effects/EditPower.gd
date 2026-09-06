class_name EditPower
extends RefCounted

func exec(set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0), player_id:int = -1):

	var id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	var power = player_data["power"] as BaseNumber
	#就地改写玩家自己的数字，避免把效果自带的数字对象挂到玩家身上
	if set_num != null:
		power.set_num(set_num)
	power.add(vary_num)
