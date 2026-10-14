extends Node
const MOVE = preload("res://scripts/system/operations/Move.gd")
var checks:int = 0
var failures:Array = []
var saved:Callable
var frame_result:Variant
var frame_action:Callable
var frame_calls:int = 0
var frame_marker:bool = false:
	set(value):
		frame_marker = value
		if value:
			frame_calls += 1
			frame_result = frame_action.call()
func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ",label," ",value)
	if not value: failures.append(label)
func start() -> SessionContext:
	var reset:Dictionary = GameData.reset_game_session([0,1])
	check(reset.ok,"PRE reset")
	GameLog.reset()
	for area:BaseMapArea in MapData.areas:
		for loc:BaseLocation in area._locations: loc._players.clear()
	GameData.player_data_library[0].location = MapData.magic_workshop0
	MapData.magic_workshop0._players.append(0)
	MapData.magic_workshop._move_cost.number = 1
	GameData.player_data_library[0].move_cost_discount_from_workshop.number = 0
	return reset.context
func invoke(context:Variant = null, id:int = 0, ignore_limit:bool = false, ignore_battle:bool = false, steps:int = 1) -> Variant:
	var op:RefCounted = MOVE.new()
	var args:Array = [BaseNumber.new(steps),id,ignore_limit,ignore_battle]
	for method in op.get_method_list():
		if method.name == "exec" and method.args.size() > args.size():
			return op.callv("exec",args+[context])
	return op.callv("exec",args)
func effect(context:SessionContext, funcs:Array, points:Array = []) -> BaseEffect:
	var descriptor:Dictionary = {"effect_name":"a1-24-real-listener","priority":0,"time_points":points,"is_pure_passive":true,"is_residue":false,"effect_numbers":[],"funcs":funcs}
	var loaded:Array = LoadHelper.load_effects([descriptor],null,context)
	check(loaded.size() == 1,"PRE runtime factory")
	var root:BaseEffect = loaded[0]
	check(EffectManager.register_effect(root,0),"PRE effect registered")
	return root
func in_frame(context:SessionContext, action:Callable) -> Variant:
	frame_action = action
	frame_result = null
	var root:BaseEffect = effect(context,[{"func_name":"set_property","parameters":[self,"frame_marker",true]}])
	var previous:int = frame_calls
	EffectManager.run_base_func(root._funcs[0],root,context)
	check(frame_calls == previous + 1,"PRE real verified frame")
	return frame_result
func snapshot() -> Dictionary:
	var p:Dictionary = GameDataManager.find_player_data(0)
	var seats:Array = []
	for area:BaseMapArea in MapData.areas:
		for loc:BaseLocation in area._locations: seats.append([loc,loc._players,loc._players.duplicate()])
	return {"library":GameData.player_data_library,"player":p,"location":p.location,"magic":p.magic,"balance":p.magic.number,"seats":seats,"facts":GameLog.query({}).size(),"keys":GameData.player_data_library.keys()}
func unchanged(before:Dictionary, label:String) -> void:
	var p:Dictionary = GameDataManager.find_player_data(0)
	var same:bool = is_same(before.library,GameData.player_data_library) and is_same(before.player,p) and before.location == p.location and is_same(before.magic,p.magic) and before.balance == p.magic.number and before.facts == GameLog.query({}).size() and before.keys == GameData.player_data_library.keys()
	for item:Array in before.seats: same = same and is_same(item[1],item[0]._players) and item[2] == item[0]._players
	check(same,label)
func saved_source() -> void:
	var old:SessionContext = start()
	saved = Callable(self,"invoke").bind(old)
	var current:SessionContext = start()
	# 建好新局合法函数帧后才取观察快照，根自身日志不冒充移动副作用。
	frame_action = func():
		var before:Dictionary = snapshot()
		var result:Variant = saved.call()
		check(result != true,"old saved callable rejected in new legal frame")
		unchanged(before,"old saved callable no new-session movement payment or fact")
		return result
	in_frame(current,frame_action)
	current = start()
	var target:BaseLocation = GetMoveTargetLocation.new().exec(MapData.magic_workshop._linked_map_area)
	check(in_frame(current,Callable(self,"invoke").bind(current)) == true,"new lawful same-ID move payment completes")
	check(GameDataManager.find_player_data(0).location == target and GameDataManager.find_player_data(0).magic.number == 3,"lawful move really places and pays once")
