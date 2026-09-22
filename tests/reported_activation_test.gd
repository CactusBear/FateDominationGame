extends Node
var failures:Array = []
var checks:int = 0
func check(ok:bool, label:String):
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", label, " ", ok)
func setup() -> Dictionary:
	EffectManager.reset_runtime(); GameLog.reset(); GameLog.set_context(1, "action")
	GameData.player_data_library.clear()
	for id in range(2):
		GameData.player_data_library[id] = GameData.new_player_data()
		GameData.player_data_library[id].is_out = false
	GameProgress.is_game_over = false
	GameProgress.current_round = 1; GameProgress.current_phase_index = 2; GameProgress.current_player_id = 0
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX])
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX], 0)
	return GameData.player_data_library[0]
func _ready(): call_deferred("run")
func run():
	var d = setup()
	var template = LoadCommandSpell.command_spells.values()[0]
	var card = CloneObject.new().exec(template)
	var eff:BaseEffect = card._effects[0]
	eff._trigger_player_id = 0
	d.command_spell_count.number = 3; d.magic.number = 0
	for i in range(3):
		var requested:bool = EffectManager.request_manual_activation(eff, 0)
		check(requested, "command request %d" % (i + 1))
		if requested: check(EffectManager.submit_option_choice(eff, [0]), "command submit %d" % (i + 1))
		check(d.command_spell_count.number == 2 - i and d.magic.number == 4 * (i + 1), "command resources %d" % (i + 1))
	check(not EffectManager.can_manual_activate(eff, 0), "empty resource blocks request")
	d.command_spell_count.number = 1
	check(not EffectManager.can_manual_activate(eff, 1), "wrong owner blocked")
	GameProgress.current_player_id = 1
	check(not EffectManager.can_manual_activate(eff, 0), "other player action blocked")
	GameProgress.current_player_id = 0
	EffectManager.close_time_point("self_action_phase", 0)
	check(not EffectManager.can_manual_activate(eff, 0), "closed window stays blocked")
	d = setup()
	var manual = BaseEffect.new("manual_probe", ["self_action_phase"], 0)
	manual._is_manual = true; manual._trigger_player_id = 0
	for i in range(2):
		var requested:bool = EffectManager.request_manual_activation(manual, 0)
		check(requested, "generic manual request %d" % i)
		if requested: EffectManager.submit_active_choice(manual, true)
	check(GameLog.query({"type":"effect", "actor":0, "data":{"effect_name":"manual_probe"}}, null).size() == 2, "generic manual settles twice")
	# Closing an already requested window must cancel it before payment.
	d = setup(); eff._trigger_player_id = 0; d.command_spell_count.number = 1
	check(EffectManager.request_manual_activation(eff, 0), "request before close")
	EffectManager.close_time_point("self_action_phase", 0)
	check(EffectManager.get_pending_active_effect() == null, "closing window prunes pending request")
	check(not EffectManager.submit_option_choice(eff, [0]) and d.command_spell_count.number == 1, "closed pending does not pay")
	d = setup(); d.command_spell_count.number = 2
	check(EffectManager.request_manual_activation(eff, 0), "cancel request opens")
	EffectManager.submit_active_choice(eff, false)
	check(d.command_spell_count.number == 2 and EffectManager.can_manual_activate(eff, 0), "cancel preserves resources and window")
	GameProgress.current_phase_index = 3
	TimePointChecker.set_phase_time_points([TimePoints.BATTLE_PHASE])
	check(not EffectManager.can_manual_activate(eff, 0), "different phase blocks request")
	d = setup()
	var event_manual = BaseEffect.new("event_manual", ["self_played_card"], 0)
	event_manual._is_manual = true; event_manual._trigger_player_id = 0
	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], 0)
	EffectManager.start_effect()
	check(not EffectManager.can_manual_activate(event_manual, 0), "consumed event is not restored")
	check(EffectManager.request_manual_activation(eff, 0), "unrelated effect cannot erase phase window")
	EffectManager.submit_active_choice(eff, false)
	test_regular_keyword()
	test_reveal_scope()
	await test_battle_manual_prompt()
	await test_battle_result_modal_sequence()
	await test_real_battle_ability_requires_priciest_noble_phantasm()
	test_result_change_detail()
	finish()


