extends BaseObject
class_name BaseBuff

var _buff_img:String
var _buff_level:BaseNumber
var _effects:Array#[BaseEffect]
var _is_active:bool
var _self_vars:Array


func _init(buff_name:String, buff_img:String):
	_name = buff_name
	_buff_img = buff_img
	_buff_level = BaseNumber.new(1)
	_effects = []
	_is_active = true
	super.add_object()
	

func add_buff_effect(_effect:BaseEffect):
	_effects.append(_effect)

	
func set_active(T_or_F:bool):
	_is_active = T_or_F

func set_buff_level(level:BaseNumber):
	_buff_level = level
