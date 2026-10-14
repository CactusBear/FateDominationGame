extends Node
var checks:int = 0
var failures:Array = []
const SET = preload("res://scripts/system/operations/SetLocation.gd")
const MOVE = preload("res://scripts/system/operations/MoveLocation.gd")
func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ",label," ",value)
	if not value: failures.append(label)
func invoke(script:Script, args:Array, context:Variant = null) -> Variant:
	# 原实现保原 ABI；不以参数数目错误冒业务红。
	var op:RefCounted = script.new()
	for method in op.get_method_list():
		if method.name == "exec" and method.args.size() > args.size():
			return op.callv("exec",args + [context])
	return op.callv("exec",args)
func start(ids:Array = [0,1]) -> SessionContext:
	var result:Dictionary = GameData.reset_game_session(ids)
	check(result.ok,"PRE reset")
	GameLog.reset()
	for area:BaseMapArea in MapData.areas:
		for loc:BaseLocation in area._locations: loc._players.clear()
	GameData.player_data_library[0].location = MapData.magic_workshop0
	MapData.magic_workshop0._players.append(0)
	return result.context
func snapshot() -> Dictionary:
	return {"player":GameData.player_data_library[0],"location":GameData.player_data_library[0].location,"old":MapData.magic_workshop0._players.duplicate(),"target":MapData.miyama0._players.duplicate(),"facts":GameLog.query({}).size(),"bindings":SessionGeneration._bindings.size(),"contexts":SessionGeneration._contexts.size(),"keys":GameData.player_data_library.keys()}
func unchanged(s:Dictionary,label:String) -> void:
	check(is_same(s.player,GameData.player_data_library[0]) and s.location == GameData.player_data_library[0].location and s.old == MapData.magic_workshop0._players and s.target == MapData.miyama0._players and s.facts == GameLog.query({}).size() and s.bindings == SessionGeneration._bindings.size() and s.contexts == SessionGeneration._contexts.size() and s.keys == GameData.player_data_library.keys(),label)
func entry_sources() -> void:
	for source_kind in ["missing","malformed","unissued","progress","game"]:
		var source:Variant = start()
		match source_kind:
			"missing": source = null
			"malformed": source = {"token":SessionGeneration.current_token().token}
			"unissued": source = SessionContext.new()
			"progress": GameProgress.reset_progress()
			"game": start()
		var s:Dictionary = snapshot()
		check(not invoke(SET,[MapData.miyama0,0,false,false,true],source),"set refuses "+source_kind)
		unchanged(s,"set refusal no half placement "+source_kind)
		source = start()
		match source_kind:
			"missing": source = null
			"malformed": source = {}
			"unissued": source = SessionContext.new()
			"progress": GameProgress.reset_progress()
			"game": start()
		s = snapshot()
		check(invoke(MOVE,[BaseNumber.new(1),0,false],source) == null,"move refuses "+source_kind)
		unchanged(s,"move refusal no half placement "+source_kind)
var callback_calls:int = 0
var callback_mode:String = ""
var callback_marker:bool = false:
	set(value):
		callback_marker = value
		if not value: return
		callback_calls += 1
		match callback_mode:
			"progress": check(GameProgress.reset_progress().ok,"PRE synchronous progress reset")
			"member": GameData.player_data_library[0] = GameData.player_data_library[0].duplicate()
			"library": GameData.player_data_library = GameData.player_data_library.duplicate()
			"map": MapData.areas = MapData.areas.duplicate()
			"locations": MapData.miyama._locations = MapData.miyama._locations.duplicate()
			"seats": MapData.miyama0._players = MapData.miyama0._players.duplicate()
func effect(context:SessionContext, funcs:Array, points:Array = []) -> BaseEffect:
	var desc:Dictionary = {"effect_name":"a1-23-listener","priority":0,"time_points":points,"is_pure_passive":true,"is_residue":false,"effect_numbers":[],"funcs":funcs}
	var loaded:Array = LoadHelper.load_effects([desc],null,context)
	check(loaded.size() == 1,"PRE runtime factory")
	var root:BaseEffect = loaded[0]
	check(EffectManager.register_effect(root,0),"PRE listener registered")
	return root
func count_point(point:String) -> int:
	var result:int = 0
	for fact:Dictionary in GameLog.query({"type":"time_point"}):
		if fact.get("data",{}).get("time_points",[]).has(point): result += 1
	return result
