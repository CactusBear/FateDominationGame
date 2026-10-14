extends Node
var checks := 0
var failures: Array = []
var commands = MatchCommands.new()
var replies: Array = []
func check(ok: bool, label: String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)
func _ready() -> void:
	call_deferred("run")
func prepare(context: SessionContext) -> BaseSkill:
	GameLog.reset()
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	GameData.player_id = 0
	var player: Dictionary = GameData.player_data_library[0]
	player.is_out = false
	player.magic.number = 8
	player.play_limit.number = 4
	player.regular_play_min.number = 1
	player.hand_cards.clear()
	player.played_cards.clear()
	player.master_skills.clear()
	player.servant_skills.clear()
	player.side.skills.clear()
	player.location = null
	MapData.active_situation = null
	for area in MapData.areas:
		area._events.clear()
		area._buffs.clear()
	var loaded: Array = LoadGame.load_skills([{"skill_name":"常规出牌来源对照", "skill_card_img":"", "attributes":[], "cost":{"number":1,"can_change":true,"is_pure_number":true}, "power":{"number":1,"can_change":true,"is_pure_number":true}, "ignore_limit":false, "effects":[]}], "", null, "skill", context)
	check(loaded.size() == 1, "trusted runtime skill factory")
	if loaded.is_empty(): return null
	player.hand_cards.append(loaded[0])
	return loaded[0]
func command_run(kind: String, args: Array, context: SessionContext):
	if kind == "submit_group": return commands.submit_group(args[0], args[1], args[2], context)
	return false
func reply(request_id: int, ok: bool, reason: String) -> void:
	replies.append({"request_id":request_id,"ok":ok,"reason":reason})
func run() -> void:
	var mode: String = "preview"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty(): mode = args[0]
	GameData.release_game_objects()
	var context: SessionContext
	if mode == "startup":
		check(GameStart.game_start([0]), "real successful GameStart")
		context = GameStart.startup_context()
	else:
		var started: Dictionary = GameData.reset_game_session([0])
		check(started.get("ok", false), "trusted session lifecycle")
		context = started.context
	check(SessionGeneration.validate_context(context).ok, "original lifecycle context remains valid")
	var card: BaseSkill = prepare(context)
	if card == null:
		get_tree().quit(1)
		return
	var player: Dictionary = GameData.player_data_library[0]
	check(card._is_awakened and not card._need_extra_play and card._play_requirements.is_empty(), "normal awake skill without extra requirement")
	check(SessionGeneration.origin_of(card).get("ok", false), "factory registered original card origin")
	check(not EffectManager.execution_context().get("ok", false), "ordinary UI has no verified effect frame")
	var builder = preload("res://scripts/match/view_builder.gd").new()
	var query = MatchSeatQuery.new(builder) if mode == "startup" else MatchSeatQuery.new(builder, context)
	var source = LocalBattleSource.new(0, builder, query)
	var payment: Dictionary = query.payment_quote(0)
	check(not payment.is_empty(), "query constructor captured original readonly payment quote")
	check(payment.is_read_only(), "saved payment envelope readonly")
	check(is_same(payment.get("source"), context) and is_same(payment.get("data"), player) and is_same(payment.get("magic"), player.magic), "saved quote preserves original context member magic identity")
	check(RegularPlay.payment_quote(0).is_empty(), "bare RegularPlay default stays fail closed without effect frame")
	if mode == "literal-hard":
		check(not RegularPlay.payment_quote(0).is_empty(), "literal requested bare payment_quote must be nonempty")
	check(RegularPlay.pending_modes(0, [], [], card, payment) == [false], "same normal skill faceup candidate through saved quote")
	var empty: Dictionary = source.read_group_preview([], [])
	var selected: Dictionary = source.read_group_preview([card], [false])
	print("GROUP_QUERY_RECEIPT ", JSON.stringify({"saved_quote_empty":payment.is_empty(),"bare_quote_empty":RegularPlay.payment_quote(0).is_empty(),"saved_modes":RegularPlay.pending_modes(0,[],[],card,payment),"bare_modes":RegularPlay.pending_modes(0,[],[],card),"empty_preview":empty.preview,"selected_preview":selected.preview}))
	check(empty.preview.get("ok", false) and empty.preview.get("candidates", []).size() == 1 and empty.preview.candidates[0].modes == [false], "production local empty preview now offers legal faceup candidate")
	check(selected.preview.get("can_submit", false), "production local selected group now can submit")
	check(player.hand_cards == [card] and player.played_cards.is_empty() and player.magic.number == 8 and GameLog.query({}, null).is_empty(), "all previews remain readonly")
	await get_tree().process_frame
	check(is_same(payment, query.payment_quote(0)) and source.read_group_preview([card], [false]).preview.get("can_submit", false), "deferred query retains exact original quote")
	if mode == "submit" or mode == "formal-submit":
		var dispatcher = MatchCommandDispatcher.new(Callable(EffectManager,"can_register_effect"), Callable(EffectManager,"location_option_origin_allowed"))
		var local = LocalBattleCommands.new(0, builder.ids, dispatcher, command_run)
		local.result.connect(reply)
		var request: int = local.submit("play_group", {"cards":[builder.ids.id_for(card)],"hidden":[false]})
		print("FORMAL_PLAY_GROUP_RECEIPT ", JSON.stringify(replies))
		if mode == "formal-submit":
			check(replies.size() == 1 and replies[0].request_id == request and replies[0].ok, "formal LocalBattleCommands play_group submits successfully")
		else:
			check(replies.size() == 1 and replies[0].request_id == request and not replies[0].ok, "formal local adapter currently denies absent upstream context")
			check(player.hand_cards == [card] and player.played_cards.is_empty() and player.magic.number == 8, "formal rejection has no play or payment")
			var result: Dictionary = dispatcher.dispatch(0,"play_group",{"cards":[builder.ids.id_for(card)],"hidden":[false]},builder.ids,command_run,context)
			print("EXPLICIT_DISPATCH_RECEIPT ",JSON.stringify(result))
			check(result.ok, "real play_group dispatcher with original action context accepted")
			check(RegularPlay.completed(0) and player.played_cards == [card] and player.hand_cards.is_empty(), "actual group reached completion and moved same card exactly once")
			check(player.magic.number == 7 and GameLog.query({"type":"play","actor":0},null).size() == 1 and GameLog.query({"type":"regular_play","actor":0},null).size() == 1, "real submit charged once and recorded completion receipt")
	else:
		var original_magic = player.magic
		player.magic = BaseNumber.new(8)
		check(query.payment_quote(0).is_empty() and not source.read_group_preview([card],[false]).preview.get("ok",false), "replacement magic identity rejects saved query without recapture")
		player.magic = original_magic
		var original_player: Dictionary = player
		GameData.player_data_library[0] = player.duplicate()
		check(query.payment_quote(0).is_empty() and not source.read_group_preview([card],[false]).preview.get("ok",false), "replacement member identity rejects saved query without recapture")
		GameData.player_data_library[0] = original_player
		check(source.read_group_preview([card],[false]).preview.get("can_submit", false), "restored original identities preserve original quote")
		var next_session: Dictionary = GameData.reset_game_session([0])
		check(next_session.ok and query.payment_quote(0).is_empty(), "new generation does not refresh old query origin")
		check(not source.read_group_preview([card],[false]).preview.get("ok",false), "delayed local source cannot cross session")
	print("RESULT ",JSON.stringify({"suite":"group-preview-origin","mode":mode,"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
