extends Node
class_name BaseFunc

var _func:Callable
var _parameters:Array
var _var_index:int = -1
var _func_used:bool = false
var _if_affect_power:bool = false
var _priority:int
var _func_target_player:int
var _func_target_property

func _init(f:Callable, ps:Array, var_index:int = -1):
	_func = f
	_parameters = ps
	_var_index = var_index
