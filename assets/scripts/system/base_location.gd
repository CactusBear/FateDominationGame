extends RefCounted
class_name BaseLocation

func clone_data(context):
	var cloned = BaseLocation.new(context.copy(_magic), context.copy(_benefit), _pl_num_limit, _will_move_to, _can_deploy)
	cloned.from = from
	cloned._printed_magic = cloned._magic if _printed_magic == _magic else context.copy(_printed_magic)
	cloned._printed_benefit = cloned._benefit if _printed_benefit == _benefit else context.copy(_printed_benefit)
	cloned._printed_pl_num_limit = _printed_pl_num_limit
	cloned._players = []
	return cloned


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
#_pl_num_limit 的印刷基线：null 表示从未被效果改动过。
#限员类局势牌进场时由 SetLocationPlNumLimit 记下原值，弃置时按基线还原
var _printed_pl_num_limit
var _will_move_to:bool
#这个点位能不能被"常规部署"选中。默认可以；额外席位声明 false 时，
#常规部署进不去（容量仍可为 -1 表示不限人数），只有效果直接落位才进得去。
#常规移动是否可达由 _will_move_to 单独决定，两者语义不同
var _can_deploy:bool

func _init(magic:BaseNumber = BaseNumber.new(0), benefit:BaseNumber = BaseNumber.new(0), pl_num_limit:int = 1, will_move_to:bool = false, can_deploy:bool = true):
	_magic = magic
	_printed_magic = magic
	_benefit = benefit
	_printed_benefit = benefit
	_pl_num_limit = pl_num_limit
	_will_move_to = will_move_to
	_can_deploy = can_deploy
