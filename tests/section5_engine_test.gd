extends Node
# §5 重型机制的新增 operation（add_player）与引擎小改动的专项回归：
#   ① add_player：分身棋子/NPC 条目，顺位与胜负排除、共用字段、战斗代表者、交战判定
#   ② phase_as：阶段视为（阶段窗口派发、常规出牌阶段判定）
#   ③ regular_play_zones：视为手牌的牌区
#   ④ effect_start / effect_end：效果开始可取消、结束派发
#   ⑤ get_phase_order：按顺位现算
# 条件型改动同时验正例与反例（反例要求与原行为一致）。

var failures:Array[String] = []
var checks:int = 0


func check(ok:bool, label:String) -> void:
	checks += 1
	if !ok: failures.append(label)
	print("CHECK ", label, " ", ok)


func _ready() -> void:
	call_deferred("run")


func setup(count:int = 2) -> void:
	EffectManager.reset_runtime()
	GameLog.reset()
	GameData.player_data_library.clear()
	GameProgress.is_game_over = false
	GameProgress.current_phase_index = -1
	GameProgress.current_player_id = -1
	for i in count:
		var d:Dictionary = GameData.new_player_data()
		d.is_out = false
		d.order.set_num(BaseNumber.new(i))
		GameData.player_data_library[i] = d
	for area in MapData.areas:
		area._battle_override = {}
		area._events.clear()
		for loc in area._locations:
			loc._players.clear()


func pd(id:int) -> Dictionary:
	return GameDataManager.get_player_data(id)


func num(n) -> Dictionary:
	return {"number": n, "can_change": true, "is_pure_number": true}


func effect_data(name:String, funcs:Array, numbers:Array = [], time_points:Array = ["game_start"]) -> Dictionary:
	return {"effect_name": name, "time_points": time_points, "priority": 0,
		"is_pure_passive": true, "is_residue": false, "effect_numbers": numbers, "funcs": funcs}


func host_with(effects:Array, id:int = 0) -> BaseAttack:
	var host := BaseAttack.new("probe_host", "", [])
	host._effects = LoadHelper.load_effects(effects, host)
	EffectManager.register_effects(host._effects, id)
	return host


func phase_index(name:String) -> int:
	for i in GameProgress.phases.size():
		if str(GameProgress.phases[i]["name"]) == name:
			return i
	return -1


func run() -> void:
	test_registry()
	test_add_player_basics()
	test_clone_battle()
	test_npc_battle()
	test_engagement()
	test_phase_as()
	test_regular_play_zones()
	test_effect_start_end()
	test_phase_order()
	print("RESULT checks=%d failures=%s" % [checks, str(failures)])
	get_tree().quit()


func test_registry() -> void:
	check(AllOperations.get_class_name_of("add_player") == "AddPlayer", "add_player registered")
	var d:Dictionary = GameData.new_player_data()
	check(int(d.get("controller", 99)) == -1 and d.get("phase_as") == {} and d.get("regular_play_zones") == ["hand_cards"],
		"new player data defaults keep original behaviour")


func test_add_player_basics() -> void:
	setup(2)
	var order_before:Array = EffectManager.get_player_order_ids()
	var clone:int = AddPlayer.new().exec(0, ["played_cards", "score", "magic"], {"player_name": "分身"})
	check(clone == 2, "new id is max+1: %d" % clone)
	check(EffectManager.get_player_order_ids() == order_before, "clone does not join turn order")
	check(GameDataManager.get_active_player_ids() == [0, 1], "clone excluded from active players (victory/climax/turns)")
	check(GameDataManager.get_board_player_ids().has(clone), "clone is a board participant")
	check(is_same(pd(clone).played_cards, pd(0).played_cards) and is_same(pd(clone).score, pd(0).score), "shared keys point to the controller's objects")
	check(!is_same(pd(clone).power, pd(0).power) and !is_same(pd(clone).hand_cards, pd(0).hand_cards), "unshared keys are independent")
	check(pd(clone).player_name == "分身", "overrides applied")
	check(GameDataManager.represented_id(clone) == 0 and GameDataManager.represented_id(1) == 1, "represented_id maps clone to controller")
	check(GameDataManager.is_shared_with_controller(clone, "played_cards") and !GameDataManager.is_shared_with_controller(clone, "hand_cards"),
		"shared-field detection")
	# 共用牌区里的牌只归控制者：归属快照与一致性检查不把它算成两个人的
	var card := BaseAttack.new("probe_shared", "", [])
	pd(0).played_cards.append(card)
	check(CardZones.owner_of(card) == 0, "shared card owned by controller")
	var v:Dictionary = DebugValidate.validate_all()
	var dup:bool = false
	for issue in v.get("issues", []):
		if str(issue.get("check", "")) == "card_unique_zone":
			dup = true
	check(!dup, "validator does not report shared zones as duplicates")
	# 数字初值：裸数字包成数字对象
	var npc:int = AddPlayer.new().exec(-2, [], {"power": 14})
	check(pd(npc).power is BaseNumber and pd(npc).power.number == 14 and int(pd(npc).controller) == -2, "npc numeric override wrapped")
	check(GameDataManager.represented_id(npc) == npc, "npc represents itself")
	# 独立条目（-1）与普通玩家相同
	var extra:int = AddPlayer.new().exec(-1)
	check(GameDataManager.get_active_player_ids().has(extra), "controller -1 creates an ordinary player")