func test_result_change_detail() -> void:
	var d = setup()
	var opponent:Dictionary = GameDataManager.get_player_data(1)
	var opponent_card=BaseAttack.new("probe_card","",[],BaseNumber.new(1),BaseNumber.new(4))
	opponent.deck=[opponent_card]
	check(opponent_card != null, "the opponent owns a card for the detail fixture")
	if opponent_card == null:
		return
	var before:Dictionary=EffectManager.capture_rule_state()
	var power_before:int=opponent_card._power.number
	opponent_card._power.add(BaseNumber.new(-3))
	d.score.add(BaseNumber.new(2))
	var changes:Array=EffectManager.diff_rule_state(before, EffectManager.capture_rule_state())
	var lines:Array=[]
	for change in changes:
		lines.append(EffectManager.format_rule_change(change))
	var joined:String="\n".join(lines)
	print("DETAIL_RESULT ", joined.replace("\n"," | "))
	check(joined.contains("战果") and joined.contains("→"), "the detail names the player score change")
	check(joined.contains("威力") and joined.contains("→"), "the detail names the card power change")
	check(joined.contains("【") , "the detail names the affected card object")
	check(joined.contains(EffectManager.player_shown_name(0)),
		"the detail names the affected player")
	# 夹具还原：改回被探针改动的数值，避免污染后续用例
	opponent_card._power.add(BaseNumber.new(3))
	d.score.add(BaseNumber.new(-2))
	check(opponent_card._power.number == power_before, "the detail fixture restored the card power")


