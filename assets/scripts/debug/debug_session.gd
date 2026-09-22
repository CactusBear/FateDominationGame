class_name DebugSession
extends RefCounted

## 调试控制台的一局会话。只持有控制台自己的暂停令牌、审计和宿主引用。
## 不暂停 SceneTree，不清空 EffectManager，也不改规则事实日志。

var host
var registry:DebugCommandRegistry
var audit:Array = []
var _pause_tokens:Dictionary = {}
var _next_command_id:int = 1
var _executing:bool = false
var _template_baseline:Dictionary = {}
var _undo_records:Array = []


func _init(p_host = null):
	host = p_host
	_template_baseline = DebugValidate.template_fingerprints()
	registry = DebugCommandRegistry.new(self)


func acquire_pause(owner:String = "console") -> String:
	var token := "%s:%s:%s" % [owner, Time.get_ticks_msec(), _pause_tokens.size()]
	_pause_tokens[token] = owner
	return token


func release_pause(token:String) -> bool:
	if !_pause_tokens.has(token):
		return false
	_pause_tokens.erase(token)
	return true


func release_owner_pauses(owner:String = "console") -> int:
	var removed:int = 0
	for token in _pause_tokens.keys().duplicate():
		if str(_pause_tokens[token]) == owner:
			_pause_tokens.erase(token)
			removed += 1
	return removed


func shutdown() -> void:
	_pause_tokens.clear()
	audit.clear()
	_undo_records.clear()
	_template_baseline.clear()
	host = null
	# DebugSession 与 Registry 互相持有；显式断开，避免 RefCounted 强引用环在禁用控制台后残留。
	if registry != null:
		registry.session = null
	registry = null


func is_paused() -> bool:
	return !_pause_tokens.is_empty()


func pause_owners() -> Array:
	return _pause_tokens.values().duplicate()


func is_idle() -> bool:
	return !EffectManager.is_running and !EffectManager.is_waiting_for_choice()


## 控制台唯一写入口：参数始终是结构化值，经 registry 白名单与校验后执行并记审计。
func execute_action(command_name:String, args:Dictionary = {}) -> Dictionary:
	if _executing:
		return _rejected("已有调试命令正在执行")
	_executing = true
	var command_id:int = _next_command_id
	_next_command_id += 1
	var spec:Dictionary = registry.schema(command_name)
	var before := _runtime_snapshot()
	var result:Dictionary = registry.execute_action(command_name, args)
	var after := _runtime_snapshot()
	var validation:Dictionary = {}
	if bool(result.get("ok", false)) and bool(result.get("changed", false)):
		validation = DebugValidate.validate_all(_template_baseline)
		result["validation"] = validation
	if bool(result.get("changed", false)):
		refresh_host()
	if bool(result.get("ok", false)) and bool(result.get("changed", false)) \
			and str(spec.get("undo_level", "none")) == "local":
		_undo_records.append({
			"command":command_name,
			"args":args.duplicate(true),
			"result":result.duplicate(true)
		})
	var entry := {
		"command_id": command_id,
		"command": command_name,
		"ok": bool(result.get("ok", false)),
		"changed": bool(result.get("changed", false)),
		"player_id": result.get("player_id", null),
		"object_id": result.get("object_id", null),
		"params": result.get("params", {}).duplicate(true),
		"reason": str(result.get("error", "")),
		"before": before,
		"after": after,
		"validation": validation.duplicate(true)
	}
	audit.append(entry)
	result["command_id"] = command_id
	_executing = false
	return result


func step_action() -> Dictionary:
	if !is_paused():
		return _rejected("动作单步只能在调试暂停期间执行")
	if EffectManager.is_running or EffectManager.is_waiting_for_choice():
		return _rejected("效果管线忙碌或等待答复，不能推进动作边界")
	var actor:int = GameProgress.current_player_id
	var ok:bool = GameProgress.end_current_player_action()
	return {"ok":ok, "changed":ok, "player_id":actor, "value":ok}


func undo_last() -> Dictionary:
	if !is_paused():
		return _rejected("撤销只能在调试暂停期间执行")
	if !is_idle():
		return _rejected("效果管线忙碌或等待答复，不能撤销")
	if _undo_records.is_empty():
		return _rejected("没有可撤销的局部编辑")
	var record:Dictionary = _undo_records.back()
	var reverse:Dictionary = _reverse_command(record)
	if reverse.is_empty():
		return _rejected("当前值已变化或该记录不能安全撤销")
	var result:Dictionary = registry.execute_action(str(reverse.command), reverse.args)
	if !bool(result.get("ok", false)):
		return result
	_undo_records.pop_back()
	result["undone_command"] = record.command
	result["reverse_command"] = reverse.duplicate(true)
	return result


