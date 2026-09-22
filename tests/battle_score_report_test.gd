extends Node
# RED：战报实得应等于本场结算期间每名参战者的净变化，而非基础奖池分配。
# 令咒必须走真实 manual -> option -> pay -> resolve；不直接伪造延迟奖励。
# 本轮采用现有一次性奖励口径，不修改令咒数据、结算器或 UI。
var failures:Array = []
var checks:int = 0
var keepalive:Array = []

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	_test_without_command()
	await _test_competition_only_pool()
	_test_single_reward()
	_test_stacked_rewards_are_once_only()
	_test_command_user_loses()
	_test_draw_keeps_personal_reward_out_of_shared_pool()
	_test_loser_penalty_is_reported()
	_test_prior_score_is_not_battle_income()
	print("RESULT checks=", checks, " failures=", failures)
	var file := FileAccess.open("res://battle_score_report_test_result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"checks": checks, "failures": failures}))
		file.close()
	get_tree().quit(0 if failures.is_empty() else 1)

func _setup() -> void:
	EffectManager.reset_runtime()
	GameLog.reset()
	GameLog.set_context(1, "action")
	GameData.player_data_library.clear()
	GameData.player_id = 0
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	for id in range(3):
		var data := GameData.new_player_data()
		data.is_out = false
		data.magic.number = 20
		data.score.number = 10
		data.power.number = 0
		data.total_power_bonus.number = 0
		data.command_spell_count.number = 3
		GameData.player_data_library[id] = data
	for area in MapData.areas:
		area._events.clear()
		for loc in area._locations:
			loc._players.clear()
	TimePointChecker.set_phase_time_points([
		TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX])
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX], 0)
	# 固定的无效果事件只提供基础奖池，不引入随机牌效或额外确认窗口。
	var event := BaseEvent.new("report_score_fixture", "", BaseNumber.new(2))
	keepalive.append(event)
	AddMapAreaEvents.new().exec(MapData.miyama, event)
	for id in [0, 1]:
		var loc:BaseLocation = MapData.miyama._locations[id]
		check(SetLocation.new().exec(loc, id, false, true), "fixture places participant %d" % id)
		check(GameDataManager.get_player_data(id).location == loc and loc._players.has(id),
			"fixture location links agree for participant %d" % id)
		check(GetEffectiveLocationBenefit.new().exec(id) == 0,
			"effect placement grants no deployment benefit for participant %d" % id)
	GameDataManager.get_player_data(0).power.number = 20

func _command_effect() -> BaseEffect:
	for template in LoadCommandSpell.command_spells.values():
		if template != null and template._name == "normal_command_spell":
			var card = CloneObject.new().exec(template)
			if card == null:
				return null
			keepalive.append(card)
			var effect:BaseEffect = card._effects[0]
			EffectManager.register_effect(effect, 0)
			return effect
	return null

func _use_commands(count:int) -> void:
	var effect := _command_effect()
	check(effect != null, "normal command spell clone exists")
	if effect == null:
		return
	var score_before:int = GameDataManager.get_player_data(0).score.number
	for index in range(count):
		# 两次请求之间不重置管线、不重派阶段，才能覆盖同回合连续令咒。
		var accepted:bool = EffectManager.request_manual_activation(effect, 0)
		check(accepted, "manual request %d accepted" % (index + 1))
		if not accepted:
			return
		check(EffectManager.submit_option_choice(effect, [1]),
			"power and delayed score option %d submitted" % (index + 1))
		check(EffectManager.waiting_effect == null, "command choice resolves without pending input")
		check(GameDataManager.get_player_data(0).command_spell_count.number == 3 - index - 1,
			"command %d pays exactly one seal" % (index + 1))
	check(GameDataManager.get_player_data(0).total_power_bonus.number == count * 2,
		"each submitted command grants its immediate power")
	check(GameDataManager.get_player_data(0).score.number == score_before,
		"commands do not award score before the real win")

func _base_pool() -> int:
	return 2 + int(MapData.miyama._score.number)

func _battle(label:String, expected_winners:Array, expected_deltas:Dictionary) -> Dictionary:
	# 快照必须紧贴本次结算入口，不能取本回合日志总和或把 score 的活对象当快照。
	var before:Dictionary = {}
	for id in [0, 1, 2]:
		before[id] = int(GameDataManager.get_player_data(id).score.number)
	GameProgress.current_phase_index = 3
	GameLog.set_context(1, "battle")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE])
	var result:Dictionary = BattleResolver.new().exec([0, 1, 2])
	var detail:Dictionary = result.details_by_area.get(MapData.miyama._area_name, {})
	check(not detail.is_empty(), label + ": real battle produces area details")
	check(detail.get("players", []) == [0, 1], label + ": both participants are recorded")
	check(detail.get("winners", []) == expected_winners, label + ": real winners match fixture")
	check(detail.get("is_draw", false) == (expected_winners.size() > 1), label + ": draw flag matches")
	check(detail.get("event_score", -1) == 2, label + ": event score remains the printed pool")
	check(detail.get("competition_score", -1) == MapData.miyama._score.number,
		label + ": competition score remains the area pool")
	check(detail.get("total_score", -1) == _base_pool(),
		label + ": personal rewards and penalties never change total_score")
	var gained:Dictionary = detail.get("score_gained", {})
	for id in [0, 1]:
		var actual:int = int(GameDataManager.get_player_data(id).score.number) - int(before[id])
		check(actual == int(expected_deltas[id]),
			"%s: participant %d actual delta expected=%d got=%d" % [label, id, expected_deltas[id], actual])
		# 不用 get(id, 0)：零收益也要明确记录，防止漏掉败者被默认值掩盖。
		check(gained.has(id), "%s: score_gained includes participant %d" % [label, id])
		check(gained.get(id) == actual,
			"%s: participant %d reported=%s actual=%d" % [label, id, str(gained.get(id)), actual])
	check(gained.size() == 2 and not gained.has(2), label + ": no nonparticipant income in report")
	check(GameDataManager.get_player_data(2).score.number == before[2],
		label + ": nonparticipant score unchanged")
	check(EffectManager.waiting_effect == null, label + ": synchronous score effects have finished")
	return detail

