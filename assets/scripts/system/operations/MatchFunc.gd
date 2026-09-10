class_name MatchFunc
extends RefCounted

func exec(_var, cases:Array):

	if cases.has(_var):
		return true
	else:
		return false
