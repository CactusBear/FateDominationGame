extends Node

const RR = preload("res://scripts/match/rule_random.gd")
var checks:int = 0
var failures:Array = []
var mode:String = "placement"

func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)

func _ready() -> void:
	call_deferred("run")

func start() -> SessionContext:
	GameStart.end_session()
	GameData.loaded_masters = []
	GameData.loaded_servants = []
	RR.start_seed(81747)
	check(GameStart.game_start([0, 1]), "PRE real GameStart")
	var source:SessionContext = GameStart.startup_context()
	check(source != null and SessionGeneration.validate_context(source).ok, "PRE original startup receipt")
	return source

# 同一守卫可在旧 ABI 的冻结运行，避免把参数数量异常当作业务 RED。
func explicit_deploy(location:BaseLocation, id:int, ignore_limit:bool, source:SessionContext) -> Variant:
	var op:Deploy = Deploy.new()
	for info in op.get_method_list():
		if info.name == &"exec" and info.args.size() == 4:
			return op.callv("exec", [location, id, ignore_limit, source])
	return op.exec(location, id, ignore_limit)

func explicit_area(area:BaseMapArea, id:int, source:SessionContext) -> Variant:
	for info in DeployRules.new().get_method_list():
		if info.name == &"deploy_to_area" and info.args.size() == 3:
			return DeployRules.new().callv("deploy_to_area", [area, id, source])
	return DeployRules.deploy_to_area(area, id)

func facts(id:int) -> int:
	return GameLog.query({"type":"deploy", "actor":id}, null).size()

func unchanged(data:Dictionary, magic:BaseNumber, balance:float, location:Variant, count:int, members:int) -> bool:
	return is_same(data, GameDataManager.find_player_data(0)) and is_same(magic, data.magic) \
		and magic.number == balance and data.location == location and facts(0) == count \
		and GameData.player_data_library.size() == members

func placement() -> void:
	var source:SessionContext = start()
	var commands:MatchCommands = MatchCommands.new()
	var data:Dictionary = GameDataManager.find_player_data(0)
	var magic:BaseNumber = data.magic
	var balance:float = magic.number
	var loc:BaseLocation = DeployRules.pick_location(MapData.miyama)
	var seats:Array = loc._players
	var members:int = GameData.player_data_library.size()
	var before:int = facts(0)
	check(not EffectManager.execution_context().ok and loc._magic.number == 0, "PRE no frame zero-gain seat")
	check(commands.deploy(loc, 0, source) == true, "formal MatchCommands original source lands")
	check(is_same(data.location, loc) and is_same(seats, loc._players) and seats == [0], "exact location and seat array identity")
	check(is_same(data, GameDataManager.find_player_data(0)) and is_same(magic, data.magic) and magic.number == balance, "formal placement preserves member magic identity")
	check(facts(0) == before + 1, "formal placement records exactly one deploy")
	var count:int = facts(0)
	check(commands.deploy(MapData.miyama1, 0) == false, "missing formal source rejects")
	check(Deploy.new().exec(MapData.miyama1, 0) == false, "old direct ABI without frame refuses")
	check(unchanged(data, magic, balance, loc, count, members) and MapData.miyama1._players.is_empty(), "missing source zero writes")
	check(explicit_deploy(MapData.miyama1, 9091, false, source) == false and not GameData.player_data_library.has(9091), "unknown member refuses without library creation")
	var occupied:Array = loc._players.duplicate()
	check(commands.deploy(loc, 1, source) == false and loc._players == occupied and facts(1) == 0, "full seat zero second fact")
	check(unchanged(data, magic, balance, loc, count, members), "full seat preserves original member state")
	check(commands.deploy_to_area(MapData.scout, 1, source) == false and GameDataManager.find_player_data(1).location == null, "declared no-deploy area rejects")
	# 实际加载器+真实函数执行器产生已验帧，保留旧 descriptor 两业务参数。
	source = start()
	var target:BaseLocation = MapData.miyama0
	var loaded:Array = LoadHelper.load_effects([{"effect_name":"deploy-origin-handoff", "time_points":[], "priority":0,
		"is_pure_passive":true, "is_residue":false, "need_activate":false, "effect_numbers":[],
		"funcs":[{"func_name":"deploy", "parameters":[target, 0], "var_index":-1}]}], null, source)
	check(loaded.size() == 1, "PRE trusted descriptor loader")
	var effect:BaseEffect = loaded[0]
	check(EffectManager.register_effect(effect, 0), "PRE descriptor runtime registration")
	var result:Array = EffectManager.run_base_func(effect._funcs[0], effect, effect.runtime_context())
	check(result == [true, true] and GameDataManager.find_player_data(0).location == target and facts(0) == 1, "validated descriptor old ABI compatible")
	check(not EffectManager.execution_context().ok, "descriptor frame does not leak")
	source = start()
	check(explicit_area(MapData.miyama, 0, source) == MapData.miyama0 and facts(0) == 1, "DeployRules original source orchestration lands")
	var expired:SessionContext = source
	source = start()
	data = GameDataManager.find_player_data(0); magic = data.magic; balance = magic.number
	check(commands.deploy(MapData.miyama0, 0, expired) == false, "expired original source refuses")
	check(unchanged(data, magic, balance, null, 0, GameData.player_data_library.size()) and MapData.miyama0._players.is_empty(), "expired source zero writes")
	check(explicit_deploy(MapData.miyama0, 0, false, source) == true, "independent Deploy explicit source succeeds")
	check(explicit_deploy(MapData.miyama0, 1, true, source) == true and MapData.miyama0._players == [0, 1], "caller-declared ignore_limit preserves existing exception")
	check(facts(0) == 1 and facts(1) == 1, "independent deployments each have one real fact")

func benefit() -> void:
	var source:SessionContext = start()
	var data:Dictionary = GameDataManager.find_player_data(0)
	var loc:BaseLocation = DeployRules.pick_location(MapData.magic_workshop)
	var before:float = data.magic.number
	check(loc._magic.number > 0, "PRE real printed gain")
	check(MatchCommands.new().deploy(loc, 0, source) == true, "formal charged-seat placement succeeds")
	check(data.location == loc and facts(0) == 1, "charged-seat placement has real single fact")
	check(data.magic.number == before + loc._magic.number, "formal printed benefit actually received")
	print("BENEFIT_OBSERVATION ", JSON.stringify({"before":before,"after":data.magic.number,"printed":loc._magic.number,"frame":EffectManager.execution_context().ok}))

func run() -> void:
	var argv:PackedStringArray = OS.get_cmdline_user_args()
	if not argv.is_empty(): mode = argv[0]
	print("USER_DIR ", OS.get_user_data_dir())
	var token:String = "deploy-origin-handoff-" + mode
	var file:FileAccess = FileAccess.open("user://deploy-origin-handoff.txt", FileAccess.WRITE)
	file.store_string(token); file.close()
	check(FileAccess.get_file_as_string("user://deploy-origin-handoff.txt") == token, "actual user data write readback")
	if mode == "benefit": benefit()
	else: placement()
	GameStart.end_session()
	RR.stop_tracking()
	print("RESULT ", JSON.stringify({"suite":"deploy-origin-handoff-" + mode,"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
