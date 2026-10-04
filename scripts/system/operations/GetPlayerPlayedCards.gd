class_name GetPlayerPlayedCards
extends RefCounted

func exec(player_id:int = -1):

	var id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	return player_data["played_cards"]
