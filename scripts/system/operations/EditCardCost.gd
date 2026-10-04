class_name EditCardCost
extends RefCounted

#改手牌的魔力消耗。与EditCardPower分开：改费用不碰合计威力。
#card留空时取当前激活效果所属的卡。
func exec(vary_num:BaseNumber = BaseNumber.new(0), set_num:BaseNumber = null, card:BaseHandCard = null):

	var target = card
	if target == null:
		var source = GetEffSourceCard.new().exec()
		if source is BaseHandCard:
			target = source
	if target == null:
		return
	var old_cost: int = (target._cost as BaseNumber).number
	target.edit_cost(vary_num, set_num)
	var new_cost: int = (target._cost as BaseNumber).number
	if target.has_method("record_modification"):
		target.record_modification("cost", "魔力消耗 %d → %d" % [old_cost, new_cost])
	return target._cost
