class_name PlayedCards
extends RefCounted

func exec(player_id:int = -1):

	player_id = EffectManager.resolve_player_id(player_id)
	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], player_id)
