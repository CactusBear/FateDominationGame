extends Node


var situations:Array

var magic_workshop0 = BaseLocation.new(2,0,1,true)
var magic_workshop1 = BaseLocation.new(1,0,1,true)
var magic_workshop2 = BaseLocation.new(1,0,1,true)
var magic_workshop3 = BaseLocation.new(1,0,1,true)
var magic_workshop4 = BaseLocation.new(0,0,-1)

var magic_workshop:BaseMapArea = BaseMapArea.new(
	[
		magic_workshop0,
		magic_workshop1,
		magic_workshop2,
		magic_workshop3,
		magic_workshop4
	],
	"魔术工房"
)

var miyama0 = BaseLocation.new(0,3)
var miyama1 = BaseLocation.new(0,1)
var miyama2 = BaseLocation.new(0,0,-1,true)

var miyama:BaseMapArea = BaseMapArea.new(
	[
		miyama0,
		miyama1,
		miyama2
	],
	"深山町",
	2
)

var shinto0 = BaseLocation.new(0,3)
var shinto1 = BaseLocation.new(0,1)
var shinto2 = BaseLocation.new(0,0,-1,true)

var shinto:BaseMapArea = BaseMapArea.new(
	[
		shinto0,
		shinto1,
		shinto2
	],
	"新都",
	3
)

var scout0 = BaseLocation.new(0,0,1,true)
var scout1 = BaseLocation.new(0,0,-1)

var scout:BaseMapArea = BaseMapArea.new(
	[
		scout0,
		scout1,
	],
	"侦察",
	2
)

var areas:Array

func _init():
	magic_workshop._linked_map_area = miyama
	magic_workshop._move_cost = 1
	
	miyama._linked_map_area = shinto
	miyama._move_cost = 2
	
	shinto._linked_map_area = scout
	shinto._move_cost = 2

	areas = [
		magic_workshop,
		miyama,
		shinto,
		scout
	]
