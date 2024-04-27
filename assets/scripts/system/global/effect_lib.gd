extends Node


var null_func = do_nothing
func do_nothing():
	pass

func edit_magic(time_points:Array, set_num:int = -1, vary_num:int = 0,player_id:int = GameData.player_id,  cost:Callable = null_func):
	if TimePointChecker.current_time_points.has(time_points):
		cost.call()
		var player_data:Dictionary = PlayerDataManager.get_data(player_id)
		player_data["magic"] = set_num
		player_data["magic"] += vary_num
	pass

