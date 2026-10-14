extends Node

# 仅验证 BoardPowerQuery 的只读求值，不模拟正式事件入场/触发链。
const BOARD_SCRIPT = preload("res://scripts/system/global/board_power_query.gd")
var checks:int = 0
var failures:Array = []
var observations:Array = []
var tracked:Array = []
var id:int = -1

func _ready() -> void:
	call_deferred("run")

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok:
		failures.append(label)

func descriptor(name:String, args:Array) -> Dictionary:
	return {"func_name":name, "parameters":args}

func contribution(value:int) -> Dictionary:
	return descriptor("power_contribution", [null, value, id])

func source(kind:String, groups:Array):
	# 同名但身份不同；诊断数据只放本测试，不写正式数据。
	var owner = BaseEvent.new("same source", "") if kind == "event" else BaseSituation.new("same source", "")
	for group in groups:
		var eff:BaseEffect = BaseEffect.new("same effect", [], 0, true, false)
		eff.from = owner
		eff._power_query = group
		owner._effects.append(eff)
		tracked.append(eff)
	tracked.append(owner)
	if kind == "event":
		MapData.areas[0]._events.append(owner)
	else:
		MapData.active_situation = owner
	return owner

func clear_board() -> void:
	for area in MapData.areas:
		area._events.clear()
	MapData.active_situation = null
	tracked.clear()

func clean(value):
	if value is BaseNumber:
		return {"instance":value.get_instance_id(), "number":value.number, "can_change":value.can_change}
	if value is Object:
		return value.get_instance_id()
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

func snapshot() -> Dictionary:
	var effects:Array = []
	var cards:Array = []
	for item in tracked:
		if item is BaseEffect:
			effects.append([item, item.from, item._power_query, item._self_vars, item._using_numbers, item.numbers, item.runtime_context()])
		else:
			cards.append([item, item._is_concealed, item._effects])
			if item is BaseHandCard:
				cards.append([item._is_activating, item._power])
	var zones:Array = []
	for area in MapData.areas:
		zones.append(area._events)
	return clean({"players":GameData.player_data_library, "zones":zones,
		"situation":MapData.active_situation, "effects":effects, "cards":cards,
		"logs":GameLog.query({}, null), "calls":GameLog.all_func_calls()})

func breakdown(who:int, preview:Array = [], hidden:Array = []) -> Dictionary:
	# 同一 oracle 对照旧实现：只读取真实 scalar，绝不伪造来源明细。
	var script:Variant = BOARD_SCRIPT
	if script.has_method("breakdown"):
		return script.call("breakdown", who, preview, hidden)
	return {"total":BoardPowerQuery.total(who, preview, hidden), "entries":[]}

func verify(label:String, expected_total:int, expected:Array, preview:Array = [], hidden:Array = []) -> void:
	var before:Dictionary = snapshot()
	var result:Dictionary = breakdown(id, preview, hidden)
	var scalar:int = BoardPowerQuery.total(id, preview, hidden)
	var repeated:Dictionary = breakdown(id, preview, hidden)
	var entries:Array = result.get("entries", [])
	check(result.get("total") == expected_total, label + " total")
	check(scalar == expected_total, label + " legacy scalar")
	check(entries.size() == expected.size(), label + " exact entry count")
	var sum:int = 0
	for entry in entries:
		sum += int(entry.get("value", 0))
	check(sum == expected_total, label + " entry sum equals total")
	# 逐笔核对确定的真实遍历顺序：局势在前，事件在后；不按名称去重。
	for index in range(mini(entries.size(), expected.size())):
		var entry:Dictionary = entries[index]
		var want:Array = expected[index]
		check(entry.size() == 3 and is_same(entry.get("source"), want[0]) and is_same(entry.get("effect"), want[1]) and entry.get("value") == want[2], label + " source/effect/signed value " + str(index))
	check(clean(result) == clean(repeated), label + " repeat stable")
	check(snapshot() == before, label + " query leaves state/logs/identities unchanged")
	observations.append({"case":label, "expected_total":expected_total, "actual":clean(result), "scalar":scalar})

