class_name IfFunc
extends RefCounted

#比较两个值是否相等，返回bool，供后续func的condition使用
#BaseNumber按数值比较而非按对象引用比较
func exec(_var1, _var2 = true):

	return _unwrap(_var1) == _unwrap(_var2)


func _unwrap(_var):
	if _var is BaseNumber:
		return _var.number
	return _var
