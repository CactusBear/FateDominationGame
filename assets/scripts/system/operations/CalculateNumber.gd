class_name CalculateNumber
extends RefCounted

#对两个数字做一次运算并返回新的BaseNumber，不改写传入对象。
#EditMagic/EditNumAndReturn会就地改数，不能拿来算"16-回合*2"这类派生值。
#op由调用方传入，不写死某种角色公式。
func exec(a, op:String, b = 0) -> BaseNumber:

	var left = _unwrap(a)
	var right = _unwrap(b)
	var result = 0
	match op:
		"+", "add":
			result = left + right
		"-", "sub":
			result = left - right
		"*", "mul":
			result = left * right
		"/", "div":
			if right == 0:
				return BaseNumber.new(0)
			result = left / right
		"%", "mod":
			if right == 0:
				return BaseNumber.new(0)
			result = int(left) % int(right)
		"min":
			result = min(left, right)
		"max":
			result = max(left, right)
		_:
			return BaseNumber.new(0)
	if typeof(left) == TYPE_INT and typeof(right) == TYPE_INT and op != "/" and op != "div":
		result = int(result)
	return BaseNumber.new(result)


func _unwrap(value):
	if value is BaseNumber:
		return value.number
	return value
