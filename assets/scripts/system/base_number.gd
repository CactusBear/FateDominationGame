extends Node
class_name BaseNumber


var num:int
var can_change:bool


func _init(_num:int, _can_change:bool = true):
	num = _num
	can_change = _can_change
