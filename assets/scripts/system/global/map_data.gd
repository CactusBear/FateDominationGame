extends Node


var situations:Array

var magic_workshop0 = BaseLocation.new(BaseNumber.new(2),BaseNumber.new(0),1,true)
var magic_workshop1 = BaseLocation.new(BaseNumber.new(1),BaseNumber.new(0),1,true)
var magic_workshop2 = BaseLocation.new(BaseNumber.new(1),BaseNumber.new(0),1,true)
var magic_workshop3 = BaseLocation.new(BaseNumber.new(1),BaseNumber.new(0),1,true)
var magic_workshop4 = BaseLocation.new(BaseNumber.new(0),BaseNumber.new(0),-1)

var magic_workshop:BaseMapArea = BaseMapArea.new(
	"魔术工房"
)

var miyama0 = BaseLocation.new(BaseNumber.new(0),BaseNumber.new(3))
var miyama1 = BaseLocation.new(BaseNumber.new(0),BaseNumber.new(1))
var miyama2 = BaseLocation.new(BaseNumber.new(0),BaseNumber.new(0),-1,true)

var miyama:BaseMapArea = BaseMapArea.new(
	"深山町",
	BaseNumber.new(2)
)

var shinto0 = BaseLocation.new(BaseNumber.new(0),BaseNumber.new(3))
var shinto1 = BaseLocation.new(BaseNumber.new(0),BaseNumber.new(1))
var shinto2 = BaseLocation.new(BaseNumber.new(0),BaseNumber.new(0),-1,true)

var shinto:BaseMapArea = BaseMapArea.new(
	"新都",
	BaseNumber.new(3)
)

var scout0 = BaseLocation.new(BaseNumber.new(0),BaseNumber.new(0),1,true)
var scout1 = BaseLocation.new(BaseNumber.new(0),BaseNumber.new(0),-1)

var scout:BaseMapArea = BaseMapArea.new(
	"侦察",
	BaseNumber.new(2)
)

var areas:Array

func _init():
	magic_workshop._locations = [
		magic_workshop0,
		magic_workshop1,
		magic_workshop2,
		magic_workshop3,
		magic_workshop4
	]
	magic_workshop._linked_map_area = miyama
	magic_workshop._move_cost = BaseNumber.new(1)
	
	miyama._locations = [
		miyama0,
		miyama1,
		miyama2
	]
	miyama._linked_map_area = shinto
	miyama._move_cost = BaseNumber.new(2)
	
	shinto._locations = [
		shinto0,
		shinto1,
		shinto2
	]
	shinto._linked_map_area = scout
	shinto._move_cost = BaseNumber.new(2)
	
	scout._locations = [
		scout0,
		scout1,
	]
	scout._score_need_win = false
	
	areas = [
		magic_workshop,
		miyama,
		shinto,
		scout
	]
