extends Node

var Rules:Script = preload("res://scripts/system/area_action_rules.gd")
const RR = preload("res://scripts/match/rule_random.gd")
# 新声明仅用于守卫，不修改普通令咒正式数据或原测试 oracle。
const SPEC = {"target_slot":"move_target"}
var checks:int = 0
var failures:Array = []
var source:SessionContext

func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)

func point(location:BaseLocation) -> bool:
	return Rules.call("is_move_target_location", location) if Rules.has_method("is_move_target_location") else false

func pick(area:BaseMapArea, context:Variant = null) -> BaseLocation:
	return Rules.first_effect_location_target(area, SPEC, source if context == null else context)

func start() -> void:
	GameStart.end_session()
	RR.start_seed(81747)
	check(GameStart.game_start([0, 1, 2, 3, 4]), "PRE real GameStart")
	source = GameStart.startup_context()
	check(source != null and SessionGeneration.validate_context(source).ok, "PRE original startup source")
	# 去除开局事件的场景干扰；真实地图、席位/人数容器与原 source identity 均保留。
	for area:BaseMapArea in MapData.areas:
		area._events.clear()
		area._buffs.clear()
	check(SetLocation.new().exec(MapData.miyama2, 0, false, false, true, source), "PRE actual actor origin")

func fill(location:BaseLocation, id:int) -> void:
	check(SetLocation.new().exec(location, id, false, false, true, source), "PRE actual seat occupant " + str(id))

func consistent(area:BaseMapArea, label:String) -> void:
	var first:BaseLocation = null
	for location:BaseLocation in area._locations:
		if location.get_from() == area and point(location) and first == null: first = location
	check(pick(area) == first, "candidate predicate consistency " + label)
	check(pick(area) == GetMoveTargetLocation.new().exec(area, false), "existing move-target query parity " + label)

func workshop() -> void:
	start()
	check(pick(MapData.magic_workshop) == MapData.magic_workshop0, "empty workshop0 candidate")
	check(point(MapData.magic_workshop0), "empty workshop0 point")
	check(point(MapData.magic_workshop1), "arbitrary second workshop point accepted")
	check(not point(MapData.magic_workshop4), "extra unlimited workshop point rejected")
	consistent(MapData.magic_workshop, "empty workshop")
	fill(MapData.magic_workshop0, 1)
	check(not point(MapData.magic_workshop0), "full workshop0 point rejected")
	check(pick(MapData.magic_workshop) == MapData.magic_workshop1, "full0 picks alternate empty workshop")
	check(point(MapData.magic_workshop2) and pick(MapData.magic_workshop) != MapData.magic_workshop2, "nonfirst selected workshop remains legal")
	consistent(MapData.magic_workshop, "partial workshop")
	fill(MapData.magic_workshop1, 2)
	fill(MapData.magic_workshop2, 3)
	fill(MapData.magic_workshop3, 4)
	check(pick(MapData.magic_workshop) == null, "all finite workshop full refuses extra unlimited")
	for location:BaseLocation in MapData.magic_workshop._locations:
		check(not point(location), "full workshop per-point rejection " + str(MapData.magic_workshop._locations.find(location)))
	consistent(MapData.magic_workshop, "full workshop")

func scout_and_battle() -> void:
	start()
	check(pick(MapData.scout) == MapData.scout0 and point(MapData.scout0), "empty scout finite point allowed")
	check(not point(MapData.scout1), "extra unlimited scout point rejected")
	consistent(MapData.scout, "empty scout")
	fill(MapData.scout0, 1)
	check(pick(MapData.scout) == null and not point(MapData.scout0), "full scout rejects all move targets")
	consistent(MapData.scout, "full scout")
	for area:BaseMapArea in [MapData.miyama, MapData.shinto]:
		check(not point(area._locations[0]) and not point(area._locations[1]), "empty benefit seats rejected " + area._area_name)
		check(pick(area) == area._locations[2] and point(area._locations[2]), "empty benefit still picks unlimited melee " + area._area_name)
		fill(area._locations[0], 2)
		fill(area._locations[1], 3)
		check(pick(area) == area._locations[2] and point(area._locations[2]), "full benefit still permits melee " + area._area_name)
		consistent(area, "full battle " + area._area_name)

