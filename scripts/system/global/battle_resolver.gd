class_name BattleResolver
extends RefCounted

#新建结算对象是来源捕获边界；旧 resolver/绑定 Callable 消费时绝不重领当前票。
var _context:SessionContext = null

func _init(source_context:SessionContext = null):
	var parent:Variant = source_context
	if parent == null:
		var frame:Dictionary = EffectManager.execution_context()
		if frame.ok:
			parent = frame.context
		elif not EffectManager.is_running and EffectManager.execution_runtime_snapshot().functions.is_empty():
			#无执行根的正式阶段入口新建对象；运行中的拒绝帧不能退回 current。
			parent = SessionGeneration.current_token().get("token")
	var captured:Dictionary = SessionGeneration.derive_context(parent, &"battle_resolver")
	if captured.ok:
		_context = captured.context

static func _result_source_valid(result:Dictionary) -> bool:
	return SessionGeneration.validate_context(result.get("_battle_context")).get("ok", false)

static func _battle_is_current(result:Dictionary) -> bool:
	return _result_source_valid(result) and _has_registered_subjects(result.get("_battle_subjects", []))

#控制通道与战报数据分离；不把任意 Dictionary/非空明细当成功收据。
#COMMITTED_STOP 承认本战已有结算，不冒称 REJECTED_NO_EFFECT。
enum ResultState { REJECTED_NO_EFFECT, PENDING_POST_BATTLE, SEALED, COMMITTED_STOP }


#按战场分别结算战斗。规则要点：
#1. _score_need_win=true 的区域（深山町、新都）才进行战力结算；_score_need_win=false 的区域（侦察）直接发战果。
#2. 魔术工房也设成 _score_need_win=false，不参与战斗结算。
#3. 被【败北】的玩家既无法获胜，也不能阻止他人获胜（不计入最高判定）。
#4. 胜利者获得事件牌战果；若该战场有至少一名对手参战，再获得竞争战果（_score）。
#5. 多名玩家并列最高时，战果平分后向上取整。
#6. 结算前派发 BATTLE 时点，胜者派发 BATTLE_WIN，败者派发 BATTLE_LOSE。
func exec(active_player_ids:Array = [], area_battle_score:BaseNumber = BaseNumber.new(1)) -> Dictionary:
	#兼容数据消费者：只投影同一次调用，不二次执行，不隐式投影控制状态为 bool。
	return exec_result(active_player_ids, area_battle_score)[1]


#显式结果 ABI：[ResultState, 原 Dictionary 战报]；本入口只执行一次。
func exec_result(active_player_ids:Array = [], area_battle_score:BaseNumber = BaseNumber.new(1)) -> Array:
	var result:Dictionary = {
		"winners_by_area" : {},
		"draw_areas" : [],
		#每个战场的完整结算过程（谁参战、各自威力构成、战果怎么分）。
		#界面战报只读它，不重新计算任何数值
		"details_by_area" : {}
	}
	if not SessionGeneration.validate_context(_context).get("ok", false):
		return [ResultState.REJECTED_NO_EFFECT, result]
	var ids:Array = active_player_ids.duplicate()
	if ids.is_empty():
		#版图上的全部参战条目：独立玩家 + 分身棋子/NPC（add_player 创建的受控条目）
		ids = GameDataManager.get_board_player_ids()
	#整批参战者与战果代表者先验成员；拒绝不得留下建库、战果、日志或时点。
	if !_has_registered_subjects(ids):
		return [ResultState.REJECTED_NO_EFFECT, result]

	#原 context 留在同一战报中，封存后仍可识别历史来源；不从参战 ID 推断资格。
	result["_battle_context"] = _context
	result["_battle_subjects"] = ids.duplicate()

	#在任何结算效果执行前固定参战区域与数值起点，之后移动不改变战报归属。
	var score_before:Dictionary = {}
	#按战场区域分组，并缓存 location -> area
	var area_to_players:Dictionary = {}
	var location_to_area:Dictionary = {}
	for id in ids:
		if not _battle_is_current(result):
			return [ResultState.COMMITTED_STOP, result]
		var player_data = GameDataManager.get_player_data(id) as Dictionary
		if player_data["is_out"]:
			continue
		var loc = player_data["location"] as BaseLocation
		if loc == null:
			continue
		if !location_to_area.has(loc):
			for area:BaseMapArea in MapData.areas:
				if not _battle_is_current(result):
					return [ResultState.COMMITTED_STOP, result]
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
		if not _battle_is_current(result):
			return [ResultState.COMMITTED_STOP, result]
		var player_data = GameDataManager.get_player_data(id) as Dictionary
		if player_data["is_out"]:
			continue
		SetPlayerData.new().exec("is_battle", true, id, _context)
		TimePointChecker.dynamic_time_point([TimePoints.BATTLE], id, null, _context)
		if not _battle_is_current(result):
			return [ResultState.COMMITTED_STOP, result]

	#注册场上所有事件牌效果（归属存活玩家作锚点），再派发一次全局战斗结算时点。
	#事件牌效果挂battle_resolve时点，触发时用event.from反查所在战场遍历战场玩家。
	if not _register_event_effects(ids, result):
		return [ResultState.COMMITTED_STOP, result]
	TimePointChecker.global_time_point([TimePoints.BATTLE_RESOLVE], null, _context)
	if not _battle_is_current(result):
		return [ResultState.COMMITTED_STOP, result]

	#逐区域结算
	for area:BaseMapArea in area_to_players.keys():
		if not _battle_is_current(result):
			return [ResultState.COMMITTED_STOP, result]
		var player_ids:Array = area_to_players[area]
		if area._score_need_win:
			if not _resolve_battle_area(area, player_ids, result):
				return [ResultState.COMMITTED_STOP, result]
		else:
			if not _resolve_non_battle_area(area, player_ids, result):
				return [ResultState.COMMITTED_STOP, result]
	#胜负改写只对本回合这一次结算有效：没人参战、不比威力的战场上的声明也一并作废，不留到下一回合
	for area:BaseMapArea in MapData.areas:
		if not _battle_is_current(result):
			return [ResultState.COMMITTED_STOP, result]
		area._battle_override = {}

	#胜者判定之后的时点：派发在全部区域结算完之后。
	#"此战场胜者可恢复1枚令咒"这类规则要在知道本场胜者之后才能触发，
	#而 battle_resolve 派发在胜者计算之前，查不到本场结果——所以另设全局时点
	TimePointChecker.global_time_point([TimePoints.BATTLE_END], null, _context)
	if not _battle_is_current(result):
		return [ResultState.COMMITTED_STOP, result]
	#等待中的预览沿用已完成实得；主体失效时不通过 getter 建库更新预览。
	if _has_registered_result_subjects(result):
		_update_score_gained(result)
	return [finalize_result_state(result, ResultState.PENDING_POST_BATTLE), result]

