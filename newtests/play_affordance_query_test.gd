extends Node

var checks := 0
var failures: Array[String] = []
var attack: BaseAttack
var player: Dictionary
var context: SessionContext
var frame_accepted := false
var frame_hits := 0
var frame_trigger := "":
	set(value):
		frame_trigger = value
		exercise_frame(value)

# 已登记的 set_property 在 BaseFunc 帧内触发；观察者不是新解释器入口。
func exercise_frame(mode: String) -> void:
	frame_hits += 1
	var execution: Dictionary = EffectManager.execution_context()
	check(bool(execution.get("ok", false)), "PRE real verified BaseFunc frame " + mode)
	check(execution.get("context") is SessionContext and is_same(execution.context.token(), context.token()), "PRE frame retains original session " + mode)
	check(EffectManager.activating_eff != null, "PRE lifecycle sets activating effect " + mode)
	var query = preload("res://scripts/system/play_affordance_query.gd").new()
	if mode == "phase":
		var before := snapshot()
		result_is(query.check(attack, 0, true), true, "", "effect driven phase bypass")
		check(snapshot() == before, "real frame qualification query has no side effects")
	elif mode == "play":
		var before := snapshot()
		check(bool(query.check(attack, 0, true).ok), "real frame same query accepts executable case")
		check(snapshot() == before, "real frame executable query has no side effects")
		frame_accepted = PlayAttack.new().exec(attack, 0, null, null, true)

func invoke_frame(mode: String) -> void:
	var loaded: Array = LoadHelper.load_effects([{
		"effect_name":"driver", "time_points":[], "priority":0,
		"is_pure_passive":false, "is_residue":true, "need_activate":false,
		"effect_numbers":[],
		"funcs":[{"func_name":"set_property", "parameters":[self, "frame_trigger", mode]}]
	}], null, context)
	check(loaded.size() == 1, "PRE trusted runtime effect factory " + mode)
	if loaded.is_empty():
		return
	var root: BaseEffect = loaded[0]
	check(EffectManager.register_effect(root, 0), "PRE real effect registration " + mode)
	var hits_before := frame_hits
	EffectManager.activate_effect(root)
	check(frame_hits == hits_before + 1, "PRE actual registered function invoked once " + mode)
	check(not EffectManager.execution_context().get("ok", false) and EffectManager.activating_eff == null, "real frame unwinds " + mode)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func setup_player() -> void:
	GameData.release_game_objects()
	var started: Dictionary = GameData.reset_game_session([0])
	check(bool(started.get("ok", false)), "PRE real session lifecycle")
	context = started.get("context")
	GameLog.reset()
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	player = GameData.player_data_library[0]
	player["is_out"] = false
	player["magic"] = BaseNumber.new(10)
	player["play_limit"] = BaseNumber.new(2)
	player["buffs"] = []
	player["phase_as"] = {}
	var cards: Array = LoadGame.load_attacks([{
		"attack_name":"query attack", "attack_card_img":"", "attributes":[],
		"cost":{"number":2, "can_change":true, "is_pure_number":true},
		"power":{"number":3, "can_change":true, "is_pure_number":true}, "effects":[]
	}], "", null, [], context)
	check(cards.size() == 1, "PRE trusted runtime attack factory")
	if cards.is_empty():
		return
	attack = cards[0]
	# 公开加载器拼接图片目录；保留原夹具的无图片输入，不影响来源。
	attack._card_img = ""
	check(attack._name == "query attack" and attack._cost.number == 2 and attack._power.number == 3 and attack._cost.can_change and attack._power.can_change and attack._cost.is_pure_number and attack._power.is_pure_number, "PRE factory preserves original card inputs")
	var origin: Dictionary = SessionGeneration.origin_of(attack)
	check(bool(origin.get("ok", false)) and is_same(origin.context.token(), context.token()) and GameData.objects.has(attack), "PRE factory publishes attack with original source")
	attack._is_activating = false
	attack._need_extra_play = false
	attack._play_requirements = []
	attack._attributes = []
	player["hand_cards"] = [attack]
	player["played_cards"] = []
	MapData.active_situation = null
	for area in MapData.areas:
		area._events.clear()
		area._buffs.clear()

func result_is(result: Dictionary, ok: bool, reason: String, label: String) -> void:
	check(bool(result.get("ok", false)) == ok, label + " ok")
	check(str(result.get("reason", "")) == reason, label + " reason")

func snapshot() -> String:
	return JSON.stringify({
		"magic": player["magic"].number,
		"played": (player["played_cards"] as Array).size(),
		"hand": (player["hand_cards"] as Array).size(),
		"activating": attack._is_activating,
		"phase": GameProgress.current_phase_index,
		"actor": GameProgress.current_player_id,
		"log": GameLog.query({}, null).size(),
		"effect": EffectManager.activating_eff != null
	})

