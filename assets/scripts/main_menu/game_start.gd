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
	masters_can_use = get_masters_can_use()
	servants_can_use = get_servants_can_use()
	GameData.reset_game_session(ids)

	#本地玩家的默认组合由 GameData 声明：先把声明的那两个模板从池里取出，
	#其余玩家再按加载顺序分剩下的。声明为空或找不到模板时退化为纯顺序分配（不猜、不报错）
	var local_master = _take_named(masters_can_use, GameData.default_master)
	var local_servant = _take_named(servants_can_use, GameData.default_servant)
	var next_master:int = 0
	var next_servant:int = 0

	for i in ids.size():
		var id:int = int(ids[i])
		var player_data = GameDataManager.get_player_data(id) as Dictionary
		player_data["is_out"] = false
		player_data["order"].set_num(BaseNumber.new(i))
		var master = null
		if id == GameData.player_id and local_master != null:
			master = local_master
		elif next_master < masters_can_use.size():
			master = masters_can_use[next_master]
			next_master += 1
		var servant = null
		if id == GameData.player_id and local_servant != null:
			servant = local_servant
		elif next_servant < servants_can_use.size():
			servant = servants_can_use[next_servant]
			next_servant += 1
		#未加载到御主/从者的测试玩家保留空归属。
		if master != null:
			player_data["master"] = master
			# 初始御主也是历史事实，供“第一名御主”类卡牌规则查询。
			GameLog.record("master_assigned", id, -1, "", master, ["master_assigned"], {"effect_name": ""})
		if servant != null:
			player_data["servant"] = servant
		MasterManager.bind_master_effects(id)
		MasterManager.deal_initial_master_cards(id)
		MasterManager.bind_command_spell_effects(id)
		ServantManager.bind_servant_effects(id)

	GameProgress.start_game()
	return true


##按名字从池里摘出模板（找到即移除并返回，找不到返回 null）。
##摘出去是为了不让后面的顺序分配把它再发一次——同一个御主/从者不能同时属于两名玩家。
func _take_named(pool:Array, wanted:String):
	if wanted == "":
		return null
	for i in range(pool.size()):
		if pool[i] != null and str(pool[i]._name) == wanted:
			return pool.pop_at(i)
	return null


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
