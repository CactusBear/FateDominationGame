class_name EditCardAttributes
extends RefCounted

#增删或替换卡牌的属性。card留空时取当前激活效果所属的卡牌
func exec(add_attributes:Array = [], del_attributes:Array = [], set_attributes:Array = [""], card:BaseCard = null):

	var target = card
	if target == null:
		target = GetEffSourceCard.new().exec()
	if target == null:
		return
	target.edit_attribute(add_attributes, del_attributes, set_attributes)
	return target._attributes