func callbacks() -> void:
	for point in [TimePoints.LEAVE_LOCATION,TimePoints.ENTER_LOCATION]:
		for mode in ["progress","member","library","map","locations","seats"]:
			for move:bool in [false,true]:
				var source:SessionContext = start()
				callback_calls = 0
				callback_mode = mode
				effect(source,[{"func_name":"set_property","parameters":[self,"callback_marker",true]}],["self_"+point])
				var old_data:Dictionary = GameData.player_data_library[0]
				var magic = old_data.magic.number
				var result:Variant = invoke(MOVE,[BaseNumber.new(1),0,false],source) if move else invoke(SET,[MapData.miyama0,0,false,false,true],source)
				var label:String = ("move/" if move else "set/")+point+"/"+mode
				check(callback_calls == 1,"PRE real callback "+label)
				check(result == null if move else result == false,"callback refuses completion "+label)
				check(GameData.player_data_library[0].magic.number == magic,"callback no payment "+label)
				if point == TimePoints.LEAVE_LOCATION:
					check(count_point(TimePoints.ENTER_LOCATION) == 0,"old ENTER not dispatched "+label)
				if mode == "progress":
					check(is_same(old_data,GameData.player_data_library[0]),"PRE progress retains member dictionary")
func positive() -> void:
	var source:SessionContext = start()
	var magic = GameData.player_data_library[0].magic.number
	check(invoke(SET,[MapData.miyama0,0,false,false,true],source),"legal explicit set completes")
	check(GameData.player_data_library[0].location == MapData.miyama0 and MapData.miyama0._players.has(0) and not MapData.magic_workshop0._players.has(0),"legal set actual position and seats")
	check(count_point(TimePoints.LEAVE_LOCATION) == 1 and count_point(TimePoints.ENTER_LOCATION) == 1,"legal set paired facts")
	check(GameData.player_data_library[0].magic.number == magic,"set no extra fee")
	source = start()
	MapData.magic_workshop._move_cost.number = 0
	var free_target:BaseLocation = GetMoveTargetLocation.new().exec(MapData.magic_workshop._linked_map_area)
	var cost:Variant = invoke(MOVE,[BaseNumber.new(1),0,false],source)
	check(cost is BaseNumber and cost.number == 0,"legal free move returns zero cost")
	check(GameData.player_data_library[0].location == free_target,"free move really places not quotation")
	check(GameData.player_data_library[0].magic.number == magic,"free move no fee")
	check(count_point(TimePoints.LEAVE_LOCATION) == 1 and count_point(TimePoints.ENTER_LOCATION) == 1,"free move paired facts")
	source = start()
	var extra:BaseLocation = BaseLocation.new(BaseNumber.new(0),BaseNumber.new(0),-1,false,false)
	extra.from = MapData.miyama
	MapData.miyama._locations.append(extra)
	check(invoke(SET,[extra,0,false,true,true],source),"declared extra seat preserved")
	check(GameData.player_data_library[0].location == extra and extra._players.has(0),"declared extra seat real placement")
	MapData.miyama._locations.erase(extra)
	source = start()
	callback_mode = "legal"
	callback_calls = 0
	effect(source,[{"func_name":"set_property","parameters":[self,"callback_marker",true]}],["self_"+TimePoints.LEAVE_LOCATION])
	check(invoke(SET,[MapData.miyama0,0,false,false,true],source),"same session callback legal")
	check(callback_calls == 1,"PRE legal callback reached")
var frame_result:Variant = null
var frame_marker:bool = false:
	set(value):
		frame_marker = value
		if value: frame_result = invoke(SET,[MapData.miyama0,0,false,false,true])
