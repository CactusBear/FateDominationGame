extends Node

const RR = preload("res://scripts/match/rule_random.gd")
const PoolSelection = preload("res://scripts/selection/class_pool_selection.gd")
var checks:int = 0
var failures:Array = []
var context:SessionContext
var shuffle_result:Variant
var event_hits:int = 0
var execute_shuffle:bool = false:
	set(value):
		execute_shuffle = value
		if value:
			shuffle_result = ReshuffleDiscard.new().exec(0)
var reshuffled:bool = false:
	set(value):
		reshuffled = value
		if value:
			event_hits += 1

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func fresh() -> void:
	var result:Dictionary = GameData.reset_game_session([0,1])
	check(result.ok, "PRE real session reset")
	context = result.context
	GameLog.reset()
	RR.stop_tracking()

func effect(name:String, funcs:Array, points:Array = []) -> BaseEffect:
	var effects:Array = LoadHelper.load_effects([{"effect_name":name,"time_points":points,"priority":0,"is_pure_passive":true,"is_residue":false,"effect_numbers":[],"funcs":funcs}], null, context)
	check(effects.size() == 1, "PRE trusted effect factory " + name)
	if effects.is_empty(): return null
	check(EffectManager.register_effect(effects[0], 0), "PRE register real effect " + name)
	return effects[0]

func selection() -> void:
	var masters:Array = GameStart.get_masters_can_use()
	var servants:Array = GameStart.get_servants_can_use()
	var file := FileAccess.open(LoadHelper.get_data_dir().path_join("selection_modes.json"), FileAccess.READ)
	var config:Dictionary = JSON.parse_string(file.get_as_text()).modes[0].duplicate(true)
	check(masters.size() >= 2, "PRE actual master templates")
	for randomize_order in [false,true]:
		config.randomize_initial_order = randomize_order
		var session = PoolSelection.new()
		check(session.setup([0,1],masters,servants,config), "PRE legal selection setup " + str(randomize_order))
		RR.stop_tracking()
		var before_rng:Dictionary = RR.snapshot()
		var before_objects:int = GameData.objects.size()
		check(not session.choose_master(0,masters[0]), "unknown first master explicitly refuses " + str(randomize_order))
		check(session.assignments.is_empty() and session.initial_order.is_empty(), "unknown first master has no publication " + str(randomize_order))
		check(RR.snapshot() == before_rng and GameData.objects.size() == before_objects, "unknown first master no consumption or registration " + str(randomize_order))
		# Recreate after the negative call so the baseline cannot contaminate the second oracle.
		session = PoolSelection.new()
		check(session.setup([0,1],masters,servants,config), "PRE recreate legal selection " + str(randomize_order))
		RR.start_seed(7193)
		check(session.choose_master(0,masters[0]), "known first master accepted " + str(randomize_order))
		var saved:Dictionary = session.assignments.duplicate(true)
		var saved_order:Array = session.initial_order.duplicate()
		RR.stop_tracking()
		before_rng = RR.snapshot()
		check(not session.choose_master(1,masters[1]), "unknown final draw explicitly refuses " + str(randomize_order))
		check(session.assignments == saved and session.initial_order == saved_order and not session.is_complete(), "unknown final draw preserves original assignments and order " + str(randomize_order))
		check(RR.snapshot() == before_rng, "unknown final draw consumes no random values " + str(randomize_order))
		# Same legal setup and declared seed reproduce the real draw and initial-order path.
		var outcomes:Array = []
		for run_index in 2:
			session = PoolSelection.new()
			check(session.setup([0,1],masters,servants,config), "PRE deterministic setup " + str(randomize_order) + "/" + str(run_index))
			RR.start_seed(7193)
			before_rng = RR.snapshot()
			check(session.choose_master(0,masters[0]) and session.choose_master(1,masters[1]) and session.is_complete(), "known draw and order finish " + str(randomize_order) + "/" + str(run_index))
			check(RR.snapshot() != before_rng, "known selection really consumes declared stream " + str(randomize_order) + "/" + str(run_index))
			check(servants.has(session.assignments[0].servant) and servants.has(session.assignments[1].servant) and session.assignments[0].servant != session.assignments[1].servant, "known draw uses unique actual templates " + str(randomize_order) + "/" + str(run_index))
			outcomes.append([session.get_assignments(),session.get_initial_order(),RR.snapshot()])
		check(outcomes[0] == outcomes[1], "known selection repeatability including order " + str(randomize_order))

