extends Node
# 卡效在真实规则入口下的运行时回归。
# 一律走"登记效果 → 派发效果自己声明的时点 → 看结算结果"，不直接调用效果内部的单个 func：
# 直接调 func 会绕过时点匹配与 condition 判断，验不到"到点才生效""条件不满足不生效"。
var failures:Array[String] = []
var checks:int = 0

func check(ok:bool, label:String) -> void:
	checks += 1
	if !ok: failures.append(label)
	print("CHECK ", label, " ", ok)

func named(pool:Array, key:String):
	for item in pool:
		if item != null and item._name == key:
			return item
	return null

func setup(player_count:int = 3, magic:int = 10) -> void:
	EffectManager.reset_runtime()
	GameLog.reset()
	GameLog.set_context(1, "battle")
	GameData.player_data_library.clear()
	for id in range(player_count):
		var d:Dictionary = GameData.new_player_data()
		d.is_out = false
		d.order.number = id
		d.magic.number = magic
		GameData.player_data_library[id] = d
	GameProgress.is_game_over = false
	GameProgress.current_round = 1
	GameProgress.current_player_id = 0
	for area in MapData.areas:
		area._events.clear()
		for loc in area._locations:
			(loc._players as Array).clear()
	DefeatBuff.clear_all()
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE, TimePoints.NON_CLIMAX])

func place(area:BaseMapArea, player_id:int, slot:int = 0) -> bool:
	return SetLocation.new().exec(area._locations[slot], player_id, false, true)

## 把从者技能的效果登记到指定玩家名下，返回该技能的克隆效果数组。
## 用克隆体：登记会写 _trigger_player_id，直接登记模板会让同一张牌下次进场不再被登记
func register_skill_effects(servant_key:String, skill_key:String, player_id:int) -> Array:
	var servant = named(GameData.loaded_servants, servant_key)
	if servant == null:
		return []
	var skill = named(servant._specials.get("SKILLS", []), skill_key)
	if skill == null:
		return []
	var cloned = CloneObject.new().exec(skill)
	if cloned == null:
		return []
	#技能牌的效果只在"这张牌已打出、正在生效"时被询问（card_state_allows 查 _is_activating），
	#所以夹具要把它标成生效中，否则非被动效果永远进不了决断队列
	if cloned is BaseHandCard:
		cloned._is_activating = true
	for effect in cloned._effects:
		EffectManager.register_effect(effect, player_id)
	return cloned._effects

func effect_named(effects:Array, key:String):
	for e in effects:
		if e != null and str(e._name) == key:
			return e
	return null

## 卡面写「战斗阶段：」的能力是【主动】的：夹具必须按玩家的真实入口发动一次。
## 只派发阶段时点不会再有自动结算（那正是"用不出来"的旧缺陷写法），
## 而且调用前要把 GameProgress 的当前阶段设成对应阶段——
## 手动效果的可发动窗口是按"当前阶段 + 当前行动者"重建的，光派发时点匹配不到
func activate_effect(effects:Array, effect_key:String, player_id:int) -> bool:
	var eff = effect_named(effects, effect_key)
	if eff == null:
		return false
	if not EffectManager.request_manual_activation(eff, player_id):
		return false
	return EffectManager.submit_active_choice(eff, true)

