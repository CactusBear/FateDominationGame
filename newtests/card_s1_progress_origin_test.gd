extends Node

const RR = preload("res://scripts/match/rule_random.gd")
var checks:int = 0
var failures:Array = []
var context:SessionContext

func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)

func fresh() -> void:
	var prepared:Dictionary = GameData.reset_game_session([0,1])
	check(prepared.ok, "PRE real public session")
	context = prepared.context
	RR.start_seed(817)
	GameLog.reset()
	MapData.reset_board()
	for id in [0,1]: GameData.player_data_library[id].is_out = false

func declaration(name:String, funcs:Array, points:Array = []) -> Dictionary:
	return {"effect_name":name,"time_points":points,"priority":0,"is_pure_passive":true,"is_residue":false,"effect_numbers":[],"funcs":funcs}

func event_template(effects:Array = []) -> BaseEvent:
	return LoadEvent.build_event({"card_name":"S1 event","card_img":"","score":{"number":1,"can_change":true,"is_pure_number":true},"effects":effects}, "")

func situation_template() -> BaseSituation:
	return LoadSituation.build_situation({"card_name":"S1 situation","card_img":"","magic":{"number":2,"can_change":true,"is_pure_number":true},"effects":[]}, "")

func decks(effects:Array = []) -> void:
	LoadEvent.events = [event_template(effects)]
	LoadSituation.situations = [situation_template()]
	LoadSituation.climax_situations = {}
	check(MapData.reset_event_deck(context).ok, "PRE real MapData event factory")
	check(MapData.reset_situation_deck(context).ok, "PRE real MapData situation factory")

func plan() -> Array:
	return [{"area_name":MapData.miyama._area_name,"concealed":true},{"area_name":MapData.shinto._area_name,"concealed":true}]

func factory_and_placement() -> void:
	fresh()
	decks()
	check(not SessionGeneration.origin_of(LoadEvent.events[0]).ok, "template remains unbound")
	check(SetCardConcealed.source_is_current(MapData.event_deck[0],context), "deck event is runtime original source")
	var placed:Dictionary = EventResolver.new().place(plan(),context)
	placed = await GameProgress.wait_progress_state(placed,context)
	check(placed.ok and placed.completed and placed.placed.size() == 2, "two actual event placements complete")
	check(MapData.miyama._events.size() == 1 and MapData.shinto._events.size() == 1, "actual board receives runtime events")
	check(not is_same(MapData.miyama._events[0],MapData.event_deck[0]) and SetCardConcealed.source_is_current(MapData.miyama._events[0],context), "event runtime clone inherits source")
	var reveal:Dictionary = EventResolver.new().start_reveal(plan(),context)
	reveal = await GameProgress.wait_progress_state(reveal,context)
	check(reveal.ok and reveal.completed and reveal.count == 2, "real planned reveal count")
	check(EventResolver.new().clear_all(context).ok and MapData.event_discard.size() == 2, "event cleanup original source")
	GameProgress.current_round = 1
	var activated:Dictionary = SituationResolver.new().activate(context)
	activated = await GameProgress.wait_progress_state(activated,context)
	check(activated.ok and activated.completed and MapData.active_situation != null, "actual situation activation complete")
	check(GameData.player_data_library[0].magic.number == 6 and GameData.player_data_library[1].magic.number == 6, "real situation magic through verified frames")
	check(SituationResolver.new().clear_all(context).ok and MapData.situation_discard.size() == 1, "situation cleanup original source")

func rejection_cases() -> void:
	fresh()
	decks()
	var old:SessionContext = context
	var state:Dictionary = {"ok":true,"completed":false,"context":old,"areas":MapData.areas,"deck":MapData.event_deck,"plan":plan(),"index":0,"placed":[]}
	var old_deck:Array = MapData.event_deck
	check(GameProgress.reset_progress().ok, "PRE rotate only progress, preserve maps and arrays")
	check(is_same(old_deck,MapData.event_deck), "PRE exact deck identity preserved")
	await Callable(EventResolver,"_resume_place").call(state)
	check(not state.ok and state.reason == &"stale_session" and state.index == 0, "saved old event cursor explicit refusal before progress")
	check(MapData.miyama._events.is_empty(), "old event cursor no new board write")
	var empty_old:Dictionary = EventResolver.new().place([],old)
	check(not empty_old.ok and empty_old.reason == &"stale_session", "old empty-plan cursor is explicit rejection not completion")
	var refused:Dictionary = EventResolver.new().place(plan())
	check(not refused.ok and refused.placed.is_empty(), "missing event source explicit rejection not zero success")
	refused = SituationResolver.new().activate(old)
	check(not refused.ok and MapData.active_situation == null, "old situation source explicit rejection")
	refused = MapData.reset_event_deck(old)
	check(not refused.ok and is_same(old_deck,MapData.event_deck), "stale factory cannot replace deck")
	fresh()
	decks()
	MapData.event_deck = [event_template()]
	refused = EventResolver.new().place(plan(),context)
	refused = await GameProgress.wait_progress_state(refused,context)
	check(not refused.ok and refused.placed.is_empty() and MapData.miyama._events.is_empty(), "unbound runtime event refused not rebound by consumer")

