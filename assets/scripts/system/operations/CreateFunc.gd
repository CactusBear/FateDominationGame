class_name CreateFunc
extends RefCounted

func exec(callable:Callable, parameters:Array):

	var _func = BaseFunc.new(callable, parameters)
	return _func
