extends Node

# 诊断原语组合，不声称普通事件可以识别在场暗牌。
# numeric_modifiers 是待执行器接线的检查式候选；旧 exec 的 BaseNumber 契约不改。
const Router = preload("res://scripts/system/operation_router.gd")
var checks:int = 0
var failures:Array = []
var observations:Array = []
var serial:int = 0
var session_context:Variant = null

func _ready() -> void:
	call_deferred("run")

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok:
		failures.append(label)

func query(id:int, include:Array = [], exclude:Array = []) -> Dictionary:
	var reader = GetPlayerPowerBreakdown.new()
	if reader.has_method("numeric_modifiers"):
		return reader.call("numeric_modifiers", id, include, exclude)
	# 仅 RED 对照：把旧公开接口的真实返回交给同一独立 oracle。
	return {"ok":true, "value":reader.exec(id, include, exclude).number, "route":"legacy_red_control"}

func verify_query(id:int, labels:Array, inc:int, exc:int, label:String) -> void:
	var a:Dictionary = query(id, labels)
	var b:Dictionary = query(id, [], labels)
	check(a.get("ok", false) and a.get("value") == inc, label + " include=" + str(inc))
	check(b.get("ok", false) and b.get("value") == exc, label + " exclude=" + str(exc))
	observations.append({"label":label, "include":a, "exclude":b})

func clean(value):
	if value is BaseNumber:
		return {"instance_id":value.get_instance_id(), "number":value.number}
	if value is Object:
		return {"instance_id":value.get_instance_id(), "script":value.get_script().resource_path if value.get_script() != null else ""} if is_instance_valid(value) else null
	if value is Array:
		var result:Array = []
		for item in value:
			result.append(clean(item))
		return result
	if value is Dictionary:
		var result:Dictionary = {}
		for key in value:
			result[str(key)] = clean(value[key])
		return result
	return value

func facts(id:int) -> Array:
	return GameLog.query({"type":"power_source", "actor":id}, null)

func member(label:String) -> int:
	return AddPlayer.new().exec(-1, [], {"player_name":label}, session_context)

func attack(id:int, hidden:bool = false) -> BaseAttack:
	var card:BaseAttack = BaseAttack.new("same target name", "", [], BaseNumber.new(0), BaseNumber.new(4))
	if hidden:
		Router.exec_registered("set_card_concealed", [card, true, id])
	check(AddAttack.new().exec(card, id), "real AddAttack")
	return card

func descriptor(name:String, args:Array, slot:int = -1) -> Dictionary:
	return {"func_name":name, "parameters":args, "var_index":slot}

func body(id:int, actions:Array, numbers:Array) -> Array:
	var funcs:Array = [descriptor("get_player_played_cards", [id], 0)]
	for action in actions:
		funcs.append(descriptor("get_card_by_index_fr_arr", [int(action.get("target", 0)), {"self_var":0}], 1))
		match str(action.op):
			"edit", "set":
				var index:int = numbers.size()
				numbers.append({"number":action.delta, "can_change":true, "is_pure_number":true})
				if action.op == "set":
					numbers.append({"number":0, "can_change":true, "is_pure_number":true})
				var vary = {"number_index":index if action.op == "edit" else index + 1}
				var assigned = {"number_index":index} if action.op == "set" else null
				funcs.append(descriptor("edit_card_power", [{"self_var":1}, vary, assigned, id]))
			"reveal", "hide":
				funcs.append(descriptor("set_card_concealed", [{"self_var":1}, action.op == "hide", id]))
			"close":
				funcs.append(descriptor("close_card", [{"self_var":1}, id]))
			"direct", "bonus":
				var index:int = numbers.size()
				numbers.append({"number":action.delta, "can_change":true, "is_pure_number":true})
				if action.op == "direct":
					funcs.append(descriptor("edit_power", [null, {"number_index":index}, id]))
				else:
					funcs.append(descriptor("edit_data_number", ["total_power_bonus", null, {"number_index":index}, id]))
	funcs.append(descriptor("get_player_total_power", [id], 2))
	return funcs

