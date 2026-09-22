extends Node


#效果系统的唯一入口：效果池登记、时点检查、询问顺序、优先级结算、时点关闭打断。
#注册为autoload"EffectManager"，所以不能再带class_name(两者会重名冲突)。
#GameProgress只负责游戏回合进程，不再持有任何效果处理逻辑。


#全局效果池。池中效果的_trigger_player_id即其归属玩家，-1表示还没进入游戏
var effect_pool:Array#[BaseEffect]
#选项级 select_cards 的 owner 取值：声明成它表示"挑先由 select_players 选定的那名玩家的牌"。
#不声明时挑的是触发者自己的牌，既有卡不受影响
const CARD_SELECTION_OWNER_TARGET := "target_player"
#当前正在结算的效果，供各effect脚本取上下文
var activating_eff:BaseEffect

#本时点的待决定队列。被动直接入池，主动逐个询问，两者按顺位交错排在同一条队列里
var decision_queue:Array#[BaseEffect]
#本时点确定要发动的效果，全部决定完后按优先级结算
var activation_pool:Array#[BaseEffect]
#正在等待其归属玩家答复的效果，非null时整条流程暂停
var waiting_effect:BaseEffect
#正在等待玩家挑具体牌张的效果（被选中的选项声明了 select_cards）。
#与 waiting_effect 并列的第二种等待：前者等"发动/放弃"，这里等"挑哪几张牌"；
#两者不会同时非null——选项提交先过 waiting_effect，再进选牌等待
var waiting_selection:BaseEffect = null
#正在等待选牌的那个选项下标（声明挂在选项字典里，所以要知道是第几项）
var _waiting_selection_option:int = -1
# {BaseEffect : Dictionary}，等选牌期间暂扣的选项提交，挑完牌再一起记用量/扣资源
var _pending_selection_choice:Dictionary = {}
#正在等待选择位置的效果。位置不是卡牌，独立于 select_cards，但同样在支付前等待。
var waiting_location:BaseEffect = null
var _pending_location_choice:Dictionary = {}
#正在等待选择玩家目标的效果（选项级 select_players）。与选牌/选位置并列的第三种玩家输入，
#同样在支付前等待：玩家取消或提交不在候选集里的目标时，效果等于没发动
var waiting_players:BaseEffect = null
var _pending_player_choice:Dictionary = {}
var matched_time_points:Dictionary
#{BaseEffect : int}，本时点已结算过的效果，避免同一时点内重复触发
var resolved_effects:Dictionary
#{player_id : Array[String]}，本时点被关闭的时点
var closed_time_points:Dictionary
#{BaseEffect : Array[BaseFunc]}，被反制的func，结算时跳过
var countered_funcs:Dictionary
#时点批次编号，每进入一个新时点递增
var time_point_id:int = 0
#结算中标记。结算过程里派发的新时点只追加效果，不另起批次
var is_running:bool = false
#待展示的提示消息队列：[{"text":String, "player_id":int}]，player_id=-1表示全员可见。
#operation只负责产生消息，界面取走并展示(取走即移除)，显示形态由界面决定
var messages:Array = []
#玩家资源字段的显示名。发动结果要写清"谁受到什么影响"，这些名字是玩家能核对的口径
const PLAYER_NUMERIC_FIELDS:Dictionary = {
	"magic": "魔力", "score": "战果", "command_spell_count": "令咒",
	"power": "合计威力", "total_power_bonus": "合计威力加成",
}
#对象上可被效果改动的数值字段的显示名（卡牌数值、状态层数、席位地利）
const OBJECT_NUMERIC_FIELDS:Dictionary = {
	"_power": "威力", "_cost": "魔力消耗", "_buff_level": "层数", "_benefit": "地利",
}
#牌区归属在规则状态快照里的字段名。它不是"对象的数值"，而是"这张牌此刻在谁手上、落在哪个区"，
#由 capture_rule_state 单独记一份，diff_rule_state 把它的前后差聚合成"手牌 → 弃牌堆 ×3"这类明细。
#没这一维时，弃牌/抽牌这类只改归属、不改数值的效果全都会显示"未产生即时变化"
const ZONE_FIELD:String = "zone"
#牌区路径各段的显示名：明细要写"手牌 → 弃牌堆"而不是内部键名 hand_cards/discard。
#路径由容器键拼成（side/skills 这类嵌套也表达得出来），这里只负责显示，不参与任何规则判定；
#没有登记中文名的段按原键名显示，不猜含义
const ZONE_SEGMENT_SHOWN:Dictionary = {
	"hand_cards": "手牌", "discard": "弃牌堆", "deck": "牌库", "played_cards": "打出区",
	"servant_skills": "从者技能区", "master_skills": "御主技能区", "command_spell": "令咒",
	"buffs": "状态", "out_of_game": "游戏外", "others": "附带物",
	"attacks": "攻击牌", "skills": "技能牌",
}
#手动发动成功后的独立结果队列。它与普通规则提示分开，界面用专门的“发动结果”弹窗展示，
#避免结果提示复用战术确认框并与下一条能力询问重叠。
var effect_results:Array = []

#本时点内累积的效果提示，按可见范围分桶 {player_id: [文案]}。
#战斗结算这类时点会连续触发一批效果，逐条推会把提示刷成一长串、还互相覆盖，
#所以先攒起来，等本时点整条管线跑完再合并成一条推送
var _pending_announcements:Dictionary = {}
# 玩家选择尚未完成时到达的后续时点批次；保存各玩家时点快照，答复后按顺序恢复处理。
var _queued_time_point_batches:Array = []


#产生一条提示消息。消息先入队，由界面在刷新时取走展示——
#效果结算过程中不应直接操作界面节点，否则界面没加载时效果会崩
func push_message(text:String, player_id:int = -1):
	if text == "":
		return
	messages.append({"text" : text, "player_id" : player_id})


#取走该玩家的全部消息(取走即移除)。界面每次刷新时调用。
#不属于该玩家的消息留在队列里，等对应玩家来取，不会串看别人的提示
func pop_messages(player_id:int) -> Array:
	var taken:Array = []
	var left:Array = []
	for msg in messages:
		var pid:int = int(msg.get("player_id", -1))
		if pid == -1 or pid == player_id:
			taken.append(str(msg.get("text", "")))
		else:
			left.append(msg)
	messages = left
	return taken


func push_effect_result(text:String, player_id:int = -1) -> void:
	if text == "":
		return
	effect_results.append({"text":text, "player_id":player_id})


func pop_effect_results(player_id:int) -> Array:
	var taken:Array = []
	var left:Array = []
	for result in effect_results:
		var pid:int = int(result.get("player_id", -1))
		if pid == -1 or pid == player_id:
			taken.append(str(result.get("text", "")))
		else:
			left.append(result)
	effect_results = left
	return taken


#发动结果的依据：结算前后各取一次"规则状态"快照，用差值说明谁/哪个对象被改了什么。
#快照只覆盖规则上会被效果改动的数值（玩家资源、卡牌数值、状态层数、席位地利），
#键里带对象实例编号，因此同名多张牌也能各自对应；存的是当时的数值，之后对象再变不影响。
func capture_rule_state() -> Dictionary:
	var snapshot:Dictionary = {}
	var indexes:Array = _card_zone_indexes()
	var owners:Dictionary = indexes[0] as Dictionary
	for id in GameData.player_data_library.keys():
		var data:Dictionary = GameData.player_data_library[id] as Dictionary
		for field in PLAYER_NUMERIC_FIELDS.keys():
			var value = data.get(field)
			if value is BaseNumber:
				snapshot["p%d|%s" % [int(id), field]] = {
					"player_id": int(id), "object_name": "", "field": field, "value": value.number}
	for obj in GameData.objects:
		if obj == null:
			continue
		var object_name:String = str(obj.get_shown_name()) if obj is BaseObject else ""
		var owner_id:int = int(owners.get(obj.get_instance_id(), -1))
		for field in OBJECT_NUMERIC_FIELDS.keys():
			var value = obj.get(field)
			if value is BaseNumber:
				snapshot["o%d|%s" % [obj.get_instance_id(), field]] = {
					"player_id": owner_id, "object_name": object_name, "field": field, "value": value.number}
	#牌区归属：同一张牌在这两次快照里"属于谁、落在哪个区"。只在前后都存在的同一张牌上比较
	#（与数值字段同一口径），所以结算中新建的克隆牌不会冒充一次搬运
	var zones:Dictionary = indexes[1] as Dictionary
	for instance_id in zones.keys():
		var info:Dictionary = zones[instance_id] as Dictionary
		snapshot["z%d" % int(instance_id)] = {
			"player_id": int(info["player_id"]), "object_name": "", "field": ZONE_FIELD,
			"zone_path": str(info["zone"]),
			"value": "%d|%s" % [int(info["player_id"]), str(info["zone"])]}
	return snapshot


#玩家的牌区遍历：一次遍历同时产出两份索引——
#① 对象实例 → 所属玩家（给数值快照标注"这张牌/这个状态是谁的"）；
#② 卡牌实例 → {所属玩家, 所在牌区路径}（给牌区归属快照用）。
#递归遍历每个玩家的所有容器（含 side/out_of_game 这类嵌套），区路径由容器键拼成，
#不写死任何区名；状态/御主/从者这类不是卡的对象只进第 ① 份索引
func _card_zone_indexes() -> Array:
	var owners:Dictionary = {}
	var zones:Dictionary = {}
	for id in GameData.player_data_library.keys():
		var data:Dictionary = GameData.player_data_library[id] as Dictionary
		for key in data.keys():
			_collect_zone_cards(data[key], owners, int(id), zones, str(key))
	return [owners, zones]


func _collect_zone_cards(value, owners:Dictionary, player_id:int, zones:Dictionary, zone_path:String) -> void:
	if value is Array:
		for item in value:
			if item is BaseObject:
				owners[item.get_instance_id()] = player_id
				if item is BaseCard:
					zones[item.get_instance_id()] = {"player_id": player_id, "zone": zone_path}
			elif item is Array or item is Dictionary:
				_collect_zone_cards(item, owners, player_id, zones, zone_path)
	elif value is Dictionary:
		for key in value.keys():
			_collect_zone_cards(value[key], owners, player_id, zones, "%s/%s" % [zone_path, str(key)])


