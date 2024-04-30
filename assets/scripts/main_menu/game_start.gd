extends Node


var masters_can_use = []



func game_start():
	MapData.player_id = get_id()
	masters_can_use = get_masters_can_use()
	


func get_id():
	var id = 0
	return id
	pass
	

func get_masters_can_use():
	var masters = []
	pass