## 贯穿心脏（穿刺死棘之枪）：若仅有一名对手与你位于同一战场，令其【败北】。
## 正例之外必须有两个反例：没有对手、对手超过一名，都不该有人败北
func test_pierce_heart_defeat() -> void:
	setup()
	place(MapData.miyama, 0, 0)
	place(MapData.miyama, 1, 1)
	GameProgress.current_phase_index = 3
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], 0)
	activate_effect(register_skill_effects("cu_chulainn", "gae_bolg_piercing_heart", 0), "placeholder_pierce_heart_single_opponent_defeat", 0)
	check(DefeatBuff.get_defeat_count(1) == 1, "pierce heart defeats the single opponent sharing the battlefield")

	setup()
	place(MapData.miyama, 0, 0)
	place(MapData.miyama, 1, 1)
	place(MapData.miyama, 2, 2)
	GameProgress.current_phase_index = 3
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], 0)
	activate_effect(register_skill_effects("cu_chulainn", "gae_bolg_piercing_heart", 0), "placeholder_pierce_heart_single_opponent_defeat", 0)
	check(DefeatBuff.get_defeat_count(1) == 0 and DefeatBuff.get_defeat_count(2) == 0, "two opponents block the pierce heart defeat")

	setup()
	place(MapData.miyama, 0, 0)
	place(MapData.shinto, 1, 0)
	GameProgress.current_phase_index = 3
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], 0)
	activate_effect(register_skill_effects("cu_chulainn", "gae_bolg_piercing_heart", 0), "placeholder_pierce_heart_single_opponent_defeat", 0)
	check(DefeatBuff.get_defeat_count(1) == 0, "an opponent in another battlefield is not defeated")

	# 一次战斗中败北直接影响胜负判定：被败北的对手不能赢，也不能阻止你赢
	setup()
	place(MapData.miyama, 0, 0)
	place(MapData.miyama, 1, 1)
	GameDataManager.get_player_data(1).power.number = 99
	GameProgress.current_phase_index = 3
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], 0)
	activate_effect(register_skill_effects("cu_chulainn", "gae_bolg_piercing_heart", 0), "placeholder_pierce_heart_single_opponent_defeat", 0)
	var battle:Dictionary = BattleResolver.new().exec([0, 1])
	var winners:Array = (battle.get("winners_by_area", {}) as Dictionary).get(MapData.miyama._area_name, [])
	check(winners.has(0) and not winners.has(1), "a defeated opponent loses the battle it was defeated in")

## 从者技能牌模板的克隆体（技能区/战场上的牌都要用实例，不能拿模板进数组）
func skill_card(servant_key:String, skill_key:String):
	var servant = named(GameData.loaded_servants, servant_key)
	if servant == null:
		return null
	var skill = named(servant._specials.get("SKILLS", []), skill_key)
	if skill == null:
		return null
	return CloneObject.new().exec(skill)

## 燕返（三之太刀）：【一之太刀】和【二之太刀】同时在战场时真名解放并合计威力+3。
## 反例覆盖"只在一张""都在手牌没上场""上场后被关闭"三种情况
func test_swallow_reversal_combo() -> void:
	setup()
	register_skill_effects("sasaki_kojirou", "san_no_tachi", 0)
	var d:Dictionary = GameDataManager.get_player_data(0)
	d.played_cards = [skill_card("sasaki_kojirou", "ichi_no_tachi"), skill_card("sasaki_kojirou", "ni_no_tachi")]
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], 0)
	check(ReleaseTrueName.is_released(0), "swallow reversal releases the true name when both cards are on the battlefield")
	check((d["total_power_bonus"] as BaseNumber).number == 3, "swallow reversal adds three total power")

	# 反例：只有一之太刀在场
	setup()
	register_skill_effects("sasaki_kojirou", "san_no_tachi", 0)
	d = GameDataManager.get_player_data(0)
	d.played_cards = [skill_card("sasaki_kojirou", "ichi_no_tachi")]
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], 0)
	check(not ReleaseTrueName.is_released(0) and (d["total_power_bonus"] as BaseNumber).number == 0, "one sword alone gives nothing")

	# 反例：两张都在手牌，没有上场
	setup()
	register_skill_effects("sasaki_kojirou", "san_no_tachi", 0)
	d = GameDataManager.get_player_data(0)
	d.hand_cards = [skill_card("sasaki_kojirou", "ichi_no_tachi"), skill_card("sasaki_kojirou", "ni_no_tachi")]
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], 0)
	check(not ReleaseTrueName.is_released(0) and (d["total_power_bonus"] as BaseNumber).number == 0, "cards in hand are not on the battlefield")

	# 反例：二之太刀上场后被关闭（回到技能区），不再算"位于战场"
	setup()
	register_skill_effects("sasaki_kojirou", "san_no_tachi", 0)
	d = GameDataManager.get_player_data(0)
	var closed = skill_card("sasaki_kojirou", "ni_no_tachi")
	if closed != null:
		closed.set("_is_closed", true)
	d.played_cards = [skill_card("sasaki_kojirou", "ichi_no_tachi")]
	d.servant_skills = [closed]
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], 0)
	check(not ReleaseTrueName.is_released(0) and (d["total_power_bonus"] as BaseNumber).number == 0, "a closed sword no longer counts as being on the battlefield")

