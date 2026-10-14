extends "res://tests/post_battle_choice_test.gd"
# 复用原真实两胜者链；只观察公共结果状态/推进、战报封存标记及日志。
# 不读取或调用生产对象私字段，不伪造 resolver 回执或战后选择。
const UNKNOWN:int = 990051
var accepted_report:Dictionary = {}

func _check_wait_boundary(event:BaseEvent, label:String) -> void:
	if label.ends_with(": after settlement"):
		accepted_report = GameProgress.last_battle_result
	super._check_wait_boundary(event, label)
	check(GameProgress.battle_resolution_state() == BattleResolver.ResultState.PENDING_POST_BATTLE, label + ": settled pending is not sealed")
	check(GameProgress.last_battle_result.has("_score_before"), label + ": accepted report retains unsealed origin")
	check(not GameProgress.is_battle_broadcast_pending(), label + ": waiting cannot publish broadcast")
	var scores:Array = _scores()
	GameProgress.end_phase(fixture_context)
	check(GameProgress.has_battle_resolved, label + ": direct reentry retains settled flag")
	check(_scores() == scores and _battle_entries().size() == 3, label + ": direct reentry cannot replay rewards or battle")
	check(GameProgress.last_battle_result.has("_score_before") and _time_point_count(TimePoints.PHASE_END) == 0, label + ": direct reentry cannot seal or close")

func blocked(expected:int, label:String) -> void:
	print("OBSERVATION ", JSON.stringify({"label":label, "expected":expected, "state":GameProgress.battle_resolution_state(), "settled":GameProgress.has_battle_resolved, "guard":EffectManager.runtime_guard_status(), "battle_end":_time_point_count(TimePoints.BATTLE_END)}))
	check(GameProgress.battle_resolution_state() == expected, label + ": explicit result state")
	check(not GameProgress.has_battle_resolved, label + ": rejected or unfinished resolver is not settled")
	check(not GameProgress.is_battle_broadcast_pending(), label + ": no broadcast")
	check(GameProgress.current_round == 1 and GameProgress.get_current_phase().get("name") == "battle", label + ": phase retained")
	check(_time_point_count(TimePoints.PHASE_END) == 0 and _time_point_count(TimePoints.DAY_END) == 0, label + ": no closing tail")
	var scores:Array = _scores()
	var facts:int = GameLog.query({"type":"battle"}, null).size()
	GameProgress.end_phase(fixture_context)
	check(not GameProgress.end_current_player_action(fixture_context), label + ": public continuation refuses")
	check(not GameProgress.has_battle_resolved and _scores() == scores and GameLog.query({"type":"battle"}, null).size() == facts, label + ": retry never creates settled success or repeats rewards")

# 原两轮夹具由自然 start_round 清结算状态；负向用公共 reset 显式隔开拒绝状态。
func negative_setup() -> BaseEvent:
	var event:BaseEvent = _setup()
	if event == null: return null
	check(GameProgress.reset_progress(false, fixture_context).ok, "negative fixture resets progress in original context")
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 3
	GameProgress.current_phase_player_index = 0
	GameProgress.current_player_id = -1
	GameLog.reset()
	GameProgress.begin_phase(fixture_context)
	return event