#两次快照的差值。只在同一把键前后都存在时比较（结算中新建/销毁的对象不参与），
#返回按"玩家 → 对象 → 字段"排序的明细，供结果弹窗逐条展示。
#牌区归属的变化单独聚合成"手牌 → 弃牌堆 ×3"这类搬运明细，排在数值变化之前——
#玩家先要知道"这次发动的牌去了哪"，再看数值被改了多少
func diff_rule_state(before:Dictionary, after:Dictionary) -> Array:
	var changes:Array = []
	var transfers:Dictionary = {}
	for key in before.keys():
		if !after.has(key):
			continue
		var old:Dictionary = before[key]
		var now:Dictionary = after[key]
		if str(now.get("field", "")) == ZONE_FIELD:
			#同一张牌换了牌区：按 (来源|去向) 聚合成一条，不逐张刷屏。
			#分组键只是两张快照里的归属描述；跨玩家的搬运照样表达得出来（目标玩家写进明细）
			if str(old.get("value")) == str(now.get("value")):
				continue
			var group_key:String = "%s>%s" % [str(old.get("value")), str(now.get("value"))]
			if !transfers.has(group_key):
				transfers[group_key] = {
					"player_id": int(old.get("player_id", -1)), "from_zone": str(old.get("zone_path", "")),
					"to_player": int(now.get("player_id", -1)), "to_zone": str(now.get("zone_path", "")),
					"count": 0}
			transfers[group_key]["count"] = int(transfers[group_key]["count"]) + 1
			continue
		if old.get("value") == now.get("value"):
			continue
		changes.append({
			"player_id": int(now.get("player_id", -1)),
			"object_name": str(now.get("object_name", "")),
			"field": str(now.get("field", "")),
			"before": old.get("value"),
			"after": now.get("value"),
		})
	changes.sort_custom(func(a, b):
		if int(a["player_id"]) != int(b["player_id"]):
			return int(a["player_id"]) < int(b["player_id"])
		if str(a["object_name"]) != str(b["object_name"]):
			return str(a["object_name"]) < str(b["object_name"])
		return str(a["field"]) < str(b["field"]))
	var lines:Array = []
	for group_key in transfers.keys():
		var transfer:Dictionary = transfers[group_key]
		lines.append({
			"kind": "zone_move", "player_id": int(transfer["player_id"]), "object_name": "",
			"field": ZONE_FIELD, "from_zone": str(transfer["from_zone"]),
			"to_player": int(transfer["to_player"]), "to_zone": str(transfer["to_zone"]),
			"count": int(transfer["count"])})
	lines.sort_custom(func(a, b):
		if str(a["from_zone"]) != str(b["from_zone"]):
			return str(a["from_zone"]) < str(b["from_zone"])
		return str(a["to_zone"]) < str(b["to_zone"]))
	lines.append_array(changes)
	return lines


#一条变化的中文行：谁／哪个对象／哪个字段／前值 → 后值。字段名取显式声明，不猜
func format_rule_change(change:Dictionary) -> String:
	if str(change.get("kind", "")) == "zone_move":
		return _format_zone_move(change)
	var field:String = str(change.get("field", ""))
	var shown_field:String = str(OBJECT_NUMERIC_FIELDS.get(field, PLAYER_NUMERIC_FIELDS.get(field, field)))
	var owner:String = ""
	var id:int = int(change.get("player_id", -1))
	if id >= 0:
		owner = player_shown_name(id)
	var object_name:String = str(change.get("object_name", ""))
	if object_name != "":
		owner += "【%s】" % object_name
	var prefix:String = (owner + " ") if owner != "" else ""
	return "%s%s %s → %s" % [prefix, shown_field, change.get("before"), change.get("after")]


#一条牌区搬运的中文行：谁手上的哪个区 → 谁手上的哪个区 ×张数。
#目标玩家与来源玩家相同时不重复写名字（"远坂凛 手牌 → 弃牌堆 ×3"），
#与数值明细"玩家 字段 前 → 后"同一写法：名字和它描述的东西之间留一个空格
func _format_zone_move(change:Dictionary) -> String:
	var from_player:int = int(change.get("player_id", -1))
	var to_player:int = int(change.get("to_player", -1))
	var from_zone:String = _zone_shown_name(str(change.get("from_zone", "")))
	var to_zone:String = _zone_shown_name(str(change.get("to_zone", "")))
	var from_part:String = from_zone
	if from_player >= 0:
		from_part = "%s %s" % [player_shown_name(from_player), from_zone]
	var to_part:String = to_zone
	if to_player >= 0 and to_player != from_player:
		to_part = "%s %s" % [player_shown_name(to_player), to_zone]
	return "%s → %s ×%d" % [from_part, to_part, int(change.get("count", 0))]


#牌区路径 → 显示名：按"段"登记（side/skills 这类嵌套每段各自翻译），
#没有登记中文名的段按原键名显示——不猜含义，缺登记只是显示得不好看，不会显示错
func _zone_shown_name(zone_path:String) -> String:
	if zone_path == "":
		return ""
	var shown:Array = []
	for part in zone_path.split("/"):
		shown.append(str(ZONE_SEGMENT_SHOWN.get(str(part), str(part))))
	return "".join(shown)


func player_shown_name(player_id:int) -> String:
	if !GameData.player_data_library.has(player_id):
		return "玩家 %d" % player_id
	var master = (GameDataManager.get_player_data(player_id) as Dictionary).get("master")
	if master != null:
		var shown:String = str(master.get_shown_name())
		if shown != "":
			return shown
	return "玩家 %d" % player_id


#清理本局运行时状态，保留已经加载的游戏资源和效果对象
func reset_runtime():
	effect_pool.clear()
	activating_eff = null
	decision_queue.clear()
	activation_pool.clear()
	waiting_effect = null
	waiting_selection = null
	waiting_location = null
	waiting_players = null
	_waiting_selection_option = -1
	_pending_selection_choice.clear()
	_pending_location_choice.clear()
	_pending_player_choice.clear()
	messages.clear()
	effect_results.clear()
	_pending_announcements.clear()
	_queued_time_point_batches.clear()
	matched_time_points.clear()
	resolved_effects.clear()
	closed_time_points.clear()
	countered_funcs.clear()
	settled_phase_windows.clear()
	time_point_id = 0
	is_running = false
	for id in GameData.player_data_library.keys():
		var player_data = GameData.player_data_library[id] as Dictionary
		(player_data["self_effects"] as Array).clear()


#每回合开始时调用：清空所有声明了"每回合重置"的选项类效果的用量计数，
#让"本回合选过的选项"这类限制在新回合重新可选
func reset_round_option_counts():
	for effect:BaseEffect in effect_pool:
		if effect.has_options():
			reset_effect_option_counts(effect)


#单个效果的计数重置：若声明了_reset_counts_each_round才清空，不声明的效果维持全局永久计数不变
func reset_effect_option_counts(effect:BaseEffect):
	if effect._reset_counts_each_round:
		effect._option_use_counts.clear()
		effect._option_quantities.clear()


#某个选项在当前重置周期内已用了几次
func get_option_use_count(effect:BaseEffect, option_index:int) -> int:
	return effect._option_use_counts.get(option_index, 0) as int


#当前重置周期内该效果所有选项累计用了几次
func get_total_use_count(effect:BaseEffect) -> int:
	var total := 0
	for v in effect._option_use_counts.values():
		total += v as int
	return total


#来源对象(effect.from)的剩余资源层数；没有声明消耗或来源没有_buff_level时返回-1(不限)
func get_source_resource_level(effect:BaseEffect) -> int:
	if !effect._consumes_source_resource or effect.from == null:
		return -1
	if !("_buff_level" in effect.from):
		return -1
	var lvl = effect.from._buff_level
	return (lvl.number as int) if lvl is BaseNumber else -1


#某个选项还能不能再选extra_count次：没超过该选项自身的max_uses(累计)、没超过效果整体的max_total_uses(累计)、
#没超过这一次提交的max_choices限额、来源资源层数够扣。extra_count默认1，供UI/AI判断"至少还能选一次"用
func is_option_available(effect:BaseEffect, option_index:int, extra_count:int = 1) -> bool:
	if option_index < 0 or option_index >= effect._options.size():
		return false
	var opt_max:int = effect._options[option_index].get("max_uses", -1) as int
	if opt_max != -1 and get_option_use_count(effect, option_index) + extra_count > opt_max:
		return false
	if effect._max_total_uses != -1 and get_total_use_count(effect) + extra_count > effect._max_total_uses:
		return false
	if effect._max_choices != -1 and extra_count > effect._max_choices:
		return false
	if effect._options[option_index].get("select_location", null) is Dictionary and !_location_option_origin_allowed(effect, effect._options[option_index].get("select_location", {})):
		return false
	#声明了玩家目标但候选集为空（如所在战场没有别的玩家）时该选项不可选：
	#与"起点不在声明战区"同一条口径，避免玩家点下去才发现没有可点的目标
	if effect._options[option_index].get("select_players", null) is Dictionary:
		var pl_spec:Dictionary = effect._options[option_index].get("select_players", {})
		if int(pl_spec.get("min", 1)) > 0 and get_player_selection_candidates(pl_spec, effect).is_empty():
			return false
	var res_level := get_source_resource_level(effect)
	if res_level != -1 and extra_count > res_level:
		return false
	# 选项可声明发动前置查询（如「本回合必须打出了某种牌」）。这里必须在"能不能选"这一层预判，
	# 否则玩家会看到一条点下去才被拒的选项；预判阶段不推消息，避免每帧刷提示
	if !_option_activation_requirements_met(effect, {option_index: extra_count}, true):
		return false
	return true