func board_cases() -> void:
	clear_board()
	var event = source("event", [[contribution(3)]])
	verify("event only", 3, [[event, event._effects[0], 3]])
	clear_board()
	var situation = source("situation", [[contribution(2)]])
	verify("situation only", 2, [[situation, situation._effects[0], 2]])
	clear_board()
	event = source("event", [[contribution(3)]])
	situation = source("situation", [[contribution(2)]])
	verify("event3 situation2", 5, [[situation, situation._effects[0], 2], [event, event._effects[0], 3]])
	situation._effects[0]._power_query = [contribution(-3)]
	verify("event3 situation-3 zero sum", 0, [[situation, situation._effects[0], -3], [event, event._effects[0], 3]])
	event._is_concealed = true
	verify("negative situation with concealed event", -3, [[situation, situation._effects[0], -3]])
	situation._is_concealed = true
	verify("all sources concealed", 0, [])
	clear_board()
	event = source("event", [[contribution(2), contribution(2), contribution(-4), contribution(0)], [contribution(3)]])
	var second = source("event", [[contribution(-1)]])
	verify("same source repeated increments distinct effects same-name sources", 2, [
		[event, event._effects[0], 2], [event, event._effects[0], 2],
		[event, event._effects[0], -4], [event, event._effects[0], 0],
		[event, event._effects[1], 3], [second, second._effects[0], -1]])
	clear_board()
	var foreach_body:Dictionary = descriptor("power_contribution", [null, 1, null])
	event = source("event", [[descriptor("foreach_func", [foreach_body, [id, id], 2])]])
	verify("foreach same effect repeated legal increments", 2, [[event, event._effects[0], 1], [event, event._effects[0], 1]])
	clear_board()
	event = source("event", [[descriptor("power_contribution", [null, 99, id + 1000]), {"func_name":"power_contribution", "parameters":[null, 88, id], "condition":false}]])
	verify("other player and false condition excluded", 0, [])

func card_cases() -> void:
	clear_board()
	var first:BaseAttack = BaseAttack.new("same attack", "", [], BaseNumber.new(0), BaseNumber.new(4))
	var second:BaseAttack = BaseAttack.new("same attack", "", [], BaseNumber.new(0), BaseNumber.new(4))
	check(AddAttack.new().exec(first, id) and AddAttack.new().exec(second, id), "real attacks enter through AddAttack")
	var event = source("event", [[descriptor("attack_power_contribution", [[], 2, id])]])
	tracked.append_array([first, second])
	verify("attack contribution one increment per counted target", 4, [[event, event._effects[0], 2], [event, event._effects[0], 2]])
	first._is_concealed = true
	verify("concealed attack excluded", 2, [[event, event._effects[0], 2]])
	var preview:BaseAttack = BaseAttack.new("preview attack", "", [], BaseNumber.new(0), BaseNumber.new(4))
	preview._is_concealed = true
	tracked.append(preview)
	verify("preview duplicate target counts once without entering zone", 4, [[event, event._effects[0], 2], [event, event._effects[0], 2]], [preview, preview], [false, false])
	verify("preview remains concealed when requested", 2, [[event, event._effects[0], 2]], [preview], [true])
	check(not GameData.player_data_library[id].played_cards.has(preview) and preview._is_concealed, "preview real zone and concealment unchanged")
	first._is_concealed = false
	clear_board()
	event = source("event", [[descriptor("card_power_contribution", [first, 2, null, id]), descriptor("card_power_contribution", [first, 3, null, id]), descriptor("card_power_contribution", [first, 0, 4, id])]])
	var situation = source("situation", [[descriptor("card_power_contribution", [first, 1, null, id])]])
	tracked.append_array([first, second])
	verify("card local running value shared across sources no double evaluation", 0, [[situation, situation._effects[0], 1], [event, event._effects[0], 2], [event, event._effects[0], 3], [event, event._effects[0], -6]])
	check(first._power.number == 4 and GameData.player_data_library[id].power.number == 8, "card and player power never written by query")
	first._power.can_change = false
	verify("immutable card contribution excluded", 0, [])

func run() -> void:
	print("ENV ", JSON.stringify({"pid":OS.get_process_id(), "user":OS.get_user_data_dir(), "res":ProjectSettings.globalize_path("res://")}))
	var started:Dictionary = EffectManager.reset_runtime()
	check(started.get("ok", false), "current session starts")
	id = AddPlayer.new().exec(-1, [], {"player_name":"board breakdown guard"}, started.context)
	var script:Variant = BOARD_SCRIPT
	check(script.has_method("breakdown"), "precise source API available")
	board_cases()
	card_cases()
	var before:Dictionary = snapshot()
	var unknown:Dictionary = breakdown(9515101)
	check(unknown.get("total") == 0 and unknown.get("entries", []).is_empty(), "unknown player zero empty")
	check(snapshot() == before, "unknown player query does not create member")
	var output = FileAccess.open("res://board-breakdown-output.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks, "failures":failures, "observations":observations}, "\t"))
	output.close()
	print("RESULT ", JSON.stringify({"suite":"board-power-source-breakdown", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
