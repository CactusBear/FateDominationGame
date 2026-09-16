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
		"draw_areas" : []
	}
	var ids:Array = active_player_ids.duplicate()
	if ids.is_empty():
		ids = GameDataManager.get_active_player_ids()

	#先重置所有非淘汰玩家的战斗标记，并派发 BATTLE 时点
	for id in ids:
		var player_data = GameDataManager.get_player_data(id) as Dictionary
		if player_data["is_out"]:
			continue
		player_data["is_battle"] = true
		TimePointChecker.dynamic_time_point([TimePoints.BATTLE], id)

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
	return result


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
		return

	var highest_power = null
	var winners:Array = []
	for id in effective_ids:
		var pl_data = GameDataManager.get_player_data(id) as Dictionary
		#合计威力加成(言峰执行者、佐佐木燕返等)只在比较胜负时叠加，不写回power本身，
		#避免power被重复累加
		var power = (pl_data["power"] as BaseNumber).number + (pl_data["total_power_bonus"] as BaseNumber).number
		#基础规则：仍位于地利位置获得等同该位置标注地利数的威力。
		#"此战场的各个地利位置不提供地利"这类例外由事件牌按效果名(no_location_benefit)
		#声明在战区上，声明的战场整体排除，数字不写死在这里
		if !MapAreaHasEffect.new().exec(area, NoLocationBenefitEffect.EFFECT_NAME):
			power += GetPlayerLocationBenefit.new().exec(id)
		if highest_power == null or power > highest_power:
			highest_power = power
			winners = [id]
		elif power == highest_power:
			winners.append(id)

	#先记这场战斗的结果，再发战果、再派生败时点：
	#胜败时点里的效果要能查到本场战斗，不能等一切都派发完才补记
	_record_battle(area, player_ids, winners)

	#总战果 = 事件牌战果 + 竞争战果（有至少一名对手时）
	var total_score:int = 0
	for event:BaseEvent in area._events:
		total_score += (event._score as BaseNumber).number
	var has_opponent:bool = player_ids.size() >= 2
	if has_opponent:
		total_score += (area._score as BaseNumber).number

	if winners.size() == 1:
		var winner_id:int = winners[0]
		var winner_data = GameDataManager.get_player_data(winner_id) as Dictionary
		EditScore.new().exec(null, BaseNumber.new(total_score), winner_id)
		TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], winner_id)
		result["winners_by_area"][area._area_name] = [winner_id]
	else:
		#平局：战果平分并向上取整
		var split_score:int = ceili(float(total_score) / winners.size())
		for winner_id in winners:
			var winner_data = GameDataManager.get_player_data(winner_id) as Dictionary
			EditScore.new().exec(null, BaseNumber.new(split_score), winner_id)
			TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], winner_id)
		result["winners_by_area"][area._area_name] = winners

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

#把一场战斗的结果写进日志：参与者、胜者，以及开打时就已经出局的玩家（has_out 直接可筛）。
#按参与者逐个记一条，效果用 actor 查就自动只拿到自己参与过的战斗
func _record_battle(area:BaseMapArea, player_ids:Array, winners:Array) -> void:
	var out_players:Array = []
	for pid in player_ids:
		if (GameDataManager.get_player_data(pid) as Dictionary)["is_out"]:
			out_players.append(pid)
	for pid in player_ids:
		GameLog.record("battle", int(pid), -1, area._area_name, null, ["battle"],
			{"players": player_ids.duplicate(), "winners": winners.duplicate(),
			"out_players": out_players.duplicate(), "has_out": !out_players.is_empty()})


#处理不需要战斗胜利即可拿战果的区域（侦察）：所有在场玩家直接获得 _score 点战果
func _resolve_non_battle_area(area:BaseMapArea, player_ids:Array, result:Dictionary):
	var score:int = (area._score as BaseNumber).number
	if score <= 0:
		return
	for id in player_ids:
		EditScore.new().exec(null, BaseNumber.new(score), id)
