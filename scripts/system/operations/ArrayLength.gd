class_name ArrayLength
extends RefCounted

#通用数组/字典长度查询，供条件判断类func组合使用(如判断某数组是否为空)
func exec(arr) -> int:

	if arr == null:
		return 0
	return arr.size()
