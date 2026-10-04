class_name GetRankByDataNumber
extends RefCounted

#按player_data里某个BaseNumber字段计算名次。默认高分在前。
#并列：有多少人严格更优，名次就是这个数+1(两个人并列第一，下一名是第3)。
#include_out为false时不把已淘汰玩家算进比较，但不写死必须淘汰。
func exec(key:String, player_id:int = -1, descending:bool = true, include_out:bool = false) -> int:

	var id = EffectManager.resolve_player_id(player_id)
	if !GameData.player_data_library.has(id):
		return 0
	var my_num = _read_number(id, key)
	if my_num == null:
		return 0

	var ids:Array = GameDataManager.get_active_player_ids() if !include_out else GameData.player_data_library.keys()
	var better:int = 0
	for other_id in ids:
		var other_num = _read_number(other_id, key)
		if other_num == null:
			continue
		if descending and other_num > my_num:
			better += 1
		elif !descending and other_num < my_num:
			better += 1
	return better + 1


func _read_number(player_id, key:String):
	var player_data:Dictionary = GameDataManager.get_player_data(int(player_id))
	if !player_data.has(key):
		return null
	var value = player_data[key]
	if value is BaseNumber:
		return value.number
	if value is int or value is float:
		return value
	return null
