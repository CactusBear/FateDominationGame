extends Node

var _model = SessionGeneration.ModelBacking.new({
	"situations":[],
	"active_situation":null,
	"event_deck":[],
	"event_discard":[],
	"situation_discard":[],
	"magic_workshop0":BaseLocation.new(BaseNumber.new(2),BaseNumber.new(0),1,true),
	"magic_workshop1":BaseLocation.new(BaseNumber.new(1),BaseNumber.new(0),1,true),
	"magic_workshop2":BaseLocation.new(BaseNumber.new(1),BaseNumber.new(0),1,true),
	"magic_workshop3":BaseLocation.new(BaseNumber.new(1),BaseNumber.new(0),1,true),
	"magic_workshop4":BaseLocation.new(BaseNumber.new(0),BaseNumber.new(0),-1,false,false),
	"magic_workshop":BaseMapArea.new(
	"魔术工房"
),
	"miyama0":BaseLocation.new(BaseNumber.new(0),BaseNumber.new(3)),
	"miyama1":BaseLocation.new(BaseNumber.new(0),BaseNumber.new(1)),
	"miyama2":BaseLocation.new(BaseNumber.new(0),BaseNumber.new(0),-1,true),
	"miyama":BaseMapArea.new(
	"深山町",
	BaseNumber.new(2)
),
	"shinto0":BaseLocation.new(BaseNumber.new(0),BaseNumber.new(3)),
	"shinto1":BaseLocation.new(BaseNumber.new(0),BaseNumber.new(1)),
	"shinto2":BaseLocation.new(BaseNumber.new(0),BaseNumber.new(0),-1,true),
	"shinto":BaseMapArea.new(
	"新都",
	BaseNumber.new(3)
),
	"scout0":BaseLocation.new(BaseNumber.new(0),BaseNumber.new(0),1,true),
	"scout1":BaseLocation.new(BaseNumber.new(0),BaseNumber.new(0),-1,false,false),
	"scout":BaseMapArea.new(
	"侦察",
	BaseNumber.new(2)
),
	"areas":[]
})


var situations:Array:
	get: return _model.read(&"situations", [])
	set(value): _model.write(&"situations", value)

#局势牌激活区(A2)：当前展示的局势牌，每回合一张
var active_situation:BaseSituation:
	get: return _model.read(&"active_situation", null)
	set(value): _model.write(&"active_situation", value)

#事件牌库区(B1)。事件牌是全局共用的一副牌，不属于任何玩家。
#里面的牌是LoadEvent.events模板的克隆，模板本身不进场
var event_deck:Array:
	get: return _model.read(&"event_deck", [])
	set(value): _model.write(&"event_deck", value)

#事件牌弃牌区：回合结束被弃置的事件牌进这里，供玩家回看本局出过哪些事件牌。
#不再直接 del()——销毁后历史就查不到了。里面的牌已离场、不参与任何规则判定
var event_discard:Array:
	get: return _model.read(&"event_discard", [])
	set(value): _model.write(&"event_discard", value)

#局势牌弃牌区：同上，回合结束弃置的局势牌进这里
var situation_discard:Array:
	get: return _model.read(&"situation_discard", [])
	set(value): _model.write(&"situation_discard", value)

var magic_workshop0:
	get: return _model.read(&"magic_workshop0", null)
	set(value): _model.write(&"magic_workshop0", value)
var magic_workshop1:
	get: return _model.read(&"magic_workshop1", null)
	set(value): _model.write(&"magic_workshop1", value)
var magic_workshop2:
	get: return _model.read(&"magic_workshop2", null)
	set(value): _model.write(&"magic_workshop2", value)
var magic_workshop3:
	get: return _model.read(&"magic_workshop3", null)
	set(value): _model.write(&"magic_workshop3", value)
#工房的额外席位：容量不限（效果放置不受人数限制），但不参与常规部署。
#常规移动本就进不来——它没有 _will_move_to 标记
var magic_workshop4:
	get: return _model.read(&"magic_workshop4", null)
	set(value): _model.write(&"magic_workshop4", value)

