class_name ManageBuff
extends RefCounted

func exec(buff, player_id:int = -1, add_or_del:bool = true, context:Variant = null):
	context = RegisterObjectEffects.captured_context(context)
	if buff == null or not RegisterObjectEffects.source_is_current(context, buff):
		return false

	var resolved:Dictionary = RegisterObjectEffects.resolved_player_id(player_id, context)
	if not resolved.ok:
		return false
	var id:int = resolved.id
	var player_data:Dictionary = GameDataManager.find_player_data(id)
	if player_data.is_empty():
		return false
	if buff is BaseBuff and not RegisterObjectEffects.can_register_object(buff, id, context):
		return false
	var buffs:Array = player_data["buffs"] as Array

	if add_or_del:
		if buffs.has(buff):
			return false
		buffs.append(buff)
		if buff is BaseBuff:
			EffectManager.register_effects(buff._effects, id)
			TimePointChecker.dynamic_time_point([TimePoints.BUFF_START], id, null, context)
		return RegisterObjectEffects.source_is_current(context, buff) and is_same(player_data, GameDataManager.find_player_data(id)) and is_same(buffs, player_data.get("buffs"))

	if !buffs.has(buff):
		return false
	if buff is BaseBuff:
		for effect:BaseEffect in buff._effects:
			EffectManager.unregister_effect(effect)
		TimePointChecker.dynamic_time_point([TimePoints.BUFF_END], id, null, context)
	#同步时点返回后不再读/写新局同ID的容器；清理只触及保活的原buffs。
	if not RegisterObjectEffects.source_is_current(context, buff):
		return false
	buffs.erase(buff)
	return true