func entry_sources() -> void:
	for kind:String in ["missing","malformed","unissued","progress","game"]:
		var source:Variant = start()
		match kind:
			"missing": source = null
			"malformed": source = {"context":"not a handle"}
			"unissued": source = SessionContext.new()
			"progress": check(GameProgress.reset_progress().ok,"PRE old progress context")
			"game": start()
		var before:Dictionary = snapshot()
		check(invoke(source) != true,"direct invalid source rejected "+kind)
		unchanged(before,"direct invalid source zero side effects "+kind)
		if kind != "missing":
			# 合法 frame context 在新的创建边界取自 lifecycle 返回，不从消费口取当前票。
			var current:SessionContext = start()
			in_frame(current,func():
				var initial:Dictionary = snapshot()
				check(invoke(source) != true,"explicit invalid source not replaced by current frame "+kind)
				unchanged(initial,"explicit invalid source no graph or payment "+kind))
	var context:SessionContext = start()
	var before:Dictionary = snapshot()
	check(invoke(context,999) != true,"unknown ID refused")
	unchanged(before,"unknown ID not created")
var callback_mode:String = ""
var callback_calls:int = 0
var callback_after:Dictionary = {}
var callback_marker:bool = false:
	set(value):
		callback_marker = value
		if not value: return
		callback_calls += 1
		match callback_mode:
			"progress": check(GameProgress.reset_progress().ok,"PRE listener resets progress")
			"game": start()
			"magic": GameData.player_data_library[0].magic = BaseNumber.new(GameData.player_data_library[0].magic.number)
			"member": GameData.player_data_library[0] = GameData.player_data_library[0].duplicate()
			"library": GameData.player_data_library = GameData.player_data_library.duplicate()
			"exhaust": GameData.player_data_library[0].magic.number = 0
		callback_after = snapshot()
func payment_count() -> int:
	var result:int = 0
	for fact:Dictionary in GameLog.query({}):
		if fact.get("data",{}).get("purpose","") == "move" and fact.get("type","") == "magic_decrease": result += 1
	return result
func point_count(point:String) -> int:
	var result:int = 0
	for fact:Dictionary in GameLog.query({"type":"time_point"}):
		if fact.get("data",{}).get("time_points",[]).has(point): result += 1
	return result
func listener_tails() -> void:
	for point:String in [TimePoints.LEAVE_LOCATION,TimePoints.ENTER_LOCATION,TimePoints.MAGIC_DECREASE]:
		for mode:String in ["progress","game","magic","member","library"]:
			var context:SessionContext = start()
			callback_calls = 0
			callback_mode = mode
			effect(context,[{"func_name":"set_property","parameters":[self,"callback_marker",true]}],["self_"+point])
			var result:Variant = in_frame(context,Callable(self,"invoke").bind(context))
			var label:String = point+"/"+mode
			check(callback_calls == 1,"PRE real listener "+label)
			check(result != true,"listener invalidation refuses completion "+label)
			check(GameDataManager.find_player_data(0).magic.number == callback_after.balance,"no resource delta after invalidation "+label)
			check(is_same(GameDataManager.find_player_data(0).magic,callback_after.magic),"no replacement overwritten "+label)
			if point != TimePoints.MAGIC_DECREASE:
				check(payment_count() == 0,"no payment after location invalidation "+label)
			if point == TimePoints.LEAVE_LOCATION and mode != "magic":
				check(point_count(TimePoints.ENTER_LOCATION) == 0,"no old ENTER after LEAVE reset "+label)
func positives() -> void:
	for mode:String in ["frame","direct","free","immune","discount","ignore"]:
		var context:SessionContext = start()
		var p:Dictionary = GameDataManager.find_player_data(0)
		var target:BaseLocation = GetMoveTargetLocation.new().exec(MapData.magic_workshop._linked_map_area)
		match mode:
			"free": MapData.magic_workshop._move_cost.number = 0
			"immune": p.is_magic_immune = true
			"discount": p.move_cost_discount_per_step.number = 1
		var result:Variant = invoke(context) if mode == "direct" else in_frame(context,Callable(self,"invoke").bind(null,0,mode=="ignore",mode=="ignore"))
		check(result == true if mode in ["frame","direct","ignore"] else result == null,"preserved payment return "+mode)
		check(p.location == target and target._players.has(0) and not MapData.magic_workshop0._players.has(0),"legal actual placement "+mode)
		check(p.magic.number == (3 if mode in ["frame","direct","ignore"] else 4),"declared fee exception "+mode)
		check(point_count(TimePoints.LEAVE_LOCATION) == 1 and point_count(TimePoints.ENTER_LOCATION) == 1,"legal paired location endpoints "+mode)
		check(payment_count() == (1 if mode in ["frame","direct","ignore"] else 0),"payment exactly once "+mode)
	var context:SessionContext = start()
	var before:Dictionary = snapshot()
	check(invoke(context,0,false,false,0) != true,"zero steps rejected")
	unchanged(before,"zero steps no side effect")
	context = start()
	GameDataManager.find_player_data(0).magic.number = 0
	before = snapshot()
	check(invoke(context) != true,"insufficient magic refused before placement")
	unchanged(before,"insufficient magic no side effect")
