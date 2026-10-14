extends Node
const Parent = preload("res://scripts/match/rule_checkpoint.gd")
var checks:int = 0
var failures:Array = []
func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ",label," ",ok)
	if not ok: failures.append(label)
const Source = preload("res://scripts/system/session_generation.gd")
const Context = preload("res://scripts/system/session_context.gd")
const Token = preload("res://scripts/system/session_token.gd")
const Domain = preload("res://scripts/system/atomic_execution_domain.gd")
class ReplacedContext extends Context:
	static var token_getter_calls:int = 0
	func token() -> SessionToken:
		token_getter_calls += 1
		# Real public Source validation would scan retained token history if reached.
		Source.validate_token(_source_token)
		return _source_token
const DIMS = ["collections","comparisons","values","objects"]
const AUTH = {"collections":32,"comparisons":96,"values":1024,"objects":0}
const BOUNDS = {"descriptors":24,"slots":48,"leaf_visits":128,"leaf_containers":16,"stack_slots":8}
const LOCAL = {"max_rows":100,"max_units":10000000,"max_scopes":20}
var retained_contexts:Array = []
var retained_tokens:Array = []
func good(out:Dictionary) -> bool:
	return out.get("status")=="COMPLETED"
func fixture(label:String) -> Dictionary:
	var ctx:Variant = Source.derive_context(Source.current_token().token,StringName(label)).context
	retained_contexts.append(ctx)
	var cp = Parent.new()
	check(cp.capture([[1]],{},ctx),label+" real public capture")
	var issued:Dictionary = cp.issue_budget_lease(ctx)
	check(good(issued),label+" official original lease")
	return {"cp":cp,"ctx":ctx,"lease":issued.get("lease"),"trace":ExecutionTrace.new()}
func create(f:Dictionary) -> Dictionary:
	return f.trace.new_bounded_shared_write_journal(f.ctx,LOCAL,f.cp,f.lease,BOUNDS)
func remaining(f:Dictionary) -> Dictionary:
	return f.cp.validate_budget_lease_bounded(f.lease,f.ctx).get("remaining",{})
func debit(before:Dictionary, after:Dictionary, cost:Dictionary) -> bool:
	if before.size()!=4 or after.size()!=4: return false
	for dim in DIMS:
		if before[dim]-after[dim]!=cost.get(dim,0): return false
	return true
func reject(f:Dictionary, owner:Variant, lease:Variant, ctx:Variant, label:String) -> void:
	var before:Dictionary = remaining(f)
	var out:Dictionary = f.trace.new_bounded_shared_write_journal(ctx,LOCAL,owner,lease,BOUNDS)
	check(not good(out) and not out.has("journal") and remaining(f)==before and f.trace.calls.is_empty(),label+" zero journal/debit/live")
