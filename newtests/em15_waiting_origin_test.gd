extends Node
const Generation = preload("res://scripts/system/session_generation.gd")
var checks:int = 0
var failures:Array = []
var tails:int = 0
var callback_hits:int = 0
var callback_baseline:Dictionary = {}
var child:BaseEffect
var ask_marker:bool = false:
	set(value):
		ask_marker = value
		if value:
			var captured:Dictionary = EffectManager.execution_context()
			child = effect(captured.context, [{"select_cards":{"source":"hand_cards","min":0,"max":1},"funcs":[]}])
			EffectManager.request_choice(child)
			check(EffectManager.get("_pending_choices").has(child), "PRE request child in real function frame")
var reset_marker:bool = false:
	set(value):
		reset_marker = value
		if value:
			callback_hits += 1
			GameData.reset_game_session([0, 1])
			GameLog.reset()
			callback_baseline = GameData.player_data_library.duplicate()
func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)
func start(ids:Array = [0, 1]) -> SessionContext:
	var result:Dictionary = GameData.reset_game_session(ids)
	check(result.ok, "PRE reset session")
	GameLog.reset()
	for id in ids: GameData.player_data_library[id].location = MapData.magic_workshop0
	return result.context
func effect(context:SessionContext, options:Array = [], funcs:Array = [], id:int = 0, points:Array = []) -> BaseEffect:
	var desc:Dictionary = {"effect_name":"em15-probe","priority":0,"time_points":points,"is_pure_passive":false,"is_residue":false,"effect_numbers":[],"funcs":funcs}
	if not options.is_empty(): desc["options"] = options
	var loaded:Array = LoadHelper.load_effects([desc], null, context)
	check(loaded.size() == 1, "PRE factory")
	var result:BaseEffect = loaded[0]
	check(EffectManager.register_effect(result, id), "PRE register")
	return result
func wait(context:SessionContext, kind:String, id:int = 0) -> BaseEffect:
	var option:Dictionary = {"shown_option_name":"probe", "funcs":[]}
	if kind == "card":
		option["select_cards"] = {"source":"hand_cards", "min":0, "max":1}
	elif kind == "player":
		option["select_players"] = {"candidates":[{"func_name":"get_all_players_id","parameters":[]}],"min":1,"max":1}
	elif kind == "location":
		option["select_location"] = {}
	var result:BaseEffect = effect(context, [] if kind == "active" else [option], [], id)
	EffectManager.decision_queue.append(result)
	EffectManager.run_pipeline()
	check(EffectManager.get_pending_active_effect() == result, "PRE real active wait " + kind)
	if kind != "active": check(EffectManager.submit_option_choice(result, [0]), "PRE transition " + kind)
	return result
func reset_chain(kind:String) -> void:
	if kind == "progress": GameProgress.reset_progress()
	elif kind == "game": GameData.reset_game_session([0, 1])
	elif kind == "runtime": EffectManager.reset_runtime()
	elif kind == "release": GameData.release_game_objects()
	elif kind == "end_start":
		GameStart.end_session()
		if OS.get_cmdline_user_args().has("full-start"):
			preload("res://scripts/match/rule_random.gd").start_seed(15015)
			check(GameStart.game_start([0, 1]), "PRE complete GameStart end/start accepted")
		else:
			GameData.reset_game_session([0, 1])
	GameLog.reset()
func answer(result:BaseEffect, kind:String) -> bool:
	if kind == "active": return EffectManager.submit_active_choice(result, true)
	if kind == "card": return EffectManager.submit_card_selection(result, [])
	if kind == "player": return EffectManager.submit_player_selection(result, [1])
	return EffectManager.submit_location_selection(result, MapData.miyama0)
func pending(kind:String):
	if kind == "active": return EffectManager.get_pending_active_effect()
	if kind == "card": return EffectManager.get_pending_card_selection()
	if kind == "player": return EffectManager.get_pending_player_selection()
	return EffectManager.get_pending_location_selection()
