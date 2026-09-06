extends RefCounted
class_name BaseLocation


#所属对象。所有者反过来也持有本对象，用强引用会形成循环引用，所以存弱引用
var from : set = set_from, get = get_from
var _from_ref:WeakRef
var _from_value


func set_from(value):
	if value is Object:
		_from_ref = weakref(value)
		_from_value = null
	else:
		_from_ref = null
		_from_value = value


func get_from():
	if _from_ref != null:
		return _from_ref.get_ref()
	return _from_value

var _players:Array
var _magic:BaseNumber
var _printed_magic:BaseNumber
var _benefit:BaseNumber
var _printed_benefit:BaseNumber
var _pl_num_limit:int
var _will_move_to:bool

func _init(magic:BaseNumber = BaseNumber.new(0), benefit:BaseNumber = BaseNumber.new(0), pl_num_limit:int = 1, will_move_to:bool = false):
	_magic = magic
	_printed_magic = magic
	_benefit = benefit
	_printed_benefit = benefit
	_pl_num_limit = pl_num_limit
	_will_move_to = will_move_to
