extends Node
const Rules = preload("res://scripts/system/area_action_rules.gd")
var rules:Script = preload("res://scripts/system/area_action_rules.gd")
var checks:int = 0
var failures:Array = []
var frame_probe:bool = false:
	set(value):
		frame_probe = value
		if value:
			check(rules.move_lock_reason(0, MapData.miyama) == "", "legal inherited real function frame")
			check(rules.first_effect_location_target(MapData.miyama) != null, "legal inherited frame target")
func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)
func query(method:String, args:Array, context:Variant = null) -> Variant:
	# Baseline retains its original ABI; no arity/parse errors count as business RED.
	for item in rules.get_script_method_list():
		if item.name == method and item.args.size() > args.size():
			return rules.callv(method, args + [context])
	return rules.callv(method, args)
func pending(context:Variant = null) -> Dictionary:
	if rules.has_method("get_pending_location_selection"):
		return rules.call("get_pending_location_selection", context)
	return EffectManager.get_pending_location_selection()
func start(ids:Array = [0, 1]) -> SessionContext:
	var result:Dictionary = GameData.reset_game_session(ids)
	check(result.ok, "PRE reset")
	GameLog.reset()
	for id in ids: GameData.player_data_library[id].location = MapData.magic_workshop0
	return result.context
func effect(context:SessionContext, options:Array = [], funcs:Array = [], id:int = 0) -> BaseEffect:
	var desc:Dictionary = {"effect_name":"a1-22","priority":0,"time_points":[],"is_pure_passive":false,"is_residue":false,"effect_numbers":[],"funcs":funcs}
	if not options.is_empty(): desc.options = options
	var loaded:Array = LoadHelper.load_effects([desc], null, context)
	check(loaded.size() == 1, "PRE factory")
	var result:BaseEffect = loaded[0]
	check(EffectManager.register_effect(result, id), "PRE register")
	return result
func wait(context:SessionContext, id:int = 0) -> BaseEffect:
	var root:BaseEffect = effect(context, [{"shown_option_name":"choose","select_location":{"allowed_origin_areas":[MapData.magic_workshop._area_name]},"funcs":[]}], [], id)
	EffectManager.decision_queue.append(root)
	EffectManager.run_pipeline()
	check(EffectManager.get_pending_active_effect() == root, "PRE real wait")
	check(EffectManager.submit_option_choice(root, [0]), "PRE select option")
	return root
func snapshot() -> Dictionary:
	return {"keys":GameData.player_data_library.keys(),"library":GameData.player_data_library,"members":GameData.player_data_library.duplicate(),"map":MapData.areas,"areas":MapData.areas.duplicate(),"locations":MapData.miyama._locations,"seats":MapData.miyama0._players,"bindings":SessionGeneration._bindings.size(),"contexts":SessionGeneration._contexts.size(),"objects":GameData.objects.size(),"facts":GameLog.query({}).size(),"funcs":GameLog.all_func_calls().size()}
func unchanged(s:Dictionary, label:String) -> void:
	var same:bool = s.keys == GameData.player_data_library.keys() and is_same(s.library, GameData.player_data_library) and is_same(s.map, MapData.areas) and is_same(s.locations, MapData.miyama._locations) and is_same(s.seats, MapData.miyama0._players)
	for id in s.members: same = same and is_same(s.members[id], GameData.player_data_library[id])
	for i in range(s.areas.size()): same = same and is_same(s.areas[i], MapData.areas[i])
	check(same and s.bindings == SessionGeneration._bindings.size() and s.contexts == SessionGeneration._contexts.size() and s.objects == GameData.objects.size() and s.facts == GameLog.query({}).size() and s.funcs == GameLog.all_func_calls().size(), label)
