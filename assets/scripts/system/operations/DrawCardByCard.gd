class_name DrawCardByCard
extends RefCounted

func exec(card:BaseCard, from:Array, to:Array, to_index:BaseNumber = BaseNumber.new(-1)):

	var i = from.find(card)
	if i == -1:
		return
	from.pop_at(i)
	if to_index.number == -1:
		to.append(card)
		return
	if !(to_index.number is int):
		#show("index只能为整数")
		return
	if to.size() < to_index.number:
		#show("超出数组范围")
		return
	to.insert(to_index.number, card)