func _place(id:int, loc:BaseLocation, power:int) -> void:
	Deploy.new().exec(loc, id, true)
	pd(id).power.set_num(BaseNumber.new(power))


func test_clone_battle() -> void:
	var miyama:BaseMapArea = MapData.miyama
	var shinto:BaseMapArea = MapData.shinto
	setup(2)
	var clone:int = AddPlayer.new().exec(0, ["score", "magic", "total_power_bonus"])
	# 本体在新都输（2 对 9），分身在深山町赢（8 对 3）：两处威力分别计算，分身的胜利算本体的
	_place(0, shinto._locations[2], 2)
	_place(1, shinto._locations[2], 9)
	_place(clone, miyama._locations[2], 8)
	var npc:int = AddPlayer.new().exec(-2, [], {"power": 3})
	Deploy.new().exec(miyama._locations[2], npc, true)
	var score0:int = pd(0).score.number
	var res:Dictionary = BattleResolver.new().exec(GameDataManager.get_board_player_ids())
	check(res.winners_by_area.get(miyama._area_name) == [clone], "clone wins its own battlefield by its own power")
	check(res.winners_by_area.get(shinto._area_name) == [1], "controller loses separately")
	check(pd(0).score.number > score0, "clone's score goes to the controller: %d -> %d" % [score0, pd(0).score.number])
	check(pd(npc).score.number == 0, "npc gets no score when losing")
	var win_logs:Array = GameLog.query({"type": "time_point", "actor": 0}, 0).filter(func(e): return (e.get("tags", []) as Array).has(TimePoints.BATTLE_WIN))
	check(!win_logs.is_empty(), "battle_win dispatched to the controller")
	# 反例：没有分身时与原来一致
	setup(2)
	_place(0, miyama._locations[2], 5)
	_place(1, miyama._locations[2], 9)
	res = BattleResolver.new().exec([])
	check(res.winners_by_area.get(miyama._area_name) == [1], "default participants unchanged without controlled entries")


func test_npc_battle() -> void:
	var miyama:BaseMapArea = MapData.miyama
	setup(2)
	var npc:int = AddPlayer.new().exec(-2, [], {"power": 14})
	Deploy.new().exec(miyama._locations[2], npc, true)
	_place(0, miyama._locations[2], 9)
	var res:Dictionary = BattleResolver.new().exec(GameDataManager.get_board_player_ids())
	check(res.winners_by_area.get(miyama._area_name) == [npc], "npc with fixed power beats the player")
	check(pd(0).score.number == 0, "player gets nothing when npc wins")
	# 终局判定不把 NPC 当候选
	pd(npc).score.set_num(BaseNumber.new(99))
	pd(0).score.set_num(BaseNumber.new(3))
	pd(1).score.set_num(BaseNumber.new(1))
	check(VictoryResolver.new().exec({}) == [0], "victory resolver ignores npc")


func test_engagement() -> void:
	var miyama:BaseMapArea = MapData.miyama
	setup(2)
	var clone:int = AddPlayer.new().exec(0, ["score"])
	Deploy.new().exec(miyama._locations[0], 0, true)
	Deploy.new().exec(miyama._locations[1], clone, true)
	check(!IsEngaged.new().exec(0), "own clone is not an opponent")
	var npc:int = AddPlayer.new().exec(-2)
	Deploy.new().exec(miyama._locations[2], npc, true)
	check(IsEngaged.new().exec(0), "npc on the same battlefield engages")


