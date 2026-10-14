extends Node

var _model = SessionGeneration.ModelBacking.new({
	"player_num":7,
	"player_max":7,
	"player_id":6,
	"player_data_library":{},
	"skill_zone_magic_limit":BaseNumber.new(8),
	"magic_limit":BaseNumber.new(12),
	"hand_limit":BaseNumber.new(3),
	"default_master":"emiya_shirou",
	"default_servant":"emiya",
	"default_player_name_pattern":"玩家%d",
	"objects":[],
	"effects":[],
	"effects_signals":{},
	"loaded_masters":[],
	"loaded_servants":[],
	"ingame_masters":[],
	"ingame_servants":[]
})


var player_num:int:
	get: return _model.read(&"player_num", 0)
	set(value): _model.write(&"player_num", value)
var player_max:int:
	get: return _model.read(&"player_max", 0)
	set(value): _model.write(&"player_max", value)
var player_id:int:
	get: return _model.read(&"player_id", 0)
	set(value): _model.write(&"player_id", value)
var player_data_library:Dictionary:
	get: return _model.read(&"player_data_library", {})
	set(value): _model.write(&"player_data_library", value)

#从技能区打出卡牌所需的魔力。规则数字不写死，特殊效果可以改动
var skill_zone_magic_limit:BaseNumber:
	get: return _model.read(&"skill_zone_magic_limit", null)
	set(value): _model.write(&"skill_zone_magic_limit", value)
#魔力上限：界面按它显示"当前/上限"，不把 12 写死在界面里。规则数字不写死，特殊效果可以改动
var magic_limit:BaseNumber:
	get: return _model.read(&"magic_limit", null)
	set(value): _model.write(&"magic_limit", value)
#手牌上限：准备阶段把每名玩家的手牌补充到这个张数。规则数字不写死，特殊效果可以改动
var hand_limit:BaseNumber:
	get: return _model.read(&"hand_limit", null)
	set(value): _model.write(&"hand_limit", value)
#新对局里本地玩家的默认登场组合，填模板名（空串＝按加载顺序分配）。
#这是数据声明，不写在分配代码里：换开局配置只改这里。
var default_master:String:
	get: return _model.read(&"default_master", "")
	set(value): _model.write(&"default_master", value)
var default_servant:String:
	get: return _model.read(&"default_servant", "")
	set(value): _model.write(&"default_servant", value)
#新对局给每名玩家写入的默认玩家名模板：%d 是号位（按开局传入的玩家顺序，从 1 起）。
#命名规则只声明在这里；界面和查询 op 都只读玩家数据里的 player_name，不自己拼名字。
var default_player_name_pattern:String:
	get: return _model.read(&"default_player_name_pattern", "")
	set(value): _model.write(&"default_player_name_pattern", value)


