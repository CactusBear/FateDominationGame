extends BaseObject
class_name  BaseMaster

var _master_name:String
var _shown_master_name:String
var _header_img:String
var _master_card_img:String
var _command_spell_img:String
var _effects:Dictionary
var _specials:Dictionary
var _upgrade_skill:Dictionary




func _init(master_name:String, shown_master_name:String, header_img:String, master_card_img:String, commmand_spell_img:String):
	_master_name = master_name
	_shown_master_name = shown_master_name
	_header_img = header_img
	_master_card_img = master_card_img
	_command_spell_img = commmand_spell_img
	_effects = {}
	_specials = {}
	_upgrade_skill = {}
	
	
