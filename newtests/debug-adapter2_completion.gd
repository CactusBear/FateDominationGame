extends Node

const RR = preload("res://scripts/match/rule_random.gd")
var checks:int = 0
var failures:Array = []
var context:SessionContext
var completed:int = 0

func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)

func declaration(funcs:Array) -> Dictionary:
	return {"effect_name":"adapter completion", "time_points":[TimePoints.SELF_CARD_REVEALED], "priority":0,
		"is_pure_passive":true, "is_residue":false, "effect_numbers":[], "funcs":funcs}

func event_template(effects:Array = []) -> BaseEvent:
	return LoadEvent.build_event({"card_name":"adapter event", "card_img":"", "score":{"number":1,"can_change":true,"is_pure_number":true}, "effects":effects}, "")

func situation_template(effects:Array = []) -> BaseSituation:
	return LoadSituation.build_situation({"card_name":"adapter situation", "card_img":"", "magic":{"number":0,"can_change":true,"is_pure_number":true}, "effects":effects}, "")

func copy_template(template:BaseCard) -> BaseCard:
	var factory := CloneContext.new()
	check(factory.configure_template(context, [template]), "PRE trusted C0 template")
	var copied:Dictionary = factory.copy_result(template, context)
	check(copied.ok, "PRE C0 original runtime source")
	return copied.object

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var args:Array = OS.get_cmdline_user_args()
	var site:String = str(args[0]) if not args.is_empty() else "reveal"
	var kind:String = str(args[1]) if args.size() > 1 else "choice"
	var stale:bool = args.has("stale")
	print("USER_DIR ", OS.get_user_data_dir())
	GameStart.end_session()
	GameData.loaded_masters = []
	GameData.loaded_servants = []
	RR.start_seed(817)
	check(GameStart.game_start([0,1]), "PRE actual successful GameStart")
	context = GameStart.startup_context()
	check(context != null and SessionGeneration.validate_context(context).ok, "PRE saved startup origin")
	RR.start_seed(817)
	MapData.reset_board()
	GameProgress.current_round = 1
	LoadSituation.climax_situations = {}
	var console = preload("res://assets/scenes/debug/debug_console.tscn").instantiate()
	console.initialize(null)
	var session:DebugSession = console.session
	check(is_same(session.source_context, context) and is_same(session.registry.source_context, context), "PRE formal original identity")
	session.action_completed.connect(func(_name:String, _result:Dictionary): completed += 1)
	if site == "reject":
		await rejection(session)
	else:
		var funcs:Array
		if kind == "choice":
			var choices:Array = [{"shown_option_name":"continue", "funcs":[{"func_name":"do_nothing","parameters":[]}]}]
			funcs = [{"func_name":"ask_player_option","parameters":[choices,"adapter choice",0,1]}]
		else:
			funcs = [{"func_name":"do_nothing","parameters":[]},{"func_name":"do_nothing","parameters":[]},{"func_name":"do_nothing","parameters":[]}]
			check(EffectManager.configure_runtime_guard({"enabled":true,"steps":1,"seconds":0.0}), "PRE guard declared")
		var command:String
		if site == "reveal":
			for area in [MapData.miyama, MapData.shinto]:
				var event:BaseEvent = copy_template(event_template([declaration(funcs)]))
				event.set_concealed(true)
				area._events.append(event)
			GameProgress.event_placements = [{"area_name":MapData.miyama._area_name,"concealed":true},{"area_name":MapData.shinto._area_name,"concealed":true}]
			command = "event.reveal_planned"
		else:
			MapData.situations = [copy_template(situation_template([declaration(funcs)]))]
			command = "situation.activate"
		var result:Dictionary = session.execute_action(command)
		var state:Dictionary = result.get("state", {})
		check(result.get("pending", false) and not result.get("changed", false), "pending is not reported as changed")
		check(not state.is_empty() and is_same(state.get("context"), context), "resolver receipt retains exact original context")
		check(EffectManager.waiting_effect != null if kind == "choice" else EffectManager.runtime_guard_status().paused, "actual ordinary choice or guard reached")
		check(session.audit.size() == 1 and session.audit[0].pending and completed == 0, "audit and notification await actual tail")
		await get_tree().process_frame
		check(result.get("pending", false) and session.audit[0].pending and completed == 0, "unanswered tail remains pending after frame")
		if stale:
			check(GameProgress.reset_progress().ok, "PRE rotate source during actual saved wait")
		else:
			var answers:int = 0
			var resumes:int = 0
			var accepted:bool = true
			for _i in 96:
				if EffectManager.waiting_effect != null:
					accepted = EffectManager.submit_option_choice(EffectManager.waiting_effect, 0) and accepted
					answers += 1
				elif EffectManager.runtime_guard_status().paused:
					accepted = EffectManager.resume_runtime_guard() and accepted
					resumes += 1
				await get_tree().process_frame
				if not result.get("pending", false): break
			check(accepted and (answers == (2 if site == "reveal" else 1) if kind == "choice" else resumes > 0), "real saved choice or guard resumes without redispatch")
		for _i in 8:
			await get_tree().process_frame
			if not result.get("pending", false) and not session.audit[0].pending: break
		check(not result.get("pending", false) and not session.audit[0].pending and completed == 1, "one final audit and completion after resolver tail")
		if stale:
			check(not result.ok and not result.changed and not session.audit[0].ok and not session.audit[0].changed, "invalidated original receipt is audited as refusal")
			check(result.get("error", "") == "stale_session" and session.audit[0].reason == "stale_session", "deferred refusal preserves original reason")
		else:
			check(result.ok and result.changed and state.get("completed", false) and state.get("ok", false), "final result consumes completed and ok")
			check(session.audit[0].ok and session.audit[0].changed and session.audit[0].get("result", {}).get("value") == result.get("value"), "final audit follows same resolver result")
			if site == "reveal":
				check(result.get("value") == 2 and not MapData.miyama._events[0]._is_concealed and not MapData.shinto._events[0]._is_concealed, "final count includes both completed areas")
			else:
				check(MapData.active_situation != null and result.get("object_id") == MapData.active_situation.get_instance_id(), "activation summary is read after completion")
	session.shutdown()
	console.free()
	GameStart.end_session()
	RR.stop_tracking()
	print("RESULT ", JSON.stringify({"suite":"debug-adapter2_completion","site":site,"kind":kind,"stale":stale,"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func rejection(session:DebugSession) -> void:
	var event:BaseEvent = event_template()
	MapData.miyama._events.append(event)
	var result:Dictionary = session.execute_action("event.clear")
	check(not result.ok and not result.changed, "event clear consumes rejected receipt")
	check(MapData.miyama._events.has(event) and MapData.event_discard.is_empty(), "event refusal leaves original board")
	var old:BaseSituation = situation_template()
	MapData.active_situation = old
	result = session.execute_action("situation.clear")
	check(not result.ok and not result.changed, "situation clear consumes rejected receipt")
	check(is_same(MapData.active_situation, old) and MapData.situation_discard.is_empty(), "situation refusal leaves original board")
	LoadSituation.situations = [situation_template()]
	result = session.execute_action("situation.replace", {"source_name":"adapter situation"})
	check(not result.ok and not result.changed, "replacement consumes rejected clear receipt")
	check(is_same(MapData.active_situation, old) and MapData.situation_discard.is_empty(), "replacement stops before installing clone when clear refused")
	check(session.audit.size() == 3 and not session.audit[2].ok and not session.audit[2].changed, "synchronous refusal audit never reports success")
