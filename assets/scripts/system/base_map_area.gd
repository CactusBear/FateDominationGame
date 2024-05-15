extends Node
class_name BaseMapArea

var from
var _locations:Array
var _area_name:String
var _events:Array
var _score:BaseNumber
var _score_need_win:bool = true
var _printed_score:BaseNumber
var _buffs:Array
var _linked_map_area:BaseMapArea
var _move_cost:BaseNumber
var _printed_move_cost:BaseNumber
var _can_move_to:bool = true

func _init(area_name:String, score:BaseNumber = BaseNumber.new(0), move_cost:BaseNumber = BaseNumber.new(0), linked_map_area:BaseMapArea = null):
	_area_name = area_name
	_score = score
	_printed_score = score
	_linked_map_area = linked_map_area
	_move_cost = move_cost
	_printed_move_cost = move_cost
	MapData.areas.append(self)


func set_map_area_score_need_win(T_or_F:bool):
	_score_need_win = T_or_F

func set_map_area_locations(locations:Array):
	_locations = locations
