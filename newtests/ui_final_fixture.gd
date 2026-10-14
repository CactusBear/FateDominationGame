extends RefCounted

static func setup() -> Dictionary:
	GameStart.reset()
	EffectManager.reset_runtime()
	GameProgress.reset_progress()
	GameLog.reset()
	GameData.player_data_library.clear()
	GameData.player_id = 0
	for pid in [0, 1]:
		GameData.player_data_library[pid] = GameData.new_player_data()
		GameData.player_data_library[pid].is_out = false
		GameData.player_data_library[pid].player_name = "UI验收" + str(pid)
		GameData.player_data_library[pid].order.number = pid
	var data: Dictionary = GameData.player_data_library[0]
	data.magic.number = 8
	data.command_spell_count.number = 3
	data.play_limit.number = 1
	data.regular_play_min.number = 1
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX])
	var context = SessionGeneration.derive_context(SessionGeneration.current_token().token, &"ui_final_fixture").context
	LoadAttack.load_all()
	LoadCommandSpell.load_all()
	# 加载模板经可信工厂复制到本局来源（同 newtests/fixture_clone.gd）。
	var spell = preload("res://newtests/fixture_clone.gd").clone_template(LoadCommandSpell.get_normal(), context)
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/command_spells/normal_command_spell.json"))
	spell._effects = LoadHelper.load_effects(parsed.effects, spell, context)
	data.out_of_game.command_spell.append(spell)
	var spell_ok: bool = not spell._effects.is_empty()
	for effect in spell._effects:
		spell_ok = EffectManager.register_effect(effect, 0) and spell_ok
	var cards: Array = []
	for flags in [[false,false],[true,false],[false,true],[true,true]]:
		var art = LoadAttack.resolve("strength:2")
		var card = BaseSkill.new("UI四态" + str(flags), art._card_img, [], BaseNumber.new(1), BaseNumber.new(1))
		card._zoom_kind = ""
		card._card_back_img = art._card_back_img
		card._is_concealed = false
		card._need_extra_play = not flags[0]
		data.hand_cards.append(card)
		if flags[1]:
			var effect = BaseEffect.new("UI手动候选" + str(flags), [TimePoints.SELF_PREFIX + TimePoints.ACTION_PHASE], 0, false, false)
			effect._is_manual = true
			effect._need_activate = false
			effect._cost = BaseNumber.new(0)
			effect.from = weakref(card)
			var bound: Dictionary = SessionGeneration.bind_origin(effect, context.token(), &"ui_final_fixture.effect")
			effect.bind_runtime_context(bound.context)
			effect._options = LoadHelper.load_effect_options([{ "shown_option_name":"测试选择生命周期", "funcs":[] }], effect, effect.runtime_context())
			card._effects = [effect]
			EffectManager.register_effect(effect, 0)
		cards.append(card)
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE], 0)
	preload("res://scripts/system/operations/EditCardCost.gd").new().exec(BaseNumber.new(1), null, cards[1])
	GameStart._started = true
	return {"data":data,"cards":cards,"spell":spell,"spell_ok":spell_ok,"context":context}
