extends BaseObject
class_name BaseBuff

var _buff_name:String
var _buff_img:String
var _buff_level:int
var _funcs:Array
var _is_active:bool


func _init(buff_name:String, buff_img:String):
	_buff_name = buff_name
	_buff_img = buff_img
	_buff_level = 1
	_funcs = []
	_is_active = true
	

func add_buff_func(_func:Callable, buff:Dictionary):
	_funcs.append(_func)
