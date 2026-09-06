class_name GetPlayerLives
extends RefCounted

func exec(player_id:int = -1):

	#默认取当前效果的触发者，而不是本地玩家
	var id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	return player_data["lives"]
