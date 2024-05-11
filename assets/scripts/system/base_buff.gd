extends BaseObject
class_name BaseBuff

var _buff_name:String
var _buff_img:String
var _buff_level:int
var _funcs:Array#[BaseFunc]
var _is_active:bool
var _self_vars:Array


func _init(buff_name:String, buff_img:String):
	_buff_name = buff_name
	_buff_img = buff_img
	_buff_level = 1
	_funcs = []
	_is_active = true
	super.add_object()
	

func add_buff_effect(_func:BaseFunc):
	_funcs.append(_func)

	
func set_active(T_or_F:bool):
	_is_active = T_or_F

func set_buff_level(level:int):
	_buff_level = level
