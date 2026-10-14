extends Node
#本修复常驻守卫；使用与 B24-I02 相同的公开业务刺激，不直接造战报/队列。
#旧实现也能加载：新增控制读口通过 has_method/call 检查，缺口报 CHECK 而非 Parse Error。
const UNKNOWN:int = 990024
const REJECTED_NO_EFFECT:int = 0
const PENDING_POST_BATTLE:int = 1
const SEALED:int = 2
const COMMITTED_STOP:int = 3
var checks:int = 0
var failures:Array = []
var cases:int = 0
var case_name:String = ""
var context:SessionContext = null

func _ready() -> void:
	call_deferred("run")

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok: failures.append(case_name + ":" + label)
	print("CHECK ", case_name, ":", label, " ", ok)

func state_is(expected:int) -> void:
	if not GameProgress.has_method("battle_resolution_state"):
		check(false, "explicit battle control channel exists")
		return
	check(GameProgress.call("battle_resolution_state") == expected, "explicit state " + str(expected))

func facts(tp:String) -> int:
	return GameLog.query({"type":"time_point", "tags":[tp]}, null).size()

func scores() -> Array:
	var values:Array = []
	for id in [0,1,2]: values.append(GameDataManager.find_player_data(id).score.number)
	return values

func fixture(name:String, confirm:bool, placed:bool) -> void:
	cases += 1
	case_name = name
	var reset:Dictionary = GameData.reset_game_session([0,1])
	check(reset.get("ok",false), "public current-session reset")
	context = reset.context
	#A1-08 新口沿用 GameData 签发的原 context；旧冻结保留单参数 ABI。
	var accepts_context:bool = false
	for method in GameProgress.get_method_list():
		if method.name == "reset_progress": accepts_context = method.args.size() >= 2
	if accepts_context and reset.has("context"):
		var cleared = GameProgress.callv("reset_progress", [confirm, reset.context])
		check(cleared is Dictionary and cleared.get("ok",false), "same-context progress reset")
	else:
		GameProgress.reset_progress(confirm)
	GameLog.reset()
	MapData.reset_board()
	for area:BaseMapArea in MapData.areas:
		area._events.clear()
		for loc:BaseLocation in area._locations: loc._players.clear()
	for id in [0,1]:
		SetPlayerData.new().exec("is_out", false, id, context)
		SetPlayerData.new().exec("order", BaseNumber.new(id), id, context)
	check(AddPlayer.new().exec(-1, [], {}, reset.context) == 2, "third member keeps nonterminal fixture")
	if placed:
		for id in [0,1]:
			check(SetLocation.new().exec(MapData.miyama._locations[id],id,false,true,true,context), "public placement " + str(id))
			SetPlayerData.new().exec("power", BaseNumber.new(10), id, context)
	var listener:BaseEffect = LoadHelper.load_effects([{
		"effect_name":"battle_contract_phase_end", "time_points":[TimePoints.SELF_PREFIX + TimePoints.BATTLE_PHASE_END],
		"priority":0, "is_pure_passive":true, "is_residue":false, "need_activate":false,
		"effect_numbers":[], "funcs":[]
	}],null,context)[0]
	check(EffectManager.register_effect(listener,0), "registered player phase-end listener")
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 3
	GameProgress.current_phase_player_index = 2
	GameProgress.current_player_id = 0
	GameLog.set_context(1,"battle")
	TimePointChecker.set_phase_time_points([TimePoints.DAY,TimePoints.PHASE,TimePoints.BATTLE_PHASE],context)
	check(not GameData.player_data_library.has(UNKNOWN), "unknown not created")

func assert_blocked(before_scores:Array, battle_count:int, expected_resolved:bool) -> void:
	check(GameProgress.current_round == 1 and GameProgress.get_current_phase().get("name","") == "battle", "no phase/round advance")
	check(GameProgress.has_method("battle_resolution_state") and GameProgress.call("battle_resolution_state") != SEALED, "unsealed battle control blocks tail")
	check(GameProgress.has_battle_resolved == expected_resolved, "settled history " + str(expected_resolved))
	check(not GameProgress.is_battle_broadcast_pending() and GameProgress.battle_broadcast_batch_id() == 0, "no broadcast or usable batch")
	check(facts(TimePoints.PHASE_END) == 0 and facts(TimePoints.BATTLE_PHASE_END) == 0 and facts(TimePoints.DAY_END) == 0, "no player/global phase-end or round-end")
	check(scores() == before_scores, "no extra score tail")
	check(GameLog.query({"type":"battle"}, null).size() == battle_count, "no replayed battle facts")
	check(not GameData.player_data_library.has(UNKNOWN), "no member creation")

func confirm_all() -> void:
	for id in GameProgress.battle_broadcast_confirmers(): GameProgress.confirm_battle_broadcast(int(id))

func rejection(confirm:bool) -> void:
	fixture("rejected_confirm" if confirm else "rejected_no_confirm", confirm, true)
	SetPlayerData.new().exec("controller",UNKNOWN,1,context)
	var before:Array = scores()
	var count:int = GameLog.query({"type":"battle"}, null).size()
	GameProgress.end_phase()
	state_is(REJECTED_NO_EFFECT)
	assert_blocked(before,count,false)
	check(facts(TimePoints.BATTLE) == 0 and facts(TimePoints.BATTLE_RESOLVE) == 0 and facts(TimePoints.BATTLE_END) == 0, "preflight refusal has no battle time points")
	check(not GameProgress.can_end_current_player_action(), "refused continuation is not actionable")
	check(not GameProgress.end_current_player_action(), "refused continuation bool is false")
	confirm_all()
	GameProgress.advance_phase()
	GameProgress.start_round()
	GameProgress.end_round()
	assert_blocked(before,count,false)
	state_is(REJECTED_NO_EFFECT)

