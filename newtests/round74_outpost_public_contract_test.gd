extends Node

# 只验已有公开生命周期、座位查询和拒绝消息；不代替完整身份回归。
var failures:Array = []
var checks:int = 0

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	EffectManager.reset_runtime()
	GameProgress.reset_progress()
	GameLog.reset()
	GameData.player_data_library.clear()
	for id in range(2):
		var data:Dictionary = GameData.new_player_data()
		data.order.number = id
		data.is_out = false
		data.magic.number = 4
		GameData.player_data_library[id] = data
	GameData.player_id = 0
	EventResolver.new().clear_all()
	SituationResolver.new().clear_all()
	GameProgress.end_game([])
	GameProgress.reset_progress()
	check(not GameProgress.is_game_over and GameProgress.current_round == 0 and GameProgress.get_current_phase().is_empty() and GameProgress.current_player_id == -1, "public reset returns completed lifecycle to unstarted state")
	check(not GameProgress.can_end_current_player_action() and not GameProgress.end_current_player_action(), "unstarted lifecycle cannot complete an action")
	GameLog.reset()
	EffectManager.pop_messages(0)
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 1
	GameProgress.begin_phase()
	check(GameProgress.current_player_id == 0 and GameProgress.current_phase_player_index == 1, "begin_phase selects first actor with advanced cursor")
	check(TimePointChecker.phase_time_points.has(TimePoints.OUTPOST_PHASE), "begin_phase establishes outpost fixed window")
	check(GameData.player_data_library[0].current_time_points.has(TimePoints.SELF_PREFIX + TimePoints.OUTPOST_PHASE), "begin_phase establishes actor self outpost window")
	var builder = preload("res://scripts/match/view_builder.gd").new()
	var query = preload("res://scripts/match/match_seat_query.gd").new(builder)
	EffectManager.pop_messages(0)
	var facts_before:int = GameLog.query({}, null).size()
	var actions:Dictionary = query.actions(0)
	check(not GameProgress.can_end_current_player_action() and not actions.can_end and not actions.deploy_areas.is_empty(), "public actions and lifecycle agree deployment is required")
	check(query.actions(0) == actions and GameLog.query({}, null).size() == facts_before and EffectManager.pop_messages(0).is_empty(), "repeated completion queries publish no facts or messages")
	check(not GameProgress.end_current_player_action(), "completion rejects undeployed actor")
	check(EffectManager.pop_messages(0) == ["尚未完成前哨部署"], "real completion publishes exact deployment rejection message")
	check(GameProgress.current_player_id == 0 and GameProgress.current_phase_index == 1 and GameData.player_data_library[0].location == null and GameData.player_data_library[0].magic.number == 4, "rejected completion preserves phase actor location and magic")
	check(DeployRules.deploy_to_area(DeployRules.deployable_areas()[0], 0) != null, "chosen deployment uses existing production rule")
	check(GameProgress.can_end_current_player_action() and query.actions(0).can_end, "public actions and lifecycle agree deployed actor may complete")
	check(GameProgress.end_current_player_action() and GameProgress.current_player_id == 1, "public completion advances to next actor")
	check(not query.actions(0).can_end, "nonactor actions cannot complete next actor's action")
	GameProgress.reset_progress()
	check(not GameProgress.can_end_current_player_action() and not GameProgress.is_battle_broadcast_pending(), "reset cancels active completion lifecycle and broadcast wait")
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
