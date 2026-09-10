class_name IsInArray
extends RefCounted

#通用"是否包含"判断，兼容BaseNumber按数值比较
func exec(item, arr:Array) -> bool:

	for element in arr:
		if element is BaseNumber and item is BaseNumber:
			if element.number == item.number:
				return true
		elif element == item:
			return true
	return false