func no_source_and_old() -> void:
	var context:SessionContext = start()
	var s:Dictionary = snapshot()
	check(query("move_lock_reason", [0,MapData.miyama]) != "", "no frame lock fails closed")
	check(query("first_effect_location_target", [MapData.miyama,{}]) == null, "no frame target fails closed")
	check(query("move_lock_reason", [0,MapData.miyama], {"token":SessionGeneration.current_token().token}) != "", "malformed source lock refused")
	check(query("first_effect_location_target", [MapData.miyama,{}], SessionContext.new()) == null, "unissued source target refused")
	unchanged(s, "source refusal pure")
	context = start()
	var root:BaseEffect = wait(context)
	var index:int = MapData.areas.find(MapData.miyama)
	check(query("block_reason", [0,index], context) == "", "legal pending declared origin")
	check(query("block_reason", [1,index], context) != "", "observer cannot borrow real trigger")
	check(not pending().is_empty(), "legal original wait getter no registration")
	check(query("block_reason", [0,index]) != "", "no frame block does not borrow waiting ticket")
	check(pending({}).is_empty(), "explicit malformed wait source refused")
	check(query("first_effect_location_target", [MapData.miyama,root._options[0].select_location], context) != null, "legal pending target")
	s = snapshot()
	for i in range(3):
		check(not pending(context).is_empty(), "repeated legal wait getter")
		check(query("block_reason",[0,index],context) == "", "repeated legal pending block")
	unchanged(s, "pending queries zero keys bindings contexts map facts")
	var retained:Callable = Callable(self,"query").bind("move_lock_reason",[0,MapData.miyama],context)
	GameProgress.reset_progress()
	check(not SessionGeneration.validate_context(context).ok, "PRE reset progress invalidates")
	s = snapshot()
	check(retained.call() != "", "saved old lock source refused")
	check(query("first_effect_location_target", [MapData.miyama,{}], context) == null, "old source target refused")
	check(query("block_reason", [0,index], context) != "", "old block source refused")
	check(pending(context).is_empty(), "old wait context refused")
	unchanged(s, "old progress queries pure")
	var fresh:SessionContext = start()
	check(query("move_lock_reason", [0,MapData.miyama], context) != "", "old same ID new dictionary lock refused")
	check(query("first_effect_location_target", [MapData.miyama,{}], context) == null, "old same ID target refused")
	check(query("move_lock_reason", [0,MapData.miyama], fresh) == "", "fresh same ID source legitimate")
func subjects_and_waits() -> void:
	var context:SessionContext = start([-7,0,1])
	var index:int = MapData.areas.find(MapData.miyama)
	for id in [999,-2,-1]:
		var s:Dictionary = snapshot()
		check(query("move_lock_reason", [id,MapData.miyama], context) != "", "independent invalid lock " + str(id))
		check(query("block_reason", [id,index], context) != "", "unknown observer " + str(id))
		unchanged(s, "invalid ID no creation " + str(id))
	check(query("move_lock_reason", [-7,MapData.miyama], context) == "", "literal negative lock member preserved")
	for id in [999,-2,-1]:
		context = start()
		var root:BaseEffect = wait(context)
		root._trigger_player_id = id
		var s:Dictionary = snapshot()
		check(pending().is_empty(), "invalid actual trigger wait " + str(id))
		check(query("block_reason", [0,index],context) != "", "known observer invalid actual trigger " + str(id))
		unchanged(s, "trigger no GetLocation creation " + str(id))
	context = start([-7,1])
	wait(context,-7)
	check(not pending().is_empty(), "literal negative actual trigger preserved")
	check(query("block_reason",[-7,index],context) == "", "literal negative pending block legitimate")
	context = start([-1,0])
	check(query("move_lock_reason",[-1,MapData.miyama],context) == "", "lock minus one literal member not local fallback")
	var sentinel:BaseEffect = wait(context,0)
	sentinel._trigger_player_id = -1
	var state:Dictionary = snapshot()
	check(pending().is_empty(), "real trigger minus one refused even present member")
	check(query("block_reason",[-1,index],context) != "", "trigger sentinel never borrows literal observer")
	unchanged(state,"sentinel no lookup creation or bindings")