func reshuffle() -> void:
	fresh()
	var d:Dictionary = GameDataManager.find_player_data(0)
	var deck:Array = d.deck
	var discard:Array = d.discard
	discard.append_array([0,1,2,3,4,5,6,7])
	var root:BaseEffect = effect("selection-rng-reshuffle-call",[{"func_name":"set_property","parameters":[self,"execute_shuffle",true]}])
	effect("selection-rng-reshuffle-listener",[{"func_name":"set_property","parameters":[self,"reshuffled",true]}],["self_" + TimePoints.DECK_RESHUFFLED])
	var original:Array = discard.duplicate()
	var saved_rng:Dictionary = RR.snapshot()
	var messages:Array = EffectManager.messages.duplicate(true)
	var before_facts:Array = GameLog.query({"type":"reshuffle_discard"})
	var points:Array = d.dynamic_time_points.duplicate()
	var result = ReshuffleDiscard.new().exec(0,context)
	check(result is Dictionary and result.get("ok") == false and result.get("reason") == &"unknown_random_stream" and is_same(result.get("context"),context), "unknown discard explicit rejection preserves original context")
	check(deck.is_empty() and discard == original and is_same(deck,d.deck) and is_same(discard,d.discard), "unknown discard no movement or container replacement")
	check(GameLog.query({"type":"reshuffle_discard"}) == before_facts and EffectManager.messages == messages and event_hits == 0 and d.dynamic_time_points == points, "unknown discard no fact message or event")
	check(RR.snapshot() == saved_rng, "unknown discard no random consumption")
	# The inherited, verified function frame must propagate the same refusal.
	EffectManager.activate_effect(root)
	check(shuffle_result is Dictionary and shuffle_result.get("ok") == false and shuffle_result.get("reason") == &"unknown_random_stream", "unknown real frame propagates discard rejection")
	check(deck.is_empty() and discard == original and event_hits == 0, "unknown real frame discard no movement or event")
	# Put back fixture content before the positive case even on the old implementation.
	deck.clear()
	discard.assign(original)
	event_hits = 0
	GameLog.reset()
	RR.start_seed(1793)
	var expected:Array = original.duplicate()
	check(ShuffleArray.new().exec(expected) != null and expected != original, "PRE known shuffle truly permutes")
	RR.start_seed(1793)
	EffectManager.activate_effect(root)
	check(shuffle_result is bool and shuffle_result, "known discard returns original success ABI")
	check(deck == expected and discard.is_empty() and is_same(deck,d.deck) and is_same(discard,d.discard), "known discard moves actual shuffled cards into original deck")
	check(event_hits == 1 and GameLog.query({"type":"reshuffle_discard"}).size() == 1, "known discard emits exactly one event and fact")
	var old:SessionContext = context
	fresh()
	d = GameDataManager.find_player_data(0)
	d.discard.append_array(original)
	RR.start_seed(1793)
	saved_rng = RR.snapshot()
	result = ReshuffleDiscard.new().exec(0,old)
	check(result is Dictionary and result.get("ok") == false and d.deck.is_empty() and d.discard == original and RR.snapshot() == saved_rng, "stale discard source still refuses before random consumption")

func debug_shuffle() -> void:
	fresh()
	var adapter := DebugCardAdapter.new()
	var d:Dictionary = GameDataManager.find_player_data(0)
	for items in [[],[7],[0,1,2,3,4,5,6,7]]:
		d.deck.assign(items)
		var deck:Array = d.deck
		RR.stop_tracking()
		var saved:Dictionary = RR.snapshot()
		var facts:Array = GameLog.query({})
		var messages:Array = EffectManager.messages.duplicate(true)
		var result:Dictionary = adapter.shuffle(0,"deck")
		check(not result.ok and not result.changed and result.get("error") == "unknown_random_stream", "unknown debug explicit refusal size " + str(items.size()))
		check(deck == items and is_same(deck,d.deck) and RR.snapshot() == saved, "unknown debug preserves input and stream size " + str(items.size()))
		check(GameLog.query({}) == facts and EffectManager.messages == messages, "unknown debug emits no fact or message size " + str(items.size()))
		RR.start_seed(1793)
		var expected:Array = items.duplicate()
		ShuffleArray.new().exec(expected)
		RR.start_seed(1793)
		result = adapter.shuffle(0,"deck")
		check(result.ok and result.changed == (items.size() > 1) and result.value == items.size() and deck == expected and is_same(deck,d.deck), "known debug preserves success ABI and declared permutation size " + str(items.size()))

func boundary() -> void:
	RR.stop_tracking()
	var screen = load("res://assets/scenes/main_menu/selection_screen.tscn").instantiate()
	add_child(screen)
	check(not RR.is_known(), "PRE real selection ready does not declare a stream")
	var started = screen.call("begin_selection")
	check(RR.is_known() and screen.session != null, "real legal selection setup explicitly declares local stream")
	check(screen.session != null and screen.session.assignments.is_empty(), "real declaration precedes any choose_master")
	check(started is bool and started, "real selection begin success propagates")
	RR.start_seed(919)
	var saved:Dictionary = RR.snapshot()
	started = screen.call("begin_selection")
	check(RR.snapshot() == saved, "real boundary preserves already declared seed and state")
	RR.set_capability_mode("none")
	started = screen.call("begin_selection")
	check(started is bool and not started and screen.session == null, "real explicit none rejection propagates without selectable session")
	check(RR.capability().mode == "none" and not RR.is_known(), "real boundary never upgrades none")
	RR.stop_tracking()
	screen.modes[screen.mode_picker.selected].per_class_count = 999999
	started = screen.call("begin_selection")
	check(not RR.is_known() and screen.session == null, "invalid selection setup declares no stream")
	screen.queue_free()

func formal() -> void:
	RR.stop_tracking()
	var board:Node = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	add_child(board)
	await get_tree().process_frame
	check(RR.is_known(), "formal unseeded entry still declares real local stream")
	check(SessionGeneration.current_token().ok and GameProgress.current_round == 1, "formal opening still reaches actual first round")
	for id in [0,1,2,3,4,5,6]:
		var d:Dictionary = GameDataManager.find_player_data(id)
		check(d.get("servant") is BaseServant and not d.get("deck",[]).is_empty(), "formal servant deck actually published " + str(id))

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var args:PackedStringArray = OS.get_cmdline_user_args()
	var mode:String = args[0] if not args.is_empty() else "selection"
	print("ENV user_dir=",OS.get_user_data_dir()," pid=",OS.get_process_id())
	match mode:
		"selection": selection()
		"reshuffle": reshuffle()
		"debug": debug_shuffle()
		"boundary": boundary()
		"formal": await formal()
		_: check(false, "unknown guard mode")
	GameStart.end_session()
	GameData.release_game_objects()
	RR.stop_tracking()
	print("RESULT ",JSON.stringify({"suite":"selection_rng","mode":mode,"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
