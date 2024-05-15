extends BaseObject
class_name BaseEffect

var _time_points:Array#[String]
var _funcs:Array#[BaseFunc]
var _is_pure_passive:bool = false
var _need_activate:bool = true
var _is_residue:bool = false
var _self_vars:Array
var _priority:int
var _using_numbers:Array


func _init(effect_name:String, time_points:Array, priority:int = -1, is_pure_passive:bool = false, is_residue:bool = false):
	_name = effect_name
	_time_points = time_points
	_funcs = []
	_priority = priority
	_is_pure_passive = is_pure_passive
	_is_residue = is_residue
	
	super.add_object()
	var _from = from as BaseObject
	_from.numbers.append_array(numbers)
	GameData.effects.append(self)



func edit_effect_name(effect_name:String):
	_name = effect_name
	
func edit_time_points(add_time_points:Array = [], del_time_points:Array = [], set_time_points:Array = [""]):
	if set_time_points != [""]:
		_time_points = set_time_points
	_time_points.append_array(add_time_points)
	for del in del_time_points:
		var i = _time_points.find(del)
		if i != -1:
			_time_points.pop_at(i)

func edit_funcs(add_funcs:Array = [], set_funcs:Array = []):
	if set_funcs != []:
		_funcs = set_funcs
	_funcs.append_array(add_funcs)


func add_func(_func:BaseFunc):
	_funcs.append(_func)

func del_func(_func:BaseFunc):
	var i = _funcs.find(_func)
	while i != -1:
		_funcs.remove_at(i)
		i = _funcs.find(_func)

func set_passive(T_or_F:bool):
	_is_pure_passive = T_or_F

func set_need_activate(T_or_F:bool):
	_need_activate = T_or_F

func set_is_residue(T_or_F:bool):
	_is_residue = T_or_F