func step_ai(player_id:int) -> Dictionary:
	if !is_paused():
		return _rejected("AI 单步只能在调试暂停期间执行")
	if EffectManager.is_running or EffectManager.is_waiting_for_choice():
		return _rejected("效果管线忙碌或等待答复，不能推进 AI")
	if player_id != GameProgress.current_player_id:
		return _rejected("只能单步推进当前行动者")
	if player_id == GameData.player_id:
		return _rejected("当前行动者是本地玩家，不能按 AI 单步推进")
	if host == null or !host.has_method("_run_dummy_bot_turn"):
		return _rejected("宿主未提供 _run_dummy_bot_turn")
	host.call("_run_dummy_bot_turn", player_id)
	return {"ok":true, "changed":true, "player_id":player_id}


func refresh_host() -> void:
	if host != null and host.has_method("refresh_all_ui"):
		host.call("refresh_all_ui")


func audit_entries() -> Array:
	return audit.duplicate(true)


func clear_audit() -> void:
	audit.clear()


## 由记录反推出「把值改回去」的一次结构化调用。返回空字典表示当前值已变化、不可安全撤销。
func _reverse_command(record:Dictionary) -> Dictionary:
	var command:String = str(record.get("command", ""))
	var args:Dictionary = record.get("args", {})
	var result:Dictionary = record.get("result", {})
	var before = result.get("before")
	var after = result.get("value")
	match command:
		"resource.magic", "resource.score", "resource.power":
			var player_id:int = int(result.get("player_id", -2147483648))
			var key:String = command.get_slice(".", 1)
			if !_resource_equals(player_id, key, after): return {}
			# 撤销是就地改回数值，不冒充一次规则动作：显式声明不派时点
			return {"command":command, "args":{"player":player_id, "set":before, "emits_time_points":false}}
		"resource.number":
			var player_id:int = int(result.get("player_id", -2147483648))
			var key:String = str(args.get("key", ""))
			if !_resource_equals(player_id, key, after): return {}
			return {"command":"resource.number", "args":{"player":player_id, "key":key, "set":before}}
		"card.cost", "card.power":
			var card_id:int = int(result.get("object_id", 0))
			var card = registry.card.find_card(card_id)
			var field:String = "_cost" if command == "card.cost" else "_power"
			if card == null or card.get(field).number != after: return {}
			return {"command":command, "args":{"card_id":card_id, "set":before}}
		"card.attrs":
			var card_id:int = int(result.get("object_id", 0))
			var card = registry.card.find_card(card_id)
			if card == null or card._attributes != after: return {}
			return {"command":"card.attrs", "args":{"card_id":card_id, "set":before}}
		"card.conceal":
			var card_id:int = int(result.get("object_id", 0))
			var card = registry.card.find_card(card_id)
			if card == null or bool(card.get("_is_concealed")) != bool(after): return {}
			return {"command":"card.conceal", "args":{"card_id":card_id, "bool":bool(before)}}
		"zone.move":
			var card_id:int = int(result.get("object_id", 0))
			var card = registry.card.find_card(card_id)
			var owner:Dictionary = registry.card.find_card_owner(card)
			if owner.is_empty() or int(owner.player_id) != int(after.get("player_id", -1)) \
					or str(owner.path) != str(after.get("path", "")):
				return {}
			return {"command":"zone.move", "args":{
				"card_id":card_id, "player":before.get("player_id"),
				"to":before.get("path"), "index":before.get("index", -1)}}
	return {}


func _resource_equals(player_id:int, key:String, expected) -> bool:
	if !GameData.player_data_library.has(player_id):
		return false
	var value = GameData.player_data_library[player_id].get(key)
	var current = value.number if value is BaseNumber else value
	return current == expected


func _runtime_snapshot() -> Dictionary:
	return {
		"round": GameProgress.current_round,
		"phase": str(GameProgress.get_current_phase().get("name", "")),
		"current_player_id": GameProgress.current_player_id,
		"effect_running": EffectManager.is_running,
		"waiting": EffectManager.is_waiting_for_choice(),
		"paused": is_paused()
	}


func _rejected(reason:String) -> Dictionary:
	return {"ok":false, "changed":false, "error":reason}
