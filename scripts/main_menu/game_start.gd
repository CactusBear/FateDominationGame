extends Node


## 主菜单场景路径由此统一声明；选人界面、对局暂停菜单等所有「返回主菜单」入口都引用它
const MAIN_MENU_SCENE := "res://assets/scenes/main_menu/main_menu.tscn"

var masters_can_use:Array = []
var servants_can_use:Array = []
var _started:bool = false


#负责从主菜单进入对局，不负责御主/从者的具体效果绑定。
func game_start(player_ids:Array = [0, 1], assignments:Dictionary = {}, initial_order:Array = []) -> bool:
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
	# 显式阵容必须完整合法；验证在重置对局前完成。
	if not assignments.is_empty() and not validate_assignments(ids, assignments):
		return false
	var order_ids:Array = ids.duplicate() if initial_order.is_empty() else initial_order.duplicate()
	if order_ids.size() != ids.size():
		return false
	var ordered_ids:Array = []
	for id in order_ids:
		if not ids.has(id) or ordered_ids.has(id):
			return false
		ordered_ids.append(id)

	_started = true
	masters_can_use = get_masters_can_use()
	servants_can_use = get_servants_can_use()
	GameData.reset_game_session(ids)

	#本地玩家的默认组合由 GameData 声明：先把声明的那两个模板从池里取出，
	#其余玩家再按加载顺序分剩下的。声明为空或找不到模板时退化为纯顺序分配（不猜、不报错）
	var local_master = _take_named(masters_can_use, GameData.default_master) if assignments.is_empty() else null
	var local_servant = _take_named(servants_can_use, GameData.default_servant) if assignments.is_empty() else null
	var next_master:int = 0
	var next_servant:int = 0

	for i in ids.size():
		var id:int = int(ids[i])
		var player_data = GameDataManager.get_player_data(id) as Dictionary
		player_data["is_out"] = false
		player_data["order"].set_num(BaseNumber.new(order_ids.find(id)))
		#玩家名是玩家级数据：开局按号位写默认名，界面与查询 op 只读这个字段
		player_data["player_name"] = GameData.default_player_name_pattern % (i + 1)
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
		if not assignments.is_empty():
			master = assignments[id]["master"]
			servant = assignments[id]["servant"]
		#未加载到御主/从者的测试玩家保留空归属。
		if master != null:
			player_data["master"] = master
			# 初始御主也是历史事实，供“第一名御主”类卡牌规则查询。
			GameLog.record("master_assigned", id, -1, "", master, ["master_assigned"], {"effect_name": ""})
		if servant != null:
			player_data["servant"] = servant
			GameLog.record("servant_assigned", id, -1, "", servant, ["servant_assigned"], {"effect_name": ""})
		MasterManager.bind_master_effects(id)
		MasterManager.deal_initial_master_cards(id)
		MasterManager.bind_command_spell_effects(id)
		ServantManager.bind_servant_effects(id)

	GameProgress.start_game()
	return true


## 此入口只验证完整角色归属；职阶池等模式规则由选人模式负责。
func validate_assignments(ids:Array, assignments:Dictionary) -> bool:
	if ids.is_empty() or assignments.size() != ids.size():
		return false
	var masters := get_masters_can_use()
	var servants := get_servants_can_use()
	var used_masters:Array = []
	var used_servants:Array = []
	var used_ids:Array = []
	for id in ids:
		if not id is int or used_ids.has(id) or not assignments.get(id) is Dictionary:
			return false
		used_ids.append(id)
		var master = assignments[id].get("master")
		var servant = assignments[id].get("servant")
		if not masters.has(master) or not servants.has(servant):
			return false
		if used_masters.has(master._name) or used_servants.has(servant._name):
			return false
		used_masters.append(master._name)
		used_servants.append(servant._name)
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


#结束当前对局并把引擎恢复到「可以再开一局」的状态：对局内所有进度作废。
#只负责编排顺序，各模块的清理内容由模块自己维护：
#先释放整局对象图（卡牌、效果、玩家数据与各加载器缓存），再复位进度/地图/模板加载器。
#模板必须重载，因为 release_game_objects 连已加载的御主/从者模板一起释放了
func end_session() -> void:
	GameData.release_game_objects()
	GameProgress.reset_progress()
	MapData.reset_board()
	LoadGame.reload_game()
	GameData.setup_players()
	masters_can_use.clear()
	servants_can_use.clear()
	reset()


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
