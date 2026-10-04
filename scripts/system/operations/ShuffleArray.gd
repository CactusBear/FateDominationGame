class_name ShuffleArray
extends RefCounted

#就地洗乱传入的数组，不另建新数组。算法不绑定牌库或弃牌堆，任何数组都能用。
func exec(arr:Array):

	if arr == null or arr.size() <= 1:
		return arr
	for i in range(arr.size() - 1, 0, -1):
		var j:int = randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
	return arr
