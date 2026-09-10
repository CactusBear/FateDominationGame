class_name ManageBuff
extends RefCounted

func exec(buff, player_id:int = -1, add_or_del:bool = true):
	if buff == null:
		return false

	var id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	var buffs:Array = player_data["buffs"] as Array

	if add_or_del:
		if buffs.has(buff):
			return false
		buffs.append(buff)
		if buff is BaseBuff:
			EffectManager.register_effects(buff._effects, id)
			TimePointChecker.dynamic_time_point([TimePoints.BUFF_START], id)
		return true

	if !buffs.has(buff):
		return false
	if buff is BaseBuff:
		for effect:BaseEffect in buff._effects:
			EffectManager.unregister_effect(effect)
		TimePointChecker.dynamic_time_point([TimePoints.BUFF_END], id)
	buffs.erase(buff)
	return true
