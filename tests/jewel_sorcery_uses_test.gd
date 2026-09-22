extends Node
# 远坂凛【宝石】的次数口径回归：高潮阶段每个选项至多3次、共计最多9次，且计数【每回合重置】
# （也就是每个高潮回合各自有 3/3/3 的额度，实际还会受宝石枚数限制）。
# 用户明确保留 reset_counts_each_round，所以这里断言的是重置后的行为；
# 覆盖目的是防止以后有人动 max_uses / max_total_uses 时静默失效。
var failures:Array=[]
var checks:int=0
var host:Node=null
var local:int=0
var jewels:BaseBuff=null
var climax_effect:BaseEffect=null
var action_effect:BaseEffect=null

func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)

func _ready(): call_deferred("run")

## 高潮回合的行动阶段窗口：宝石高潮效果声明的是 self_action_phase + self_climax（两者都要），
## 而"高潮"是回合属性，第 9/10/11 回合挂着高潮局势牌，所以夹具要把回合推进到高潮回合
func open_climax_window() -> void:
	GameProgress.current_round=9
	GameProgress.current_phase_index=2
	GameProgress.current_player_id=local
	GameLog.set_context(9,"action")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE,
		TimePoints.ACTION_PHASE, TimePoints.CLIMAX])
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE, TimePoints.CLIMAX], local)

## 走真实链路发动一次：请求 → 选项 → 结算
func activate(option_index:int) -> bool:
	if not EffectManager.request_manual_activation(climax_effect, local):
		print("    request refused")
		return false
	if not EffectManager.submit_option_choice(climax_effect, [option_index]):
		print("    submit refused")
		return false
	return true

func used(effect:BaseEffect, option_index:int) -> int:
	return EffectManager.get_option_use_count(effect, option_index)