func frame_and_resume() -> void:
	var source:SessionContext = start()
	var root:BaseEffect = effect(source,[{"func_name":"set_property","parameters":[self,"frame_marker",true]}])
	var result:Array = EffectManager.run_base_func(root._funcs[0],root,source)
	check(result[0] and frame_result == true,"legal inherited verified function frame")
	check(GameData.player_data_library[0].location == MapData.miyama0,"inherited frame real placement")
	check(count_point(TimePoints.LEAVE_LOCATION) == 1 and count_point(TimePoints.ENTER_LOCATION) == 1,"inherited frame paired facts")
	source = start()
	root = effect(source,[{"func_name":"set_location","parameters":[MapData.miyama0,0,false,false,true]},{"func_name":"do_nothing","parameters":[]}])
	check(EffectManager.configure_runtime_guard({"enabled":true,"steps":1,"seconds":0.0}),"PRE guard enabled")
	EffectManager.activate_effect(root)
	check(EffectManager.runtime_guard_status().paused,"PRE real same session guard pause")
	var resumes:int = 0
	while EffectManager.runtime_guard_status().paused and resumes < 12:
		check(EffectManager.resume_runtime_guard(),"same session original guard resume accepted")
		resumes += 1
	check(not EffectManager.runtime_guard_status().paused and GameData.player_data_library[0].location == MapData.miyama0,"same session resume completes real placement")
	check(count_point(TimePoints.LEAVE_LOCATION) == 1 and count_point(TimePoints.ENTER_LOCATION) == 1,"same session resume facts exactly once")
	check(EffectManager.configure_runtime_guard({"enabled":false,"steps":0,"seconds":0.0}),"PRE guard disabled")
func independent_queries_and_saved() -> void:
	var source:SessionContext = start()
	var saved:Callable = Callable(self,"invoke").bind(SET,[MapData.miyama0,0,false,false,true],source)
	GameProgress.reset_progress()
	var s:Dictionary = snapshot()
	check(saved.call() == false,"saved old callable never refreshed")
	unchanged(s,"saved old callable no mutation")
	check(SET.current_map_location(MapData.miyama0),"current_map_location independent pure map query")
	check(not SET.area_locked(MapData.miyama),"area_locked independent shared predicate")
	check(SET.locked_area_for_move(0,MapData.miyama) == null,"locked_area_for_move independent shared predicate")
	unchanged(s,"three shared queries zero registration or facts")
	source = start()
	var foreign:BaseLocation = BaseLocation.new()
	s = snapshot()
	check(invoke(SET,[foreign,0,false,false,true],source) == false,"foreign location refused")
	unchanged(s,"foreign location no half placement")
	check(invoke(SET,[MapData.miyama0,999,false,false,true],source) == false,"unknown member refused")
	unchanged(s,"unknown member not created")
	source = start([0,-7])
	GameData.player_data_library[-7].location = MapData.magic_workshop0
	MapData.magic_workshop0._players.append(-7)
	check(invoke(SET,[MapData.miyama0,-7,false,false,true],source),"legal negative member preserved")
	check(GameData.player_data_library[-7].location == MapData.miyama0,"negative member actual placement")
func atomic_boundary() -> void:
	var source:SessionContext = start()
	callback_calls = 0
	callback_mode = "progress"
	effect(source,[{"func_name":"set_property","parameters":[self,"callback_marker",true]}],["self_"+TimePoints.LEAVE_LOCATION])
	var before:Dictionary = snapshot()
	check(invoke(SET,[MapData.miyama0,0,false,false,true],source) == false,"atomic source rejection observed")
	check(callback_calls == 1,"PRE atomic real LEAVE reset")
	unchanged(before,"A4 full no half placement including seats and facts")
	print("ATOMIC_DETAIL ",JSON.stringify({"at_origin":GameData.player_data_library[0].location == MapData.magic_workshop0,"at_target":GameData.player_data_library[0].location == MapData.miyama0,"origin_seats":MapData.magic_workshop0._players,"target_seats":MapData.miyama0._players,"leave":count_point(TimePoints.LEAVE_LOCATION),"enter":count_point(TimePoints.ENTER_LOCATION)}))
func _ready() -> void:
	var env:Dictionary = {"user":OS.get_user_data_dir(),"global_user":ProjectSettings.globalize_path("user://")}
	for key in ["TMPDIR","TEMP","TMP","APPDATA","LOCALAPPDATA"]: env[key] = OS.get_environment(key)
	print("ENV_DETAIL ",JSON.stringify(env))
	if OS.get_cmdline_user_args().has("atomic"):
		atomic_boundary()
	else:
		entry_sources()
		if not OS.get_cmdline_user_args().has("entry"):
			callbacks()
			positive()
			frame_and_resume()
			independent_queries_and_saved()
	print("RESULT ",JSON.stringify({"checks":checks,"failures":failures,"suite":"a1_23_location_origin"}))
	get_tree().quit(0 if failures.is_empty() else 1)
