extends Node


var player_num:int = 7
var player_max:int = 7
var player_id:int = 6
var player_data_library:Dictionary

#从技能区打出卡牌所需的魔力。规则数字不写死，特殊效果可以改动
var skill_zone_magic_limit:BaseNumber = BaseNumber.new(8)
#魔力上限：界面按它显示"当前/上限"，不把 12 写死在界面里。规则数字不写死，特殊效果可以改动
var magic_limit:BaseNumber = BaseNumber.new(12)


#每个玩家都要一份独立的数据，不能共用同一个字典，否则各玩家的数值会互相串改
func new_player_data() -> Dictionary:
	return {
	"player_name" : "null_name",
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
	"is_deployed" : false,
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
	"command_spell_used_this_game" : 0,
	"command_spell_used_this_turn" : false,
	"command_spell_gained_magic" : false,
	"play_limit" : BaseNumber.new(2),
	"can_draw_card" : true,
	"last_turn_location" : null,
	"is_magic_immune" : false,
	"ignore_skill_zone_magic_limit" : false,
	"ignore_engagement_for_move" : false,
	"total_power_bonus" : BaseNumber.new(0),
	"attack_cost_discount" : BaseNumber.new(0),
	"move_cost_discount_from_workshop" : BaseNumber.new(0),
	"victory_override" : false
	}


#人数不写死，按需建立玩家数据；已存在的玩家不覆盖
func setup_players(num:int = player_num):
	player_num = num
	for i in num:
		if !player_data_library.has(i):
			player_data_library[i] = new_player_data()
	if !player_data_library.has(player_id):
		player_data_library[player_id] = new_player_data()


#局内会话重置：只重建本局玩家数据，不动已加载的御主/资源库(loaded_masters、objects、effects)。
#调用方需要在返回后显式设置每个玩家的master/order/is_out等初始状态
func reset_game_session(player_ids:Array):
	player_data_library.clear()
	for id in player_ids:
		player_data_library[id] = new_player_data()
	player_num = player_ids.size()
	player_max = player_ids.size()
	EffectManager.reset_runtime()


func _ready():
	setup_players()


var objects:Array#[BaseObject]
var effects:Array#[BaseEffect]
var effects_signals:Dictionary #{BaseEffect : Signal}

var loaded_masters:Array#[BaseMaster]
var loaded_servants:Array#[BaseServant]

var ingame_masters:Array#[BaseMaster]
var ingame_servants:Array#[BaseServant]


#释放一局完整对象图。先断开对象之间的所有权引用，再清全局容器；
#否则只清 objects 注册表，御主→卡牌→效果等强引用链仍会存活到进程退出。
#该函数只负责对象生命周期，不改变规则状态，也不负责开始下一局。
func release_game_objects() -> void:
	GameLog.reset()
	EffectManager.reset_runtime()

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
