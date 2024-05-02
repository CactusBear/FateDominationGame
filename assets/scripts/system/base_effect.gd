extends BaseObject
class_name BaseEffect

var _effect_name:String
var _time_points:Array[String]
var _funcs:Array[Callable]



func _init(effect_name:String, time_points:Array[String], funcs:Array[Callable]):
	_effect_name = effect_name
	_time_points = time_points
	_funcs = funcs




