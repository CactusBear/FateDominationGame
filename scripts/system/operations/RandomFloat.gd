class_name RandomFloat
extends RefCounted

const RuleRandom = preload("res://scripts/match/rule_random.gd")

func exec(range_start:float, range_end:float):

	return RuleRandom.float_in_range(range_start,range_end)


#功能函数(记得写发信号)