func stale_waits() -> void:
	for chain in ["progress", "game", "runtime", "release", "end_start"]:
		for kind in ["active", "card", "player", "location"]:
			var context:SessionContext = start()
			var old:BaseEffect = wait(context, kind)
			var retained:Callable = Callable(EffectManager, "submit_active_choice").bind(old, true)
			reset_chain(chain)
			var keys:Array = GameData.player_data_library.keys()
			var facts:int = GameLog.query({}).size()
			var counts:Dictionary = old._option_use_counts.duplicate()
			check(not Generation.validate_context(context).ok, "PRE invalidated " + chain)
			var query = pending(kind)
			check(query == null if kind == "active" else query.is_empty(), "old query closed " + chain + "/" + kind)
			check(not answer(old, kind), "old submit refused " + chain + "/" + kind)
			check(not retained.call(), "saved submit refused " + chain + "/" + kind)
			check(GameData.player_data_library.keys() == keys and GameLog.query({}).size() == facts, "no new graph or facts " + chain + "/" + kind)
			check(old._option_use_counts == counts, "no usage after invalidation " + chain + "/" + kind)
			check(not old.has_meta(EffectManager.PAYMENT_RECEIPT_META), "no payment after invalidation " + chain + "/" + kind)
func tail() -> void:
	tails += 1
func defer(context:SessionContext) -> bool:
	# Public call preserves old ABI for the A1-14 baseline run only.
	if EffectManager.get_method_list().filter(func(m): return m.name == "defer_until_runtime_guard_complete")[0].args.size() == 1:
		return EffectManager.defer_until_runtime_guard_complete(Callable(self, "tail"))
	return EffectManager.call("defer_until_runtime_guard_complete", Callable(self, "tail"), context)
func transaction(context:SessionContext) -> Dictionary:
	var methods:Array = EffectManager.get_method_list().filter(func(m): return m.name == "capture_transaction_state")
	if methods[0].args.is_empty(): return EffectManager.capture_transaction_state()
	return EffectManager.call("capture_transaction_state", context)
func pause(context:SessionContext) -> BaseEffect:
	var root:BaseEffect = effect(context, [], [{"func_name":"foreach_func","parameters":[{"func_name":"get_player_data_value","parameters":["score",null]},[0,1,0],1]}])
	check(EffectManager.configure_runtime_guard({"enabled":true,"steps":1,"seconds":0.0}), "PRE budget")
	EffectManager.activate_effect(root)
	check(EffectManager.runtime_guard_status().paused, "PRE real loop guard paused")
	return root
func stale_guards() -> void:
	for chain in ["progress", "game", "runtime", "release", "end_start"]:
		var context:SessionContext = start()
		var root:BaseEffect = pause(context)
		check(defer(context), "PRE legal deferred tail")
		var snapshot:Dictionary = EffectManager.execution_runtime_snapshot()
		var saved_run:Dictionary = snapshot.suspended_run
		var saved_frames:Array = snapshot.suspended_functions.duplicate()
		var saved_transactions:Dictionary = transaction(context)
		check(not saved_frames.is_empty() and saved_frames[0].has("loop"), "PRE actual loop frame saved")
		var loop:Dictionary = saved_frames[0].loop.duplicate()
		reset_chain(chain)
		var baseline_state:Dictionary = EffectManager.capture_transaction_state()
		var keys:Array = GameData.player_data_library.keys()
		var facts:int = GameLog.query({}).size()
		# Reset-progress deliberately leaves guard in place. Other resets: retain old public graph
		# to exercise the documented restore consumer, not a private engine method.
		EffectManager.set("_guard_run", saved_run)
		EffectManager.set("_guard_frames", saved_frames)
		EffectManager.get("_runtime_guard").paused = true
		var before_tails:int = tails
		var count:int = EffectManager.capture_transaction_state().continuation_queue.size()
		check(not defer(context), "defer registration front " + chain)
		check(EffectManager.capture_transaction_state().continuation_queue.size() == count, "no old tail registration " + chain)
		check(not EffectManager.restore_transaction_state(saved_transactions), "restore front " + chain)
		check(EffectManager.capture_transaction_state().continuation_queue.size() == count, "no old graph restore " + chain)
		check(not EffectManager.resume_runtime_guard(), "guard resume refusal " + chain)
		check(saved_frames[0].loop == loop, "old loop remains unadvanced " + chain)
		check(tails == before_tails and GameLog.query({}).size() == facts and GameData.player_data_library.keys() == keys, "guard no tail or new facts " + chain)
		check(not Generation.validate_context(context).ok, "PRE old guard context remains invalid " + chain)
