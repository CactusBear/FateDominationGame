class_name RemoveFromArray
extends RefCounted

#从数组里删掉一个元素。只删第一次匹配，不负责改威力或关牌。
func exec(item, arr:Array):

	if arr == null:
		return false
	var i = arr.find(item)
	if i == -1:
		return false
	arr.remove_at(i)
	return true
