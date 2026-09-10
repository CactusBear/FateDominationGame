class_name EditMapAreaMoveCost
extends RefCounted

func exec(map_area:BaseMapArea, set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0)):

	if set_num != null:
		map_area._move_cost = set_num
	map_area._move_cost.add(vary_num)
