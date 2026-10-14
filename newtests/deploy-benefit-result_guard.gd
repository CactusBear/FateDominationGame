extends Node

const RR = preload("res://scripts/match/rule_random.gd")
var checks:int = 0
var failures:Array = []
var source:SessionContext
var request:Array = []
var receipt:Dictionary = {}
var legacy:Variant
var use_legacy:bool = false
var probe_mode:String = "edit"
var probe_requested:bool = false:
	set(value):
		probe_requested = value
		if not value: return
		if probe_mode == "benefit_legacy":
			legacy = DeployRules.new().callv("apply_benefit", request)
		elif probe_mode == "benefit":
			receipt = DeployRules.new().callv("apply_benefit_result", request) if DeployRules.new().has_method("apply_benefit_result") else {"status":"MISSING_API", "actual_delta":-999}
		elif probe_mode == "query":
			legacy = CanGainMagic.new().callv("exec", request)
		else:
			var operation = EditMagic.new()
			if use_legacy: legacy = operation.callv("exec", request)
			elif operation.has_method("exec_result"): receipt = operation.callv("exec_result", request)
			else: receipt = {"status":"MISSING_API", "actual_delta":-999}
var replacement_mode:String = ""
var borrowed_result:Dictionary = {}
var borrowed_query:Variant
var replace_requested:bool = false:
	set(value):
		replace_requested = value
		if not value: return
		if replacement_mode == "member":
			GameData.player_data_library[0] = GameData.player_data_library[0].duplicate()
		elif replacement_mode == "session":
			GameStart.end_session()
			var fresh:Dictionary = GameData.reset_game_session([0,1])
			borrowed_result = result_edit([null,BaseNumber.new(-1),0,"",null,fresh.context])
			borrowed_query = CanGainMagic.new().callv("exec",["",0,fresh.context])

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func _ready() -> void: call_deferred("run")

func start() -> Dictionary:
	GameStart.end_session()
	GameData.loaded_masters = []; GameData.loaded_servants = []
	RR.start_seed(81749)
	check(GameStart.game_start([0,1]), "PRE real GameStart")
	source = GameStart.startup_context()
	check(source != null and SessionGeneration.validate_context(source).ok, "PRE startup original source")
	request = []; receipt = {}; use_legacy = false; probe_mode = "edit"; legacy = null
	return GameDataManager.find_player_data(0)

func declaration(funcs:Array, points:Array = []) -> Dictionary:
	return {"effect_name":"deploy-benefit-result-probe", "time_points":points, "priority":0,
		"is_pure_passive":true, "is_residue":false, "need_activate":false, "effect_numbers":[], "funcs":funcs}

func register(funcs:Array, points:Array = []) -> BaseEffect:
	var loaded:Array = LoadHelper.load_effects([declaration(funcs,points)], null, source)
	check(loaded.size() == 1 and EffectManager.register_effect(loaded[0],0), "PRE trusted declarative operation registration")
	return loaded[0]

func in_frame(args:Array, kind:String = "edit", old:bool = false, expected_frame_success:bool = true) -> void:
	request = args; probe_mode = kind; use_legacy = old
	var effect:BaseEffect = register([{"func_name":"set_property", "parameters":[self,"probe_requested",true], "var_index":-1}])
	var result:Array = EffectManager.run_base_func(effect._funcs[0], effect, effect.runtime_context())
	check(result[0] == expected_frame_success, "actual validated frame returns expected source status")

func changes() -> int:
	return GameLog.query({"type":"magic_add", "actor":0}, null).size() + GameLog.query({"type":"magic_decrease", "actor":0}, null).size()

func result_edit(args:Array) -> Dictionary:
	var operation = EditMagic.new()
	return operation.callv("exec_result",args) if operation.has_method("exec_result") else {"status":"MISSING_API", "actual_delta":-999, "wrote":false}

