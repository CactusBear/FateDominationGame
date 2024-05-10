extends Node





var global_signals:Dictionary
var phase_time_points:Array

func dynamic_time_point(time_points:Array, current_player_id:int):
	var current_player_data:Dictionary = GameDataManager.get_player_data(current_player_id)
	var current_dtp_arr:Array = current_player_data["dynamic_time_points"] as Array
	for tp in time_points:
		current_dtp_arr.append(tp)
		current_dtp_arr.append("self_" + tp)
	var current_tp_arr = current_player_data["current_time_points"] as Array
	current_tp_arr = phase_time_points + current_dtp_arr
	
	var pl_ids = EffectLib.get_all_players_id() as Array
	pl_ids.erase(current_player_id)
	for id in pl_ids:
		var other_player_data:Dictionary = GameDataManager.get_player_data(id)
		var other_dtp_arr:Array = other_player_data["dynamic_time_points"] as Array
		for tp in time_points:
			other_dtp_arr.append(tp)
			other_dtp_arr.append("others_" + tp)
		var other_tp_arr = other_player_data["current_time_points"] as Array
		other_tp_arr = phase_time_points + other_dtp_arr
	
	

func time_point_check():
	var player_data = GameDataManager.get_player_data(GameData.player_id)
	var current_time_points = player_data["current_time_points"] as Array
	for effect:BaseEffect in GameData.effects:
		var has_effect:bool
		for tp in effect._time_points:
			has_effect = current_time_points.has(tp)
		if has_effect:
			var sig = GameData.effects_signals[effect] as Signal
			sig.emit()
		
