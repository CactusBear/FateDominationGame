extends Node

const RuleRandom = preload("res://scripts/match/rule_random.gd")
var checks:int = 0
var failures:Array = []
var context:SessionContext
var helper_result:Variant
var operation:String = "draw"
var reset_hits:int = 0
var callback_state:Dictionary = {}
var helper_marker:bool = false:
	set(value):
		helper_marker = value
		if value:
			match operation:
				"draw": helper_result = DrawCardFromPlDeckToHand.new().exec(0, 0)
				"refill": helper_result = RefillHand.new().exec(0, 3)
				"shuffle": helper_result = ReshuffleDiscard.new().exec(0)
				"event": helper_result = AddEventFromDeck.new().exec(MapData.miyama, 1, true)
var reset_marker:bool = false:
	set(value):
		reset_marker = value
		if value:
			reset_hits += 1
			for frame in EffectManager.execution_runtime_snapshot().functions:
				if frame.has("loop"): callback_state = frame.loop
			check(GameProgress.reset_progress().get("ok", false), "PRE real synchronous progress reset")

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func rejected(result) -> bool:
	return result is Dictionary and result.get("ok") == false and result.has("reason") and result.has("context")

func fresh() -> void:
	var result:Dictionary = GameData.reset_game_session([0,1])
	check(result.get("ok", false), "PRE public session reset")
	context = result.context
	RuleRandom.start_seed(614)
	GameLog.reset()
	reset_hits = 0
	callback_state = {}
	helper_result = null
	for id in [0,1]: GameData.player_data_library[id].is_out = false

func card() -> BaseHandCard:
	var c := BaseHandCard.new()
	c._name = "origin-draw-probe"
	c._cost = BaseNumber.new(0)
	c._power = BaseNumber.new(0)
	check(SessionGeneration.bind_origin(c, context.token(), &"a1_refill_draw.fixture_factory").ok, "PRE new fixture card bound by producer")
	return c

func effect(name:String, funcs:Array, points:Array = []) -> BaseEffect:
	var effects:Array = LoadHelper.load_effects([{"effect_name":name,"time_points":points,"priority":0,"is_pure_passive":true,"is_residue":false,"effect_numbers":[],"funcs":funcs}], null, context)
	check(effects.size() == 1, "PRE trusted effect factory " + name)
	if effects.is_empty(): return null
	check(EffectManager.register_effect(effects[0], 0), "PRE real effect registered " + name)
	return effects[0]

func helper(which:String) -> void:
	operation = which
	EffectManager.activate_effect(effect("helper-" + which, [{"func_name":"set_property","parameters":[self,"helper_marker",true]}]))

func no_source() -> void:
	fresh()
	var data:Dictionary = GameData.player_data_library[0]
	data.deck = [card()]
	var result = DrawCardFromPlDeckToHand.new().exec(0,0)
	check(rejected(result), "empty draw source explicit rejection")
	check(data.deck.size() == 1 and data.hand_cards.is_empty(), "empty draw source cannot move card")
	data.deck.clear()
	data.discard = [card()]
	result = ReshuffleDiscard.new().exec(0)
	check(rejected(result), "empty shuffle source explicit rejection")
	check(data.deck.is_empty() and data.discard.size() == 1, "empty shuffle source cannot move discard")
	# 原实现会抛缺键；只在新拒绝 ABI 存在时直跑游标入口，不用 SCRIPT ERROR 冒业务 RED。
	if rejected(result):
		check(rejected(RefillHand.new().exec(0,3)), "empty refill source explicit rejection")
		check(rejected(AddEventFromDeck.new().exec(MapData.miyama,1,true)), "empty event source explicit rejection")
		check(rejected(Callable(RefillHand,"_resume_refill").call({})), "empty refill cursor explicit rejection")
		check(rejected(Callable(AddEventFromDeck,"_resume_add").call({})), "empty event cursor explicit rejection")
	else:
		check(false, "empty refill source explicit rejection")
		check(false, "empty event source explicit rejection")

func legal() -> void:
	fresh()
	var data:Dictionary = GameData.player_data_library[0]
	var one:BaseHandCard = card()
	data.deck = [one]
	helper("draw")
	check(data.deck.is_empty() and data.hand_cards == [one] and not rejected(helper_result), "same-session real frame draw green")
	fresh()
	data = GameData.player_data_library[0]
	data.deck = []
	data.discard = [card(),card(),card()]
	helper("refill")
	check(helper_result is int and helper_result == 3, "same-session refill returns original count")
	check(data.hand_cards.size() == 3 and data.deck.is_empty() and data.discard.is_empty(), "same-session refill includes real reshuffle and three draws")
	check(GameLog.query({"type":"refill_hand"}).size() == 1 and GameLog.query({"type":"draw"}).size() == 3, "legal refill facts recorded once")
	fresh()
	MapData.event_deck = []
	helper("event")
	check(helper_result is int and helper_result == 0, "current event empty deck legitimate zero")

func synchronous_rejection() -> void:
	for which in ["draw", "refill", "shuffle"]:
		fresh()
		var data:Dictionary = GameData.player_data_library[0]
		data.deck = [card(),card(),card()] if which != "shuffle" else []
		data.discard = [card(),card()] if which == "shuffle" else []
		var point:String = TimePoints.DECK_RESHUFFLED if which == "shuffle" else TimePoints.CARD_DRAWN
		effect("reset-on-"+which, [{"func_name":"set_property","parameters":[self,"reset_marker",true]}], ["self_"+point])
		helper(which)
		check(reset_hits == 1 and not SessionGeneration.validate_context(context).ok, "PRE actual " + which + " listener invalidates original source")
		check(rejected(helper_result) and helper_result.reason == &"stale_session", which + " synchronous return explicit stale rejection")
		if which == "refill":
			check(data.hand_cards.size() == 1 and data.deck.size() == 2, "old refill stops before second card")
		check(not EffectManager.runtime_guard_status().paused, "source refusal is not resumable pause " + which)

