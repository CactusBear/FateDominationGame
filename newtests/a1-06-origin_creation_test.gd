extends "res://newtests/a1_06_regular_origin_test.gd"

# Read-only observation of cards created by the original fixture methods.
# The observer never binds, refreshes, or supplies provenance to a consumer.
var creation_source:SessionContext = null
var observed:Dictionary = {}
var last_baseline:Dictionary = {}

func check(label:String, ok:bool) -> void:
	if label == "old requeued finish cannot finish or pay in new root":
		var data:Dictionary = GameData.player_data_library[0]
		var facts:Array = GameLog.query({}, null, -1)
		var new_types:Array = []
		for fact in facts.slice(last_baseline.get("logs", []).size()):
			new_types.append(fact.type)
		print("EFFECT_END_DIAGNOSTIC ", JSON.stringify({
			"old_tail_paid": data.magic.number != last_baseline.get("magic"),
			"old_tail_entered": data.played_cards != last_baseline.get("played"),
			"old_tail_completed": RegularPlay.completed(0),
			"new_root_fact_types": new_types,
			"expected_new_root_fact_types": ["effect", "time_point"],
		}))
	super.check(label, ok)

func setup() -> SessionContext:
	var original:SessionContext = super.setup()
	creation_source = original
	return original

func observe_created(card:Variant) -> void:
	if not card is BaseAttack:
		return
	var site:String = ""
	match card._name:
		"regular-prep-card": site = "90"
		"a1-06-tail": site = "169"
		"pure": site = "234"
		"dynamic-0": site = "251"
		"declared-true-name": site = "305"
	if site.is_empty() or observed.has(site):
		return
	var origin:Dictionary = Sessions.origin_of(card)
	observed[site] = {
		"bound": origin.ok and creation_source != null and is_same(origin.context.token(), creation_source.token()) and origin.context.origin() == creation_source.origin(),
		"published_once": GameData.objects.count(card) == 1,
	}

func snapshot() -> Dictionary:
	var data:Dictionary = GameData.player_data_library[0]
	for card in data.hand_cards:
		observe_created(card)
	last_baseline = super.snapshot()
	return last_baseline

func regular_call(method:String, arguments:Array):
	if method == "add" and arguments.size() > 1:
		observe_created(arguments[1])
	elif method == "submit_group" and arguments.size() > 1:
		for card in arguments[1]:
			observe_created(card)
	return super.regular_call(method, arguments)

func run() -> void:
	print("PATH_PROOF ", JSON.stringify({"pid":OS.get_process_id(),"user":OS.get_user_data_dir()}))
	if OS.get_cmdline_user_args().has("effect-end"):
		requeued_finish()
		print("RESULT ", JSON.stringify({"suite":"a1-06-origin-effect-end-diagnostic","checks":checks,"failures":failures}))
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	entries()
	pure_queries()
	tails(false)
	dynamic_limits(4)
	router_top_source()
	# Clear the phase through its real public producer so a missing phase source cannot
	# hide behind an ACTION_PHASE left over by an earlier case.
	var phase_source:SessionContext = setup()
	TimePointChecker.set_phase_time_points([], phase_source)
	pending()
	check("phase creation retains explicit original source at :126", TimePointChecker.phase_time_points == [TimePoints.ACTION_PHASE])
	for site in ["90","169","234","251","305"]:
		check("actual creation observed at original :" + site, observed.has(site))
		check("creation origin uses original lifecycle at :" + site, observed.get(site, {}).get("bound", false))
		check("creation publishes once at :" + site, observed.get(site, {}).get("published_once", false))
	print("ORIGIN_OBSERVATIONS ", JSON.stringify(observed))
	print("RESULT ", JSON.stringify({"suite":"a1-06-origin-creation","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
