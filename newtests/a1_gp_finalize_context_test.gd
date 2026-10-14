extends Node

const Sessions = preload("res://scripts/system/session_generation.gd")
var checks:int = 0
var failures:Array = []

# The public location query can change between preflight and finalization.
# No replacement of RegularPlay/EM and no forged completion facts.
class ChangingLocation extends RefCounted:
	var reads:int = 0
	var area:BaseMapArea
	func get_from():
		reads += 1
		return null if reads == 1 else area

func check(label:String, ok:bool) -> void:
	checks += 1
	print("CHECK ",label," ",ok)
	if not ok: failures.append(label)

func _ready() -> void:
	call_deferred("run")

func setup() -> SessionContext:
	var reset:Dictionary = GameProgress.reset_progress()
	check("reset returns original context",reset.ok)
	if not reset.ok: return null
	var source:SessionContext = reset.context
	check("same source clears actual runtime",EffectManager.clear_runtime_in_context(source).ok)
	GameLog.reset()
	GameLog.set_context(1,"action")
	GameData.player_data_library.clear()
	GameData.player_id = 0
	for id in [0,1]:
		var data:Dictionary = GameData.new_player_data()
		GameData.player_data_library[id] = data
		data.order.number = id
		data.is_out = false
		data.regular_play_min.number = 0
		data.play_limit.number = 2
		data.magic.number = 8
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 2
	GameProgress.current_phase_player_index = 1
	GameProgress.current_player_id = 0
	check("real action member order",GameProgress.get_ordered_player_ids() == [0,1])
	return source

func snapshot() -> Dictionary:
	var resources:Array = []
	for id in [0,1]:
		var data:Dictionary = GameData.player_data_library[id]
		resources.append([data.magic.number,data.hand_cards.duplicate(),data.played_cards.duplicate()])
	return {"progress":[GameProgress.current_round,GameProgress.current_phase_index,
		GameProgress.current_phase_player_index,GameProgress.current_player_id,GameProgress.is_game_over],
		"resources":resources,"facts":GameLog.query({},null,-1).duplicate(true),
		"keys":GameData.player_data_library.keys(),"messages":EffectManager.messages.duplicate(true),
		"token":Sessions.current_token().token}

func unbound_and_saved() -> void:
	var source:SessionContext = setup()
	if source == null: return
	var before:Dictionary = snapshot()
	check("missing source forced finalize fails closed",not RegularPlay.finalize(0,true))
	check("missing source has no completion or progress write",not RegularPlay.completed(0) and snapshot() == before)
	var saved_finalize:Callable = Callable(RegularPlay,"finalize").bind(0,true,source)
	var saved_end:Callable = Callable(GameProgress,"end_current_player_action").bind(source)
	var data:Dictionary = GameData.player_data_library[0]
	var reset:Dictionary = GameProgress.reset_progress()
	check("reset only revokes origin while retaining actual member",reset.ok and is_same(data,GameData.player_data_library[0]) and not Sessions.validate_context(source).ok)
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 2
	GameProgress.current_phase_player_index = 1
	GameProgress.current_player_id = 0
	before = snapshot()
	check("saved old finalize refuses same dictionary",not saved_finalize.call())
	check("saved old GP end refuses original context",not saved_end.call())
	check("old saved consumers cannot advance or publish completion",snapshot() == before and not RegularPlay.completed(0))
	check("malformed GP context refuses without refresh",not GameProgress.end_current_player_action({"context":reset.context}) and snapshot() == before)

func legal_end() -> void:
	var source:SessionContext = setup()
	if source == null: return
	check("legitimate action can end before finalize",GameProgress.can_end_current_player_action() and not RegularPlay.completed(0))
	check("same-session GP end accepts original context",GameProgress.end_current_player_action(source))
	check("GP finalize publishes exactly one real completion",RegularPlay.completed(0) and GameLog.query({"type":"regular_play","actor":0},0).size() == 1)
	check("successful finalize advances once to next member",GameProgress.current_round == 1 and GameProgress.current_phase_index == 2 and GameProgress.current_phase_player_index == 2 and GameProgress.current_player_id == 1)
	check("same original context still valid",Sessions.validate_context(source).ok)
	check("explicit same-source finalize remains idempotent",RegularPlay.finalize(0,true,source) and GameLog.query({"type":"regular_play","actor":0},0).size() == 1)

func actual_finalize_refusal() -> void:
	var source:SessionContext = setup()
	if source == null: return
	var location:ChangingLocation = ChangingLocation.new()
	for area in MapData.areas:
		if area is BaseMapArea and area._score_need_win:
			location.area = area
			break
	check("actual battlefield declaration available",location.area != null)
	if location.area == null: return
	var data:Dictionary = GameData.player_data_library[0]
	data.location = location
	var card:BaseAttack = BaseAttack.new("gp-finalize-recheck","",[],BaseNumber.new(0),BaseNumber.new(1))
	data.hand_cards.append(card)
	var before:Dictionary = snapshot()
	# First get_from returns no battlefield, so completion preflight permits end.
	# Finalize's second query sees an actual battlefield without face-up play.
	# A real legal add exists, so forced=true must still refuse completion.
	check("actual finalize refusal is consumed",not GameProgress.end_current_player_action(source))
	check("real finalize recheck reached beyond preflight",location.reads >= 2)
	check("refused finalize does not publish completion",not RegularPlay.completed(0))
	check("refused finalize changes no phase player resources or facts",snapshot() == before)
	check("refusal is rule-side while original source remains valid",Sessions.validate_context(source).ok)
	check("real legal addition prevents forced bypass",RegularPlay.has_legal_add(0))

func run() -> void:
	print("USER_PATH ",OS.get_user_data_dir())
	unbound_and_saved()
	legal_end()
	actual_finalize_refusal()
	print("RESULT ",JSON.stringify({"suite":"a1_gp_finalize_context","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
