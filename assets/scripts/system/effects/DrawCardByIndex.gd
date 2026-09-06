class_name DrawCardByIndex
extends RefCounted

func exec(from:Array, to:Array, from_index:BaseNumber = BaseNumber.new(0), to_index:BaseNumber = BaseNumber.new(-1)):

	if from.size() <= from_index.number:
		#show("超出数组范围")
		return
	var card = from[from_index.number]
	if card is BaseCard:
		from.pop_at(0)
		if to_index.number == -1:
			to.append(card)
		if !(to_index.number is int):
			#show("index只能为整数")
			return
		if to.size() < to_index.number:
			#show("超出数组范围")
			return
		to.insert(to_index.number, card)
