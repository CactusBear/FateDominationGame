class_name HasAttribute
extends RefCounted

#判断卡牌是否具有所给属性中的任意一个，返回bool供后续func的condition使用。
#attributes留空时视为符合；card留空时取当前激活效果所属的卡牌
func exec(attributes:Array, card:BaseCard = null):

	var target = card
	if target == null:
		target = GetEffSourceCard.new().exec()
	if target == null:
		return false
	if attributes.is_empty():
		return true
	for attribute in attributes:
		if target.has_attribute(attribute):
			return true
	return false
