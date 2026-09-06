class_name GetCardAttributes
extends RefCounted

#取出卡牌的属性数组。攻击、技能、事件等各类卡牌都适用。
#card留空时取当前激活效果所属的卡牌
func exec(card:BaseCard = null):

	var target = card
	if target == null:
		target = GetEffSourceCard.new().exec()
	if target == null:
		return []
	return target._attributes
