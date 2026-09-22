extends Node


var situations:Array

#局势牌激活区(A2)：当前展示的局势牌，每回合一张
var active_situation:BaseSituation = null

#事件牌库区(B1)。事件牌是全局共用的一副牌，不属于任何玩家。
#里面的牌是LoadEvent.events模板的克隆，模板本身不进场
var event_deck:Array = []

#事件牌弃牌区：回合结束被弃置的事件牌进这里，供玩家回看本局出过哪些事件牌。
#不再直接 del()——销毁后历史就查不到了。里面的牌已离场、不参与任何规则判定
var event_discard:Array = []

#局势牌弃牌区：同上，回合结束弃置的局势牌进这里
var situation_discard:Array = []

var magic_workshop0 = BaseLocation.new(BaseNumber.new(2),BaseNumber.new(0),1,true)
var magic_workshop1 = BaseLocation.new(BaseNumber.new(1),BaseNumber.new(0),1,true)
var magic_workshop2 = BaseLocation.new(BaseNumber.new(1),BaseNumber.new(0),1,true)
var magic_workshop3 = BaseLocation.new(BaseNumber.new(1),BaseNumber.new(0),1,true)
#工房的额外席位：容量不限（效果放置不受人数限制），但不参与常规部署。
#常规移动本就进不来——它没有 _will_move_to 标记
var magic_workshop4 = BaseLocation.new(BaseNumber.new(0),BaseNumber.new(0),-1,false,false)

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
#侦察的额外席位：容量不限，但不参与常规部署（侦察本来也不接受常规部署，这里把它写明确）
var scout1 = BaseLocation.new(BaseNumber.new(0),BaseNumber.new(0),-1,false,false)

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
	#前哨阶段可部署的战区由地图数据声明（缺声明的战区不具备部署席位）：
	#工房=魔力充能席、深山町/新都=地利席，侦察区只作先锋席，不接受常规部署
	magic_workshop._can_deploy = true
	#工房席位的魔力来自"工房"：限制类效果（cannot_gain_magic_from_workshop）按这个名字查
	magic_workshop._magic_source = "workshop"
	miyama._can_deploy = true
	shinto._can_deploy = true
	
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

	#反向登记每个位置所属的战区。BaseLocation.get_from()要能取回map_area，
	#UI/规则按area._area_name分流(部署槽位/信息栏/头像放置)全靠这份归属，
	#只填_locations不反向设置from的话，from永远是null
	for area:BaseMapArea in areas:
		for loc:BaseLocation in area._locations:
			loc.from = area

#重建事件牌库：把模板池深拷贝一份洗混，每局开始时调用。
#克隆是为了让场上的牌改不到模板，重开一局还能从模板重新发牌
func reset_event_deck():
	var deck:Array = []
	for template in LoadEvent.events:
		deck.append(CloneObject.new().exec(template))
	ShuffleArray.new().exec(deck)
	event_deck = deck
	#新的一局：上一局的弃牌区对象要先销毁再清空，只清数组会让它们永久残留在对象表里
	for event in event_discard:
		if event is BaseObject:
			event.del()
	event_discard.clear()

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
	#与事件牌弃牌区同一套：先销毁上一局的弃牌，再清空
	for situation in situation_discard:
		if situation is BaseObject:
			situation.del()
	situation_discard.clear()
