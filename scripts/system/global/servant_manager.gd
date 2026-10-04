extends Node


#只负责从者归属和从者效果绑定，不负责游戏开始、御主或技能管理。
func bind_servant_effects(player_id:int):
	var player_data = GameDataManager.get_player_data(player_id) as Dictionary
	var servant = player_data["servant"]
	if servant != null and "_effects" in servant:
		EffectManager.register_effects(servant._effects, player_id)
