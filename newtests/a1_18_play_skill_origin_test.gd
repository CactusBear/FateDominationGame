extends Node

var checks:int = 0
var failures:Array = []
var subject:BaseSkill
var result:Variant = null
var mode:String = ""
var callback_hits:int = 0
var overdraft:bool = false
var requested:bool = false:
	set(value):
		requested = value
		if value: result = PlaySkill.new().exec(subject, 0, true, null, null, overdraft)
var callback:bool = false:
	set(value):
		callback = value
		if value:
			callback_hits += 1
			match mode:
				"reset": GameProgress.reset_progress()
				"rotate": SessionGeneration.begin_generation(&"a1_18.listener_rotate")
				"magic": GameDataManager.find_player_data(0).magic = BaseNumber.new(10)
				"raise": subject._cost.set_num(BaseNumber.new(20))
				"lower": subject._cost.set_num(BaseNumber.new(2))

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", label, " ", ok)

func setup() -> SessionContext:
	var started:Dictionary = GameData.reset_game_session([0,1])
	check(started.ok, "PRE session")
	GameData.player_id = 0
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	var data:Dictionary = GameDataManager.find_player_data(0)
	data.is_out = false
	data.magic.set_num(BaseNumber.new(10))
	GameLog.reset()
	mode = ""; result = null; callback_hits = 0; overdraft = false
	return started.context

func card(context:SessionContext, amount:float = 1) -> BaseSkill:
	var skill:BaseSkill = BaseSkill.new("a1_18_skill", "", [], BaseNumber.new(amount), BaseNumber.new(2), false, [], false)
	if context != null: check(SessionGeneration.bind_origin(skill, context.token(), &"a1_18.new_skill").ok, "PRE fresh skill")
	return skill

func effect(context:SessionContext, funcs:Array, points:Array = []) -> BaseEffect:
	var loaded:Array = LoadHelper.load_effects([{"effect_name":"a1_18_runtime", "time_points":points, "priority":0,
		"is_pure_passive":true, "is_residue":false, "need_activate":false, "effect_numbers":[], "funcs":funcs}], null, context)
	check(loaded.size() == 1, "PRE trusted runtime")
	return loaded[0] if loaded.size() == 1 else null

# Registered SetProperty supplies a real EM frame. The callback's stored card is
# deliberately outside BaseFunc parameters: this isolates PlaySkill's own gate.
func invoke(context:SessionContext, outer:bool = false) -> void:
	var root:BaseEffect = effect(context, [{"func_name":"set_property", "parameters":[self,"requested",true]}], ["a1_18_outer"] if outer else [])
	if root == null: return
	check(EffectManager.register_effect(root,0), "PRE registered root")
	if outer: TimePointChecker.dynamic_time_point(["a1_18_outer"],0,null,context)
	else: EffectManager.run_base_func(root._funcs[0],root,root.runtime_context())

func listener(context:SessionContext, point:String = TimePoints.CARD_COST_CALCULATED) -> void:
	var live:BaseEffect = effect(context,[{"func_name":"set_property", "parameters":[self,"callback",true]}],[point])
	check(live != null and EffectManager.register_effect(live,1), "PRE real listener")

func clean_rejection(data:Dictionary, magic:BaseNumber, balance:float) -> bool:
	return not subject._is_activating and data.played_cards.is_empty() and data.power.number == 0 and magic.number == balance \
		and GameLog.query({"type":"play"},null,-1).is_empty() and GameLog.query({"type":"resource_payment"},null,-1).is_empty()

func _ready() -> void: call_deferred("run")