func test_phase_as() -> void:
	setup(2)
	var prep:int = phase_index("prepare")
	GameProgress.current_phase_index = prep
	check(GameProgress.effective_phase_names(0) == ["prepare"], "no mapping: current phase only")
	check(!GameProgress.is_phase_for(0, "action"), "no mapping: not in action during prepare")
	pd(0).phase_as = {"prepare": ["prepare", "outpost", "action"], "outpost": [], "action": []}
	check(GameProgress.is_phase_for(0, "outpost") and GameProgress.is_phase_for(0, "action"), "mapped prepare includes outpost and action")
	check(!GameProgress.is_phase_for(1, "action"), "mapping is per player")
	var mids:Array = GameProgress.effective_phase_mids(0)
	check(mids.has(TimePoints.PREPARE_PHASE) and mids.has(TimePoints.ACTION_PHASE), "mids follow the mapping")
	GameProgress.current_phase_index = phase_index("action")
	check(GameProgress.effective_phase_names(0).is_empty(), "action mapped to nothing")
	# 阶段窗口派发：准备阶段轮到玩家 0 时，行动阶段能力的窗口成立
	setup(2)
	pd(0).phase_as = {"prepare": ["prepare", "action"]}
	host_with([effect_data("probe_action_ability", [
		{"func_name": "edit_score", "parameters": [null, {"number_index": 0}, -1], "var_index": -1}
	], [num(1)], ["self_action_phase"])], 0)
	host_with([effect_data("probe_action_ability", [
		{"func_name": "edit_score", "parameters": [null, {"number_index": 0}, -1], "var_index": -1}
	], [num(1)], ["self_action_phase"])], 1)
	GameProgress.current_phase_index = prep
	GameProgress.current_phase_player_index = 0
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.PREPARE_PHASE])
	GameProgress.next_player_in_phase()
	check(GameProgress.current_player_id == 0 and pd(0).score.number == 1, "mapped player's action-phase ability fires in prepare")
	GameProgress.next_player_in_phase()
	check(GameProgress.current_player_id == 1 and pd(1).score.number == 0, "unmapped player's action ability does not fire in prepare")
	GameProgress.current_phase_index = -1
	GameProgress.current_player_id = -1
	# 常规出牌：准备阶段被映射为行动阶段的玩家可以出牌；没映射的不行
	setup(2)
	var atk := BaseAttack.new("probe_atk", "", [])
	atk._cost.set_num(BaseNumber.new(0))
	pd(0).hand_cards.append(atk)
	pd(0).regular_play_min.set_num(BaseNumber.new(1))
	GameProgress.current_phase_index = prep
	GameProgress.current_player_id = 0
	check(RegularPlay.modes(0, atk).is_empty(), "no mapping: cannot regular-play during prepare")
	pd(0).phase_as = {"prepare": ["prepare", "action"]}
	check(!RegularPlay.modes(0, atk).is_empty(), "mapped: regular play allowed during prepare")
	GameProgress.current_phase_index = -1
	GameProgress.current_player_id = -1


func test_regular_play_zones() -> void:
	setup(2)
	GameProgress.current_phase_index = phase_index("action")
	GameProgress.current_player_id = 0
	var from_discard := BaseAttack.new("probe_discard", "", [])
	from_discard._cost.set_num(BaseNumber.new(0))
	var in_hand := BaseAttack.new("probe_hand", "", [])
	in_hand._cost.set_num(BaseNumber.new(0))
	pd(0).discard.append(from_discard)
	pd(0).hand_cards.append(in_hand)
	check(RegularPlay.candidates(0).has(in_hand) and !RegularPlay.candidates(0).has(from_discard), "default: hand only")
	pd(0).regular_play_zones = ["discard"]
	check(RegularPlay.candidates(0).has(from_discard) and !RegularPlay.candidates(0).has(in_hand), "discard treated as the hand, hand no longer")
	pd(0).regular_play_min.set_num(BaseNumber.new(1))
	check(RegularPlay.modes(0, from_discard).has(true), "concealed play allowed from the declared zone")
	check(RegularPlay.submit_group(0, [from_discard], [false]), "group from the declared zone submits")
	check(pd(0).played_cards.has(from_discard) and !pd(0).discard.has(from_discard), "played card leaves the declared zone")
	pd(0).regular_play_zones = ["extra_zones/missing"]
	check(!RegularPlay.candidates(0).has(in_hand), "unknown zone path contributes nothing")
	GameProgress.current_phase_index = -1
	GameProgress.current_player_id = -1


