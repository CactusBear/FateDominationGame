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
	target.edit_cost(vary_num, set_num)
	return target._cost
