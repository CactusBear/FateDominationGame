class_name BattleResolver
extends RefCounted


#按战场分别结算战斗。规则要点：
#1. _score_need_win=true 的区域（深山町、新都）才进行战力结算；_score_need_win=false 的区域（侦察）直接发战果。
#2. 魔术工房也设成 _score_need_win=false，不参与战斗结算。
#3. 被【败北】的玩家既无法获胜，也不能阻止他人获胜（不计入最高判定）。
#4. 胜利者获得事件牌战果；若该战场有至少一名对手参战，再获得竞争战果（_score）。
#5. 多名玩家并列最高时，战果平分后向上取整。
#6. 结算前派发 BATTLE 时点，胜者派发 BATTLE_WIN，败者派发 BATTLE_LOSE。
func exec(active_player_ids:Array = [], area_battle_score:BaseNumber = BaseNumber.new(1)) -> Dictionary:
	var result:Dictionary = {
		"winners_by_area" : {},
		"draw_areas" : [],
		#每个战场的完整结算过程（谁参战、各自威力构成、战果怎么分）。
		#界面战报只读它，不重新计算任何数值
		"details_by_area" : {}
	}
	var ids:Array = active_player_ids.duplicate()
	if ids.is_empty():
		ids = GameDataManager.get_active_player_ids()

	#在任何结算效果执行前固定参战区域与数值起点，之后移动不改变战报归属。
	var score_before:Dictionary = {}
	#按战场区域分组，并缓存 location -> area
	var area_to_players:Dictionary = {}
	var location_to_area:Dictionary = {}
	for id in ids:
		var player_data = GameDataManager.get_player_data(id) as Dictionary
		if player_data["is_out"]:
			continue
		var loc = player_data["location"] as BaseLocation
		if loc == null:
			continue
		if !location_to_area.has(loc):
			for area:BaseMapArea in MapData.areas:
				if area._locations.has(loc):
					location_to_area[loc] = area
					break
		var area:BaseMapArea = location_to_area.get(loc, null)
		if area == null:
			continue
		if !area_to_players.has(area):
			area_to_players[area] = []
		area_to_players[area].append(id)
		score_before[id] = (player_data["score"] as BaseNumber).number
	#仅在本次结果等待收尾时保留；封存后删除，不在玩家或 resolver 上积累状态。
	result["_score_before"] = score_before

	for id in ids:
		var player_data = GameDataManager.get_player_data(id) as Dictionary
		if player_data["is_out"]:
			continue
		player_data["is_battle"] = true
		TimePointChecker.dynamic_time_point([TimePoints.BATTLE], id)

	#注册场上所有事件牌效果（归属存活玩家作锚点），再派发一次全局战斗结算时点。
	#事件牌效果挂battle_resolve时点，触发时用event.from反查所在战场遍历战场玩家。
	_register_event_effects(ids)
	TimePointChecker.global_time_point([TimePoints.BATTLE_RESOLVE])

	#逐区域结算
	for area:BaseMapArea in area_to_players.keys():
		var player_ids:Array = area_to_players[area]
		if area._score_need_win:
			_resolve_battle_area(area, player_ids, result)
		else:
			_resolve_non_battle_area(area, player_ids, result)

	#胜者判定之后的时点：派发在全部区域结算完之后。
	#"此战场胜者可恢复1枚令咒"这类规则要在知道本场胜者之后才能触发，
	#而 battle_resolve 派发在胜者计算之前，查不到本场结果——所以另设全局时点
	TimePointChecker.global_time_point([TimePoints.BATTLE_END])
	_update_score_gained(result)
	finalize_result(result)
	return result


#GameProgress 在 BATTLE_END 所有选择完成后、派发下一时点前调用。
#同步结算立即封存；等待中的结果只展示已完成部分，绝不代替玩家作选择。
#已封存的历史结果再次传入是 no-op，后续结算不能污染它。
static func finalize_result(result:Dictionary) -> Dictionary:
	if !result.has("_score_before"):
		return result
	if EffectManager.is_running or EffectManager.is_waiting_for_choice():
		return result
	_update_score_gained(result)
	result.erase("_score_before")
	return result


