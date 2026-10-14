extends Node

var checks:int = 0
var failures:Array = []
var case_name:String = ""
var context:SessionContext
var subject:BaseHandCard
var outcome:Variant
var observed:bool = false
var replace_magic:bool = false
var callback_hits:int = 0
var held_magic:BaseNumber
var invoke_trigger:bool = false:
	set(value):
		invoke_trigger = value
		if value: exercise_frame()
var cost_trigger:bool = false:
	set(value):
		cost_trigger = value
		if value:
			callback_hits += 1
			if replace_magic: GameData.player_data_library[0].magic = BaseNumber.new(10)

func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)

func setup(skill:bool = false) -> void:
	GameData.release_game_objects()
	var started:Dictionary = GameData.reset_game_session([0,1])
	check(started.ok, "PRE real session")
	context = started.context
	GameData.player_id=0
	GameProgress.current_round=1
	GameProgress.current_phase_index=2
	GameProgress.current_player_id=0
	var d:Dictionary=GameData.player_data_library[0]
	d.is_out=false
	d.magic.number=10
	d.regular_play_min.number=1
	d.play_limit.number=1
	subject = BaseSkill.new("caller-skill","",[],BaseNumber.new(1),BaseNumber.new(2),false,[],false) if skill else BaseAttack.new("caller-attack","",[],BaseNumber.new(1),BaseNumber.new(2))
	check(SessionGeneration.bind_origin(subject,context.token(),&"paymagic-callers.new-card").ok,"PRE new runtime card")
	d.hand_cards=[subject]
	held_magic=d.magic
	outcome=null;observed=false;callback_hits=0
	GameLog.reset()

func effect(funcs:Array, points:Array = []) -> BaseEffect:
	var loaded:Array=LoadHelper.load_effects([{"effect_name":"paymagic-callers","time_points":points,"priority":0,"is_pure_passive":true,"need_activate":false,"is_residue":false,"effect_numbers":[],"funcs":funcs}],null,context)
	check(loaded.size()==1,"PRE trusted effect factory")
	if loaded.is_empty():return null
	var root:BaseEffect=loaded[0]
	check(EffectManager.register_effect(root,0),"PRE effect registered")
	return root

func invoke_frame() -> void:
	var root:BaseEffect=effect([{"func_name":"set_property","parameters":[self,"invoke_trigger",true]}])
	if root!=null: EffectManager.run_base_func(root._funcs[0],root,root.runtime_context())
	check(observed,"PRE actual verified frame exercised")

func exercise_frame() -> void:
	observed=true
	check(EffectManager.execution_context().ok,"PRE verified frame")
	var d:Dictionary=GameData.player_data_library[0]
	match case_name:
		"edit": outcome=EditMagic.new().exec(null,BaseNumber.new(-1),0,"caller-edit",subject)
		"attack": outcome=PlayAttack.new().exec(subject,0,null,null,true)
		"skill": outcome=PlaySkill.new().exec(subject,0,true)
		"faceup":
			var before:String=snapshot()
			outcome=RegularPlay.faceup_allowed(subject,0)
			check(snapshot()==before,"faceup quote pure")
		"mode":
			var before:String=snapshot()
			outcome=RegularPlay.can_add(0,subject,false)
			check(snapshot()==before,"mode quote pure")

func snapshot() -> String:
	var d:Dictionary=GameData.player_data_library[0]
	return JSON.stringify([d.magic.number,d.played_cards.size(),d.hand_cards.size(),d.power.number,GameLog.query({}),GameData.objects.size(),GameData.effects.size()])