func old_explicit() -> void:
	fresh()
	var old:SessionContext = context
	fresh()
	var data:Dictionary = GameData.player_data_library[0]
	data.deck = [card()]
	var draw := DrawCardFromPlDeckToHand.new()
	var shuffle := ReshuffleDiscard.new()
	var result:Variant
	# 原实现的二参签名不制造 arity RED；新 ABI 才实跑保存来源参数。
	if draw.get_method_argument_count("exec") >= 3:
		result = draw.call("exec",0,0,old)
		check(rejected(result) and result.reason == &"stale_session", "saved old draw origin explicit rejection")
		check(data.deck.size() == 1 and data.hand_cards.is_empty(), "saved old draw source cannot write new member")
		data.deck.clear()
		data.discard = [card()]
		result = shuffle.call("exec",0,old)
		check(rejected(result) and data.deck.is_empty() and data.discard.size() == 1, "saved old shuffle source cannot write new member")
	else:
		check(false, "saved old draw origin explicit rejection")
		check(false, "saved old shuffle source cannot write new member")

func saved_cursors() -> void:
	fresh()
	var data:Dictionary = GameData.player_data_library[0]
	var state:Dictionary = {"context":context,"player":0,"data":data,"hand":data.hand_cards,"deck":data.deck,"discard":data.discard,"completed":false,"phase":"draw","drawn":0,"target":3}
	var events:Dictionary = {"context":context,"area":MapData.miyama,"deck":MapData.event_deck,"events":MapData.miyama._events,"areas":MapData.areas,"placed":0,"count":1}
	check(GameProgress.reset_progress().ok, "PRE saved cursor reset preserves member objects")
	check(is_same(data, GameData.player_data_library[0]), "PRE actual same-ID same dictionary survives reset")
	if DrawCardFromPlDeckToHand.new().get_method_argument_count("exec") >= 3:
		check(rejected(Callable(RefillHand,"_resume_refill").call(state)) and state.drawn == 0, "old refill cursor refuses before field progress")
		check(rejected(Callable(AddEventFromDeck,"_resume_add").call(events)) and events.placed == 0, "old event cursor refuses before field progress")

func actual_guard() -> void:
	for stale in [false,true]:
		fresh()
		var data:Dictionary = GameData.player_data_library[0]
		data.deck = [card(),card(),card()]
		var root:BaseEffect = effect("guard-refill", [{"func_name":"refill_hand","parameters":[0,3],"var_index":0}])
		check(EffectManager.configure_runtime_guard({"enabled":true,"steps":3,"seconds":0.0}), "PRE actual refill guard enabled")
		EffectManager.activate_effect(root)
		check(EffectManager.runtime_guard_status().paused, "PRE actual refill guard pauses")
		var before:int = data.hand_cards.size()
		if stale:
			check(GameProgress.reset_progress().ok, "PRE old paused refill reset")
			check(not EffectManager.resume_runtime_guard() and data.hand_cards.size() == before, "old actual paused refill rejected with no extra draw")
			check(EffectManager.reset_runtime().ok, "PRE old guard public cleanup")
		else:
			var resumed:int = 0
			while EffectManager.runtime_guard_status().paused and resumed < 12:
				check(EffectManager.resume_runtime_guard(), "same-session actual refill resume accepted")
				resumed += 1
			check(not EffectManager.runtime_guard_status().paused and data.hand_cards.size() == 3, "same-session actual guard refill finishes three once")
			check(GameLog.query({"type":"draw"}).size() == 3 and GameLog.query({"type":"refill_hand"}).size() == 1, "guard refill facts not repeated")
		check(EffectManager.configure_runtime_guard({"enabled":false,"steps":0,"seconds":0.0}), "PRE guard disabled")

func event_clone_boundary() -> void:
	fresh()
	var template := BaseEvent.new("event-origin-template","",BaseNumber.new(0),[])
	MapData.event_deck = [template]
	var before:int = MapData.miyama._events.size()
	helper("event")
	# 正式通用克隆没有来源；守卫要求消费端拒绝而不是凭 frame 给未绑定 clone 补票。
	check(rejected(helper_result) and helper_result.reason == &"unbound_origin", "unbound runtime event clone explicit refusal")
	check(MapData.miyama._events.size() == before, "unbound event clone not reported or placed as success")

func _ready() -> void:
	print("ENV user_dir=",OS.get_user_data_dir()," pid=",OS.get_process_id())
	var args:PackedStringArray = OS.get_cmdline_user_args()
	var mode:String = args[0] if not args.is_empty() else "all"
	if mode in ["all","source"]: no_source()
	if mode in ["all","legal"]: legal()
	if mode in ["all","sync"]: synchronous_rejection()
	if mode in ["all","old"]: old_explicit()
	if mode in ["all","cursor"]: saved_cursors()
	if mode in ["all","event"]: event_clone_boundary()
	if mode in ["all","guard"]: actual_guard()
	GameStart.end_session()
	GameData.release_game_objects()
	RuleRandom.stop_tracking()
	print("RESULT ",JSON.stringify({"suite":"a1_refill_draw_origin","checks":checks,"failures":failures,"mode":mode}))
	get_tree().quit(0 if failures.is_empty() else 1)
