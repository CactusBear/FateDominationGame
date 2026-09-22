class_name DebugIdentityAdapter
extends RefCounted

## 身份替换只组合现有原语。所有玩家牌区都按对象 from 引用清退，不按牌名猜来源。

var _recycled_cards:Array = []


func inspect_identity(player_id:int) -> Dictionary:
	if !GameData.player_data_library.has(player_id):
		return _fail("玩家不存在")
	var d:Dictionary = GameData.player_data_library[player_id]
	return {"ok":true, "changed":false, "player_id":player_id, "value":{
		"master":_summary(d.get("master")),
		"servant":_summary(d.get("servant")),
		"master_owners":_owners_of(d.get("master"), "master"),
		"servant_owners":_owners_of(d.get("servant"), "servant"),
		"command_spell_clones":d.get("out_of_game", {}).get("command_spell", []).size()
	}}


func set_master(player_id:int, master_name:String, occupancy:String = "exclusive", rebind_command_spell:bool = true, master_zone:String = "clear", replay_game_start:bool = false) -> Dictionary:
	if replay_game_start:
		return _fail("首版禁止重放 GAME_START")
	if !_valid_occupancy(occupancy):
		return _fail("occupancy 只支持 exclusive 或 steal；拒绝 allow_duplicate")
	var new_master = _find_template(GameData.loaded_masters, master_name)
	if new_master == null:
		return _fail("御主模板不存在")
	var conflict := _conflicting_owner(new_master, "master", player_id)
	if conflict != -1 and occupancy == "swap":
		#交换：双方互换御主与各自的随附状态，不退役任何牌
		return _swap_master(player_id, conflict, rebind_command_spell)
	if conflict != -1:
		if occupancy == "exclusive":
			return _fail("御主已被其他玩家占用")
		var stolen := unequip_master(conflict, master_zone)
		if !stolen.ok:
			return stolen
	var removed := unequip_master(player_id, master_zone)
	if !removed.ok:
		return removed
	SetPlayerData.new().exec("master", new_master, player_id)
	RegisterObjectEffects.new().exec(new_master, player_id)
	#御主自带的随附状态（如远坂凛的【宝石】）必须一并交给新持有者：
	#它挂在 specials.BUFFS 上，不跟着 _effects 走。漏掉这一步会出现
	#“换了御主、卡面也对了，但宝石能力永远点不出来”
	_attach_owner_buffs(new_master, player_id)
	if rebind_command_spell:
		_rebind_command_spell(player_id)
	return {"ok":true, "changed":true, "player_id":player_id, "object_id":new_master.get_instance_id(), "value":_summary(new_master)}


func set_servant(player_id:int, servant_name:String, occupancy:String = "exclusive", dealt_zones:String = "replace", true_name:String = "keep_log", rebind_command_spell:bool = true) -> Dictionary:
	if !_valid_occupancy(occupancy):
		return _fail("occupancy 只支持 exclusive / steal / swap；拒绝 allow_duplicate")
	if !_valid_dealt_zones(dealt_zones):
		return _fail("dealt_zones 只支持 replace / keep / swap")
	var new_servant = _find_template(GameData.loaded_servants, servant_name)
	if new_servant == null:
		return _fail("从者模板不存在")
	var conflict := _conflicting_owner(new_servant, "servant", player_id)
	if conflict != -1 and occupancy == "swap":
		#交换：双方互换从者与各自已发到玩家区的牌，不退役、不重发
		return _swap_servant(player_id, conflict, dealt_zones, true_name, rebind_command_spell)
	if conflict != -1:
		if occupancy == "exclusive":
			return _fail("从者已被其他玩家占用")
		var stolen := unequip_servant(conflict, dealt_zones, true_name)
		if !stolen.ok:
			return stolen
	var removed := unequip_servant(player_id, dealt_zones, true_name)
	if !removed.ok:
		return removed
	SetPlayerData.new().exec("servant", new_servant, player_id)
	RegisterObjectEffects.new().exec(new_servant, player_id)
	#从者自带的随附状态与御主同理，换人时一并交给新持有者
	_attach_owner_buffs(new_servant, player_id)
	if dealt_zones == "replace":
		# 只向目标玩家发牌，绝不使用 -1 触发全员重发。
		DealPlayerCards.new().exec(player_id)
	if rebind_command_spell:
		_rebind_command_spell(player_id)
	return {"ok":true, "changed":true, "player_id":player_id, "object_id":new_servant.get_instance_id(), "value":_summary(new_servant)}


