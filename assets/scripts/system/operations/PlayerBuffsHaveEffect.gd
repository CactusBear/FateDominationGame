class_name PlayerBuffsHaveEffect
extends RefCounted

#通用查询：玩家身上是否有任意激活的buff，其_effects里带有指定名称的效果。
#规则判定位置(出牌、战力结算等)统一调用本函数，不关心具体是哪种buff类型；
#效果本身(如CannotPlayCardsEffect)的含义由声明它的buff和查询它的规则位置共同约定
func exec(effect_name:String, player_id:int = -1) -> bool:

	var id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	for buff in player_data["buffs"]:
		if !(buff is BaseBuff):
			continue
		if !buff._is_active:
			continue
		for eff in buff._effects:
			if eff is BaseEffect and eff._name == effect_name:
				return true
	return false
