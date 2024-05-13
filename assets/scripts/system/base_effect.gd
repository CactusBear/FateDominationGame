extends BaseObject
class_name BaseEffect

var _time_points:Array#[String]
var _funcs:Array#[BaseFunc]
var _is_passive:bool = false
var _self_vars:Array


func _init(effect_name:String, time_points:Array):
	_name = effect_name
	_time_points = time_points
	_funcs = []
	
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

func edit_num(index:int, add_num:int = 0, set_num = null):
	if set_num != null:
		numbers[index] = set_num
	numbers[index] += add_num

func add_func(_func:BaseFunc):
	_funcs.append(_func)

func del_func(_func:BaseFunc):
	var i = _funcs.find(_func)
	while i != -1:
		_funcs.remove_at(i)
		i = _funcs.find(_func)

func set_passive(T_or_F:bool):
	_is_passive = T_or_F
