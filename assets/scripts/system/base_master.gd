extends Node
class_name  BaseMaster

var player_id:int

var _data:Dictionary = {
	"master_id" : -1,
	"master_name" : "null_master_name",
	"shown_master_name" : "null_shown_master_name",
	"command_spell_type" : "normal",
	"command_spell_image" : "emiya_shirou",
	"command_spell_num" : 3,
	"abilities" : [],
	"specials" : {},
	"upgrade_skill" : {},
	"signals_dic" : {},
}
var _signals_dic:Dictionary = {"null_time_point" : _signals}
var _signals:Array

var _ability = {
	"name" : "null_name",
	"time-points" : [],
}

func set_ability(ability:Dictionary, name:String, time_points:Array):
	ability["name"] = name
	ability["time_points"] = time_points
	