func available() -> void:
	var d:Dictionary = start()
	check(CanGainMagic.new().callv("exec",["workshop",0,source]) == true, "query explicit original source without frame")
	check(CanGainMagic.new().exec("workshop",0) == null, "query missing original source rejects")
	check(CanGainMagic.new().callv("exec",["workshop",98271,source]) == null and not GameData.player_data_library.has(98271), "query unknown member no library creation")
	# 仅负向夹具创建另一张受信合法票；生产消费口不 derive/bind。
	var other:SessionContext = SessionGeneration.derive_context(source, &"negative-other-origin").context
	check(SessionGeneration.validate_context(other).ok, "PRE alternative context genuinely valid")
	in_frame(["",0,other], "query")
	check(legacy == null, "query another legal context cannot replace active original frame")
	var buff := BaseBuff.new("query-prohibition", "")
	buff._is_active = true
	var restriction_data:Dictionary = declaration([])
	restriction_data.effect_name = "cannot_gain_magic_from_workshop"
	var restriction:BaseEffect = LoadHelper.load_effects([restriction_data], buff, source)[0]
	buff._effects = [restriction]; d.buffs.append(buff)
	check(CanGainMagic.new().callv("exec",["workshop",0,source]) == false, "query declared source prohibition")
	check(CanGainMagic.new().callv("exec",["event",0,source]) == true, "query independent source allowed")
	d = start()
	var amount := BaseNumber.new(2)
	var magic:BaseNumber = d.magic
	in_frame([null,amount,0])
	check(receipt.status == "COMPLETED" and receipt.actual_delta == 2 and magic.number == 6 and amount.number == 2 and is_same(magic,d.magic), "result actual gain and amount magic identities")
	check(changes() == 1, "gain exactly one magic resource fact")
	in_frame([null,BaseNumber.new(1),0], "edit", true)
	check(legacy == null and magic.number == 7, "old exec ordinary success stays null")
	d = start(); d.is_magic_immune = true
	in_frame([null,BaseNumber.new(2),0])
	check(receipt.status == "COMPLETED" and receipt.actual_delta == 0 and not receipt.wrote and d.magic.number == 4 and changes() == 0, "immune completed zero delta no resource fact")
	in_frame([null,BaseNumber.new(2),0], "edit", true)
	check(legacy == null, "old exec immune stays null")
	d = start()
	register([{"func_name":"cancel_pending_action", "parameters":[]}], [TimePoints.BEFORE_MAGIC_ADD])
	in_frame([null,BaseNumber.new(2),0])
	check(receipt.status == "CANCELLED" and receipt.actual_delta == 0 and d.magic.number == 4 and changes() == 0, "BEFORE synchronous cancellation zero write")
	in_frame([null,BaseNumber.new(2),0], "edit", true)
	check(legacy == null, "old exec cancellation stays null")
	d = start()
	register([{"func_name":"edit_pending_action", "parameters":["amount",BaseNumber.new(1),null]}], [TimePoints.BEFORE_MAGIC_ADD])
	in_frame([null,BaseNumber.new(2),0])
	check(receipt.status == "COMPLETED" and receipt.actual_delta == 1 and d.magic.number == 5, "BEFORE rewritten amount is actual receipt")
	d = start(); d.magic.set_num(BaseNumber.new(GameData.player_magic_limit(0).number - 1))
	in_frame([null,BaseNumber.new(2),0])
	check(receipt.status == "COMPLETED" and receipt.actual_delta == 1 and d.magic.number == GameData.player_magic_limit(0).number, "cap clamps before receipt delta")
	in_frame([null,BaseNumber.new(2),0])
	check(receipt.status == "COMPLETED" and receipt.actual_delta == 0, "full cap completed zero receipt")
	in_frame([null,BaseNumber.new(0),0])
	check(receipt.status == "COMPLETED" and receipt.actual_delta == 0, "zero edit completed zero receipt")
	d = start()
	receipt = result_edit([null,BaseNumber.new(-9),0,"",null,source])
	check(receipt.status == "COMPLETED" and receipt.actual_delta == -4 and d.magic.number == 0, "ordinary decrease clamps instead of requiring payment")
	d = start()
	var paid_value:Variant = EditMagic.new().callv("exec",[null,BaseNumber.new(-2),0,"probe",null,source])
	check(typeof(paid_value) == TYPE_BOOL and paid_value == true and d.magic.number == 2, "old payment bool succeeds with explicit source")
	var rejected_value:Variant = EditMagic.new().callv("exec",[null,BaseNumber.new(-3),0,"probe",null,source])
	check(typeof(rejected_value) == TYPE_BOOL and rejected_value == false and d.magic.number == 2, "payment rejects insufficient instead of clamping")
	d = start(); d.magic.can_change = false
	receipt = result_edit([null,BaseNumber.new(-2),0,"probe",null,source])
	check(receipt.status == "COMPLETED" and receipt.actual_delta == 0 and not receipt.wrote and d.magic.number == 4 and changes() == 0, "immutable payment has real zero delta not assumed amount")
	d = start(); d.is_magic_immune = true
	receipt = result_edit([null,BaseNumber.new(-2),0,"probe",null,source])
	check(receipt.status == "COMPLETED" and receipt.actual_delta == 0 and receipt.legacy_value == true and changes() == 0, "immune payment preserves PayMagic bool zero delta")
	d = start()
	register([{"func_name":"set_player_data", "parameters":["magic",BaseNumber.new(9),0]}], [TimePoints.MAGIC_ADD])
	in_frame([null,BaseNumber.new(2),0])
	check(receipt.status == "COMPLETED" and receipt.actual_delta == 2 and d.magic.number == 9, "AFTER resource replacement does not contaminate original delta")
	d = start()
	register([{"func_name":"set_player_data", "parameters":["magic",BaseNumber.new(9),0]}], [TimePoints.BEFORE_MAGIC_ADD])
	magic = d.magic
	in_frame([null,BaseNumber.new(2),0])
	check(receipt.status == "REJECTED" and receipt.actual_delta == 0 and magic.number == 4 and d.magic.number == 9 and changes() == 0, "BEFORE replacement rejects old magic without undoing listener")
	d = start(); replacement_mode = "member"
	register([{"func_name":"set_property", "parameters":[self,"replace_requested",true]}], [TimePoints.BEFORE_MAGIC_ADD])
	in_frame([null,BaseNumber.new(2),0])
	check(receipt.status == "REJECTED" and receipt.actual_delta == 0 and d.magic.number == 4 and changes() == 0, "BEFORE same ID member replacement rejects old tail")
	d = start(); replacement_mode = "session"
	register([{"func_name":"set_property", "parameters":[self,"replace_requested",true]}], [TimePoints.BEFORE_MAGIC_ADD])
	in_frame([null,BaseNumber.new(2),0], "edit", false, false)
	check(receipt.status == "REJECTED" and receipt.actual_delta == 0 and d.magic.number == 4 and GameData.player_data_library[0].magic.number == 4, "BEFORE session change rejects old resource tail")
	check(borrowed_result.status == "REJECTED" and borrowed_query == null and GameData.player_data_library[0].magic.number == 4, "stale active frame cannot borrow new legal lifecycle source")
	var expired:SessionContext = source
	d = start()
	var old_count:int = changes()
	receipt = result_edit([null,BaseNumber.new(-1),0,"",null,expired])
	check(receipt.status == "REJECTED" and receipt.actual_delta == 0 and d.magic.number == 4 and changes() == old_count, "expired explicit source zero edits and logs")
	check(CanGainMagic.new().callv("exec",["",0,expired]) == null, "expired query rejects")
	d = start()
	check(SetLocation.new().exec(MapData.magic_workshop0,0,false,false,false,source), "PRE neutral placement independent benefit")
	in_frame([MapData.magic_workshop0,0], "benefit")
	check(receipt.status == "COMPLETED" and receipt.actual_delta == 2 and d.magic.number == 6, "independent benefit consumes full actual result")
	d.magic.set_num(BaseNumber.new(GameData.player_magic_limit(0).number - 1))
	in_frame([MapData.magic_workshop0,0], "benefit_legacy")
	check(legacy == 1 and d.magic.number == GameData.player_magic_limit(0).number, "legacy benefit reports actual cap delta not printed amount")
	d.is_magic_immune = true
	in_frame([MapData.magic_workshop0,0], "benefit_legacy")
	check(legacy == 0, "legacy benefit immunity reports zero")

