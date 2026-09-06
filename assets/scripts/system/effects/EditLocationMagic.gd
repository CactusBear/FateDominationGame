class_name EditLocationMagic
extends RefCounted

func exec(location:BaseLocation, set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0)):

	if set_num != null:
		location._magic = set_num
	location._magic.add(vary_num)
