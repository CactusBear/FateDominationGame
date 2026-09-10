class_name GetExtremeByProperty
extends RefCounted

#从数组里取出某属性最大或最小的对象。属性值可以是BaseNumber或裸数字。
#只返回对象，不改数值；并列时返回先遇到的那个。
func exec(objects:Array, property:String, take_max:bool = true):

	if objects == null or property == "":
		return null
	var getter = GetProperty.new()
	var best = null
	var best_value = null
	for object in objects:
		var raw = getter.exec(object, property)
		var value = raw.number if raw is BaseNumber else raw
		if value == null:
			continue
		if best == null:
			best = object
			best_value = value
			continue
		if take_max and value > best_value:
			best = object
			best_value = value
		elif !take_max and value < best_value:
			best = object
			best_value = value
	return best