func positive() -> void:
	var context:SessionContext = start()
	var root:BaseEffect = pause(context)
	var before:int = tails
	check(defer(context), "legal explicit tail registers")
	var saved:Dictionary = transaction(context)
	check(EffectManager.restore_transaction_state(saved), "same-session transaction graph restore")
	var attempts:int = 0
	while EffectManager.runtime_guard_status().paused and attempts < 12:
		check(EffectManager.resume_runtime_guard(), "legal actual loop resume")
		attempts += 1
	check(not EffectManager.runtime_guard_status().paused, "legal loop completes")
	check(tails == before + 1, "tail exactly once")
	check(GameLog.query({"type":"effect"}).size() == 1, "root exactly once")
	check(not EffectManager.resume_runtime_guard() and tails == before + 1, "second resume no replay")
	context = start()
	var cards:BaseEffect = wait(context, "card")
	check(EffectManager.submit_card_selection(cards, []), "declared legal empty card choice")
	context = start()
	var players:BaseEffect = wait(context, "player")
	var calls:int = GameLog.all_func_calls().size()
	var objects:int = GameData.objects.size()
	var bindings:int = Generation._bindings.size()
	for i in range(3): check(EffectManager.get_pending_player_selection().candidates == [0,1], "pure declared candidates")
	check(GameLog.all_func_calls().size() == calls and GameData.objects.size() == objects and Generation._bindings.size() == bindings, "queries no logs objects or bindings")
	check(EffectManager.submit_player_selection(players, [1]), "declared target accepted")
	context = start()
	var locations:BaseEffect = wait(context, "location")
	check(EffectManager.submit_location_selection(locations, MapData.miyama0), "declared same-map location answer accepted")
	context = start([-7, 1])
	var negative:BaseEffect = wait(context, "card", -7)
	check(EffectManager.submit_card_selection(negative, []), "literal negative member not trigger sentinel")
func replacement_and_cancel() -> void:
	var context:SessionContext = start()
	var old:BaseEffect = wait(context, "card")
	var data:Dictionary = GameData.player_data_library[0]
	GameData.player_data_library[0] = data.duplicate()
	check(EffectManager.get_pending_card_selection().is_empty(), "member replacement query closed")
	check(not EffectManager.submit_card_selection(old, []), "member replacement submit closed")
	context = start()
	old = wait(context, "card")
	var original:Array = MapData.miyama._locations
	MapData.miyama._locations = original.duplicate()
	MapData.miyama._locations[0] = MapData.shinto0
	check(not EffectManager.submit_card_selection(old, []), "undeclared topology replacement closed")
	MapData.miyama._locations = original
	context = start()
	old = wait(context, "card")
	GameProgress.reset_progress()
	var magic = GameData.player_data_library[0].magic.number
	check(EffectManager.cancel_pending_choice(old), "exact stale wait cancellation")
	check(EffectManager.waiting_selection == null and GameData.player_data_library[0].magic.number == magic, "cancel no cost")
	context = start()
	var fresh:BaseEffect = wait(context, "card")
	check(not EffectManager.cancel_pending_choice(old) and EffectManager.waiting_selection == fresh, "old cancel preserves fresh same-ID wait")
	context = start()
	old = effect(context)
	old._trigger_player_id = -1
	EffectManager.request_choice(old)
	check(EffectManager.get("_pending_choices").is_empty(), "S03 trigger sentinel does not register")
	check(EffectManager.get_pending_active_effect() == null, "S03 sentinel no local wait")