## 万符必应破戒（美狄亚）：指定你所在战场的一名玩家，其失去一枚令咒；
## 原本只有一枚或更少时令其【败北】；原本没有令咒时你总威力+10；每局限一次。
## 目标由选项级 select_players 声明，候选集来自数据（这里声明的是"与你同战区的其他玩家"）。
## 走真实链路：行动阶段时点触发 → 玩家选"指定目标"这一项 → 停下来等选人 → 提交目标
func test_rule_breaker() -> void:
	var eff = _arm_rule_breaker(3)
	check(EffectManager.waiting_effect == eff, "rule breaker asks for a decision at the action phase")
	check(EffectManager.submit_option_choice(eff, [0]), "choosing the target option opens the player choice")
	var pending:Dictionary = EffectManager.get_pending_player_selection()
	check(not (pending.get("candidates", []) as Array).is_empty(), "rule breaker offers candidates from the declared query")
	check(not (pending.get("candidates", []) as Array).has(0), "the declared candidate query excludes the caster itself")
	check(EffectManager.submit_player_selection(eff, [1]), "a candidate in the same battlefield is accepted")
	check(GameDataManager.get_player_data(1)["command_spell_count"].number == 2, "target with three seals loses one")
	check(DefeatBuff.get_defeat_count(1) == 0, "a target with more than one seal is not defeated")
	check((GameDataManager.get_player_data(0)["total_power_bonus"] as BaseNumber).number == 0, "no power bonus while the target still had seals")
	check(not EffectManager.request_manual_activation(eff, 0), "rule breaker cannot be used twice in one game")

	# 非法目标：不在候选集里的人（自己）、以及别的战场的人，都必须被拒
	eff = _arm_rule_breaker(3)
	EffectManager.submit_option_choice(eff, [0])
	check(not EffectManager.submit_player_selection(eff, [0]), "the caster itself is rejected as a target")
	eff = _arm_rule_breaker(3)
	EffectManager.submit_option_choice(eff, [0])
	check(not EffectManager.submit_player_selection(eff, [2]), "a player in another battlefield is rejected")

	# 目标原本只有 1 枚：失去后为 0，并被败北；没有"原本没有令咒"的加成
	eff = _arm_rule_breaker(1)
	EffectManager.submit_option_choice(eff, [0])
	check(EffectManager.submit_player_selection(eff, [1]), "single seal target is accepted")
	check(GameDataManager.get_player_data(1)["command_spell_count"].number == 0, "single seal target drops to zero")
	check(DefeatBuff.get_defeat_count(1) == 1, "a target with one seal or fewer is defeated")
	check((GameDataManager.get_player_data(0)["total_power_bonus"] as BaseNumber).number == 0, "a one seal target gives no power bonus")

	# 目标原本没有令咒：不能被减成负数，仍然败北，且你总威力+10
	eff = _arm_rule_breaker(0)
	EffectManager.submit_option_choice(eff, [0])
	check(EffectManager.submit_player_selection(eff, [1]), "zero seal target is accepted")
	check(GameDataManager.get_player_data(1)["command_spell_count"].number == 0, "a target without seals is never pushed below zero")
	check(DefeatBuff.get_defeat_count(1) == 1, "a target without seals is still defeated")
	check((GameDataManager.get_player_data(0)["total_power_bonus"] as BaseNumber).number == 10, "a target without seals grants ten total power")

	# 所在战场没有别的玩家：候选集为空，这一项不可选，效果不应进入目标选择
	eff = _arm_rule_breaker(3, false)
	check(eff != null and not EffectManager.is_option_available(eff, 0), "no candidate makes the option unavailable")
	check(not EffectManager.submit_option_choice(eff, [0]), "the option cannot be submitted without candidates")


