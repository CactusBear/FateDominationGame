class_name WhileFunc
extends RefCounted

func exec(_func:BaseFunc, condition:bool):

	while condition:
		_func._func.callv(_func._parameters)
