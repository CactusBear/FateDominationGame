extends BaseMaster



var signals_dic:Dictionary
var signals:Array
var weishu_0001_sig:Signal 

func _init():
	
	var data:Dictionary = _data.duplicate()
	
	var weishu_0001 = _ability.duplicate()
	var touying_0001 = _ability.duplicate()
	var ylcsdlxx_0001 = _ability.duplicate()
	
	set_ability(weishu_0001, "未熟", [TimePointChecker.GAME_START])
	
	var abilities:Array = [weishu_0001]
	var specials = {
	
	}
	var upgrade_skill = {
	
	}
	
	
	data["master_id"] = 000001
	data["master_name"] = "emiya_shirou"
	data["shown_master_name"] = "卫宫士郎"
	data["command_spell_image"] = "emiya_shirou"
	data["abilities"] = abilities
	data["specials"] = specials
	data["upgrade_skill"] = upgrade_skill
	data["signals_dic"] = signals_dic
	
	signal_connection()
	


func signal_connection():
	signals.append(weishu_0001_sig)
	connect(weishu_0001_sig.get_name(),weishu_func)
	signals_dic[TimePointChecker.GAME_START] = signals




func weishu_func():
	var player_data = PlayerDataManager.get_data(player_id)
	player_data["magic"] = 2
	pass
	
func touying_func():
	pass
	
func ylcsdlxx_func():
	pass