func declared_properties() -> void:
	start()
	var loc:BaseLocation = MapData.magic_workshop0
	loc._will_move_to = false
	check(not point(loc) and pick(MapData.magic_workshop) == MapData.magic_workshop1, "new enum precedes workshop hardcoded branch")
	loc._will_move_to = true
	loc._pl_num_limit = 0
	check(not point(loc) and pick(MapData.magic_workshop) == MapData.magic_workshop1, "zero finite capacity rejects empty seat")
	loc._pl_num_limit = 2
	fill(loc, 1)
	check(point(loc), "finite capacity greater than actual count permits")
	fill(loc, 2)
	check(not point(loc), "finite capacity equal actual count rejects")
	loc._pl_num_limit = -1
	check(point(loc) and pick(MapData.magic_workshop) == loc, "declared unlimited movable workshop obeys data not area name")
	loc._pl_num_limit = 1
	var extra:BaseLocation = MapData.scout1
	extra._will_move_to = true
	check(point(extra), "declared unlimited movable point accepted independent of name")
	extra._will_move_to = false
	check(not point(extra), "restored extra point declaration refused")
	check(not point(null), "null point refused")

func identities_and_sources() -> void:
	start()
	var foreign_area:BaseMapArea = BaseMapArea.new("foreign map")
	MapData.areas.erase(foreign_area)
	var foreign:BaseLocation = BaseLocation.new(BaseNumber.new(0), BaseNumber.new(0), -1, true)
	foreign.from = foreign_area
	foreign_area._locations.append(foreign)
	check(not point(foreign), "foreign map point rejected despite movable unlimited properties")
	check(pick(foreign_area) == null, "foreign map area query rejected")
	MapData.magic_workshop._locations.push_front(foreign)
	check(not point(foreign) and pick(MapData.magic_workshop) == MapData.magic_workshop0, "foreign owner cannot authorize inserted first point")
	MapData.magic_workshop._locations.pop_front()
	var current:BaseLocation = MapData.magic_workshop0
	MapData.magic_workshop._locations.erase(current)
	check(not point(current), "removed old point identity rejected")
	check(pick(MapData.magic_workshop) == MapData.magic_workshop1, "removed old point excluded from candidate")
	MapData.magic_workshop._locations.push_front(current)
	check(point(current), "exact current point restored")
	check(pick(MapData.magic_workshop, SessionContext.new()) == null, "unissued source candidate refused")
	check(Rules.first_effect_location_target(MapData.magic_workshop, SPEC) == null, "no source candidate fails closed")
	var old:SessionContext = source
	start()
	check(pick(MapData.magic_workshop, old) == null, "old source candidate refused")
	check(pick(MapData.magic_workshop) == MapData.magic_workshop0, "fresh startup original source accepted")

func locks_and_wait_identity() -> void:
	start()
	var effect_array:Array = LoadHelper.load_effects([{"effect_name":"area_locked", "priority":0, "time_points":[], "is_pure_passive":true, "is_residue":false, "effect_numbers":[], "funcs":[]}], null, source)
	check(effect_array.size() == 1, "PRE lock effect trusted loader")
	check(not MapData.event_deck.is_empty(), "PRE real startup runtime event")
	var event:BaseEvent = MapData.event_deck[0]
	event._effects = effect_array
	MapData.scout._events.append(event)
	check(SetLocation.area_locked(MapData.scout), "PRE real destination lock")
	check(pick(MapData.scout) == null, "destination lock candidate refused")
	check(point(MapData.scout0), "point predicate intentionally does not grant destination lock clearance")
	MapData.scout._events.erase(event)
	check(pick(MapData.scout) == MapData.scout0, "unlocked destination candidate restored")
	var roots:Array = LoadHelper.load_effects([{"effect_name":"command-move-target guard", "priority":0, "time_points":[], "is_pure_passive":false, "is_residue":false, "effect_numbers":[], "funcs":[], "options":[{"shown_option_name":"test explicit move target", "select_location":SPEC.duplicate(), "funcs":[]}]}], null, source)
	check(roots.size() == 1 and EffectManager.register_effect(roots[0], 0), "PRE real explicit test declaration")
	var root:BaseEffect = roots[0]
	EffectManager.decision_queue.append(root)
	EffectManager.run_pipeline()
	check(EffectManager.get_pending_active_effect() == root, "PRE genuine option wait")
	check(EffectManager.submit_option_choice(root, [0]), "PRE genuine location choice")
	check(pick(MapData.magic_workshop) == MapData.magic_workshop0, "original pending identity allows new candidate")
	var seats:Array = MapData.magic_workshop0._players
	MapData.magic_workshop0._players = seats.duplicate()
	check(pick(MapData.magic_workshop) == null, "old pending seat container identity rejected")
	MapData.magic_workshop0._players = seats
	check(pick(MapData.magic_workshop) == MapData.magic_workshop0, "original pending container restored")

