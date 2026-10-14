extends Node


# 数据驱动私有信息保存 RefCounted 从者对象身份；del() 仅注销，强引用保证比较安全。
# is_instance_valid 同时防止异常主动 free 后的失效实例参与比较。公开信息仍由真名解放控制。
static func knows_servant_info(observer_id:int, target_id:int, kind:String = "servant_class") -> bool:
	var observer:Dictionary = GameData.player_data_library.get(observer_id, {})
	var target:Dictionary = GameData.player_data_library.get(target_id, {})
	var servant = target.get("servant")
	if not is_instance_valid(servant):
		return false
	var knowledge = observer.get("known_info", {})
	if not knowledge is Dictionary:
		return false
	var category = knowledge.get(kind, {})
	return category is Dictionary and is_instance_valid(category.get(target_id)) and is_same(category.get(target_id), servant)


static func can_see_servant_class(observer_id:int, target_id:int) -> bool:
	return ReleaseTrueName.is_released(target_id) or knows_servant_info(observer_id, target_id)


func get_player_data(id:int):
	# D 只读已认证成员；未知 id 不借 getter 建库。
	if SessionGeneration.in_private_frame(): return find_player_data(id)
	#按需建立玩家数据，避免访问尚未初始化的玩家时拿到null
	if !GameData.player_data_library.has(id):
		GameData.player_data_library[id] = GameData.new_player_data()
	var player_data = GameData.player_data_library[id]
	return player_data


#只查询已存在的玩家；未知 id 返回空字典，不建立玩家数据。已有数据仍返回原字典引用。
func find_player_data(id:int) -> Dictionary:
	return GameData.player_data_library.get(id, {})


#只读入口：缺失返回空字典，绝不按需建立玩家；已有数据保留原字典引用。
func get_player_data_readonly(id:int) -> Dictionary:
	return find_player_data(id)


#返回本局仍在场的玩家，顺序与当前顺位一致
func get_active_player_ids() -> Array:
	var result:Array = []
	for id in get_domain_ordered_player_ids():
		var player_data = get_player_data(id) as Dictionary
		if !player_data["is_out"]:
			result.append(id)
	return result


#独立玩家：不受任何人控制（controller 为 -1 或未声明）。只有独立玩家轮流行动、计胜负、参与顺位
func is_independent(id:int) -> bool:
	if !GameData.player_data_library.has(id):
		return false
	return int(GameData.player_data_library[id].get("controller", -1)) == -1


#这名条目在规则上代表谁：分身棋子代表它的控制者，其余（独立玩家、NPC）代表自己。
#战斗胜负、战果、胜败时点按代表者结算——"两位爱丽丝代表同一名玩家"
func represented_id(id:int) -> int:
	if !GameData.player_data_library.has(id):
		return id
	var controller:int = int(GameData.player_data_library[id].get("controller", -1))
	return controller if controller >= 0 else id


#这个字段是不是与控制者共用的同一份数据（add_player 的 shared_keys）。
#牌区遍历（归属快照、一致性检查）跳过共用字段，否则同一张牌会被算成属于两名玩家
func is_shared_with_controller(id:int, key) -> bool:
	if !GameData.player_data_library.has(id):
		return false
	var data:Dictionary = GameData.player_data_library[id]
	var controller:int = int(data.get("controller", -1))
	if controller < 0 or !GameData.player_data_library.has(controller):
		return false
	var value = data.get(key)
	var owner_value = GameData.player_data_library[controller].get(key)
	return (value is Array or value is Dictionary) and is_same(value, owner_value)


#版图上可能参战的全部条目：未出局的独立玩家（按顺位）+ 未出局的受控条目（分身、NPC，按 id）。
#战斗结算与交战判定用它；行动、顺位、胜负、淘汰仍只看 get_active_player_ids
func get_board_player_ids() -> Array:
	var result:Array = get_active_player_ids()
	var controlled:Array = []
	for id in GameData.player_data_library.keys():
		if !is_independent(int(id)) and !bool(GameData.player_data_library[id].get("is_out", true)):
			controlled.append(int(id))
	controlled.sort()
	result.append_array(controlled)
	return result

# 顺位唯一实现：只排独立玩家（分身/NPC 不占顺位），order 相同按 id 兜底保证全序可复现。
# 缺 order 声明不猜默认值：报错并返回空数组（用户裁定 2026-10-13，fail-closed）。
func get_domain_ordered_player_ids() -> Array:
	var ids:Array = []
	for id in GameData.player_data_library:
		if not is_independent(int(id)): continue
		if not find_player_data(int(id)).get("order") is BaseNumber:
			push_error("玩家 %s 缺少 order 顺位声明，无法排顺位" % str(id))
			return []
		ids.append(id)
	ids.sort_custom(func(a, b):
		var l:float = float(find_player_data(int(a)).order.number)
		var r:float = float(find_player_data(int(b)).order.number)
		return l < r if l != r else int(a) < int(b))
	return ids