func histories() -> void:
	for n in [1,100,512]:
		for i in range(n): retained_tokens.append(Source.begin_generation(StringName("token_"+"tier "+str(n)+"_"+str(i))).token)
		for i in range(n): retained_contexts.append(Source.derive_context(retained_tokens.back(),StringName("context_"+"tier "+str(n)+"_"+str(i))).context)
		var f:Dictionary = {"cp":Parent.new(),"ctx":retained_contexts.back(),"trace":ExecutionTrace.new()}
		check(f.cp.capture([],{},f.ctx),"tier "+str(n)+" exact last context real capture")
		f["lease"] = f.cp.issue_budget_lease(f.ctx).get("lease")
		var before:Dictionary = f.cp.budget_remaining(f.ctx).remaining
		var diag:Dictionary = Source.lifecycle_diagnostics()
		print("HOT_BEGIN ",JSON.stringify({"tier":n,"contexts":diag.contexts,"tokens":diag.issued_tokens}))
		check(good(f.cp.validate_budget_lease_bounded(f.lease,f.ctx)),"tier "+str(n)+" hot bounded validation")
		var paid:Dictionary = f.cp.reserve_budget_bounded(f.lease,{},f.ctx)
		check(good(paid) and debit(before,paid.get("remaining",{}),AUTH),"tier "+str(n)+" fixed empty reserve four-dimensional debit")
		before = paid.get("remaining",{})
		var made:Dictionary = create(f)
		check(good(made),"tier "+str(n)+" real bounded Trace factory")
		if good(made):
			var j:Variant = made.journal
			check(debit(before,remaining(f),made.parent_reservation) and made.parent_reservation=={"collections":42,"comparisons":102,"values":1104,"objects":1},"tier "+str(n)+" factory exact original parent debit")
			print("BOUNDED_DEBIT ",JSON.stringify({"operation":"factory","before":before,"after":remaining(f),"cost":made.parent_reservation}))
			var scoped:Dictionary = j.begin_scope(f.ctx)
			check(good(scoped) and scoped.get("parent_reservation",{})=={"collections":60,"comparisons":108,"values":1200,"objects":1},"tier "+str(n)+" real bounded scope")
			check(good(j.apply([{"kind":"append","target":f.trace.calls,"items":[{"value":n}]}],f.ctx)) and f.trace.calls.size()==1,"tier "+str(n)+" bounded public write")
			if scoped.has("handle"): check(good(j.restore(scoped.handle,f.ctx)) and f.trace.calls.is_empty(),"tier "+str(n)+" bounded identity restore")
		print("HOT_END ",n)
		var old_balance:Dictionary = f.cp.budget_remaining(f.ctx).remaining
		check(good(f.cp.reserve_budget(f.lease,{"comparisons":old_balance.comparisons},f.ctx)),"tier "+str(n)+" exhaust comparisons via original ABI")
		check(good(f.cp.validate_budget_lease(f.lease,f.ctx)) and good(f.cp.reserve_budget(f.lease,{},f.ctx)),"tier "+str(n)+" old free scanning validation remains")
		var zero:Dictionary = f.cp.budget_remaining(f.ctx).remaining
		check(zero.comparisons==0 and not good(f.cp.reserve_budget_bounded(f.lease,{},f.ctx)) and f.cp.budget_remaining(f.ctx).remaining==zero,"tier "+str(n)+" new empty reserve zero comparison balance rejects atomic")