func negative_cases() -> void:
	var event:BaseEvent = negative_setup()
	if event == null: return
	SetPlayerData.new().exec("controller", UNKNOWN, 1, fixture_context)
	check(GameDataManager.find_player_data(1).controller == UNKNOWN, "refusal fixture has invalid representative")
	GameProgress.end_phase(fixture_context)
	blocked(BattleResolver.ResultState.REJECTED_NO_EFFECT, "preflight refusal")
	check(_battle_entries().is_empty() and _time_point_count(TimePoints.BATTLE) == 0, "preflight refusal has no battle work")
	SetPlayerData.new().exec("controller", -1, 1, fixture_context)

	event = negative_setup()
	if event == null: return
	var interrupt:Array = LoadHelper.load_effects([{
		"effect_name":"settled_flag_interrupt", "time_points":[TimePoints.BATTLE_RESOLVE], "priority":0,
		"is_pure_passive":true, "is_residue":false, "need_activate":false, "effect_numbers":[],
		"funcs":[{"func_name":"set_player_data", "parameters":["controller", UNKNOWN, 1]}]
	}], null, fixture_context)
	check(interrupt.size() == 1 and EffectManager.register_effect(interrupt[0], 0), "interrupt uses real declared effect")
	GameProgress.end_phase(fixture_context)
	blocked(BattleResolver.ResultState.COMMITTED_STOP, "interrupted settlement")
	check(_time_point_count(TimePoints.BATTLE_RESOLVE) == 1 and _time_point_count(TimePoints.BATTLE_END) == 0, "interrupt reached resolver before completed settlement")
	SetPlayerData.new().exec("controller", -1, 1, fixture_context)

	event = negative_setup()
	if event == null: return
	MatchJournal.audit_error = "settled-flag deliberate audit refusal"
	GameProgress.end_phase(fixture_context)
	check(EffectManager.runtime_guard_status().paused, "audit refusal really pauses existing guard")
	check(GameProgress.battle_resolution_state() == BattleResolver.ResultState.PENDING_POST_BATTLE and GameProgress.has_battle_resolved, "postsettlement audit wait remembers actual settled battle")
	check(GameProgress.last_battle_result.has("_score_before") and not GameProgress.is_battle_broadcast_pending(), "postsettlement audit wait cannot seal or broadcast")
	check(_time_point_count(TimePoints.PHASE_END) == 0 and _time_point_count(TimePoints.DAY_END) == 0, "postsettlement audit wait cannot close phase")
	var audit_detail:Dictionary = GameProgress.last_battle_result.details_by_area[MapData.miyama._area_name]
	check(_scores()[0] == 0 and _scores()[1] > 0 and _scores()[1] == _scores()[2] and audit_detail.score_gained[1] == _scores()[1] and audit_detail.score_gained[2] == _scores()[2], "postsettlement audit fixture actually committed original tied rewards")
	print("OBSERVATION ", JSON.stringify({"label":"postsettlement audit inspection", "scores":_scores(), "state":GameProgress.battle_resolution_state(), "settled":GameProgress.has_battle_resolved, "guard":EffectManager.runtime_guard_status()}))
	var scores:Array = _scores()
	GameProgress.end_phase(fixture_context)
	check(GameProgress.has_battle_resolved and _scores() == scores and _battle_entries().size() == 3, "postsettlement audit retry retains state without replay")
	MatchJournal.audit_error = ""

	event = negative_setup()
	if event == null: return
	var roots:Array = LoadHelper.load_effects([{"effect_name":"settled_flag_preexisting_guard", "time_points":[], "priority":0,
		"is_pure_passive":true, "is_residue":false, "need_activate":false, "effect_numbers":[], "funcs":[]}], null, fixture_context)
	check(roots.size() == 1, "preexisting audit fixture has trusted runtime root")
	if roots.size() != 1: return
	check(EffectManager.register_effect(roots[0], 0), "preexisting audit root has registered owner")
	MatchJournal.audit_error = "settled-flag deliberate preexisting audit refusal"
	EffectManager.run_func_descriptor({"func_name":"queue_optional_effect_for_players", "parameters":[[0], [], "guard", "settled_flag_preexisting_choice", []]}, roots[0], fixture_context)
	check(EffectManager.runtime_guard_status().paused, "real prior operation leaves audit pending before battle")
	GameProgress.end_phase(fixture_context)
	blocked(-1, "preexisting audit prevents battle start")
	check(_battle_entries().is_empty() and _time_point_count(TimePoints.BATTLE_END) == 0, "preexisting audit emits no settled battle work")
	MatchJournal.audit_error = ""

