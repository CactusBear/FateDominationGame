class_name RegisterObjectEffects
extends RefCounted

#把对象上的_effects登记给一名玩家。换御主/从者、把技能放进技能区之外的来源，都只做登记这一件事。
func exec(object, player_id:int = -1):

	if object == null or !("_effects" in object):
		return
	var id = EffectManager.resolve_player_id(player_id)
	EffectManager.register_effects(object._effects, id)