#规则奖励复用正式描述符/执行帧；只创建本次函数的运行期载体，不入池、不激活、不补 current。
#router 第三参只认证派发，不能给 EditScore 凭空创建执行帧，所以旧无帧直调改走此既有入口。
func _award_score(amount:int, player_id:int, result:Dictionary) -> bool:
	if not _battle_is_current(result):
		return false
	var context:SessionContext = result["_battle_context"]
	var carriers:Array = LoadHelper.load_effects([{
		"effect_name":"battle_score", "time_points":[], "priority":0,
		"is_pure_passive":true, "is_residue":false, "effect_numbers":[], "funcs":[]
	}], null, context)
	if carriers.size() != 1 or not _battle_is_current(result):
		return false
	var outcome:Array = EffectManager.run_func_descriptor({
		"func_name":"edit_score", "parameters":[null, BaseNumber.new(amount), player_id]
	}, carriers[0], context)
	return bool(outcome[0]) and _battle_is_current(result)


#只读资格门：无禁令不等于成员；分身的战果/胜败时点代表者也必须已登记。
static func _has_registered_subjects(ids:Array) -> bool:
	for id in ids:
		if GameDataManager.find_player_data(id).is_empty():
			return false
		if GameDataManager.find_player_data(GameDataManager.represented_id(id)).is_empty():
			return false
	return true


#GameProgress 在 BATTLE_END 所有选择完成后、派发下一时点前调用。
#同步结算立即封存；等待中的结果只展示已完成部分，绝不代替玩家作选择。
#已封存的历史结果再次传入是 no-op，后续结算不能污染它。
static func finalize_result(result:Dictionary) -> Dictionary:
	#旧数据 ABI 保留：历史无标记是 no-op；它本身不能向消费者证明结算被接受。
	if result.has("_score_before"):
		finalize_result_state(result, ResultState.PENDING_POST_BATTLE)
	return result


#必须携同一次 exec_result 的先前状态；拒绝/中断不因无 _score_before 变成成功。
static func finalize_result_state(result:Dictionary, prior_state:int) -> int:
	if prior_state != ResultState.PENDING_POST_BATTLE:
		return prior_state
	if not _result_source_valid(result):
		return ResultState.COMMITTED_STOP
	#只有已接受的本次结果，才复用“封存删除临时起点”的既有可观察合同。
	if !result.has("_score_before"):
		return ResultState.SEALED
	if not _battle_is_current(result) or not _has_registered_result_subjects(result):
		return ResultState.COMMITTED_STOP
	if EffectManager.is_running or EffectManager.is_waiting_for_choice():
		return ResultState.PENDING_POST_BATTLE
	if not _update_score_gained(result):
		return ResultState.COMMITTED_STOP
	result.erase("_score_before")
	return ResultState.SEALED


