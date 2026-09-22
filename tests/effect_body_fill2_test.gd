extends Node
# 「移动至除魔术工房外的任意地点」（库丘林）与「坐骑召唤」（美杜莎）的效果体回归。
# 两条原先都是 do_nothing，本轮按卡面补全，顺带补了两项通用声明：
#   select_location.forbidden_target_areas —— 目标区域的排除（卡面「除…外的任意地点」）
#   select_cards.max_power               —— 候选的印刷威力上限（卡面「基本威力为3或更低」）
# 两者都只在数据声明时才生效，未声明的既有卡行为不变。
var failures:Array=[]
var checks:int=0

func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)

func _ready(): call_deferred("run")

func named(arr:Array, key:String):
	for o in arr:
		if o != null and str(o._name) == key:
			return o
	return null

## 按效果名全库查找技能牌并登记（不写死牌名）
func register_skill_by_effect(effect_key:String, player_id:int) -> BaseEffect:
	var holders:Array = []
	holders.append_array(GameData.loaded_servants)
	holders.append_array(GameData.loaded_masters)
	for holder in holders:
		if holder == null:
			continue
		for sk in holder._specials.get("SKILLS", []):
			if sk == null:
				continue
			var has_it:bool = false
			for e in sk._effects:
				if e != null and str(e._name) == effect_key:
					has_it = true
					break
			if !has_it:
				continue
			var cloned = CloneObject.new().exec(sk)
			if cloned == null:
				continue
			if cloned is BaseHandCard:
				cloned._is_activating = true
			GameData.player_data_library[player_id].servant_skills.append(cloned)
			for e in cloned._effects:
				EffectManager.register_effect(e, player_id)
			for e in cloned._effects:
				if e != null and str(e._name) == effect_key:
					return e
	return null

func setup() -> void:
	EffectManager.reset_runtime(); GameLog.reset(); GameLog.set_context(1,"action")
	GameData.player_data_library.clear()
	for i in range(3):
		var d:Dictionary=GameData.new_player_data()
		d.is_out=false
		d.order.set_num(BaseNumber.new(i))
		d.magic.set_num(BaseNumber.new(20))
		d.score.set_num(BaseNumber.new(5))
		GameData.player_data_library[i]=d
	GameProgress.is_game_over=false
	GameProgress.current_round=1
	GameProgress.current_phase_index=2
	GameProgress.current_player_id=0
	for area:BaseMapArea in MapData.areas:
		for loc in area._locations:
			(loc._players as Array).clear()
	# 库丘林站在深山町，目的地自由
	SetLocation.new().exec(MapData.miyama._locations[0], 0, false, true)
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE,
		TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX])
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE], 0)

func setup_battle_fact(winners:Array) -> void:
	GameLog.set_context(1,"battle")
	GameProgress.current_phase_index=3
	GameProgress.current_player_id=0
	# 三人实际位于同一战区；战斗事实按 BattleResolver 的真实形状逐参与者记录
	for i in range(3):
		SetLocation.new().exec(MapData.miyama._locations[0], i, false, true)
	var players:Array=[0,1,2]
	for i in players:
		GameLog.record("battle",i,-1,MapData.miyama._area_name,null,["battle"],
			{"players":players.duplicate(),"winners":winners.duplicate(),
			"out_players":[],"has_out":false,"powers":{}})


func activate_battle_score_effect() -> BaseEffect:
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE,
		TimePoints.BATTLE_PHASE, TimePoints.NON_CLIMAX])
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE],0)
	var eff=register_skill_by_effect("battle_end_score_per_opponent",0)
	if eff != null:
		EffectManager.request_manual_activation(eff,0)
		EffectManager.submit_option_choice(eff,[0])
	return eff


func make_card(key:String) -> BaseCard:
	var tpl = LoadAttack.resolve(key)
	if tpl == null:
		return null
	return CloneObject.new().exec(tpl)

