extends Node

var checks:int = 0
var failures:Array = []
var source:SessionContext
var other:SessionContext
var mode:String = ""
var action:Dictionary = {}
var nested:Dictionary = {}
var received:Array = []
var replacement:Dictionary = {}
var expected_running:bool = false
var root_callback:bool = false:
	set(value):
		root_callback = value
		if value:
			replacement = GameData.player_data_library[1].duplicate()
			GameData.player_data_library[1] = replacement
			EffectManager.is_running = expected_running
var invoked:bool = false:
	set(value):
		invoked = value
		if not value: return
		match mode:
			"legacy":
				for args in [["before-magic-origin"], ["before-magic-origin",0], ["before-magic-origin",0,{}], ["before-magic-origin",0,{},null]]:
					received.append(EffectManager.callv("begin_pending_action",args))
			"borrow":
				action = EffectManager.begin_pending_action("before-magic-origin",0,{},null,other)
			"root_member":
				action = EffectManager.begin_pending_action(TimePoints.BEFORE_MAGIC_ADD,0,{"amount":BaseNumber.new(2)},null,EffectManager.execution_context().context)
			"nested":
				var original:Dictionary = EffectManager.current_pending_action()
				nested = EffectManager.begin_pending_action("before-magic-origin-inner",0,{"amount":BaseNumber.new(9)},null,EffectManager.execution_context().context)
				check(is_same(EffectManager.current_pending_action(),original),"nested returns to original pending identity")
			"member":
				replacement = GameData.player_data_library[0].duplicate()
				GameData.player_data_library[0] = replacement
				EffectManager.is_running = expected_running
			"session":
				GameStart.end_session()
				replacement = GameData.reset_game_session([0,1])
				EffectManager.is_running = expected_running
			"invalidate":
				SessionGeneration.invalidate_generation(&"before-magic-origin-listener")

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ",label," ",ok)
	if not ok: failures.append(label)

func fresh() -> Dictionary:
	GameStart.end_session()
	var created:Dictionary = GameData.reset_game_session([0,1])
	check(created.ok,"PRE real public session reset")
	source = created.context
	other = SessionGeneration.derive_context(source,&"before-magic-origin-other").context
	check(SessionGeneration.validate_context(source).ok and SessionGeneration.validate_context(other).ok,"PRE original and independent legal origins")
	received=[];action={};nested={};mode="";replacement={};expected_running=false
	return GameDataManager.find_player_data(0)

func registered(funcs:Array, points:Array = [], ctx:SessionContext = null, owner:Variant = null, bound:bool = false, id:int = 0) -> BaseEffect:
	var effects:Array = LoadHelper.load_effects([{"effect_name":"before-magic-origin-listener", "time_points":points,
		"priority":0,"is_pure_passive":true,"is_residue":false,"need_activate":false,"source_bound":bound,
		"effect_numbers":[],"funcs":funcs}],owner,ctx if ctx != null else source)
	check(effects.size()==1 and EffectManager.register_effect(effects[0],id),"PRE trusted declarative listener")
	return effects[0]

func invoke_frame(id:int = 0) -> void:
	var effect:BaseEffect = registered([],[],source,null,false,id)
	var outcome:Array = EffectManager.run_func_descriptor({"func_name":"set_property","parameters":[self,"invoked",true]},effect,effect.runtime_context())
	check(outcome[0],"real registered function frame executes")

func before_facts() -> int:
	return GameLog.query({"type":"time_point","tags":TimePoints.BEFORE_MAGIC_ADD},null).size()

func magic_facts() -> int:
	return GameLog.query({"type":"magic_add","actor":0},null).size()

func change_listener(kind:String, ctx:SessionContext = null) -> void:
	mode=kind
	registered([{"func_name":"set_property","parameters":[self,"invoked",true]}],[TimePoints.BEFORE_MAGIC_ADD],ctx)

func public_positive() -> void:
	var data:Dictionary=fresh()
	var amount:=BaseNumber.new(2)
	action=EffectManager.begin_pending_action(TimePoints.BEFORE_MAGIC_ADD,0,{"amount":amount},null,source)
	check(not action.get("invalidated",false) and is_same(action.values.amount,amount),"public no-frame original context preserves BaseNumber values")
	check(before_facts()==1 and EffectManager.current_pending_action().is_empty() and not EffectManager.is_running,"public no-frame BEFORE once and original stack idle")
	var result:Dictionary=EditMagic.new().exec_result(null,BaseNumber.new(2),0,"",null,source)
	check(result.status=="COMPLETED" and result.actual_delta==2 and data.magic.number==6 and magic_facts()==1,"public EditMagic actually grants once with original source")
	data=fresh()
	registered([{"func_name":"cancel_pending_action","parameters":[]}],[TimePoints.BEFORE_MAGIC_ADD],other)
	result=EditMagic.new().exec_result(null,BaseNumber.new(2),0,"",null,source)
	check(result.status=="CANCELLED" and data.magic.number==4 and magic_facts()==0,"different legal listener origin synchronously cancels public gain")
	data=fresh()
	registered([{"func_name":"edit_pending_action","parameters":["amount",BaseNumber.new(1),null]}],[TimePoints.BEFORE_MAGIC_ADD],other)
	result=EditMagic.new().exec_result(null,BaseNumber.new(2),0,"",null,source)
	check(result.status=="COMPLETED" and result.actual_delta==1 and data.magic.number==5 and magic_facts()==1,"different legal listener origin rewrites public gain before commit")
	data=fresh();change_listener("nested",other)
	registered([{"func_name":"edit_pending_action","parameters":["amount",BaseNumber.new(1),null]}],["before-magic-origin-inner"],other)
	result=EditMagic.new().exec_result(null,BaseNumber.new(2),0,"",null,source)
	var inner_amount:BaseNumber = nested.get("values",{}).get("amount") as BaseNumber
	check(inner_amount!=null and inner_amount.number==1 and data.magic.number==6,"nested amount rewrite does not change outer amount")
	check(EffectManager.current_pending_action().is_empty(),"nested successful public scopes fully unwind")

