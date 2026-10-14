extends Node

# 独立进程输出真实规则对象图；runner 逐处比较同一依赖冻结，不改生产规则。
var checks:int = 0
var failures:Array = []
var rows:Array = []
var action_context:SessionContext = null

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func setup() -> Dictionary:
	EffectManager.reset_runtime()
	var started:Dictionary = GameProgress.reset_progress()
	check(started.get("ok", false), "public reset creates original context")
	var action:Dictionary = SessionGeneration.derive_context(started.context, &"existing-ops-compare.action")
	check(action.ok, "fixture action inherits original startup source")
	action_context = action.context
	GameLog.reset()
	GameLog.set_context(1, "action")
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	GameData.player_data_library.clear()
	preload("res://scripts/match/rule_random.gd").start_seed(731)
	var d:Dictionary = GameData.new_player_data()
	GameData.player_data_library[0] = d
	d.is_out = false
	d.magic = BaseNumber.new(10)
	# 可信 runtime 建牌入口保存 action_context；数值可变性与原构造一致。
	d.hand_cards = LoadGame.load_attacks([
		{"attack_name":"ops-a", "attack_card_img":"", "attributes":[], "cost":{"number":2,"can_change":true,"is_pure_number":true}, "power":{"number":3,"can_change":true,"is_pure_number":true}, "effects":[]},
		{"attack_name":"ops-b", "attack_card_img":"", "attributes":[], "cost":{"number":2,"can_change":true,"is_pure_number":true}, "power":{"number":4,"can_change":true,"is_pure_number":true}, "effects":[]}
	], "", null, [], action_context)
	# loader 会拼素材前缀；无图夹具仍保留原空路径。
	for card in d.hand_cards: card._card_img = ""
	return d