func run():
	# —— ① 库丘林：起点不限（未声明 allowed_origin_areas），目标排除魔术工房 ——
	setup()
	var eff=register_skill_by_effect("move_anywhere_except_workshop", 0)
	check(eff != null, "the move ability is loaded")
	check(eff._is_manual and eff._need_activate, "it is player-activated and needs activation")
	check(EffectManager.request_manual_activation(eff, 0), "it can be requested in the action phase")
	check(EffectManager.submit_option_choice(eff, [0]), "the option is accepted")
	check(EffectManager.waiting_location == eff, "it asks for a destination")

	var workshop = GetMapAreaByName.new().exec("魔术工房")
	check(workshop != null, "the workshop area is resolvable by name")
	check(not EffectManager.submit_location_selection(eff, workshop._locations[0]),
		"the workshop is refused as a destination")

	# 拒绝即视为放弃、等待被清空（与 select_cards 同一口径）：换地点要重新请求一次
	check(EffectManager.waiting_location == null, "a refused pick clears the waiting state")
	check(EffectManager.request_manual_activation(eff, 0), "the ability can be requested again")
	check(EffectManager.submit_option_choice(eff, [0]), "the option is accepted again")
	check(EffectManager.submit_location_selection(eff, MapData.shinto._locations[0]),
		"a non-workshop destination is accepted")
	check(GameData.player_data_library[0].location == MapData.shinto._locations[0],
		"the player actually moved there")

	# —— ② 美杜莎：候选只含印刷威力 ≤3 的攻击牌 ——
	setup()
	var eff2=register_skill_by_effect("riding_mount_summon_play_low_power_cards", 0)
	check(eff2 != null, "the riding mount ability is loaded")
	var low=make_card("strength:2")
	var high=make_card("strength:5")
	check(low != null and high != null, "fixture cards are resolvable")
	GameData.player_data_library[0].hand_cards.append(low)
	GameData.player_data_library[0].hand_cards.append(high)
	check(EffectManager.request_manual_activation(eff2, 0), "it can be requested in the action phase")
	check(EffectManager.submit_option_choice(eff2, [0]), "the option is accepted")
	var pending:Dictionary=EffectManager.get_pending_card_selection()
	check(not (pending.get("cards", []) as Array).has(high), "a card with power above the limit is not offered")

	# 不挑任何一张也算提交（卡面是"至多3张"）
	check(EffectManager.submit_card_selection(eff2, []), "picking nothing is accepted for an at-most choice")
	check(not GameData.player_data_library[0].played_cards.has(high), "nothing is played when nothing is picked")

	# 再走一次：选中低威力牌 → 真的被打出
	setup()
	var eff3=register_skill_by_effect("riding_mount_summon_play_low_power_cards", 0)
	var low3=make_card("strength:2")
	GameData.player_data_library[0].hand_cards.append(low3)
	EffectManager.request_manual_activation(eff3, 0)
	EffectManager.submit_option_choice(eff3, [0])
	var pending3:Dictionary=EffectManager.get_pending_card_selection()
	check((pending3.get("cards", []) as Array).has(low3), "a low-power card is offered")
	check(EffectManager.submit_card_selection(eff3, [low3]), "picking it is accepted")
	check(GameData.player_data_library[0].played_cards.has(low3), "the picked card is played")

	# —— ③ 库丘林：战后按实际交战对手人数结算；只有获胜才令对手失去同量战果 ——
	setup()
	setup_battle_fact([0])
	var eff4=activate_battle_score_effect()
	check(eff4 != null, "the battle-end score ability is loaded")
	check(eff4._is_manual and eff4._need_activate, "the battle-end ability is player-activated")
	check(EffectManager.get_total_use_count(eff4) == 1, "the activation is recorded once for this round")
	TimePointChecker.global_time_point([TimePoints.BATTLE_END])
	check(GameData.player_data_library[0].score.number == 7,
		"the winner gains score equal to two fought opponents")
	check(GameData.player_data_library[1].score.number == 3 and GameData.player_data_library[2].score.number == 3,
		"each fought opponent loses the same amount when the user wins")

	setup()
	setup_battle_fact([1])
	var eff5=activate_battle_score_effect()
	check(eff5 != null, "the losing branch ability is loaded")
	TimePointChecker.global_time_point([TimePoints.BATTLE_END])
	check(GameData.player_data_library[0].score.number == 7,
		"the user still gains score for fought opponents without winning")
	check(GameData.player_data_library[1].score.number == 5 and GameData.player_data_library[2].score.number == 5,
		"opponents lose no score when the user did not win")

	print("RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
