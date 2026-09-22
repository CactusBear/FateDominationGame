class_name DebugCommandRegistry
extends RefCounted

## 命令注册表是唯一写入口白名单：按钮提交结构化参数，参数名与校验只在这里定义。
## 玩家必须显式给出，local 别名只在这里翻译。

var session:DebugSession
var player := DebugPlayerAdapter.new()
var card := DebugCardAdapter.new()
var map:DebugMapAdapter
var board:DebugBoardAdapter
var identity := DebugIdentityAdapter.new()
var _console_pause_tokens:Array = []

var schemas:Dictionary = {
	"inspect.player": _schema("inspect", true, false, "none", ["player"]),
	"inspect.card": _schema("inspect", false, false, "none", ["id"]),
	"inspect.board": _schema("inspect", false, false, "none", []),
	"inspect.wait": _schema("inspect", false, false, "none", []),
	"inspect.log": _schema("inspect", false, false, "none", []),
	"inspect.identity": _schema("inspect", true, false, "none", ["player"]),
	"resource.magic": _schema("board_edit", true, false, "local", ["player"]),
	"resource.score": _schema("board_edit", true, false, "local", ["player"]),
	"resource.power": _schema("board_edit", true, false, "local", ["player"]),
	"resource.sync_power": _schema("board_edit", true, false, "none", ["player"]),
	"resource.number": _schema("board_edit", true, false, "local", ["player", "key"]),
	"zone.move": _schema("board_edit", false, false, "local", ["card_id", "to"]),
	"zone.add_clone": _schema("board_edit", true, false, "none", ["player", "source_name", "to"]),
	"zone.draw": _schema("rule_action", true, true, "forbidden", ["player"]),
	"zone.refill_hand": _schema("rule_action", true, true, "forbidden", ["player"]),
	"zone.shuffle": _schema("board_edit", true, false, "none", ["player", "zone"]),
	"card.swap_zones": _schema("board_edit", true, false, "none", ["player", "other_player", "from_zone", "to_zone"]),
	"card.cost": _schema("board_edit", false, false, "local", ["card_id"]),
	"card.power": _schema("board_edit", false, false, "local", ["card_id"]),
	"card.attrs": _schema("board_edit", false, false, "local", ["card_id"]),
	"card.conceal": _schema("board_edit", false, false, "local", ["card_id", "bool"]),
	"card.close": _schema("rule_action", false, true, "forbidden", ["card_id"]),
	"map.deploy": _schema("rule_action", true, true, "forbidden", ["player", "area"]),
	"map.move": _schema("rule_action", true, true, "forbidden", ["player", "steps"]),
	"map.teleport": _schema("board_edit", true, false, "forbidden", ["player", "location_id"]),
	"map.leave": _schema("board_edit", true, false, "forbidden", ["player"]),
	"play.regular": _schema("rule_action", true, true, "forbidden", ["player", "cards", "hidden"]),
	"play.extra_attack": _schema("rule_action", true, true, "forbidden", ["player", "card_id"]),
	"play.extra_skill": _schema("rule_action", true, true, "forbidden", ["player", "card_id"]),
	"name.release": _schema("rule_action", true, true, "forbidden", ["player"]),
	"name.hide": _schema("rule_action", true, true, "forbidden", ["player"]),
	"out.eliminate": _schema("rule_action", true, true, "forbidden", ["player"]),
	"out.restore": _schema("board_edit", true, false, "forbidden", ["player"]),
	"buff.add": _schema("board_edit", true, true, "forbidden", ["player", "buff_id"]),
	"buff.remove": _schema("board_edit", true, true, "forbidden", ["player", "buff_id"]),
	"buff.defeat": _schema("rule_action", true, true, "forbidden", ["player"]),
	"buff.undead": _schema("rule_action", true, true, "forbidden", ["player"]),
	"event.place": _schema("board_edit", false, true, "forbidden", ["area"]),
	"event.clear": _schema("board_edit", false, false, "forbidden", []),
	"event.reveal_planned": _schema("rule_action", false, true, "forbidden", []),
	"situation.activate": _schema("rule_action", false, true, "forbidden", []),
	"situation.clear": _schema("board_edit", false, false, "forbidden", []),
	"situation.replace": _schema("board_edit", false, true, "forbidden", ["source_name"]),
	"identity.set_master": _idle_schema("board_edit", true, true, "forbidden", ["player", "master_name"]),
	"identity.set_servant": _idle_schema("board_edit", true, true, "forbidden", ["player", "servant_name"]),
	"identity.set_pair": _idle_schema("board_edit", true, true, "forbidden", ["player", "master_name", "servant_name"]),
	"identity.unequip_master": _idle_schema("board_edit", true, true, "forbidden", ["player"]),
	"identity.equip_master": _idle_schema("board_edit", true, true, "forbidden", ["player", "master_name"]),
	"identity.unequip_servant": _idle_schema("board_edit", true, true, "forbidden", ["player"]),
	"identity.equip_servant": _idle_schema("board_edit", true, true, "forbidden", ["player", "servant_name"]),
	"session.pause": _schema("board_edit", false, false, "none", []),
	"session.resume": _schema("board_edit", false, false, "none", []),
	"session.undo": _schema("board_edit", false, false, "none", []),
	"session.step_action": _idle_schema("rule_action", false, true, "forbidden", []),
	"session.step_ai": _idle_schema("rule_action", true, true, "forbidden", ["player"]),
	"wait.yes": _schema("rule_action", false, false, "forbidden", []),
	"wait.no": _schema("rule_action", false, false, "forbidden", []),
	"wait.option": _schema("rule_action", false, false, "forbidden", ["selection"]),
	"wait.cards": _schema("rule_action", false, false, "forbidden", ["cards"]),
	"wait.location": _schema("rule_action", false, false, "forbidden", ["location_id"]),
	"wait.players": _schema("rule_action", false, false, "forbidden", ["players"])
}