# 真实事件进牌堆、克隆、入场、亮出；buff 使用真实注册和时点派发。
func stage(id:int, by:int, kind:String, action_groups:Array) -> Dictionary:
	serial += 1
	var point:String = "self_card_revealed" if kind == "event" else "contribution_probe_" + str(serial)
	var effects:Array = []
	for actions in action_groups:
		var numbers:Array = []
		var funcs:Array = body(id, actions, numbers)
		effects.append({"effect_name":"same effect name", "time_points":[point], "priority":0,
			"is_pure_passive":true, "is_residue":false, "need_activate":false, "source_bound":true,
			"effect_numbers":numbers, "funcs":funcs})
	var owner
	if kind == "event":
		var template:BaseEvent = LoadGame.load_events([{"card_name":"same source name", "card_img":"", "score":{"number":0, "can_change":true, "is_pure_number":true}, "effects":effects}], "", null)[0]
		template._effects = LoadHelper.load_effects(effects, template, session_context)
		check(template._effects.size() == effects.size(), "trusted factory creates current runtime event effects")
		MapData.event_deck.clear()
		MapData.event_deck.append(template)
		var area:BaseMapArea = MapData.areas[0]
		check(Router.exec_registered("add_event_from_deck", [area, 1, false]) == 1, "real event entered")
		owner = area._events.back()
		check(not is_same(owner, template) and is_same(owner.from, area), "real event clone identity")
	else:
		owner = LoadGame.load_buffs([{"buff_name":"same source name", "buff_img":"", "is_active":true,
			"buff_level":{"number":1, "can_change":true, "is_pure_number":true}, "effects":effects}], "", null)[0]
		owner._effects = LoadHelper.load_effects(effects, owner, session_context)
		check(owner._effects.size() == effects.size(), "trusted factory creates current runtime buff effects")
		Router.exec_registered("register_object_effects", [owner, by])
		TimePointChecker.dynamic_time_point([point], by, owner, session_context)
	for effect in owner._effects:
		check(is_same(effect.from, owner), "effect actual source identity")
		check(effect._self_vars.size() > 2 and effect._self_vars[0] is Array and effect._self_vars[1] is BaseHandCard and effect._self_vars[2] is int, "real effect body executed")
		EffectManager.unregister_effect(effect)
	print("SOURCE ", JSON.stringify({"kind":kind, "owner":clean(owner), "effects":clean(owner._effects), "actions":action_groups}))
	return {"owner":owner, "effects":owner._effects}

func eight_cases() -> void:
	# [name, initially hidden, stages, total, event modifier, buff modifier]
	var cases:Array = [
		["event edit reveal", true, [["event", [{"op":"edit", "delta":2}, {"op":"reveal"}]]], 6, 2, 0],
		["event edit only", true, [["event", [{"op":"edit", "delta":2}]]], 0, 0, 0],
		["event reveal only", true, [["event", [{"op":"reveal"}]]], 4, 0, 0],
		["event visible edit", false, [["event", [{"op":"edit", "delta":2}]]], 6, 2, 0],
		["event edit buff reveal", true, [["event", [{"op":"edit", "delta":2}]], ["buff", [{"op":"reveal"}]]], 6, 2, 0],
		["buff edit event reveal", true, [["buff", [{"op":"edit", "delta":2}]], ["event", [{"op":"reveal"}]]], 6, 0, 2],
		["buff edit reveal", true, [["buff", [{"op":"edit", "delta":2}, {"op":"reveal"}]]], 6, 0, 2],
		["other buff edit event reveal", true, [["others", [{"op":"edit", "delta":2}]], ["event", [{"op":"reveal"}]]], 6, 0, 2]
	]
	for c in cases:
		var id:int = member(c[0])
		var other:int = member("bystander")
		var card:BaseAttack = attack(id, c[1])
		var power = GameDataManager.find_player_data(id).power
		var card_power = card._power
		for s in c[2]:
			stage(id, other if s[0] == "others" else id, "buff" if s[0] == "others" else s[0], [s[1]])
		check(GetPlayerTotalPower.new().exec(id) == c[3], c[0] + " actual total")
		verify_query(id, ["event"], c[4], c[3] - c[4], c[0] + " event")
		verify_query(id, ["buff"], c[5], c[3] - c[5], c[0] + " buff")
		verify_query(id, ["event", "buff", "rule"], c[4] + c[5], c[3] - c[4] - c[5], c[0] + " union")
		var or_labels:Array = ["buff", "others", "buff"] if c[0] == "other buff edit event reveal" else ["buff", "self", "buff"]
		verify_query(id, or_labels, c[5], c[3] - c[5], c[0] + " repeated OR labels")
		var own:int = 0 if c[0] == "other buff edit event reveal" else c[5]
		var other_value:int = c[5] if c[0] == "other buff edit event reveal" else 0
		verify_query(id, ["self"], own, c[3] - own, c[0] + " self")
		verify_query(id, ["others"], other_value, c[3] - other_value, c[0] + " others")
		check(is_same(power, GameDataManager.find_player_data(id).power) and is_same(card_power, card._power), c[0] + " numbers retain identity")
		var raw:Array = facts(id)
		var expected_count:int = 1 if c[0] in ["event edit only", "event reveal only", "event visible edit"] else 2
		check(raw.size() == expected_count, c[0] + " raw count intact")
		for fact in raw:
			if fact.data.field == "card_power":
				check(fact.data.delta == 2 and is_same(fact.object, card), c[0] + " raw edit +2 with real target")
			else:
				check(fact.data.delta == c[3], c[0] + " raw full flip delta intact")
		check(GetPlayerPowerBreakdown.new().exec(id) is BaseNumber, c[0] + " legacy BaseNumber schema intact")

