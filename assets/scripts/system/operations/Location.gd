class_name Location
extends RefCounted

func exec(magic:BaseNumber = BaseNumber.new(0), benefit:BaseNumber = BaseNumber.new(0), pl_num_limit:int = 1, will_move_to:bool = false):

	var location = BaseLocation.new(magic,benefit,pl_num_limit,will_move_to)
	return location