#每个玩家都要一份独立的数据，不能共用同一个字典，否则各玩家的数值会互相串改
#player_name 是玩家本人的名字，与御主名是两份数据：空串表示"还没命名"，
#开局由 GameStart 按号位写入默认名；界面只显示这个字段，缺失时留空、不拿御主名顶替。
func new_player_data() -> Dictionary:
	return {
	"player_name" : "",
	"master" : null,
	"servant" : null,
	"command_spell" : [],
	"magic" : BaseNumber.new(4),
	"score" : BaseNumber.new(0),
	"lives" : BaseNumber.new(1),
	"deck" : [],
	"discard" : [],
	"hand_cards" : [],
	"played_cards" : [],
	"master_skills" : [],
	"servant_skills" : [],
	"location" : null,
	"temp_locations" : [],
	"power" : BaseNumber.new(0),
	"is_victory" : false,
	"is_out" : true,
	"is_shown" : false,
	"is_battle" : false,
	"is_first" : false,
	"order" : BaseNumber.new(0),
	"current_time_points" : [],
	"dynamic_time_points" : [],
	"buffs" : [],
	#self_effects是效果归属的反查表，效果的待决定队列与结算池统一在EffectManager里
	"self_effects" : [],
	"out_of_game" : {
		"master" : null,
		"servant" : null,
		"command_spell" : [],
		"attacks" : [],
		"skills" : [],
		"buffs" : [],
		"others" : []
		},
	"side" : {
		"master" : null,
		"servant" : null,
		"command_spell" : [],
		"deck" : [],
		"discard" : [],
		"hand_cards" : [],
		"skills" : [],
		"buffs" : [],
		"others" : []
		},
	"command_spell_count" : BaseNumber.new(3),
	# 令咒上限是玩家级可修改数据；通常为3，效果可以提高或降低。
	"command_spell_limit" : BaseNumber.new(3),
	#每局限一次效果的共享使用记录；只在效果实际完成后追加其英文效果名。
	"used_once_effects" : [],
	"play_limit" : BaseNumber.new(2),
	"regular_play_min" : BaseNumber.new(2),
	"can_draw_card" : true,
	#行动结束的声明式前置条件（Array[String]）：由效果增减、ActionRules 按名字判定。
	#空数组表示没有额外要求，与"规则数字不写死"同一原则：条件本身由数据声明
	"action_requirements" : [],
	"last_turn_location" : null,
	"is_magic_immune" : false,
	"ignore_skill_zone_magic_limit" : false,
	"ignore_engagement_for_move" : false,
	"total_power_bonus" : BaseNumber.new(0),
	"attack_cost_discount" : BaseNumber.new(0),
	"move_cost_discount_from_workshop" : BaseNumber.new(0),
	"victory_override" : false,
	#以下是玩家级的规则数字覆盖。null 表示"没有被效果改过"，读取时退回 GameData 的全局值：
	#这样全局规则改动（例如某张局势牌改了手牌上限）仍然对没被单独改过的玩家生效
	"hand_limit" : null,
	"magic_limit" : null,
	#战果下限：null 表示不设下限（与原有 EditScore 行为一致）；效果需要"不能低于某值"时写入 BaseNumber
	"score_min" : null,
	#常规移动每经过一段的费用减免（与离开工房的减免叠加），费用不会被减成负数
	"move_cost_discount_per_step" : BaseNumber.new(0),
	#玩家级基础地利加成：只在玩家实际享有地利时叠加，由 GetEffectiveLocationBenefit 统一计入
	"location_benefit_bonus" : BaseNumber.new(0),
	#身份标签（异星神、隐匿者、新郎、红队……），判定用 is_in_array，名字由数据起
	"roles" : [],
	#恐惧属性等按玩家声明的属性列表，内容由数据写入，程序不推断
	"fear_attributes" : [],
	#按名字的独立牌区（月灵髓液、艺术品、记忆……）：{区名 : Array}。
	#区名由卡牌数据声明，建区用 set_dictionary_value，搬运用 draw_card_by_card
	"extra_zones" : {},
	#由谁控制：-1 表示独立玩家（常规）；分身棋子填本体玩家 id；NPC 填 -2（不属于任何玩家）。
	#受控条目参与版图与战斗，但不单独行动、不单独计胜负/淘汰/顺位。由 add_player 创建时写入
	"controller" : -1,
	#阶段视为：{实际阶段名 : [视为的阶段名...]}。天堂之孔"准备阶段即进行前哨与行动"、
	#无极"战斗阶段可用行动阶段能力"写在这里；空字典表示没有覆盖（与原行为一致）
	"phase_as" : {},
	#常规出牌的候选牌区（player_data 里的区路径，如 hand_cards、discard、extra_zones/记忆）。
	#螺湮城"仅将弃牌堆视为手牌"改这里；缺省就是手牌
	"regular_play_zones" : ["hand_cards"]
	}


#玩家此刻的手牌上限：有玩家级覆盖用覆盖值，否则用全局规则值
func player_hand_limit(player_id:int) -> BaseNumber:
	return _player_limit(player_id, "hand_limit", hand_limit)


#玩家此刻的魔力上限：有玩家级覆盖用覆盖值，否则用全局规则值
func player_magic_limit(player_id:int) -> BaseNumber:
	return _player_limit(player_id, "magic_limit", magic_limit)


func _player_limit(player_id:int, key:String, fallback:BaseNumber) -> BaseNumber:
	if player_data_library.has(player_id):
		var own = (player_data_library[player_id] as Dictionary).get(key)
		if own is BaseNumber:
			return own
	return fallback


#显式模板初始化：只补缺失成员，不覆盖、不签票，也不绑定运行期来源。
func setup_players(num:int = player_num):
	_initialize_player_templates(num)


func _initialize_player_templates(num:int) -> void:
	player_num = num
	for i in num:
		if !player_data_library.has(i):
			player_data_library[i] = new_player_data()
	if !player_data_library.has(player_id):
		player_data_library[player_id] = new_player_data()


#公共重置先换代再清值；外层启动传入已验 context 时沿用同域，不二次换代。
#成功只表示玩家数据重建；角色/runtime 绑定与规则开局仍由各自所有者显式完成。
func reset_game_session(player_ids:Array, startup_context:Variant = null) -> Dictionary:
	# EM runtime 清理尚未域化：拒绝必须在成员清值/换代前。
	if SessionGeneration.in_private_frame(): return {"ok":false, "context":null, "reason":&"unsupported_domain_runtime_cleanup"}
	var context:SessionContext
	if startup_context == null:
		var generation:Dictionary = preload("res://scripts/system/session_generation.gd").begin_generation(&"GameData.reset_game_session")
		if not generation.ok:
			return {"ok":false, "context":null, "reason":generation.reason}
		var derived:Dictionary = preload("res://scripts/system/session_generation.gd").derive_context(generation.token, &"GameData.reset_game_session")
		if not derived.ok:
			return derived
		context = derived.context
	else:
		if not startup_context is SessionContext:
			return {"ok":false, "context":null, "reason":&"unbound_origin"}
		var valid:Dictionary = preload("res://scripts/system/session_generation.gd").validate_context(startup_context)
		if not valid.ok:
			return {"ok":false, "context":null, "reason":valid.reason}
		context = startup_context
	if not _reset_player_values(player_ids, context):
		return {"ok":false, "context":null, "reason":&"stale_session"}
	#同域清理沿用本次捕获的原 context；失败原样传播，不再次换代或补票。
	var cleanup:Dictionary = EffectManager.clear_runtime_in_context(context)
	if not cleanup.ok:
		return cleanup
	var current:Dictionary = preload("res://scripts/system/session_generation.gd").validate_context(context)
	if not current.ok:
		return {"ok":false, "context":null, "reason":current.reason}
	return {"ok":true, "context":context, "reason":&"current"}