func _location_option_origin_allowed(effect:BaseEffect, spec:Dictionary) -> bool:
	var origin:BaseLocation = GetLocation.new().exec(effect._trigger_player_id)
	var area:BaseMapArea = origin.get_from() as BaseMapArea if origin != null else null
	if area == null:
		return false
	#未声明起点限制时不限制：卡面「移动至任意地点」这类没有起点条件，
	#与"未声明 owner 就挑自己的牌"同一口径（缺声明=不限，而不是恒假）
	var allowed:Array = spec.get("allowed_origin_areas", []) as Array
	return allowed.is_empty() or allowed.has(str(area._area_name))


#是否还有任何一个选项可选；全部耗尽(次数上限用完或来源资源为0)时UI/AI都不应再弹出这个效果
func has_available_options(effect:BaseEffect) -> bool:
	if effect._consumes_source_resource and get_source_resource_level(effect) == 0:
		return false
	for i in range(effect._options.size()):
		if is_option_available(effect, i, 1):
			return true
	return false


#校验一份完整的选择提交是否合法：每项次数、这一次提交的总次数、累计总次数、来源资源都要够，
#任一超限则整体不合法。selection为{选项下标:本次要用几次}
func validate_selection(effect:BaseEffect, selection:Dictionary) -> bool:
	if selection.is_empty():
		return false
	var total := 0
	for idx in selection.keys():
		var count:int = selection[idx] as int
		if !(idx is int) or count <= 0:
			return false
		if idx < 0 or idx >= effect._options.size():
			return false
		var opt_max:int = effect._options[idx].get("max_uses", -1) as int
		if opt_max != -1 and get_option_use_count(effect, idx) + count > opt_max:
			return false
		total += count
	if effect._max_choices != -1 and total > effect._max_choices:
		return false
	if effect._max_total_uses != -1 and get_total_use_count(effect) + total > effect._max_total_uses:
		return false
	var res_level := get_source_resource_level(effect)
	if res_level != -1 and total > res_level:
		return false
	return true


#选项可声明发动前置查询；查询在记用量/扣来源资源之前执行。
#每项 requirement 的 funcs 共用一张临时变量表，最后一个返回值为真才通过；
#失败消息完全由数据声明，引擎不认识具体卡名或资源名。
func _option_activation_requirements_met(effect:BaseEffect, selection:Dictionary, silent:bool = false) -> bool:
	var previous_effect = activating_eff
	var previous_vars:Array = effect._self_vars.duplicate()
	activating_eff = effect
	for idx in selection.keys():
		if !(idx is int) or idx < 0 or idx >= effect._options.size():
			continue
		var requirements = effect._options[idx].get("activation_requirements", [])
		if !(requirements is Array):
			continue
		for requirement in requirements:
			if !(requirement is Dictionary):
				continue
			effect._self_vars = []
			var final_result = null
			var called:bool = false
			for desc in (requirement.get("funcs", []) as Array):
				var outcome:Array = run_func_descriptor(desc, effect)
				if bool(outcome[0]):
					called = true
					final_result = outcome[1]
			var passed:bool = called
			if final_result is BaseNumber:
				passed = passed and final_result.number != 0
			else:
				passed = passed and bool(final_result)
			if !passed:
				var message:String = str(requirement.get("message", "无法发动该选项"))
				if !silent:
					push_message(message, effect._trigger_player_id)
				effect._self_vars = previous_vars
				activating_eff = previous_effect
				return false
	effect._self_vars = previous_vars
	activating_eff = previous_effect
	return true


#把一份已校验通过的选择计入用量，并按声明消耗来源资源层数。
#在validate_selection通过、确定要发动之后调用一次
func record_selection_usage(effect:BaseEffect, selection:Dictionary):
	var total := 0
	for idx in selection.keys():
		var count:int = selection[idx] as int
		effect._option_use_counts[idx] = get_option_use_count(effect, idx) + count
		total += count
	if effect._consumes_source_resource and effect.from != null and ("_buff_level" in effect.from):
		var lvl = effect.from._buff_level
		if lvl is BaseNumber:
			lvl.minus(BaseNumber.new(total))
	effect._chosen_selection = selection.duplicate()
	#选项使用事实：记下"谁用了哪个效果的哪一项"，供后续规则查询（如"本回合是否以令咒获得过魔力"）。
	#带选项标签，让查询按语义匹配而不是按下标——选项顺序或文案变化不会让规则静默失效
	for idx in selection.keys():
		if !(idx is int) or idx < 0 or idx >= effect._options.size():
			continue
		var opt:Dictionary = effect._options[idx]
		var tags:Array = (opt.get("tags", []) as Array).duplicate()
		tags.append("option_used")
		GameLog.record("option_used", effect._trigger_player_id, -1, "", effect, tags,
			{"effect_name": effect._name, "option_index": int(idx),
				"option_name": str(opt.get("shown_option_name", ""))})


#按选中的选择字典取要结算的funcs：次数>1的选项，其funcs重复追加相应次数
func get_chosen_funcs(effect:BaseEffect) -> Array:
	var result:Array = []
	for idx in effect._chosen_selection.keys():
		if !(idx is int) or idx < 0 or idx >= effect._options.size():
			continue
		var count:int = effect._chosen_selection[idx] as int
		var opt_funcs:Array = effect._options[idx].get("funcs", [])
		for i in range(count):
			result.append_array(opt_funcs)
	return result


func get_all_players_id():
	return GameData.player_data_library.keys()


#把-1解析成"当前效果的触发者"，供各effect的player_id参数使用，避免默认成本地玩家
func resolve_player_id(player_id:int) -> int:
	if player_id != -1:
		return player_id
	if activating_eff != null and activating_eff._trigger_player_id != -1:
		return activating_eff._trigger_player_id
	return GameData.player_id


#顺位
#按玩家数据里的order排序。order可被ChangePlOrder改动，所以顺位不等于玩家id
func get_player_order_ids() -> Array:
	var ids = get_all_players_id() as Array
	ids.sort_custom(func(a, b):
		var a_order = (GameDataManager.get_player_data(a)["order"] as BaseNumber).number
		var b_order = (GameDataManager.get_player_data(b)["order"] as BaseNumber).number
		if a_order != b_order:
			return a_order < b_order
		#order相同时用id兜底，保证排序是全序，结果可复现
		return int(a) < int(b)
	)
	return ids


func get_player_order_index(player_id:int) -> int:
	var i = get_player_order_ids().find(player_id)
	if i == -1:
		return GameData.player_max + 1
	return i


#效果池登记
#player_id不为-1时同时把效果登记为该玩家所有，并写入其self_effects供反查
func register_effect(effect:BaseEffect, player_id:int = -1):
	if effect == null:
		return
	if player_id != -1:
		effect._trigger_player_id = player_id
	if !effect_pool.has(effect):
		effect_pool.append(effect)
	if player_id != -1:
		var pl_data = GameDataManager.get_player_data(player_id) as Dictionary
		var self_effects = pl_data["self_effects"] as Array
		if !self_effects.has(effect):
			self_effects.append(effect)


func register_effects(effects:Array, player_id:int = -1):
	for effect in effects:
		if effect is BaseEffect:
			register_effect(effect, player_id)


#效果离场(卡牌被移除游戏等)时取消登记，之后的时点不再检查它
func unregister_effect(effect:BaseEffect):
	if effect == null:
		return
	effect_pool.erase(effect)
	decision_queue.erase(effect)
	activation_pool.erase(effect)
	matched_time_points.erase(effect)
	if waiting_effect == effect:
		waiting_effect = null
	if waiting_selection == effect:
		waiting_selection = null
		_waiting_selection_option = -1
		_pending_selection_choice.erase(effect)
	if waiting_location == effect:
		waiting_location = null
		_pending_location_choice.erase(effect)
	if waiting_players == effect:
		waiting_players = null
		_pending_player_choice.erase(effect)
	var id = effect._trigger_player_id
	if id != -1:
		var pl_data = GameDataManager.get_player_data(id) as Dictionary
		(pl_data["self_effects"] as Array).erase(effect)


#开局加载完的效果先全部入池，此时还没有归属玩家；
#选完御主/从者后再用register_effects(xx._effects, id)绑定归属
func sync_loaded_effect_pool():
	for effect in GameData.effects:
		register_effect(effect)


#时点流程
#进入一个新时点。调用方(TimePointChecker)负责先把各玩家的current_time_points更新好
func run_time_point(source = null):
	if is_running:
		#结算过程中派发的时点只追加效果，交由外层流程继续处理
		collect_current_effects(source)
		TimePointChecker.consume_transient_time_points()
		return
	if is_waiting_for_choice():
		_queue_time_point_batch(source)
		TimePointChecker.consume_transient_time_points()
		return
	time_point_id += 1
	decision_queue.clear()
	activation_pool.clear()
	matched_time_points.clear()
	resolved_effects.clear()
	closed_time_points.clear()
	countered_funcs.clear()
	waiting_effect = null
	collect_current_effects(source)
	# 匹配结果已经保存于效果快照；没有效果响应的瞬时事件也必须消费，
	# 否则下一次无来源的费用计算会重新触发上一张牌的出牌事件。
	TimePointChecker.consume_transient_time_points()
	run_pipeline()


func _queue_time_point_batch(source) -> void:
	var players: Dictionary = {}
	for id in get_all_players_id():
		var data: Dictionary = GameDataManager.get_player_data(id)
		players[id] = {
			"current": (data["current_time_points"] as Array).duplicate(),
			"dynamic": (data["dynamic_time_points"] as Array).duplicate()
		}
	_queued_time_point_batches.append({"source": source, "players": players})


func _run_next_queued_time_point() -> void:
	if is_waiting_for_choice() or _queued_time_point_batches.is_empty():
		return
	var batch: Dictionary = _queued_time_point_batches.pop_front()
	var players: Dictionary = batch.get("players", {})
	for id in players.keys():
		if not GameData.player_data_library.has(id):
			continue
		var data: Dictionary = GameDataManager.get_player_data(id)
		var snapshot: Dictionary = players[id]
		data["current_time_points"] = (snapshot.get("current", []) as Array).duplicate()
		data["dynamic_time_points"] = (snapshot.get("dynamic", []) as Array).duplicate()
	run_time_point(batch.get("source"))


