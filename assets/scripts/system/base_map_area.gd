extends RefCounted
class_name BaseMapArea

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

var _locations:Array
var _area_name:String
var _events:Array = []
var _score:BaseNumber
var _score_need_win:bool = true
var _printed_score:BaseNumber
var _buffs:Array = []
var _linked_map_area:BaseMapArea
var _move_cost:BaseNumber
var _printed_move_cost:BaseNumber
var _can_move_to:bool = true
#_can_move_to 的印刷基线：null 表示从未被效果改动过。
#局势牌(封区类)进场时由 SetMapAreaCanMoveTo 记下原值，弃置时按基线还原
var _printed_can_move_to
#该战区在前哨阶段是否接受常规部署。默认 false：缺声明就不给行为——
#所有战区一视同仁地"看起来能部署"会把侦察区这种只作先锋席的战区也算进去
var _can_deploy:bool = false

func _init(area_name:String, score:BaseNumber = BaseNumber.new(0), move_cost:BaseNumber = BaseNumber.new(0), linked_map_area:BaseMapArea = null):
	_area_name = area_name
	_score = score
	_printed_score = score
	_linked_map_area = linked_map_area
	_move_cost = move_cost
	_printed_move_cost = move_cost
	#MapData自己的成员初始化阶段就会构造地区，此时单例还未就绪，那些地区由MapData._init()自行登记
	if MapData != null:
		MapData.areas.append(self)


func set_map_area_score_need_win(T_or_F:bool):
	_score_need_win = T_or_F

func set_map_area_locations(locations:Array):
	_locations = locations
