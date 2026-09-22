class_name DebugPlayerAdapter
extends RefCounted

const NUMBER_KEYS:Array = [
	"command_spell_count", "command_spell_limit", "play_limit", "regular_play_min",
	"total_power_bonus", "attack_cost_discount", "move_cost_discount_from_workshop", "order"
]


func player_id(value) -> int:
	if str(value) == "local":
		return GameData.player_id
	if !str(value).is_valid_int():
		return -2147483648
	var id:int = int(value)
	return id if GameData.player_data_library.has(id) else -2147483648


func inspect_player(id:int) -> Dictionary:
	if !GameData.player_data_library.has(id):
		return _fail("玩家不存在")
	var d:Dictionary = GameData.player_data_library[id]
	return {"ok":true, "changed":false, "player_id":id, "value":{
		"player_name":d.get("player_name"),
		"master":_object_summary(d.get("master")),
		"servant":_object_summary(d.get("servant")),
		"magic":_number(d.get("magic")),
		"score":_number(d.get("score")),
		"command_spell_count":_number(d.get("command_spell_count")),
		"is_out":d.get("is_out"),
		"location":_object_summary(d.get("location")),
		"true_name_released":ReleaseTrueName.is_released(id),
		"power":GetPlayerTotalPower.breakdown(id),
		"zones":_zone_counts(id)
	}}


func set_resource(kind:String, id:int, set_value, vary_value, emits_time_points:bool = true) -> Dictionary:
	if !GameData.player_data_library.has(id):
		return _fail("玩家不存在")
	if set_value == null and vary_value == null:
		return _fail("set 与 vary 至少提供一个")
	var d:Dictionary = GameData.player_data_library[id]
	var key:String = {"magic":"magic", "score":"score", "power":"power"}.get(kind, "")
	if key == "":
		return _fail("未知资源类型")
	var target = d.get(key)
	if !(target is BaseNumber):
		return _fail("目标不是 BaseNumber")
	var before = target.number
	var set_num = BaseNumber.new(float(set_value)) if set_value != null else null
	var vary_num = BaseNumber.new(float(vary_value)) if vary_value != null else BaseNumber.new(0)
	if emits_time_points:
		match kind:
			"magic": EditMagic.new().exec(set_num, vary_num, id)
			"score": EditScore.new().exec(set_num, vary_num, id)
			"power": EditPower.new().exec(set_num, vary_num, id)
	else:
		if set_value != null:
			target.set_num(BaseNumber.new(float(set_value)))
		if vary_value != null:
			target.add(BaseNumber.new(float(vary_value)))
	return {"ok":true, "changed":before != target.number, "player_id":id, "before":before, "value":target.number}


func edit_number(id:int, key:String, set_value, vary_value, min_value = null, max_value = null) -> Dictionary:
	if !NUMBER_KEYS.has(key):
		return _fail("数字字段不在控制台白名单")
	if !GameData.player_data_library.has(id):
		return _fail("玩家不存在")
	if set_value == null and vary_value == null:
		return _fail("set 与 vary 至少提供一个")
	var d:Dictionary = GameData.player_data_library[id]
	var before = _number(d.get(key))
	EditDataNumber.new().exec(
		key,
		BaseNumber.new(float(set_value)) if set_value != null else null,
		BaseNumber.new(float(vary_value)) if vary_value != null else BaseNumber.new(0),
		id, min_value, max_value)
	return {"ok":true, "changed":before != _number(d.get(key)), "player_id":id, "before":before, "value":_number(d.get(key))}


func sync_power(id:int) -> Dictionary:
	if !GameData.player_data_library.has(id):
		return _fail("玩家不存在")
	var before = _number(GameData.player_data_library[id].get("power"))
	SyncPower.new().exec(id)
	return {"ok":true, "changed":before != _number(GameData.player_data_library[id].get("power")), "player_id":id, "before":before, "value":_number(GameData.player_data_library[id].get("power"))}


func eliminate(id:int) -> Dictionary:
	if !GameData.player_data_library.has(id):
		return _fail("玩家不存在")
	var ok:bool = ClimaxResolver.new().eliminate_player(id)
	return {"ok":ok, "changed":ok, "player_id":id, "value":ok}


func restore(id:int) -> Dictionary:
	if !GameData.player_data_library.has(id):
		return _fail("玩家不存在")
	var d:Dictionary = GameData.player_data_library[id]
	var changed:bool = bool(d.get("is_out", false))
	SetPlayerData.new().exec("is_out", false, id)
	return {"ok":true, "changed":changed, "player_id":id, "value":false}


func manage_buff(id:int, buff, add:bool) -> Dictionary:
	if !GameData.player_data_library.has(id):
		return _fail("玩家不存在")
	if buff == null or !(buff is BaseBuff):
		return _fail("buff 不存在")
	var target:BaseBuff = buff
	if add:
		# Buff 模板和其他玩家持有的实例都不能直接改写 trigger_player_id；
		# 新增时统一克隆，移除时才要求传目标玩家当前持有的真实实例。
		target = CloneObject.new().exec(buff) as BaseBuff
		if target == null:
			return _fail("buff 克隆失败")
	elif !(GameData.player_data_library[id].get("buffs", []) as Array).has(buff):
		return _fail("目标玩家未持有该 buff 实例")
	var ok:bool = bool(ManageBuff.new().exec(target, id, add))
	return {"ok":ok, "changed":ok, "player_id":id, "object_id":target.get_instance_id()}


func set_defeat(id:int, defeated:bool) -> Dictionary:
	if !GameData.player_data_library.has(id):
		return _fail("玩家不存在")
	if defeated:
		Defeat.new().exec(id)
	else:
		RemoveDefeat.new().exec(id)
	return {"ok":true, "changed":true, "player_id":id}


func find_buff(instance_id:int):
	for object in GameData.objects:
		if object is BaseBuff and object.get_instance_id() == instance_id:
			return object
	return null


func _zone_counts(id:int) -> Dictionary:
	var result:Dictionary = {}
	for path in DebugValidate.player_zones(id):
		result[path] = DebugValidate.player_zones(id)[path].size()
	return result


func _number(value):
	return value.number if value is BaseNumber else value


func _object_summary(object):
	if object == null:
		return null
	var result := {"class":object.get_class(), "id":object.get_instance_id()}
	if "_name" in object:
		result["name"] = object._name
	if object.has_method("get_shown_name"):
		result["shown_name"] = object.get_shown_name()
	return result


func _fail(reason:String) -> Dictionary:
	return {"ok":false, "changed":false, "error":reason}
