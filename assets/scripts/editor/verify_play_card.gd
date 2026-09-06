extends Node

#验证：打出攻击卡时派发 self_played_card，效果池检查到 Caliburn 被动（力量/敏捷卡威力+2）并自动结算
func _ready():
	await get_tree().process_frame

	print("=== 开始验证打卡时点派发与 Caliburn passive 联动 ===")

	var test_player_id = 0
	var pl_data = GameDataManager.get_player_data(test_player_id)
	pl_data["magic"].set_num(BaseNumber.new(10)) # 充足魔力

	# 找到士郎并取出誓约胜利之剑 (caliburn)
	var master = null
	for m in GameData.loaded_masters:
		if m._name == "emiya_shirou":
			master = m
	var caliburn:BaseSkill = master._upgrade_skill[0]
	print("升级技能: ", caliburn._name, " 初始力量: ", caliburn._power.number)

	# 把 caliburn 的效果登记进效果池，归属测试玩家
	EffectManager.register_effects(caliburn._effects, test_player_id)
	print("效果池数量: ", EffectManager.effect_pool.size())

	# 构造一张力量属性的测试攻击卡
	var atk = BaseAttack.new("test_slash", "", ["strength"], BaseNumber.new(1), BaseNumber.new(3))
	print("测试攻击卡初始威力: ", atk._power.number)

	# 执行打出攻击卡 PlayAttack。它内部派发时点，EffectManager 自动检查并结算
	PlayAttack.new().exec(atk, test_player_id)

	print("打出攻击卡后，检查 played_cards 数量: ", pl_data["played_cards"].size())
	print("本时点已结算效果数: ", EffectManager.resolved_effects.size())
	print("是否有效果在等待玩家决定: ", EffectManager.is_waiting_for_choice())

	print("结算 Caliburn passive 后，测试攻击卡威力: ", atk._power.number)
	print("玩家当前总威力: ", pl_data["power"].number)

	assert(atk._power.number == 5, "力量攻击卡威力应由 3 增至 5 (+2)")
	assert(pl_data["power"].number == 5, "玩家当前总力量应同步增至 5")

	print("=== 打牌时点与 Caliburn passive 联动验证通过! ===")
	get_tree().quit()