func topology_and_replacement() -> void:
	var context:SessionContext = start()
	var root:BaseEffect = wait(context)
	var old_data:Dictionary = GameData.player_data_library[0]
	GameData.player_data_library[0] = old_data.duplicate()
	var s:Dictionary = snapshot()
	check(pending().is_empty(), "same ID new dictionary old wait rejected")
	check(query("move_lock_reason",[0,MapData.miyama],context) != "", "replacement independent lock closes old wait")
	check(query("first_effect_location_target",[MapData.miyama,root._options[0].select_location],context) == null, "replacement independent target closes old wait")
	check(query("block_reason",[0,MapData.areas.find(MapData.miyama)],context) != "", "invalid wait cannot fall into normal action")
	unchanged(s,"replacement query pure")
	GameData.player_data_library[0] = old_data
	var locations:Array = MapData.miyama._locations
	MapData.miyama._locations = locations.duplicate()
	check(pending().is_empty(), "undeclared equal location container refused")
	check(query("first_effect_location_target",[MapData.miyama,{}],context) == null, "undeclared equal locations independent target refused")
	check(query("move_lock_reason",[0,MapData.miyama],context) != "", "undeclared equal locations independent lock refused")
	MapData.miyama._locations = locations
	var seats:Array = MapData.miyama0._players
	MapData.miyama0._players = seats.duplicate()
	check(pending().is_empty(), "undeclared equal seat container refused")
	MapData.miyama0._players = seats
	var areas:Array = MapData.areas
	MapData.areas = areas.duplicate()
	check(pending().is_empty(), "undeclared map container refused")
	MapData.areas = areas
	check(not pending().is_empty(), "original identities restored legitimate wait")
	check(root == EffectManager.waiting_location,"query does not cancel or replace waiting")
	context = start()
	locations = MapData.miyama._locations
	var old_area:BaseMapArea = BaseMapArea.new("foreign")
	MapData.areas.erase(old_area)
	old_area._locations.append(MapData.miyama0)
	check(query("first_effect_location_target",[old_area,{}],context) == null,"foreign area never authorizes target")
	check(query("move_lock_reason",[0,old_area],context) != "","foreign area no null lock authorization")
	var foreign:BaseLocation = BaseLocation.new()
	foreign.set_from(old_area)
	locations.push_front(foreign)
	check(query("first_effect_location_target",[MapData.miyama,{}],context) != foreign,"foreign location in current area excluded")
	locations.pop_front()
func positive() -> void:
	var context:SessionContext = start()
	GameProgress.current_player_id = 0
	for i in range(GameProgress.phases.size()):
		if GameProgress.phases[i].name == "action": GameProgress.current_phase_index = i
	check(query("block_reason",[0,MapData.areas.find(MapData.miyama)],context) == "", "legal normal movement query String preserved")
	var s:Dictionary = snapshot()
	for i in range(3):
		check(query("move_lock_reason",[0,MapData.miyama],context) == "","ordinary no lock String preserved")
		check(query("first_effect_location_target",[MapData.miyama,{}],context) != null,"current map available target")
	unchanged(s,"repeated explicit queries zero keys bindings facts")
	var root:BaseEffect = effect(context,[],[{"func_name":"set_property","parameters":[self,"frame_probe",true]}])
	EffectManager.activate_effect(root)
	check(frame_probe,"legal real EM rule path executes")
	check(frame_probe,"PRE frame callback reached")
func _ready() -> void:
	print("ENV ",OS.get_user_data_dir())
	var env:Dictionary = {"user":OS.get_user_data_dir(),"global_user":ProjectSettings.globalize_path("user://")}
	for key in ["TMPDIR","TEMP","TMP","APPDATA","LOCALAPPDATA"]: env[key] = OS.get_environment(key)
	print("ENV_DETAIL ",JSON.stringify(env))
	no_source_and_old()
	subjects_and_waits()
	topology_and_replacement()
	positive()
	print("RESULT ",JSON.stringify({"checks":checks,"failures":failures,"suite":"a1_22_area_origin"}))
	get_tree().quit(0 if failures.is_empty() else 1)
