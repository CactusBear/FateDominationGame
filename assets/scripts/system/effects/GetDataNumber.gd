class_name GetDataNumber
extends RefCounted

func exec(key:String, player_id:int = GameData.player_id):

	var player_data = GameDataManager.get_player_data(player_id) as Dictionary
	if !player_data.has(key):
		#show("所提供的键不存在于player_data中")
		return
	if player_data[key] is Dictionary:
		var data:Dictionary = player_data[key]
		return data.size()
	if player_data[key] is Array:
		var data:Array = player_data[key]
		return data.size() 
	if player_data[key] is int:
		return player_data[key]
