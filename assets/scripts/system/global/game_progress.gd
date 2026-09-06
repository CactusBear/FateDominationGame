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
	#开局把已加载的效果全部入池，之后各卡牌进场时再补登记归属
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
	refresh_first_player()
	TimePointChecker.set_phase_time_points([TimePoints.DAY])
	TimePointChecker.global_time_point([TimePoints.DAY_START])
	advance_phase()


func end_round():
	current_phase_index = -1
	current_phase_player_index = 0
	current_player_id = -1
	TimePointChecker.set_phase_time_points([TimePoints.DAY])
	TimePointChecker.global_time_point([TimePoints.DAY_END])
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
	if current_phase_player_index >= ids.size():
		end_phase()
		return
	current_player_id = ids[current_phase_player_index]
	current_phase_player_index += 1
	TimePointChecker.dynamic_time_point([phase["mid"]], current_player_id)
	#该玩家在这个阶段的实际动作由UI/规则动作完成，做完后再调用next_player_in_phase()继续


#供UI和各处派发临时时点
func process_time_point(time_point:String, player_id:int = -1):
	if player_id == -1:
		TimePointChecker.global_time_point([time_point])
		return
	TimePointChecker.dynamic_time_point([time_point], player_id)