func test_rule_breaker_after_prior_action_effect() -> void:
	_rule_breaker_scene(true)
	var prior := BaseEffect.new("prior_action_effect", [TimePoints.SELF_ACTION_PHASE], 0, true, false)
	prior._need_activate = false
	prior._funcs = LoadHelper.load_funcs([
		{"func_name":"edit_magic", "parameters":[null, BaseNumber.new(0), 0], "var_index":-1}
	], prior)
	EffectManager.register_effect(prior, 0)
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE], 0)
	var card = skill_card("medea", "rule_breaker")
	check(card != null, "real rule breaker skill is loadable after another action effect")
	if card == null:
		return
	card._is_activating = true
	GameDataManager.get_player_data(0).played_cards = [card]
	var eff = effect_named(card._effects, "rule_breaker_remove_command_spell")
	EffectManager.register_effect(eff, 0)
	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], 0, card)
	# 该能力是主动的：按玩家的真实入口请求。本测试的意图不变——
	# 验证"别的效果执行后，持续的行动阶段窗口对手动查询依然成立"
	check(EffectManager.can_manual_activate(eff, 0),
		"the persistent action window is still matched after a prior effect")
	check(EffectManager.request_manual_activation(eff, 0),
		"rule breaker still opens for the player after a prior effect")
	check(EffectManager.waiting_effect == eff,
		"rule breaker still sees the persistent action window after a prior effect")
	if EffectManager.waiting_effect != eff:
		return
	check(EffectManager.submit_option_choice(eff, [0]), "real rule breaker opens target selection")
	check(EffectManager.submit_player_selection(eff, [1]), "real rule breaker resolves on the selected opponent")
	check(GameDataManager.get_player_data(1).command_spell_count.number == 2,
		"real rule breaker removes one command spell")
	var logs:Array = GameLog.query({"type":"effect", "actor":0, "data":{"effect_name":"rule_breaker_remove_command_spell"}}, null)
	check(logs.size() == 1 and bool(logs[0].data.get("applied", false)),
		"used servant skill effect is recorded as applied for the report")

## 铺局并把万符必应破戒推到"等玩家选效果"的状态，返回该效果。
## 目标玩家默认与美狄亚同处深山町，same_area=false 时放去新都
func _arm_rule_breaker(target_seals:int, same_area:bool = true):
	_rule_breaker_scene(same_area)
	GameDataManager.get_player_data(1)["command_spell_count"].number = target_seals
	var effects := register_skill_effects("medea", "rule_breaker", 0)
	var eff = effect_named(effects, "rule_breaker_remove_command_spell")
	# 卡面写「行动阶段：」的能力是【主动】的：夹具要按玩家的真实入口请求一次，
	# 只派发阶段时点不会再有自动询问（旧实现标了 pure=false 会自动弹窗）
	if eff != null:
		GameProgress.current_phase_index = 2
		GameProgress.current_player_id = 0
		TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE], 0)
		EffectManager.request_manual_activation(eff, 0)
	return eff

## 美狄亚（玩家0）在深山町，玩家1 视 same_area 决定是否同处一处，玩家2 在新都
func _rule_breaker_scene(same_area:bool = true) -> void:
	setup()
	# 主动能力的可发动窗口按"当前阶段 + 当前行动者"重建，夹具要把这两项设对
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX])
	place(MapData.miyama, 0, 0)
	if same_area:
		place(MapData.miyama, 1, 1)
	else:
		place(MapData.shinto, 1, 0)
	place(MapData.shinto, 2, 1)

## 远坂凛：绝对服从的命令 - 若你以该令咒获得了魔力，战斗阶段结束后失去4点魔力。
## 判据是"本回合用过令咒的获得魔力选项"这条结构化事实，不从当前魔力数值反推
func test_rin_absolute_order() -> void:
	# 本回合用了令咒的"获得4魔力"选项 → 战斗阶段结束后失去4点魔力
	var d := _rin_scene()
	check(_use_command_spell_option(0), "the command spell gain magic option is used")
	check(not GameLog.query({"type": "option_used", "tags": ["command_spell_gain_magic"]}, 0).is_empty(),
		"using the option is recorded as a structured fact")
	var before: int = d["magic"].number
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE_END], 0)
	check(d["magic"].number == before - 4, "rin loses four magic after gaining magic from the command spell")

	# 用的是别的选项 → 不触发
	d = _rin_scene()
	_use_command_spell_option(1)
	before = d["magic"].number
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE_END], 0)
	check(d["magic"].number == before, "other command spell options do not trigger the penalty")

	# 上一回合用过、这一回合没用 → 不触发
	d = _rin_scene()
	GameLog.set_context(1, "action")
	_use_command_spell_option(0)
	GameLog.set_context(2, "battle")
	before = d["magic"].number
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE_END], 0)
	check(d["magic"].number == before, "last round's command spell does not trigger this round's penalty")

