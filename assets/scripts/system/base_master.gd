extends BaseObject
class_name  BaseMaster

var _shown_master_name:String
var _header_img:String
var _master_card_img:String
var _command_spell_img:String
#卡背图。为空时用通用卡背
var _card_back_img:String = ""
var _effects:Array
var _specials:Dictionary
var _upgrade_skill:Array
#不能归类为技能/攻击/buff的御主附带物件(如宝石卡)，放other_master_things
var _other_things:Array




func _init(master_name:String, shown_master_name:String, header_img:String, master_card_img:String, commmand_spell_img:String):
	_name = master_name
	_shown_master_name = shown_master_name
	_header_img = header_img
	_master_card_img = master_card_img
	_command_spell_img = commmand_spell_img
	_effects = []
	_specials = {}
	_upgrade_skill = []
	_other_things = []
	
	super.add_object()
	
