class_name TransferObjectEffects
extends RefCounted

#把对象上本局的_effects整体改归另一名玩家（夺取/交换类效果）。只改效果归属，不搬牌。
#整批先验，任一条不合格就一条都不改并返回 false。
func exec(object, player_id:int = -1, context:Variant = null) -> bool:
	context = RegisterObjectEffects.captured_context(context)
	if not RegisterObjectEffects.source_is_current(context, object):
		return false
	var resolved:Dictionary = RegisterObjectEffects.resolved_player_id(player_id, context)
	if not resolved.ok:
		return false
	var id:int = resolved.id
	if not ("_effects" in object) or not object._effects is Array:
		return false
	for item in object._effects:
		if item is BaseEffect and (not RegisterObjectEffects.source_is_current(context, item) or not EffectManager.can_transfer_effect(item, id)):
			return false
	for item in object._effects:
		if item is BaseEffect and not EffectManager.transfer_effect(item, id):
			return false
	return true
