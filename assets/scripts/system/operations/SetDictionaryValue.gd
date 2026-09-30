class_name SetDictionaryValue
extends RefCounted

#把一个值写进字典的某个键（已有就覆盖）。与 get_dictionary_value 成对：
#对象命名计数（_counters）、玩家按名字的独立牌区（extra_zones）、秘密选择的结果表都用它写，
#不为每种字典各写一个 Set。返回写入后的值
func exec(dict, key, value):

	if !(dict is Dictionary) or key == null:
		return null
	dict[key] = value
	return value