func observe(label:String, accepted:bool, cards:Array, d:Dictionary) -> void:
	var ids = NetIds.new()
	var projection:Dictionary = ids.snapshot_graph({"player":d,"cards":cards,
		"facts":GameLog.query({}, null),"restrictions":AbilityRestrictions.entries,
		"time_points":NetIds.script_fields(TimePointChecker),
		"random":preload("res://scripts/match/rule_random.gd").snapshot()})
	check(ids.error.is_empty(), label + " complete declared rule projection")
	var log_ids = NetIds.new()
	var logs:Dictionary = log_ids.snapshot_graph({"facts":GameLog.query({}, null)})
	check(log_ids.error.is_empty(), label + " full fact payload and object references")
	rows.append({"case":label,"accepted":accepted,"rule":projection,"logs":logs,
		"resources":{"magic":d.magic.number,"magic_type":typeof(d.magic.number),
		"power":d.power.number,"power_type":typeof(d.power.number),"is_float":d.power.is_float,
		"mutable":d.power.can_change}})

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	for mode in [[false,false],[true,false],[true,true]]:
		var d:Dictionary = setup()
		var cards:Array = d.hand_cards.duplicate()
		var accepted:bool = RegularPlay.submit_group(0,cards,mode,false,action_context)
		check(accepted and d.played_cards == cards, "normal group " + str(mode))
		observe("normal " + str(mode),accepted,cards,d)
	for kind in ["declared", "servant", "master", "side", "alias", "duplicates"]:
		var d:Dictionary = setup()
		var cards:Array = d.hand_cards.duplicate()
		match kind:
			"declared":
				d.deck = cards.duplicate()
				d.hand_cards.clear()
				d.regular_play_zones = ["deck"]
			"servant":
				d.servant_skills = cards.duplicate()
				d.hand_cards.clear()
			"master":
				d.master_skills = cards.duplicate()
				d.hand_cards.clear()
			"side":
				d.side.skills = cards.duplicate()
				d.hand_cards.clear()
			"alias":
				d.servant_skills = d.hand_cards
				d.master_skills = d.hand_cards
				d.side.skills = d.hand_cards
				d.regular_play_zones = ["hand_cards","servant_skills","side/skills"]
			"duplicates":
				d.hand_cards = [cards[0],cards[0],cards[0],cards[1],cards[1],cards[1]]
				d.servant_skills = d.hand_cards
				d.master_skills = d.hand_cards
				d.side.skills = d.hand_cards
		var source:Array = d.hand_cards
		var played:Array = d.played_cards
		var accepted:bool = RegularPlay.submit_group(0,cards,[false,false],false,action_context)
		check(accepted and d.played_cards == cards and is_same(played,d.played_cards) and is_same(source,d.hand_cards),kind + " array identity and enter order")
		observe(kind,accepted,cards,d)
	for power in [0,0.0,2,2.5,-1]:
		for mutable in [true,false]:
			var d:Dictionary = setup()
			var cards:Array = d.hand_cards.duplicate()
			cards[0]._power = BaseNumber.new(power)
			cards[1]._power = BaseNumber.new(0.0)
			d.power = BaseNumber.new(1,mutable)
			var power_ref = d.power
			var accepted:bool = RegularPlay.submit_group(0,cards,[false,false],false,action_context)
			check(accepted and is_same(power_ref,d.power) and d.power.number == (1 + power if mutable else 1),"power value/identity " + str(power) + " " + str(typeof(power)) + " " + str(mutable))
			observe("power " + str(power) + " " + str(typeof(power)) + " " + str(mutable),accepted,cards,d)
	var d:Dictionary = setup()
	var cards:Array = d.hand_cards.duplicate()
	d.is_magic_immune = true
	check(RegularPlay.submit_group(0,cards,[false,false],false,action_context) and d.magic.number == 10,"immunity unchanged")
	observe("immune",true,cards,d)
	d = setup(); cards = d.hand_cards.duplicate()
	var first:bool = RegularPlay.add(0,cards[0],false,action_context)
	observe("incremental first",first,cards,d)
	var second:bool = RegularPlay.add(0,cards[1],true,action_context)
	check(first and second and RegularPlay.completed(0),"incremental completion unchanged")
	observe("incremental complete",second,cards,d)
	# 第一张已入场、第二张费用时点涨价：必须恢复第一张的扣费/来源/属性/威力/日志。
	d = setup(); cards = d.hand_cards.duplicate()
	var effect:BaseEffect = LoadHelper.load_effects([{
		"effect_name":"second cost increase", "time_points":[TimePoints.SELF_CARD_COST_CALCULATED],
		"priority":0, "is_pure_passive":true, "is_residue":true, "effect_numbers":[], "funcs":[]
	}], cards[1], action_context)[0]
	effect._need_activate = false
	effect._source_bound = true
	effect.from = cards[1]
	effect._funcs = LoadHelper.load_funcs([{"func_name":"edit_card_cost","parameters":[BaseNumber.new(20)],"var_index":-1}],effect)
	cards[1]._effects = [effect]
	EffectManager.register_effect(effect,0)
	var rejected:bool = RegularPlay.submit_group(0,cards,[false,false],false,action_context)
	check(not rejected and d.magic.number == 10 and d.power.number == 0 and d.hand_cards == cards and d.played_cards.is_empty(),"second-card refusal restores prior entry/resources")
	check(GameLog.query({"type":"play"},0).is_empty() and GameLog.query({"type":"magic_decrease"},0).is_empty(),"second-card refusal restores facts")
	observe("second-card rollback",rejected,cards,d)
	# 直接 enter 帧覆盖激活 true -> false setter，终态迟到续行必须不再写入。
	d = setup(); cards = d.hand_cards.duplicate()
	cards[0]._is_activating = true
	var state:Dictionary = RegularPlay._begin_group(0,cards,[true,false],Callable(RegularPlay,"_finish_group"), false, action_context)
	state.phase = "enter"
	state["extra_cards"] = []
	RegularPlay._resume_group(state)
	check(state.phase == "done" and not cards[0]._is_activating and cards[0]._is_concealed,"hidden setter deactivates existing source")
	observe("setter completed",true,cards,d)
	RegularPlay._resume_group(state)
	observe("late done continuation",true,cards,d)
	var args:PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		check(false,"explicit E evidence path supplied")
	else:
		var f = FileAccess.open(args[0],FileAccess.WRITE)
		check(f != null,"comparison receipt opened")
		if f != null:
			f.store_string(JSON.stringify(rows)); f.close()
	EffectManager.reset_runtime()
	print("RESULT regular_play_existing_ops_compare checks=",checks," failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
