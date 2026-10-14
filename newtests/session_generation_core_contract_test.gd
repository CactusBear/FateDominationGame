# Original core assertions are preserved verbatim; only the fixture/dispatch changes.
# Fault branches require an isolated allocator source variant; production has no hook.
# Default all runs the six normal core branches and the public lifetime experiment.
extends Node
const SG = preload("res://scripts/system/session_generation.gd")
const ST = preload("res://scripts/system/session_token.gd")
const SC = preload("res://scripts/system/session_context.gd")
const Rules = preload("res://scripts/match/rule_state.gd")
const Ids = preload("res://scripts/match/net_ids.gd")
var checks:int = 0
var failures:Array = []
var branch:String
func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)
func shape(result:Dictionary, keys:Array, label:String) -> void:
	var actual:Array = result.keys()
	actual.sort(); keys.sort()
	check(actual == keys and typeof(result.ok) == TYPE_BOOL and typeof(result.reason) == TYPE_STRING_NAME, label + " frozen shape")
func meta() -> Dictionary:
	return {"current":SG._current,"issued":SG._issued_tokens.duplicate(),"bindings":SG._bindings.duplicate(true),"contexts":SG._contexts.duplicate(true),"reason":SG._last_lifecycle_reason}
func rule_state() -> String:
	return JSON.stringify(Rules.capture(Ids.new()))
