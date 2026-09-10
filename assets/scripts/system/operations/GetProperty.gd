class_name GetProperty
extends RefCounted

#读取任意对象上的属性。JSON无法直接写obj._servant_class，统一走这个入口。
#属性名由调用方传入，不写死任何字段；对象没有该属性时返回null。
func exec(object, property:String):

	if object == null or property == "":
		return null
	if object is Object and object.get(property) == null and !_has_property(object, property):
		return null
	return object.get(property)


func _has_property(object, property:String) -> bool:
	if object == null:
		return false
	for info in object.get_property_list():
		if info.get("name", "") == property:
			return true
	return false
