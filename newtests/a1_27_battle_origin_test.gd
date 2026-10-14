extends Node
var checks:int = 0
var failures:Array = []
var case_name:String = ""
var context:SessionContext
var switch_baseline:Dictionary = {}
var switch_count:int = 0
var switch_full_reset:bool = false

#真实时点监听中的同步可重入方法；只注入生命周期，不替代战斗/奖励实现。
class ResetEffect extends BaseEffect:
	var armed:bool = false
	var callback:Callable
	func has_options() -> bool:
		if armed:
			armed = false
			callback.call()
		return super.has_options()

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok: failures.append(case_name + ":" + label)
	print("CHECK ", case_name, ":", label, " ", ok)

func fixture(name:String, placed:bool = true) -> void:
	case_name = name
	var reset:Dictionary = GameData.reset_game_session([0,1])
	check(reset.ok, "new session")
	context = reset.context
	GameProgress.reset_progress(true,reset.context)
	MapData.reset_board()
	for area:BaseMapArea in MapData.areas:
		area._events.clear()
		for loc:BaseLocation in area._locations: loc._players.clear()
	for id in [0,1]:
		SetPlayerData.new().exec("is_out",false,id,context)
		SetPlayerData.new().exec("power",BaseNumber.new(10),id,context)
		if placed: check(SetLocation.new().exec(MapData.miyama._locations[id],id,false,true,true,context), "placement " + str(id))
	GameLog.reset()

func snapshot() -> Dictionary:
	var scores:Array = []
	var battles:Array = []
	for id in [0,1]:
		var data:Dictionary = GameDataManager.find_player_data(id)
		scores.append(data.score.number)
		battles.append(data.is_battle)
	return {"scores":scores,"is_battle":battles,"logs":GameLog.query({},null).size()}

func stale_resolver() -> void:
	fixture("old_resolver")
	var resolver := BattleResolver.new()
	var delayed:Callable = resolver.exec_result.bind([0,1])
	var library:Dictionary = GameData.player_data_library
	GameProgress.reset_progress()
	check(is_same(library,GameData.player_data_library), "progress reset reuses members")
	var before:Dictionary = snapshot()
	var outcome:Array = delayed.call()
	check(outcome[0] == BattleResolver.ResultState.REJECTED_NO_EFFECT, "old captured exec rejected")
	check(snapshot() == before, "old exec has no new score/log/is_battle delta")
	var current:Array = BattleResolver.new().exec_result([0,1])
	check(current[0] == BattleResolver.ResultState.SEALED, "fresh same-ID settlement legal")

func old_result() -> void:
	fixture("old_result")
	var host := BaseAttack.new("origin_choice","",[])
	host._effects = LoadHelper.load_effects([{"effect_name":"origin_choice","time_points":[TimePoints.BATTLE_END],"priority":0,
		"is_pure_passive":false,"is_residue":false,"effect_numbers":[],"need_activate":false,
		"options":[{"shown_option_name":"选项","funcs":[{"func_name":"store_value","parameters":["ok"],"var_index":0}]}]}],host,context)
	check(EffectManager.register_effects(host._effects,0), "real pending listener")
	var outcome:Array = BattleResolver.new().exec_result([0,1])
	var report:Dictionary = outcome[1]
	check(outcome[0] == BattleResolver.ResultState.PENDING_POST_BATTLE and report.has("_score_before"), "real unsealed result")
	fixture("old_result_new_same_ID")
	SetPlayerData.new().exec("score",BaseNumber.new(73),0,context)
	var before:Dictionary = snapshot()
	var detail_before:Dictionary = report.details_by_area.duplicate(true)
	check(is_same(BattleResolver.finalize_result(report),report), "legacy result identity retained")
	check(report.has("_score_before"), "stale result not sealed")
	check(report.details_by_area == detail_before, "stale result not recomputed from new scores")
	check(BattleResolver.finalize_result_state(report,outcome[0]) == BattleResolver.ResultState.COMMITTED_STOP, "stale pending state stops")
	check(snapshot() == before, "old finalize no new game delta")

func legal() -> void:
	fixture("legal_tie")
	var outcome:Array = BattleResolver.new().exec_result()
	check(outcome[0] == BattleResolver.ResultState.SEALED, "default board legal")
	var report:Dictionary = outcome[1]
	var detail:Dictionary = report.details_by_area.get(MapData.miyama._area_name,{})
	check(not detail.is_empty(), "legal settlement produced real detail prerequisite")
	if detail.is_empty(): return
	check(detail.is_draw and detail.winners == [0,1], "tie retains both winners")
	var share:int = ceili(float(detail.total_score) / detail.winners.size())
	check(snapshot().scores == [share,share], "legal tie awards declared pool to each winner")
	check(detail.score_gained == {0:share,1:share}, "sealed report keeps actual declared rewards")
	check(not report.has("_score_before"), "legal sealed")
	check(is_same(BattleResolver.finalize_result(report),report), "sealed legacy no-op identity")
	var facts:Array = []
	for row:Dictionary in GameLog.query({},null):
		facts.append({"type":row.type,"actor":row.actor,"target":row.target,"place":row.place,"tags":row.tags,"data":row.data})
	print("LEGAL_BASELINE ",JSON.stringify({"winners_by_area":report.winners_by_area,"draw_areas":report.draw_areas,"details_by_area":report.details_by_area,"scores":snapshot().scores,"facts":facts}))
	fixture("legal_no_winner")
	SetBattleResult.new().exec(MapData.miyama,[],"replace")
	outcome = BattleResolver.new().exec_result()
	check(outcome[0] == BattleResolver.ResultState.SEALED and outcome[1].winners_by_area.is_empty(), "declared no winner still sealed")
	check(outcome[1].draw_areas.has(MapData.miyama._area_name), "declared no winner draw area retained")
	fixture("legal_empty",false)
	outcome = BattleResolver.new().exec_result()
	check(outcome[0] == BattleResolver.ResultState.SEALED and outcome[1].details_by_area.is_empty(), "legal empty sealed")