#检查全局效果池，把本时点命中的效果按顺位排进待决定队列
func collect_current_effects(source = null):
	var newly_matched:Array = []
	# 到期注销会修改效果池，遍历快照避免跳过相邻效果。
	for effect:BaseEffect in effect_pool.duplicate():
		if effect._trigger_player_id == -1:
			continue
		#手动发动类效果(如令咒)不进自动询问队列：它只在玩家主动点击发动时才被询问，
		#否则会在每个命中时点自动弹窗问玩家用不用
		if effect._is_manual:
			continue
		if resolved_effects.has(effect):
			continue
		if decision_queue.has(effect) or activation_pool.has(effect):
			continue
		var matched = get_matched_time_points(effect)
		var expired: bool = false
		if not effect._expire_time_points.is_empty():
			var current_points = (GameDataManager.get_player_data(effect._trigger_player_id) as Dictionary)["current_time_points"] as Array
			for expire_point in effect._expire_time_points:
				if current_points.has(expire_point):
					expired = true
					break
		# 目标与到期同帧时目标优先；只有目标未命中才注销。
		if matched.is_empty() and expired:
			unregister_effect(effect)
			continue
		if !card_state_allows(effect):
			continue
		if source != null:
			var owner = effect.from.get_ref() if effect.from is WeakRef else effect.from
			if owner != source:
				matched.erase(TimePoints.CARD_ENTERED)
				if effect._source_bound:
					continue
		if matched.is_empty():
			continue
		#持续阶段窗口（self_action_phase / self_battle_phase / self_climax …）派发后会一直留在
		#玩家的时点表里，直到阶段轮转才被 clear_player_scope_time_points 清掉。同一阶段内
		#后续每个批次（战力结算、事件进场、战后选择…）都会再命中它，纯被动效果因此被反复执行
		#——实测言峰"战斗阶段：总威力+2"在同一个战斗阶段里叠到 8 点。这里按"窗口内只结算一次"过滤，
		#瞬时时点（PLAYED_CARD、MAGIC_ADD…）不受影响，仍然每次命中都算
		matched = _first_settlement_of_phase_windows(effect, matched)
		if matched.is_empty():
			continue
		matched_time_points[effect] = matched
		#快照触发上下文。start_effect会清空动态时点，所以要在结算前记下来，供When判断分支
		effect._trigger_time_points = matched.duplicate()
		newly_matched.append(effect)
	decision_queue.append_array(newly_matched)
	sort_by_turn_order(decision_queue)


#持续阶段窗口的结算记录：效果 → 本窗口内已结算过的窗口时点。
#窗口靠换行动者/换阶段轮转（由 TimePointChecker 调 reset_phase_window_settlements 清空），
#不随每个时点批次清，否则等于没去重
var settled_phase_windows:Dictionary = {}


## 只保留本窗口内"还没结算过"的持续窗口时点，瞬时时点原样通过。
## 缺了这一步，持续窗口会被同一阶段内的每个后续批次重复结算（威力类效果表现为暴涨）
func _first_settlement_of_phase_windows(effect:BaseEffect, matched:Array) -> Array:
	var result:Array = []
	var settled:Array = settled_phase_windows.get(effect, [])
	for tp in matched:
		var point := str(tp)
		if !TimePointChecker.is_persistent_player_window(point):
			result.append(tp)
			continue
		if settled.has(point):
			continue
		settled.append(point)
		result.append(tp)
	if !settled.is_empty():
		settled_phase_windows[effect] = settled
	return result


## 阶段窗口整体轮转（换行动者、换阶段、重开一局）时清空
func reset_phase_window_settlements() -> void:
	settled_phase_windows.clear()


#_need_activate表示"这个效果需不需要卡牌处于激活状态"。
#是否强制结算由_is_pure_passive控制，不绕过数据声明的激活要求。
func card_state_allows(effect:BaseEffect) -> bool:
	#声明了每局限一次的效果，本局已经触发过就不再进决断队列
	if effect._once_per_game and is_effect_used_once(effect):
		return false
	if !effect._need_activate:
		return true
	var owner = effect.from.get_ref() if effect.from is WeakRef else effect.from
	if owner is BaseHandCard:
		return (owner as BaseHandCard)._is_activating
	return true


#返回效果在其归属玩家的当前时点表里命中的所有时点。
#命中多个时，关掉其中一个不会让效果整体失效。
#AND模式(_time_points_require_all)下要求全部时点同时命中，任一未命中就返回空数组
#——用于"高潮回合且正处于自己行动阶段"这类需要两个时点同时成立的规则。
func get_matched_time_points(effect:BaseEffect) -> Array:
	var pl_data = GameDataManager.get_player_data(effect._trigger_player_id) as Dictionary
	var current_tps = pl_data["current_time_points"] as Array
	if effect._is_manual:
		#事件时点会被 start_effect 消耗；持续窗口按当前阶段/行动者重建，
		#只用于手动查询，不重派自动效果，也不恢复已消耗的事件时点。
		current_tps = current_tps.duplicate()
		var phase = GameProgress.get_current_phase()
		for phase_data in GameProgress.phases:
			for prefix in [TimePoints.SELF_PREFIX, TimePoints.OTHERS_PREFIX]:
				erase_all(current_tps, prefix + str(phase_data["mid"]))
		for tp in [TimePoints.CLIMAX, TimePoints.NON_CLIMAX]:
			for prefix in [TimePoints.SELF_PREFIX, TimePoints.OTHERS_PREFIX]:
				erase_all(current_tps, prefix + str(tp))
		if not phase.is_empty() and GameProgress.current_player_id >= 0:
			var prefix = TimePoints.SELF_PREFIX if effect._trigger_player_id == GameProgress.current_player_id else TimePoints.OTHERS_PREFIX
			for tp in [phase["mid"], TimePoints.CLIMAX if GameProgress.is_climax_round() else TimePoints.NON_CLIMAX]:
				if TimePointChecker.phase_time_points.has(tp):
					current_tps.append(prefix + str(tp))
	var closed = closed_time_points.get(effect._trigger_player_id, []) as Array
	var matched:Array = []
	for tp in effect._time_points:
		if closed.has(tp):
			if effect._time_points_require_all:
				return []
			continue
		if current_tps.has(tp):
			if !matched.has(tp):
				matched.append(tp)
		elif effect._time_points_require_all:
			return []
	return matched


#询问顺序：按顺位，同一玩家内按优先级
func sort_by_turn_order(effects:Array):
	var order = get_player_order_ids()
	effects.sort_custom(func(a:BaseEffect, b:BaseEffect):
		var a_index = order.find(a._trigger_player_id)
		var b_index = order.find(b._trigger_player_id)
		if a_index != b_index:
			return a_index < b_index
		if a._priority != b._priority:
			return a._priority < b._priority
		return effect_pool.find(a) < effect_pool.find(b)
	)


#结算顺序：按优先级，同一优先级按顺位
func sort_by_priority(effects:Array):
	var order = get_player_order_ids()
	effects.sort_custom(func(a:BaseEffect, b:BaseEffect):
		if a._priority != b._priority:
			return a._priority < b._priority
		var a_index = order.find(a._trigger_player_id)
		var b_index = order.find(b._trigger_player_id)
		if a_index != b_index:
			return a_index < b_index
		return effect_pool.find(a) < effect_pool.find(b)
	)


#主流程：先决定(交错)，再按优先级结算。结算中产生的新效果同样先决定再结算
func run_pipeline():
	is_running = true
	while true:
		#等玩家答复或被要求挑牌，由 submit_active_choice / submit_card_selection 继续跑
		if waiting_effect != null or waiting_selection != null or waiting_location != null or waiting_players != null:
			break
		if !decision_queue.is_empty():
			drain_decision_queue()
			continue
		if !activation_pool.is_empty():
			resolve_one()
			continue
		break
	is_running = false
	#本时点的效果都结算完了：把攒下的效果提示合并成一条推给玩家。
	#放在这里而不是每个效果各推一条——同一时点连续触发的一批效果只弹一次
	_flush_announcements()
	if not is_waiting_for_choice():
		_run_next_queued_time_point()


#被动直接按顺位加入效果池，不询问；遇到需要玩家决定的效果就停下等答复
func drain_decision_queue():
	while !decision_queue.is_empty():
		var effect = decision_queue[0] as BaseEffect
		if is_pruned(effect):
			decision_queue.pop_front()
			continue
		if effect._is_pure_passive:
			decision_queue.pop_front()
			add_to_activation_pool(effect)
			continue
		#选项类效果所有选项都已耗尽用量：没有可选的分支，直接视为放弃，不打扰玩家
		if effect.has_options() and !has_available_options(effect):
			decision_queue.pop_front()
			continue
		waiting_effect = effect
		return


#当前正在等待答复的效果，null表示没有待决定的效果
func get_pending_active_effect() -> BaseEffect:
	return waiting_effect


#本局是否已经触发过这个效果。直接查效果日志，不再另存一份 used_once_effects——
#日志本来就是"发生过什么"的唯一出处
func is_effect_used_once(effect:BaseEffect) -> bool:
	if effect == null:
		return false
	var id:int = effect._trigger_player_id
	if id < 0:
		return false
	return !GameLog.query({"type": "effect", "actor": id, "data": {"effect_name": effect._name}}, null).is_empty()