func guard_case(stale:bool) -> void:
	fresh()
	decks()
	check(EffectManager.configure_runtime_guard({"enabled":true,"steps":1,"seconds":0.0}), "PRE actual guard budget")
	var placed:Dictionary = EventResolver.new().place(plan(),context)
	check(EffectManager.runtime_guard_status().paused and not placed.completed, "real event root paused and outer cursor retained")
	if stale:
		check(GameProgress.reset_progress().ok, "PRE rotate with saved guard")
		await get_tree().process_frame
		check(not placed.ok and placed.reason == &"stale_session", "saved guarded outer cursor refuses old source")
	else:
		var slices:int = 0
		while EffectManager.runtime_guard_status().paused and slices < 32:
			check(EffectManager.resume_runtime_guard(), "PRE actual guard resume")
			slices += 1
			await get_tree().process_frame
		placed = await GameProgress.wait_progress_state(placed,context)
		check(placed.ok and placed.placed.size() == 2, "guard resume places each planned event once")
		check(MapData.miyama._events.size() == 1 and MapData.shinto._events.size() == 1, "guard resume no repeated placement")

func role_deal_and_refill() -> void:
	fresh()
	var source:BaseServant = GameData.loaded_servants[0]
	var copied:Dictionary = MasterManager.prepare_role_runtime(source, context)
	check(copied.ok, "PRE real S0 role runtime factory")
	GameData.player_data_library[0].servant = copied.object
	check(GameProgress.deal_player_cards(0,context).ok, "real role card dealing inherits runtime source")
	var data:Dictionary = GameData.player_data_library[0]
	check(not data.deck.is_empty() and SetCardConcealed.source_is_current(data.deck[0],context), "dealt actual servant deck bound")
	var original:BaseCard = data.deck[0]
	var result:Dictionary = await GameProgress.wait_progress_operation(GameProgress.start_progress_operation("refill_hand",[0,3],context))
	check(result.ok and result.value == 3 and data.hand_cards.size() == 3, "progress refill uses proper root and real three draws")
	check(data.hand_cards.has(original) and GameLog.query({"type":"draw"}).size() == 3, "refill preserves actual identities and facts once")
	var old:SessionContext = context
	check(GameProgress.reset_progress().ok, "PRE preserve runtime cards across progress rotation")
	var refused:Dictionary = GameProgress.clone_cards([original],old)
	check(not refused.ok, "runtime card copy rejects old action context")
	var newer:SessionContext = SessionGeneration.derive_context(SessionGeneration.current_token().token,&"s1 new action").context
	refused = GameProgress.clone_cards([original],newer)
	check(not refused.ok, "new context cannot resign old runtime card")

func ordinary_choice(stale:bool) -> void:
	fresh()
	var choices:Array = [{"shown_option_name":"continue", "funcs":[{"func_name":"do_nothing","parameters":[]}]}]
	decks([declaration("S1 reveal choice",[{"func_name":"ask_player_option","parameters":[choices,"S1 choice",0,1]}],[TimePoints.SELF_CARD_REVEALED])])
	var placements:Array = plan()
	for item in placements: item.concealed = false
	var placed:Dictionary = EventResolver.new().place(placements,context)
	check(EffectManager.waiting_effect != null and not placed.completed and MapData.shinto._events.is_empty(), "ordinary real choice retains outer event tail before next area")
	if stale:
		check(GameProgress.reset_progress().ok, "PRE rotate during ordinary choice")
		await get_tree().process_frame
		check(not placed.ok and placed.reason == &"stale_session" and MapData.shinto._events.is_empty(), "ordinary choice old tail cannot enter next area")
	else:
		var answered:int = 0
		for _i in 12:
			if EffectManager.waiting_effect != null:
				check(EffectManager.submit_option_choice(EffectManager.waiting_effect,0), "PRE actual option answer accepted")
				answered += 1
			await get_tree().process_frame
			if placed.completed: break
		check(placed.ok and placed.completed and answered == 2 and placed.placed.size() == 2, "ordinary choice resumes both planned areas without root redispatch")
		check(MapData.miyama._events.size() == 1 and MapData.shinto._events.size() == 1, "ordinary choice no duplicate placement")

func round_choice_tail(stale:bool) -> void:
	fresh()
	decks()
	var choices:Array = [{"shown_option_name":"round continue","funcs":[{"func_name":"do_nothing","parameters":[]}]}]
	var effects:Array = LoadHelper.load_effects([declaration("S1 DAY_START choice",[{"func_name":"ask_player_option","parameters":[choices,"round choice",0,1]}],[TimePoints.DAY_START])],null,context)
	check(effects.size() == 1 and EffectManager.register_effect(effects[0],0), "PRE real DAY_START listener")
	var started:Dictionary = GameProgress.start_game(context)
	check(started.ok and EffectManager.waiting_effect != null and GameProgress.current_phase_index == -1 and MapData.miyama._events.is_empty(), "real GP round tail waits for ordinary DAY_START choice")
	if stale:
		check(GameProgress.reset_progress().ok, "PRE rotate while GP round tail saved")
		await get_tree().process_frame
		check(GameProgress.current_round == 0 and GameProgress.current_phase_index == -1 and MapData.miyama._events.is_empty(), "old saved GP round tail cannot advance new domain")
	else:
		check(EffectManager.submit_option_choice(EffectManager.waiting_effect,0), "PRE answer real GP round choice")
		for _i in 12:
			await get_tree().process_frame
			if GameProgress.current_phase_index >= 0: break
		check(GameProgress.current_phase_index == 0 and MapData.miyama._events.size() == 1 and MapData.shinto._events.size() == 1, "same GP round tail places events and advances once after choice")
		check(GameLog.query({"type":"refill_hand"}).size() == 2, "round choice does not redispatch player refill roots")

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	print("USER_DIR ",OS.get_user_data_dir())
	await factory_and_placement()
	await rejection_cases()
	await guard_case(false)
	await guard_case(true)
	await role_deal_and_refill()
	await ordinary_choice(false)
	await ordinary_choice(true)
	await round_choice_tail(false)
	await round_choice_tail(true)
	GameData.release_game_objects()
	RR.stop_tracking()
	print("RESULT ",JSON.stringify({"suite":"card_s1_progress_origin","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
