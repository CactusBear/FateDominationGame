extends Node

const RR = preload("res://scripts/match/rule_random.gd")
var checks:int = 0
var failures:Array = []
var context:SessionContext
var mode:int = 1
var direct:bool = false

func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)

func event_template() -> BaseEvent:
	return LoadEvent.build_event({"card_name":"debug board event","card_img":"","score":{"number":1,"can_change":true,"is_pure_number":true},"effects":[]}, "")

func situation_template(name:String) -> BaseSituation:
	return LoadSituation.build_situation({"card_name":name,"card_img":"","magic":{"number":0,"can_change":true,"is_pure_number":true},"effects":[]}, "")

func copy_template(template:BaseCard) -> BaseCard:
	var factory := CloneContext.new()
	check(factory.configure_template(context, [template]), "PRE C0 trusted template identity")
	var copied:Dictionary = factory.copy_result(template, context)
	check(copied.ok, "PRE C0 runtime copy original source")
	return copied.object

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var args:Array = OS.get_cmdline_user_args()
	if not args.is_empty(): mode = int(args[0])
	direct = args.has("direct")
	print("USER_DIR ", OS.get_user_data_dir())
	GameStart.end_session()
	GameData.loaded_masters = []
	GameData.loaded_servants = []
	RR.start_seed(817)
	check(GameStart.game_start([0,1]), "PRE real GameStart startup")
	context = GameStart.startup_context()
	check(context != null and SessionGeneration.validate_context(context).ok, "PRE real saved startup source")
	var consume_context:SessionContext = null if args.has("omit") else context
	RR.start_seed(817)
	MapData.reset_board()
	GameProgress.current_round = 1
	LoadSituation.climax_situations = {}
	var console = preload("res://assets/scenes/debug/debug_console.tscn").instantiate()
	console.initialize(null)
	var session:DebugSession = console.session
	check(is_same(session.source_context, context), "PRE production console delivers exact startup source")
	check(is_same(session.registry.source_context, context), "PRE production registry saves exact startup source")
	var result:Dictionary
	if mode == 1 or mode == 2:
		var event:BaseEvent = copy_template(event_template())
		event.set_concealed(true)
		MapData.miyama._events.append(event)
		GameProgress.event_placements = [{"area_name":MapData.miyama._area_name,"concealed":true}]
		if mode == 1:
			result = EventResolver.new().clear_all(consume_context) if direct else session.execute_action("event.clear")
			check(result.get("ok", false) and MapData.miyama._events.is_empty() and MapData.event_discard.has(event), "site 1 original-source event clear actually completed")
		else:
			if direct:
				result = EventResolver.new().start_reveal(GameProgress.event_placements, consume_context)
				result = await GameProgress.wait_progress_state(result, context)
			else:
				result = session.execute_action("event.reveal_planned")
				await get_tree().process_frame
			check(result.get("ok", false) and not event._is_concealed and not result.get("pending", false), "site 2 original-source reveal actually completed")
	elif mode == 3:
		MapData.situations = [copy_template(situation_template("debug activate"))]
		if direct:
			result = SituationResolver.new().activate(consume_context)
			result = await GameProgress.wait_progress_state(result, context)
		else:
			result = session.execute_action("situation.activate")
			await get_tree().process_frame
		check(result.get("ok", false) and MapData.active_situation != null and not result.get("pending", false), "site 3 original-source activation actually completed")
	elif mode == 4 or mode == 5:
		var old:BaseSituation = copy_template(situation_template("debug old"))
		MapData.active_situation = old
		if mode == 4:
			result = SituationResolver.new().clear_all(consume_context) if direct else session.execute_action("situation.clear")
			check(result.get("ok", false) and MapData.active_situation == null and MapData.situation_discard.has(old), "site 4 original-source situation clear actually completed")
		else:
			var template:BaseSituation = situation_template("debug replacement")
			LoadSituation.situations = [template]
			if direct:
				var replacement:BaseSituation = copy_template(template)
				result = SituationResolver.new().clear_all(consume_context)
				if result.ok:
					MapData.active_situation = replacement
					TimePointChecker.card_revealed(replacement, context)
			else:
				result = session.execute_action("situation.replace", {"source_name":"debug replacement"})
			check(result.get("ok", false) and MapData.situation_discard.has(old) and MapData.active_situation != old, "site 5 original-source replacement cleared original situation")
			var origin:Dictionary = SessionGeneration.origin_of(MapData.active_situation)
			check(origin.ok and is_same(origin.context.token(), context.token()) and origin.context.origin() == context.origin(), "site 5 replacement retains creation receipt token and origin")
	session.shutdown()
	console.free()
	GameStart.end_session()
	RR.stop_tracking()
	print("RESULT ", JSON.stringify({"suite":"debug-console-origin_five_sites","site":mode,"direct_resolver_control":direct,"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