##交换双方的御主。不走 unequip_master：交换不是"卸下"，
##旧御主随旧持有者一起去对方手里，牌区不该被搬进游戏外
func _swap_master(player_id:int, other_id:int, rebind_command_spell:bool) -> Dictionary:
	var data:Dictionary = GameData.player_data_library
	var mine = data[player_id].get("master")
	var theirs = data[other_id].get("master")
	if mine == null or theirs == null:
		return _fail("交换御主需要双方都持有御主")
	UnregisterObjectEffects.new().exec(mine)
	UnregisterObjectEffects.new().exec(theirs)
	#随附状态随御主一起对调：交接的是同一批实例，已消耗的层数（宝石等）原样保留，
	#既不销毁重建，也不按名字猜归属
	_hand_over_buffs(_buffs_from_owner(player_id, mine), player_id, other_id)
	_hand_over_buffs(_buffs_from_owner(other_id, theirs), other_id, player_id)
	SetPlayerData.new().exec("master", theirs, player_id)
	SetPlayerData.new().exec("master", mine, other_id)
	RegisterObjectEffects.new().exec(theirs, player_id)
	RegisterObjectEffects.new().exec(mine, other_id)
	if rebind_command_spell:
		#令咒按(御主,从者)解析：御主换了就要重绑，先清后绑保证每人只留一份
		_rebind_command_spell(player_id)
		_rebind_command_spell(other_id)
	return {"ok":true, "changed":true, "player_id":player_id, "other_player":other_id,
		"object_id":theirs.get_instance_id(), "value":_summary(theirs)}


##交换双方的从者与已发到玩家区的牌。
##牌按同名区整批对搬：卡实例、被效果改过的数值与排列顺序都保留；
##不搬进游戏外、也不重新发牌——重发会丢掉这些状态，那正是"换完旧牌全进游戏外"的成因
func _swap_servant(player_id:int, other_id:int, dealt_zones:String, true_name:String, rebind_command_spell:bool) -> Dictionary:
	if !_valid_dealt_zones(dealt_zones):
		return _fail("dealt_zones 只支持 replace / keep / swap")
	var data:Dictionary = GameData.player_data_library
	var mine = data[player_id].get("servant")
	var theirs = data[other_id].get("servant")
	if mine == null or theirs == null:
		return _fail("交换从者需要双方都持有从者")
	UnregisterObjectEffects.new().exec(mine)
	UnregisterObjectEffects.new().exec(theirs)
	if dealt_zones == "swap":
		_transfer_cards_from_source(player_id, other_id, mine)
		_transfer_cards_from_source(other_id, player_id, theirs)
	if true_name == "hide_if_released":
		for id in [player_id, other_id]:
			if ReleaseTrueName.is_released(id):
				HideTrueName.new().exec(id)
	_hand_over_buffs(_buffs_from_owner(player_id, mine), player_id, other_id)
	_hand_over_buffs(_buffs_from_owner(other_id, theirs), other_id, player_id)
	SetPlayerData.new().exec("servant", theirs, player_id)
	SetPlayerData.new().exec("servant", mine, other_id)
	RegisterObjectEffects.new().exec(theirs, player_id)
	RegisterObjectEffects.new().exec(mine, other_id)
	if rebind_command_spell:
		_rebind_command_spell(player_id)
		_rebind_command_spell(other_id)
	return {"ok":true, "changed":true, "player_id":player_id, "other_player":other_id,
		"object_id":theirs.get_instance_id(), "value":_summary(theirs)}


##把 from_id 名下、来源是 source 的已发牌整批转给 to_id 的同名牌区。
##按牌区路径名对搬（deck→deck、side.skills→side.skills），因此不写死卡牌类型与目标区；
##目标玩家或源玩家没有该牌区时跳过，不做兜底猜测
func _transfer_cards_from_source(from_id:int, to_id:int, source) -> void:
	var zones:Dictionary = DebugValidate.player_zones(from_id)
	for raw_path in zones.keys():
		var path := str(raw_path)
		var zone:Array = zones[raw_path]
		var destination = _zone_by_path(to_id, path)
		if !(destination is Array) or destination == zone:
			continue
		for card in zone.duplicate():
			if !(card is BaseCard) or !_source_is(card, source):
				continue
			UnregisterObjectEffects.new().exec(card)
			DrawCardByCard.new().exec(card, zone, destination)
			RegisterObjectEffects.new().exec(card, to_id)


##按路径取牌区（"deck"、"side.skills" 这类），取不到返回 null
func _zone_by_path(player_id:int, path:String):
	if !GameData.player_data_library.has(player_id):
		return null
	var current = GameData.player_data_library[player_id]
	for part in path.split("."):
		if !(current is Dictionary) or !current.has(part):
			return null
		current = current[part]
	return current if current is Array else null


##某个持有者当前持有的、来源指向 owner 的状态对象。
##判定用状态对象自己的 from 引用，不按名字或后缀猜——猜错会把别人的状态搬走
func _buffs_from_owner(player_id:int, owner) -> Array:
	var result:Array = []
	if owner == null or !GameData.player_data_library.has(player_id):
		return result
	for buff in GameData.player_data_library[player_id].get("buffs", []):
		if buff is BaseBuff and _source_is(buff, owner):
			result.append(buff)
	return result


