extends Node


var player_num:int = 7
var player_max:int = 7
var player_id:int = 6
var player_data_library:Dictionary

#从技能区打出卡牌所需的魔力。规则数字不写死，特殊效果可以改动
var skill_zone_magic_limit:BaseNumber = BaseNumber.new(8)


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
	"is_battle_lose" : false,
	"is_battle_win" : false,
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
	"true_name_released" : false,
	#本局已经触发过的一次性效果名。效果触发后把名字加进来，靠它保证"第一次/每局限一次"。
	#不按效果各写一个bool字段——新增一次性效果只需往这里加名字
	"used_once_effects" : [],
	"command_spell_count" : BaseNumber.new(3),
	"command_spell_used_this_game" : 0,
	"command_spell_used_this_turn" : false,
	"command_spell_gained_magic" : false,
	"play_limit" : BaseNumber.new(2),
	"can_draw_card" : true,
	"score_gained_this_turn" : 0,
	"played_attacks_this_turn" : [],
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