func run() -> void:
	setup_player()
	var before := snapshot()
	var query_script = load("res://scripts/system/play_affordance_query.gd")
	check(query_script != null, "query script exists")
	if query_script == null:
		print("STATE_BEFORE ", before)
		print("STATE_AFTER ", snapshot())
		print("RESULT play_affordance_query checks=", checks, " failures=", JSON.stringify(failures))
		get_tree().quit(1)
		return

	var query = query_script.new()
	result_is(query.check(attack, 0), false, "entry_requires_effect", "normal single entry")
	check(snapshot() == before, "query has no side effects")
	result_is(query.check(null, 0), false, "attack_missing", "null card")
	result_is(query.check(attack, 99, true), false, "player_missing", "unknown player")
	player["is_out"] = true
	result_is(query.check(attack, 0, true), false, "player_out", "out player")
	player["is_out"] = false

	var ban := BaseBuff.new("cannot play", "")
	ban._is_active = true
	ban._effects = [BaseEffect.new(CannotPlayCardsEffect.EFFECT_NAME, [], 0, false, true)]
	player["buffs"] = [ban]
	result_is(query.check(attack, 0, true), false, "cards_forbidden", "cannot play buff")
	player["buffs"] = []

	GameProgress.current_phase_index = 3
	result_is(query.check(attack, 0, true), false, "wrong_phase", "wrong phase without effect")
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 1
	result_is(query.check(attack, 0, true), false, "not_current_player", "wrong actor")
	GameProgress.current_player_id = 0
	attack._is_activating = true
	result_is(query.check(attack, 0, true), false, "card_activating", "already activating")
	attack._is_activating = false

	attack._need_extra_play = true
	result_is(query.check(attack, 0, true), false, "card_rule", "card rule rejection")
	attack._need_extra_play = false
	attack._play_requirements = [{"type":"min_magic", "value":11}]
	result_is(query.check(attack, 0, true), false, "card_rule", "card requirement rejection")
	attack._play_requirements = []

	for i in range(2):
		GameLog.record("play", 0, -1, "", attack, [], {"extra": false, "card_type": "attack"})
	result_is(query.check(attack, 0, false), false, "entry_requires_effect", "play limit entry short circuit")
	result_is(query.check(attack, 0, true), true, "", "ignore limit")
	GameLog.reset()

	GameProgress.current_phase_index = 3
	invoke_frame("phase")
	result_is(query.check(attack, 0, true), false, "wrong_phase", "ignore limit does not bypass phase")
	GameProgress.current_phase_index = 2

	# 同一个查询结果决定 PlayAttack 的可执行性；合法时再允许真实入口产生副作用。
	var legal: Dictionary = query.check(attack, 0, true)
	check(bool(legal.ok), "same query accepts executable case")
	var magic_before: float = player["magic"].number
	var played_before: int = (player["played_cards"] as Array).size()
	var rejected_without_driver := PlayAttack.new().exec(attack, 0, null, null, false)
	check(not rejected_without_driver, "PlayAttack follows query rejection")
	check(player["magic"].number == magic_before and (player["played_cards"] as Array).size() == played_before, "rejected PlayAttack has no side effects")
	# 可赋值的效果字段不是执行票；即使卡已由真实工厂创建也不能付款。
	EffectManager.activating_eff = BaseEffect.new("driver", [], 0, false, true)
	check(not EffectManager.execution_context().get("ok", false), "manual activating effect is not a verified frame")
	var manual_before := snapshot()
	check(bool(query.check(attack, 0, true).ok), "manual field can satisfy qualification but not payment source")
	check(not PlayAttack.new().exec(attack, 0, null, null, true), "manual activating effect never grants payment source")
	check(snapshot() == manual_before, "manual activating effect rejection has no side effects")
	EffectManager.activating_eff = null
	var original_magic: BaseNumber = player["magic"]
	invoke_frame("play")
	var accepted := frame_accepted
	check(accepted, "PlayAttack follows same query acceptance")
	check((player["played_cards"] as Array).has(attack), "accepted PlayAttack enters played cards")
	check(is_same(player["magic"], original_magic) and original_magic.number == magic_before - 2, "real frame pays exact cost through original magic identity")
	check(not (player["hand_cards"] as Array).has(attack) and attack._is_activating and (player["played_cards"] as Array).size() == played_before + 1, "real frame performs exactly one coherent entry")

	print("STATE_BEFORE ", before)
	print("STATE_AFTER_QUERY_ONLY ", before)
	print("STATE_AFTER ", snapshot())
	print("RESULT play_affordance_query checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
