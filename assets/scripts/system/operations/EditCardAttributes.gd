class_name EditCardAttributes
extends RefCounted

#增删或替换卡牌的属性。card留空时取当前激活效果所属的卡牌
func exec(add_attributes:Array = [], del_attributes:Array = [], set_attributes:Array = [""], card:BaseCard = null):

	var target = card
	if target == null:
		target = GetEffSourceCard.new().exec()
	if target == null:
		return
	var attrs_before: Array = target._attributes.duplicate()
	target.edit_attribute(add_attributes, del_attributes, set_attributes)
	if target.has_method("record_modification"):
		target.record_modification("attribute", "属性 %s → %s" % [
			"、".join(attrs_before) if not attrs_before.is_empty() else "无",
			"、".join(target._attributes) if not target._attributes.is_empty() else "无"])
	return target._attributes