var magic_workshop:BaseMapArea:
	get: return _model.read(&"magic_workshop", null)
	set(value): _model.write(&"magic_workshop", value)

var miyama0:
	get: return _model.read(&"miyama0", null)
	set(value): _model.write(&"miyama0", value)
var miyama1:
	get: return _model.read(&"miyama1", null)
	set(value): _model.write(&"miyama1", value)
var miyama2:
	get: return _model.read(&"miyama2", null)
	set(value): _model.write(&"miyama2", value)

var miyama:BaseMapArea:
	get: return _model.read(&"miyama", null)
	set(value): _model.write(&"miyama", value)

var shinto0:
	get: return _model.read(&"shinto0", null)
	set(value): _model.write(&"shinto0", value)
var shinto1:
	get: return _model.read(&"shinto1", null)
	set(value): _model.write(&"shinto1", value)
var shinto2:
	get: return _model.read(&"shinto2", null)
	set(value): _model.write(&"shinto2", value)

var shinto:BaseMapArea:
	get: return _model.read(&"shinto", null)
	set(value): _model.write(&"shinto", value)

var scout0:
	get: return _model.read(&"scout0", null)
	set(value): _model.write(&"scout0", value)
#侦察的额外席位：容量不限，但不参与常规部署（侦察本来也不接受常规部署，这里把它写明确）
var scout1:
	get: return _model.read(&"scout1", null)
	set(value): _model.write(&"scout1", value)

var scout:BaseMapArea:
	get: return _model.read(&"scout", null)
	set(value): _model.write(&"scout", value)

var areas:Array:
	get: return _model.read(&"areas", [])
	set(value): _model.write(&"areas", value)

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

	_assign_areas()


#把四个固定战区挂到 areas 并做位置→战区的反向登记。开局构造与中途结束对局后重建共用。
#BaseLocation.get_from()要能取回map_area，UI/规则按area._area_name分流(部署槽位/信息栏/头像放置)
#全靠这份归属，只填_locations不反向设置from的话，from永远是null
func _assign_areas():
	areas = [
		magic_workshop,
		miyama,
		shinto,
		scout
	]
	for area:BaseMapArea in areas:
		for loc:BaseLocation in area._locations:
			loc.from = area


#中途结束对局后把版图恢复成开局前的样子：战区列表重挂（release_game_objects 会清空它），
#席位上的玩家与放置牌清空，效果改写过的数值按印刷基线还原（印刷值是数据声明的事实，
#当前值才允许被效果改写——与 RestoreLocation* 系列 operation 同一口径），
#战区上的事件/增益/战斗结果改写声明清空，两副牌库与弃牌区清空（下一局 start_game 重建）。
#效果新增的战区不在固定四区里，随 release_game_objects 一起作废
func reset_board():
	if SessionGeneration.in_private_frame() and domain_model_status().status != "COMPLETED": return
	_assign_areas()
	for area:BaseMapArea in areas:
		area._events.clear()
		area._buffs.clear()
		area._battle_override.clear()
		area._score = area._printed_score
		area._move_cost = area._printed_move_cost
		if area._printed_can_move_to != null:
			area._can_move_to = area._printed_can_move_to
			area._printed_can_move_to = null
		for loc:BaseLocation in area._locations:
			loc._players.clear()
			loc._placed_cards.clear()
			loc._magic = loc._printed_magic
			loc._benefit = loc._printed_benefit
			if loc._printed_pl_num_limit != null:
				loc._pl_num_limit = loc._printed_pl_num_limit
				loc._printed_pl_num_limit = null
	event_deck.clear()
	event_discard.clear()
	situations.clear()
	situation_discard.clear()
	active_situation = null

