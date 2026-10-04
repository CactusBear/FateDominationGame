class_name MatchFunc
extends RefCounted

func exec(_var, cases:Array):
	var value = _var.number if _var is BaseNumber else _var
	for candidate in cases:
		var normalized = candidate.number if candidate is BaseNumber else candidate
		if value == normalized:
			return true
	return false
