class_name CloneObject
extends RefCounted

#JSON 原语只负责发起复制；字段与重置策略由对象自己的 clone_data 维护。
func exec(object):
	return CloneContext.new().copy(object)
