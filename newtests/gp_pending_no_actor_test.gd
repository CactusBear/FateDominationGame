extends Node
var checks:int = 0
var failures:Array = []
var observations:Array = []
var parents:Array = []
var context:SessionContext = null

func check(ok:bool, label:String) -> bool:
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", label, " ", ok)
	return ok

func snap() -> Dictionary:
	return {"actor":GameProgress.current_player_id,"phase":GameProgress.get_current_phase().get("name", ""),
		"index":GameProgress.current_phase_index,"pending":GameProgress.get("_phase_end_pending"),
		"running":GameProgress.get("_phase_end_running"),"effect_running":EffectManager.is_running,
		"waiting":EffectManager.is_waiting_for_choice(),"game_over":GameProgress.is_game_over,
		"can_end":GameProgress.can_end_current_player_action(),"keys":GameData.player_data_library.keys()}

func record(label:String, extra:Dictionary = {}) -> void:
	var s:Dictionary = snap()
	s["label"] = label
	s.merge(extra)
	observations.append(s)
	print("OBSERVATION ", JSON.stringify(s))

func setup(label:String) -> bool:
	GameStart.end_session()
	var reset:Dictionary = GameData.reset_game_session([])
	if not check(reset.ok,label + " real session reset"): return false
	var progress:Dictionary = GameProgress.reset_progress(false, reset.context)
	if not check(progress.ok,label + " original lifecycle context retained"): return false
	context = progress.context
	parents.clear()
	var first:int = AddPlayer.new().exec(-1,[],{"order":0,"player_name":"probe0"},context)
	var second:int = AddPlayer.new().exec(-1,[],{"order":1,"player_name":"probe1"},context)
	if not check(first == 0 and second == 1 and GameDataManager.is_independent(0) and GameDataManager.is_independent(1),label + " real independent members"): return false
	GameProgress.advance_phase(context)
	if not check(not GameProgress.get_current_phase().is_empty(),label + " phase exists before prepare oracle"): return false
	return check(GameProgress.get_current_phase().name == "prepare" and GameProgress.current_player_id == 0,label + " natural prepare actor")

func register_wait(point:String, label:String) -> BaseEffect:
	var declaration:Dictionary = {"effect_name":label,"time_points":[point],"priority":0,
		"is_pure_passive":true,"is_residue":false,"need_activate":false,"effect_numbers":[],
		"funcs":[{"func_name":"ask_player_option","parameters":[[
			{"shown_option_name":"继续","funcs":[{"func_name":"store_value","parameters":[label],"var_index":5}]}
		],label],"var_index":-1},
		{"func_name":"store_value","parameters":[{"self_var":5}],"var_index":6}]}
	var produced:Array = LoadHelper.load_effects([declaration],null,context)
	if not check(produced.size() == 1,label + " original-context runtime wait factory"): return null
	var parent:BaseEffect = produced[0]
	parents.append(parent)
	check(parent.runtime_source_status().ok and EffectManager.register_effects([parent],0),label + " original-context runtime wait registered")
	return parent

func answer(parent:BaseEffect, label:String) -> bool:
	var child = EffectManager.get_pending_active_effect()
	if not check(child != null and child.has_options(),label + " real option waiting"): return false
	if not check(EffectManager.submit_option_choice(child,[0]),label + " public option answer accepted"): return false
	return check(parent._self_vars.size() > 6 and parent._self_vars[6] == parent._self_vars[5] and not EffectManager.is_waiting_for_choice() and not EffectManager.is_running,label + " declared option and tail executed pipeline clear")

func count(point:String) -> int:
	var n:int = 0
	for fact in GameLog.query({"type":"time_point","actor":-1},0,-1):
		if fact.tags.has(point): n += 1
	return n