##把状态对象从一名玩家交接给另一名：先摘登记再挂上，效果归属随人走
func _hand_over_buffs(buffs:Array, from_id:int, to_id:int) -> void:
	for buff in buffs:
		ManageBuff.new().exec(buff, from_id, false)
		ManageBuff.new().exec(buff, to_id, true)


##御主/从者自带的随附状态（specials.BUFFS）交给新持有者。
##已被别人持有的实例不抢：同一个实例被两名玩家同时持有会让他们的效果争同一个触发者
func _attach_owner_buffs(owner, player_id:int) -> void:
	if owner == null or !("_specials" in owner):
		return
	for buff in owner._specials.get("BUFFS", []):
		if !(buff is BaseBuff) or _held_by_other(buff, player_id):
			continue
		ManageBuff.new().exec(buff, player_id, true)


##把该持有者名下、来源指向 owner 的状态对象摘掉（卸下御主/从者时用）。
##来源判定：状态对象自己的 from 指向 owner，或它本身就是 owner 声明的 BUFFS 之一
##（后者兼容历史上没设 from 的实例）
func _detach_owner_buffs(owner, player_id:int) -> void:
	if owner == null or !GameData.player_data_library.has(player_id):
		return
	var declared:Array = owner._specials.get("BUFFS", []) if "_specials" in owner else []
	for buff in GameData.player_data_library[player_id].get("buffs", []).duplicate():
		if _source_is(buff, owner) or declared.has(buff):
			ManageBuff.new().exec(buff, player_id, false)


func _held_by_other(buff, player_id:int) -> bool:
	for raw_id in GameData.player_data_library.keys():
		if int(raw_id) == player_id:
			continue
		if (GameData.player_data_library[raw_id].get("buffs", []) as Array).has(buff):
			return true
	return false


func set_pair(player_id:int, master_name:String, servant_name:String, occupancy:String = "exclusive", order:String = "master_first") -> Dictionary:
	var first:Dictionary
	var second:Dictionary
	if order == "servant_first":
		first = set_servant(player_id, servant_name, occupancy, "replace", "keep_log", false)
		if !first.ok:
			return first
		second = set_master(player_id, master_name, occupancy, true, "clear", false)
	else:
		first = set_master(player_id, master_name, occupancy, false, "clear", false)
		if !first.ok:
			return first
		second = set_servant(player_id, servant_name, occupancy, "replace", "keep_log", true)
	second["partial_steps"] = [first]
	return second


func unequip_master(player_id:int, master_zone:String = "clear") -> Dictionary:
	if !GameData.player_data_library.has(player_id):
		return _fail("玩家不存在")
	if !["keep", "clear"].has(master_zone):
		return _fail("master_zone 只支持 keep 或 clear")
	var d:Dictionary = GameData.player_data_library[player_id]
	var old = d.get("master")
	if old == null:
		_clear_command_spells(player_id)
		return {"ok":true, "changed":false, "player_id":player_id}
	UnregisterObjectEffects.new().exec(old)
	_detach_owner_buffs(old, player_id)
	_clear_command_spells(player_id)
	# 即使 master_zone=keep，也不能把来自旧御主的可发动牌留在活动区；
	# keep 仅保留与旧御主无关的现有御主技能牌。
	_retire_cards_from_source(player_id, old, master_zone == "clear")
	SetPlayerData.new().exec("master", null, player_id)
	return {"ok":true, "changed":true, "player_id":player_id, "object_id":old.get_instance_id(), "value":null}


func unequip_servant(player_id:int, dealt_zones:String = "replace", true_name:String = "keep_log") -> Dictionary:
	if !GameData.player_data_library.has(player_id):
		return _fail("玩家不存在")
	if !_valid_removal_dealt_zones(dealt_zones):
		return _fail("dealt_zones 只支持 replace 或 keep")
	if !["keep_log", "hide_if_released"].has(true_name):
		return _fail("true_name 参数无效")
	var d:Dictionary = GameData.player_data_library[player_id]
	var old = d.get("servant")
	if old == null:
		return {"ok":true, "changed":false, "player_id":player_id}
	UnregisterObjectEffects.new().exec(old)
	if dealt_zones == "replace":
		_retire_cards_from_source(player_id, old, true)
	_detach_owner_buffs(old, player_id)
	if true_name == "hide_if_released" and ReleaseTrueName.is_released(player_id):
		HideTrueName.new().exec(player_id)
	_clear_command_spells(player_id)
	SetPlayerData.new().exec("servant", null, player_id)
	return {"ok":true, "changed":true, "player_id":player_id, "object_id":old.get_instance_id(), "value":null}


