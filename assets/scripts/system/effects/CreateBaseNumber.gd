class_name CreateBaseNumber
extends RefCounted

func exec(number, can_change:bool = false):

	var n
	var num
	if number is int:
		n = number
		num = BaseNumber.new(n, can_change)
		num.is_float = false
	elif number is float:
		n = number
		num = BaseNumber.new(n, can_change)
		num.is_float = true
	return num