## 铺一局：玩家0 用远坂凛，并把"绝对服从的命令"惩罚效果登记进效果池。
## 令咒是行动阶段的手动能力，所以夹具要先把玩家推进行动阶段
func _rin_scene() -> Dictionary:
	setup()
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX])
	place(MapData.miyama, 0, 0)
	var master = named(GameData.loaded_masters, "tohsaka_rin")
	if master != null:
		var cloned = CloneObject.new().exec(master)
		GameDataManager.get_player_data(0)["master"] = cloned
		for e in cloned._effects:
			EffectManager.register_effect(e, 0)
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE], 0)
	return GameDataManager.get_player_data(0)

## 走真实入口用一枚令咒并选中指定选项（令咒的效果只有一个"使用"效果，选项在其 options 里）
func _use_command_spell_option(option_index: int) -> bool:
	var template = named(LoadCommandSpell.command_spells.values(), "normal_command_spell")
	if template == null:
		return false
	var card = CloneObject.new().exec(template)
	if card == null:
		return false
	var eff: BaseEffect = card._effects[0]
	GameDataManager.get_player_data(0)["command_spell_count"].number = 3
	#手动效果要先登记归属，否则 _trigger_player_id 仍是 -1，发动判据过不去
	EffectManager.register_effect(eff, 0)
	if not EffectManager.request_manual_activation(eff, 0):
		return false
	return EffectManager.submit_option_choice(eff, [option_index])

## 领域外生命：【真名解放】你和降临者各获得合计威力+6，并将此牌加入降临者的弃牌堆。
## 降临者的判定按数据声明的职阶过滤（这里写的是 foreigner），不按名字猜
func test_foreigner_life() -> void:
	# 场上有且只有一名降临者：双方各+6，此牌进该降临者的弃牌堆
	var card = _foreigner_card()
	var d = _foreigner_scene(1, card)
	var eff = _foreigner_effect(card, 0)
	TimePointChecker.dynamic_time_point([TimePoints.TRUE_NAME_RELEASE], 0)
	check(EffectManager.waiting_effect == eff, "foreigner life asks to resolve on true name release")
	EffectManager.submit_active_choice(eff, true)
	check((d["total_power_bonus"] as BaseNumber).number == 6, "the playing player gains six total power")
	check((GameDataManager.get_player_data(1)["total_power_bonus"] as BaseNumber).number == 6, "the foreigner gains six total power")
	check((GameDataManager.get_player_data(1)["discard"] as Array).has(card), "the card joins the foreigner's discard pile")
	check(not (d["played_cards"] as Array).has(card), "the card left the zone it was played from")

	# 场上没有降临者：只有自己+6，牌不搬（没有目标可搬，不能乱搬）
	card = _foreigner_card()
	d = _foreigner_scene(0, card)
	eff = _foreigner_effect(card, 0)
	TimePointChecker.dynamic_time_point([TimePoints.TRUE_NAME_RELEASE], 0)
	EffectManager.submit_active_choice(eff, true)
	check((d["total_power_bonus"] as BaseNumber).number == 6, "the playing player still gains six total power with no foreigner in play")
	check((d["played_cards"] as Array).has(card), "the card stays where it is when no foreigner exists")

	# 场上有多名降临者：归属不唯一，不搬牌也不给这一半加成
	card = _foreigner_card()
	d = _foreigner_scene(2, card)
	eff = _foreigner_effect(card, 0)
	TimePointChecker.dynamic_time_point([TimePoints.TRUE_NAME_RELEASE], 0)
	EffectManager.submit_active_choice(eff, true)
	check((GameDataManager.get_player_data(1)["total_power_bonus"] as BaseNumber).number == 0, "an ambiguous foreigner target grants no power")
	check((d["played_cards"] as Array).has(card), "an ambiguous foreigner target keeps the card in place")

## 领域外生命这张牌（按数据现建，不手搓卡面）
func _foreigner_card():
	return LoadAttack.resolve("special:foreigner_class")

