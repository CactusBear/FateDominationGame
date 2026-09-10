class_name SetProperty
extends RefCounted

#写入任意对象上的属性。与GetProperty成对，不限定卡牌/从者/buff。
#对象或属性不存在时不写，避免把规则写进这个operation。
func exec(object, property:String, value):

	if object == null or property == "":
		return null
	if !_has_property(object, property):
		return null
	object.set(property, value)
	return object.get(property)


func _has_property(object, property:String) -> bool:
	if object == null:
		return false
	for info in object.get_property_list():
		if info.get("name", "") == property:
			return true
	return false