func no_actor() -> void:
	var label:String = "no_actor"
	if not setup(label): return
	var ending:BaseEffect = register_wait(TimePoints.OUTPOST_PHASE_END,label + " ending")
	register_wait(TimePoints.ACTION_PHASE_START,label + " successor marker")
	for id in [0,1]: EditLives.new().exec(BaseNumber.new(0),BaseNumber.new(0),id)
	if not check(GameDataManager.find_player_data(0).is_out and GameDataManager.find_player_data(1).is_out and GameData.player_data_library.size() == 2,label + " real retirement retains member entries"): return
	check(not GameProgress.is_game_over,label + " retirement does not immediately end game")
	GameProgress.advance_phase(context)
	record(label + " waiting")
	if not check(not GameProgress.get_current_phase().is_empty(),label + " phase exists before pending oracle"): return
	if not check(GameProgress.current_player_id == -1 and GameProgress.get_current_phase().name == "outpost" and bool(GameProgress.get("_phase_end_pending")) and EffectManager.is_waiting_for_choice(),label + " naturally generated no actor pending"): return
	var waiting:Dictionary = snap()
	check(not GameProgress.end_current_player_action(context) and snap() == waiting,label + " pending choice blocks end without mutation")
	if not answer(ending,label): return
	await get_tree().process_frame
	record(label + " after answer")
	if not check(GameProgress.current_player_id == -1 and bool(GameProgress.get("_phase_end_pending")) and not bool(GameProgress.get("_phase_end_running")) and not EffectManager.is_running and not EffectManager.is_waiting_for_choice() and not GameProgress.is_game_over,label + " clear pipeline retains no actor pending"): return
	check(GameProgress.can_end_current_player_action(),label + " query can end true")
	var before:Dictionary = snap()
	var driver = MatchDriver.new()
	var planned:String = driver.prepare_step(1.0)
	var stepped:bool = driver.step(1.0)
	check(planned == "" and not stepped and snap() == before,label + " existing real driver no actor gate does not resume either version")
	record(label + " automatic driver",{"planned":planned,"stepped":stepped})
	var accepted:bool = GameProgress.end_current_player_action(context)
	record(label + " public end",{"accepted":accepted,"before":before})
	if not check(not GameProgress.get_current_phase().is_empty(),label + " phase exists before resumed cleanup oracle"): return
	check(accepted and GameProgress.get_current_phase().name == "action",label + " public end must resume cleanup")
	check(EffectManager.is_waiting_for_choice() and not bool(GameProgress.get("_phase_end_pending")),label + " successor marker reached not stopped in old cleanup")
	var resumed:Dictionary = snap()
	check(not GameProgress.end_current_player_action(context) and snap() == resumed,label + " repeated end cannot bypass successor wait")
	check(count(TimePoints.OUTPOST_PHASE_END) == 1,label + " global ending dispatched once")

func ordinary() -> void:
	var label:String = "ordinary_last_actor"
	if not setup(label): return
	var ending:BaseEffect = register_wait(TimePoints.PREPARE_PHASE_END,label + " ending")
	register_wait(TimePoints.OUTPOST_PHASE_START,label + " successor marker")
	check(GameProgress.end_current_player_action(context) and GameProgress.current_player_id == 1,label + " first member ends normally")
	check(GameProgress.end_current_player_action(context),label + " last member end accepted and pauses")
	record(label + " waiting")
	if not check(GameProgress.current_player_id == 1 and bool(GameProgress.get("_phase_end_pending")) and EffectManager.is_waiting_for_choice(),label + " last actor pending generated"): return
	var waiting:Dictionary = snap()
	check(not GameProgress.end_current_player_action(context) and snap() == waiting,label + " pending choice blocks end without mutation")
	if not answer(ending,label): return
	await get_tree().process_frame
	check(GameProgress.can_end_current_player_action(),label + " query true after answer")
	check(GameProgress.end_current_player_action(context),label + " same public end accepts pending")
	record(label + " resumed")
	if not check(not GameProgress.get_current_phase().is_empty(),label + " phase exists before successor oracle"): return
	check(GameProgress.get_current_phase().name == "outpost" and EffectManager.is_waiting_for_choice(),label + " successor reached")
	var resumed:Dictionary = snap()
	check(not GameProgress.end_current_player_action(context) and snap() == resumed,label + " repeated end cannot bypass successor wait")
	check(count(TimePoints.PREPARE_PHASE_END) == 1,label + " global ending dispatched once")

func missing_nonpending() -> void:
	if not setup("missing_nonpending"): return
	for id in [-1,907066]:
		# 只注入公开行动者 ID，pending 由真实 setup 自然为 false。
		GameProgress.current_player_id = id
		check(not bool(GameProgress.get("_phase_end_pending")),"missing nonpending fixture %d" % id)
		var before:Dictionary = snap()
		var facts:Array = GameLog.query({},null,-1).duplicate(true)
		check(not GameProgress.end_current_player_action(context),"missing nonpending rejected %d" % id)
		check(snap() == before and GameLog.query({},null,-1) == facts,"missing nonpending unchanged no player creation %d" % id)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	print("USER_PATH ",OS.get_user_data_dir())
	await no_actor()
	await ordinary()
	missing_nonpending()
	print("RESULT ",JSON.stringify({"suite":"gp_pending_no_actor","checks":checks,"failures":failures}))
	GameStart.end_session()
	get_tree().quit(0 if failures.is_empty() else 1)