func run() -> void:
	print("USER_PATH ", OS.get_user_data_dir())
	var context:SessionContext = setup()
	subject = card(context)
	var data:Dictionary = GameDataManager.find_player_data(0)
	var magic:BaseNumber = data.magic
	check(not EffectManager.execution_context().ok, "PRE no frame")
	check(PlaySkill.new().exec(subject,0,true) == false, "no frame rejects fresh card")
	check(clean_rejection(data,magic,10), "no frame no partial payment or activation")
	# Even a manually assigned activating effect is not a verified frame.
	EffectManager.activating_eff = effect(context,[])
	check(PlaySkill.new().exec(subject,0,true) == false, "activating effect is not provenance")
	EffectManager.activating_eff = null

	context = setup(); subject = card(null)
	data = GameDataManager.find_player_data(0); magic = data.magic
	invoke(context)
	check(result == false and clean_rejection(data,magic,10), "unbound card rejects in current frame")

	context = setup(); subject = card(context)
	data = GameDataManager.find_player_data(0); magic = data.magic
	var reset:Dictionary = GameProgress.reset_progress()
	check(reset.ok and is_same(data,GameDataManager.find_player_data(0)), "PRE progress-only reset retains dictionary")
	invoke(reset.context)
	check(result == false and clean_rejection(data,magic,10), "old skill rejects with new frame same ID dictionary")
	check(not SessionGeneration.origin_of(subject).ok, "consumer did not rebind old skill")

	for mutation in ["reset","rotate","magic","raise"]:
		context = setup(); subject = card(context)
		data = GameDataManager.find_player_data(0); magic = data.magic
		mode = mutation; listener(context); invoke(context)
		check(callback_hits == 1, "real cost listener " + mutation)
		check(result == false and clean_rejection(data,magic,10), "callback rejects without partial state " + mutation)
		if mutation == "magic": check(data.magic.number == 10 and not is_same(data.magic,magic), "S06 replacement not debited")

	for args in [[1.0,false,false,9.0],[-2.0,false,false,10.0],[20.0,true,false,10.0],[20.0,false,true,-10.0]]:
		context = setup(); subject = card(context,args[0]); data = GameDataManager.find_player_data(0)
		data.is_magic_immune = args[1]; overdraft = args[2]
		invoke(context)
		check(result == true and subject._is_activating and data.played_cards == [subject] and data.power.number == 2, "same-session legal coherent " + str(args[0]))
		check(data.magic.number == args[3], "legal exact payment " + str(args[0]))
		check(GameLog.query({"type":"play"},null,-1).size() == 1, "legal one play fact")
		check(GameLog.query({"type":"time_point","tags":TimePoints.CARD_REVEALED},null,-1).size() == 1 and GameLog.query({"type":"time_point","tags":TimePoints.PLAYED_CARD},null,-1).size() == 1, "legal reveal and played facts")

	# Use the production registered play_skill descriptor, not only the setter seam.
	context = setup(); subject = card(context); data = GameDataManager.find_player_data(0)
	var registered:BaseEffect = effect(context,[{"func_name":"play_skill","parameters":[subject,0,true]}])
	check(registered != null and EffectManager.register_effect(registered,0), "PRE registered PlaySkill factory")
	var played:Array = EffectManager.run_base_func(registered._funcs[0],registered,registered.runtime_context())
	check(played[0] and played[1] == true and subject._is_activating and data.played_cards == [subject] and data.magic.number == 9, "registered PlaySkill real frame legal")

	context = setup(); subject = card(context,20); data = GameDataManager.find_player_data(0)
	mode = "lower"; listener(context); invoke(context)
	check(callback_hits == 1 and result == true and data.magic.number == 8 and data.played_cards == [subject], "real sync listener completes before payment")

	# A post-commit provenance loss blocks later facts; full A4 rollback is external.
	context = setup(); subject = card(context); data = GameDataManager.find_player_data(0)
	mode = "rotate"; listener(context,TimePoints.CARD_REVEALED); invoke(context)
	check(callback_hits == 1 and result == false, "reveal source loss rejects remaining tail")
	check(GameLog.query({"type":"time_point","tags":TimePoints.PLAYED_CARD},null,-1).is_empty(), "reveal source loss no later played fact")
	if OS.get_cmdline_user_args().has("a4-open"):
		print("OBSERVED A4 result=",result," activated=",subject._is_activating," balance=",data.magic.number," entered=",data.played_cards.has(subject))
		check(clean_rejection(data,data.magic,10), "OPEN A4 rejected post-commit tail must leave no partial state")

	# Separate A3 OPEN suite: automatic outer pipeline merely queues the listener.
	if OS.get_cmdline_user_args().has("a3-open"):
		context = setup(); subject = card(context); data = GameDataManager.find_player_data(0)
		mode = "raise"; listener(context); invoke(context,true)
		print("OBSERVED A3 callback_hits=",callback_hits," final_cost=",subject._cost.number," balance=",data.magic.number," entered=",data.played_cards.has(subject))
		check(callback_hits == 1 and data.magic.number == 10 and not subject._is_activating and data.played_cards.is_empty(), "OPEN WR021 outer cost completion before payment")
	print("RESULT ", JSON.stringify({"checks":checks,"failures":failures,"suite":"a1_18_play_skill_origin"}))
	get_tree().quit(0 if failures.is_empty() else 1)
