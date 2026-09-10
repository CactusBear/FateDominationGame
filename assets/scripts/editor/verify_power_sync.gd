extends Node

#验证合计威力在卡牌状态变化时实时同步，以及回合结束基线重建
func _ready():
	await get_tree().process_frame

	print("=== 开始验证合计威力实时同步 ===")

	var id = 0
	var pl = GameDataManager.get_player_data(id)
	var played = pl["played_cards"] as Array
	var discard = pl["discard"] as Array
	var skill_zone = pl["side"]["skills"] as Array
	played.clear(); discard.clear(); skill_zone.clear()
	var power = pl["power"] as BaseNumber
	power.set_num(BaseNumber.new(0))

	#明置攻击牌进场，手工模拟PlayAttack的加威力
	var atk = BaseAttack.new("atk5", "", ["strength"], BaseNumber.new(0), BaseNumber.new(5))
	played.append(atk)
	power.add(atk._power)
	print("打出威力5的攻击牌后 power=", power.number)
	assert(power.number == 5)

	#关闭该牌 -> 转暗置 -> 威力应实时扣回
	CloseCard.new().exec(atk, id)
	print("关闭后 concealed=", atk._is_concealed, " power=", power.number)
	assert(atk._is_concealed, "攻击牌关闭后应暗置")
	assert(power.number == 0, "暗置牌不计合计威力，power应扣回0")

	#重新明置 -> 威力应加回
	SetCardConcealed.new().exec(atk, false, id)
	print("重新明置后 power=", power.number)
	assert(power.number == 5, "明置后应重新计入威力")

	#重复设置同一状态不应重复增减
	SetCardConcealed.new().exec(atk, false, id)
	assert(power.number == 5, "状态未变化时不应重复加威力")

	#不在场上的牌翻面不影响power
	var hand_card = BaseAttack.new("in_hand", "", [], BaseNumber.new(0), BaseNumber.new(9))
	SetCardConcealed.new().exec(hand_card, true, id)
	assert(power.number == 5, "非场上牌翻面不应影响power")
	print("非场上牌翻面后 power=", power.number)

	#技能牌进场并关闭 -> 离场，威力应扣回
	var skill = BaseSkill.new("skill3", "", [], BaseNumber.new(0), BaseNumber.new(3))
	played.append(skill)
	power.add(skill._power)
	print("技能牌进场后 power=", power.number)
	assert(power.number == 8)
	CloseCard.new().exec(skill, id)
	print("技能牌关闭后 in_skills=", skill_zone.has(skill), " power=", power.number)
	assert(skill_zone.has(skill), "技能牌关闭应回技能区")
	assert(power.number == 5, "技能牌离场应扣回其威力")

	#回合结束基线重建：残留明置牌留场继续提供威力，非残留牌清掉
	var residue = BaseAttack.new("residue4", "", [], BaseNumber.new(0), BaseNumber.new(4))
	residue._effects = [BaseEffect.new("residue_test", [], -1, false, true)]
	played.append(residue)
	power.add(residue._power)
	#再加一份非卡牌来源加成，回合结束应被丢弃
	EditPower.new().exec(null, BaseNumber.new(100), id)
	print("回合结束前 power=", power.number, " played=", played.map(func(c): return c._name))
	assert(power.number == 109, "5(暗置前的atk) + 4(残留) + 100(额外加成)")

	DiscardPlayedCards.new().exec(id)
	SyncPower.new().exec(id)
	print("回合结束后 played=", played.map(func(c): return c._name))
	print("回合结束后 power=", power.number)
	assert(played.size() == 1 and played[0] == residue, "只剩未关闭的残留牌留场")
	assert(power.number == 4, "基线应为留场残留牌威力4，非卡牌加成被丢弃")

	print("=== 合计威力实时同步验证通过! ===")
	get_tree().quit()
