extends Node


#游戏回合进程推进器：回合 -> 阶段 -> 各玩家在该阶段的自己的回合。
#只负责把时点交给TimePointChecker派发，效果的发现、询问、结算全部在EffectManager里。


#总回合数。规则数字不写死，特殊效果可以改动
var total_rounds:BaseNumber = BaseNumber.new(11)

var current_round:int = 0
#当前阶段下标，-1表示还没进入任何阶段
var current_phase_index:int = -1
#当前阶段里轮到第几个玩家(按顺位)
var current_phase_player_index:int = 0
#当前正在进行自己阶段的玩家
var current_player_id:int = -1
var is_game_over:bool = false
var has_battle_resolved:bool = false
#阶段收尾可跨玩家选择暂停；续行只走尚未完成的步骤，不重复玩家行动或结束时点。
var _phase_end_pending:bool = false
var _phase_end_dispatched:bool = false
#同步结算调用尚未返回时，禁止效果或其他调用方重入阶段收尾。
var _phase_end_running:bool = false
#本回合战斗阶段结算结果，供最终回合判定胜负时查询深山町战斗胜者
var last_battle_result:Dictionary = {}
var climax_keep_counts:Dictionary = {
	8: BaseNumber.new(4),
	9: BaseNumber.new(3),
	10: BaseNumber.new(2)
}
#开局时从从者的_specials发放到玩家区域的内容。
#取不到键就当没有，以后从者多出别的卡在这里加一行即可，不写死
var card_deal_rules:Array = [
	{"special_key" : "ATTACKS", "area" : "deck", "shuffle" : true, "concealed" : false},
	{"special_key" : "SKILLS", "area" : "servant_skills", "shuffle" : false, "concealed" : true}
]
#每回合开始时事件牌的放置计划：抽几张、放哪个战场、明置还是暗置。
#规则数字不写死，默认是深山町一张明置、新都一张暗置，效果可以改动它
var event_placements:Array = [
	{"area_name" : "深山町", "concealed" : false},
	{"area_name" : "新都", "concealed" : true}
]

#四个阶段：准备、前哨、行动、战斗
var phases:Array = [
	{
		"name" : "prepare",
		"start" : TimePoints.PREPARE_PHASE_START,
		"mid" : TimePoints.PREPARE_PHASE,
		"end" : TimePoints.PREPARE_PHASE_END
	},
	{
		"name" : "outpost",
		"start" : TimePoints.OUTPOST_PHASE_START,
		"mid" : TimePoints.OUTPOST_PHASE,
		"end" : TimePoints.OUTPOST_PHASE_END
	},
	{
		"name" : "action",
		"start" : TimePoints.ACTION_PHASE_START,
		"mid" : TimePoints.ACTION_PHASE,
		"end" : TimePoints.ACTION_PHASE_END
	},
	{
		"name" : "battle",
		"start" : TimePoints.BATTLE_PHASE_START,
		"mid" : TimePoints.BATTLE_PHASE,
		"end" : TimePoints.BATTLE_PHASE_END
	}
]


#按order排序的玩家顺位，顺位可被ChangePlOrder改动
func get_ordered_player_ids() -> Array:
	return EffectManager.get_player_order_ids()


func get_current_phase() -> Dictionary:
	if current_phase_index < 0 or current_phase_index >= phases.size():
		return {}
	return phases[current_phase_index]


#游戏开始
func start_game():
	is_game_over = false
	current_round = 0
	has_battle_resolved = false
	_phase_end_pending = false
	_phase_end_dispatched = false
	_phase_end_running = false
	#新的一局：历史日志清空
	GameLog.reset()
	EffectManager.sync_loaded_effect_pool()
	#规则：将所有事件牌洗混为事件牌堆(B1)，每局重新洗
	MapData.reset_event_deck()
	#规则：10张非高潮局势牌洗混后烧2张，剩8张作为局势牌堆(A1)
	MapData.reset_situation_deck()
	#规则：将12张攻击牌洗混后暗置作为自己的牌堆，将3张技能牌暗置于自己的技能区
	deal_player_cards()
	TimePointChecker.set_phase_time_points([TimePoints.GAME])
	TimePointChecker.global_time_point([TimePoints.GAME_START])
	start_round()