func test_real_battle_ability_requires_priciest_noble_phantasm() -> void:
	# 用开局真实发牌的数据：从者技能区里同时有对魔力、风王结界与誓约胜利之剑，
	# 才能验证"只有最高费用的宝具攻击"这一条。不要用会清空玩家数据的夹具。
	var ui = load("res://assets/scenes/game_scene/tactical_board_ui.tscn").instantiate()
	add_child(ui)
	ui.set_process(false)
	ui._local_player_id = GameData.player_id
	var id:int = ui._local_player_id
	var d:Dictionary = GameDataManager.get_player_data(id)
	EffectManager.reset_runtime()
	GameLog.reset()
	GameProgress.is_game_over = false
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 3
	GameProgress.current_player_id = id
	GameLog.set_context(1, "battle")
	d.played_cards.clear()
	# 打出宝具攻击要付得起（誓约胜利之剑为印刷费用 8）
	d.magic.set_num(BaseNumber.new(20))
	# 开局随机抽到的局势牌可能带「宝具禁止使用」，那会让本用例无法打出宝具攻击；
	# 这条禁令与"宝具绽放只在打出最高费用宝具时可用"无关，先移出局面。
	var previous_situation = MapData.active_situation
	MapData.active_situation = null
	var effect:BaseEffect=null
	# 用从者模板克隆整组技能牌（对魔力／风王结界／誓约胜利之剑）放进技能区：
	# 前面的用例清空过玩家数据，这里必须自己铺出真实技能组，
	# 才能同时覆盖"能发动的那条能力"和"最高费用的宝具攻击"。
	var templates:Array=[]
	for servant in GameData.loaded_servants:
		if servant._name == "artoria_pendragon":
			templates = servant._specials.get("SKILLS", [])
	var skills:Array=[]
	for template in templates:
		skills.append(CloneObject.new().exec(template))
	d.servant_skills = skills
	for skill in skills:
		RegisterObjectEffects.new().exec(skill, id)
		for candidate in skill._effects:
			if candidate._name == "np_bloom_score":
				effect=candidate
	check(effect != null, "real battle ability is available for the availability test")
	if effect == null:
		ui.queue_free()
		return
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE])
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], id)
	# 没打出最高费用的宝具攻击时：不进入询问队列，也就不会弹窗
	check(!EffectManager.can_manual_activate(effect, id),
		"real battle ability is not offered without the priciest noble phantasm")
	check(!EffectManager.request_manual_activation(effect, id),
		"requesting an unavailable real ability is refused")
	check(!EffectManager.is_waiting_for_choice(), "an unavailable ability creates no waiting input")
	ui._check_and_step_ai(0.0)
	check(ui.effect_modal == null or not ui.effect_modal.visible,
		"no dialog is shown while the printed condition is unmet")
	# 上面这次推进会结束本地玩家这一阶段的行动（此刻确实没有可做的事），
	# 所以要把战斗阶段窗口重新铺回来，再继续验证"条件满足后可以发动"。
	GameProgress.is_game_over = false
	GameProgress.current_phase_index = 3
	GameProgress.current_player_id = id
	GameLog.set_context(1, "battle")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE])
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], id)
	# 打出最高费用的宝具攻击后：可以发动，且结果写明影响对象与数值变化
	var best:BaseSkill=null
	for candidate in d.servant_skills:
		if candidate.has_attribute(Attributes.NOBLE_PHANTASM):
			if best == null or candidate._cost.number > best._cost.number:
				best=candidate
	check(best != null, "the priciest servant noble phantasm is found")
	if best != null:
		check(PlaySkill.new().exec(best, id, true), "the priciest noble phantasm is played through the real entry")
		EffectManager.reset_round_option_counts()
		check(EffectManager.can_manual_activate(effect, id),
			"real battle ability is offered once the priciest noble phantasm was played")
		var score_before:int=d.score.number
		check(EffectManager.request_manual_activation(effect, id), "the ability opens once its condition holds")
		check(EffectManager.submit_option_choice(effect, [0]), "the ability resolves")
		check(d.score.number > score_before, "the priciest noble phantasm scores")
		# 结果走界面取走路径：引擎队列 → 发动结果弹窗。
		# 不要在这里先 pop 掉结果，否则界面取走时队列已空、弹窗空着（截图必须与断言同源）。
		ui._flush_effect_messages()
		var shown_label = ui.effect_result_modal.get_node_or_null("Box/VBox/ResultScroll/ResultDesc") as Label
		var shown_text:String = str(shown_label.text) if shown_label != null else ""
		print("SHOWN_RESULT ", shown_text.replace("\n"," | "))
		check(ui.effect_result_modal != null and ui.effect_result_modal.visible,
			"the real ability result modal is visible for the screenshot")
		check(shown_text.contains("战果") and shown_text.contains("→"),
			"the modal body shows the affected player, field and its change")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/real_ability_result_detail.png")
		ui._on_effect_result_closed()
	MapData.active_situation = previous_situation
	ui.queue_free()