func empty_and_stale() -> void:
	var event:BaseEvent = negative_setup()
	if event == null: return
	for id in range(3):
		check(RemoveFromBoard.new().exec(id, fixture_context), "empty battle removes participant %d through public removal" % id)
	GameProgress.battle_broadcast_requires_confirm = true
	GameProgress.end_phase(fixture_context)
	check(GameProgress.battle_resolution_state() == BattleResolver.ResultState.SEALED and GameProgress.has_battle_resolved, "accepted empty battle is settled and sealed")
	check(GameProgress.last_battle_result.details_by_area.is_empty() and not GameProgress.last_battle_result.has("_score_before"), "empty report seals without fabricated participants")
	check(GameProgress.is_battle_broadcast_pending() and _time_point_count(TimePoints.PHASE_END) == 1, "empty battle follows original sealed tail")
	GameProgress.battle_broadcast_requires_confirm = false
	var old:SessionContext = fixture_context
	var resolver:BattleResolver = BattleResolver.new(old)
	check(EventResolver.new().clear_all(old).ok, "stale fixture clears original event")
	var reset:Dictionary = EffectManager.reset_runtime()
	check(reset.ok, "stale fixture changes real lifecycle")
	fixture_context = reset.context
	check(GameProgress.reset_progress(false, fixture_context).ok, "new lifecycle explicitly clears progress")
	var result:Array = resolver.exec_result([])
	check(result[0] == BattleResolver.ResultState.REJECTED_NO_EFFECT, "stale resolver rejects instead of settled success")
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 3
	GameProgress.end_phase(old)
	check(not GameProgress.has_battle_resolved and GameProgress.battle_resolution_state() == -1, "stale progress source cannot set settled flag")

func sealed_tail_case() -> void:
	var event:BaseEvent = negative_setup()
	if event == null: return
	GameProgress.battle_broadcast_requires_confirm = true
	var tail:Array = LoadHelper.load_effects([{"effect_name":"settled_flag_phase_tail", "time_points":[TimePoints.PHASE_END], "priority":0,
		"is_pure_passive":true, "is_residue":false, "need_activate":false, "effect_numbers":[],
		"funcs":[{"func_name":"edit_score", "parameters":[null, BaseNumber.new(1), 1]}]}], null, fixture_context)
	check(tail.size() == 1 and EffectManager.register_effect(tail[0], 1), "phase-tail fixture uses real registered score effect")
	GameProgress.end_phase(fixture_context)
	var report:Dictionary = GameProgress.last_battle_result
	var before:Array = _scores()
	check(GameProgress.has_battle_resolved and report.has("_score_before"), "tail fixture is settled but unsealed while choices wait")
	for index in range(2):
		var pending:BaseEffect = EffectManager.get_pending_active_effect()
		check(pending != null, "tail fixture has real winner choice %d" % index)
		if pending == null: return
		check(EffectManager.submit_option_choice(pending, [index]), "tail fixture answers real independent choice %d" % index)
		if index == 0:
			check(report.has("_score_before") and _time_point_count(TimePoints.PHASE_END) == 0, "one answer cannot seal or dispatch phase tail")
	check(not EffectManager.is_waiting_for_choice(), "tail fixture drains both real answers")
	GameProgress.end_phase(fixture_context)
	check(GameProgress.battle_resolution_state() == BattleResolver.ResultState.SEALED and not report.has("_score_before"), "both answers permit actual same-report seal")
	check(_scores() == [before[0], before[1] + 1, before[2]], "real phase-end reward runs only after answers")
	check(report.details_by_area[MapData.miyama._area_name].score_gained[1] == before[1], "phase-end reward never contaminates sealed battle actual-gain snapshot")
	check(GameProgress.is_battle_broadcast_pending() and _time_point_count(TimePoints.PHASE_END) == 1, "sealed phase tail publishes one declared broadcast")
	GameProgress.end_phase(fixture_context)
	check(_scores() == [before[0], before[1] + 1, before[2]] and _time_point_count(TimePoints.PHASE_END) == 1, "sealed tail reentry cannot duplicate phase reward")
	GameProgress.battle_broadcast_requires_confirm = false

func run() -> void:
	var initial:Dictionary = EffectManager.reset_runtime()
	check(initial.ok, "fixture establishes original lifecycle context")
	fixture_context = initial.get("context")
	await _test_post_battle_choices({1:0, 2:1}, "first restores")
	check(not accepted_report.has("_score_before") and not accepted_report.get("details_by_area", {}).is_empty(), "first answers seal the same nonempty report before next round")
	check(not GameProgress.has_battle_resolved, "next round resets previous settled flag")
	await _test_post_battle_choices({1:1, 2:0}, "second restores")
	check(not accepted_report.has("_score_before") and not accepted_report.get("details_by_area", {}).is_empty(), "second answers seal the same nonempty report before next round")
	sealed_tail_case()
	negative_cases()
	empty_and_stale()
	print("RESULT ", JSON.stringify({"suite":"postbattle-settled-flag", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
