class_name EditNumAndReturn
extends RefCounted

func exec(num:BaseNumber, add:BaseNumber = BaseNumber.new(0), times:BaseNumber = BaseNumber.new(1), is_round_up:bool = false):

	var result:BaseNumber
	if add.number != 0:
		num.add(add)
	if times.number != 1 and !is_round_up:
		num.multiply(times)
	elif times.number != 1 and is_round_up:
		var val:float = num.number * times.number
		var numi = int(num.number * times.number)
		if val != numi:
			numi += 1 
	result.number = num
	return result
