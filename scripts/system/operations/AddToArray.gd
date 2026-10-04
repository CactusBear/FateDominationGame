class_name AddToArray
extends RefCounted

#把元素放进数组。index为-1时追加。不做去重、不登记效果，那些由调用方组合。
func exec(item, arr:Array, index = -1):

	if arr == null:
		return arr
	var at = index.number if index is BaseNumber else int(index)
	if at < 0 or at >= arr.size():
		arr.append(item)
	else:
		arr.insert(at, item)
	return arr