#把每名玩家从者的_specials按card_deal_rules发放到对应区域。
#发出去的是克隆体、模板留在从者身上：否则牌堆里的牌会改到同一组数字和效果，
#重开一局也会带着上一局的状态。
#player_id 传具体玩家时只发给他一个人——换从者这类效果只需重发当事玩家的牌，
#不能顺手把其他玩家已有的牌堆也重置掉
func deal_player_cards(player_id: int = -1):
	var ids: Array = [player_id] if player_id != -1 else GameDataManager.get_active_player_ids()
	for id in ids:
		var player_data = GameDataManager.get_player_data(id) as Dictionary
		var servant = player_data["servant"]
		if servant == null or !("_specials" in servant):
			continue
		for rule in card_deal_rules:
			var cards:Array = clone_cards(servant._specials.get(rule["special_key"], []))
			if rule.get("shuffle", false):
				ShuffleArray.new().exec(cards)
			if rule.get("concealed", false):
				for card in cards:
					card.set_concealed(true)
			player_data[rule["area"]] = cards
			#实际发到玩家区域的克隆体才是后续出牌与时点检查的来源。
			for card in cards:
				RegisterObjectEffects.new().exec(card, id)


#克隆一份卡牌数组，供发放牌堆/技能区使用
func clone_cards(cards:Array) -> Array:
	var cloned:Array = []
	for card in cards:
		cloned.append(CloneObject.new().exec(card))
	return cloned


#结束本局。winners 由调用方（VictoryResolver 的结果）传入：
#谁获胜是胜负规则的事，这里只负责把结局作为事实记下来并告知玩家。
#空数组是规则里真实存在的结局（圣杯溢出，全员判负），不能当作"还没算出来"
func end_game(winners:Array = []):
	is_game_over = true
	var names:Array = []
	for id in winners:
		names.append(_player_shown_name(int(id)))
	GameLog.record("game_end", -1, -1, "", null, ["game_end"],
		{"winners": winners.duplicate(), "round": current_round})
	if winners.is_empty():
		#规则：并列且决胜仍无法分出唯一胜者时，圣杯溢出，所有人都输
		EffectManager.push_message("圣杯溢出，全员判负")
	else:
		EffectManager.push_message("游戏结束，胜者：" + "、".join(names))
	TimePointChecker.set_phase_time_points([])
	TimePointChecker.global_time_point([TimePoints.GAME_END])


#玩家的示人名字：走御主的显示名接口，取不到才回退玩家编号
func _player_shown_name(player_id:int) -> String:
	if !GameData.player_data_library.has(player_id):
		return "玩家 %d" % player_id
	var master = (GameDataManager.get_player_data(player_id) as Dictionary).get("master")
	if master != null:
		var shown:String = str(master.get_shown_name())
		if shown != "":
			return shown
	return "玩家 %d" % player_id