#效果自己的消耗(effect._cost)付不付得起——纯查询，不改任何状态。
#与 pay_effect_cost 共用同一份判断：界面按它决定"能不能发动"，结算按它决定扣不扣，
#两边不会出现"提示能发动、真发动时却付不起"的分裂。
#消耗形状由数据声明：{"number":N}是魔力数字消耗；{"type":"command_spell","amount":N}是令咒消耗；
#未识别的 type 一律放行——缺声明不给行为，避免新资源形状悄悄拦住老效果
func can_pay_effect_cost(effect:BaseEffect) -> bool:
	if effect == null:
		return true
	var cost = effect._cost
	if cost == null:
		return true
	var id:int = effect._trigger_player_id
	if id < 0:
		id = GameData.player_id
	#数字形状：与卡牌费用同构的魔力消耗。无限魔力(is_magic_immune)视为付得起
	if cost is BaseNumber:
		if cost.number <= 0:
			return true
		var player_data:Dictionary = GameDataManager.get_player_data(id)
		if player_data == null or player_data.is_empty():
			return false
		if player_data.get("is_magic_immune", false):
			return true
		var magic = player_data["magic"] as BaseNumber
		return magic != null and magic.number >= cost.number
	#其他资源形状：type 声明消耗哪种资源，amount 声明数量
	if cost is Dictionary and cost.has("type"):
		#令咒不是魔力，is_magic_immune 是"魔力免疫"，不豁免令咒消耗
		if str(cost["type"]) != "command_spell":
			return true
		var count:int = int(cost.get("amount", 0))
		if count <= 0:
			return true
		var pl_data:Dictionary = GameDataManager.get_player_data(id)
		if pl_data == null or pl_data.is_empty():
			return false
		var spells = pl_data["command_spell_count"] as BaseNumber
		return spells != null and spells.number >= count
	return true


#效果自己的消耗(effect._cost)：付得起返回true并扣掉，付不起返回false。
#能不能付由 can_pay_effect_cost 判断，这里只负责扣减。
#魔力消耗与卡牌出牌同一套规则：无限魔力(is_magic_immune)状态下不检查也不扣；
#扣费复用EditMagic，让魔力变化照常派发MAGIC_DECREASE时点。
#令咒消耗扣command_spell_count并派发COMMAND_SPELL_USED时点
func pay_effect_cost(effect:BaseEffect) -> bool:
	if !can_pay_effect_cost(effect):
		return false
	if effect == null or effect._cost == null:
		return true
	var cost = effect._cost
	var id:int = effect._trigger_player_id
	if id < 0:
		id = GameData.player_id
	if cost is BaseNumber:
		if cost.number <= 0:
			return true
		var player_data:Dictionary = GameDataManager.get_player_data(id)
		if player_data == null or player_data.is_empty():
			return false
		if player_data.get("is_magic_immune", false):
			return true
		EditMagic.new().exec(null, BaseNumber.new(0 - cost.number), id)
		return true
	if cost is Dictionary and cost.has("type"):
		if str(cost["type"]) != "command_spell":
			return true
		return _pay_command_spell_cost(effect, int(cost.get("amount", 0)))
	return true


#令咒消耗：扣玩家的command_spell_count，记日志并派发COMMAND_SPELL_USED时点。
#数量不足时拒绝且不扣。count为0视为没声明，直接放行
func _pay_command_spell_cost(effect:BaseEffect, count:int) -> bool:
	if count <= 0:
		return true
	var id:int = effect._trigger_player_id
	if id < 0:
		id = GameData.player_id
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	if player_data == null or player_data.is_empty():
		return false
	var spells = player_data["command_spell_count"] as BaseNumber
	if spells == null or spells.number < count:
		return false
	spells.minus(BaseNumber.new(count))
	GameLog.record("command_spell_used", id, -1, "", effect, ["command_spell_used"],
		{"amount": count})
	TimePointChecker.dynamic_time_point([TimePoints.COMMAND_SPELL_USED], id)
	return true


#正在等待玩家挑牌的效果信息，供界面生成选牌面板；没有等待时返回空字典
func get_pending_card_selection() -> Dictionary:
	if waiting_selection == null:
		return {}
	var spec := card_selection_spec(waiting_selection)
	return {
		"effect" : waiting_selection,
		"shown_name" : waiting_selection.get_shown_name(),
		"min" : int(spec.get("min", 1)),
		"max" : int(spec.get("max", 1)),
		"cards" : card_selection_source(waiting_selection)
	}


func is_waiting_for_card_selection() -> bool:
	return waiting_selection != null


#当前等待挑牌的这次声明的选牌要求（选项级）。没有等待或该项没声明时返回空字典
func card_selection_spec(effect:BaseEffect) -> Dictionary:
	if effect == null or _waiting_selection_option < 0 or _waiting_selection_option >= effect._options.size():
		return {}
	var spec = effect._options[_waiting_selection_option].get("select_cards", null)
	if !(spec is Dictionary):
		return {}
	return spec


#挑牌的来源数组：按声明的 source（player_data 的键名）取。
#来源由数据声明而不是写死手牌——以后"从弃牌堆挑一张"之类不必改这里
# "挑谁的牌"同样由声明决定：owner 写 target_player 时取先由 select_players 选定的那名玩家；
# 未声明时保持原语义（触发者自己），既有卡不受影响
func card_selection_source(effect:BaseEffect) -> Array:
	if effect == null:
		return []
	var spec := card_selection_spec(effect)
	var key := str(spec.get("source", ""))
	if key == "":
		return []
	var owner_id:int = effect._trigger_player_id
	if str(spec.get("owner", "")) == CARD_SELECTION_OWNER_TARGET:
		owner_id = effect._selected_player
	if owner_id < 0:
		return []
	var pl_data = GameDataManager.get_player_data(owner_id) as Dictionary
	if pl_data == null or !pl_data.has(key):
		return []
	var arr = pl_data[key]
	if !(arr is Array):
		return []
	#可选的属性筛选：卡面「从手牌打出一张力量基础攻击」这类限定由数据声明，
	#候选里就不会出现选不了的目标（与 select_players 的候选集同一口径：
	#范围由数据算，引擎不认识任何具体牌型）
	var wanted = spec.get("attributes", null)
	if wanted is Array and !wanted.is_empty():
		arr = GetCardsByAttributesFrArr.new().exec(wanted, arr)
	#可选的印刷威力上限：卡面「打出至多3张基本威力为3或更低的手牌」这类限定，
	#与 attributes 同属"候选范围由数据算"（引擎不认识具体牌型，也不写死数字）
	var max_power = spec.get("max_power", null)
	if max_power != null:
		var kept:Array = []
		for card in arr:
			if card is BaseAttack and (card._power as BaseNumber).number <= int(max_power):
				kept.append(card)
		arr = kept
	return arr


#本次提交里第一个"还要求玩家挑牌"的选项下标（没有则 -1）。
#一次提交只处理一个：当前规则一次只选一项，多选场景下"挑完一个再问下一个"不属于本函数职责
func _option_requiring_card_selection(effect:BaseEffect, selection:Dictionary) -> int:
	for idx in selection.keys():
		if !(idx is int) or idx < 0 or idx >= effect._options.size():
			continue
		var spec = effect._options[idx].get("select_cards", null)
		if spec is Dictionary and int(spec.get("max", 1)) != 0:
			return idx
	return -1


# 位置选择与 select_cards 同为选项级的延迟输入；只有选项显式声明才会等待。
func _option_requiring_location_selection(effect:BaseEffect, selection:Dictionary) -> int:
	for idx in selection.keys():
		if !(idx is int) or idx < 0 or idx >= effect._options.size():
			continue
		if effect._options[idx].get("select_location", null) is Dictionary:
			return idx
	return -1


#玩家目标选择同样是选项级延迟输入：只有选项声明了 select_players 才会等待
func _option_requiring_player_selection(effect:BaseEffect, selection:Dictionary) -> int:
	for idx in selection.keys():
		if !(idx is int) or idx < 0 or idx >= effect._options.size():
			continue
		if effect._options[idx].get("select_players", null) is Dictionary:
			return idx
	return -1


#候选玩家集由选项声明的 candidates 求值得到：那段声明是普通 func 描述（可写多条），
#用与效果链完全相同的求值入口跑，把每条返回的数组并起来即候选id。
#候选范围（同战区、在场、某职阶拥有者…）全部由数据决定，引擎不认识任何具体范围
func get_player_selection_candidates(spec:Dictionary, effect:BaseEffect) -> Array:
	var ids:Array = []
	var descs = spec.get("candidates", [])
	if descs is Dictionary or descs is String:
		descs = [descs]
	if !(descs is Array):
		return ids
	#求值要在"本效果为当前效果"的上下文里进行：候选声明里的 -1 表示"效果的触发者"，
	#而查询可能发生在还没激活时（如选项可选性判断）。临时置上下文并在结束后还原，
	#这样候选声明与效果链用同一套 player_id 约定，数据不必为"查询时点"换写法
	var prev_eff = activating_eff
	activating_eff = effect
	for desc in descs:
		if !(desc is Dictionary) and !(desc is BaseFunc):
			continue
		var res:Array = run_func_descriptor(desc, effect)
		if !res[0] or !(res[1] is Array):
			continue
		for raw_id in res[1]:
			var id:int = int(raw_id)
			if GameData.player_data_library.has(id) and !ids.has(id):
				ids.append(id)
	activating_eff = prev_eff
	return ids


func get_pending_player_selection() -> Dictionary:
	if waiting_players == null:
		return {}
	var pending:Dictionary = _pending_player_choice.get(waiting_players, {})
	var option_index:int = int(pending.get("option", -1))
	if option_index < 0 or option_index >= waiting_players._options.size():
		return {}
	var spec:Dictionary = waiting_players._options[option_index].get("select_players", {})
	return {"effect": waiting_players, "spec": spec,
		"candidates": get_player_selection_candidates(spec, waiting_players)}