static func _has_registered_result_subjects(result:Dictionary) -> bool:
	if not _result_source_valid(result):
		return false
	for detail:Dictionary in result["details_by_area"].values():
		if !_has_registered_subjects(detail["players"]):
			return false
	return true


static func _update_score_gained(result:Dictionary) -> bool:
	if not _battle_is_current(result):
		return false
	var before:Dictionary = result.get("_score_before", {})
	for detail:Dictionary in result["details_by_area"].values():
		if not _battle_is_current(result):
			return false
		var gained:Dictionary = {}
		for id in detail["players"]:
			if not _battle_is_current(result):
				return false
			var score:BaseNumber = GameDataManager.get_player_data(id)["score"]
			gained[id] = score.number - before[id]
		detail["score_gained"] = gained
	return true


#把场上所有事件牌的效果登记进效果池，归属一个存活玩家作锚点。
#事件牌效果挂battle_resolve时点，触发时用event.from反查所在战场再遍历战场玩家，
#所以锚点玩家是谁不影响效果作用对象。只对尚未归属的效果登记一次，避免重复入池。

func _register_event_effects(ids:Array, result:Dictionary) -> bool:
	if not _battle_is_current(result):
		return false
	var anchor:int = -1
	for id in ids:
		if not _battle_is_current(result):
			return false
		if !(GameDataManager.get_player_data(id) as Dictionary)["is_out"]:
			anchor = id
			break
	if anchor == -1:
		return true
	for area:BaseMapArea in MapData.areas:
		if not _battle_is_current(result):
			return false
		for event:BaseEvent in area._events:
			if not _battle_is_current(result):
				return false
			for effect in event._effects:
				if not _battle_is_current(result):
					return false
				if effect._trigger_player_id == -1:
					EffectManager.register_effect(effect, anchor)
					if not _battle_is_current(result):
						return false
	return true


#处理需要战斗胜利才能拿战果的战场

