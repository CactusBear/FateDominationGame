extends Node
# 持续阶段窗口的结算去重回归。
# 现象：言峰绮礼的「执行者 - 战斗阶段：你的总威力+2」在同一个战斗阶段里叠到 8 点。
# 根因：self_battle_phase 这类【持续窗口】派发后会一直留在玩家的时点表里，直到阶段轮转
# 才被清掉；同一阶段内后续每个批次（战力结算、事件进场、战后选择…）都会再命中它，
# 于是自动加成被反复执行。修法是按"同一窗口内只结算一次"过滤持续窗口时点，
# 瞬时时点（PLAYED_CARD、MAGIC_ADD…）仍然每次命中都算。
#
# 夹具用自建效果而不是言峰那条：卡面口径已确认「战斗阶段：」是主动能力（is_manual），
# 它不再走自动结算，拿它当自动效果的样本会让这条引擎机制的回归跟着角色数据一起失效。
var failures:Array=[]
var checks:int=0

func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)

func _ready(): call_deferred("run")

func setup() -> void:
	EffectManager.reset_runtime(); GameLog.reset(); GameLog.set_context(1,"battle")
	GameProgress.is_game_over=false
	GameProgress.current_round=1
	GameProgress.current_phase_index=3
	GameProgress.current_player_id=0
	GameData.player_data_library.clear()
	for i in range(2):
		GameData.player_data_library[i]=GameData.new_player_data()
		var d:Dictionary=GameData.player_data_library[i]
		d.is_out=false
		d.order.set_num(BaseNumber.new(i))
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE,
		TimePoints.BATTLE_PHASE, TimePoints.NON_CLIMAX])

## 一个"战斗阶段：你的总威力+2"形状的自动效果（不要求激活，进自动结算）
func make_battle_bonus(effect_name:String) -> BaseEffect:
	var eff:=BaseEffect.new(effect_name,[TimePoints.SELF_PREFIX + TimePoints.BATTLE_PHASE],0,true,false)
	eff._need_activate=false
	eff.numbers=[BaseNumber.new(2)]
	#手工构造的效果也要把 numbers 接给 _using_numbers：number_index 是从它取值的，
	#正常加载路径由 load_helper 负责这一步，漏了会让参数解析成 null（静默不生效）
	eff._using_numbers=eff.numbers
	eff._funcs=LoadHelper.load_funcs([{"func_name":"edit_data_number",
		"parameters":["total_power_bonus",null,{"number_index":0}],"var_index":-1}],eff)
	return eff

func bonus_of(player_id:int) -> float:
	return float(GetPlayerTotalPower.breakdown(player_id).get("bonus", 0.0))

func run():
	# —— ① 同一窗口内只结算一次 ——
	setup()
	var effect:=make_battle_bonus("probe_battle_bonus")
	EffectManager.register_effect(effect, 0)

	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], 0)
	check(bonus_of(0) == 2.0, "the battle phase window applies its bonus once")
	# 同一窗口内的后续批次：战力结算、战后时点都还会命中这个持续窗口
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_RESOLVE], 0)
	check(bonus_of(0) == 2.0, "a battle resolve batch does not apply it again")
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_END], 0)
	check(bonus_of(0) == 2.0, "a battle end batch does not apply it again")
	EffectManager.run_time_point()
	check(bonus_of(0) == 2.0, "rerunning the pipeline inside the window does not stack")

	# —— ② 窗口轮转后必须能重新结算（否则第二个玩家的阶段能力会被当成已用过）——
	TimePointChecker.clear_player_scope_time_points()
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], 0)
	check(bonus_of(0) == 4.0, "a rotated window settles again")

	# —— ③ 另一个玩家在自己的窗口里照常结算 ——
	# 同一效果的实例只能属于一个玩家（register_effect 会写 _trigger_player_id），
	# 给第二个人要用另一个实例，不能共用同一条
	setup()
	EffectManager.register_effect(make_battle_bonus("probe_battle_bonus_a"), 0)
	EffectManager.register_effect(make_battle_bonus("probe_battle_bonus_b"), 1)
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], 0)
	check(bonus_of(0) == 2.0, "the acting player settles in its own window")
	check(bonus_of(1) == 0.0, "a non-acting player is untouched by another player's window")
	TimePointChecker.clear_player_scope_time_points()
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], 1)
	check(bonus_of(1) == 2.0, "the next player settles in its own window")

	# —— ④ 反例：瞬时时点仍然每次命中都算 ——
	setup()
	var listener:=BaseEffect.new("repeat_listener",[TimePoints.PLAYED_CARD],0,true,false)
	listener._need_activate=false
	listener._funcs=LoadHelper.load_funcs([{"func_name":"do_nothing","parameters":[],"var_index":-1}],listener)
	EffectManager.register_effect(listener, 0)
	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], 0)
	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], 0)
	check(GameLog.query({"type":"effect","actor":0,"data":{"effect_name":"repeat_listener"}},0).size()==2,
		"instant time points still settle on every occurrence")

	# —— ⑤ 反例：不属于当前窗口的阶段时点不该被结算 ——
	setup()
	EffectManager.register_effect(make_battle_bonus("probe_battle_bonus_c"), 0)
	TimePointChecker.dynamic_time_point([TimePoints.OUTPOST_PHASE], 0)
	check(bonus_of(0) == 0.0, "a window of another phase never settles")

	print("RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