func credentials() -> void:
	var f:Dictionary = fixture("credentials")
	var other:Dictionary = fixture("other_parent")
	for ticket in [Parent.BudgetLease.new(),{},weakref(f.lease)]: reject(f,f.cp,ticket,f.ctx,"fake or wrapped lease")
	reject(f,other.cp,f.lease,f.ctx,"cross owner")
	reject(f,f.cp,other.lease,f.ctx,"cross owner lease")
	reject(f,f.cp,f.lease,other.ctx,"same token different authentic ctx")
	var fake:Variant = Context.new(f.ctx.token(),f.ctx.origin())
	reject(f,f.cp,f.lease,fake,"same-shaped unissued ctx")
	reject(f,RefCounted.new(),f.lease,f.ctx,"same-shaped owner")
	reject(f,f.cp,f.lease,weakref(f.ctx),"wrapped ctx")
	var forged:Variant = ExecutionTrace.WriteJournal.new(f.trace,fake,LOCAL,f.cp,f.lease)
	check(not good(forged.begin_scope(fake)),"direct construction does not forge parent auth")
	var made:Dictionary = create(f)
	check(good(made),"credential public factory control")
	if not good(made): return
	var j:Variant = made.journal
	var token:Variant = f.ctx.token()
	var origin:StringName = f.ctx.origin()
	var balance:Dictionary = remaining(f)
	f.ctx.set("_source_origin",&"mutated")
	check(not good(j.begin_scope(f.ctx)),"exact ctx mutated origin rejected")
	f.ctx.set("_source_origin",origin)
	check(remaining(f)==balance,"mutated origin zero owner debit")
	f.ctx.set("_source_token",Token.new())
	check(not good(j.begin_scope(f.ctx)),"exact ctx mutated token rejected")
	f.ctx.set("_source_token",token)
	check(remaining(f)==balance,"mutated token zero owner debit")
	var counterfeit = Parent.new()
	check(not counterfeit.capture([],{},fake),"unissued ctx cold capture rejects")
	reject(f,counterfeit,f.lease,fake,"missing cold authenticated cache")
	counterfeit.ready = true
	counterfeit._captured_context = fake
	counterfeit._open_budget_session()
	check(not good(counterfeit.issue_budget_lease(fake)) and not good(counterfeit.validate_budget_lease_bounded(f.lease,fake)),"forged fields do not manufacture authentic cache")
	var domain = Domain.new()
	var frame:Dictionary = domain.enter_frame(RefCounted.new(),f.ctx)
	check(good(frame),"real private frame fixture")
	if good(frame):
		check(f.cp.reserve_budget_bounded(f.lease,{},f.ctx).reason=="budget_private_frame_unsupported" and not good(create(f)),"public bounded mode explicitly rejects private frame")
		check(good(Domain.leave_frame(frame.frame_marker)),"real private frame exit")
	check(remaining(f)==balance,"private rejection zero parent debit")
	var original_script:Variant = f.ctx.get_script()
	f.ctx.set_script(ReplacedContext)
	f.ctx.set("_source_token",token)
	f.ctx.set("_source_origin",origin)
	ReplacedContext.token_getter_calls = 0
	check(not good(j.begin_scope(f.ctx)) and not good(create(f)),"replaced context script cannot make bounded journal call untrusted getter")
	check(ReplacedContext.token_getter_calls==0,"replaced context getter doing real Source history scan never executes")
	f.ctx.set_script(original_script)
	f.ctx.set("_source_token",token)
	f.ctx.set("_source_origin",origin)
	check(remaining(f)==balance,"replaced context script zero original account debit")
	check(Source.validate_original_context(f.ctx).ok,"restored original source Context script and fields control")
func lifecycle() -> void:
	for action in ["close","success","invalid","budget","generation"]:
		var f:Dictionary = fixture(action)
		var made:Dictionary = create(f)
		check(good(made),action+" bounded factory control")
		if not good(made): continue
		var j:Variant = made.journal
		var scope:Dictionary = j.begin_scope(f.ctx)
		check(good(scope),action+" issued old scope")
		if action=="close": check(good(f.cp.close_budget(f.ctx)),action+" real close")
		elif action=="success": check(f.cp.capture([],{},f.ctx),action+" real successful recapture")
		elif action=="invalid": check(not f.cp.capture([],{},Context.new()),action+" real invalid recapture")
		elif action=="budget":
			f.cp.limits.max_capture_collections = 0
			check(not f.cp.capture([[]],{},f.ctx),action+" real budget recapture refusal")
		else:
			var changed:Dictionary = Source.begin_generation(&"revoke_bounded")
			retained_tokens.append(changed.token)
			check(changed.ok,action+" real generation change")
		var usage:Dictionary = j.usage()
		check(not good(f.cp.validate_budget_lease_bounded(f.lease,f.ctx)),action+" old bounded lease revoked")
		check(not good(create(f)),action+" public bounded factory refuses revoked original session")
		check(not good(j.begin_scope(f.ctx)) and j.usage()==usage and f.trace.calls.is_empty(),action+" old bounded journal revoked zero local/live")
		if scope.has("handle"): check(not good(j.restore(scope.handle,f.ctx)) and not good(j.release(scope.handle,f.ctx)),action+" restore/release cannot revive old scope")
		if action=="success":
			var next:Dictionary = f.cp.issue_budget_lease(f.ctx)
			check(good(next) and good(f.trace.new_bounded_shared_write_journal(f.ctx,LOCAL,f.cp,next.lease,BOUNDS)),"successful recapture new official lease works without reviving old")
	var f:Dictionary = fixture("owner_retirement")
	var old:Variant = f.cp
	var id:int = old.get_instance_id()
	var lease:Variant = f.lease
	var weak:WeakRef = weakref(old)
	f.cp = null
	old = null
	check(weak.get_ref()==null,"owner genuinely freed while issued lease retained")
	var replacement = Parent.new()
	check(replacement.capture([],{},f.ctx),"replacement owner real capture")
	check(not good(replacement.validate_budget_lease_bounded(lease,f.ctx)),"new owner cannot inherit original strong held lease")
	print("OWNER_ID_OBSERVATION ",JSON.stringify({"old":id,"replacement":replacement.get_instance_id(),"actual_reuse":id==replacement.get_instance_id()}))
