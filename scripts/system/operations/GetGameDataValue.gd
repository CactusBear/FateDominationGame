class_name GetGameDataValue
extends RefCounted

#读取GameData上的字段。loaded_masters、loaded_servants、skill_zone_magic_limit等都走这里，
#不为每个库各写一个Get。
func exec(key:String):

	if key == "":
		return null
	return GameData.get(key)