#提交玩家目标选择，仍在支付前。校验两条：人数落在声明范围内、每个目标都在候选集里。
#不合法时整体按"放弃"处理（与选牌一致），避免 UI 传坏数据时结算到不该结算的目标
func submit_player_selection(effect:BaseEffect, players:Array) -> bool:
	if effect == null or waiting_players != effect:
		return false
	var pending:Dictionary = _pending_player_choice.get(effect, {})
	var option_index:int = int(pending.get("option", -1))
	var selection:Dictionary = pending.get("selection", {})
	waiting_players = null
	_pending_player_choice.erase(effect)
	if option_index < 0 or option_index >= effect._options.size() or selection.is_empty():
		if !is_running: run_pipeline()
		return false
	var spec:Dictionary = effect._options[option_index].get("select_players", {})
	var candidates:Array = get_player_selection_candidates(spec, effect)
	var min_count:int = int(spec.get("min", 1))
	var max_count:int = int(spec.get("max", min_count))
	var picked:Array = []
	for raw_id in players:
		var id:int = int(raw_id)
		if !candidates.has(id) or picked.has(id):
			if !is_running: run_pipeline()
			return false
		picked.append(id)
	if picked.size() < min_count or (max_count != -1 and picked.size() > max_count):
		if !is_running: run_pipeline()
		return false
	effect._selected_players = picked
	effect._selected_player = int(picked[0]) if picked.size() == 1 else -1
	#同一个选项可以同时要求"选玩家"和"选这名玩家的牌"（如"关闭一名交战玩家至多一张基础攻击"）：
	#先记下目标，再转成等待选牌；支付与用量留到挑完牌，语义与只声明 select_cards 时一致
	#（挑完才扣资源、取消或提交不合法等于这个效果没发动）
	if effect._options[option_index].get("select_cards", null) is Dictionary:
		waiting_selection = effect
		_waiting_selection_option = option_index
		_pending_selection_choice[effect] = selection
		return true
	if !pay_effect_cost(effect):
		if !is_running: run_pipeline()
		return false
	record_selection_usage(effect, selection)
	add_to_activation_pool(effect)
	if !is_running: run_pipeline()
	return true


func get_pending_location_selection() -> Dictionary:
	if waiting_location == null:
		return {}
	var pending:Dictionary = _pending_location_choice.get(waiting_location, {})
	var option_index:int = int(pending.get("option", -1))
	if option_index < 0 or option_index >= waiting_location._options.size():
		return {}
	return {"effect": waiting_location, "spec": waiting_location._options[option_index].get("select_location", {})}


# 位置选择提交仍在支付前；起点由选项声明的 allowed_origin_areas 校验，目标只要求是地图上的位置。
func submit_location_selection(effect:BaseEffect, location:BaseLocation) -> bool:
	if effect == null or waiting_location != effect:
		return false
	var pending:Dictionary = _pending_location_choice.get(effect, {})
	var option_index:int = int(pending.get("option", -1))
	var selection:Dictionary = pending.get("selection", {})
	waiting_location = null
	_pending_location_choice.erase(effect)
	#null 是显式取消位置选择：等待必须清掉，否则 AI/无界面推进会永久卡在这里。
	#与选牌/选玩家的非法或放弃提交同一口径，不支付费用、不记录用量。
	if location == null:
		if !is_running: run_pipeline()
		return false
	if option_index < 0 or option_index >= effect._options.size() or selection.is_empty():
		if !is_running: run_pipeline()
		return false
	var spec:Dictionary = effect._options[option_index].get("select_location", {})
	var origin:BaseLocation = GetLocation.new().exec(effect._trigger_player_id)
	var origin_area:BaseMapArea = origin.get_from() as BaseMapArea if origin != null else null
	var allowed:Array = spec.get("allowed_origin_areas", []) as Array
	if origin_area == null or !(location.get_from() is BaseMapArea):
		if !is_running: run_pipeline()
		return false
	if !allowed.is_empty() and !allowed.has(str(origin_area._area_name)):
		if !is_running: run_pipeline()
		return false
	#目标区域的排除同样由数据声明（卡面「移动至除魔术工房外的任意地点」这类限定），
	#与 allowed_origin_areas 对称：范围由数据算，引擎不认识具体区域名
	var target_area:BaseMapArea = location.get_from() as BaseMapArea
	var forbidden:Array = spec.get("forbidden_target_areas", []) as Array
	if target_area != null and forbidden.has(str(target_area._area_name)):
		if !is_running: run_pipeline()
		return false
	effect._selected_location = location
	if !pay_effect_cost(effect):
		if !is_running: run_pipeline()
		return false
	record_selection_usage(effect, selection)
	add_to_activation_pool(effect)
	if !is_running: run_pipeline()
	return true


#玩家为选牌提交了具体牌张。张数或来源不合法时整体视为放弃：
#此刻资源与用量都还没动过，所以放弃等价于"这个效果没发动"，不会白扣宝石层数
func submit_card_selection(effect:BaseEffect, cards:Array) -> bool:
	if effect == null or waiting_selection != effect:
		return false
	#声明与来源必须在清掉等待状态之前取好：card_selection_spec 依赖 _waiting_selection_option，
	#先清状态再校验会取到空声明、让合法提交也被判非法
	var spec := card_selection_spec(effect)
	var source := card_selection_source(effect)
	var pending:Dictionary = _pending_selection_choice.get(effect, {})
	waiting_selection = null
	_waiting_selection_option = -1
	_pending_selection_choice.erase(effect)
	if spec.is_empty() or !_is_card_selection_valid(spec, source, cards):
		effect._selected_cards = []
		if !is_running:
			run_pipeline()
		return false
	effect._selected_cards = cards.duplicate()
	#挑完牌才真正记用量/扣来源资源，然后把效果交给结算
	if !pay_effect_cost(effect):
		effect._selected_cards = []
		if !is_running:
			run_pipeline()
		return false
	record_selection_usage(effect, pending)
	decision_queue.erase(effect)
	add_to_activation_pool(effect)
	if !is_running:
		run_pipeline()
	return true


#spec 与 source 都由调用方先取好再传进来：这个判断本身不读等待状态，
#免得"先清状态后校验"的顺序问题又把合法提交判成非法
func _is_card_selection_valid(spec:Dictionary, source:Array, cards:Array) -> bool:
	var low:int = int(spec.get("min", 1))
	var high:int = int(spec.get("max", low))
	if cards.size() < low:
		return false
	if high != -1 and cards.size() > high:
		return false
	var picked:Array = []
	for card in cards:
		#必须来自声明的来源区，且同一张牌不能重复提交
		if card == null or !source.has(card) or picked.has(card):
			return false
		picked.append(card)
	return true


func is_waiting_for_choice() -> bool:
	return waiting_effect != null or waiting_selection != null or waiting_location != null or waiting_players != null


#玩家此刻能不能主动发动这个手动效果。判据全部复用既有规则：
#效果自己声明了 is_manual、属于该玩家、没有别的答复/挑牌在等、
#卡状态允许(每局限一次、每回合一次等)、付得起自己的消耗、
#且当前时点命中它自己声明的发动窗口(time_points 在这类效果上是"允许发动的时机窗口")。
#界面提示与点击入口共用这一个判据，避免出现"看起来能发动、点下去没反应"
func can_manual_activate(effect:BaseEffect, player_id:int) -> bool:
	if effect == null or !effect._is_manual:
		return false
	if player_id < 0 or effect._trigger_player_id != player_id:
		return false
	if waiting_effect != null or waiting_selection != null or waiting_location != null or waiting_players != null:
		return false
	if !card_state_allows(effect):
		return false
	# 选项全都不可用（前置条件不满足/次数耗尽）时不询问：这条能力此刻没有可做的事，
	# 进入询问只会让玩家点开一个什么都选不了的窗口
	if effect.has_options() and !has_available_options(effect):
		return false
	if !can_pay_effect_cost(effect):
		return false
	return !get_matched_time_points(effect).is_empty()


#这个玩家此刻有没有"能点着发动"的手动效果。
#战斗阶段与准备好阶段没有点击类操作，界面靠它决定"跳过这个玩家"还是"停下来等他点"——
#只看有没有正在等待的答复会漏掉"还没点、但点得动"的情况：宝石这类手动效果
#不会自己进等待队列，必须等玩家点击才产生等待。
#判据与点击入口、金框提示共用 can_manual_activate，不另写一套
func has_manual_activation(player_id:int) -> bool:
	return not manual_activations(player_id).is_empty()


#列出这个玩家此刻能点着发动的所有手动效果。
#AI 决策与界面停驻判断共用它；判据与点击入口完全同源，不另写一套
func manual_activations(player_id:int) -> Array:
	var result:Array = []
	if player_id < 0:
		return result
	for effect in effect_pool:
		if not (effect is BaseEffect) or not effect._is_manual:
			continue
		if can_manual_activate(effect, player_id):
			result.append(effect)
	return result


#玩家主动发动一个手动效果(如令咒)：把它排进待答复队列，之后的询问、选项弹窗、
#费用支付、放弃语义、用量计数全部走与自动触发效果相同的那条链路。
#返回是否真的开始询问
func request_manual_activation(effect:BaseEffect, player_id:int) -> bool:
	if !can_manual_activate(effect, player_id):
		return false
	matched_time_points[effect] = get_matched_time_points(effect)
	effect._trigger_time_points = matched_time_points[effect].duplicate()
	#新的一次主动请求不是同一批次里的自动重触发。
	resolved_effects.erase(effect)
	if !decision_queue.has(effect):
		decision_queue.append(effect)
		sort_by_turn_order(decision_queue)
	if !is_running:
		run_pipeline()
	return true


#玩家答复。should_activate为false也算走完流程
#——规则里带"你可以"的效果即使不发动，依旧视为遵循了规则
func submit_active_choice(effect:BaseEffect, should_activate:bool) -> bool:
	if effect == null or waiting_effect != effect:
		return false
	decision_queue.erase(effect)
	waiting_effect = null
	if !should_activate:
		#拒绝在本窗口内即放弃：这里必须记一笔，否则 run_pipeline 会立刻把同一个自动效果
		#重新收进决策队列，"拒绝→重问"无限循环，整局卡死（实测：一个没有效果体的空壳效果
		#在战斗阶段能把对局永久卡在第2回合）。窗口轮转由 reset_phase_window_settlements 统一清理，
		#与纯被动效果"窗口内只结算一次"同一口径；玩家之后主动请求会 erase 掉这笔记录（见
		#request_manual_activation），所以拒绝不封死再次发动的机会
		resolved_effects[effect] = "declined"
	if should_activate:
		#付不起效果自己声明的魔力消耗就当作放弃，避免结算到一半才发现扣不动
		if !pay_effect_cost(effect):
			if !is_running:
				run_pipeline()
			return false
		add_to_activation_pool(effect)
	if !is_running:
		run_pipeline()
	return true


