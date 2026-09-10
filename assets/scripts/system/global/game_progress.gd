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
#本回合战斗阶段结算结果，供最终回合判定胜负时查询深山町战斗胜者
var last_battle_result:Dictionary = {}
var climax_keep_counts:Dictionary = {
	8: BaseNumber.new(4),
	9: BaseNumber.new(3),
	10: BaseNumber.new(2)
}

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
	EffectManager.sync_loaded_effect_pool()
	TimePointChecker.set_phase_time_points([TimePoints.GAME])
	TimePointChecker.global_time_point([TimePoints.GAME_START])
	start_round()


func end_game():
	is_game_over = true
	TimePointChecker.set_phase_time_points([])
	TimePointChecker.global_time_point([TimePoints.GAME_END])


#回合
func start_round():
	if is_game_over:
		return
	current_round += 1
	if current_round > total_rounds.number:
		end_game()
		return
	current_phase_index = -1
	current_phase_player_index = 0
	current_player_id = -1
	has_battle_resolved = false
	refresh_first_player()
	#每回合开始时重置本回合类记录字段，并派发ROUND_START_RESET供效果监听
	for id in GameDataManager.get_active_player_ids():
		var player_data = GameDataManager.get_player_data(id) as Dictionary
		player_data["played_attacks_this_turn"] = []
		player_data["score_gained_this_turn"] = 0
		player_data["command_spell_used_this_turn"] = false
		player_data["command_spell_gained_magic"] = false
		player_data["temp_locations"] = []
		TimePointChecker.dynamic_time_point([TimePoints.ROUND_START_RESET], id)
	TimePointChecker.set_phase_time_points([TimePoints.DAY])
	TimePointChecker.global_time_point([TimePoints.DAY_START])
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
		VictoryResolver.new().exec(last_battle_result)
		end_game()
		return
	for id in GameDataManager.get_active_player_ids():
		var player_data = GameDataManager.get_player_data(id) as Dictionary
		player_data["last_turn_location"] = player_data["location"]
		player_data["is_battle"] = false
		player_data["is_battle_win"] = false
		player_data["is_battle_lose"] = false
		#残留牌留在场上，回合结束不处理（残留牌只在自身效果满足条件时自行关闭）
		DiscardPlayedCards.new().exec(id)
		#先清理再重建合计威力基线：规则上残留牌跨回合留场并继续提供威力，
		#所以基线是留场明置牌的威力之和，同时丢弃回合内的非卡牌来源加成
		SyncPower.new().exec(id)
	#规则：【败北】状态持续至回合结束
	DefeatBuff.clear_all()
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
	if is_game_over:
		return
	current_phase_index += 1
	current_phase_player_index = 0
	current_player_id = -1
	if current_phase_index >= phases.size():
		end_round()
		return
	begin_phase()


func begin_phase():
	var phase = get_current_phase()
	if phase.is_empty():
		return
	#整个阶段内都成立的时点
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, phase["mid"]])
	TimePointChecker.global_time_point([TimePoints.PHASE_START, phase["start"]])
	next_player_in_phase()


func end_phase():
	var phase = get_current_phase()
	if phase.is_empty():
		return
	if phase["name"] == "battle" and !has_battle_resolved:
		has_battle_resolved = true
		last_battle_result = BattleResolver.new().exec(GameDataManager.get_active_player_ids(), BaseNumber.new(1))
	TimePointChecker.global_time_point([TimePoints.PHASE_END, phase["end"]])
	advance_phase()


#规则：每个阶段开始时，所有玩家按回合顺位，从顺位第一的玩家开始以顺时针依次进行自己的阶段。
#派发出去的是phase["mid"]，触发者拿到self_xxx_phase，其他人拿到others_xxx_phase，
#所以"当前玩家先处理完自己的效果，再轮到下一位"是时点表本身带来的，不需要额外的排序逻辑
func next_player_in_phase():
	if is_game_over:
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
		TimePointChecker.dynamic_time_point([phase["mid"]], current_player_id)
		return
	end_phase()


#当前玩家完成本阶段行动后使用的唯一推进入口。
func end_current_player_action() -> bool:
	if is_game_over or current_player_id == -1 or get_current_phase().is_empty():
		return false
	next_player_in_phase()
	return true


#供UI和各处派发临时时点
func process_time_point(time_point:String, player_id:int = -1):
	if player_id == -1:
		TimePointChecker.global_time_point([time_point])
		return
	TimePointChecker.dynamic_time_point([time_point], player_id)
