extends Node


var player_num:int = 7
var player_max:int = 7
var player_id:int = 6
var player_data_library:Dictionary = {player_id:player_data}

var player_card:Dictionary = {
	"card" : null,
	"is_back" : false
}

var player_data:Dictionary = {
	"player_name" : "null_name",
	"master" : null,
	"servant" : null,
	"command_spell" : [],
	"magic" : 4,
	"score" : 0,
	"deck" : [],
	"discard" : [],
	"played_cards" : [],
	"master_skills" : [],
	"servant_skills" : [],
	"location" : {},
	"temp_location" : {},
	"power" : 0,
	"is_deployed" : false,
	"is_out" : true,
	"is_shown" : false,
	"is_battle" : false,
	"is_battle_lose" : false,
	"is_battle_win" : false,
	"is_first" : false,
	"order" : 1,
	"current_time_points" : [],
	"buffs" : [],
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
		"skills" : [],
		"buffs" : [],
		"others" : []
		}
	}

var objects:Array[BaseObject]

var master_datas:Array[Dictionary]
var servant_datas:Array[Dictionary]