func boundary_cases() -> void:
	var id:int = member("independent increments")
	var card:BaseAttack = attack(id)
	var one:Dictionary = stage(id, id, "buff", [[{"op":"edit", "delta":2}, {"op":"edit", "delta":3}]])
	verify_query(id, ["buff", "self", "buff"], 5, 4, "same real effect two increments")
	check(facts(id).size() == 2 and card._power.number == 9, "both increments kept raw")
	var two:Dictionary = stage(id, id, "buff", [[{"op":"edit", "delta":-2}]])
	check(not is_same(one.owner, two.owner) and one.owner._name == two.owner._name, "different same-name sources")
	verify_query(id, ["buff"], 3, 4, "same-name independent source negative increment")
	check(facts(id).size() == 3, "negative fact not dropped")
	var multi:Dictionary = stage(id, id, "buff", [[{"op":"edit", "delta":2}], [{"op":"edit", "delta":3}]])
	check(not is_same(multi.effects[0], multi.effects[1]) and is_same(multi.effects[0].from, multi.effects[1].from), "same source distinct effects")
	verify_query(id, ["buff"], 8, 4, "same source independent effects sum")
	var second:BaseAttack = attack(id)
	stage(id, id, "buff", [[{"op":"edit", "delta":2, "target":0}, {"op":"edit", "delta":3, "target":1}]])
	verify_query(id, ["buff"], 13, 8, "same source different actual targets")
	check(not is_same(card, second), "targets actual identity distinct")

	id = member("flip cycle")
	card = attack(id, true)
	stage(id, id, "event", [[{"op":"edit", "delta":2}, {"op":"reveal"}]])
	verify_query(id, ["event"], 2, 4, "cycle initially counted")
	stage(id, id, "buff", [[{"op":"hide"}]])
	verify_query(id, ["event", "buff"], 0, 0, "cycle hidden numeric inactive")
	stage(id, id, "buff", [[{"op":"reveal"}, {"op":"reveal"}]])
	verify_query(id, ["event", "buff"], 2, 4, "cycle revealed modifier counted once")
	var raw:Array = facts(id)
	check(raw.size() == 4 and raw[0].data.delta == 2 and raw[1].data.delta == 6 and raw[2].data.delta == -6 and raw[3].data.delta == 6, "raw +2 +6 -6 +6; repeated reveal no-op")

	id = member("reverse negative")
	card = attack(id, true)
	stage(id, id, "event", [[{"op":"reveal"}]])
	stage(id, id, "buff", [[{"op":"edit", "delta":-2}]])
	verify_query(id, ["event"], 0, 2, "reveal before edit event has no numeric modifier")
	verify_query(id, ["buff"], -2, 4, "signed negative no clamp")

	id = member("direct numeric")
	attack(id)
	stage(id, id, "buff", [[{"op":"direct", "delta":2}, {"op":"bonus", "delta":3}]])
	verify_query(id, ["buff"], 5, 4, "direct and bonus numeric writers")
	check(facts(id).size() == 2, "direct and bonus single raw fact each")

	id = member("skill exit")
	member("skill bystander")
	var skill:BaseSkill = BaseSkill.new("diagnostic skill", "", [], BaseNumber.new(0), BaseNumber.new(4))
	check(AddSkill.new().exec(skill, id, true), "real skill enters")
	stage(id, id, "event", [[{"op":"edit", "delta":2}]])
	verify_query(id, ["event"], 2, 4, "skill before close numeric active")
	stage(id, id, "buff", [[{"op":"close"}]])
	verify_query(id, ["event", "buff"], 0, 0, "skill exit no negative numeric modifier")
	raw = facts(id)
	check(raw.size() == 2 and raw[0].data.delta == 2 and raw[1].data.delta == -6, "skill close single actual -6 raw fact")
	check(not GameDataManager.find_player_data(id).played_cards.has(skill) and not skill._is_activating and not skill._is_concealed, "skill removed and stopped activating")
	check(GameDataManager.find_player_data(id).side.skills.has(skill), "skill really returned to skill zone")
	check(raw.size() == 2 and is_same(raw[1].object, skill) and raw[1].data.get("contribution_role") == "card_count_transition", "skill exit explicitly classified with original target")
	print("SKILL_FACTS ", raw)
	check(GameDataManager.find_player_data(id).power.number == 0, "skill close deducted once")