func test_effect_start_end() -> void:
	# 反例：没有监听时照常结算
	setup(2)
	var e:BaseEffect = host_with([effect_data("probe_gain", [
		{"func_name": "edit_score", "parameters": [null, {"number_index": 0}, -1], "var_index": -1}
	], [num(3)])], 1)._effects[0]
	EffectManager.add_to_activation_pool(e)
	EffectManager.run_pipeline()
	check(pd(1).score.number == 3, "effect resolves without effect_start listeners")
	# 正例：others_effect_start 监听者取消他人效果
	setup(2)
	host_with([effect_data("probe_delay", [
		{"func_name": "cancel_pending_action", "parameters": [], "var_index": -1}
	], [], ["others_effect_start"])], 0)
	var gain:BaseEffect = host_with([effect_data("probe_gain", [
		{"func_name": "edit_score", "parameters": [null, {"number_index": 0}, -1], "var_index": -1}
	], [num(3)])], 1)._effects[0]
	EffectManager.add_to_activation_pool(gain)
	EffectManager.run_pipeline()
	check(pd(1).score.number == 0, "others_effect_start listener cancels the effect")
	check(GameLog.query({"type": "effect", "data": {"effect_name": "probe_gain"}}, null).is_empty(), "cancelled effect is not recorded as used")
	check(EffectManager.pending_actions.is_empty(), "pending stack empty afterwards")
	# get_pending_action_value：监听者读到即将开始的那条效果并取消它（按效果名只拦 probe_gain2）
	setup(2)
	var seen:Array = []
	host_with([effect_data("probe_read", [
		{"func_name": "get_pending_action_value", "parameters": ["effect"], "var_index": 0},
		{"func_name": "add_to_array", "parameters": [{"self_var": 0}, seen], "var_index": -1}
	], [], ["others_effect_start"])], 0)
	var gain2:BaseEffect = host_with([effect_data("probe_gain2", [
		{"func_name": "edit_score", "parameters": [null, {"number_index": 0}, -1], "var_index": -1}
	], [num(1)])], 1)._effects[0]
	EffectManager.add_to_activation_pool(gain2)
	EffectManager.run_pipeline()
	check(seen == [gain2], "listener reads the effect about to start: %s" % str(seen))
	check(GetPendingActionValue.new().exec("effect") == null, "no pending value outside the window")
	# 自己的效果不被 others_ 监听取消
	var own:BaseEffect = host_with([effect_data("probe_own", [
		{"func_name": "edit_score", "parameters": [null, {"number_index": 0}, -1], "var_index": -1}
	], [num(2)])], 0)._effects[0]
	EffectManager.add_to_activation_pool(own)
	EffectManager.run_pipeline()
	check(pd(0).score.number == 2, "own effects are not cancelled by others_ listener")
	# effect_end：他人效果结算后派发
	setup(2)
	host_with([effect_data("probe_after", [
		{"func_name": "edit_magic", "parameters": [null, {"number_index": 0}, -1], "var_index": -1}
	], [num(1)], ["others_effect_end"])], 0)
	var m0:int = pd(0).magic.number
	var other:BaseEffect = host_with([effect_data("probe_other", [
		{"func_name": "edit_score", "parameters": [null, {"number_index": 0}, -1], "var_index": -1}
	], [num(1)])], 1)._effects[0]
	EffectManager.add_to_activation_pool(other)
	EffectManager.run_pipeline()
	check(pd(0).magic.number == m0 + 1, "others_effect_end fires after another player's effect: %d" % pd(0).magic.number)
	var end_logs:Array = GameLog.query({"type": "time_point", "actor": 1}, 0).filter(func(x): return (x.get("tags", []) as Array).has(TimePoints.EFFECT_END) and x.get("object") == other)
	check(!end_logs.is_empty(), "effect_end log carries the finished effect as object")
	# 两名玩家都监听 others_effect_start 时不会互相嵌套
	setup(2)
	host_with([effect_data("probe_watch_a", [
		{"func_name": "edit_magic", "parameters": [null, {"number_index": 0}, -1], "var_index": -1}
	], [num(1)], ["others_effect_start"])], 0)
	host_with([effect_data("probe_watch_b", [
		{"func_name": "edit_magic", "parameters": [null, {"number_index": 0}, -1], "var_index": -1}
	], [num(1)], ["others_effect_start"])], 1)
	var trig:BaseEffect = host_with([effect_data("probe_trig", [
		{"func_name": "edit_score", "parameters": [null, {"number_index": 0}, -1], "var_index": -1}
	], [num(1)])], 1)._effects[0]
	EffectManager.add_to_activation_pool(trig)
	EffectManager.run_pipeline()
	check(pd(1).score.number == 1, "mutual effect_start listeners terminate")


func test_phase_order() -> void:
	setup(3)
	check(GetPhaseOrder.new().exec(0).number == 0 and GetPhaseOrder.new().exec(2).number == 2, "phase order computed from turn order")
	ChangePlOrder.new().exec(null, BaseNumber.new(1))
	var ids:Array = EffectManager.get_player_order_ids()
	check(GetPhaseOrder.new().exec(ids[0]).number == 0, "phase order follows order changes")
	var clone:int = AddPlayer.new().exec(0)
	check(GetPhaseOrder.new().exec(clone) == null, "controlled entries have no phase order")