func _init(p_session:DebugSession):
	session = p_session
	map = DebugMapAdapter.new(card, session.host)
	board = DebugBoardAdapter.new(map)


static func _schema(scope:String, player_required:bool, emits_time_points:bool, undo_level:String, required:Array) -> Dictionary:
	return {"name":"", "scope":scope, "params":{"required":required, "player_required":player_required},
		"requires_idle":false, "emits_time_points":emits_time_points,
		"undo_level":undo_level, "steps":[], "validate":scope != "inspect"}


static func _idle_schema(scope:String, player_required:bool, emits_time_points:bool, undo_level:String, required:Array) -> Dictionary:
	var result := _schema(scope, player_required, emits_time_points, undo_level, required)
	result.requires_idle = true
	return result


func command_names() -> Array:
	var result:Array = schemas.keys()
	result.sort()
	return result


func schema(command_name:String) -> Dictionary:
	var result:Dictionary = schemas.get(command_name, {}).duplicate(true)
	if !result.is_empty():
		result.name = command_name
	return result


## 唯一写入口：按钮提交结构化参数，经白名单、必填项、idle 与运行态校验后才分发。
func execute_action(command_name:String, args:Dictionary = {}) -> Dictionary:
	if !schemas.has(command_name):
		return _fail("未登记命令：%s" % command_name)
	var spec:Dictionary = schema(command_name)
	for required in spec.params.required:
		if !args.has(required):
			return _fail("缺少参数：%s" % required)
	if bool(spec.params.player_required):
		var id_check := _player(args)
		if !id_check.ok:
			return id_check
	if bool(spec.requires_idle) and !session.is_idle():
		return _fail("命令 requires_idle：先完成或取消当前等待")
	if spec.scope != "inspect" and EffectManager.is_running:
		return _fail("效果管线正在同步执行，禁止写入")
	var result:Dictionary = _dispatch(command_name, args)
	result["params"] = args.duplicate(true)
	return result