func atomic_budget() -> void:
	for dim in DIMS:
		var f:Dictionary = fixture("short_"+dim)
		var made:Dictionary = create(f)
		check(good(made),dim+" bounded factory control")
		if not good(made): continue
		var j:Variant = made.journal
		var expected:Dictionary = {"collections":60,"comparisons":108,"values":1200,"objects":1}
		var before:Dictionary = remaining(f)
		check(good(f.cp.reserve_budget(f.lease,{dim:before[dim]-expected[dim]+1},f.ctx)),dim+" true original account one-short")
		before = remaining(f)
		var usage:Dictionary = j.usage()
		var denied:Dictionary = j.begin_scope(f.ctx)
		check(not good(denied) and denied.reason=="budget_exhausted_"+dim and remaining(f)==before and j.usage()==usage and f.trace.calls.is_empty(),dim+" bounded reserve refusal consumed zero local/live/debit")
	var f:Dictionary = fixture("invalid_costs")
	for bad in [null,[],{"x":1},{"values":true},{"objects":1.0},{"values":-1},{"values":9223372036854775807},{"a":0,"b":0,"c":0,"d":0,"e":0}]:
		var before:Dictionary = remaining(f)
		check(not good(f.cp.reserve_budget_bounded(f.lease,bad,f.ctx)) and remaining(f)==before,"malformed/overflow/oversized costs zero debit "+str(bad))
func shared_work() -> void:
	var f:Dictionary = fixture("nested")
	var a:Dictionary = create(f)
	var b:Dictionary = create(f)
	check(good(a) and good(b),"two journals use original account")
	if not good(a) or not good(b): return
	var j:Variant = a.journal
	var k:Variant = b.journal
	var before:Dictionary = remaining(f)
	var outer:Dictionary = j.begin_scope(f.ctx)
	check(good(outer) and debit(before,remaining(f),outer.get("parent_reservation",{})),"outer scope exact four-dimensional original debit")
	var entry:Dictionary = {"value":1}
	check(good(j.apply([{"kind":"append","target":f.trace.calls,"items":[entry]}],f.ctx)) and is_same(f.trace.calls[0],entry),"bounded append exact live identity")
	var inner:Dictionary = j.begin_scope(f.ctx)
	check(good(inner) and good(j.apply([{"kind":"patch","target":entry,"changes":{"value":2}}],f.ctx)) and entry.value==2,"bounded nested real patch")
	if inner.has("handle"):
		before = remaining(f)
		var restored:Dictionary = j.restore(inner.handle,f.ctx)
		check(good(restored) and entry.value==1 and debit(before,remaining(f),restored.get("parent_reservation",{})),"nested restore same account no refund")
	if outer.has("handle"): check(good(j.restore(outer.handle,f.ctx)) and f.trace.calls.is_empty(),"outer original root restored")
	var scope:Dictionary = k.begin_scope(f.ctx)
	before = remaining(f)
	if scope.has("handle"):
		var released:Dictionary = k.release(scope.handle,f.ctx)
		check(good(released) and debit(before,remaining(f),released.get("parent_reservation",{})),"second journal release original debit no refund")
	before = remaining(f)
	var next:Dictionary = f.cp.issue_budget_lease(f.ctx)
	check(good(next) and debit(before,remaining(f),{"objects":1,"values":1}),"new lease same remaining only official issuance fee")
	var active:Dictionary = j.begin_scope(f.ctx)
	before = remaining(f)
	var usage:Dictionary = j.usage()
	var rejected:Dictionary = j.apply([{"kind":"unknown","target":f.trace.calls}],f.ctx)
	check(not good(rejected) and debit(before,remaining(f),rejected.get("parent_reservation",{})) and j.usage()==usage and f.trace.calls.is_empty(),"paid diagnostic refuses no refund no partial write")
	if active.has("handle"): check(good(j.release(active.handle,f.ctx)),"diagnostic bounded release")
	var facade:Dictionary = k.begin_scope(f.ctx)
	var execution:Dictionary = k.try_begin_execution(f.ctx)
	var call:Dictionary = k.try_begin_call({"trigger_time_points":[]},"bounded_probe",[],[],f.ctx)
	check(good(facade) and good(execution) and good(call),"real bounded execution/call public facade")
	if call.has("call_id"): check(good(k.try_end_call(call.call_id,7,"completed",f.ctx)),"real bounded end call")
	if execution.has("execution_id"): check(good(k.try_end_execution(execution.execution_id,f.ctx)),"real bounded end execution")
	if facade.has("handle"): check(good(k.restore(facade.handle,f.ctx)) and f.trace.calls.is_empty(),"real bounded facade identity restoration")