func rejects() -> void:
	var data:Dictionary=fresh()
	for bad in [null,SessionContext.new(),{},"forged"]:
		var count:int=before_facts()
		var rejected:Dictionary=EffectManager.begin_pending_action(TimePoints.BEFORE_MAGIC_ADD,0,{"amount":BaseNumber.new(2)},null,bad)
		check(rejected.get("invalidated",false) and rejected.get("cancelled",false) and rejected.get("status")=="REJECTED","missing forged original context returns consumable rejection")
		check(before_facts()==count and magic_facts()==0 and data.magic.number==4 and EffectManager.current_pending_action().is_empty(),"missing forged original context creates no initiator fact or write")
	var old:SessionContext=source
	data=fresh()
	var rejected:Dictionary=EffectManager.begin_pending_action(TimePoints.BEFORE_MAGIC_ADD,0,{},null,old)
	check(rejected.get("invalidated",false) and before_facts()==0 and data.magic.number==4,"expired original context creates no initiator fact or write")
	rejected=EffectManager.begin_pending_action(TimePoints.BEFORE_MAGIC_ADD,92871,{},null,source)
	check(rejected.get("invalidated",false) and not GameData.player_data_library.has(92871) and before_facts()==0,"unknown actual member does not create library or fact")
	mode="borrow";invoke_frame()
	check(action.get("invalidated",false) and GameLog.query({"type":"time_point","tags":"before-magic-origin"},null).is_empty(),"another legal context cannot borrow active original function frame")

func source_bound() -> void:
	fresh()
	var first:BaseAttack=LoadAttack.resolve("strength:2",source)
	var second:BaseAttack=LoadAttack.resolve("strength:2",source)
	check(first!=null and second!=null and first!=second,"PRE two independently valid business sources")
	registered([{"func_name":"cancel_pending_action","parameters":[]}],[TimePoints.BEFORE_MAGIC_ADD],other,first,true)
	action=EffectManager.begin_pending_action(TimePoints.BEFORE_MAGIC_ADD,0,{},second,source)
	check(not action.cancelled and is_same(action.source,second),"context does not replace business source bound filter")
	action=EffectManager.begin_pending_action(TimePoints.BEFORE_MAGIC_ADD,0,{},first,source)
	check(action.cancelled and not action.get("invalidated",false) and is_same(action.source,first),"matching business source cancels with independent original context")

func identity_callbacks() -> void:
	var data:Dictionary=fresh()
	var old_magic:BaseNumber=data.magic
	registered([{"func_name":"set_player_data","parameters":["magic",BaseNumber.new(9),0]}],[TimePoints.BEFORE_MAGIC_ADD],other)
	var result:Dictionary=EditMagic.new().exec_result(null,BaseNumber.new(2),0,"",null,source)
	check(result.status=="REJECTED" and old_magic.number==4 and data.magic.number==9 and magic_facts()==0,"magic replacement rejects origin write but preserves legal listener side effect")
	data=fresh();change_listener("member",other)
	EffectManager.is_running = true
	result=EditMagic.new().exec_result(null,BaseNumber.new(2),0,"",null,source)
	check(result.status=="REJECTED" and data.magic.number==4 and not is_same(data,GameDataManager.find_player_data(0)) and magic_facts()==0,"same ID replacement rejects old resource write")
	check(EffectManager.is_running==expected_running,"member change does not restore old running after callback")
	data=fresh();change_listener("session",other)
	result=EditMagic.new().exec_result(null,BaseNumber.new(2),0,"",null,source)
	check(result.status=="REJECTED" and data.magic.number==4 and GameDataManager.find_player_data(0).magic.number==4 and magic_facts()==0,"session change refuses old initiator fact and resource write")
	check(EffectManager.current_pending_action().is_empty() and EffectManager.is_running==expected_running,"session change does not restore or pop new session scope")
	data=fresh()
	registered([{"func_name":"set_property","parameters":[self,"root_callback",true]}],[TimePoints.BEFORE_MAGIC_ADD],other)
	mode="root_member";invoke_frame(1)
	check(action.get("invalidated",false) and data.magic.number==4 and magic_facts()==0,"root owner replacement rejects unchanged target member action")
	data=fresh();change_listener("invalidate",other)
	result=EditMagic.new().exec_result(null,BaseNumber.new(2),0,"",null,source)
	check(result.status=="REJECTED" and data.magic.number==4 and magic_facts()==0,"callback revoked original context refuses initiator write")

func legacy() -> void:
	fresh();mode="legacy";invoke_frame()
	check(received.size()==4 and received.all(func(item):return not item.get("invalidated",false)),"old 1 2 3 4 argument ABI inherits actual validated function frame")
	check(EffectManager.current_pending_action().is_empty() and not EffectManager.execution_context().ok,"old compatible ABI leaks no pending or function frame")

func run() -> void:
	public_positive();rejects();source_bound();identity_callbacks();legacy()
	GameStart.end_session()
	print("RESULT ",JSON.stringify({"suite":"before-magic-origin","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _ready() -> void: call_deferred("run")
