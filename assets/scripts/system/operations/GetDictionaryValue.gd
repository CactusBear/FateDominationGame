class_name GetDictionaryValue
extends RefCounted

#从字典里按键取值。specials["ATTACKS"]、side["skills"]这类嵌套字典用这个，
#不要为每个键再写一个Get。键不存在返回null。
func exec(dict, key):

	if !(dict is Dictionary):
		return null
	if !dict.has(key):
		return null
	return dict[key]
