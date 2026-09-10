class_name EditNumAndReturn
extends RefCounted

func exec(num:BaseNumber, add:BaseNumber = BaseNumber.new(0), times:BaseNumber = BaseNumber.new(1), is_round_up:bool = false):

	if num == null:
		return null
	if add != null and add.number != 0:
		num.add(add)
	if times != null and times.number != 1:
		if is_round_up:
			var val:float = float(num.number) * float(times.number)
			var numi:int = int(val)
			if val != float(numi):
				numi += 1
			num.set_num(BaseNumber.new(numi))
		else:
			num.multiply(times)
	return num
