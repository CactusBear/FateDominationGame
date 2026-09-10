class_name MergeArrays
extends RefCounted

#把多个数组合并成新数组，不改原数组。手牌+牌库+弃牌一起筛选时用，避免为"三区合并"写专用操作。
func exec(a:Array = [], b:Array = [], c:Array = [], d:Array = []) -> Array:

	var result:Array = []
	if a != null:
		result.append_array(a)
	if b != null:
		result.append_array(b)
	if c != null:
		result.append_array(c)
	if d != null:
		result.append_array(d)
	return result
