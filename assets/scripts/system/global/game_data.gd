extends Node


var player_num:int = 7
var player_max:int = 7
var player_id:int = 6
var player_data_library:Dictionary = {player_id:player_data}


var player_data:Dictionary = {
	"player_name" : "null_name",
	"master" : null,
	"servant" : null,
	"command_spell" : [],
	"magic" : BaseNumber.new(4),
	"score" : BaseNumber.new(0),
	"deck" : [],
	"discard" : [],
	"hand_cards" : [],
	"played_cards" : [], #{"card" : null, "is_back" : false}
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
	"order" : 0,
	"current_time_points" : [],
	"dynamic_time_points" : [],
	"buffs" : [],
	"self_effects" : [],
	"choosing_active_effects" : [],
	"ordering_passive_effects" : [],
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
		}
	}

var objects:Array#[BaseObject]
var effects:Array#[BaseEffect]
var effects_signals:Dictionary #{BaseEffect : Signal}

var loaded_masters:Array#[BaseMaster]
var loaded_servants:Array#[BaseServant]

var ingame_masters:Array#[BaseMaster]
var ingame_servants:Array#[BaseServant]