func _dispatch(command_name:String, a:Dictionary) -> Dictionary:
	var id:int = _player(a).id if a.has("player") else -2147483648
	match command_name:
		"inspect.player": return player.inspect_player(id)
		"inspect.card": return card.inspect_card(int(a.id))
		"inspect.board": return map.inspect_board()
		"inspect.wait": return _inspect_wait()
		"inspect.log": return _inspect_log(a)
		"inspect.identity": return identity.inspect_identity(id)
		"resource.magic", "resource.score", "resource.power": return player.set_resource(command_name.get_slice(".", 1), id, a.get("set"), a.get("vary"), bool(a.get("emits_time_points", true)))
		"resource.sync_power": return player.sync_power(id)
		"resource.number": return player.edit_number(id, str(a.key), a.get("set"), a.get("vary"), a.get("min"), a.get("max"))
		"zone.move": return card.move_card(int(a.card_id), str(a.to), id if a.has("player") else null, a.get("index", -1))
		"zone.add_clone": return card.add_clone(id, str(a.source_name), str(a.to))
		"zone.draw": return card.draw(id)
		"zone.refill_hand": return card.refill(id)
		"zone.shuffle": return card.shuffle(id, str(a.zone))
		"card.swap_zones":
			#两名玩家都必须是真实存在的玩家：交换是双向的，落单的 id 一律拒绝
			var other:int = player.player_id(a.other_player)
			if other == -2147483648:
				return _fail("对方玩家 id 无效或不存在")
			return card.swap_zones(id, other, str(a.from_zone), str(a.to_zone))
		"card.cost": return card.edit_cost(int(a.card_id), a.get("set"), a.get("vary"))
		"card.power": return card.edit_power(int(a.card_id), a.get("set"), a.get("vary"))
		"card.attrs": return card.edit_attributes(int(a.card_id), _array(a.get("add", [])), _array(a.get("remove", [])), _array(a.set) if a.has("set") else null)
		"card.conceal": return card.conceal(int(a.card_id), bool(a.bool))
		"card.close": return card.close(int(a.card_id))
		"map.deploy": return map.deploy(id, str(a.area))
		"map.move": return map.move(id, int(a.steps), bool(a.get("ignore_limit", false)), bool(a.get("ignore_battle", false)))
		"map.teleport": return map.teleport(id, int(a.location_id))
		"map.leave": return map.leave(id)
		"play.regular": return map.regular_play(id, _int_array(a.cards), _bool_array(a.hidden))
		"play.extra_attack": return map.extra_play(id, int(a.card_id), "attack")
		"play.extra_skill": return map.extra_play(id, int(a.card_id), "skill")
		"name.release": return map.release_name(id)
		"name.hide": return map.hide_name(id)
		"out.eliminate": return player.eliminate(id)
		"out.restore": return player.restore(id)
		"buff.add": return player.manage_buff(id, player.find_buff(int(a.buff_id)), true)
		"buff.remove": return player.manage_buff(id, player.find_buff(int(a.buff_id)), false)
		"buff.defeat": return player.set_defeat(id, true)
		"buff.undead": return player.set_defeat(id, false)
		"event.place": return board.place_event(str(a.area), bool(a.get("concealed", false)), int(a.get("count", 1)))
		"event.clear": return board.clear_events()
		"event.reveal_planned": return board.reveal_planned()
		"situation.activate": return board.activate_situation()
		"situation.clear": return board.clear_situation()
		"situation.replace": return board.replace_situation(str(a.source_name), bool(a.get("grant_printed_magic", false)))
		"identity.set_master", "identity.equip_master": return identity.set_master(id, str(a.master_name), str(a.get("occupancy", "exclusive")), bool(a.get("rebind_command_spell", true)), str(a.get("master_zone", "clear")), bool(a.get("replay_game_start", false)))
		"identity.set_servant", "identity.equip_servant": return identity.set_servant(id, str(a.servant_name), str(a.get("occupancy", "exclusive")), str(a.get("dealt_zones", "replace")), str(a.get("true_name", "keep_log")), bool(a.get("rebind_command_spell", true)))
		"identity.set_pair": return identity.set_pair(id, str(a.master_name), str(a.servant_name), str(a.get("occupancy", "exclusive")), str(a.get("order", "master_first")))
		"identity.unequip_master": return identity.unequip_master(id, str(a.get("master_zone", "clear")))
		"identity.unequip_servant": return identity.unequip_servant(id, str(a.get("dealt_zones", "replace")), str(a.get("true_name", "keep_log")))
		"session.pause": return _pause()
		"session.resume": return _resume(a)
		"session.undo": return session.undo_last()
		"session.step_action": return session.step_action()
		"session.step_ai": return session.step_ai(id)
		"wait.yes": return _wait_active(true)
		"wait.no": return _wait_active(false)
		"wait.option": return _wait_option(a.selection)
		"wait.cards": return _wait_cards(_int_array(a.cards))
		"wait.location": return _wait_location(int(a.location_id))
		"wait.players": return _wait_players(_int_array(a.players))
	return _fail("命令已登记但未实现分发")


func _player(args:Dictionary) -> Dictionary:
	if !args.has("player"):
		return _fail("玩家 id 必须显式传入；本地玩家写 player=local")
	var id:int = player.player_id(args.player)
	if id == -2147483648:
		return _fail("玩家 id 无效或不存在")
	return {"ok":true, "changed":false, "id":id}