#选项类效果的玩家答复。selection可以是：
#  - Array[int]：下标数组，每项默认用1次(简单单选/多选场景，如令咒三选一)
#  - Dictionary{下标:次数}：同一下标可以要求用多次(一次提交里连用同一选项多次)
#校验不通过(超过用量上限/来源资源不够)时整体视为放弃，避免UI传坏数据时结算到不该结算的分支
func submit_option_choice(effect:BaseEffect, selection) -> bool:
	if effect == null or waiting_effect != effect:
		return false
	var selection_dict:Dictionary = {}
	if selection is Array:
		for idx in selection:
			selection_dict[idx] = selection_dict.get(idx, 0) + 1
	elif selection is Dictionary:
		selection_dict = selection
	else:
		return submit_active_choice(effect, false)
	if !validate_selection(effect, selection_dict):
		return submit_active_choice(effect, false)
	#发动条件先于任何延迟选择、用量记录和资源支付；失败按放弃处理，提示由数据声明。
	if !_option_activation_requirements_met(effect, selection_dict):
		return submit_active_choice(effect, false)
	#选玩家必须排在选牌之前：同一个选项可以声明"选玩家 + 选那名玩家的牌"，
	#选牌要拿 _selected_player 去定位来源区，顺序反了会先停下等选牌却没有目标。
	#只声明其中一项时另一项判为 -1，顺序调整对既有卡没有影响
	var player_option := _option_requiring_player_selection(effect, selection_dict)
	if player_option != -1:
		decision_queue.erase(effect)
		waiting_effect = null
		waiting_players = effect
		_pending_player_choice[effect] = {"selection": selection_dict, "option": player_option}
		return true
	#选中的选项还要求玩家挑具体牌张时，先停下等挑牌：
	#此刻刻意不记用量也不扣来源资源，玩家取消挑牌时等于"这个效果没发动"，不会白扣
	var selection_option := _option_requiring_card_selection(effect, selection_dict)
	if selection_option != -1:
		decision_queue.erase(effect)
		waiting_effect = null
		waiting_selection = effect
		_waiting_selection_option = selection_option
		_pending_selection_choice[effect] = selection_dict
		return true
	var location_option := _option_requiring_location_selection(effect, selection_dict)
	if location_option != -1:
		decision_queue.erase(effect)
		waiting_effect = null
		waiting_location = effect
		_pending_location_choice[effect] = {"selection": selection_dict, "option": location_option}
		return true
	record_selection_usage(effect, selection_dict)
	return submit_active_choice(effect, true)


func add_to_activation_pool(effect:BaseEffect):
	if effect == null or activation_pool.has(effect):
		return
	activation_pool.append(effect)
	sort_by_priority(activation_pool)


#结算效果池里优先级最高的一个。一次只结算一个，
#这样它关闭时点或反制其他效果的结果能立刻影响后面还没结算的效果
func resolve_one():
	while !activation_pool.is_empty():
		var effect = activation_pool.pop_front() as BaseEffect
		if is_pruned(effect):
			continue
		if resolved_effects.has(effect):
			continue
		#优先级为-1是未填写的占位符，跳过不结算
		if effect._priority < 0:
			continue
		resolved_effects[effect] = time_point_id
		activating_eff = effect
		activate_effect(effect)
		activating_eff = null
		return


#时点关闭
#关闭某个时点(如结束其他玩家的回合)。因该时点触发、且没有其他命中时点的效果会被打断。
#已经结算完的效果不回滚——规则里没有回退机制。player_id为-1表示关闭所有玩家的该时点
func close_time_point(time_point:String, player_id:int = -1):
	var ids:Array = []
	if player_id != -1:
		ids.append(player_id)
	else:
		ids = get_all_players_id()
	for id in ids:
		var closed = closed_time_points.get(id, []) as Array
		if !closed.has(time_point):
			closed.append(time_point)
		closed_time_points[id] = closed
		var pl_data = GameDataManager.get_player_data(id) as Dictionary
		erase_all(pl_data["current_time_points"] as Array, time_point)
		erase_all(pl_data["dynamic_time_points"] as Array, time_point)
	prune_closed()


func is_time_point_closed(time_point:String, player_id:int) -> bool:
	var closed = closed_time_points.get(player_id, []) as Array
	return closed.has(time_point)


func erase_all(arr:Array, value):
	var i = arr.find(value)
	while i != -1:
		arr.remove_at(i)
		i = arr.find(value)


#把被关闭的时点从各效果的命中集合里剔除，命中集合空掉的效果就被打断
func prune_closed():
	for effect in matched_time_points.keys():
		var matched = matched_time_points[effect] as Array
		var closed = closed_time_points.get(effect._trigger_player_id, []) as Array
		for tp in closed:
			erase_all(matched, tp)
		if matched.is_empty():
			decision_queue.erase(effect)
			activation_pool.erase(effect)
			#正在等待答复或等待挑牌的效果也一并打断
			if waiting_effect == effect:
				waiting_effect = null
			if waiting_selection == effect:
				waiting_selection = null
				_waiting_selection_option = -1
				_pending_selection_choice.erase(effect)


func is_pruned(effect:BaseEffect) -> bool:
	if !matched_time_points.has(effect):
		return false
	return (matched_time_points[effect] as Array).is_empty()


#反制
#countered_func留空时整个效果不结算；否则只跳过其中一个func，效果里其余func照常
func counter_effect(effect:BaseEffect, countered_func:BaseFunc = null):
	if effect == null:
		return
	if countered_func == null:
		decision_queue.erase(effect)
		activation_pool.erase(effect)
		if waiting_effect == effect:
			waiting_effect = null
		if waiting_selection == effect:
			waiting_selection = null
			_waiting_selection_option = -1
			_pending_selection_choice.erase(effect)
		return
	var funcs = countered_funcs.get(effect, []) as Array
	if !funcs.has(countered_func):
		funcs.append(countered_func)
	countered_funcs[effect] = funcs


func is_func_countered(effect:BaseEffect, _func:BaseFunc) -> bool:
	if !countered_funcs.has(effect):
		return false
	return (countered_funcs[effect] as Array).has(_func)


#效果执行
#只管理时点上下文，不推进回合，也不再维护效果批次索引
func start_effect():
	TimePointChecker.consume_transient_time_points()


func end_effect():
	TimePointChecker.time_point_check()


#把占位符解析成实际值。{"number_index":i}取效果自带的数字，{"self_var":i}取前面func存下的返回值，
#{"option_quantity_index":i}取第 i 个选项本次玩家额外选定的数量(选项声明了quantity_range才有)。
#返回[是否解析成功, 值]，越界或下标为-1、或该项数量没被玩家设定时视为失败
func resolve_placeholder(para, effect:BaseEffect) -> Array:
	if !(para is Dictionary):
		return [true, para]

	if para.has("number_index"):
		var i = para["number_index"] as int
		if i < 0 or i >= effect._using_numbers.size():
			return [false, null]
		return [true, effect._using_numbers[i]]

	if para.has("option_quantity_index"):
		var oi = para["option_quantity_index"] as int
		if oi < 0 or oi >= effect._options.size():
			return [false, null]
		#玩家没为这项设定过数量(0)时视为失败：调用方通常用 for_func 按数量重复，
		#数量为0本就该什么都不做，不必让调用方再写一层条件
		var qty := effect.get_option_quantity(oi)
		if qty <= 0:
			return [false, null]
		return [true, qty]

	if para.has("self_var"):
		var i = para["self_var"] as int
		if i < 0 or i >= effect._self_vars.size():
			return [false, null]
		return [true, effect._self_vars[i]]

	return [true, para]


#判断func的执行条件是否成立
func check_condition(_func:BaseFunc, effect:BaseEffect) -> bool:
	if _func._condition == null:
		return true
	var resolved = resolve_placeholder(_func._condition, effect)
	if !resolved[0]:
		return false
	var value = resolved[1]
	if value is BaseNumber:
		return value.number != 0
	return bool(value)


#执行单个BaseFunc：反制检查、条件检查、延迟绑定、参数解析、调用、写回var_index。
#抽成公共入口，好让循环类operation(ForFunc/ForeachFunc/WhileFunc)复用同一套规则，
#而不是直接调callable绕开self_var/number_index/condition。
#返回[是否真正调用了callable, 调用结果]；未调用时结果为null
func run_base_func(f:BaseFunc, effect:BaseEffect) -> Array:
	var raw_params:Array = f._parameters.duplicate()
	#没真正调用的失败也留一条记录，否则分不清"JSON 没执行"与"条件没满足"。
	#先落记录再立刻结束，call_id 才连续、父子关系也不断
	if is_func_countered(effect, f):
		GameLog.end_func_call(GameLog.begin_func_call(effect, f._name, raw_params, []), null, "countered")
		return [false, null]
	if !check_condition(f, effect):
		GameLog.end_func_call(GameLog.begin_func_call(effect, f._name, raw_params, []), null, "condition_false")
		return [false, null]

	var callable = f._func
	#延迟绑定的方法调用，目标对象此刻才从变量表里取出
	if f._self_var_index != -1:
		if f._self_var_index >= effect._self_vars.size():
			GameLog.end_func_call(GameLog.begin_func_call(effect, f._name, raw_params, []), null, "invalid_target")
			return [false, null]
		var target = effect._self_vars[f._self_var_index]
		if target == null or !target.has_method(f._method_name):
			GameLog.end_func_call(GameLog.begin_func_call(effect, f._name, raw_params, []), null, "invalid_target")
			return [false, null]
		callable = Callable(target, f._method_name)
	if !callable.is_valid():
		GameLog.end_func_call(GameLog.begin_func_call(effect, f._name, raw_params, []), null, "invalid_callable")
		return [false, null]

	var paras = f._parameters.duplicate()
	var paras_ready:bool = true
	for i in paras.size():
		var resolved = resolve_placeholder(paras[i], effect)
		if !resolved[0]:
			paras_ready = false
			break
		paras[i] = resolved[1]
	#参数解析不出来就跳过这个func，但效果里后续的func照常处理
	if !paras_ready:
		GameLog.end_func_call(GameLog.begin_func_call(effect, f._name, raw_params, []), null, "invalid_parameter")
		return [false, null]

	#先落记录再调用：嵌套进来的 func 才会排在本条之后、parent 指向本条
	var call_id:int = GameLog.begin_func_call(effect, f._name, raw_params, paras)
	var result = callable.callv(paras)
	if f._var_index != -1:
		while effect._self_vars.size() <= f._var_index:
			effect._self_vars.append(null)
		effect._self_vars[f._var_index] = result
	GameLog.end_func_call(call_id, result, "executed")
	return [true, result]