func frame_case(name:String) -> void:
	case_name=name;replace_magic=false
	setup(name=="skill")
	invoke_frame()
	check(outcome==true,name+" legal call succeeds")
	var d:Dictionary=GameData.player_data_library[0]
	if name in ["edit","attack","skill"]:
		check(held_magic.number==9,name+" exact debit original magic")
		check(GameLog.query({"type":"magic_decrease"}).size()==1,name+" one payment fact")
	else: check(held_magic.number==10 and d.played_cards.is_empty(),name+" no debit or entry")
	if name in ["attack","skill"]:
		check(subject._is_activating and d.played_cards==[subject],name+" one coherent entry")
		# A real cost listener swaps the magic object. No consumer may reacquire it.
		setup(name=="skill");replace_magic=true
		effect([{"func_name":"set_property","parameters":[self,"cost_trigger",true]}],[TimePoints.CARD_COST_CALCULATED])
		invoke_frame()
		check(callback_hits==1,name+" real cost callback")
		check(outcome==false and held_magic.number==10 and GameData.player_data_library[0].magic.number==10 and not subject._is_activating,name+" replaced identity refused without debit or entry")
		replace_magic=false

func group_case() -> void:
	setup()
	var d:Dictionary=GameData.player_data_library[0]
	check(RegularPlay.submit_group(0,[subject],[true],false,context),"group zero payment accepts original intent")
	check(d.played_cards==[subject] and RegularPlay.completed(0) and held_magic.number==10,"group zero enters and completes once")
	setup()
	preload("res://scripts/match/rule_random.gd").start_seed(350006)
	var funcs:Array=[]
	for i in range(5): funcs.append({"func_name":"do_nothing","parameters":[]})
	effect(funcs,[TimePoints.CARD_COST_CALCULATED])
	EffectManager.configure_runtime_guard({"enabled":true,"steps":2,"seconds":0.0})
	check(RegularPlay.add(0,subject,false,context) and EffectManager.runtime_guard_status().paused,"group real cost wait accepted")
	check(held_magic.number==10 and GameData.player_data_library[0].played_cards.is_empty(),"group wait no early payment or entry")
	for i in range(32):
		if not EffectManager.runtime_guard_status().paused:break
		EffectManager.resume_runtime_guard()
	check(not EffectManager.runtime_guard_status().paused,"group actual guard completed")
	check(held_magic.number==9 and GameData.player_data_library[0].played_cards==[subject] and RegularPlay.completed(0),"group deferred original identity pays once")

func public_quote() -> Dictionary:
	var api:RefCounted=RegularPlay.new()
	return api.call("payment_quote",0,context) if api.has_method("payment_quote") else {}

# 原实现缺新尾参时仅裁去不存在的参数，保留同一业务 oracle。
func quote_call(method:String, args:Array) -> bool:
	var script:Script=RegularPlay.new().get_script()
	for entry:Dictionary in script.get_script_method_list():
		if entry.name==method: return bool(Callable(RegularPlay,method).callv(args.slice(0,entry.args.size())))
	return false

func quote_identity_case() -> void:
	for method in ["faceup_allowed","can_add"]:
		setup()
		var payment:Dictionary=public_quote()
		var args:Array=[subject,0,null,false,payment] if method=="faceup_allowed" else [0,subject,false,payment]
		var before:String=snapshot()
		check(quote_call(method,args),method+" explicit original quote succeeds without frame")
		check(snapshot()==before,method+" explicit quote pure")
		var saved:Callable=quote_call.bind(method,args)
		GameData.player_data_library[0].magic=BaseNumber.new(10)
		before=snapshot()
		check(not saved.call(),method+" saved quote rejects replaced magic")
		check(snapshot()==before and held_magic.number==10,method+" replaced quote no new or old debit")
		setup()
		payment=public_quote()
		args=[subject,0,null,false,payment] if method=="faceup_allowed" else [0,subject,false,payment]
		var member:Dictionary=GameData.player_data_library[0]
		var next:Dictionary=GameProgress.reset_progress()
		check(next.ok and is_same(member,GameData.player_data_library[0]),"PRE reset only preserves member")
		before=snapshot()
		check(not quote_call(method,args),method+" saved quote rejects reset same dictionary")
		check(snapshot()==before,method+" stale quote no facts")
	setup()
	var before:String=snapshot()
	check(not RegularPlay.faceup_allowed(subject,0),"no frame quote never receives current ticket")
	check(snapshot()==before,"no source quote pure rejection")

