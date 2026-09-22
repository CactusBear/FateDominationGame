extends "res://tests/card_effect_runtime_test.gd"
# 复用已有 setup/place/check；不调用其手工登记来源的辅助函数。
# 来源只经 deal_player_cards -> RegularPlay -> BattleResolver。
# 本套件是待运行 RED：不能以手工登记/修改激活状态修补生产链路。

func run() -> void:
	test_fresh_deal_loss_and_removed_copy()
	test_unplayed_dealt_copies()
	test_returned_copy_stays_idle_and_keeps_bonus()
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func lifecycle_setup() -> Array:
	super.setup(3, int(GameData.magic_limit.number))
	SituationResolver.new().clear_all()
	var servant = named(GameData.loaded_servants, "heracles")
	check(servant != null, "fixture loads Heracles")
	if servant == null:
		return []
	var d:Dictionary = GameDataManager.get_player_data(0)
	d.servant = servant
	GameProgress.deal_player_cards(0)
	var copies:Array = d.servant_skills.duplicate()
	check(copies.size() == 3, "real deal supplies three Twelve Labors instances")
	if copies.size() != 3:
		return []
	for card in copies:
		check(card is BaseSkill and card._name == "twelve_labors", "dealt card is Twelve Labors")
		check(not servant._specials.SKILLS.has(card), "dealt card is not a template")
		check(card._cost.number == 1 and card._power.number == 5, "printed cost one and power five")
	check(copies[0] != copies[1] and copies[1] != copies[2] and copies[0] != copies[2], "three distinct dealt copies")
	for id in [1, 2]:
		GameDataManager.get_player_data(id).score.number = 10
	enter_action_round(1)
	return copies

func enter_action_round(round_number:int) -> void:
	GameProgress.current_round = round_number
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	GameLog.set_context(round_number, "action")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX])
	for id in range(3):
		var d:Dictionary = GameDataManager.get_player_data(id)
		# 夹具每回合恢复正常上限魔力，不启用费用豁免或降低技能区门槛。
		d.magic.number = GameData.magic_limit.number
		check(place(MapData.miyama, id, id), "fixture places participant %d in round %d" % [id, round_number])

func next_action_round() -> void:
	# 复用 end_round 的收牌/威力同步原语，避免 start_round 随机抽局势干扰专项。
	# 不清 EffectManager/GameLog，保留真实回收登记与移除后残留效果。
	for id in range(3):
		DiscardPlayedCards.new().exec(id)
		SyncPower.new().exec(id)
		RemoveFromBoard.new().exec(id)
		GameDataManager.get_player_data(id).total_power_bonus.number = 0
	DefeatBuff.clear_all()
	enter_action_round(GameProgress.current_round + 1)

func play_pair(skill = null) -> bool:
	var d:Dictionary = GameDataManager.get_player_data(0)
	var filler := BaseAttack.new("lifecycle_filler", "", [], BaseNumber.new(0), BaseNumber.new(0))
	d.hand_cards.append(filler)
	var first = skill
	if first == null:
		first = BaseAttack.new("lifecycle_plain", "", [], BaseNumber.new(0), BaseNumber.new(0))
		d.hand_cards.append(first)
	var cards:Array = [first, filler]
	check(d.magic.number >= GameData.skill_zone_magic_limit.number, "round starts with enough magic for legal skill-zone play")
	var legal:bool = RegularPlay.can_submit_group(0, cards, [false, false])
	check(legal, "regular group is legal before submission")
	if not legal:
		return false
	var before = d.magic.number
	var expected_cost:float = RegularPlay.cost(first, d) + RegularPlay.cost(filler, d)
	var submitted:bool = RegularPlay.submit_group(0, cards, [false, false])
	check(submitted, "real regular group submits")
	check(d.magic.number == before - expected_cost, "regular play actually pays card costs")
	check(RegularPlay.completed(0) and d.played_cards.has(first), "regular group completion and live source are recorded")
	return submitted

func resolve_battle(owner_wins:bool = false) -> Dictionary:
	GameProgress.current_phase_index = 3
	GameLog.set_context(GameProgress.current_round, "battle")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE, TimePoints.NON_CLIMAX])
	# 确定性对手威力；不手写胜败事实或直接派 BATTLE_LOSE。
	GameDataManager.get_player_data(0).total_power_bonus.number = 200 if owner_wins else 0
	for id in [1, 2]:
		GameDataManager.get_player_data(id).power.number = 100
	var result:Dictionary = BattleResolver.new().exec([0, 1, 2])
	var winners:Array = result.get("winners_by_area", {}).get(MapData.miyama._area_name, [])
	check(winners == ([0] if owner_wins else [1, 2]), "BattleResolver produces the intended winners")
	return result

