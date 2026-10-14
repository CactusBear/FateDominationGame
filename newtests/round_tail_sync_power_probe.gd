extends "res://newtests/b31_round_tail_probe_fixture.gd"

## :356 真实尾部重建 power 基线；从不直接调用 SyncPower。
func probe() -> void:
	await enter_action()
	if not failures.is_empty(): return
	var shown: BaseAttack = attack("B31明置威力5", 5, true)
	var hidden: BaseAttack = attack("B31暗置威力7", 7, true)
	var closed: BaseAttack = attack("B31关闭威力11", 11, true)
	var unchanged: BaseAttack = attack("B31零加成对照威力3", 3, true)
	var hand: Array = GetPlayerHandCards.new().exec(0)
	hand.append_array([shown, hidden])
	check(RegularPlay.submit_group(0, [shown, hidden], [false, true], false, fixture_context),
		"真实常规整组分别明置暗置残留攻击")
	await fixture_idle()
	check(await fixture_operation("add_attack", [closed, 0]) == true and await fixture_operation("add_attack", [unchanged, 1]) == true,
		"公开追加出牌建立关闭样本与零加成玩家对照")
	check(await fixture_operation("close_card", [closed, 0, fixture_context]) == true, "PRE 关闭样本原来源操作成功")
	check(CardCountsPower.new().exec(shown, 0) and not CardCountsPower.new().exec(hidden, 0)
		and not CardCountsPower.new().exec(closed, 0), "公开计威力查询区分明置暗置和关闭样本")
	var data: Dictionary = GameDataManager.get_player_data(0)
	var control_data: Dictionary = GameDataManager.get_player_data(1)
	var power: BaseNumber = data["power"]
	var control_power: BaseNumber = control_data["power"]
	var bonus: BaseNumber = data["total_power_bonus"]
	check(power.number == 5 and control_power.number == 3, "出牌翻面真实形成两玩家印刷威力基线5和3")
	await fixture_operation("edit_power", [null, BaseNumber.new(13), 0, fixture_context], false)
	# 外层清零另验，但它绝不代替 power 重建断言。
	bonus.set_num(BaseNumber.new(9))
	var before: int = power.number
	var before_round: int = GameProgress.current_round
	check(before == 18 and bonus.number == 9 and data["power"] == power, "公开EditPower叠加非卡牌13且不替换原数值对象")
	await get_tree().process_frame
	check(GameProgress.current_round == before_round and power.number == before
		and bonus.number == 9 and control_power.number == 3,
		"不走回合尾部对照保留非卡牌加成和原业务值")
	await GameProgress.end_round(fixture_context)
	check(GameProgress.current_round == before_round + 1
		and GameProgress.get_current_phase().get("name") == "prepare"
		and not EffectManager.is_waiting_for_choice(), "真实回合尾部进入下一准备阶段")
	var remaining: Array = GetPlayerPlayedCards.new().exec(0)
	check(remaining == [shown] and CardCountsPower.new().exec(shown, 0)
		and not CardCountsPower.new().exec(hidden, 0) and not CardCountsPower.new().exec(closed, 0),
		"尾部仅留明置残留原对象且暗置关闭牌均不计威力")
	check(power.number == 5, "尾部power精确重建为留场明置牌5并清除非卡牌13")
	check(power.number != before and before - power.number == 13,
		"power重建业务差值13区别于不推进对照")
	check(data["power"] == power and control_data["power"] == control_power,
		"尾部同步就地保留两玩家power数值对象identity")
	check(data["total_power_bonus"] == bonus and bonus.number == 0, "外层total_power_bonus独立清零且保留identity")
	check(GetPlayerPlayedCards.new().exec(1) == [unchanged]
		and CardCountsPower.new().exec(unchanged, 1) and control_power.number == 3,
		"无非卡牌加成玩家对照同一路径威力保持3且残留不换对象")
	print("OBSERVATION ", JSON.stringify({"before": before, "after": power.number,
		"expected_card_baseline": 5, "bonus_after": bonus.number, "control_after": control_power.number,
		"power_identity": data["power"] == power}))

func run() -> void:
	print("DIAGNOSTIC_USER_PATH ", OS.get_user_data_dir())
	if start(): await probe()
	report("round_tail_sync_power")
