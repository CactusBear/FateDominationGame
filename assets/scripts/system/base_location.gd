extends Node
class_name BaseLocation


var from
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
