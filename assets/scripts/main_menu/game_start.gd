extends Node


var masters_can_use:Array = []
var servants_can_use:Array = []
var _started:bool = false


#负责从主菜单进入对局，不负责御主/从者的具体效果绑定。
func game_start(player_ids:Array = [0, 1]) -> bool:
	if _started:
		return false

	var ids:Array = player_ids.duplicate()
	if ids.is_empty():
		return false
	var unique_ids:Array = []
	for id in ids:
		if !unique_ids.has(id):
			unique_ids.append(id)
	if unique_ids.size() != ids.size():
		return false

	_started = true
	MapData.player_id = get_id()
	masters_can_use = get_masters_can_use()
	servants_can_use = get_servants_can_use()
	GameData.reset_game_session(ids)

	for i in ids.size():
		var player_data = GameDataManager.get_player_data(ids[i]) as Dictionary
		player_data["is_out"] = false
		player_data["order"].set_num(BaseNumber.new(i))
		#当前数据库只有一个御主/从者，未加载的测试玩家保留空归属。
		if i < masters_can_use.size():
			player_data["master"] = masters_can_use[i]
		if i < servants_can_use.size():
			player_data["servant"] = servants_can_use[i]
		MasterManager.bind_master_effects(ids[i])
		ServantManager.bind_servant_effects(ids[i])

	GameProgress.start_game()
	return true


func reset():
	_started = false


func get_id():
	return 0


func get_masters_can_use() -> Array:
	var masters:Array = []
	for master in GameData.loaded_masters:
		if master is BaseMaster:
			masters.append(master)
	return masters


func get_servants_can_use() -> Array:
	var servants:Array = []
	for servant in GameData.loaded_servants:
		if servant is BaseServant:
			servants.append(servant)
	return servants