func factory_and_shared_exhaustion() -> void:
	for dim in DIMS:
		var f:Dictionary = fixture("factory_short_"+dim)
		var amount:Dictionary = {"collections":42,"comparisons":102,"values":1104,"objects":1}
		var before:Dictionary = remaining(f)
		check(good(f.cp.reserve_budget(f.lease,{dim:before[dim]-amount[dim]+1},f.ctx)),dim+" factory actual budget one-short")
		before = remaining(f)
		var denied:Dictionary = create(f)
		check(not good(denied) and not denied.has("journal") and remaining(f)==before and f.trace.calls.is_empty(),dim+" factory shortage no journal/copy/live/debit")
	var f:Dictionary = fixture("shared_exhaustion")
	var a:Dictionary = create(f)
	var b:Dictionary = create(f)
	check(good(a) and good(b),"exhaustion two authentic bounded journals")
	if not good(a) or not good(b): return
	var before:Dictionary = remaining(f)
	check(good(f.cp.reserve_budget(f.lease,{"collections":before.collections-120},f.ctx)),"two journals leave two scope fees in original account")
	var outer:Dictionary = a.journal.begin_scope(f.ctx)
	var other:Dictionary = b.journal.begin_scope(f.ctx)
	check(good(outer) and good(other) and remaining(f).collections==0,"two journals consume same last original collections")
	before = remaining(f)
	var usage:Dictionary = b.journal.usage()
	check(not good(b.journal.apply([{"kind":"append","target":f.trace.calls,"items":[9]}],f.ctx)) and remaining(f)==before and b.journal.usage()==usage and f.trace.calls.is_empty(),"second bounded journal no local/live write after shared exhaustion")
	if outer.has("handle"):
		check(not good(a.journal.restore(outer.handle,f.ctx)) and not good(a.journal.release(outer.handle,f.ctx)) and remaining(f)==before,"restore/release insufficient parent balance cannot refund")
func _ready() -> void:
	retained_tokens.append(Source.begin_generation(&"trace_budget_auth_bounded").token)
	var cp = Parent.new()
	check(cp.has_method("validate_budget_lease_bounded") and cp.has_method("reserve_budget_bounded") and ExecutionTrace.new().has_method("new_bounded_shared_write_journal"),"explicit bounded public parent and Trace ABI exists")
	histories()
	credentials()
	lifecycle()
	atomic_budget()
	shared_work()
	factory_and_shared_exhaustion()
	print("RESULT ",JSON.stringify({"suite":"trace-budget-auth-bounded","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