func guard_resume() -> void:
	var context:SessionContext = start()
	var root:BaseEffect = effect(context,[{"func_name":"move","parameters":[BaseNumber.new(1),0]},{"func_name":"do_nothing","parameters":[]}])
	check(EffectManager.configure_runtime_guard({"enabled":true,"steps":1,"seconds":0.0}),"PRE guard enabled")
	EffectManager.activate_effect(root)
	check(EffectManager.runtime_guard_status().paused,"PRE actual guard paused")
	var resumes:int = 0
	while EffectManager.runtime_guard_status().paused and resumes < 20:
		check(EffectManager.resume_runtime_guard(),"same source resumed")
		resumes += 1
	check(not EffectManager.runtime_guard_status().paused,"same source guard finished")
	check(payment_count() == 1 and point_count(TimePoints.LEAVE_LOCATION) == 1 and point_count(TimePoints.ENTER_LOCATION) == 1,"same source guard no duplicate move or payment")
	check(GameDataManager.find_player_data(0).magic.number == 3,"same source guard final balance")
	check(EffectManager.configure_runtime_guard({"enabled":false,"steps":0,"seconds":0.0}),"PRE guard disabled")
func atomic_boundary() -> void:
	var context:SessionContext = start()
	callback_mode = "progress"
	callback_calls = 0
	effect(context,[{"func_name":"set_property","parameters":[self,"callback_marker",true]}],["self_"+TimePoints.LEAVE_LOCATION])
	var before:Dictionary = snapshot()
	check(in_frame(context,Callable(self,"invoke").bind(context)) != true,"old LEAVE chain does not complete")
	check(callback_calls == 1,"PRE atomic real reset")
	check(GameDataManager.find_player_data(0).location == before.location,"A4 rejected Move retains original position")
	check(MapData.magic_workshop0._players.has(0),"A4 rejected Move retains original seat")
	print("ATOMIC_DETAIL ",JSON.stringify({"at_origin":GameDataManager.find_player_data(0).location == before.location,"balance":GameDataManager.find_player_data(0).magic.number,"leave":point_count(TimePoints.LEAVE_LOCATION),"enter":point_count(TimePoints.ENTER_LOCATION)}))
	# 原 ENTER 断言保留为跨位置消费者的强原子门，不用来源专项绿覆盖。
	context = start()
	callback_mode = "magic"
	callback_calls = 0
	effect(context,[{"func_name":"set_property","parameters":[self,"callback_marker",true]}],["self_"+TimePoints.LEAVE_LOCATION])
	check(in_frame(context,Callable(self,"invoke").bind(context)) != true,"magic replacement refuses payment")
	check(callback_calls == 1,"PRE atomic magic replacement")
	check(point_count(TimePoints.ENTER_LOCATION) == 0,"no old ENTER after LEAVE reset leave_location/magic")
	context = start()
	before = snapshot()
	check(invoke() != true,"unframed paid Move without source refused")
	check(GameDataManager.find_player_data(0).location == before.location,"unframed source refusal has no half placement")
func _ready() -> void:
	var env:Dictionary = {"user":OS.get_user_data_dir()}
	for key in ["TMPDIR","TEMP","TMP","APPDATA","LOCALAPPDATA"]: env[key] = OS.get_environment(key)
	print("ENV_DETAIL ",JSON.stringify(env))
	if OS.get_cmdline_user_args().has("atomic"):
		atomic_boundary()
	elif OS.get_cmdline_user_args().has("entry"):
		entry_sources()
	else:
		saved_source()
		entry_sources()
		listener_tails()
		positives()
		guard_resume()
	print("RESULT ",JSON.stringify({"checks":checks,"failures":failures,"suite":"a1_24_move_origin"}))
	get_tree().quit(0 if failures.is_empty() else 1)
