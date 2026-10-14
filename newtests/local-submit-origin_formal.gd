extends "res://scripts/game_scene/battle_board_v2.gd"

# 继承生产场景，只通过生产 ready 构造命令适配器；不注入 context 或替换 dispatcher/run。
var origin_checks: int = 0
var origin_failures: Array = []
var origin_replies: Array = []
var origin_card: BaseSkill
var origin_context: SessionContext

func origin_check(ok: bool, label: String) -> void:
	origin_checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: origin_failures.append(label)

func _ready() -> void:
	origin_check(GameStart.game_start([0]), "real successful GameStart before production UI construction")
	origin_context = GameStart.startup_context()
	origin_check(SessionGeneration.validate_context(origin_context).get("ok", false), "successful startup saved original context")
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
	var cards: Array = LoadGame.load_skills([{"skill_name":"正式本地来源提交守卫", "skill_card_img":"", "attributes":[], "cost":{"number":1,"can_change":true,"is_pure_number":true}, "power":{"number":1,"can_change":true,"is_pure_number":true}, "ignore_limit":false, "effects":[]}], "", null, "skill", origin_context)
	origin_check(cards.size() == 1, "trusted runtime factory created legal ordinary skill")
	if cards.is_empty():
		origin_finish()
		return
	origin_card = cards[0]
	player.hand_cards.append(origin_card)
	super._ready()
	set_process(false)
	origin_check(_source_is_local and _battle_commands is LocalBattleCommands, "production ready constructed actual local command adapter")
	_battle_commands.result.connect(origin_reply)
	call_deferred("origin_run")

func origin_reply(request_id: int, ok: bool, reason: String) -> void:
	origin_replies.append({"request_id":request_id,"ok":ok,"reason":reason})

func origin_run() -> void:
	# 守卫前检精确回调形状，避免旧 ABI 触发引擎参数错误后被误当业务拒绝。
	var callback_arity_ok: bool = _run_battle_command.get_argument_count() == 3
	origin_check(callback_arity_ok, "production dispatcher callback ABI accepts original third context")
	if not callback_arity_ok:
		origin_finish()
		return
	var player: Dictionary = GameData.player_data_library[0]
	origin_check(not EffectManager.execution_context().get("ok", false), "ordinary UI submit has no verified effect frame")
	origin_check(RegularPlay.payment_quote(0).is_empty(), "bare quote stays fail closed without frame")
	_selected_cards.append(origin_card)
	var group: Dictionary = _read_group_preview()
	origin_check(group.get("preview", {}).get("can_submit", false), "same actual UI selected group can submit")
	origin_check(_can_confirm_held_cards(), "actual production UI confirmation gate allows legal selection")
	await get_tree().process_frame
	origin_check(is_same(GameStart.startup_context(), origin_context), "deferred UI retains successful startup original identity")
	var local = _battle_commands
	var args: Dictionary = {"cards":[_held_action_ids.id_for(origin_card)],"hidden":[false]}
	_ops.get_node("PlayButton").pressed.emit()
	print("FORMAL_PLAY_GROUP_RECEIPT ", JSON.stringify(origin_replies))
	origin_check(origin_replies.size() == 1 and origin_replies[0].ok and origin_replies[0].request_id == 1 and origin_replies[0].reason.is_empty(), "formal production UI play_group submits successfully")
	origin_check(RegularPlay.completed(0), "actual RegularPlay group completed")
	origin_check(player.played_cards.size() == 1 and is_same(player.played_cards[0], origin_card) and player.hand_cards.is_empty(), "same card moved from hand into played zone exactly once")
	origin_check(player.magic.number == 7, "formal UI charged original magic exactly once 8 to 7")
	origin_check(GameLog.query({"type":"play","actor":0},null).size() == 1 and GameLog.query({"type":"regular_play","actor":0},null).size() == 1, "actual play and regular_play facts each once")
	print("FORMAL_PLAY_GROUP_STATE ", JSON.stringify({"magic":player.magic.number,"hand":player.hand_cards.size(),"played":player.played_cards.size(),"completed":RegularPlay.completed(0),"play_facts":GameLog.query({"type":"play","actor":0},null).size(),"regular_play_facts":GameLog.query({"type":"regular_play","actor":0},null).size()}))
	local.submit("play_group", args)
	origin_check(origin_replies.size() == 2 and not origin_replies[1].ok and player.magic.number == 7 and player.played_cards == [origin_card], "repeat submission cannot charge or enter same card twice")
	var next_session: Dictionary = GameData.reset_game_session([0])
	origin_check(next_session.get("ok", false), "new session created for stale deferred adapter control")
	var next_player: Dictionary = GameData.player_data_library[0]
	var before_magic: Variant = next_player.magic.number
	var before_hand: Array = next_player.hand_cards.duplicate()
	var before_played: Array = next_player.played_cards.duplicate()
	var before_facts: Array = GameLog.query({},null)
	local.submit("play_group", args)
	origin_check(origin_replies.size() == 3 and not origin_replies[2].ok and origin_replies[2].reason == "对局请求来源无效", "old adapter retains old context and rejects across session")
	origin_check(next_player.magic.number == before_magic and next_player.hand_cards == before_hand and next_player.played_cards == before_played and GameLog.query({},null) == before_facts, "stale adapter rejection has no new session resource card or fact changes")
	origin_finish()

func origin_finish() -> void:
	print("RESULT ", JSON.stringify({"suite":"local-submit-origin-formal","checks":origin_checks,"failures":origin_failures}))
	get_tree().quit(0 if origin_failures.is_empty() else 1)
