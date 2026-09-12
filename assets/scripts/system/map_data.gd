extends Node


var situations:Array

#局势牌激活区(A2)：当前展示的局势牌，每回合一张
var active_situation:BaseSituation = null

#事件牌库区(B1)。事件牌是全局共用的一副牌，不属于任何玩家。
#里面的牌是LoadEvent.events模板的克隆，模板本身不进场
var event_deck:Array = []

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
	#工房区的战果不通过战斗获得，因此不参与战力结算
	magic_workshop._score_need_win = false
	
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

#重建事件牌库：把模板池深拷贝一份洗混，每局开始时调用。
#克隆是为了让场上的牌改不到模板，重开一局还能从模板重新发牌
func reset_event_deck():
	var deck:Array = []
	for template in LoadEvent.events:
		deck.append(CloneObject.new().exec(template))
	ShuffleArray.new().exec(deck)
	event_deck = deck

#重建局势牌库：10张非高潮洗混，烧前2张，剩8张进A1。每局开始时调用。
#局势牌每张只用一次(8非高潮+3高潮=11回合)，抽走不回牌堆
func reset_situation_deck():
	var non_climax:Array = LoadSituation.situations.duplicate()
	ShuffleArray.new().exec(non_climax)
	if non_climax.size() > 2:
		situations = non_climax.slice(2)
	else:
		situations = non_climax
	active_situation = null
