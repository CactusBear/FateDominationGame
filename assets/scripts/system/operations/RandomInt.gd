class_name RandomInt
extends RefCounted

#取区间内的随机整数（含两端）。
#参数兼容 int/float/BaseNumber：效果里的边界多是上一步算出来的BaseNumber，
#每次都要求调用方先拆包太啰嗦。GetCardByIndexFrArr 同样接受 BaseNumber
func exec(range_start, range_end):

	return randi_range(int(_unwrap(range_start)), int(_unwrap(range_end)))


func _unwrap(value):
	if value is BaseNumber:
		return value.number
	return value