#内部同域清值：不能单独签发资格，清理回调换局后也不能继续重建另一域。
func _reset_player_values(player_ids:Array, context:SessionContext) -> bool:
	if not preload("res://scripts/system/session_generation.gd").validate_context(context).ok:
		return false
	player_data_library.clear()
	if not preload("res://scripts/system/session_generation.gd").validate_context(context).ok:
		return false
	for id in player_ids:
		player_data_library[id] = new_player_data()
	player_num = player_ids.size()
	player_max = player_ids.size()
	return true


func _ready():
	setup_players()


var objects:Array:
	get: return _model.read(&"objects", [])
	set(value): _model.write(&"objects", value)
var effects:Array:
	get: return _model.read(&"effects", [])
	set(value): _model.write(&"effects", value)
var effects_signals:Dictionary:
	get: return _model.read(&"effects_signals", {})
	set(value): _model.write(&"effects_signals", value)

var loaded_masters:Array:
	get: return _model.read(&"loaded_masters", [])
	set(value): _model.write(&"loaded_masters", value)
var loaded_servants:Array:
	get: return _model.read(&"loaded_servants", [])
	set(value): _model.write(&"loaded_servants", value)

var ingame_masters:Array:
	get: return _model.read(&"ingame_masters", [])
	set(value): _model.write(&"ingame_masters", value)
var ingame_servants:Array:
	get: return _model.read(&"ingame_servants", [])
	set(value): _model.write(&"ingame_servants", value)


#释放一局完整对象图。先断开对象之间的所有权引用，再清全局容器；
#否则只清 objects 注册表，御主→卡牌→效果等强引用链仍会存活到进程退出。
#该函数关闭资格域，不负责开始下一局；嵌套清理也不能签新可执行资格。
func release_game_objects() -> void:
	# D cleanup 不得碰 L 的 Load*/EM/static 池。
	if SessionGeneration.in_private_frame(): return
	preload("res://scripts/system/session_generation.gd").invalidate_generation(&"GameData.release_game_objects")
	GameLog.reset()
	var cleanup:Dictionary = EffectManager.clear_runtime_after_invalidation()
	if not cleanup.ok:
		return

	#快照后逐个断开对象内部强引用。字段是否存在由对象类型自身决定，
	#不按角色或具体卡牌写分支，新增对象类型仍可复用公共容器约定。
	var registered_objects:Array = objects.duplicate()
	for object in registered_objects:
		if object == null:
			continue
		if "from" in object:
			object.from = null
		if "_effects" in object:
			(object._effects as Array).clear()
		if "_specials" in object:
			(object._specials as Dictionary).clear()
		if "_upgrade_skill" in object:
			(object._upgrade_skill as Array).clear()
		if "_other_things" in object:
			(object._other_things as Array).clear()
		if "_relate_buff" in object:
			object._relate_buff = null
		if "_funcs" in object:
			(object._funcs as Array).clear()
		if "_options" in object:
			(object._options as Array).clear()
		if "_self_vars" in object:
			(object._self_vars as Array).clear()
		if "_selected_cards" in object:
			(object._selected_cards as Array).clear()

	objects.clear()
	effects.clear()
	effects_signals.clear()
	loaded_masters.clear()
	loaded_servants.clear()
	ingame_masters.clear()
	ingame_servants.clear()
	player_data_library.clear()

	#这些 autoload/static 缓存也独立持有业务对象或资源，必须与主注册表一起释放。
	MapData.event_deck.clear()
	MapData.active_situation = null
	MapData.situations.clear()
	#事件牌/局势牌弃牌区同样持有对象引用，漏清会在退出时报对象泄漏
	MapData.event_discard.clear()
	MapData.situation_discard.clear()
	for area in MapData.areas:
		if area is BaseMapArea:
			area._events.clear()
			area._buffs.clear()
	MapData.areas.clear()
	LoadEvent.events.clear()
	LoadSituation.situations.clear()
	LoadSituation.climax_situations.clear()
	LoadCommandSpell.command_spells.clear()
	LoadAttack._attack_datas.clear()
	LoadHelper._texture_cache.clear()
	GameStart.masters_can_use.clear()
	GameStart.servants_can_use.clear()
	GameProgress.last_battle_result.clear()


func _exit_tree() -> void:
	release_game_objects()

# 只提供原始写集 backing 与 D 映射；没有 owner install/commit。
func publication_backing() -> Dictionary:
	return _model.backing()

func bind_domain_model(domain:Variant, private_state:Dictionary) -> Dictionary:
	return _model.bind(domain, private_state)

func domain_model_status() -> Dictionary:
	return _model.resolve()