func equip_master(player_id:int, master_name:String, occupancy:String = "exclusive", rebind_command_spell:bool = true, master_zone:String = "clear", replay_game_start:bool = false) -> Dictionary:
	return set_master(player_id, master_name, occupancy, rebind_command_spell, master_zone, replay_game_start)


func equip_servant(player_id:int, servant_name:String, occupancy:String = "exclusive", dealt_zones:String = "replace", true_name:String = "keep_log", rebind_command_spell:bool = true) -> Dictionary:
	return set_servant(player_id, servant_name, occupancy, dealt_zones, true_name, rebind_command_spell)


func _retire_cards_from_source(player_id:int, source, include_all_dealt_zones:bool) -> void:
	var zones:Dictionary = DebugValidate.player_zones(player_id)
	# 快照遍历所有区域。卡的 from 由加载器/克隆契约保留，按引用判断归属。
	for path in zones.keys():
		var zone:Array = zones[path]
		for card in zone.duplicate():
			if !(card is BaseCard):
				continue
			if !_source_is(card, source):
				continue
			if !include_all_dealt_zones and str(path) != "master_skills":
				continue
			var destination:Array = _retirement_zone(player_id, card)
			if zone == destination:
				continue
			UnregisterObjectEffects.new().exec(card)
			DrawCardByCard.new().exec(card, zone, destination)


func _retirement_zone(player_id:int, card) -> Array:
	var out:Dictionary = GameData.player_data_library[player_id]["out_of_game"]
	if card is BaseAttack:
		return out["attacks"]
	if card is BaseSkill:
		return out["skills"]
	return out["others"]


func _clear_command_spells(player_id:int) -> void:
	var d:Dictionary = GameData.player_data_library[player_id]
	var command_spells:Array = d.get("out_of_game", {}).get("command_spell", [])
	for card in command_spells.duplicate():
		UnregisterObjectEffects.new().exec(card)
		command_spells.erase(card)
		_recycled_cards.append(card)
		card.del()
	# 兼容历史数据可能把令咒放进其它区域：仍按卡模板来源引用清退。
	for path in DebugValidate.player_zones(player_id):
		var zone:Array = DebugValidate.player_zones(player_id)[path]
		if zone == command_spells:
			continue
		for card in zone.duplicate():
			if card is BaseCard and _is_command_spell_clone(card):
				UnregisterObjectEffects.new().exec(card)
				zone.erase(card)
				_recycled_cards.append(card)
				card.del()


func _rebind_command_spell(player_id:int) -> void:
	# 先清后绑，重复调用也始终至多保留一份令咒克隆及其效果。
	_clear_command_spells(player_id)
	MasterManager.bind_command_spell_effects(player_id)


func _is_command_spell_clone(card) -> bool:
	if card == null:
		return false
	for template in LoadCommandSpell.command_spells.values():
		if card == template:
			return true
		if card._name == template._name and card.get_from() == template.get_from():
			return true
	return false


func _source_is(object, source) -> bool:
	if object == null or source == null or !("from" in object):
		return false
	var owner = object.get_from() if object.has_method("get_from") else object.from
	return owner == source


func _find_template(pool:Array, object_name:String):
	for object in pool:
		if object != null and (object._name == object_name or str(object.get_instance_id()) == object_name):
			return object
	return null


func _conflicting_owner(object, key:String, target_id:int) -> int:
	for raw_id in GameData.player_data_library.keys():
		var player_id:int = int(raw_id)
		if player_id != target_id and GameData.player_data_library[player_id].get(key) == object:
			return player_id
	return -1


func _owners_of(object, key:String) -> Array:
	var owners:Array = []
	if object == null:
		return owners
	for raw_id in GameData.player_data_library.keys():
		if GameData.player_data_library[raw_id].get(key) == object:
			owners.append(int(raw_id))
	return owners


##已发牌区的处理政策：replace=清退旧从者的牌并重发，keep=原样保留，swap=与交换对象对调牌区
const DEALT_ZONE_POLICIES:Array = ["replace", "keep", "swap"]
##单独"卸下"时只有这两种：swap 必须有交换对象，没有对象的交换不成立
const REMOVAL_DEALT_ZONE_POLICIES:Array = ["replace", "keep"]


func _valid_occupancy(value:String) -> bool:
	return ["exclusive", "steal", "swap"].has(value)


func _valid_dealt_zones(value:String) -> bool:
	return DEALT_ZONE_POLICIES.has(value)


func _valid_removal_dealt_zones(value:String) -> bool:
	return REMOVAL_DEALT_ZONE_POLICIES.has(value)


func _summary(object):
	if object == null:
		return null
	return {"id":object.get_instance_id(), "name":object._name, "shown_name":object.get_shown_name()}


func _fail(reason:String) -> Dictionary:
	return {"ok":false, "changed":false, "error":reason}