func purity() -> void:
	start()
	var data:Dictionary = GameDataManager.find_player_data(0)
	var magic:BaseNumber = data.magic
	var balance:float = magic.number
	var loc:BaseLocation = data.location
	var spells:float = data.command_spell_count.number
	var facts:int = GameLog.query({}).size()
	var calls:int = GameLog.all_func_calls().size()
	var keys:Array = GameData.player_data_library.keys()
	var seats:Array = MapData.magic_workshop0._players
	for _i in 3:
		check(point(MapData.magic_workshop0) and pick(MapData.magic_workshop) == MapData.magic_workshop0, "repeated read-only point candidate")
	check(is_same(data, GameDataManager.find_player_data(0)) and is_same(magic, data.magic) and magic.number == balance and data.command_spell_count.number == spells and data.location == loc, "queries preserve original member resources location")
	check(GameLog.query({}).size() == facts and GameLog.all_func_calls().size() == calls and GameData.player_data_library.keys() == keys and is_same(seats, MapData.magic_workshop0._players) and seats.is_empty(), "queries create no facts payments member or seat write")

func legacy() -> void:
	start()
	for mode:String in ["unlimited", "missing", "old_other"]:
		var spec:Dictionary = {} if mode == "missing" else {"target_slot":mode}
		var row:Array = []
		for area:BaseMapArea in MapData.areas:
			var loc:BaseLocation = Rules.first_effect_location_target(area, spec, source)
			row.append(area._locations.find(loc))
		print("LEGACY ", JSON.stringify({"state":"empty","slot":mode,"targets":row}))
		check(row == [0,2,2,0] if mode == "unlimited" else row == [0,0,0,0], "legacy empty expected " + mode)
	for index:int in 4: fill(MapData.magic_workshop._locations[index], index + 1)
	for mode:String in ["unlimited", "missing", "old_other"]:
		var spec:Dictionary = {} if mode == "missing" else {"target_slot":mode}
		check(Rules.first_effect_location_target(MapData.magic_workshop, spec, source) == null, "legacy full workshop expected " + mode)
		print("LEGACY ", JSON.stringify({"state":"workshop-full","slot":mode,"target":-1}))
	fill(MapData.scout0, 1)
	for mode:String in ["unlimited", "missing", "old_other"]:
		var spec:Dictionary = {} if mode == "missing" else {"target_slot":mode}
		check(Rules.first_effect_location_target(MapData.scout, spec, source) == null, "legacy full scout expected " + mode)
		print("LEGACY ", JSON.stringify({"state":"scout-full","slot":mode,"target":-1}))

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var env:Dictionary = {"user":OS.get_user_data_dir(), "global_user":ProjectSettings.globalize_path("user://"), "pid":OS.get_process_id()}
	for key:String in ["APPDATA", "LOCALAPPDATA", "TEMP", "TMP", "TMPDIR"]: env[key] = OS.get_environment(key)
	print("ENV_DETAIL ", JSON.stringify(env))
	check(OS.get_user_data_dir().replace("\\", "/").begins_with("E:/"), "actual user directory physically declared on E")
	var marker:String = "command-move-target-" + str(OS.get_process_id())
	var receipt:FileAccess = FileAccess.open("user://command-move-target-receipt.json", FileAccess.WRITE)
	check(receipt != null, "real user write opens")
	if receipt != null:
		env["marker"] = marker
		receipt.store_string(JSON.stringify(env))
		receipt.close()
		check(JSON.parse_string(FileAccess.get_file_as_string("user://command-move-target-receipt.json")).marker == marker, "real user write readback")
	var mode:String = "all"
	var args:PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty(): mode = args[0]
	if mode == "legacy":
		legacy()
	else:
		workshop()
		scout_and_battle()
		declared_properties()
		identities_and_sources()
		locks_and_wait_identity()
		purity()
	GameStart.end_session()
	print("RESULT ", JSON.stringify({"suite":"command-move-target-contract", "checks":checks, "failures":failures, "mode":mode}))
	get_tree().quit(0 if failures.is_empty() else 1)
