class_name ForFunc
extends RefCounted

func exec(_func:BaseFunc, count:int):

	for i in range(count):
		_func._func.callv(_func._parameters)
