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

var location_data:Dictionary = {
	"magic_workshop" : [
		-1,-1,-1,-1,[]
	],
	"miyama" : [
		-1,-1,[]
	],
	"shinto" : [
		-1,-1,[]
	],
	"scout" : [
		-1,[]
	]
}

const MAGIC_WORKSHOP_0 = {"magic_workshop" : 0}
const MAGIC_WORKSHOP_1 = {"magic_workshop" : 1}
const MAGIC_WORKSHOP_2 = {"magic_workshop" : 2}
const MAGIC_WORKSHOP_3 = {"magic_workshop" : 3}
const MAGIC_WORKSHOP_4 = {"magic_workshop" : 4}

const MIYAMA_0 = {"miyama" : 0}
const MIYAMA_1 = {"miyama" : 1}
const MIYAMA_2 = {"miyama" : 2}

const SHINTO_0 = {"shinto" : 0}
const SHINTO_1 = {"shinto" : 1}
const SHINTO_2 = {"shinto" : 2}

const SCOUT_0 = {"scout" : 0}
const SCOUT_1 = {"scout" : 1}

const MAGIC_WORKSHOP = "magic_workshop"
const MIYAMA = "miyama"
const SHINTO = "shinto"
const SCOUT = "scout"
