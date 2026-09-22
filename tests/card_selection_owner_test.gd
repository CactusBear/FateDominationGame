extends Node
# 方案A：选项级 select_cards 的"挑谁的牌" + 两级延迟输入回归。
# 背景：卡面「关闭一名交战玩家至多一张基础攻击」要求玩家先指定玩家、再挑那名玩家的牌。
# 引擎侧三处改动：owner 声明（target_player 取先选定的玩家）、
# 提交顺序（选玩家必须排在选牌前，否则先停下等选牌却没有目标）、
# 未声明 owner 时保持原语义（挑触发者自己的牌）——最后一条是既有卡不受影响的保证。
var failures:Array=[]
var checks:int=0

func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)

func _ready(): call_deferred("run")

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
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE,
		TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX])

## 构造带一条选项的手动效果；选项内容由调用方声明
func make_effect(effect_name:String, option:Dictionary) -> BaseEffect:
	var eff:=BaseEffect.new(effect_name,[TimePoints.SELF_PREFIX + TimePoints.ACTION_PHASE],0,false,false)
	eff._is_manual=true
	eff._need_activate=false
	eff._max_choices=1
	eff._options=[option]
	return eff

## 造一张牌当手牌用（属性:威力）。必须克隆成独立实例：
## resolve 取到的是同一张牌对象，两个玩家共用它会让"来源区"校验失去区分度
func make_card() -> BaseCard:
	var tpl = LoadAttack.resolve("strength:2")
	if tpl == null:
		push_error("fixture could not resolve a base attack")
		return null
	return CloneObject.new().exec(tpl)

func open_window() -> void:
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE,
		TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX])
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE], 0)

func run():
	# —— ① 同时声明 select_players + select_cards(owner=target_player) ——
	setup()
	var mine:BaseCard=make_card()
	var theirs:BaseCard=make_card()
	GameData.player_data_library[0].hand_cards.append(mine)
	GameData.player_data_library[1].hand_cards.append(theirs)

	var eff:=make_effect("probe_two_stage", {
		"shown_option_name":"测试：选一名玩家再挑他一张牌",
		"select_players":{"candidates":[{"func_name":"get_active_players_id","parameters":[],"var_index":-1}],
			"min":1,"max":1},
		"select_cards":{"source":"hand_cards","owner":"target_player","min":1,"max":1},
		"funcs":[]
	})
	EffectManager.register_effect(eff, 0)
	open_window()
	check(EffectManager.request_manual_activation(eff, 0), "the ability can be requested")
	check(EffectManager.submit_option_choice(eff, [0]), "the option is accepted")

	# 先等选玩家，不是先等选牌（顺序反了会先停下等选牌却没有目标）
	check(EffectManager.waiting_players == eff, "it waits for a player target first")
	check(EffectManager.waiting_selection == null, "it does not wait for cards yet")

	check(EffectManager.submit_player_selection(eff, [1]), "the player target is accepted")
	check(EffectManager.waiting_selection == eff, "then it waits for cards")

	var pending:Dictionary=EffectManager.get_pending_card_selection()
	check((pending.get("cards", []) as Array).has(theirs), "the candidates come from the chosen player")
	check(not (pending.get("cards", []) as Array).has(mine), "not from the activator")

	# 正例：挑目标玩家的牌
	check(EffectManager.submit_card_selection(eff, [theirs]), "a card of the chosen player is accepted")
	check((eff._selected_cards as Array).has(theirs), "the chosen card is recorded")
	check(eff._selected_player == 1, "the chosen player is recorded")

	# —— ② 反例：提交触发者自己的牌必须被拒（它不在来源区里）——
	setup()
	var mine2:BaseCard=make_card()
	var theirs2:BaseCard=make_card()
	GameData.player_data_library[0].hand_cards.append(mine2)
	GameData.player_data_library[1].hand_cards.append(theirs2)
	var eff2:=make_effect("probe_two_stage_b", {
		"shown_option_name":"测试：反例",
		"select_players":{"candidates":[{"func_name":"get_active_players_id","parameters":[],"var_index":-1}],
			"min":1,"max":1},
		"select_cards":{"source":"hand_cards","owner":"target_player","min":1,"max":1},
		"funcs":[]
	})
	EffectManager.register_effect(eff2, 0)
	open_window()
	EffectManager.request_manual_activation(eff2, 0)
	EffectManager.submit_option_choice(eff2, [0])
	EffectManager.submit_player_selection(eff2, [1])
	check(not EffectManager.submit_card_selection(eff2, [mine2]),
		"a card from the activator is refused for a target-owned selection")
	check((eff2._selected_cards as Array).is_empty(), "nothing is recorded after a refused pick")

	# —— ③ 反例：不声明 owner 时仍挑触发者自己的牌（既有卡行为不变）——
	setup()
	var mine3:BaseCard=make_card()
	var theirs3:BaseCard=make_card()
	GameData.player_data_library[0].hand_cards.append(mine3)
	GameData.player_data_library[1].hand_cards.append(theirs3)
	var eff3:=make_effect("probe_self_only", {
		"shown_option_name":"测试：只挑自己的牌",
		"select_cards":{"source":"hand_cards","min":1,"max":1},
		"funcs":[]
	})
	EffectManager.register_effect(eff3, 0)
	open_window()
	EffectManager.request_manual_activation(eff3, 0)
	EffectManager.submit_option_choice(eff3, [0])
	check(EffectManager.waiting_selection == eff3, "a self-owned selection waits for cards directly")
	var pending3:Dictionary=EffectManager.get_pending_card_selection()
	check((pending3.get("cards", []) as Array).has(mine3), "the candidates are the activator's own cards")
	check(not (pending3.get("cards", []) as Array).has(theirs3), "the other player's cards are not offered")
	check(EffectManager.submit_card_selection(eff3, [mine3]), "a self-owned pick is accepted")

	print("RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