func switch_session() -> void:
	switch_count += 1
	if switch_full_reset:
		GameData.reset_game_session([0,1])
	else:
		GameProgress.reset_progress()
	for id in [0,1]: (GameDataManager.find_player_data(id).score as BaseNumber).set_num(BaseNumber.new(73 + id))
	switch_baseline = snapshot()

func callback_reset(tp:String, full_reset:bool = false, scout:bool = false) -> void:
	fixture("callback_" + tp + ("_new_members" if full_reset else "_same_members") + ("_scout" if scout else ""))
	if tp == TimePoints.BATTLE_LOSE: SetPlayerData.new().exec("power",BaseNumber.new(99),0,context)
	if scout:
		for id in [0,1]: check(SetLocation.new().exec(MapData.scout._locations[id],id,false,true,true,context),"scout placement " + str(id))
		GameLog.reset()
	switch_count = 0
	switch_full_reset = full_reset
	var listener := ResetEffect.new("reset_at_" + tp,[tp],0,true,false)
	listener._need_activate = false
	listener.callback = switch_session
	var bound:Dictionary = SessionGeneration.bind_origin(listener,context.token(),&"a1_27_fixture")
	check(bound.ok and listener.bind_runtime_context(bound.context), "trusted listener origin")
	check(EffectManager.register_effect(listener,0), "real reset listener registered")
	listener.armed = true
	var outcome:Array = BattleResolver.new().exec_result([0,1])
	check(switch_count == 1, "real synchronous lifecycle callback reached")
	check(outcome[0] == BattleResolver.ResultState.COMMITTED_STOP, "old active settlement stops")
	check(snapshot() == switch_baseline, "callback return leaves new score/log/is_battle baseline unchanged")
	print("SWITCH_EVIDENCE ",JSON.stringify({"case":case_name,"baseline":switch_baseline,"after":snapshot()}))

func legal_pending(stop:bool) -> void:
	fixture("pending_stop" if stop else "pending_seal")
	var host := BaseAttack.new("pending_legal","",[])
	host._effects = LoadHelper.load_effects([{"effect_name":"pending_legal","time_points":[TimePoints.BATTLE_END],"priority":0,
		"is_pure_passive":false,"is_residue":false,"effect_numbers":[],"need_activate":false,
		"options":[{"shown_option_name":"选项","funcs":[{"func_name":"store_value","parameters":["ok"],"var_index":0}]}]}],host,context)
	check(EffectManager.register_effects(host._effects,0), "trusted real pending listener")
	var outcome:Array = BattleResolver.new().exec_result([0,1])
	var report:Dictionary = outcome[1]
	check(outcome[0] == BattleResolver.ResultState.PENDING_POST_BATTLE, "same-session pending state")
	var before:Dictionary = snapshot()
	check(BattleResolver.finalize_result_state(report,outcome[0]) == BattleResolver.ResultState.PENDING_POST_BATTLE, "pending remains pending without replay")
	check(snapshot() == before, "pending no score/log replay")
	var pending:BaseEffect = EffectManager.get_pending_active_effect()
	if pending == null:
		check(false,"real pending prerequisite")
		return
	if stop: SetPlayerData.new().exec("controller",990027,1,context)
	check(EffectManager.submit_option_choice(pending,[0]), "same-session real choice completes")
	before = snapshot()
	var state:int = BattleResolver.finalize_result_state(report,outcome[0])
	check(state == (BattleResolver.ResultState.COMMITTED_STOP if stop else BattleResolver.ResultState.SEALED), "same-session seal or committed member stop")
	check(report.has("_score_before") == stop, "temporary snapshot retained only when stopped")
	check(is_same(BattleResolver.finalize_result(report),report), "public finalize same report")
	check(snapshot() == before, "finalize no score/log replay")

func rejection() -> void:
	fixture("whole_batch_rejected")
	var before:Dictionary = snapshot()
	var outcome:Array = BattleResolver.new().exec_result([0,990027,1])
	check(outcome[0] == BattleResolver.ResultState.REJECTED_NO_EFFECT, "one unknown rejects whole batch")
	check(snapshot() == before and not GameData.player_data_library.has(990027), "no filtered partial settlement or member creation")

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	print("USER_DIR ",OS.get_user_data_dir())
	if OS.get_cmdline_user_args().has("intra_score_probe"):
		callback_reset(TimePoints.BEFORE_SCORE_ADD)
	else:
		stale_resolver()
		old_result()
		callback_reset(TimePoints.BATTLE)
		callback_reset(TimePoints.BATTLE_RESOLVE)
		callback_reset(TimePoints.BATTLE_WIN)
		callback_reset(TimePoints.BATTLE_LOSE)
		callback_reset(TimePoints.SCORE_ADD,false,true)
		callback_reset(TimePoints.BATTLE_END)
		callback_reset(TimePoints.SCORE_ADD)
		callback_reset(TimePoints.BEFORE_SCORE_ADD,true)
		legal_pending(false)
		legal_pending(true)
		rejection()
		legal()
		callback_reset(TimePoints.BEFORE_SCORE_ADD)
	print("RESULT ",JSON.stringify({"suite":"a1_27_battle_origin","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
