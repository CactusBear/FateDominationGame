extends Node



func _on_game_start():
	#将御主信号加入全局信号
	for id in range(GameData.player_num):
		var player_data = PlayerDataManager.get_data(id)
		var signals_dic = player_data["master"]["signals_dic"] as Dictionary
		for time_point in signals_dic.keys():
			if TimePointChecker.global_signals.keys() != null:
				for tp in TimePointChecker.global_signals:
					if tp == time_point:
						var signals = TimePointChecker.global_signals[tp] as Array
						signals.append(signals_dic[time_point])
			else :
				TimePointChecker.global_signals.merge(signals_dic)
				
	
	TimePointChecker.time_point(TimePointChecker.GAME_START)