func run():
	host=load("res://assets/scenes/game_scene/tactical_board_ui.tscn").instantiate()
	get_tree().root.add_child(host)
	host.set_process(false)
	local=GameData.player_id
	var d:Dictionary=GameData.player_data_library[local]

	var jewel_card=null
	for thing in d.master._other_things:
		if thing != null and str(thing._name) == "jewel_card":
			jewel_card=thing
			break
	check(jewel_card != null, "Rin owns a real jewel card")
	jewels=jewel_card.get("_relate_buff")
	check(jewels != null, "the jewel card is wired to the jewel buff")
	for effect in jewels._effects:
		if effect._name == "jewel_sorcery_climax":
			climax_effect=effect
		elif effect._name == "jewel_sorcery_action":
			action_effect=effect
	check(climax_effect != null and action_effect != null, "both jewel abilities are loaded")
	check(d.buffs.has(jewels), "the jewel buff is on the player")
	var initial_yin:Array=[]
	for card in d.out_of_game.attacks:
		if card != null and str(card._name) == "yin_qi_bullet":
			initial_yin.append(card)
	check(initial_yin.size() == 3, "Rin starts with three yin bullets out of game")
	check(initial_yin.size() == 3 and initial_yin[0] != initial_yin[1] and initial_yin[1] != initial_yin[2],
		"the three starting yin bullets are independent instances")

	# —— 数据口径 ——
	check(int(climax_effect._max_total_uses) == 9, "the climax ability declares nine uses in total")
	check(climax_effect._reset_counts_each_round == true,
		"the climax ability resets its option counts each round")
	check(action_effect._reset_counts_each_round == true,
		"the non-climax ability resets each round too")
	check((action_effect._options[1].get("activation_requirements", []) as Array).size() == 1,
		"the non-climax yin bullet choice declares its prerequisite")
	check((climax_effect._options[1].get("activation_requirements", []) as Array).size() == 1,
		"the climax yin bullet choice declares its prerequisite")

	# —— 游戏外没有阴炁弹：提示并取消，不扣宝石、不记次数 ——
	open_climax_window()
	# 开局时阴炁弹未必已进入游戏外；先从御主声明克隆一张，再移出，构造确定的“当前没有”。
	var yin_fixture=null
	for attack in (d.master._specials.get("ATTACKS", []) as Array):
		if attack != null and str(attack._name) == "yin_qi_bullet":
			yin_fixture=CloneObject.new().exec(attack)
			break
	check(yin_fixture != null, "the yin bullet template is available for the fixture")
	if yin_fixture != null:
		d.out_of_game.attacks.append(yin_fixture)
	var removed_yin:Array=[]
	for card in (d.out_of_game.attacks as Array).duplicate():
		if card != null and str(card._name) == "yin_qi_bullet":
			d.out_of_game.attacks.erase(card)
			removed_yin.append(card)
	check(!removed_yin.is_empty(), "the fixture originally owns an out-of-game yin bullet")
	var no_yin_level:int=jewels._buff_level.number
	EffectManager.pop_messages(local)
	check(EffectManager.request_manual_activation(climax_effect, local),
		"the jewel ability can still be opened when the yin bullet is absent")
	check(EffectManager.submit_option_choice(climax_effect, [1]),
		"the unavailable choice is handled as a cancellation")
	check(jewels._buff_level.number == no_yin_level,
		"a cancelled yin bullet choice consumes no jewel")
	check(used(climax_effect, 1) == 0,
		"a cancelled yin bullet choice records no use")
	check(not EffectManager.is_waiting_for_choice(),
		"the cancelled choice leaves no pending input")
	var missing_messages:Array=EffectManager.pop_messages(local)
	check(missing_messages.any(func(message): return "游戏外没有【阴炁弹】" in str(message)),
		"the player receives the missing yin bullet prompt")
	for card in removed_yin:
		d.out_of_game.attacks.append(card)

	# —— 弃牌后抽同等数量：牌库为空时先把弃牌堆洗回，再完成本次抽牌 ——
	open_climax_window()
	var selected := BaseAttack.new("selected_for_jewel", "", [], BaseNumber.new(0), BaseNumber.new(1))
	var old_discard := BaseAttack.new("old_discard", "", [], BaseNumber.new(0), BaseNumber.new(1))
	d.hand_cards = [selected]
	d.deck = []
	d.discard = [old_discard]
	check(EffectManager.request_manual_activation(climax_effect, local), "jewel redraw opens with an empty deck")
	check(EffectManager.submit_option_choice(climax_effect, [2]), "jewel redraw enters card selection")
	check(EffectManager.submit_card_selection(climax_effect, [selected]), "jewel redraw accepts the selected card")
	check(d.hand_cards.size() == 1, "jewel redraw still draws when the deck started empty")
	check(not GameLog.query({"type":"reshuffle_discard", "actor":local}, null).is_empty(),
		"jewel redraw records the discard reshuffle")

	# —— 每个选项至多3次（真实链路）——
	open_climax_window()
	var level_before:int=jewels._buff_level.number
	check(EffectManager.is_option_available(climax_effect, 0, 1), "the first choice is offered")
	for i in range(3):
		check(activate(0), "climax choice %d resolves" % (i + 1))
	check(used(climax_effect, 0) == 3, "the option is counted three times")
	check(not EffectManager.is_option_available(climax_effect, 0, 1),
		"the same option is refused after three uses")
	check(jewels._buff_level.number == level_before - 3, "each activation consumes one jewel")

	# —— 共计最多9次：另两项各用满3次后，连还有余量的选项也不能再用 ——
	climax_effect._option_use_counts[1] = 3
	climax_effect._option_use_counts[2] = 3
	check(EffectManager.get_total_use_count(climax_effect) == 9, "nine uses in total are counted")
	check(not EffectManager.is_option_available(climax_effect, 0, 1),
		"the ninth use exhausts the whole ability")
	check(not EffectManager.has_available_options(climax_effect),
		"no option is offered once the total is spent")

	# —— 每回合重置：新回合重新拿到 3/3/3 与 9 次的额度 ——
	GameProgress.start_round()
	check(used(climax_effect, 0) == 0, "a new round refunds the option counter")
	check(EffectManager.get_total_use_count(climax_effect) == 0, "a new round clears the nine-use budget")
	open_climax_window()
	check(EffectManager.is_option_available(climax_effect, 0, 1), "the option is offered again next round")
	check(activate(0), "the ability can be activated again next round")
	check(used(climax_effect, 0) == 1, "the new round counts from one again")

	print("RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
