extends Node

# A1-29 专项：来源事实与卡牌威力消费者必须承接显式/已验 context。
# 夹具只在真实当前会话中显式创建玩家；不向消费口补票、不使用 current_token 代替来源。
var checks:int = 0
var failures:Array = []
var context:SessionContext
var player_id:int

func _ready() -> void:
	call_deferred("run")

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok:
		failures.append(label)

func fresh() -> void:
	var lifecycle:Dictionary = GameData.reset_game_session([])
	check(lifecycle.get("ok", false), "fresh session starts")
	context = lifecycle.get("context")
	player_id = AddPlayer.new().exec(-1, [], {"player_name":"A1-29"}, context)
	check(player_id >= 0, "trusted fixture member created")
	GameLog.reset()

func card_in_play() -> BaseAttack:
	var card:BaseAttack = BaseAttack.new("A1-29 card", "", [], BaseNumber.new(0), BaseNumber.new(4))
	var player:Dictionary = GameDataManager.find_player_data(player_id)
	(player.get("played_cards") as Array).append(card)
	card._is_activating = true
	return card

func facts() -> Array:
	return GameLog.query({"type":"power_source", "actor":player_id}, null)

func legal_cases() -> void:
	fresh()
	var card:BaseAttack = card_in_play()
	PowerSources.record(player_id, "power", 2, null, context)
	check(facts().size() == 1, "explicit current record writes one fact")
	check(PowerSources.active_entries(player_id, context).size() == 1, "explicit current active query reads fact")
	check(PowerSources.active_entries(player_id).is_empty(), "no-frame active query fails closed")

	GameLog.reset()
	var before_card:int = card._power.number
	var before_player:int = GameDataManager.find_player_data(player_id).power.number
	EditCardPower.new().exec(card, BaseNumber.new(2), null, player_id, context)
	check(card._power.number == before_card + 2, "current card power edit changes card")
	check(GameDataManager.find_player_data(player_id).power.number == before_player + 2, "current counted card updates total power")
	check(facts().size() == 1 and facts()[0].data.field == "card_power", "current card edit records one card fact")
	check(PowerSources.active_entries(player_id, context).size() == 1, "current card fact remains queryable")

func rejection_cases() -> void:
	fresh()
	var card:BaseAttack = card_in_play()
	var before_card:int = card._power.number
	var before_player:int = GameDataManager.find_player_data(player_id).power.number
	var keys:Array = GameData.player_data_library.keys()
	EditCardPower.new().exec(card, BaseNumber.new(3), null, player_id)
	check(card._power.number == before_card and GameDataManager.find_player_data(player_id).power.number == before_player, "no-frame card edit refuses before write")
	check(facts().is_empty() and GameData.player_data_library.keys() == keys, "no-frame card edit leaves no fact or member mutation")

	PowerSources.record(player_id, "power", 3)
	check(facts().is_empty(), "no-frame record refuses before fact")
	check(PowerSources.active_entries(player_id).is_empty(), "no-frame active query refuses before log read")

	var old_context:SessionContext = context
	var old_card:BaseAttack = card
	var old_power:int = before_card
	fresh()
	var new_keys:Array = GameData.player_data_library.keys()
	EditCardPower.new().exec(old_card, BaseNumber.new(3), null, player_id, old_context)
	check(old_card._power.number == old_power, "stale explicit card context refuses before card write")
	check(facts().is_empty() and GameData.player_data_library.keys() == new_keys, "stale explicit card context leaves new session untouched")
	check(PowerSources.active_entries(player_id, old_context).is_empty(), "stale query context refuses before log read")
	PowerSources.record(player_id, "power", 3, null, old_context)
	check(facts().is_empty(), "stale record context refuses before fact")

	var unknown:int = 9515029
	var unknown_keys:Array = GameData.player_data_library.keys()
	var unknown_card:BaseAttack = BaseAttack.new("unknown", "", [], BaseNumber.new(0), BaseNumber.new(4))
	EditCardPower.new().exec(unknown_card, BaseNumber.new(2), null, unknown, context)
	PowerSources.record(unknown, "power", 2, null, context)
	check(unknown_card._power.number == 4, "unknown card owner refuses before card write")
	check(GameDataManager.find_player_data(unknown).is_empty() and GameData.player_data_library.keys() == unknown_keys, "unknown card owner does not create member")
	check(GameLog.query({"type":"power_source", "actor":unknown}, null).is_empty(), "unknown card owner creates no source fact")

func run() -> void:
	print("ENV ", JSON.stringify({"pid":OS.get_process_id(), "user":OS.get_user_data_dir(), "res":ProjectSettings.globalize_path("res://")}))
	legal_cases()
	rejection_cases()
	print("RESULT ", JSON.stringify({"suite":"A1-29-power-sources-origin", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
