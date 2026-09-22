extends Node
# 战斗阶段「主动能力」的可用性回归。
# 卡面口径（用户确认）：
#   「被动/战斗阶段：」= 这张牌【不激活也能用】的主动能力（need_activate=false）
#   「战斗阶段：」    = 这张牌【必须先激活】才能用的主动能力（need_activate=true）
# 两者都是主动：玩家在战斗阶段点牌发动，而不是由引擎自动执行。
# 历史缺陷：它们被写成 is_pure_passive:true（自动生效），玩家既看不到也点不着，
# 表现就是"战斗阶段可以使用的效果无法使用，被直接跳过"。
var failures:Array=[]
var checks:int=0
var host:Node=null
var local:int=0

func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)

func _ready(): call_deferred("run")

## 进入「自己的战斗阶段」窗口：主动能力的发动时机就是阶段窗口
func open_battle_window() -> void:
	GameProgress.current_phase_index=3
	GameProgress.current_player_id=local
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE,
		TimePoints.BATTLE_PHASE, TimePoints.NON_CLIMAX])
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], local)

## 按效果名在一张牌的效果里找一条
func effect_named(card, effect_name:String):
	for eff in card.get("_effects"):
		if eff != null and str(eff._name) == effect_name:
			return eff
	return null

func run():
	host=load("res://assets/scenes/game_scene/tactical_board_ui.tscn").instantiate()
	get_tree().root.add_child(host)
	host.set_process(false)
	local=GameData.player_id
	var d:Dictionary=GameData.player_data_library[local]
	# 开局随机抽到的局势牌可能带「宝具禁止使用」，本用例要经真实入口打出宝具攻击，
	# 先把这类禁令移出局面（用例验证的是战斗阶段能力，不是禁令叠加）
	MapData.active_situation=null
	check(not BoardHasEffect.new().exec(ForbidNoblePhantasmEffect.EFFECT_NAME),
		"the fixture runs without a noble-phantasm prohibition")
	var mana_resistance=null
	for skill in d.servant_skills:
		if effect_named(skill, "np_bloom_score") != null:
			mana_resistance=skill
			break
	check(mana_resistance != null, "the mana-resistance skill is dealt to the player")
	var passive_ability=effect_named(mana_resistance, "np_bloom_score")
	var active_ability=effect_named(mana_resistance, "zero_opponent_magic_power")
	check(passive_ability != null and active_ability != null, "both printed abilities are loaded")
	check(passive_ability._is_manual and active_ability._is_manual,
		"both printed abilities are player-activated, not engine-driven")
	check(passive_ability._need_activate == false, "the 被动/ ability needs no activation")
	check(active_ability._need_activate == true, "the bare 战斗阶段 ability needs activation")
	check(passive_ability._time_points.has(TimePoints.SELF_PREFIX + TimePoints.BATTLE_PHASE),
		"both abilities fire during the battle phase")

	open_battle_window()
	# 宝具绽放的卡面条件是"本回合打出了魔力消耗最高的宝具攻击"：先经真实入口把最高费用的
	# 宝具打出，条件才成立；这与"牌要不要先激活"是两件独立的事。
	d.magic.set_num(BaseNumber.new(20))
	var priciest:BaseSkill=null
	for skill in d.servant_skills:
		if skill.has_attribute(Attributes.NOBLE_PHANTASM):
			if priciest == null or skill._cost.number > priciest._cost.number:
				priciest=skill
	check(priciest != null, "the servant owns a noble-phantasm attack for the fixture")
	if priciest != null:
		check(PlaySkill.new().exec(priciest, local, true), "the priciest noble phantasm is played for the fixture")
	# —— 牌还没激活：只有「被动/」那条能用 ——
	mana_resistance.set("_is_activating", false)
	check(EffectManager.can_manual_activate(passive_ability, local),
		"the 被动/ ability can be used while the card is not activated")
	check(not EffectManager.can_manual_activate(active_ability, local),
		"the 战斗阶段 ability is refused while the card is not activated")
	check(EffectManager.has_manual_activation(local),
		"the player has something to activate in the battle phase")

	# —— 牌激活之后：两条都能用 ——
	mana_resistance.set("_is_activating", true)
	check(EffectManager.can_manual_activate(active_ability, local),
		"the 战斗阶段 ability can be used once the card is activated")

	# —— 界面必须停下来等他点，而不是直接跳过 ——
	var before:int=GameProgress.current_player_id
	host._check_and_step_ai(0.0)
	check(GameProgress.current_player_id == before,
		"the board stops on the local player instead of skipping his battle phase")
	check(EffectManager.waiting_effect != null,
		"the board opens a prompt for the available battle ability")
	if EffectManager.waiting_effect != null:
		EffectManager.submit_active_choice(EffectManager.waiting_effect, false)

	# —— 没有可发动能力时照常自动推进（不能把回合卡住）——
	mana_resistance.set("_is_activating", false)
	check(not EffectManager.can_manual_activate(active_ability, local),
		"the ability is no longer offered once the card is deactivated again")
	# 把两条能力都排除后，战斗阶段应恢复自动跳过
	# 把本地玩家此刻所有可发动能力一并排除，构造"确实没有可做的事"的局面。
	# 不能只排除对魔力那两条：打出宝具后它自带的战斗阶段能力也会进入可发动列表
	for eff in EffectManager.manual_activations(local):
		eff._trigger_player_id = -1
	check(not EffectManager.has_manual_activation(local),
		"nothing to activate once the abilities belong to nobody")
	host._check_and_step_ai(0.0)
	check(GameProgress.current_player_id != before,
		"the battle phase still advances automatically when there is nothing to activate")

	print("RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