func formal() -> void:
	var d:Dictionary = start()
	var loc:BaseLocation = DeployRules.pick_location(MapData.magic_workshop)
	var command = MatchCommands.new()
	var result:Dictionary = command.callv("deploy_result",[loc,0,source])
	check(result.status == "COMPLETED" and result.placed, "formal original source deployment benefit completed")
	check(d.location == loc and GameLog.query({"type":"deploy", "actor":0},null).size() == 1, "formal exactly one real placement fact")
	check(d.magic.number == 4 + loc._magic.number and result.benefit.actual_delta == loc._magic.number and changes() == 1, "formal printed gain actual single magic fact")
	print("FORMAL_OBSERVATION ",JSON.stringify(result))

func run() -> void:
	print("USER_DIR ",OS.get_user_data_dir())
	var f := FileAccess.open("user://deploy-benefit-result.txt",FileAccess.WRITE)
	f.store_string("deploy-benefit-result"); f.close()
	check(FileAccess.get_file_as_string("user://deploy-benefit-result.txt") == "deploy-benefit-result", "actual user data write readback")
	if OS.get_cmdline_user_args().has("formal"): formal()
	else: available()
	GameStart.end_session(); RR.stop_tracking()
	print("RESULT ",JSON.stringify({"suite":"deploy-benefit-result", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
