extends Node
# 「一之太刀」的实现回归。
# 卡面：战斗阶段：关闭此牌，然后从手牌打出一张力量基础攻击。
#       若如此，获得2点魔力且关闭一名交战玩家至多一张基础攻击。
# 一个选项只能声明一个 select_cards，所以两条半句各自成一条效果：
# ①挑自己手牌里的力量基本攻击 → 打出 → 获得2点魔力（每回合一次，否则能反复刷魔力）
# ②指定一名同战场玩家 → 挑他至多一张基础攻击关闭 → 最后由它关闭此牌
#   （"关闭此牌"放在②：放①会先关掉自己，而②要求牌处于激活状态）
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

func effect_named(effs:Array, key:String):
	for e in effs:
		if e != null and str(e._name) == key:
			return e
	return null

func setup() -> void:
	EffectManager.reset_runtime(); GameLog.reset(); GameLog.set_context(1,"battle")
	GameData.player_data_library.clear()
	for i in range(2):
		var d:Dictionary=GameData.new_player_data()
		d.is_out=false
		d.order.set_num(BaseNumber.new(i))
		d.magic.set_num(BaseNumber.new(10))
		GameData.player_data_library[i]=d
	GameProgress.is_game_over=false
	GameProgress.current_round=1
	GameProgress.current_phase_index=3
	GameProgress.current_player_id=0
	#两名玩家放到同一战场："交战玩家"的候选集来自同战场，没有位置时候选为空、选项不可选
	var area:BaseMapArea = MapData.areas[1]
	for i in range(2):
		SetLocation.new().exec(area._locations[i], i, false, true)
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE,
		TimePoints.BATTLE_PHASE, TimePoints.NON_CLIMAX])
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], 0)

## 把佐佐木的技能牌克隆给指定玩家并登记其效果（与真实发牌同一条路）
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
	if cloned is BaseHandCard:
		cloned._is_activating = true
	GameData.player_data_library[player_id].servant_skills.append(cloned)
	for e in cloned._effects:
		EffectManager.register_effect(e, player_id)
	return cloned._effects

func make_hand_card(key:String) -> BaseCard:
	var tpl = LoadAttack.resolve(key)
	if tpl == null:
		return null
	return CloneObject.new().exec(tpl)

func run():
	# —— ① 两条效果都在，且都是主动、需要激活 ——
	setup()
	var effs:Array=register_skill_effects("sasaki_kojirou", "ichi_no_tachi", 0)
	var e1=effect_named(effs, "ichi_no_tachi_close_and_play_strength")
	var e2=effect_named(effs, "ichi_no_tachi_close_engaged_attack")
	check(e1 != null and e2 != null, "both halves of 一之太刀 are loaded")
	check(e1._is_manual and e1._need_activate, "playing a card is player-activated and needs activation")
	check(e2._is_manual and e2._need_activate, "closing an opponent's card is the same")

	# —— ② 候选只含力量基本攻击 ——
	setup()
	var effs2:Array=register_skill_effects("sasaki_kojirou", "ichi_no_tachi", 0)
	var play_eff=effect_named(effs2, "ichi_no_tachi_close_and_play_strength")
	var strength_card=make_hand_card("strength:2")
	var agility_card=make_hand_card("agility:2")
	check(strength_card != null and agility_card != null, "fixture cards are resolvable")
	GameData.player_data_library[0].hand_cards.append(strength_card)
	GameData.player_data_library[0].hand_cards.append(agility_card)

	check(EffectManager.request_manual_activation(play_eff, 0), "the ability can be requested")
	check(EffectManager.submit_option_choice(play_eff, [0]), "the option is accepted")
	var pending:Dictionary=EffectManager.get_pending_card_selection()
	var candidates:Array=pending.get("cards", [])
	check(candidates.has(strength_card), "a strength base attack is offered")
	check(not candidates.has(agility_card), "a non-strength card is not offered")

	# —— ③ 打出选中的牌并拿到 2 点魔力 ——
	var magic_before:int=GameData.player_data_library[0].magic.number
	check(EffectManager.submit_card_selection(play_eff, [strength_card]), "picking the strength card is accepted")
	check(GameData.player_data_library[0].magic.number == magic_before + 2, "it grants 2 magic")
	check(GameData.player_data_library[0].played_cards.has(strength_card), "the picked card is played")

	# 每回合一次，否则可以反复发动刷魔力。
	# 次数上限在"能不能选"这一层把关：本回合已用完时不再入队询问
	# （不可用的能力不该弹出窗口让玩家点一个选不了的选项）
	check(not EffectManager.request_manual_activation(play_eff, 0),
		"a second request in the same round is refused instead of queued")
	check(not EffectManager.submit_option_choice(play_eff, [0]),
		"a second submission in the same round is refused")
	EffectManager.reset_round_option_counts()
	check(EffectManager.request_manual_activation(play_eff, 0), "a new round offers it again")
	EffectManager.submit_active_choice(play_eff, false)

	# —— ④ 关闭一名交战玩家的基础攻击，并由它收尾关闭此牌 ——
	setup()
	var effs3:Array=register_skill_effects("sasaki_kojirou", "ichi_no_tachi", 0)
	var lock_eff=effect_named(effs3, "ichi_no_tachi_close_engaged_attack")
	var my_skill_card=lock_eff.from.get_ref() if lock_eff.from is WeakRef else lock_eff.from
	var victim_card=make_hand_card("strength:2")
	GameData.player_data_library[1].played_cards.append(victim_card)

	check(EffectManager.request_manual_activation(lock_eff, 0), "closing an opponent card can be requested")
	check(EffectManager.submit_option_choice(lock_eff, [0]), "the option is accepted")
	check(EffectManager.waiting_players == lock_eff, "it asks for a player target first")
	check(EffectManager.submit_player_selection(lock_eff, [1]), "the player target is accepted")
	check(EffectManager.waiting_selection == lock_eff, "then it asks which card of his")

	var pending2:Dictionary=EffectManager.get_pending_card_selection()
	check((pending2.get("cards", []) as Array).has(victim_card), "his played cards are offered")
	check(EffectManager.submit_card_selection(lock_eff, [victim_card]), "closing his card is accepted")
	check(victim_card._is_closed, "the chosen card is closed")
	check(my_skill_card._is_closed, "the ability closes its own card at the end")

	print("RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