func batches() -> void:
	for chain in ["same", "progress", "game", "runtime", "release", "end_start"]:
		var context:SessionContext = start()
		var root:BaseEffect = wait(context, "card")
		GameData.player_data_library[0].current_time_points = ["em15-old-marker"]
		var methods:Array = EffectManager.get_method_list().filter(func(m): return m.name == "queue_time_point_batch")
		if methods[0].args.size() < 4: EffectManager.queue_time_point_batch(root, 0)
		else: EffectManager.call("queue_time_point_batch", root, 0, context, root)
		var captured:Array = EffectManager.get("_queued_time_point_batches").duplicate()
		check(captured.size() == 1, "PRE batch captured " + chain)
		if chain == "same":
			check(EffectManager.cancel_pending_choice(root), "same-session choice cancellation before batch")
			check(EffectManager.get("_queued_time_point_batches").is_empty(), "same-session batch consumes exactly once")
		else:
			reset_chain(chain)
			EffectManager.cancel_pending_choice(root)
			# Retain the exact old batch for the graph-restore consumer to check before player writes.
			EffectManager.set("_queued_time_point_batches", captured)
			for id in GameData.player_data_library: GameData.player_data_library[id].current_time_points = ["em15-new-marker"]
			var serial:int = EffectManager.time_point_id
			var keys:Array = GameData.player_data_library.keys()
			EffectManager.run_pipeline()
			check(EffectManager.time_point_id == serial and GameData.player_data_library.keys() == keys, "old batch does not dispatch " + chain)
			var unchanged:bool = true
			for id in keys: unchanged = unchanged and GameData.player_data_library[id].current_time_points == ["em15-new-marker"]
			check(unchanged, "old batch does not restore new member time points " + chain)
func extra_source_cases() -> void:
	var context:SessionContext = start()
	var root:BaseEffect = pause(context)
	var empty:Dictionary = {"transaction_bindings":{},"batch_transactions":[],"continuation_queue":[],"continuation_transactions":{}}
	check(defer(context), "PRE pending graph for empty compatibility")
	check(EffectManager.restore_transaction_state(empty) and EffectManager.capture_transaction_state().continuation_queue.size() == 1, "empty legacy restore is no-op not new graph erasure")
	var invalid:Dictionary = empty.duplicate()
	invalid["context"] = "not-a-context"
	check(not EffectManager.restore_transaction_state(invalid), "malformed context refuses without runtime error")
	var snapshot:Dictionary = transaction(context)
	GameProgress.reset_progress()
	check(not EffectManager.restore_transaction_state(snapshot), "explicit old context never becomes empty compatibility")
	context = start()
	var old:BaseEffect = wait(context, "card")
	var container:Array = MapData.miyama._locations
	MapData.miyama._locations = container.duplicate()
	check(not EffectManager.submit_card_selection(old, []), "equal-valued location container replacement closed")
	MapData.miyama._locations = container
	context = start()
	old = wait(context, "card")
	var seats:Array = MapData.miyama0._players
	MapData.miyama0._players = seats.duplicate()
	check(EffectManager.get_pending_card_selection().is_empty(), "equal-valued seat container replacement closed")
	MapData.miyama0._players = seats
	context = start()
	old = wait(context, "card")
	old._selected_player = 1
	check(EffectManager.get_pending_card_selection().is_empty(), "external undeclared selected-target change closed")
	context = start()
	old = wait(context, "card")
	var library:Dictionary = GameData.player_data_library
	GameData.player_data_library = library.duplicate()
	check(EffectManager.get_pending_card_selection().is_empty(), "equal-valued member-library container replacement closed")
	GameData.player_data_library = library
