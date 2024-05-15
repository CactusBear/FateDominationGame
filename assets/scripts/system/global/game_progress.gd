extends Node


var current_player_id:int
var eff_progress_index:int = -1
var effect_progress:Array#[Array]
var activating_eff:BaseEffect


#效果处理
func choose_active_effect():
	for n in GameData.player_num:
		var id = current_player_id + n
		if id > GameData.player_num:
			id -= GameData.player_num
		if id < 0:
			id += GameData.player_num
		var chosen_effects:Array
		var pl_data = GameDataManager.get_player_data(id) as Dictionary
		if pl_data["choosing_active_effects"] == [] :continue
		#chosen_effects = show_choose_effects(id)
		for effect in chosen_effects:
			use_active_effect(effect)
		

func order_passive_effect():
	for n in GameData.player_num:
		var id = current_player_id + n
		if id > GameData.player_num:
			id -= GameData.player_num
		if id < 0:
			id += GameData.player_num
		var ordered_effects:Array
		var pl_data = GameDataManager.get_player_data(id) as Dictionary
		var ordering_passive_effects = pl_data["ordering_passive_effects"] as Array
		if ordering_passive_effects == [] :continue
		if ordering_passive_effects.size() == 1:
			ordered_effects = ordering_passive_effects
		#ordered_effects = show_order_effects(id)
		for effect in ordered_effects:
			use_passive_effect(effect)

func add_to_choose_active(effect:BaseEffect, player_id:int):
	var pl_data = GameDataManager.get_player_data(player_id) as Dictionary
	var arr = pl_data["choosing_active_effects"] as Array
	arr.append(effect)

func add_to_order_passive(effect:BaseEffect, player_id:int):
	var  pl_data = GameDataManager.get_player_data(player_id) as Dictionary
	var arr = pl_data["ordering_passive_effects"] as Array
	arr.append(effect)


func use_active_effect(effect:BaseEffect):
	var eff_name:String = effect._name
	var shown_tps:Array
	for tp in effect._time_points:
		var shown_tp = TimePoints.shown_time_points[tp]
		shown_tps.append(shown_tp)
	if eff_progress_index <= -1:
		return
	if effect_progress.size() <= eff_progress_index:
		for i in eff_progress_index + 1:
			if effect_progress.size() <= i:
				effect_progress.append([])
		var arr = effect_progress[eff_progress_index] as Array
		arr.append(effect)
	elif effect_progress[eff_progress_index] is Array:
		var arr = effect_progress[eff_progress_index] as Array
		arr.append(effect)


func use_passive_effect(effect:BaseEffect):
	var eff_name:String = effect._name
	var shown_tps:Array
	for tp in effect._time_points:
		var shown_tp = TimePoints.shown_time_points[tp]
		shown_tps.append(shown_tp)
	if eff_progress_index <= -1:
		return
	if effect_progress.size() <= eff_progress_index:
		for i in eff_progress_index + 1:
			if effect_progress.size() <= i:
				effect_progress.append([])
		var arr = effect_progress[eff_progress_index] as Array
		arr.append(effect)
	elif effect_progress[eff_progress_index] is Array:
		var arr = effect_progress[eff_progress_index] as Array
		arr.append(effect)


func activate_effects():
	var effs_arr:Array
	for i in range(effect_progress.size()-1, -1, -1):
		var array = effect_progress[i] as Array
		for eff:BaseEffect in array:
			if effs_arr.size() <= eff._priority:
				for index in eff._priority + 1:
					if effs_arr.size() <= index:
						effs_arr.append([])
				var arr = effs_arr[eff._priority] as Array
				arr.append(eff)
			if effs_arr[eff._priority] is Array:
				var arr = effs_arr[eff._priority] as Array
				arr.append(eff)
	
	for effs in effs_arr:
		if effs == []:continue
		for eff in effs:
			if eff is BaseEffect:
				EffectLib.activate_effect(eff)
				activating_eff = eff
		
	
