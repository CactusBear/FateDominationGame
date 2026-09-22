extends Node
# 宝具绽放（对魔力牌的第一条能力）的回归。
# 卡面：宝具绽放-被动/战斗阶段：若你于本回合打出了你战斗中魔力消耗最高的宝具攻击，
#       获得1点战果。若其消耗≥4，你额外获得1点战果。
# 原先效果体是 do_nothing（占位），本轮按卡面补全。
# 关键事实：Saber 的宝具攻击（誓约胜利之剑 / 风王结界）是【技能牌】形式、平时待在技能区，
# 所以"你战斗中魔力消耗最高的宝具攻击"必须把技能区一并算进来。
# 次数：卡面没写次数，但它是玩家可以反复点的主动能力，不做限制就能在同一回合刷战果；
# 用"一条效果 + 一个选项 + max_total_uses:1 + 每回合重置"表达"每回合至多一次"，
# 这条路径会记用量（无选项效果不会记，max_total_uses 对它们无效）。
var failures:Array=[]
var checks:int=0
var host:Node=null
var local:int=0

func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)

func _ready(): call_deferred("run")

func np_cards_in(cards:Array) -> Array:
	var got:Array=[]
	for card in cards:
		if card is BaseCard and card.has_attribute(Attributes.NOBLE_PHANTASM):
			got.append(card)
	return got

func priciest(cards:Array):
	var best=null
	for card in cards:
		if best == null or (card._cost as BaseNumber).number > (best._cost as BaseNumber).number:
			best=card
	return best

## 该玩家持有的全部牌区（含技能区——宝具攻击以技能牌形式待在技能区）
func all_cards(d:Dictionary) -> Array:
	var pool:Array=[]
	pool.append_array(d.deck)
	pool.append_array(d.hand_cards)
	pool.append_array(d.played_cards)
	pool.append_array(d.discard)
	pool.append_array(d.servant_skills)
	pool.append_array(d.master_skills)
	return pool

## 真实发动一次：请求 → 选项 → 结算
func activate(eff:BaseEffect) -> bool:
	if not EffectManager.request_manual_activation(eff, local):
		return false
	return EffectManager.submit_option_choice(eff, [0])

func run():
	host=load("res://assets/scenes/game_scene/tactical_board_ui.tscn").instantiate()
	get_tree().root.add_child(host)
	host.set_process(false)
	local=GameData.player_id
	var d:Dictionary=GameData.player_data_library[local]
	d.magic.set_num(BaseNumber.new(20))
	# 开局随机抽到的局势牌可能带「宝具禁止使用」，本用例要经真实入口打出宝具攻击，
	# 先把这类禁令移出局面（用例验证的是宝具绽放，不是禁令叠加）
	MapData.active_situation=null
	check(not BoardHasEffect.new().exec(ForbidNoblePhantasmEffect.EFFECT_NAME),
		"the fixture runs without a noble-phantasm prohibition")

	var np_all:Array=np_cards_in(all_cards(d))
	check(np_all.size() >= 2, "the servant owns noble-phantasm attacks")
	var best=priciest(np_all)
	var second=null
	for card in np_all:
		if card != best and (second == null or (card._cost as BaseNumber).number > (second._cost as BaseNumber).number):
			second=card
	check(best != null and second != null, "there are a priciest and a cheaper noble phantasm")
	print("   priciest=", best.get_shown_name(), " cost=", (best._cost as BaseNumber).number,
		" | cheaper=", second.get_shown_name(), " cost=", (second._cost as BaseNumber).number)

	var eff:BaseEffect=null
	for skill in d.servant_skills:
		for e in skill._effects:
			if e != null and str(e._name) == "np_bloom_score":
				eff=e
	check(eff != null, "the 宝具绽放 ability is loaded")
	check(eff._is_manual and eff._need_activate == false,
		"it is player-activated and needs no activation")
	check(eff.has_options(), "it is expressed as one option so its use can be counted per round")

	# 进入自己的战斗阶段
	GameProgress.current_phase_index=3
	GameProgress.current_player_id=local
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE,
		TimePoints.BATTLE_PHASE, TimePoints.NON_CLIMAX])
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], local)
	check(not EffectManager.can_manual_activate(eff, local),
		"the ability stays out of the prompt while no noble phantasm was played")

	# —— 反例①：本回合什么都没打出 —— 条件不满足，能力不进入询问，也不弹窗
	d.played_cards.clear()
	EffectManager.reset_round_option_counts()
	var before:int=d.score.number
	check(not EffectManager.is_option_available(eff, 0), "no option is offered without a played noble phantasm")
	check(not EffectManager.can_manual_activate(eff, local),
		"the ability is not offered at all when its condition is unmet")
	check(not activate(eff), "the ability cannot be resolved with nothing played")
	check(d.score.number == before, "no score when no noble phantasm was played this turn")

	# —— 反例②：打出的是更便宜的那张宝具（风王结界）—— 同样不该提示
	d.played_cards.clear()
	# 第 3 个参数跳过"必须由效果触发"的限制：PlaySkill 平时只在效果链里被调用
	check(PlaySkill.new().exec(second, local, true), "the cheaper noble phantasm is played through the real entry")
	check(d.played_cards.has(second), "playing it puts it in the played area")
	EffectManager.reset_round_option_counts()
	before=d.score.number
	check(not EffectManager.is_option_available(eff, 0),
		"a cheaper noble phantasm does not offer the ability")
	check(not EffectManager.can_manual_activate(eff, local),
		"a cheaper noble phantasm keeps the ability out of the prompt queue")
	check(not activate(eff), "the ability cannot be resolved with the cheaper noble phantasm played")
	check(d.score.number == before, "a cheaper noble phantasm does not score")

	# —— 正例：打出魔力消耗最高的宝具攻击 ——
	d.played_cards.clear()
	check(PlaySkill.new().exec(best, local, true), "the priciest noble phantasm is played through the real entry")
	check(d.played_cards.has(best), "playing the priciest one puts it in the played area")
	EffectManager.reset_round_option_counts()
	check(EffectManager.is_option_available(eff, 0), "the priciest noble phantasm offers the ability")
	check(EffectManager.can_manual_activate(eff, local), "the ability can be activated in the battle phase")
	before=d.score.number
	var expect:int = 2 if (best._cost as BaseNumber).number >= 4 else 1
	check(activate(eff), "the ability resolves with the priciest noble phantasm played")
	check(d.score.number == before + expect,
		"the priciest noble phantasm scores %d point(s)" % expect)

	# —— 反例③：同一回合不能再发动一次（否则可以反复点着刷战果）——
	var after_first:int=d.score.number
	check(not activate(eff), "a second activation in the same round is refused")
	check(d.score.number == after_first, "the refused activation scores nothing")

	# —— 新回合恢复可用 ——
	EffectManager.reset_round_option_counts()
	check(activate(eff), "a new round offers the ability again")

	print("RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
