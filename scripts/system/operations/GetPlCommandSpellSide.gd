class_name GetPlCommandSpellSide
extends RefCounted

func exec(player_id:int = -1):

	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["side"]["command_spell"]
