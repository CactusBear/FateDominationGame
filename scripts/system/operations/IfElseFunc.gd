class_name IfElseFunc
extends RefCounted

#按条件在两个已求值的结果里二选一。IfFunc只返回bool，不能把后续func接到某一分支的返回值上。
#条件规则与效果condition一致：null/0/false为假，BaseNumber按数值是否非0判断。
func exec(condition, then_value, else_value = null):

	if _is_true(condition):
		return then_value
	return else_value


func _is_true(value) -> bool:
	if value == null:
		return false
	if value is BaseNumber:
		return value.number != 0
	return bool(value)
