class_name ForeachFunc
extends RefCounted

func exec(_func:BaseFunc, _var, parameter_index:int = 0):

	for i in _var:
		_func._parameters[parameter_index] = i
		_func._func.callv(_func._parameters)

#获取数值
