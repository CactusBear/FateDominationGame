class_name PlayedCards
extends RefCounted

func exec(player_id:int = GameData.player_id):

	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], player_id)