func _test_without_command() -> void:
	_setup()
	_battle("no command", [0], {0: _base_pool(), 1: 0})


func _test_competition_only_pool() -> void:
	var ui = load("res://assets/scenes/game_scene/tactical_board_ui.tscn").instantiate()
	get_tree().root.add_child(ui)
	ui.set_process(false)
	_setup()
	MapData.miyama._events.clear()
	var before_winner:int = GameDataManager.get_player_data(0).score.number
	var before_loser:int = GameDataManager.get_player_data(1).score.number
	var result:Dictionary = BattleResolver.new().exec([0, 1, 2])
	var detail:Dictionary = result.details_by_area.get(MapData.miyama._area_name, {})
	var competition:int = 2
	check(int(MapData.miyama._score.number) == competition,
		"miyama keeps its printed two-point competition reward")
	check(GameDataManager.get_player_data(0).score.number - before_winner == competition,
		"competition-only battle gives the printed competition score to the winner")
	check(GameDataManager.get_player_data(1).score.number == before_loser,
		"competition-only battle gives nothing to the loser")
	check(int(detail.get("event_score", -1)) == 0 and int(detail.get("competition_score", -1)) == competition,
		"competition-only report separates the competition pool")
	var score_logs:Array = GameLog.query({"type":"score_add", "actor":0}, null)
	check(score_logs.size() == 1 and int(score_logs[0].data.get("delta", -1)) == competition,
		"competition score is recorded as a winner resource fact")
	ui._local_player_id = 0
	ui.refresh_all_ui()
	await get_tree().process_frame
	check(ui.score_text_label != null and ui.score_text_label.text.contains(str(before_winner + competition)),
		"competition score is visible in the winner's live score label")
	ui.queue_free()

func _test_single_reward() -> void:
	_setup()
	_use_commands(1)
	var detail := _battle("single reward", [0], {0: _base_pool() + 2, 1: 0})
	# 只调用现有排版方法，不入树、不启动 UI，也不自行补写 report 数据。
	var ui = load("res://assets/scripts/game_scene/tactical_board_ui.gd").new()
	var row:Control = ui._build_battle_report_area_row(MapData.miyama._area_name, detail)
	var text := _label_text(row)
	var shown_name:String = ui._player_shown_name_by_id(0)
	check(text.contains("%s +%d" % [shown_name, _base_pool() + 2]),
		"existing battle report row displays actual score including command reward")
	row.free()
	ui.free()

func _test_stacked_rewards_are_once_only() -> void:
	_setup()
	_use_commands(2)
	var first := _battle("two commands", [0], {0: _base_pool() + 4, 1: 0})
	# 沿用同一局同一回合，无再次发动：一次性奖励不得在后续胜场重复计入。
	_battle("later win without new command", [0], {0: _base_pool(), 1: 0})
	var gained:Dictionary = first.get("score_gained", {})
	check(gained.get(0) == _base_pool() + 4,
		"later settlement does not overwrite previous report income")

func _test_command_user_loses() -> void:
	_setup()
	_use_commands(1)
	GameDataManager.get_player_data(1).power.number = 40
	_battle("command user loses", [1], {0: 0, 1: _base_pool()})

func _test_draw_keeps_personal_reward_out_of_shared_pool() -> void:
	_setup()
	_use_commands(1)
	GameDataManager.get_player_data(1).power.number = 22
	check(GetPlayerTotalPower.new().exec(0) == GetPlayerTotalPower.new().exec(1),
		"draw fixture has equal effective power after command bonus")
	var split:int = ceili(float(_base_pool()) / 2.0)
	_battle("draw with one command user", [0, 1], {0: split + 2, 1: split})

func _test_loser_penalty_is_reported() -> void:
	_setup()
	_use_commands(1)
	# 测试声明一条强制败北扣分效果，交给真实效果池和败北时点执行。
	# 它不是手工修改结算后分数；用来防止实现仅给胜者补令咒常量。
	var penalty := BaseEffect.new("report_loser_penalty", [TimePoints.SELF_BATTLE_LOSE], 0, true, false)
	penalty._need_activate = false
	penalty._remove_after_trigger = true
	penalty._funcs = LoadHelper.load_funcs([{
		"func_name": "edit_score", "parameters": [null, BaseNumber.new(-3), -1], "var_index": -1
	}], penalty)
	keepalive.append(penalty)
	EffectManager.register_effect(penalty, 1)
	_battle("winner reward and loser penalty", [0], {0: _base_pool() + 2, 1: -3})

func _test_prior_score_is_not_battle_income() -> void:
	_setup()
	_use_commands(1)
	# 同一回合、甚至同一 battle 阶段，但在 resolver 调用之外获得的战果不属于本场。
	GameProgress.current_phase_index = 3
	GameLog.set_context(1, "battle")
	for id in [0, 1, 2]:
		EditScore.new().exec(null, BaseNumber.new(11 + id), id)
		check(GameDataManager.get_player_data(id).score.number == 21 + id,
			"prior unrelated gain is present for player %d" % id)
	_battle("prior same-round income excluded", [0], {0: _base_pool() + 2, 1: 0})

func _label_text(node:Node) -> String:
	var text:String = node.text if node is Label else ""
	for child in node.get_children():
		text += "\n" + _label_text(child)
	return text