func test_battle_result_modal_sequence() -> void:
	var d = setup()
	var ui = load("res://assets/scenes/game_scene/tactical_board_ui.tscn").instantiate()
	add_child(ui)
	ui.set_process(false)
	ui._local_player_id = 0
	GameProgress.is_game_over = false
	GameProgress.current_round = 4
	GameProgress.current_phase_index = 3
	GameProgress.current_player_id = 0
	GameLog.set_context(4, "battle")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE])
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], 0)
	var card = BaseSkill.new("battle_result_card", "", [], BaseNumber.new(0), BaseNumber.new(0))
	card._shown_name = "结果测试卡"
	card._is_activating = true
	var first = BaseEffect.new("result_first", [TimePoints.SELF_BATTLE_PHASE], 0)
	first._shown_name = "第一项战斗能力"
	first._is_manual = true
	first._need_activate = true
	first.from = card
	first._funcs = LoadHelper.load_funcs([{"func_name":"edit_power","parameters":[null,BaseNumber.new(1),0],"var_index":-1}], first)
	var second = BaseEffect.new("result_second", [TimePoints.SELF_BATTLE_PHASE], 0)
	second._shown_name = "第二项战斗能力"
	second._is_manual = true
	second._need_activate = true
	second.from = card
	second._funcs = LoadHelper.load_funcs([{"func_name":"edit_power","parameters":[null,BaseNumber.new(1),0],"var_index":-1}], second)
	card._effects = [first, second]
	RegisterObjectEffects.new().exec(card, 0)
	ui._show_tactical_confirm("战斗阶段已有提示", true)
	ui._check_and_step_ai(0.0)
	check(ui.tactical_confirm_modal.visible and not ui.effect_modal.visible and EffectManager.waiting_effect == null,
		"existing tactical alert is handled before battle ability prompt")
	ui._on_tactical_confirm_cancel()
	check(ui._prompt_next_manual_activation(0, "battle"), "first battle result fixture opens a prompt")
	ui._check_waiting_effects()
	ui._on_effect_modal_confirm()
	ui._prompt_next_manual_activation(0, "battle")
	ui._check_waiting_effects()
	ui._flush_effect_messages()
	await get_tree().process_frame
	await get_tree().process_frame
	var result_modal = ui.get_node_or_null("Modal_EffectResult") as Control
	check(result_modal != null and result_modal.visible, "manual ability opens the dedicated result modal")
	check(ui.effect_modal == null or not ui.effect_modal.visible, "result modal does not overlap the next ability prompt")
	var result_desc = result_modal.get_node_or_null("Box/VBox/ResultScroll/ResultDesc") as Label if result_modal != null else null
	check(result_desc != null and "第一项战斗能力" in result_desc.text, "result modal shows the resolved ability result")
	var result_title = result_modal.get_node_or_null("Box/VBox/Title") as Control if result_modal != null else null
	var result_scroll = result_modal.get_node_or_null("Box/VBox/ResultScroll") as Control if result_modal != null else null
	var result_close = result_modal.get_node_or_null("Box/VBox/BtnClose") as Control if result_modal != null else null
	check(result_title != null and result_scroll != null and result_close != null
		and result_title.get_global_rect().end.y <= result_scroll.get_global_rect().position.y
		and result_scroll.get_global_rect().end.y <= result_close.get_global_rect().position.y,
		"effect result title content and button do not overlap")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/effect_result_modal.png")
	ui._on_effect_result_closed()
	check(ui.effect_modal != null and ui.effect_modal.visible and EffectManager.waiting_effect == second,
		"closing the result modal reveals the next ability prompt")
	ui.queue_free()


