extends Node

var checks:int = 0
var failures:Array = []

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ",label," ",ok)
	if not ok: failures.append(label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var prepared:Dictionary = GameData.reset_game_session([0,1])
	check(prepared.ok,"real session created")
	var context:SessionContext = prepared.context
	preload("res://scripts/match/rule_random.gd").start_seed(812)
	var copied:Dictionary = MasterManager.prepare_role_runtime(GameData.loaded_servants[0],context)
	check(copied.ok,"real role factory supplies runtime")
	GameData.player_data_library[0].servant = copied.object
	var outcome:Dictionary = await GameProgress.wait_progress_operation(GameProgress.start_progress_operation("deal_player_cards",[0],context))
	check(outcome.ok,"registered DealPlayerCards consumes genuine execution frame")
	var data:Dictionary = GameData.player_data_library[0]
	check(not data.deck.is_empty(),"actual servant deck published")
	check(not data.deck.is_empty() and SetCardConcealed.source_is_current(data.deck[0],context),"dealt card retains original source")
	var before:Array = data.deck.duplicate()
	var refusal = DealPlayerCards.new().exec(0)
	check(refusal is Dictionary and refusal.get("ok") == false,"unframed consumer returns explicit refusal")
	check(data.deck == before,"unframed refusal leaves actual deck unchanged")
	var missing:Dictionary = await GameProgress.wait_progress_operation(GameProgress.start_progress_operation("deal_player_cards",[999],context))
	check(not missing.ok,"unknown member refusal propagated through registered root")
	check(not GameData.player_data_library.has(999),"rejected unknown member never creates data")
	GameData.release_game_objects()
	preload("res://scripts/match/rule_random.gd").stop_tracking()
	print("RESULT ",JSON.stringify({"suite":"s1_deal_consumer","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
