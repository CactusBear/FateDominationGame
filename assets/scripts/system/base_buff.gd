extends BaseObject
class_name BaseBuff

func clone_data(context):
	var cloned = BaseBuff.new(_name, _buff_img)
	copy_clone_fields(cloned, context)
	cloned._is_active = _is_active
	cloned._related_effect_names = _related_effect_names.duplicate()
	cloned._buff_level = context.copy(_buff_level)
	cloned._effects = context.copy_effects(_effects, cloned)
	return cloned

var _buff_img:String
var _buff_level:BaseNumber
var _effects:Array#[BaseEffect]
# 说明中需展示的持有者效果名；只存引用键，不复制规则或文案。
var _related_effect_names:Array = []
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
