class_name IsNull
extends RefCounted

#判断值是否为null。IfFunc只能比相等，缺值分支需要这个查询。
func exec(value) -> bool:

	return value == null
