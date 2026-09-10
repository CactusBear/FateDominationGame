class_name CardHasEffect
extends RefCounted

#通用查询：卡牌的_effects里是否带有指定名称的效果。
#与PlayerBuffsHaveEffect对应，后者查玩家身上的buff，本函数查卡牌自身。
#规则判定位置统一按效果名查询，不关心是哪张卡赋予的
func exec(effect_name:String, card:BaseCard) -> bool:

	if card == null:
		return false
	for eff in card._effects:
		if eff is BaseEffect and eff._name == effect_name:
			return true
	return false