func query_value(method:String, args:Array) -> Variant:
	var script:Script=RegularPlay.new().get_script()
	for entry:Dictionary in script.get_script_method_list():
		if entry.name==method:return Callable(RegularPlay,method).callv(args.slice(0,entry.args.size()))
	return null

func quote_search_case() -> void:
	setup()
	var d:Dictionary=GameData.player_data_library[0]
	d.regular_play_min.number=2;d.play_limit.number=2
	var extra:BaseAttack=BaseAttack.new("second-quote-card","",[],BaseNumber.new(2),BaseNumber.new(2))
	check(SessionGeneration.bind_origin(extra,context.token(),&"paymagic-callers.new-second-card").ok,"PRE second runtime card")
	d.hand_cards.append(extra)
	var payment:Dictionary=public_quote()
	var before:String=snapshot()
	check(query_value("can_add",[0,subject,false,payment])==true,"quote recursion finds complete two card path")
	check((query_value("modes",[0,subject,payment]) as Array).has(false),"quote modes preserves original intent")
	check((query_value("pending_modes",[0,[subject],[false],extra,payment]) as Array).has(false),"quote pending modes forwards original intent")
	check(query_value("can_play_group_prefix",[0,[subject],[false],false,payment])==true,"quote prefix forwards original intent")
	check(query_value("can_submit_group",[0,[subject,extra],[false,false],false,payment])==true,"quote full group forwards original intent")
	var found:Dictionary=query_value("find_group",[0,[],payment])
	check(not found.is_empty() and not found.hidden.has(true),"quote find_group forwards through recursive pending search")
	check((query_value("find_add",[0,payment]) as Dictionary).get("hidden",true)==false,"quote find_add preserves faceup option")
	check(query_value("has_legal_add",[0,payment])==true and query_value("can_end",[0,payment])==false,"quote completion predicates share captured intent")
	check(snapshot()==before,"recursive quotes have no writes")

func group_identity_case() -> void:
	for mutation in ["magic","reset"]:
		setup()
		preload("res://scripts/match/rule_random.gd").start_seed(350007)
		var funcs:Array=[]
		for i in range(5):funcs.append({"func_name":"do_nothing","parameters":[]})
		effect(funcs,[TimePoints.CARD_COST_CALCULATED])
		EffectManager.configure_runtime_guard({"enabled":true,"steps":2,"seconds":0.0})
		check(RegularPlay.add(0,subject,false,context) and EffectManager.runtime_guard_status().paused,"identity group real wait "+mutation)
		var queue:Array=EffectManager.execution_runtime_snapshot().guard_continuations
		check(not queue.is_empty(),"PRE exact production continuation "+mutation)
		if queue.is_empty():continue
		var tail:Callable=queue.back().continuation
		var state:Dictionary=tail.get_bound_arguments()[0]
		check(is_same(state.context.get("magic"),held_magic),"group state retained creation magic "+mutation)
		if mutation=="magic":GameData.player_data_library[0].magic=BaseNumber.new(10)
		else:
			var next:Dictionary=GameProgress.reset_progress()
			check(next.ok,"PRE real group reset")
		var before:String=snapshot()
		tail.call()
		check(state.phase=="rejected","group exact tail rejects identity/source change "+mutation)
		check(snapshot()==before and held_magic.number==10,"group stale tail no payment entry or facts "+mutation)

func _ready() -> void: call_deferred("run")
func run() -> void:
	print("ENV executable=",OS.get_executable_path()," user=",OS.get_user_data_dir())
	for key in ["TMPDIR","TEMP","TMP","APPDATA","LOCALAPPDATA"]:print("ENV ",key,"=",OS.get_environment(key))
	var selected:String=OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "all"
	for name in ["edit","attack","skill","faceup","mode"]:
		if selected in ["all",name]:frame_case(name)
	if selected in ["all","group"]:group_case()
	if selected in ["all","quote-identity"]:quote_identity_case()
	if selected in ["all","quote-search"]:quote_search_case()
	if selected in ["all","group-identity"]:group_identity_case()
	print("RESULT ",JSON.stringify({"suite":"paymagic-callers","case":selected,"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