func _resolve_battle_area(area:BaseMapArea, player_ids:Array, result:Dictionary) -> bool:
	if not _battle_is_current(result):
		return false
	var effective_ids:Array = []
	var excluded_ids:Array = []
	var buffs_checker = PlayerBuffsHaveEffect.new()
	for id in player_ids:
		if not _battle_is_current(result):
			return false
		#带有"排除出胜负判定"效果(如【败北】)的玩家被忽略，
		#既不能获胜也不能阻止他人获胜。按效果名通用查询，不关心具体buff类型
		var excluded:bool = buffs_checker.exec(ExcludedFromBattleWinEffect.EFFECT_NAME, id)
		if not _battle_is_current(result):
			return false
		if excluded:
			excluded_ids.append(id)
			continue
		effective_ids.append(id)
	#效果对本战场胜负的改写（set_battle_result）。"只在败北者中计胜者"换一批比威力的人；
	#"指定胜者/追加胜者"在比完威力之后处理。改写只作用于本战场本回合，结算时清空
	var override:Dictionary = area._battle_override
	var override_winners:Array = []
	for id in override.get("winners", []):
		if not _battle_is_current(result):
			return false
		if player_ids.has(id):
			override_winners.append(id)
	if str(override.get("mode", "")) == "losers_only":
		effective_ids = excluded_ids

	if effective_ids.is_empty() and override_winners.is_empty():
		result["draw_areas"].append(area._area_name)
		#全员被排除也要留一条事实，否则这场战斗在日志里完全不存在
		if not _record_battle(area, player_ids, [], result):
			return false
		var event_score:int = 0
		for event:BaseEvent in area._events:
			if not _battle_is_current(result):
				return false
			event_score += (event._score as BaseNumber).number
		var competition_score:int = (area._score as BaseNumber).number if player_ids.size() >= 2 else 0
		result["details_by_area"][area._area_name] = {
			"players": player_ids.duplicate(), "effective_players": [],
			"powers": {}, "winners": [], "is_draw": true, "highest_power": 0,
			"event_score": event_score, "competition_score": competition_score,
			"total_score": event_score + competition_score, "score_gained": {}
		}
		return true

	var highest_power = null
	var winners:Array = []
	#每个人用于比较胜负的威力构成都记下来：事后核对"为什么是他赢"时不用再猜
	#（power=出牌威力、bonus=合计威力加成、location_benefit=地利，total 才是比较用的值）
	var powers:Dictionary = {}
	for id in effective_ids:
		if not _battle_is_current(result):
			return false
		#威力构成统一走 GetPlayerTotalPower：结算与界面共用同一份公式，
		#避免两边各算一套导致"界面显示 12、结算按 10 判"（本项目已出过这类误报）。
		#合计威力加成(言峰执行者、佐佐木燕返等)只在比较胜负时叠加、不写回 power 本身，
		#这条口径也在那个查询里
		var pw:Dictionary = GetPlayerTotalPower.breakdown(id)
		if not _battle_is_current(result):
			return false
		var power:int = int(pw["total"])
		powers[id] = pw
		if highest_power == null or power > highest_power:
			highest_power = power
			winners = [id]
		elif power == highest_power:
			winners.append(id)
	match str(override.get("mode", "")):
		"replace":
			winners = override_winners.duplicate()
		"add":
			for id in override_winners:
				if not _battle_is_current(result):
					return false
				if !winners.has(id):
					winners.append(id)
	if winners.is_empty():
		result["draw_areas"].append(area._area_name)

	#先记这场战斗的结果，再发战果、再派生败时点：
	#胜败时点里的效果要能查到本场战斗，不能等一切都派发完才补记
	if not _record_battle(area, player_ids, winners, result, powers):
		return false

	#总战果 = 事件牌战果 + 竞争战果（有至少一名对手时）
	var total_score:int = 0
	for event:BaseEvent in area._events:
		if not _battle_is_current(result):
			return false
		total_score += (event._score as BaseNumber).number
	var has_opponent:bool = player_ids.size() >= 2
	if has_opponent:
		total_score += (area._score as BaseNumber).number

	#这里只发基础奖池；全部效果完成后的实得由结算起止快照统一生成。
	#战果与胜时点落到"代表者"：分身棋子赢了算它的控制者赢（represented_id），独立玩家与 NPC 就是自己。
	#平分按参战条目数算（两个条目并列就是两份），与原规则一致
	if winners.size() == 1:
		var winner_id:int = winners[0]
		var rep_id:int = GameDataManager.represented_id(winner_id)
		if not _award_score(total_score, rep_id, result):
			return false
		TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], rep_id, null, _context)
		if not _battle_is_current(result):
			return false
		result["winners_by_area"][area._area_name] = [winner_id]
	elif winners.size() > 1:
		#平局：战果平分并向上取整
		var split_score:int = ceili(float(total_score) / winners.size())
		for winner_id in winners:
			if not _battle_is_current(result):
				return false
			var rep_id:int = GameDataManager.represented_id(winner_id)
			if not _award_score(split_score, rep_id, result):
				return false
			TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], rep_id, null, _context)
			if not _battle_is_current(result):
				return false
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
		if not _battle_is_current(result):
			return false
		if winners.has(id):
			continue
		var player_data = GameDataManager.get_player_data(id) as Dictionary
		var already_excluded:bool = buffs_checker.exec(ExcludedFromBattleWinEffect.EFFECT_NAME, id)
		if not _battle_is_current(result):
			return false
		if !already_excluded:
			TimePointChecker.dynamic_time_point([TimePoints.BATTLE_LOSE], GameDataManager.represented_id(id), null, _context)
			if not _battle_is_current(result):
				return false
	
	# 派发战斗结束时点由 exec 在"全部战区结算完之后"统一做一次（见 exec 里的
	# TimePoints.BATTLE_END 派发）：那里才能保证每个战场的战斗日志都已写好，
	# get_area_round_winners/get_area_round_participants 查得到本场结果。
	# 不要在这里按战区再派一次——同一回合多个战场会重复触发同一个战场效果
	return true

#把一场战斗的结果写进日志：参与者、胜者，以及开打时就已经出局的玩家（has_out 直接可筛）。
#按参与者逐个记一条，效果用 actor 查就自动只拿到自己参与过的战斗

func _record_battle(area:BaseMapArea, player_ids:Array, winners:Array, result:Dictionary, powers:Dictionary = {}) -> bool:
	if not _battle_is_current(result):
		return false
	var out_players:Array = []
	for pid in player_ids:
		if not _battle_is_current(result):
			return false
		if (GameDataManager.get_player_data(pid) as Dictionary)["is_out"]:
			out_players.append(pid)
	for pid in player_ids:
		if not _battle_is_current(result):
			return false
		GameLog.record("battle", int(pid), -1, area._area_name, null, ["battle"],
			{"players": player_ids.duplicate(), "winners": winners.duplicate(),
			"out_players": out_players.duplicate(), "has_out": !out_players.is_empty(),
			"powers": powers.duplicate()})
		if not _battle_is_current(result):
			return false
	return true


#处理不需要战斗胜利即可拿战果的区域（侦察）：所有在场玩家直接获得 _score 点战果

func _resolve_non_battle_area(area:BaseMapArea, player_ids:Array, result:Dictionary) -> bool:
	if not _battle_is_current(result):
		return false
	var score:int = (area._score as BaseNumber).number
	for id in player_ids:
		if not _battle_is_current(result):
			return false
		if score > 0:
			if not _award_score(score, id, result):
				return false
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
	return true
