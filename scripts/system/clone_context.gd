class_name CloneContext
extends RefCounted

#复制机制不认识游戏类型；对象自己声明 clone_data。
func copy(value):
	if value == null:
		return null
	if value is Array:
		var result:Array = []
		for item in value:
			result.append(copy(item))
		return result
	if value is Dictionary:
		var result:Dictionary = {}
		for key in value:
			result[key] = copy(value[key])
		return result
	if value is Object:
		if value.has_method("clone_data"):
			return value.clone_data(self)
		return null
	return value


#参数里的游戏对象是引用，只有显式声明值语义的对象才复制。
func copy_value(value):
	if value is Array:
		var result:Array = []
		for item in value:
			result.append(copy_value(item))
		return result
	if value is Dictionary:
		var result:Dictionary = {}
		for key in value:
			result[key] = copy_value(value[key])
		return result
	if value is Object and value.has_method("clone_value"):
		return value.clone_value(self)
	return value


#只在新拥有者就绪后建立数字索引，绝不写回源对象。
func copy_effects(effects:Array, owner) -> Array:
	var result:Array = copy(effects)
	for effect in result:
		if effect != null:
			effect.from = owner
			effect.register_numbers_to_source()
	return result


func copy_specials(specials:Dictionary, owner) -> Dictionary:
	var result:Dictionary = copy(specials)
	for value in result.values():
		var items:Array = value if value is Array else [value]
		for item in items:
			if item is Object and item.has_method("set_from"):
				item.set_from(owner)
	return result