## 铺一局：玩家0 打出领域外生命，场上按 foreigner_count 造出对应数量的降临者
func _foreigner_scene(foreigner_count:int, card) -> Dictionary:
	setup(5)
	place(MapData.miyama, 0, 0)
	for i in range(foreigner_count):
		var owner_id:int = 1 + i
		var servant := BaseServant.new("foreigner_%d" % owner_id, "降临者", "foreigner", "", "")
		GameDataManager.get_player_data(owner_id)["servant"] = servant
	if card != null:
		card._is_activating = true
		GameDataManager.get_player_data(0)["played_cards"] = [card]
	return GameDataManager.get_player_data(0)

## 把领域外生命的效果登记给玩家0（此牌已打出、正在生效）
func _foreigner_effect(card, player_id:int):
	if card == null:
		return null
	for e in card._effects:
		EffectManager.register_effect(e, player_id)
	return card._effects[0] if not (card._effects as Array).is_empty() else null

## 临时 AI 的行为：魔力见底时用令咒换魔力。走真实入口：
## 令咒卡放进 out_of_game.command_spell → AI 请求发动 → 选项由 AI 自己选（默认"获得魔力"）
func test_ai_uses_command_spell() -> void:
	setup()
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 1
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX])
	place(MapData.miyama, 1, 0)
	var bot_data: Dictionary = GameDataManager.get_player_data(1)
	bot_data["magic"].number = 0
	bot_data["command_spell_count"].number = 1
	var template = named(LoadCommandSpell.command_spells.values(), "normal_command_spell")
	var card = CloneObject.new().exec(template)
	check(card != null, "the command spell template is loadable")
	bot_data["out_of_game"]["command_spell"] = [card]
	#真局里令咒在开局就登记给玩家；夹具补上这一步，否则手动发动判据过不去（触发者仍是 -1）
	for e in card._effects:
		EffectManager.register_effect(e, 1)
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE], 1)
	DummyBot.new().use_command_spell_if_needed(1, bot_data)
	check(bot_data["command_spell_count"].number == 0, "the ai spends a command spell when its magic runs out")
	check(bot_data["magic"].number == 4, "the ai takes the gain magic option by default")

func test_shinji_clown_command_spell_floor() -> void:
	for initial in [1, 0]:
		setup(1)
		var template = named(GameData.loaded_masters, "matou_shinji")
		var master = CloneObject.new().exec(template)
		check(master != null, "matou shinji master is loadable")
		if master == null:
			return
		GameDataManager.get_player_data(0).master = master
		GameDataManager.get_player_data(0).command_spell_count.number = initial
		EffectManager.register_effects(master._effects, 0)
		TimePointChecker.dynamic_time_point([TimePoints.BATTLE_LOSE], 0)
		check(GameDataManager.get_player_data(0).command_spell_count.number == max(initial - 1, 0),
			"shinji clown never reduces command spells below zero from %d" % initial)


func test_missing_dynamic_play_targets_are_safe() -> void:
	setup(1)
	check(PlayAttack.new().exec(null) == false, "play attack safely rejects a missing target")
	check(PlaySkill.new().exec(null) == false, "play skill safely rejects a missing target")
	check(AddAttack.new().exec(null) == false, "add attack safely rejects a missing target")
	check(AddSkill.new().exec(null) == false, "add skill safely rejects a missing target")
	check(GameLog.query({"type":"play"}, null).is_empty(), "missing dynamic targets produce no play facts")

func test_unlimited_blade_works_play_range() -> void:
	setup(1)
	var d:Dictionary = GameDataManager.get_player_data(0)
	var card = skill_card("emiya", "unlimited_blade_works")
	check(card != null, "unlimited blade works is loadable")
	if card == null:
		return
	d.played_cards = [card]
	d.hand_cards = [BaseAttack.new("reserve", "", [], BaseNumber.new(0), BaseNumber.new(1))]
	for effect in card._effects:
		EffectManager.register_effect(effect, 0)
	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], 0, card)
	check(EffectManager.waiting_effect == null and d.play_limit.number == 2,
		"an inactive servant skill does not trigger or announce its effects")
	card._is_activating = true
	var other := BaseAttack.new("other", "", [], BaseNumber.new(0), BaseNumber.new(1))
	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], 0, other)
	check(EffectManager.waiting_effect == null, "another played card does not open unlimited blade works")
	check(d.play_limit.number == 2 and d.regular_play_min.number == 2 and d.can_draw_card,
		"another played card does not activate unlimited blade works")
	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], 0, card)
	check(EffectManager.waiting_effect == card._effects[0], "unlimited blade works asks for its hand rebuild")
	check(EffectManager.submit_active_choice(card._effects[0], true), "unlimited blade works hand rebuild decision resolves")
	check(d.play_limit.number == 4 and d.regular_play_min.number == 0 and not d.can_draw_card,
		"unlimited blade works declares zero to four cards and disables drawing")
	d.hand_cards.clear()
	TimePointChecker.dynamic_time_point([TimePoints.PREPARE_PHASE], 0)
	check(d.play_limit.number == 2 and d.regular_play_min.number == 2 and d.can_draw_card,
		"closing unlimited blade works restores normal play and drawing")
	check(card._is_closed, "unlimited blade works closes after the hand becomes empty")