func unsupported_boundaries() -> void:
	var id:int = member("set boundary")
	attack(id)
	stage(id, id, "event", [[{"op":"edit", "delta":2}]])
	stage(id, id, "buff", [[{"op":"set", "delta":5}]])
	check(GetPlayerTotalPower.new().exec(id) == 5, "real set still executes")
	var r:Dictionary = query(id, ["event"])
	check(not r.get("ok", true) and not r.has("value") and r.get("reason") == "unsupported_power_source_role", "other source set prevents false linear current attribution")
	check(facts(id).size() == 2 and facts(id)[1].data.delta == -1, "set actual -1 raw delta kept")

	id = member("board capability")
	var event:BaseEvent = BaseEvent.new("board diagnostic event", "")
	var situation:BaseSituation = BaseSituation.new("board diagnostic situation", "")
	var e:BaseEffect = BaseEffect.new("board event query", [], 0, true, false)
	var s:BaseEffect = BaseEffect.new("board situation query", [], 0, true, false)
	e.from = event
	s.from = situation
	e._power_query = [descriptor("power_contribution", [null, 3, id])]
	s._power_query = [descriptor("power_contribution", [null, 2, id])]
	event._effects = [e]
	situation._effects = [s]
	MapData.areas[0]._events.append(event)
	MapData.active_situation = situation
	check(GetPlayerTotalPower.breakdown(id).board == 5, "real board evaluates event3 situation2")
	r = query(id, ["event"])
	check(not r.get("ok", true) and not r.has("value") and r.get("reason") == "board_source_breakdown_unavailable", "scalar board cannot certify event source")
	verify_query(id, ["board"], 5, 0, "explicit all-board label supported")
	s._power_query = [descriptor("power_contribution", [null, -3, id])]
	check(GetPlayerTotalPower.breakdown(id).board == 0, "real board distinct contributions cancel")
	r = query(id, ["event"])
	check(not r.get("ok", true) and not r.has("value"), "zero aggregate does not prove no board source")
	MapData.areas[0]._events.erase(event)
	MapData.active_situation = null

func compatibility_cases() -> void:
	var reader = GetPlayerPowerBreakdown.new()
	var supported:bool = reader.has_method("numeric_modifiers")
	check(supported, "checked numeric candidate available")
	var id:int = member("legacy history")
	# 旧日志 fixture：明确无 role；不假造已分类历史。不用于八对照或来源规则正例。
	GameLog.record("power_source", id, -1, "", null, ["event", "power"], {"field":"power", "delta":6, "source_name":"legacy"})
	var before:Array = facts(id)
	var old = reader.exec(id, ["event"])
	check(old is BaseNumber and old.number == 6, "legacy API preserves unclassified historical sum")
	var result:Dictionary = query(id, ["event"])
	check(not result.get("ok", true) and not result.has("value") and result.get("reason") == "unclassified_power_source", "unclassified old history unsupported; not guessed or zero")
	check(facts(id) == before, "checked query does not migrate or mutate old raw")
	# 外部调试写点不在生产授权范围；真实调用证明它仍未分类，不能冒认全仓收口。
	var debug_id:int = member("unwired debug writer")
	DebugPlayerAdapter.new().set_resource("power", debug_id, null, 2)
	result = query(debug_id, ["rule"])
	check(not result.get("ok", true) and not result.has("value"), "unwired debug writer explicitly unsupported")
	var unknown:int = 9515101
	var keys:Array = GameData.player_data_library.keys()
	PowerSources.record(unknown, "power", 4)
	EditPower.new().exec(null, BaseNumber.new(4), unknown)
	EditDataNumber.new().exec("total_power_bonus", null, BaseNumber.new(4), unknown)
	check(facts(unknown).is_empty() and GameDataManager.find_player_data(unknown).is_empty() and keys == GameData.player_data_library.keys(), "S14 member gates preserved")

func run() -> void:
	print("ENV ", JSON.stringify({"pid":OS.get_process_id(), "user":OS.get_user_data_dir(), "res":ProjectSettings.globalize_path("res://")}))
	var started:Dictionary = EffectManager.reset_runtime()
	check(started.get("ok", false), "explicit current session starts")
	session_context = started.get("context")
	eight_cases()
	boundary_cases()
	unsupported_boundaries()
	compatibility_cases()
	var output = FileAccess.open("res://contribution-output.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks, "failures":failures, "observations":observations, "raw":clean(GameLog.query({"type":"power_source"}, null)), "execution_calls":GameLog.all_func_calls()}, "\t"))
	output.close()
	print("RESULT ", JSON.stringify({"suite":"power-source-contribution", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