#重建事件牌库：把模板池深拷贝一份洗混，每局开始时调用。
#克隆是为了让场上的牌改不到模板，重开一局还能从模板重新发牌
func reset_event_deck(context:SessionContext = null) -> Dictionary:
	if SessionGeneration.in_private_frame(): return {"ok":false, "object":null, "context":context, "reason":&"unsupported_domain_runtime_factory"}
	var preflight:Dictionary = SessionGeneration.validate_context(context)
	if not preflight.ok: return {"ok":false, "context":context, "reason":preflight.reason}
	if not ShuffleArray.can_shuffle():
		return {"ok":false, "context":context, "reason":&"unknown_random_stream"}
	var copied:Dictionary = _copy_templates(LoadEvent.events, context)
	if not copied.ok: return copied
	var deck:Array = copied.object
	if ShuffleArray.new().exec(deck) == null:
		return {"ok":false, "context":context, "reason":&"unknown_random_stream"}
	var source:Dictionary = SessionGeneration.validate_context(context)
	if not source.ok: return {"ok":false, "context":context, "reason":source.reason}
	event_deck = deck
	#新的一局：上一局的弃牌区对象要先销毁再清空，只清数组会让它们永久残留在对象表里
	for event in event_discard:
		if event is BaseObject:
			event.del()
	event_discard.clear()
	return {"ok":true, "context":context, "reason":&"current"}

#重建局势牌库：10张非高潮洗混，烧前2张，剩8张进A1。每局开始时调用。
#局势牌每张只用一次(8非高潮+3高潮=11回合)，抽走不回牌堆
func reset_situation_deck(context:SessionContext = null) -> Dictionary:
	if SessionGeneration.in_private_frame(): return {"ok":false, "object":null, "context":context, "reason":&"unsupported_domain_runtime_factory"}
	var preflight:Dictionary = SessionGeneration.validate_context(context)
	if not preflight.ok: return {"ok":false, "context":context, "reason":preflight.reason}
	if not ShuffleArray.can_shuffle():
		return {"ok":false, "context":context, "reason":&"unknown_random_stream"}
	var copied:Dictionary = _copy_templates(LoadSituation.situations, context)
	if not copied.ok: return copied
	var non_climax:Array = copied.object
	if ShuffleArray.new().exec(non_climax) == null:
		return {"ok":false, "context":context, "reason":&"unknown_random_stream"}
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
	return {"ok":true, "context":context, "reason":&"current"}

# 只由此工厂从明确装载池生产；runtime 输入 C0 仍只继承/拒绝。
func _copy_templates(templates:Array, context:SessionContext) -> Dictionary:
	if SessionGeneration.in_private_frame(): return {"ok":false, "object":null, "context":context, "reason":&"unsupported_domain_runtime_factory"}
	var source:Dictionary = SessionGeneration.validate_context(context)
	if not source.ok: return {"ok":false, "object":null, "context":context, "reason":source.reason}
	for template in templates:
		if not LoadEvent.events.has(template) and not LoadSituation.situations.has(template) and not LoadSituation.climax_situations.values().has(template):
			return {"ok":false, "object":null, "context":context, "reason":&"untrusted_template"}
	var copier := CloneContext.new()
	if not copier.configure_template(context, templates):
		return {"ok":false, "object":null, "context":context, "reason":copier.failure_reason()}
	return copier.copy_result(templates, context)

func copy_climax(round_number:int, context:SessionContext) -> Dictionary:
	if SessionGeneration.in_private_frame(): return {"ok":false, "object":null, "context":context, "reason":&"unsupported_domain_runtime_factory"}
	if not LoadSituation.climax_situations.has(round_number):
		return {"ok":false, "object":null, "context":context, "reason":&"missing_situation"}
	var copied:Dictionary = _copy_templates([LoadSituation.climax_situations[round_number]], context)
	if copied.ok: copied.object = copied.object[0]
	return copied

# 只提供原始写集 backing 与 D 映射；没有 owner install/commit。
func publication_backing() -> Dictionary:
	return _model.backing()

func bind_domain_model(domain:Variant, private_state:Dictionary) -> Dictionary:
	return _model.bind(domain, private_state)

func domain_model_status() -> Dictionary:
	return _model.resolve()