#回合
func start_round():
	if is_game_over:
		return
	current_round += 1
	if current_round > total_rounds.number:
		#兜底路径（正常在 end_round 就结束了）：结束前同样要判定胜负，
		#否则这条路径会以"没有胜者"收场，看起来像游戏无法正常结束
		end_game(VictoryResolver.new().exec(last_battle_result))
		return
	#回合号立即生效：这一回合记的每条日志都归到新回合下，不能等到 begin_phase 才更新，
	#否则开局抽局势牌/事件牌、DAY_START 这些日志会记到上一回合
	#回合边界不属于任何阶段，不能沿用上一回合最后一个阶段的名字；
	#阶段名由随后第一次 begin_phase 写进来
	GameLog.set_context(current_round, "")
	current_phase_index = -1
	current_phase_player_index = 0
	current_player_id = -1
	has_battle_resolved = false
	#新回合开始：日志裁掉超过保留上限的旧条目
	GameLog.begin_round()
	refresh_first_player()
	#每回合开始时重置本回合类记录字段，并派发ROUND_START_RESET供效果监听
	EffectManager.reset_round_option_counts()
	for id in GameDataManager.get_active_player_ids():
		var player_data = GameDataManager.get_player_data(id) as Dictionary
		player_data["temp_locations"] = []
		TimePointChecker.dynamic_time_point([TimePoints.ROUND_START_RESET], id)
	TimePointChecker.set_phase_time_points([TimePoints.DAY])
	#规则：准备阶段按回合顺位把自己的手牌补充到手牌上限（已有上限张以上则不抽）。
	#上限数字来自 GameData 的声明，流程里不写死；牌堆抽空时由 operation 负责把弃牌堆洗回
	for id in get_ordered_player_ids():
		RefillHand.new().exec(id, GameData.hand_limit)
	#规则：每一回合开始时抽一张局势牌展示，所有玩家获得其魔力
	SituationResolver.new().activate()
	TimePointChecker.global_time_point([TimePoints.DAY_START])
	#规则：每一回合开始时，为深山町抽一张明置事件牌、为新都抽一张暗置事件牌
	EventResolver.new().place(event_placements)
	advance_phase()


func end_round():
	current_phase_index = -1
	current_phase_player_index = 0
	current_player_id = -1
	TimePointChecker.set_phase_time_points([TimePoints.DAY])
	TimePointChecker.global_time_point([TimePoints.DAY_END])
	if climax_keep_counts.has(current_round):
		TimePointChecker.global_time_point([TimePoints.CLIMAX_START])
		ClimaxResolver.new().exec(climax_keep_counts[current_round])
		TimePointChecker.global_time_point([TimePoints.CLIMAX_END])
	if current_round == total_rounds.number or GameDataManager.get_active_player_ids().size() <= 1:
		#胜者由 VictoryResolver 判定（战果最高 → 并列看深山町胜者 → 仍并列则圣杯溢出），
		#结果传给 end_game 记进日志并提示玩家；这里不重复判定规则
		end_game(VictoryResolver.new().exec(last_battle_result))
		return
	for id in GameDataManager.get_active_player_ids():
		var player_data = GameDataManager.get_player_data(id) as Dictionary
		player_data["last_turn_location"] = player_data["location"]
		player_data["is_battle"] = false
		#规则：回合结束时将每名御主的立牌移除版图（下回合前哨阶段重新部署）。
		#必须在记完 last_turn_location 之后调用，否则查不到本回合结束时的位置
		RemoveFromBoard.new().exec(id)
		#残留牌留在场上，回合结束不处理（残留牌只在自身效果满足条件时自行关闭）
		DiscardPlayedCards.new().exec(id)
		#先清理再重建合计威力基线：规则上残留牌跨回合留场并继续提供威力，
		#所以基线是留场明置牌的威力之和，同时丢弃回合内的非卡牌来源加成
		SyncPower.new().exec(id)
		#规则：合计威力加成只在本回合有效，回合一结束就归零
		(player_data["total_power_bonus"] as BaseNumber).set_num(BaseNumber.new(0))
	#规则：【败北】状态持续至回合结束
	DefeatBuff.clear_all()
	#规则：回合结束时弃置所有激活的局势牌和事件牌
	SituationResolver.new().clear_all()
	EventResolver.new().clear_all()
	#地利修正类效果（远隔操作地利翻倍、占领高地、卫宫地利变3倍）只在本回合有效：
	#把各席位的地利按印刷基线还原，否则同一席位的地利会跨回合越乘越大，
	#而且改的是共享地图数据，会连带影响之后占据该席位的其他玩家
	RestoreLocationBenefits.new().exec()
	#规则：每个回合结束时，将回合顺位顺时针后移一位
	ChangePlOrder.new().exec(null, BaseNumber.new(1))
	start_round()


