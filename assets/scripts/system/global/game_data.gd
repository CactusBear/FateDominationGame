extends Node


var player_num:int = 7
var player_max:int = 7
var player_id:int = 6
var player_data_library:Dictionary = {player_id:player_data}


var player_data:Dictionary = {
	"player_name" : "null_name",
	"master" : null,
	"servant" : null,
	"command_spell" : {},
	"magic" : 4,
	"score" : 0,
	"deck" : {},
	"discard" : {},
	"master_skills" : {},
	"servant_skills" : {},
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
	"phase_order" : 1,
	"current_time_points" : [],
	"buffs" : [],
	"others" : {}
	}

var objects:Array[BaseObject]


