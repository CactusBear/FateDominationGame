class_name SetPlayerData
extends RefCounted

func exec(key_name:String, value, player_id:int = -1):

	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	player_data[key_name] = value
	# 所属御主的初始/替换历史只作为事实写日志；不为单卡新增快照字段。
	if key_name == "master":
		var effect_name := ""
		if EffectManager.activating_eff != null:
			effect_name = EffectManager.activating_eff._name
		GameLog.record("master_assigned", player_id, -1, "", value, ["master_assigned"], {"effect_name": effect_name})