#按JSON可表达的函数描述{"func_name":.., "parameters":[..], "var_index":-1, "condition":null}
#动态加载operation并执行，规则与load_game.gd里加载func_name的方式一致。
#兼容直接传入BaseFunc(内部/旧代码构造的循环体)。
#用于循环体这类"JSON里无法直接构造BaseFunc/Callable"的场合，
#让self_var既能传数组/次数，也能传循环体本身需要的参数。
#返回同run_base_func：[是否真正调用了callable, 调用结果]
func run_func_descriptor(desc, effect:BaseEffect) -> Array:
	if desc is BaseFunc:
		return run_base_func(desc, effect)

	if !(desc is Dictionary):
		return [false, null]

	var key = desc.get("func_name", "") as String
	if key == "":
		return [false, null]
	var _class_name = LoadHelper.func_name_to_class_name(key)
	var func_path = "res://assets/scripts/system/operations/" + _class_name + ".gd"
	if !ResourceLoader.exists(func_path):
		print("没有操作:" + "'" + key + "'")
		GameLog.end_func_call(GameLog.begin_func_call(effect, key, desc.get("parameters", []), []), null, "missing_operation")
		return [false, null]

	var func_instance = load(func_path).new()
	var main_callable = Callable(func_instance, "exec")
	var paras = desc.get("parameters", []) as Array
	var var_index = desc.get("var_index", -1) as int
	var condition = desc.get("condition", null)
	var _func = BaseFunc.new(main_callable, paras, var_index, condition)
	#Callable不会保活实例，必须由func自己持有引用，否则调用完就被释放
	_func._instance = func_instance
	_func._name = key

	return run_base_func(_func, effect)


func activate_effect(effect:BaseEffect):
	#一次结算的执行编号：名下所有 func 日志都带同一个 execution_id。
	#收栈时按编号定位，中途抛错没走到的执行不会留在栈上
	var execution_id:int = GameLog.begin_execution()
	start_effect()
	#每次激活都从空白的变量表开始，避免读到上一次激活的残留值
	effect._self_vars = []
	#手动发动的结果要写清"谁/哪个对象被改了什么"：结算前后各取一次规则状态快照，
	#差值就是这次发动的实际影响（与卡面文案无关，条件不满足时差值为空）
	var state_before:Dictionary = capture_rule_state() if effect._is_manual else {}

	#多选一效果结算选中分支的funcs，不结算effect自身的_funcs(那里本就是空的)
	var funcs_to_run:Array = get_chosen_funcs(effect) if effect.has_options() else effect._funcs
	var applied: bool = false
	for f:BaseFunc in funcs_to_run:
		var outcome: Array = run_base_func(f, effect)
		if bool(outcome[0]) and f._var_index == -1 and f._name != "do_nothing":
			applied = true

	end_effect()
	GameLog.end_execution(execution_id)
	#日志：这个效果本局触发过了。"每局限一次"的判断也从这里查，
	#不再另外维护一份 used_once_effects
	GameLog.record("effect", _effect_fact_actor_id(effect), -1, "", effect, ["effect"],
		{"effect_name": effect._name, "shown_effect": str(effect._shown_name),
		 "source_name": _effect_source_name(effect), "applied": applied,
		 "trigger_time_points": effect._trigger_time_points.duplicate()})
	# 手动发动即使没有产生即时数值变化，也要给玩家交代结算结果。
	# applied 只表示执行了写入型函数，不表示玩家没有确认发动。
	if applied or effect._is_manual:
		var changes:Array = diff_rule_state(state_before, capture_rule_state()) if effect._is_manual else []
		_announce_effect(effect, changes)
	if effect._remove_after_trigger:
		unregister_effect(effect)


#效果结算完后统一告知玩家"谁因为什么受到了什么效果"。
#放在这一处而不是各效果自己推：所有效果（自己的、他人的、事件牌、局势牌、buff）
#都经由 activate_effect 结算，一处接线即全量覆盖。
#只推有卡面文案的效果：没有 shown_name 的是系统内部效果（禁令声明、
#排除胜负判定这类持续型被动），推内部英文名对玩家没有意义。
#来源对象名（哪张牌/哪个状态发动的）从效果的 from 取，取不到就只报效果文案
func _announce_effect(effect:BaseEffect, changes:Array = []) -> void:
	if effect == null:
		return
	var text:String = str(effect.get_shown_name())
	#选项类效果（如令咒的三选一）要报出本次实际选中的选项名：效果级文案只是"令咒"这种统称，
	#不报选项玩家无法核对刚才选的哪一项。选项名由数据声明，不按牌名/角色名分支
	var chosen_lines:Array = []
	for idx in effect._chosen_selection.keys():
		if !(idx is int) or idx < 0 or idx >= effect._options.size():
			continue
		var opt_name:String = str(effect._options[idx].get("shown_option_name", ""))
		if opt_name != "":
			chosen_lines.append(opt_name)
	if !chosen_lines.is_empty():
		text = "\n".join(chosen_lines)
	if text == "":
		return
	var actor:String = _effect_actor_name(effect)
	var source:String = _effect_source_name(effect)
	var parts:Array = []
	if actor != "":
		parts.append(actor)
	#御主自身能力中“触发玩家”和“来源对象”可能是同一个名字；此时只显示一次。
	#来源为卡牌、状态或其他对象时仍保留【来源】，玩家才能知道是哪张牌发动。
	var actor_name:String = actor.trim_suffix("：")
	if source != "" and source != actor_name:
		parts.append("【%s】" % source)
	var line:String = text if parts.is_empty() else ("%s%s" % ["".join(parts), text])
	#玩家主动发动的能力使用独立结果队列：确认完成后由专门的“发动结果”弹窗展示，
	#不与下一条能力询问共用或重叠。自动/被动效果仍按时点折叠成普通公告。
	if effect._is_manual:
		var lines:Array = [line]
		# 明细逐条写明"谁／哪个对象／哪个字段／前值 → 后值"：
		# 玩家要能核对这次发动到底影响了谁，而不是只看到一句卡面文案。
		if changes.is_empty():
			lines.append("未产生即时变化")
		else:
			for change in changes:
				lines.append(format_rule_change(change))
		push_effect_result("\n".join(lines), -1)
		return
	#同一时点内触发的多条效果折叠成一条推送：战斗结算这类时点会连续触发一批效果，
	#逐条推会把提示刷成一长串、还会互相覆盖。按玩家可见范围分桶累积，
	#等本时点整条管线跑完（run_pipeline 收尾）再合并成一条
	var scope:int = effect._trigger_player_id
	var bucket:Array = _pending_announcements.get(scope, [])
	#同一时点里同名效果只报一次（多张同名牌各触发一次时不必重复刷同一行）
	if !bucket.has(line):
		bucket.append(line)
	_pending_announcements[scope] = bucket


#把本时点累积的效果提示合并推送。由 run_pipeline 在整条管线跑完时调用——
#那里才是"这个时点的效果都结算完了"的边界
func _flush_announcements() -> void:
	if _pending_announcements.is_empty():
		return
	var pending:Dictionary = _pending_announcements.duplicate()
	#先清空再推送：push_message 不会再回头触发效果，但清空在前可避免任何重入重复推
	_pending_announcements.clear()
	#效果公布是公开事件：要让人知道"谁因为什么做了什么"，只推给触发者本人等于没公布。
	#同一时点内触发的多条效果合并成一条，避免战斗结算时刷屏
	var all_lines:Array = []
	for scope in pending.keys():
		for line in pending[scope]:
			if not all_lines.has(line):
				all_lines.append(line)
	if not all_lines.is_empty():
		push_message("\n".join(all_lines), -1)


#效果触发者的示人名字（"谁"）。未归属玩家的效果（事件牌/局势牌挂在场上）返回空串
func _effect_actor_name(effect:BaseEffect) -> String:
	var id:int = _effect_fact_actor_id(effect)
	if id < 0 or !GameData.player_data_library.has(id):
		return ""
	var master = (GameDataManager.get_player_data(id) as Dictionary).get("master")
	if master == null:
		return "玩家 %d：" % id
	var shown:String = str(master.get_shown_name())
	return ("%s：" % shown) if shown != "" else ("玩家 %d：" % id)


func _effect_fact_actor_id(effect:BaseEffect) -> int:
	var owner = effect.from
	if owner is WeakRef:
		owner = owner.get_ref()
	# 场上牌效果借玩家 id 作为结算顺序锚点，该玩家不是发动者；提示只显示真实来源牌。
	if owner is BaseSituation or owner is BaseEvent:
		return -1
	return effect._trigger_player_id


#效果来源对象的示人名字（"因为什么"）：哪张牌、哪个状态发动的
func _effect_source_name(effect:BaseEffect) -> String:
	var owner = effect.from
	if owner == null:
		return ""
	#from 有两种形态：WeakRef（打断所有权强引用环用）与直接持有对象本身。
	#两种都要兼容——只按 WeakRef 处理会在直接持有对象时报
	#"Nonexistent function 'get_ref' in base 'RefCounted (BaseMaster)'"
	if owner is WeakRef:
		owner = owner.get_ref()
	if owner == null or !owner.has_method("get_shown_name"):
		return ""
	return str(owner.get_shown_name())
