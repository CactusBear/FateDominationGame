class_name GetEffSourceCard
extends RefCounted

#取当前激活效果所属的卡牌。顺着from链往上找，用于"此卡"这类自指效果。
#攻击、技能、事件等各类卡牌都适用
func exec(effect:BaseEffect = null):

	var eff = effect
	if eff == null:
		eff = EffectManager.activating_eff
	if eff == null:
		return null
	var source = eff.from
	while source is BaseObject:
		if source is BaseCard:
			return source
		source = source.from
	return null
