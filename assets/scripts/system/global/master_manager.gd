extends Node


#只管理御主效果与玩家的御主归属，不负责游戏开始、从者或技能。
func bind_master_effects(player_id:int):
	var player_data = GameDataManager.get_player_data(player_id) as Dictionary
	var master = player_data["master"]
	if master is BaseMaster:
		EffectManager.register_effects(master._effects, player_id)
