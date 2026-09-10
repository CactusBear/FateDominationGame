class_name GetObjectsByNameFrArr
extends RefCounted

#按_name从任意对象数组取值。GetCardsByNameFrArr只接受BaseCard，御主/从者/buff要用这个。
func exec(object_name:String, objects:Array) -> Array:

	var got:Array = []
	if objects == null:
		return got
	for object in objects:
		if object is BaseObject and object._name == object_name:
			got.append(object)
	return got