func child_waits() -> void:
	for chain in ["same", "progress", "game", "runtime", "release", "end_start"]:
		var context:SessionContext = start()
		var root:BaseEffect = effect(context, [], [{"func_name":"set_property","parameters":[self,"ask_marker",true]},{"func_name":"edit_score","parameters":[null,BaseNumber.new(2),1]}])
		EffectManager.activate_effect(root)
		check(child != null and EffectManager.get_pending_active_effect() == child, "PRE true child wait " + chain)
		check(EffectManager.submit_option_choice(child, [0]), "PRE true child card transition " + chain)
		check(EffectManager.paused_runs_snapshot().has(child), "PRE true continuation saved " + chain)
		if chain == "same":
			check(EffectManager.submit_card_selection(child, []), "same-session child answer")
			check(GameData.player_data_library[1].score.number == 2, "same-session root resumes once")
			check(GameLog.query({"type":"effect"}).size() == 2, "child and root complete once each")
		else:
			reset_chain(chain)
			var facts:int = GameLog.query({}).size()
			var score = GameDataManager.find_player_data(1).get("score")
			var baseline = score.number if score != null else null
			check(not EffectManager.submit_card_selection(child, []), "old child answer rejected " + chain)
			check(GameLog.query({}).size() == facts and (score == null or score.number == baseline), "old continuation no completion or reward " + chain)
	var context:SessionContext = start()
	var saved:SessionContext = context
	start()
	var stale:BaseEffect = effect(Generation.derive_context(Generation.current_token().token, &"test-child").context)
	# Public request API must not refresh the caller's captured old context from the fresh effect.
	var methods:Array = EffectManager.get_method_list().filter(func(m): return m.name == "request_choice")
	if methods[0].args.size() == 1: EffectManager.request_choice(stale)
	else: EffectManager.call("request_choice", stale, saved)
	check(EffectManager.get("_pending_choices").is_empty(), "mixed old caller fresh child no registration")
	context = start()
	var root:BaseEffect = effect(context, [], [{"func_name":"set_property","parameters":[self,"ask_marker",true]},{"func_name":"edit_score","parameters":[null,BaseNumber.new(2),1]}])
	EffectManager.activate_effect(root)
	check(EffectManager.submit_option_choice(child, [0]), "PRE child for changed-root trigger")
	root._trigger_player_id = 1
	check(not EffectManager.submit_card_selection(child, []), "undeclared root-trigger replacement closed")
	check(GameData.player_data_library[1].score.number == 0, "changed-root continuation no reward")
func synchronous_submit() -> void:
	var context:SessionContext = start()
	var listener:BaseEffect = effect(context, [], [{"func_name":"set_property","parameters":[self,"reset_marker",true]}],0,["self_" + TimePoints.BEFORE_COMMAND_SPELL_SPEND])
	listener._is_pure_passive = true
	var old:BaseEffect = wait(context, "card")
	old._cost = {"type":"command_spell","amount":1}
	var before:int = callback_hits
	check(not EffectManager.submit_card_selection(old, []), "submit synchronous reset refuses old completion")
	check(callback_hits == before + 1, "PRE accepted submit reaches real BEFORE callback")
	check(old._option_use_counts.is_empty(), "callback return stops usage")
	check(GameLog.query({"type":"effect"}).is_empty() and GameLog.query({"type":"option_used"}).is_empty(), "callback return no old completion facts")
	check(is_same(GameData.player_data_library[0], callback_baseline[0]) and GameData.player_data_library[0].command_spell_count.number == 3, "new callback baseline unaffected")
func _ready() -> void:
	print("ENV user=", OS.get_user_data_dir(), " appdata=", OS.get_environment("APPDATA"))
	stale_waits()
	stale_guards()
	positive()
	replacement_and_cancel()
	batches()
	extra_source_cases()
	child_waits()
	synchronous_submit()
	print("RESULT ", JSON.stringify({"suite":"em15_waiting_origin","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