func _inspect_wait() -> Dictionary:
	return {"ok":true, "changed":false, "value":{
		"is_running":EffectManager.is_running,
		"waiting_effect":_effect_summary(EffectManager.waiting_effect),
		"waiting_selection":_effect_summary(EffectManager.waiting_selection),
		"waiting_location":_effect_summary(EffectManager.waiting_location),
		"waiting_players":_effect_summary(EffectManager.waiting_players),
		"decision_queue":EffectManager.decision_queue.size()
	}}


func _inspect_log(a:Dictionary) -> Dictionary:
	var filter:Dictionary = a.get("filter", {}) if a.get("filter", {}) is Dictionary else {}
	return {"ok":true, "changed":false, "value":GameLog.query(filter, a.get("round_offset", null), int(a.get("limit", -1)))}


func _pause() -> Dictionary:
	var token:String = session.acquire_pause("console")
	_console_pause_tokens.append(token)
	return {"ok":true, "changed":true, "value":token}


func _resume(a:Dictionary) -> Dictionary:
	var token:String = str(a.get("token", _console_pause_tokens.back() if !_console_pause_tokens.is_empty() else ""))
	if token == "" or !session.release_pause(token):
		return _fail("暂停令牌不存在")
	_console_pause_tokens.erase(token)
	return {"ok":true, "changed":true, "value":token}


func _wait_active(accept:bool) -> Dictionary:
	var effect = EffectManager.waiting_effect
	if effect == null:
		return _fail("当前没有 yes/no 等待")
	var ok:bool = EffectManager.submit_active_choice(effect, accept)
	return {"ok":ok or !accept, "changed":true, "object_id":effect.get_instance_id(), "value":accept}


func _wait_option(selection) -> Dictionary:
	var effect = EffectManager.waiting_effect
	if effect == null:
		return _fail("当前没有选项等待")
	var value = _selection_dict(selection)
	var ok:bool = EffectManager.submit_option_choice(effect, value)
	return {"ok":ok, "changed":true, "object_id":effect.get_instance_id(), "value":value}


func _wait_cards(ids:Array) -> Dictionary:
	var effect = EffectManager.waiting_selection
	if effect == null:
		return _fail("当前没有选牌等待")
	var selected:Array = []
	for id in ids:
		var found = card.find_card(int(id))
		if found == null:
			return _fail("选牌实例不存在")
		selected.append(found)
	var ok:bool = EffectManager.submit_card_selection(effect, selected)
	return {"ok":ok, "changed":true, "object_id":effect.get_instance_id(), "value":ids}


func _wait_location(location_id:int) -> Dictionary:
	# 当前 submit_location_selection 不提供取消协议；本命令只接受真实位置，绝不以 null 强行取消。
	var effect = EffectManager.waiting_location
	if effect == null:
		return _fail("当前没有选位置等待")
	var location = map.find_location(location_id)
	if location == null:
		return _fail("位置实例不存在；wait.location 不支持取消")
	var ok:bool = EffectManager.submit_location_selection(effect, location)
	return {"ok":ok, "changed":true, "object_id":effect.get_instance_id(), "value":location_id}


func _wait_players(ids:Array) -> Dictionary:
	var effect = EffectManager.waiting_players
	if effect == null:
		return _fail("当前没有选玩家等待")
	for id in ids:
		if !GameData.player_data_library.has(int(id)):
			return _fail("候选玩家不存在")
	var ok:bool = EffectManager.submit_player_selection(effect, ids)
	return {"ok":ok, "changed":true, "object_id":effect.get_instance_id(), "value":ids}


func _effect_summary(effect):
	if effect == null:
		return null
	return {"id":effect.get_instance_id(), "name":effect._name, "player_id":effect._trigger_player_id}


## 参数数组化：null 必须变成空数组，不能变成 [null]。
## 否则按钮没选任何卡时 `int(null)` 会抛 `Invalid call. Nonexistent 'int' constructor`；
## 而且这些参数是在进入被调用函数**之前**求值的，函数内部那层"没有等待就返回"的保护救不了它。
func _array(value) -> Array:
	if value == null:
		return []
	return value if value is Array else [value]


func _int_array(value) -> Array:
	var result:Array = []
	for item in _array(value):
		if item == null:
			continue
		result.append(int(item))
	return result


func _bool_array(value) -> Array:
	var result:Array = []
	for item in _array(value):
		if item == null:
			continue
		result.append(bool(item))
	return result


func _selection_dict(value):
	if value is Dictionary:
		var result:Dictionary = {}
		for key in value:
			result[int(key)] = int(value[key])
		return result
	return _int_array(value)


func _fail(reason:String) -> Dictionary:
	return {"ok":false, "changed":false, "error":reason}