func wait_then_seal(invalidate:bool) -> void:
	fixture("postchoice_stop" if invalidate else "postchoice_complete", true, true)
	var host := BaseAttack.new("battle_contract_host","",[])
	var factory := CloneContext.new()
	factory.configure_template(context,[host])
	host = factory.copy_result(host,context).object
	host._effects = LoadHelper.load_effects([{"effect_name":"battle_contract_choice","time_points":[TimePoints.BATTLE_END],"priority":0,
		"is_pure_passive":false,"is_residue":false,"effect_numbers":[],"need_activate":false,
		"options":[{"shown_option_name":"合法选项","funcs":[{"func_name":"store_value","parameters":["chosen"],"var_index":0}]}]}],host,context)
	check(EffectManager.register_effects(host._effects,0), "real battle-end optional effect registered")
	GameProgress.end_phase()
	state_is(PENDING_POST_BATTLE)
	var pending:BaseEffect = EffectManager.get_pending_active_effect()
	check(pending == host._effects[0] and EffectManager.is_waiting_for_choice(), "real battle-end choice pending")
	check(GameProgress.last_battle_result.has("_score_before"), "unsealed score origin retained")
	var before:Array = scores()
	var count:int = GameLog.query({"type":"battle"}, null).size()
	assert_blocked(before,count,true)
	GameProgress.end_phase()
	assert_blocked(before,count,true)
	if pending == null:
		check(false, "real choice prerequisite; do not manufacture pending object")
		return
	if invalidate: SetPlayerData.new().exec("controller",UNKNOWN,1,context)
	check(EffectManager.submit_option_choice(pending,[0]), "public legal option completes")
	check(not EffectManager.is_waiting_for_choice(), "pipeline no longer waiting")
	GameProgress.end_phase()
	if invalidate:
		state_is(COMMITTED_STOP)
		check(GameProgress.last_battle_result.has("_score_before"), "refused finalization remains observably unsealed")
		assert_blocked(before,count,true)
		check(not GameProgress.end_current_player_action(), "stopped continuation is not success")
		confirm_all()
		GameProgress.start_round()
		GameProgress.end_round()
		assert_blocked(before,count,true)
		#恢复 controller 后也不能自动重放已提交但中断的战斗。
		SetPlayerData.new().exec("controller",-1,1,context)
		GameProgress.end_phase()
		state_is(COMMITTED_STOP)
		assert_blocked(before,count,true)
	else:
		state_is(SEALED)
		check(GameProgress.has_battle_resolved and not GameProgress.last_battle_result.has("_score_before"), "settled choice result is sealed")
		check(GameProgress.is_battle_broadcast_pending(), "sealed result gets declared broadcast")
		check(facts(TimePoints.PHASE_END) == 1 and facts(TimePoints.BATTLE_END) == 1, "battle and close facts exactly once")
		check(scores() == before and GameLog.query({"type":"battle"},null).size() == count, "seal never repeats score or battle")
		confirm_all()
		check(GameProgress.current_round == 2, "completed choice advances after confirmation")

func legal(kind:String, confirm:bool = true) -> void:
	fixture("legal_" + kind + ("_confirm" if confirm else "_no_confirm"), confirm, kind != "empty")
	if kind == "no_winner":
		check(SetBattleResult.new().exec(MapData.miyama,[],"replace") != null, "declared no-winner result")
	GameProgress.end_phase()
	check(not GameProgress.last_battle_result.has("_score_before"), "legal result sealed including empty")
	if kind == "empty":
		check(GameProgress.last_battle_result.details_by_area.is_empty(), "legal no participants preserved")
	else:
		var detail:Dictionary = GameProgress.last_battle_result.details_by_area[MapData.miyama._area_name]
		if kind == "tie":
			check(detail.is_draw and detail.winners == [0,1], "equal power keeps tied winners")
		else:
			check(detail.winners.is_empty() and GameProgress.last_battle_result.draw_areas.has(MapData.miyama._area_name), "declared no winner retained; do not force is_draw")
	if confirm:
		state_is(SEALED)
		check(GameProgress.has_battle_resolved and GameProgress.is_battle_broadcast_pending(), "only sealed completion broadcasts")
		confirm_all()
	check(GameProgress.current_round == 2 and GameProgress.get_current_phase().get("name","") == "prepare", "legal completion advances")

func legacy_projection() -> void:
	fixture("legacy_projection",true,false)
	var report:Dictionary = BattleResolver.new(context).exec(GameDataManager.get_board_player_ids())
	check(report.has("winners_by_area") and report.has("draw_areas") and report.has("details_by_area"), "legacy Dictionary fields retained")
	check(not report.has("_score_before"), "legacy accepted empty report sealed")
	check(is_same(BattleResolver.finalize_result(report),report), "legacy finalize returns same report")

func run() -> void:
	rejection(true)
	rejection(false)
	wait_then_seal(true)
	wait_then_seal(false)
	legal("empty")
	legal("tie")
	legal("no_winner")
	legal("empty",false)
	legacy_projection()
	print("RESULT ", JSON.stringify({"suite":"battle_result_commit_gate", "cases":cases, "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
