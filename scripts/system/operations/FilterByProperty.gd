class_name FilterByProperty
extends RefCounted

#从数组里筛出属性等于给定值的对象。暗置牌、激活中的牌、按_name取值都可以走这里。
#ForeachFunc不能收集过滤结果，所以需要这个查询。
func exec(objects:Array, property:String, value) -> Array:

	var got:Array = []
	if objects == null or property == "":
		return got
	var getter = GetProperty.new()
	for object in objects:
		if getter.exec(object, property) == value:
			got.append(object)
	return got
