extends Node
var checks := 0
var failures: Array = []
func check(ok: bool, label: String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	GameData.release_game_objects()
	var started: Dictionary = GameData.reset_game_session([0])
	check(started.get("ok", false), "trusted session lifecycle")
	var context: SessionContext = started.context
	GameLog.reset()
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	GameData.player_id = 0
	var player: Dictionary = GameData.player_data_library[0]
	player.is_out = false
	player.magic.number = 8
	player.play_limit.number = 4
	player.regular_play_min.number = 1
	MapData.active_situation = null
	for area in MapData.areas:
		area._events.clear()
		area._buffs.clear()
	var loaded: Array = LoadGame.load_skills([{"skill_name":"常规出牌来源对照", "skill_card_img":"", "attributes":[], "cost":{"number":1,"can_change":true,"is_pure_number":true}, "power":{"number":1,"can_change":true,"is_pure_number":true}, "ignore_limit":false, "effects":[]}], "", null, "skill", context)
	check(loaded.size() == 1, "trusted runtime skill factory")
	if loaded.is_empty():
		get_tree().quit(1)
		return
	var card: BaseSkill = loaded[0]
	player.hand_cards = [card]
	check(card._is_awakened and not card._need_extra_play and card._play_requirements.is_empty(), "normal awake skill without extra requirement")
	check(SessionGeneration.origin_of(card).get("ok", false), "factory registered original card origin")
	check(not EffectManager.execution_context().get("ok", false), "normal UI outside effect execution frame")
	var explicit: Dictionary = RegularPlay.payment_quote(0, context)
	var implicit: Dictionary = RegularPlay.payment_quote(0)
	check(not explicit.is_empty(), "original context creates valid readonly payment quote")
	check(implicit.is_empty(), "no effect frame yields empty implicit payment quote")
	var good: Array = RegularPlay.pending_modes(0, [], [], card, explicit)
	var bad: Array = RegularPlay.pending_modes(0, [], [], card)
	check(good == [false], "existing rules permit normal faceup skill with original quote")
	check(bad.is_empty(), "same normal skill no quote rejected")
	var builder = preload("res://scripts/match/view_builder.gd").new()
	var query = preload("res://scripts/match/match_seat_query.gd").new(builder)
	var source = preload("res://scripts/game_scene/battle_io/local_battle_source.gd").new(0, builder, query)
	var empty: Dictionary = source.read_group_preview([], [])
	var selected: Dictionary = source.read_group_preview([card], [false])
	check(empty.preview.ok and empty.preview.candidates.is_empty(), "production local source drops legal regular candidate")
	check(not selected.preview.can_submit and RegularPlay.can_submit_group(0, [card], [false], false, explicit), "production selected group denies same legal explicit group")
	check(player.hand_cards == [card] and player.played_cards.is_empty() and player.magic.number == 8 and GameLog.query({}, null).is_empty(), "diagnostic queries change no rule state")
	print("GROUP_SOURCE_BOUNDARY ", JSON.stringify({"implicit_quote_empty":implicit.is_empty(),"explicit_modes":good,"implicit_modes":bad,"source_empty":empty,"source_selected":selected}))
	print("RESULT ", JSON.stringify({"suite":"ui_affordance2_group_source_boundary","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