func test_battle_manual_prompt() -> void:
	var d = setup()
	var ui = load("res://assets/scenes/game_scene/tactical_board_ui.tscn").instantiate()
	add_child(ui)
	ui.set_process(false)
	ui._local_player_id = 0
	GameProgress.is_game_over = false
	GameProgress.current_round = 2
	GameProgress.current_phase_index = 3
	GameProgress.current_player_id = 0
	GameLog.set_context(2, "battle")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE])
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], 0)
	var card = BaseSkill.new("battle_prompt_card", "", [], BaseNumber.new(6), BaseNumber.new(0))
	card._is_activating = true
	var manual = BaseEffect.new("battle_prompt_probe", [TimePoints.SELF_BATTLE_PHASE], 0)
	manual._shown_name = "战斗能力询问探针"
	manual._is_manual = true
	manual._need_activate = true
	manual.from = card
	card._effects = [manual]
	RegisterObjectEffects.new().exec(card, 0)
	ui._check_and_step_ai(0.0)
	check(EffectManager.waiting_effect == manual, "battle manual prompt enters waiting queue")
	ui._check_waiting_effects()
	check(ui.effect_modal != null and ui.effect_modal.visible, "battle manual prompt shows effect modal")
	var desc = ui.effect_modal.get_node_or_null("Box/VBox/Desc") as Label
	var confirm = ui.effect_modal.get_node_or_null("Box/VBox/ButtonsRow/BtnConfirm") as Button
	check(desc != null and "战斗能力询问探针" in desc.text, "battle manual modal shows ability text")
	check(desc != null and "消耗资源" not in desc.text and "魔力 6" not in desc.text,
		"activating a card ability does not show the card play cost")
	check(confirm != null and confirm.visible and not confirm.disabled,
		"plain battle ability can be confirmed after option dialogs")
	var magic_before:int = d.magic.number
	ui._on_effect_modal_confirm()
	check(d.magic.number == magic_before, "confirming a card ability does not pay the card play cost")
	check(EffectManager.waiting_effect == null, "confirming a battle ability resolves the waiting prompt")
	ui._current_waiting_effect = null
	ui.effect_modal.visible = false
	check(not ui._prompt_next_manual_activation(0, "battle"), "resolved ability is not prompted twice in one battle window")
	GameProgress.current_round = 3
	GameLog.set_context(3, "battle")
	check(ui._prompt_next_manual_activation(0, "battle"), "ability is prompted again in a new battle window")
	EffectManager.submit_active_choice(manual, false)
	ui.queue_free()
func test_reveal_scope():
	var d = setup()
	var zone_skill = BaseSkill.new("zone", "", [])
	var side_skill = BaseSkill.new("side", "", [])
	var played_skill = BaseSkill.new("played", "", [])
	var held_skill = BaseSkill.new("held", "", [])
	var hidden_attack = BaseAttack.new("hidden_attack", "", [], BaseNumber.new(0), BaseNumber.new(5))
	for card in [zone_skill, side_skill, played_skill, held_skill, hidden_attack]: card._is_concealed = true
	d.servant_skills = [zone_skill]; d.side.skills = [side_skill]
	d.played_cards = [played_skill, hidden_attack]; d.hand_cards = [held_skill]
	check(ReleaseTrueName.new().exec(0), "release scope succeeds")
	for card in [zone_skill, side_skill, played_skill, held_skill]:
		check(not card._is_concealed, "revealed actual skill " + card._name)
		check(not card._is_activating, "reveal does not activate " + card._name)
	check(hidden_attack._is_concealed and not hidden_attack._is_activating and d.power.number == 0, "ordinary hidden attack remains inert")
	check(not ReleaseTrueName.new().exec(0), "release is idempotent")
func test_regular_keyword():
	for hidden in [false, true]:
		var d = setup()
		d.magic.number = 12
		var keyword = BaseAttack.new("keyword", "", [], BaseNumber.new(1), BaseNumber.new(2))
		keyword._keywords = [ApplyCardKeywords.TRUE_NAME_RELEASE]
		d.hand_cards = [keyword, BaseAttack.new("plain", "", [], BaseNumber.new(0), BaseNumber.new(1))]
		check(RegularPlay.add(0, keyword, hidden), "regular keyword enters hidden=%s" % hidden)
		check(ReleaseTrueName.is_released(0) == not hidden, "regular keyword release hidden=%s" % hidden)
		if not hidden:
			var events = GameLog.query({"type":"time_point", "actor":0}, null)
			var release_index = -1
			var played_index = -1
			for i in range(events.size()):
				if events[i].tags.has(TimePoints.TRUE_NAME_RELEASE): release_index = i
				if events[i].tags.has(TimePoints.PLAYED_CARD): played_index = i
			check(release_index >= 0 and played_index > release_index, "release precedes PLAYED_CARD")
func finish():
	print("RESULT checks=", checks, " failures=", failures)
	var f = FileAccess.open("res://reported_activation_result.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks, "failures":failures})); f.close()
	get_tree().quit(0 if failures.is_empty() else 1)