func finish() -> void:
	print("RESULT ", JSON.stringify({"suite":"A1-03-" + branch,"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
func test_reset_release() -> void:
	var reset:Dictionary = GameData.reset_game_session([0,1])
	check(reset.ok and reset.reason == &"current", "public reset legally opens domain")
	check(SG.current_token().ok and SG.validate_context(reset.context).ok, "reset returns usable issued context")
	check(reset.context is SessionContext and is_same(reset.context.token(),SG.current_token().token), "reset context belongs to exact current token")
	GameData.release_game_objects()
	check(SG.current_token() == {"ok":false,"token":null,"reason":&"no_session"}, "public release closes domain")
	check(not SG.validate_context(reset.context).ok, "public release invalidates reset context")
	GameData.release_game_objects()
	check(SG.current_token().reason == &"no_session", "repeat public release never reopens")

func _ready() -> void:
	branch = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "all"
	print("PATH_PROOF ", JSON.stringify({"pid":OS.get_process_id(),"user_dir":OS.get_user_data_dir(),"user_path":ProjectSettings.globalize_path("user://")}))
	test_reset_release()
	if branch == "all":
		for name:String in ["begin","invalidate","bind","derive","query","legal"]:
			_run_branch(name)
		test_lifetime()
	elif branch == "lifetime":
		test_lifetime()
	else:
		_run_branch(branch)
	SG.invalidate_generation(&"core_contract.finished")
	finish()

func _run_branch(name:String) -> void:
	GameData.reset_game_session([0,1])
	GameLog.reset()
	# A1-07 standalone reset opens a domain. Explicitly close it for the original
	# initial no_session contract; never manufacture this state through _current.
	SG.invalidate_generation(&"core_contract.initial_closed")
	var baseline:String = rule_state()
	var before:Dictionary = meta()
	check(SG.current_token() == {"ok":false,"token":null,"reason":&"no_session"}, "initial no_session")
	check(meta() == before, "initial query metadata purity")
	if name == "begin": test_begin()
	elif name == "invalidate": test_invalidate()
	elif name == "bind": test_bind()
	elif name == "derive": test_derive()
	elif name == "query": test_query()
	elif name == "fault_token" or name == "fault_reuse": test_token_fault()
	elif name == "fault_context": test_context_fault()
	elif name == "fault_derive": test_derive_fault()
	elif name == "legal": test_legal()
	else: check(false, "known contract branch")
	check(rule_state() == baseline, "rule graph independent zero writes")
	# Scalar diagnostics only. Do not carry a private metadata graph into lifetime.
	print("OBS_META ", JSON.stringify({"bindings":SG._bindings.size(),"contexts":SG._contexts.size(),"issued":SG._issued_tokens.size(),"closed":not SG.current_token().ok}))

func test_begin() -> void:
	var first:Dictionary = SG.begin_generation(&"probe_start")
	shape(first,["ok","token","reason"],"begin")
	check(first.ok and first.token is SessionToken, "new generation issued handle")
	check(is_same(SG.current_token().token,first.token), "only current is issued reference")
	var second:Dictionary = SG.begin_generation(&"probe_rotate")
	check(second.ok and not is_same(first.token,second.token), "generation is new reference")
	check(SG.validate_token(first.token) == {"ok":false,"reason":&"stale_session"}, "old token rejected")
	check(SG.validate_token(second.token).ok, "new token accepted")
	var fake:SessionToken = ST.new()
	check(SG.validate_token(fake) == {"ok":false,"reason":&"invalid_token"}, "same shape unissued token rejected")
	check(not SG.validate_token(weakref(fake)).ok, "weak fake actual identity rejected")
	check(SG.validate_token(weakref(second.token)).ok, "weak current actual identity accepted")
	for value in [null,{},[],17,&"token",RefCounted.new()]:
		var result:Dictionary = SG.validate_token(value)
		shape(result,["ok","reason"],"malformed token")
		check(not result.ok, "malformed token refused")
	var dead:Object = Object.new()
	var dead_ref:WeakRef = weakref(dead)
	dead.free()
	check(not SG.validate_token(dead_ref).ok, "dead weak token refused")
func test_invalidate() -> void:
	var token:SessionToken = SG.begin_generation(&"open").token
	var subject := RefCounted.new()
	var context:SessionContext = SG.bind_origin(subject,token,&"probe.subject").context
	var records:int = SG._bindings.size()
	var result:Dictionary = SG.invalidate_generation(&"close")
	check(result == {"ok":true,"token":null,"reason":&"invalidated"}, "invalidate exact shape")
	check(SG.invalidate_generation(&"close_again") == result, "invalidate idempotent")
	check(SG.current_token().reason == &"no_session", "invalidate remains closed")
	check(SG.validate_token(token).reason == &"no_session", "closed issued token refused")
	check(SG.validate_context(context).reason == &"no_session", "closed context refused")
	check(SG._bindings.size() == records, "invalidate retains living old binding")
	var fresh:SessionToken = SG.begin_generation(&"new").token
	check(SG.validate_token(token).reason == &"stale_session", "closed old token never reactivated")
	check(SG.validate_token(fresh).ok, "new generation usable after invalidation")
func test_bind() -> void:
	var token:SessionToken = SG.begin_generation(&"bind").token
	var subject := RefCounted.new()
	var original:Dictionary = SG.bind_origin(subject,token,&"probe.trusted_factory")
	shape(original,["ok","context","reason"],"bind")
	check(original.ok, "explicit trusted bind accepted")
	var before:Dictionary = meta()
	var again:Dictionary = Callable(SG,"bind_origin").call(subject,token,&"probe.trusted_factory")
	check(again.ok and is_same(original.context,again.context), "same object same origin bind reentry idempotent")
	check(meta() == before, "bind reentry does not duplicate records")
	check(SG.bind_origin(subject,token,&"different").reason == &"origin_rebind_denied", "same domain different origin rebind denied")
	check(SG.bind_origin(null,token,&"probe.trusted_factory").reason == &"unbound_origin", "null subject rejected")
	check(SG.bind_origin(RefCounted.new(),token,&"").reason == &"unbound_origin", "missing origin declaration refused")
	check(SG.bind_origin(RefCounted.new(),ST.new(),&"probe.trusted_factory").reason == &"invalid_token", "unissued token cannot bind")
	var current:SessionToken = SG.begin_generation(&"next").token
	var retained:int = SG._bindings.size()
	var reject:Dictionary = SG.bind_origin(subject,current,&"probe.trusted_factory")
	check(not reject.ok and reject.reason == &"origin_rebind_denied", "old object cannot be washed by register")
	check(SG._bindings.size() == retained and is_same(SG._bindings[0].token,token), "old source table immutable")
	check(SG.bind_origin(subject,token,&"probe.trusted_factory").reason == &"stale_session", "old token repeat bind denied")
	var next_subject := RefCounted.new()
	check(SG.bind_origin(next_subject,current,&"probe.trusted_factory").ok, "new object new generation works")
	var dead:Object = Object.new()
	var dead_context:SessionContext = SG.bind_origin(dead,current,&"probe.dead").context
	var weak_subject:WeakRef = weakref(dead)
	dead.free()
	var query_before:Dictionary = meta()
	check(SG.origin_of(weak_subject).reason == &"unbound_origin", "dead subject weak identity refused")
	check(meta() == query_before, "dead record query never sweeps")
	SG.begin_generation(&"collect_dead")
	check(not SG._bindings.any(func(row:Dictionary) -> bool: return row.origin == &"probe.dead"), "write collects dead subject only")
	check(not SG.validate_context(dead_context).ok, "retained context still stale after subject cleanup")
func test_derive() -> void:
	var token:SessionToken = SG.begin_generation(&"derive").token
	var subject := RefCounted.new()
	var parent:SessionContext = SG.bind_origin(subject,token,&"probe.parent").context
	for value in [token,weakref(token),parent,weakref(parent),subject,weakref(subject)]:
		var result:Dictionary = SG.derive_context(value,&"probe.child")
		shape(result,["ok","context","reason"],"derive")
		check(result.ok and is_same(result.context.token(),token), "derive inherits original token")
		check(result.context.origin() == &"probe.child", "derive preserves declared child origin")
		check(SG.validate_context(result.context).ok, "derived issued context accepted")
	var before:Dictionary = meta()
	for value in [null,{},ST.new(),SC.new(token,&"probe.parent"),RefCounted.new()]:
		check(SG.derive_context(value,&"probe.child").reason == &"unbound_origin", "unissued parent cannot derive")
	check(meta() == before, "failed derive creates no record")
	SG.begin_generation(&"rotate")
	for value in [token,parent,subject,weakref(parent)]:
		check(SG.derive_context(value,&"probe.clone").reason == &"stale_session", "old runtime clone parent cannot wash source")
	check(SG.derive_context(SG.current_token().token,&"").reason == &"unbound_origin", "derive missing origin refused")
func test_query() -> void:
	var token:SessionToken = SG.begin_generation(&"query").token
	var subject := RefCounted.new()
	var context:SessionContext = SG.bind_origin(subject,token,&"probe.subject").context
	var unknown := RefCounted.new()
	var before:Dictionary = meta()
	for round_index in range(3):
		shape(SG.current_token(),["ok","token","reason"],"current")
		shape(SG.origin_of(subject),["ok","context","reason"],"origin")
		shape(SG.validate_context(context),["ok","reason"],"context")
		check(SG.validate_token(token).ok and SG.validate_context(weakref(context)).ok, "repeat queries legal")
		check(SG.origin_of(unknown).reason == &"unbound_origin", "unknown query never auto binds")
		check(SG.origin_of(weakref(unknown)).reason == &"unbound_origin", "weak unknown query never auto binds")
		check(SG.validate_context(SC.new(token,&"probe.subject")).reason == &"unbound_origin", "same shape unissued context refused")
		check(meta() == before, "query binding and issuance table purity")
	check(is_same(SG.origin_of(weakref(subject)).context,context), "weak subject actual identity accepted")
	SG.begin_generation(&"new")
	check(SG.origin_of(subject).reason == &"stale_session", "origin query retains old source")
	context._source_token = SG.current_token().token
	check(SG.validate_context(context).reason == &"invalid_token", "private field tamper cannot retarget issued context")
	context._source_token = token
	check(not SG.validate_context(context).ok, "restoring fields cannot revive old token")
func test_legal() -> void:
	var token:SessionToken = SG.begin_generation(&"legal").token
	var subject := RefCounted.new()
	var context:SessionContext = SG.bind_origin(subject,token,&"probe.legal").context
	for round_index in range(5):
		check(SG.validate_token(token).ok, "same session repeated validate")
		check(SG.validate_context(context).ok, "same session repeated context validate")
		var bound:Dictionary = SG.bind_origin(subject,token,&"probe.legal")
		check(bound.ok and is_same(bound.context,context), "legal idempotent bind same context")
		var child:Dictionary = SG.derive_context(context,&"probe.wait")
		check(child.ok and is_same(child.context.token(),token), "legal repeated derive not one use ticket")
	var old_weak:WeakRef = weakref(token)
	token = null
	check(is_same(old_weak.get_ref(),context.token()), "context keeps original token alive")
	check(SG.validate_token(old_weak).ok, "keep alive weak original valid")
	var first:Dictionary = SG.invalidate_generation(&"closed")
	check(SG.invalidate_generation(&"closed_again") == first, "legal invalidate idempotent")
	check(not SG.validate_token(old_weak).ok, "keep alive old ref cannot revive")
	var fresh:SessionToken = SG.begin_generation(&"fresh").token
	var fresh_subject := RefCounted.new()
	var fresh_context:Dictionary = SG.bind_origin(fresh_subject,fresh,&"probe.legal")
	check(fresh_context.ok and SG.validate_context(fresh_context.context).ok, "fresh generation and fresh object usable")
	check(not SG.derive_context(context,&"probe.clone").ok, "old clone provenance rejected")
func test_token_fault() -> void:
	var old:SessionToken = SG.begin_generation(&"before_fault").token
	var subject := RefCounted.new()
	var context:SessionContext = SG.bind_origin(subject,old,&"probe.fault").context
	OS.set_environment("A1_ALLOCATE_FAULT",branch)
	var result:Dictionary = SG.begin_generation(&"fault")
	OS.set_environment("A1_ALLOCATE_FAULT","")
	check(result == {"ok":false,"token":null,"reason":&"generation_unavailable"}, "allocation failure exact shape")
	check(SG.current_token().reason == &"no_session", "allocation failure closes current")
	check(not SG.validate_token(old).ok and not SG.validate_context(context).ok, "allocation failure never revives old refs")
	check(SG._bindings.size() == 1 and is_same(SG._bindings[0].token,old), "failure preserves immutable old binding")
	var fresh:Dictionary = SG.begin_generation(&"retry_new")
	check(fresh.ok and not is_same(fresh.token,old), "retry issues new never old handle")
	check(SG.bind_origin(subject,fresh.token,&"probe.fault").reason == &"origin_rebind_denied", "failure then retry cannot wash old object")
	check(OS.get_environment("A1_ALLOC_OBS_CLOSED") == "true", "token allocator observes revocation before allocation")
func test_context_fault() -> void:
	var old:SessionToken = SG.begin_generation(&"before_fault").token
	var subject := RefCounted.new()
	var before:Dictionary = meta()
	OS.set_environment("A1_ALLOCATE_FAULT",branch)
	var result:Dictionary = SG.bind_origin(subject,old,&"probe.fault")
	OS.set_environment("A1_ALLOCATE_FAULT","")
	check(not result.ok and result.context == null, "context allocation failure rejected")
	check(SG.current_token().reason == &"no_session", "context allocation failure closes domain")
	check(SG._bindings == before.bindings and SG._contexts == before.contexts, "context failure has no half records")
	check(not SG.validate_token(old).ok, "context failure cannot revive old token")
	var fresh:SessionToken = SG.begin_generation(&"fresh").token
	check(SG.bind_origin(subject,fresh,&"probe.fault").ok, "uncommitted subject can bind fresh after recovery")


func test_derive_fault() -> void:
	var token:SessionToken = SG.begin_generation(&"derive_fault.setup").token
	var subject := RefCounted.new()
	var parent:SessionContext = SG.bind_origin(subject,token,&"derive_fault.parent").context
	var sibling:SessionContext = SG.derive_context(parent,&"derive_fault.sibling").context
	check(SG.validate_context(parent).ok and SG.validate_context(sibling).ok, "derive fault parent and sibling initially legal")
	# Scalar counts cannot keep a context/token alive; public refusals remain the oracle.
	var context_records:int = SG._contexts.size()
	var binding_records:int = SG._bindings.size()
	OS.set_environment("A1_ALLOCATE_FAULT","fault_derive")
	var result:Dictionary = SG.derive_context(parent,&"derive_fault.failed_child")
	OS.set_environment("A1_ALLOCATE_FAULT","")
	check(SG._contexts.size() == context_records and SG._bindings.size() == binding_records, "derive allocation failure adds no partial registry records")
	check(result == {"ok":false,"context":null,"reason":&"unbound_origin"}, "derive allocation failure exact shape no half context")
	check(not SG.validate_context(result.context).ok, "derive allocation failure yields no usable context")
	check(SG.current_token() == {"ok":false,"token":null,"reason":&"no_session"}, "derive allocation failure closes domain")
	check(SG.validate_context(parent) == {"ok":false,"reason":&"no_session"}, "derive allocation failure revokes parent")
	check(SG.validate_context(sibling) == {"ok":false,"reason":&"no_session"}, "derive allocation failure revokes sibling")
	check(SG.validate_token(token).reason == &"no_session", "derive allocation failure revokes original token")
	check(SG.origin_of(subject).reason == &"stale_session", "derive allocation failure preserves stale subject provenance")
	var fresh:SessionToken = SG.begin_generation(&"derive_fault.recovery").token
	check(SG.validate_token(fresh).ok and not is_same(fresh,token), "derive recovery issues fresh legal token")
	check(SG.bind_origin(subject,fresh,&"derive_fault.parent").reason == &"origin_rebind_denied", "derive recovery cannot wash old live subject")
	check(not SG.derive_context(parent,&"derive_fault.wash").ok and not SG.derive_context(sibling,&"derive_fault.wash").ok, "derive recovery cannot wash old parent or sibling")
	var fresh_subject := RefCounted.new()
	var bound:Dictionary = SG.bind_origin(fresh_subject,fresh,&"derive_fault.new_subject")
	check(bound.ok and SG.validate_context(bound.context).ok, "derive recovery fresh subject binds legally")
	var child:Dictionary = SG.derive_context(bound.context,&"derive_fault.new_child")
	check(child.ok and SG.validate_context(child.context).ok and is_same(child.context.token(),fresh), "derive recovery fresh child remains legal")

func test_lifetime() -> void:
	# Never call meta(), retain a service row, or retain query Dictionaries here.
	SG.invalidate_generation(&"lifetime.clean_previous")
	SG.invalidate_generation(&"lifetime.collect_previous")
	var baseline:String = rule_state()
	var token:SessionToken = SG.begin_generation(&"lifetime.original").token
	var subject:RefCounted = RefCounted.new()
	var parent:SessionContext = SG.bind_origin(subject,token,&"lifetime.parent").context
	var sibling:SessionContext = SG.derive_context(parent,&"lifetime.sibling").context
	var last_context:SessionContext = SG.derive_context(parent,&"lifetime.last").context
	var weak_token:WeakRef = weakref(token)
	var weak_subject:WeakRef = weakref(subject)
	var weak_parent:WeakRef = weakref(parent)
	var weak_sibling:WeakRef = weakref(sibling)
	var weak_context:WeakRef = weakref(last_context)
	check(SG.validate_context(last_context).ok, "lifetime last context initially legal")
	subject = null
	parent = null
	sibling = null
	token = null
	# Two write passes also remove records whose handles die during the first pass.
	SG.begin_generation(&"lifetime.rotate_and_collect")
	SG.begin_generation(&"lifetime.second_collect")
	check(weak_subject.get_ref() == null, "lifetime service does not retain dead subject")
	check(weak_parent.get_ref() == null and weak_sibling.get_ref() == null, "lifetime other contexts are released")
	check(weak_token.get_ref() != null, "lifetime last context retains original token after rotation and sweep")
	check(SG.validate_token(weak_token).reason == &"stale_session", "lifetime retained token is stale not revived")
	check(is_same(weak_token.get_ref(),last_context.token()), "lifetime last context still references exact original token")
	check(SG.validate_context(last_context).reason == &"stale_session", "lifetime last context remains stale")
	last_context = null
	check(weak_context.get_ref() == null, "lifetime last context dies without observer retention")
	SG.invalidate_generation(&"lifetime.final_collect")
	SG.invalidate_generation(&"lifetime.final_collect_again")
	check(weak_token.get_ref() == null, "lifetime token dies after last context and write sweep")
	check(not SG.validate_token(weak_token).ok, "lifetime dead weak token cannot validate")
	check(SG.current_token().reason == &"no_session", "lifetime sweep never opens a domain")
	check(rule_state() == baseline, "lifetime experiment leaves rule graph unchanged")
