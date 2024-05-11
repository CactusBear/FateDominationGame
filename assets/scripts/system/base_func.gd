extends Node
class_name BaseFunc

var _func:Callable
var _parameters:Array
var _var_index:int = -1

func _init(f:Callable, ps:Array, var_index:int = -1):
	_func = f
	_parameters = ps
	_var_index = var_index