func _ready() -> void:
	call_deferred("run")

## 十二试炼：卡面印的是"【真名解放】若你战败，获得3点战果并令此战斗的所有胜者分别失去3点战果，
## 然后将此牌移除游戏并令你的其他【十二试炼】获得+3威力直至游戏结束"。
## 真打一场败仗（BATTLE_LOSE 与"本场胜者"都由 BattleResolver 记录），逐条核对卡面四件事。
## "你的其他【十二试炼】"覆盖仍在技能区的副本与已经打出的副本，且只认这个名字
func test_twelve_labors_defeat_bonus() -> void:
	setup(2)
	place(MapData.miyama, 0, 0)
	place(MapData.miyama, 1, 1)
	var d:Dictionary = GameDataManager.get_player_data(0)
	var source = skill_card("heracles", "twelve_labors")
	var in_play = skill_card("heracles", "twelve_labors")
	var in_zone = skill_card("heracles", "twelve_labors")
	var unrelated = BaseSkill.new("别的技能", "", [], BaseNumber.new(1), BaseNumber.new(4))
	d.played_cards = [source, in_play]
	d.servant_skills = [in_zone, unrelated]
	# 本用例只登记来源效果，隔离验证一次战败链；场上夹具仍须处于真实激活态。
	source._is_activating = true
	in_play._is_activating = true
	source._is_concealed = false
	in_play._is_concealed = false
	d.power.number = source._power.number + in_play._power.number
	GameDataManager.get_player_data(1).power.number = d.power.number + 9
	for effect in source._effects:
		EffectManager.register_effect(effect, 0)
	var battle:Dictionary = BattleResolver.new().exec([0, 1])
	var winners:Array = (battle.get("winners_by_area", {}) as Dictionary).get(MapData.miyama._area_name, [])
	check(winners.has(1) and not winners.has(0), "twelve labors fixture really loses the battle")
	check(d.score.number == 3, "the defeated owner gains three score")
	# 胜者失去3点战果：读记录下来的那笔扣减，不看绝对值（战斗本身会给胜者发战果）
	var drop:Array = GameLog.query({"type": "score_decrease", "actor": 1}, 0)
	check(drop.size() == 1 and int((drop[0].get("data", {}) as Dictionary).get("delta", 0)) == -3,
		"the battle winner loses three score")
	check(not d.played_cards.has(source), "the defeated card is removed from play")
	check((in_play._power as BaseNumber).number == 8, "a copy already in play gains three power")
	check((in_zone._power as BaseNumber).number == 8, "a copy still in the skill zone gains three power")
	check((unrelated._power as BaseNumber).number == 4, "a skill of another name gains nothing")

func run() -> void:
	test_pierce_heart_defeat()
	test_swallow_reversal_combo()
	test_rule_breaker()
	test_rule_breaker_after_prior_action_effect()
	test_rin_absolute_order()
	test_foreigner_life()
	test_ai_uses_command_spell()
	test_shinji_clown_command_spell_floor()
	test_missing_dynamic_play_targets_are_safe()
	test_unlimited_blade_works_play_range()
	test_twelve_labors_defeat_bonus()
	print("RESULT checks=", checks, " failures=", failures)
	var f := FileAccess.open("res://card_effect_runtime_result.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks": checks, "failures": failures}))
	f.close()
	get_tree().quit(0 if failures.is_empty() else 1)
