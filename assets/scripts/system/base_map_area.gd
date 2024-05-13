extends Node
class_name BaseMapArea


var _locations:Array
var _area_name:String
var _events:Array
var _score:int
var _printed_score:int
var _buffs:Array
var _linked_map_area:BaseMapArea
var _move_cost:int
var _printed_move_cost:int
var _can_move_to:bool = true

func _init(locations:Array, area_name:String, score:int = 0, linked_map_area:BaseMapArea = null, move_cost:int = 0):
	_locations = locations
	_area_name = area_name
	_score = score
	_printed_score = score
	_linked_map_area = linked_map_area
	_move_cost = move_cost
	_printed_move_cost = move_cost
	MapData.areas.append(self)