static func _update_score_gained(result:Dictionary) -> void:
	var before:Dictionary = result.get("_score_before", {})
	for detail:Dictionary in result["details_by_area"].values():
		var gained:Dictionary = {}
		for id in detail["players"]:
			var score:BaseNumber = GameDataManager.get_player_data(id)["score"]
			gained[id] = score.number - before[id]
		detail["score_gained"] = gained


#把场上所有事件牌的效果登记进效果池，归属一个存活玩家作锚点。
#事件牌效果挂battle_resolve时点，触发时用event.from反查所在战场再遍历战场玩家，
#所以锚点玩家是谁不影响效果作用对象。只对尚未归属的效果登记一次，避免重复入池。
func _register_event_effects(ids:Array):
	var anchor:int = -1
	for id in ids:
		if !(GameDataManager.get_player_data(id) as Dictionary)["is_out"]:
			anchor = id
			break
	if anchor == -1:
		return
	for area:BaseMapArea in MapData.areas:
		for event:BaseEvent in area._events:
			for effect in event._effects:
				if effect._trigger_player_id == -1:
					EffectManager.register_effect(effect, anchor)


#处理需要战斗胜利才能拿战果的战场
func _resolve_battle_area(area:BaseMapArea, player_ids:Array, result:Dictionary):
	var effective_ids:Array = []
	var buffs_checker = PlayerBuffsHaveEffect.new()
	for id in player_ids:
		#带有"排除出胜负判定"效果(如【败北】)的玩家被忽略，
		#既不能获胜也不能阻止他人获胜。按效果名通用查询，不关心具体buff类型
		if buffs_checker.exec(ExcludedFromBattleWinEffect.EFFECT_NAME, id):
			continue
		effective_ids.append(id)

	if effective_ids.is_empty():
		result["draw_areas"].append(area._area_name)
		#全员被排除也要留一条事实，否则这场战斗在日志里完全不存在
		_record_battle(area, player_ids, [])
		var event_score:int = 0
		for event:BaseEvent in area._events:
			event_score += (event._score as BaseNumber).number
		var competition_score:int = (area._score as BaseNumber).number if player_ids.size() >= 2 else 0
		result["details_by_area"][area._area_name] = {
			"players": player_ids.duplicate(), "effective_players": [],
			"powers": {}, "winners": [], "is_draw": true, "highest_power": 0,
			"event_score": event_score, "competition_score": competition_score,
			"total_score": event_score + competition_score, "score_gained": {}
		}
		return

	var highest_power = null
	var winners:Array = []
	#每个人用于比较胜负的威力构成都记下来：事后核对"为什么是他赢"时不用再猜
	#（power=出牌威力、bonus=合计威力加成、location_benefit=地利，total 才是比较用的值）
	var powers:Dictionary = {}
	for id in effective_ids:
		#威力构成统一走 GetPlayerTotalPower：结算与界面共用同一份公式，
		#避免两边各算一套导致"界面显示 12、结算按 10 判"（本项目已出过这类误报）。
		#合计威力加成(言峰执行者、佐佐木燕返等)只在比较胜负时叠加、不写回 power 本身，
		#这条口径也在那个查询里
		var pw:Dictionary = GetPlayerTotalPower.breakdown(id)
		var power:int = int(pw["total"])
		powers[id] = pw
		if highest_power == null or power > highest_power:
			highest_power = power
			winners = [id]
		elif power == highest_power:
			winners.append(id)

	#先记这场战斗的结果，再发战果、再派生败时点：
	#胜败时点里的效果要能查到本场战斗，不能等一切都派发完才补记
	_record_battle(area, player_ids, winners, powers)

	#总战果 = 事件牌战果 + 竞争战果（有至少一名对手时）
	var total_score:int = 0
	for event:BaseEvent in area._events:
		total_score += (event._score as BaseNumber).number
	var has_opponent:bool = player_ids.size() >= 2
	if has_opponent:
		total_score += (area._score as BaseNumber).number

	#这里只发基础奖池；全部效果完成后的实得由结算起止快照统一生成。
	if winners.size() == 1:
		var winner_id:int = winners[0]
		EditScore.new().exec(null, BaseNumber.new(total_score), winner_id)
		TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], winner_id)
		result["winners_by_area"][area._area_name] = [winner_id]
	else:
		#平局：战果平分并向上取整
		var split_score:int = ceili(float(total_score) / winners.size())
		for winner_id in winners:
			EditScore.new().exec(null, BaseNumber.new(split_score), winner_id)
			TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], winner_id)
		result["winners_by_area"][area._area_name] = winners
	#本场战斗的完整结算过程：参战者、每人威力构成、总战果来源、各人实得战果。
	#界面战报按这份数据逐条展示"每个战场每人多少威力、怎么结算的"，
	#并列时也能列出到底是谁和谁平局——这些都不该由界面重新推算
	result["details_by_area"][area._area_name] = {
		"players": player_ids.duplicate(),
		"effective_players": effective_ids.duplicate(),
		"powers": powers.duplicate(),
		"winners": winners.duplicate(),
		"is_draw": winners.size() > 1,
		"highest_power": highest_power if highest_power != null else 0,
		"event_score": total_score - ((area._score as BaseNumber).number if has_opponent else 0),
		"competition_score": (area._score as BaseNumber).number if has_opponent else 0,
		"total_score": total_score,
		"score_gained": {}
	}

	#非胜者标记为战斗失败，并派发 BATTLE_LOSE 时点。
	#被排除出胜负判定的玩家(如已被效果赋予【败北】)在获得该状态时已经派发过 BATTLE_LOSE，
	#这里不再重复派发，避免同一状态触发两次
	for id in player_ids:
		if winners.has(id):
			continue
		var player_data = GameDataManager.get_player_data(id) as Dictionary
		var already_excluded:bool = buffs_checker.exec(ExcludedFromBattleWinEffect.EFFECT_NAME, id)
		if !already_excluded:
			TimePointChecker.dynamic_time_point([TimePoints.BATTLE_LOSE], id)
	
	# 派发战斗结束时点由 exec 在"全部战区结算完之后"统一做一次（见 exec 里的
	# TimePoints.BATTLE_END 派发）：那里才能保证每个战场的战斗日志都已写好，
	# get_area_round_winners/get_area_round_participants 查得到本场结果。
	# 不要在这里按战区再派一次——同一回合多个战场会重复触发同一个战场效果

