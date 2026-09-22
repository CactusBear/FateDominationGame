extends Node
# 「万符必应破戒」（美狄亚）的效果体回归——原先 funcs 为空。
# 卡面：「【真名解放】〈每局游戏限一次〉行动阶段：你所在战场的一名玩家失去一枚令咒，
#        若其原本只有一枚或更少的令咒，令其【败北】。若其原本没有令咒，你总威力+10」
# 注：言峰的「恶之守护者」虽然形态相似，但它挂在 upgrade_skill 下（升华技），不在本轮范围。
var failures:Array=[]
var checks:int=0

func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)

func _ready(): call_deferred("run")

func effect_named(effs:Array, key:String):
	for e in effs:
		if e != null and str(e._name) == key:
			return e
	return null

## 在全部已加载的御主/从者里找到含指定效果的技能牌，克隆给玩家并登记（与真实发牌同一条路）。
## 按效果名查找而不是按牌名：牌的 _name 取自 skill_name/card_name，写死牌名容易对不上
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


## 把御主自带的某个 buff 克隆给玩家（返回该 buff 的效果数组）
func register_buff_effect(master_key:String, buff_name:String, player_id:int) -> Array:
	for m in GameData.loaded_masters:
		if m == null or str(m._name) != master_key:
			continue
		for buff in m._specials.get("BUFFS", []):
			if buff == null or str(buff._name) != buff_name:
				continue
			var cloned = CloneObject.new().exec(buff)
			if cloned == null:
				continue
			GameData.player_data_library[player_id].buffs.append(cloned)
			for e in cloned._effects:
				EffectManager.register_effect(e, player_id)
			return cloned._effects
	return []


func setup() -> void:
	EffectManager.reset_runtime(); GameLog.reset(); GameLog.set_context(1,"action")
	GameData.player_data_library.clear()
	for i in range(2):
		var d:Dictionary=GameData.new_player_data()
		d.is_out=false
		d.order.set_num(BaseNumber.new(i))
		d.magic.set_num(BaseNumber.new(20))
		GameData.player_data_library[i]=d
	GameProgress.is_game_over=false
	GameProgress.current_round=1
	GameProgress.current_phase_index=2
	GameProgress.current_player_id=0
	# 两名玩家放到同一战场：两条卡面的目标都是"你所在战场的一名玩家"
	var area:BaseMapArea = MapData.areas[1]
	for i in range(2):
		SetLocation.new().exec(area._locations[i], i, false, true)
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE,
		TimePoints.BATTLE_PHASE, TimePoints.NON_CLIMAX])
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE, TimePoints.BATTLE_PHASE], 0)

func run():
	# —— ① 万符必应破戒：目标原有 2 枚令咒 → 只失去 1 枚，不败北 ——
	setup()
	var eff3=register_skill_by_effect("rule_breaker_remove_command_spell", 0)
	check(eff3 != null, "the 万符必应破戒 ability is loaded")
	GameData.player_data_library[1].command_spell_count.set_num(BaseNumber.new(2))
	check(EffectManager.request_manual_activation(eff3, 0), "it can be requested in the action phase")
	check(EffectManager.submit_option_choice(eff3, [0]), "the option is accepted")
	check(EffectManager.submit_player_selection(eff3, [1]), "the target is accepted")
	check(GameData.player_data_library[1].command_spell_count.number == 1, "the target loses one command spell")
	check(DefeatBuff.get_defeat_count(1) == 0, "having two spells, he is not defeated")
	check(GameData.player_data_library[0].total_power_bonus.number == 0, "and the caster gains no power")

	# —— ② 目标原本只有 1 枚 → 失去后为 0，令其【败北】——
	setup()
	var eff4=register_skill_by_effect("rule_breaker_remove_command_spell", 0)
	GameData.player_data_library[1].command_spell_count.set_num(BaseNumber.new(1))
	EffectManager.request_manual_activation(eff4, 0)
	EffectManager.submit_option_choice(eff4, [0])
	EffectManager.submit_player_selection(eff4, [1])
	check(GameData.player_data_library[1].command_spell_count.number == 0, "his last command spell is taken")
	check(DefeatBuff.get_defeat_count(1) == 1, "having only one, he is defeated")

	# —— ③ 目标原本没有令咒 → 自己总威力+10，且令咒不会被压成负数 ——
	setup()
	var eff5=register_skill_by_effect("rule_breaker_remove_command_spell", 0)
	GameData.player_data_library[1].command_spell_count.set_num(BaseNumber.new(0))
	EffectManager.request_manual_activation(eff5, 0)
	EffectManager.submit_option_choice(eff5, [0])
	EffectManager.submit_player_selection(eff5, [1])
	check(GameData.player_data_library[1].command_spell_count.number == 0, "his zero spells are not pushed negative")
	# 卡面「只有一枚或更少」包含 0 枚：没有令咒同样满足败北条件，
	# 并且额外触发「若其原本没有令咒，你总威力+10」——两条并存
	check(DefeatBuff.get_defeat_count(1) == 1, "zero spells still meets the one-or-fewer clause")
	check(GameData.player_data_library[0].total_power_bonus.number == 10, "the caster gains 10 total power")

	print("RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
