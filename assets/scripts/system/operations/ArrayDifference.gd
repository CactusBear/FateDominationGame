class_name ArrayDifference
extends RefCounted

#返回在arr里但不在subtract里的元素，不修改原数组。
func exec(arr:Array, subtract:Array) -> Array:

	var result:Array = []
	if arr == null:
		return result
	for item in arr:
		if subtract == null or !subtract.has(item):
			result.append(item)
	return result