#顺位第一的玩家即先手，供只看is_first的效果使用
func refresh_first_player():
	var ids = get_ordered_player_ids()
	for i in ids.size():
		var pl_data = GameDataManager.get_player_data(ids[i]) as Dictionary
		pl_data["is_first"] = (i == 0)


#阶段
func advance_phase():
	if is_game_over or _phase_end_running:
		return
	if _phase_end_pending:
		end_phase()
		return
	current_phase_index += 1
	current_phase_player_index = 0
	current_player_id = -1
	if current_phase_index >= phases.size():
		end_round()
		return
	begin_phase()


#规则：高潮局势牌生效的回合（第9/10/11回合）称为高潮回合。
#"高潮"是回合属性而不是独立阶段——这些回合里玩家的各阶段同时处于高潮状态，
#所以效果写 self_climax 表达的是"高潮回合里我的阶段"。
#回合号不写死，直接问局势牌池里登记了哪些高潮回合（与SituationResolver同源）
func is_climax_round() -> bool:
	return LoadSituation.climax_situations.has(current_round)


func begin_phase():
	var phase = get_current_phase()
	if phase.is_empty():
		return
	_phase_end_pending = false
	_phase_end_dispatched = false
	#整个阶段内都成立的时点。高潮回合额外挂CLIMAX、非高潮回合挂NON_CLIMAX，
	#成对派发让效果两边都能表达（"仅高潮"与"仅非高潮"）
	#日志上下文：当前回合与阶段名，之后记的每一条事实都带上它
	GameLog.set_context(current_round, str(phase.get("name", "")))
	var phase_tps:Array = [TimePoints.DAY, TimePoints.PHASE, phase["mid"]]
	phase_tps.append(TimePoints.CLIMAX if is_climax_round() else TimePoints.NON_CLIMAX)
	TimePointChecker.set_phase_time_points(phase_tps)
	#规则：行动阶段开始时展示暗置放置的事件牌（基础规则写明是"位于新都"的那张）。
	#翻在派发阶段时点之前：阶段能力跑的时候应该已经看得到这张明置牌
	if str(phase.get("name", "")) == "action":
		EventResolver.new().reveal_planned(event_placements)
	TimePointChecker.global_time_point([TimePoints.PHASE_START, phase["start"]])
	next_player_in_phase()


#等待接口已涵盖发动、选牌、选位置及选玩家；执行中的管线也不能被阶段推进打断。
func _effects_block_progress() -> bool:
	return EffectManager.is_running or EffectManager.is_waiting_for_choice()


func end_phase():
	if is_game_over or _phase_end_running or _effects_block_progress():
		return
	var phase = get_current_phase()
	if phase.is_empty():
		return
	_phase_end_pending = true
	_phase_end_running = true
	if phase["name"] == "battle" and !has_battle_resolved:
		has_battle_resolved = true
		last_battle_result = BattleResolver.new().exec(GameDataManager.get_active_player_ids(), BaseNumber.new(1))
	#BATTLE_END 的选择尚未完成时保留阶段、事件和原决策队列，不能开 PHASE_END 新批次。
	if is_game_over or _effects_block_progress():
		_phase_end_running = false
		return
	if !_phase_end_dispatched:
		# 战后选择全部结束后封存本次实得，不能把阶段结束收益混入战报。
		if phase["name"] == "battle":
			BattleResolver.finalize_result(last_battle_result)
		#先记已派发，避免结束效果回调重入或稍后续行时重发同一时点。
		_phase_end_dispatched = true
		TimePointChecker.global_time_point([TimePoints.PHASE_END, phase["end"]])
	_phase_end_running = false
	if is_game_over or _effects_block_progress():
		return
	_phase_end_pending = false
	advance_phase()


