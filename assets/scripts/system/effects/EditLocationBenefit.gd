class_name EditLocationBenefit
extends RefCounted

func exec(location:BaseLocation, set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0)):

	if set_num != null:
		location._benefit = set_num
	location._benefit.add(vary_num)
