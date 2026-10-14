extends "res://tests/twelve_labors_lifecycle_test.gd"
# 只读来源/报价拒绝守卫；不手工激活、不登记假能力、不放宽支付规则。

func run() -> void:
	var copies:Array = lifecycle_setup()
	if copies.size() != 3:
		finish_origin_guard()
		return
	var old:SessionContext = fixture_context
	var d:Dictionary = GameDataManager.get_player_data(0)
	for card in copies:
		check(RegisterObjectEffects.source_is_current(old, card), "dealt copy inherits original runtime token")
	var filler:BaseAttack = lifecycle_attack("origin_guard_filler")
	if filler == null:
		finish_origin_guard()
		return
	d.hand_cards.append(filler)
	var cards:Array = [copies[0], filler]
	var payment:Dictionary = RegularPlay.payment_quote(0, old)
	check(RegularPlay.payment_quote_is_current(0, payment), "explicit original envelope remains current")
	check(RegularPlay.can_submit_group(0, cards, [false, false], false, payment), "explicit original envelope permits legal pair")
	var magic_before = d.magic.number
	var play_before:Array = GameLog.query({"type":"play", "actor":0}, null)
	check(RegularPlay.payment_quote(0).is_empty(), "bare quote does not acquire current ticket")
	check(not RegularPlay.can_submit_group(0, cards, [false, false]), "bare quote never automatically permits group")
	check(d.magic.number == magic_before and GameLog.query({"type":"play", "actor":0}, null) == play_before,
		"query rejection changes neither payment nor play facts")

	var next_copies:Array = lifecycle_setup()
	check(next_copies.size() == 3 and fixture_context != old, "new fixture retains a different original lifecycle handle")
	if next_copies.size() != 3:
		finish_origin_guard()
		return
	var current:Dictionary = GameDataManager.get_player_data(0)
	var held:Array = current.servant_skills
	var current_magic = current.magic.number
	check(not SituationResolver.new().clear_all(old).ok, "old cleanup source is rejected")
	check(not GameProgress.deal_player_cards(0, old).ok, "old deal source is rejected without replacement")
	check(is_same(current.servant_skills, held), "rejected deal preserves current card container identity")
	check(not MasterManager.prepare_role_runtime(named(GameData.loaded_servants, "heracles"), old).ok,
		"S0 does not wash old source into new runtime")
	check(RegularPlay.payment_quote(0, old).is_empty(), "old context cannot create new envelope")
	check(not RegularPlay.payment_quote_is_current(0, payment), "saved old envelope remains invalid")
	var next_filler:BaseAttack = lifecycle_attack("origin_guard_current_filler")
	if next_filler == null:
		finish_origin_guard()
		return
	current.hand_cards.append(next_filler)
	var current_pair:Array = [next_copies[0], next_filler]
	var current_payment:Dictionary = RegularPlay.payment_quote(0, fixture_context)
	check(RegularPlay.can_submit_group(0, current_pair, [false, false], false, current_payment),
		"stale submission negative uses a currently legal pair")
	check(not RegularPlay.submit_group(0, current_pair, [false, false], false, old), "old source cannot submit into new lifecycle")
	var battle:Dictionary = BattleResolver.new(old).exec([0, 1, 2])
	check(battle.get("winners_by_area", {}).is_empty(), "explicit old battle source is rejected")
	check(current.magic.number == current_magic and current.played_cards.is_empty() and current.score.number == 0,
		"stale consumers leave current resources and played zone unchanged")
	for card in next_copies:
		check(card._power.number == 5 and not card.has_modifications(), "stale consumers leave current copies unmodified")
	finish_origin_guard()

func finish_origin_guard() -> void:
	print("RESULT ", JSON.stringify({"checks":checks, "failures":failures, "suite":"s1-twelve-labors-origin"}))
	get_tree().quit(0 if failures.is_empty() else 1)