func check_winner_penalty(expected:int) -> void:
	for id in [1, 2]:
		var drops:Array = GameLog.query({"type":"score_decrease", "actor":id}, 0)
		check(drops.size() == expected, "winner %d receives exactly %d penalty entries" % [id, expected])
		if expected == 1 and drops.size() == 1:
			check(drops[0].data.delta == -3, "each winner loses exactly three score")

func test_fresh_deal_loss_and_removed_copy() -> void:
	var copies:Array = lifecycle_setup()
	if copies.is_empty() or not play_pair(copies[0]):
		return
	var d:Dictionary = GameDataManager.get_player_data(0)
	resolve_battle()
	check(d.score.number == 3, "freshly dealt played copy grants exactly three score")
	check_winner_penalty(1)
	check(d.out_of_game.skills.has(copies[0]) and not d.played_cards.has(copies[0]), "losing source moves out of game")
	check(copies[0]._power.number == 5 and not copies[0].has_modifications(), "source does not boost itself")
	for card in [copies[1], copies[2]]:
		check(d.servant_skills.has(card) and not d.out_of_game.skills.has(card), "unplayed copy is not consumed by another copy's loss")
		check(card._power.number == 8, "other dealt copy gains permanent three power")
	var score_before = d.score.number
	var powers_before:Array = [copies[1]._power.number, copies[2]._power.number]
	next_action_round()
	check(d.out_of_game.skills.has(copies[0]), "removed source stays removed across cleanup")
	check(not RegularPlay.candidates(0).has(copies[0]), "removed source cannot be played again")
	if not play_pair():
		return
	resolve_battle()
	check(d.score.number == score_before, "removed source and idle copies do not trigger on a later loss")
	check_winner_penalty(0)
	check([copies[1]._power.number, copies[2]._power.number] == powers_before, "later loss without Twelve Labors gives no additional power")

func test_unplayed_dealt_copies() -> void:
	var copies:Array = lifecycle_setup()
	if copies.is_empty() or not play_pair():
		return
	resolve_battle()
	var d:Dictionary = GameDataManager.get_player_data(0)
	check(d.score.number == 0 and d.out_of_game.skills.is_empty(), "never-played copies grant no score and are not removed")
	check_winner_penalty(0)
	for card in copies:
		check(d.servant_skills.has(card) and card._power.number == 5 and not card.has_modifications(), "never-played copy remains unchanged")

func test_returned_copy_stays_idle_and_keeps_bonus() -> void:
	var copies:Array = lifecycle_setup()
	if copies.is_empty() or not play_pair(copies[0]):
		return
	var d:Dictionary = GameDataManager.get_player_data(0)
	resolve_battle(true)
	next_action_round()
	var returned = copies[0]
	check(d.side.skills.has(returned) and not returned._is_activating, "winning copy really returns inactive to side.skills")
	var history_before:Array = returned.get_modification_details().duplicate(true)
	var score_before = d.score.number
	if not play_pair(copies[1]):
		return
	resolve_battle()
	check(d.score.number == score_before + 3, "only the played copy triggers, not the returned idle copy")
	check_winner_penalty(1)
	check(d.side.skills.has(returned) and not d.out_of_game.skills.has(returned), "returned idle copy is not consumed")
	check(d.out_of_game.skills.has(copies[1]), "second round played source is consumed")
	check(returned._power.number == 8, "returned side.skills copy receives permanent plus three")
	check(copies[2]._power.number == 8, "still-unplayed copy receives the same single bonus")
	var history:Array = returned.get_modification_details().duplicate(true)
	check(history.size() == history_before.size() + 1, "returned copy records exactly one power modification")
	if history.size() == history_before.size() + 1:
		check(history.back().get("type") == "power", "returned copy history identifies a power change")
		history.pop_back()
		check(history == history_before, "adding a power history entry preserves prior history")
	var saved_history:Array = returned.get_modification_details().duplicate(true)
	next_action_round()
	check(returned._power.number == 8 and returned.get_modification_details() == saved_history, "bonus and history survive the next round")
	# 即使前面的规则断言失败也继续尝试真实出牌；非法候选会明确报夹具/规则失败而非崩溃。
	if not play_pair(returned):
		return
	check(d.power.number == 8, "replayed returned copy contributes its increased power")
	check(not d.side.skills.has(returned), "replay removes the returned copy from side.skills")
	resolve_battle(true)
	next_action_round()
	check(d.side.skills.has(returned) and returned._power.number == 8, "replayed copy returns again without losing permanent bonus")
	check(returned.get_modification_details() == saved_history, "replay and cleanup neither erase nor duplicate history")