#规则：每个阶段开始时，所有玩家按回合顺位，从顺位第一的玩家开始以顺时针依次进行自己的阶段。
#派发出去的是phase["mid"]，触发者拿到self_xxx_phase，其他人拿到others_xxx_phase，
#所以"当前玩家先处理完自己的效果，再轮到下一位"是时点表本身带来的，不需要额外的排序逻辑
func next_player_in_phase():
	if is_game_over or _phase_end_running:
		return
	if _phase_end_pending:
		end_phase()
		return
	var phase = get_current_phase()
	if phase.is_empty():
		return
	var ids = get_ordered_player_ids()
	while current_phase_player_index < ids.size():
		var id:int = ids[current_phase_player_index]
		current_phase_player_index += 1
		var player_data = GameDataManager.get_player_data(id) as Dictionary
		if player_data["is_out"]:
			continue
		current_player_id = id
		#高潮/非高潮与阶段时点一起按玩家派发：触发者拿到self_climax或self_non_climax，
		#效果因此能表达"高潮回合里我的阶段"（如宝石魔术放宽上限）与"仅非高潮回合"
		var tps:Array = [phase["mid"]]
		tps.append(TimePoints.CLIMAX if is_climax_round() else TimePoints.NON_CLIMAX)
		#先清掉上一轮的玩家级时点再派发：否则"自己的行动阶段"与"他人的行动阶段"
		#会在同一个人身上同时成立
		TimePointChecker.clear_player_scope_time_points()
		TimePointChecker.dynamic_time_point(tps, current_player_id)
		return
	end_phase()


#当前玩家完成本阶段行动后使用的唯一推进入口。
func end_current_player_action() -> bool:
	if is_game_over or get_current_phase().is_empty():
		return false
	#效果等待任意玩家输入或正在执行时，阶段行动不能绕过管线继续推进。
	#统一在进程层拦截，避免UI、AI和其他调用方各自实现不同的保护。
	if _phase_end_running or _effects_block_progress():
		return false
	#最后行动者已经完成行动：答复后由同一个公开入口续行收尾，不重做行动或结算。
	if _phase_end_pending:
		end_phase()
		return true
	if current_player_id == -1:
		return false
	var phase_name:String = str(get_current_phase().get("name", ""))
	if phase_name == "outpost":
		#规则：前哨阶段各玩家依次把自己的御主部署到版图上。
		#这一步不能只由界面负责——不经界面的推进（AI 推演、无界面运行）会全员不部署，
		#于是没人在版图上、战斗阶段跳过所有人、无人获得战果。
		#已经在版图上的（界面已替玩家部署过）不重复部署；
		#没有任何空席位时什么都不做，不阻塞推进
		var player_data = GameDataManager.get_player_data(current_player_id) as Dictionary
		if player_data.get("location") == null:
			#规则：部署是玩家/AI 在自己前哨阶段的动作，引擎不能替他挑席位。
			#旧实现在这里自动遍历战区替玩家落位——于是还没选地点的玩家一被推进
			#就"莫名结束前哨"，还白拿了一个没选过的席位收益。
			EffectManager.push_message("尚未完成前哨部署", current_player_id)
			return false
	elif phase_name == "action":
		#行动结束的声明式前置条件（如"第一回合必须使用一枚令咒"）：
		#判据在规则层，界面与无界面推进共用同一份，不在这里写死具体规则
		var requirement_block:String = ActionRules.block_reason(current_player_id)
		if requirement_block != "":
			EffectManager.push_message(requirement_block, current_player_id)
			return false
		if not RegularPlay.can_end(current_player_id):
			EffectManager.push_message("尚未满足常规出牌最低要求", current_player_id)
			return false
		if not RegularPlay.completed(current_player_id):
			RegularPlay.finalize(current_player_id, true)
	next_player_in_phase()
	return true


#供UI和各处派发临时时点
func process_time_point(time_point:String, player_id:int = -1):
	if player_id == -1:
		TimePointChecker.global_time_point([time_point])
		return
	TimePointChecker.dynamic_time_point([time_point], player_id)
