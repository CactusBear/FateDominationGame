class_name GetAllPlayersId
extends RefCounted

func exec():

	return GameData.player_data_library.keys()