#把一场战斗的结果写进日志：参与者、胜者，以及开打时就已经出局的玩家（has_out 直接可筛）。
#按参与者逐个记一条，效果用 actor 查就自动只拿到自己参与过的战斗
func _record_battle(area:BaseMapArea, player_ids:Array, winners:Array, powers:Dictionary = {}) -> void:
	var out_players:Array = []
	for pid in player_ids:
		if (GameDataManager.get_player_data(pid) as Dictionary)["is_out"]:
			out_players.append(pid)
	for pid in player_ids:
		GameLog.record("battle", int(pid), -1, area._area_name, null, ["battle"],
			{"players": player_ids.duplicate(), "winners": winners.duplicate(),
			"out_players": out_players.duplicate(), "has_out": !out_players.is_empty(),
			"powers": powers.duplicate()})


#处理不需要战斗胜利即可拿战果的区域（侦察）：所有在场玩家直接获得 _score 点战果
func _resolve_non_battle_area(area:BaseMapArea, player_ids:Array, result:Dictionary):
	var score:int = (area._score as BaseNumber).number
	for id in player_ids:
		if score > 0:
			EditScore.new().exec(null, BaseNumber.new(score), id)
	#这类战区不比威力，但同样要能在战报里看到"谁在这里拿了多少战果"
	result["details_by_area"][area._area_name] = {
		"players": player_ids.duplicate(),
		"effective_players": player_ids.duplicate(),
		"powers": {},
		"winners": player_ids.duplicate(),
		"is_draw": false,
		"needs_win": false,
		"highest_power": 0,
		"event_score": 0,
		"competition_score": score,
		"total_score": score,
		"score_gained": {}
	}
