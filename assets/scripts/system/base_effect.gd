extends BaseObject
class_name BaseEffect

var _effect_name:String
var _time_points:Array[String]
var _funcs:Array[BaseFunc]
var _is_passive:bool = false


func _init(effect_name:String, time_points:Array[String], funcs:Array[BaseFunc]):
	_effect_name = effect_name
	_time_points = time_points
	_funcs = funcs



func edit_effect_name(effect_name:String):
	_effect_name = effect_name
	
func edit_time_points(add_time_points:Array[String] = [], del_time_points:Array[String] = [], set_time_points:Array[String] = [""]):
	if set_time_points != [""]:
		_time_points = set_time_points
	_time_points.append_array(add_time_points)
	for del in del_time_points:
		var i = _time_points.find(del)
		if i != -1:
			_time_points.pop_at(i)

func edit_funcs(set_funcs:Array[BaseFunc] = [EffectLib.do_nothing()], add_funcs:Array[BaseFunc] = []):
	if set_funcs != [EffectLib.do_nothing()]:
		_funcs = set_funcs
	_funcs.append_array(add_funcs)

func set_passive(T_or_F:bool):
	_is_passive = T_or_F
