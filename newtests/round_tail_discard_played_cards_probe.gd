extends "res://newtests/b31_round_tail_probe_fixture.gd"

## :353 真实 end_round 的牌区行为；从不直接调用 DiscardPlayedCards。
func probe() -> void:
	await enter_action()
	if not failures.is_empty(): return
	var ordinary: BaseAttack = attack("B31普通攻击", 4)
	var returning: BaseSkill = skill("B31回区技能", 2)
	var persistent: BaseAttack = attack("B31明置残留", 5, true)
	var hand: Array = GetPlayerHandCards.new().exec(0)
	var played: Array = GetPlayerPlayedCards.new().exec(0)
	var discard: Array = GetPlayerDiscard.new().exec(0)
	var deck: Array = GetPlayerDeck.new().exec(0)
	var skills: Array = GetPlSkillsSide.new().exec(0)
	# 只经公开数组/技能入区入口构造来源，整组出牌真实消费来源牌。
	hand.append(ordinary)
	await fixture_operation("add_skill_to_skill_zone", [returning, 0])
	check(RegularPlay.submit_group(0, [ordinary, returning], [false, false], false, fixture_context),
		"真实常规整组出牌普通攻击和技能")
	await fixture_idle()
	check(await fixture_operation("add_attack", [persistent, 0]) == true, "公开追加出牌建立明置残留")
	check(played == [ordinary, returning, persistent] and not hand.has(ordinary)
		and not skills.has(returning) and not discard.has(ordinary), "原对象真实离开来源区并进入混合出牌区")
	check(not RegularPlay.candidates(0).has(returning) and CardCountsPower.new().exec(persistent, 0),
		"已出技能不再候选且明置残留真实计威力")
	var before_played: Array = played.duplicate()
	var before_discard: Array = discard.duplicate()
	var before_skills: Array = skills.duplicate()
	var before_round: int = GameProgress.current_round
	var next_draw_count: int = maxi(0, GameData.player_hand_limit(0).number - hand.size())
	check(deck.size() >= next_draw_count and not deck.has(ordinary), "下回合牌堆足以补牌无需洗回目标弃牌")
	await get_tree().process_frame
	check(GameProgress.current_round == before_round and played == before_played
		and discard == before_discard and skills == before_skills,
		"不走回合尾部对照牌区均保持不变")
	await GameProgress.end_round(fixture_context)
	check(GameProgress.current_round == before_round + 1
		and GameProgress.get_current_phase().get("name") == "prepare"
		and not EffectManager.is_waiting_for_choice(), "真实回合尾部结束并进入下一准备阶段")
	check(not played.has(ordinary) and discard.has(ordinary) and not hand.has(ordinary)
		and not deck.has(ordinary), "尾部普通攻击原对象离开出牌区且确实进入原玩家弃牌堆")
	check(discard.size() == before_discard.size() + 1 and discard[0] == ordinary,
		"弃牌计数净增一且顶部身份为普通攻击原对象")
	check(not played.has(returning) and skills.has(returning) and not discard.has(returning)
		and skills.size() == before_skills.size() + 1, "尾部技能原对象回技能区而非弃牌堆")
	# 候选查询排除激活牌；重新成为候选证明停止激活，不读取私有标志。
	check(RegularPlay.candidates(0).has(returning), "回区技能停止激活并重新成为公开出牌候选")
	check(played == [persistent] and CardCountsPower.new().exec(persistent, 0),
		"明置残留对照同一对象继续留场计威力")
	check(played.size() == before_played.size() - 2 and played != before_played
		and discard != before_discard, "真实尾部回收差值区别于不推进对照")
	check(not GetPlayerDiscard.new().exec(1).has(ordinary)
		and not GetPlayerPlayedCards.new().exec(1).has(returning)
		and not GetPlSkillsSide.new().exec(1).has(returning), "回收卡牌不串到另一玩家牌区")
	print("OBSERVATION ", JSON.stringify({"played_before": before_played.size(), "played_after": played.size(),
		"discard_delta": discard.size() - before_discard.size(), "skill_delta": skills.size() - before_skills.size()}))

func run() -> void:
	print("DIAGNOSTIC_USER_PATH ", OS.get_user_data_dir())
	if start(): await probe()
	report("round_tail_discard_played_cards")
