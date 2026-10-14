extends Node
const Trace = preload("res://scripts/system/global/execution_trace.gd")
const Parent = preload("res://scripts/match/rule_checkpoint.gd")
const Source = preload("res://scripts/system/session_generation.gd")
const Context = preload("res://scripts/system/session_context.gd")
const LIMITS = {"max_rows":512,"max_units":1000000,"max_scopes":32}
const BOUNDS = {"descriptors":24,"slots":48,"leaf_visits":128,"leaf_containers":16,"stack_slots":8}
var checks:int = 0
var failures:Array = []
var ctx:Variant
class FakeOwner extends RefCounted:
	func validate_budget_lease(_lease, _context): return {"status":"COMPLETED"}
	func reserve_budget(_lease, _costs, _context): return {"status":"COMPLETED"}
func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ",label," ",ok)
	if not ok: failures.append(label)
func yes(result:Dictionary) -> bool: return result.get("status", "") == "COMPLETED"
func rem(cp:RefCounted) -> Dictionary: return cp.budget_remaining(ctx).get("remaining", {})
func deducted(before:Dictionary, after:Dictionary, cost:Dictionary) -> bool:
	if before.size() != 4 or after.size() != 4: return false
	for key in Parent.BUDGET_DIMENSIONS:
		if before[key] - after[key] != cost.get(key, 0): return false
	return true
func parent() -> RefCounted:
	var cp = Parent.new()
	var aliased:Array = [5]
	var rng = RandomNumberGenerator.new()
	check(cp.capture([aliased,aliased,rng],{},ctx), "real nonempty original capture")
	check(cp._collections.size()==1 and cp._comparisons==1 and cp._values==4 and cp._objects.size()==1,"real capture consumed four counters")
	return cp
func reservation(bounds:Dictionary, rows:int, scope:bool = false, revision:bool = true) -> Dictionary:
	var d:int = bounds.descriptors
	var s:int = bounds.slots
	var v:int = bounds.leaf_visits
	var k:int = bounds.leaf_containers
	var t:int = bounds.stack_slots
	var w:int = 2*s+2*d+4
	return {"collections":20+8*d+3*t+2*w+s+v,"comparisons":12+v*k+6*v+d*d+d*(d+rows)+s*s+2*t*t+4*t+(6*d+d*t+48*(d+1) if revision else 0),"values":160+32*d+4*w+16*v+16*s+18*t+12*v*k+s*s+4*t*t+8*d*(d+rows)+(2*d+4*d*t+192*(d+1) if revision else 0),"objects":1 if scope else 0}
func build(cp:RefCounted, trace:RefCounted, bounds:Dictionary = BOUNDS) -> Dictionary:
	var issued:Dictionary = cp.issue_budget_lease(ctx)
	check(yes(issued),"real original parent issued opaque ticket")
	var before:Dictionary = rem(cp)
	var auth:Dictionary = Source.lifecycle_diagnostics()
	var factory_cost:Dictionary = {"collections":10,"comparisons":auth.contexts+auth.issued_tokens+6,"values":80+4*(auth.contexts+auth.issued_tokens),"objects":1}
	var made:Dictionary = trace.new_shared_write_journal(ctx,LIMITS,cp,issued.get("lease"),bounds)
	check(yes(made),"explicit shared factory succeeds")
	check(made.get("parent_reservation",{})==factory_cost and deducted(before,rem(cp),factory_cost),"factory exact four dimension reservation")
	print("SHARED_DEBIT ",JSON.stringify({"operation":"factory","cost":factory_cost,"before":before,"after":rem(cp)}))
	return {"journal":made.get("journal"),"lease":issued.get("lease")}
func op(cp:RefCounted, journal:RefCounted, method:String, args:Array, label:String) -> Dictionary:
	var before:Dictionary = rem(cp)
	var effective:Dictionary = BOUNDS.duplicate()
	if method=="begin_scope" or method=="release":
		for key in effective: effective[key] = 0
	var expected:Dictionary = reservation(effective,journal.usage().rows,method=="begin_scope",method!="begin_scope" and method!="release")
	var result:Dictionary = journal.callv(method,args)
	check(yes(result),label+" succeeds")
	check(result.get("parent_reservation",{})==expected and deducted(before,rem(cp),expected),label+" exact four dimension debit")
	print("SHARED_DEBIT ",JSON.stringify({"operation":label,"cost":expected,"before":before,"after":rem(cp)}))
	return result
func _ready() -> void:
	var gen:Dictionary = Source.begin_generation(&"trace_shared_budget")
	ctx = Source.derive_context(gen.token,&"trace_shared_original").context
	var no_capture = Parent.new()
	var trace = Trace.new()
	check(not yes(trace.new_shared_write_journal(ctx,LIMITS,no_capture,Parent.BudgetLease.new(),BOUNDS)),"no capture cannot launder history budget")
	var cp = parent()
	var a:Dictionary = build(cp,trace)
	var j:RefCounted = a.journal
	check(not Parent.Ids.script_fields(j).has("trace_shared_budget"),"budget handles graph external metadata")
	var second_trace = Trace.new()
	var b:Dictionary = build(cp,second_trace)
	var j2:RefCounted = b.journal
	check(cp.validate_budget_lease(a.lease,ctx).remaining == cp.validate_budget_lease(b.lease,ctx).remaining,"two journals original common account")
	var outer:Variant = op(cp,j,"begin_scope",[ctx],"outer scope").get("handle")
	var target:Array = [1]
	var dict:Dictionary = {"v":2}
	op(cp,j,"apply",[[{"kind":"append","target":target,"items":[3]},{"kind":"patch","target":dict,"changes":{"v":4}}],ctx],"compound write")
	check(target==[1,3] and dict.v==4,"compound real writes installed")
	var inner:Variant = op(cp,j,"begin_scope",[ctx],"nested scope").get("handle")
	op(cp,j,"apply",[[{"kind":"patch","target":target,"index":0,"value":8}],ctx],"nested patch")
	var before_release:Dictionary = rem(cp)
	op(cp,j,"release",[inner,ctx],"nested release")
	check(rem(cp).values < before_release.values,"inner release never refunds parent")
	op(cp,j,"restore",[outer,ctx],"outer reverse")
	check(target==[1] and dict.v==2,"released inner retained original inverse")
	var h2:Variant = op(cp,j2,"begin_scope",[ctx],"second journal scope").get("handle")
	var leaf:Array = [7]
	var cycle:Array = []
	cycle.append(cycle)
	var aliased:Array = [leaf,leaf,cycle]
	op(cp,j2,"apply",[[{"kind":"patch","target":aliased,"index":0,"value":leaf}],ctx],"alias cycle patch")
	op(cp,j2,"restore",[h2,ctx],"alias reverse")
	check(is_same(aliased[0],leaf) and is_same(aliased[1],leaf) and is_same(cycle[0],cycle),"alias cycle exact original identity")
	cycle.clear()
	# Real legacy wrappers: executing nested/dangling patches and loop cleanup.
	var h:Variant = op(cp,j,"begin_scope",[ctx],"legacy scope").get("handle")
	var eid:int = op(cp,j,"try_begin_execution",[ctx],"execution begin").get("execution_id",-1)
	op(cp,j,"try_push_loop",[4,ctx],"loop push")
	var c:int = op(cp,j,"try_begin_call",[{"round":1},"outer",[1],[2],ctx],"call begin").get("call_id",-1)
	op(cp,j,"try_begin_call",[{},"dangling",[],[],ctx],"dangling call")
	op(cp,j,"try_end_call",[c,9,"completed",ctx],"active and dangling patch")
	check(trace.calls.size()==2 and trace.calls[0].return_value==9 and trace.calls[1].status=="aborted","legacy actual active patch")
	op(cp,j,"try_pop_loop",[ctx],"loop pop")
	op(cp,j,"try_end_execution",[eid,ctx],"execution end")
	op(cp,j,"restore",[h,ctx],"legacy reverse")
	check(trace.calls.is_empty() and trace.call_stack.is_empty() and trace.next_call_id==0 and trace.next_execution_id==0,"all real wrappers restore original six roots")
	var active_scope:Variant = op(cp,j,"begin_scope",[ctx],"active execution cursor").get("handle")
	var active_eid:int = op(cp,j,"try_begin_execution",[ctx],"active execution start").get("execution_id",-1)
	op(cp,j,"try_begin_call",[{},"running-a",[],[],ctx],"active call a")
	op(cp,j,"try_begin_call",[{},"running-b",[],[],ctx],"active call b")
	op(cp,j,"try_end_execution",[active_eid,ctx],"execution abort patches")
	check(trace.calls.size()==2 and trace.calls[0].status=="aborted" and trace.calls[1].status=="aborted","end execution real active patches")
	op(cp,j,"restore",[active_scope,ctx],"active execution inverse")
	check(trace.calls.is_empty(),"active execution retained original history")
	var nesting:Variant = op(cp,j,"begin_scope",[ctx],"inner restore outer").get("handle")
	var nested_restore:Variant = op(cp,j,"begin_scope",[ctx],"inner restore cursor").get("handle")
	op(cp,j,"try_push_loop",[7,ctx],"inner restore write")
	var inner_spent:Dictionary = rem(cp)
	op(cp,j,"restore",[nested_restore,ctx],"inner restore")
	check(trace.loop_stack.is_empty() and rem(cp).values < inner_spent.values,"inner restore never refunds account")
	op(cp,j,"release",[nesting,ctx],"outer release after inner restore")
	var new_ticket_before:Dictionary = rem(cp)
	var new_ticket:Dictionary = cp.issue_budget_lease(ctx)
	check(yes(new_ticket) and rem(cp).values==new_ticket_before.values-1 and rem(cp).objects==new_ticket_before.objects-1 and rem(cp).collections==new_ticket_before.collections,"another legal ticket only remaining not full")
	# Two actual journal calls, not only a direct reserve, exhaust one original account.
	var common = Parent.new()
	common.limits.max_capture_collections = 180
	check(common.capture([[1]],{},ctx),"small declared parent budget capture")
	var common_a:Dictionary = build(common,Trace.new())
	var common_b:Dictionary = build(common,Trace.new())
	var successes:int = 0
	for i in range(10):
		var chosen:RefCounted = common_a.journal if i%2==0 else common_b.journal
		var scope:Dictionary = chosen.begin_scope(ctx)
		if not yes(scope): break
		successes += 1
	check(successes>=2 and successes<10,"two real journals alternating shared exhaustion")
	var common_live:Array = [9]
	var common_usage:Dictionary = common_a.journal.usage()
	check(not yes(common_a.journal.apply([{"kind":"append","target":common_live,"items":[10]}],ctx)),"other journal exhausted original common budget")
	check(common_live==[9] and common_a.journal.usage()==common_usage,"alternating exhaustion no live records half write")
	# Exact parent shortage even though local units still suffice. Real parent burn.
	var empty:Variant = op(cp,j,"begin_scope",[ctx],"exhaustion cursor").get("handle")
	var before_usage:Dictionary = j.usage()
	var balance:Dictionary = rem(cp)
	check(yes(cp.reserve_budget(b.lease,{"values":balance.values},ctx)),"second journal lease consumes first account to exhaustion")
	var untouched:Array = [0]
	var rejected:Dictionary = j.apply([{"kind":"append","target":untouched,"items":[1]}],ctx)
	check(not yes(rejected),"shared shortage refuses with local units sufficient")
	check(untouched==[0] and j.usage()==before_usage,"refused consumption gate zero business records local charge")
	check(rem(cp).values==0,"child must not reissue full allowance")
	check(not yes(j2.begin_scope(ctx)),"second journal sees same exhausted parent")
	check(not yes(cp.issue_budget_lease(ctx)),"new ticket not full allowance")
	# Different parent and fake tickets/context owners rejected.
	var other = parent()
	var original_lease:Variant = other.issue_budget_lease(ctx).lease
	check(not yes(trace.new_shared_write_journal(ctx,LIMITS,other,a.lease,BOUNDS)),"cross parent lease rejected")
	check(not yes(trace.new_shared_write_journal(ctx,LIMITS,FakeOwner.new(),original_lease,BOUNDS)),"same shape owner rejected not ducktyped")
	for fake in [Parent.BudgetLease.new(),RefCounted.new(),weakref(original_lease),{"lease":original_lease}]:
		check(not yes(trace.new_shared_write_journal(ctx,LIMITS,other,fake,BOUNDS)),"forged opaque lease rejected")
	var other_ctx:Variant = Source.derive_context(gen.token,&"another_valid_original").context
	check(not yes(trace.new_shared_write_journal(other_ctx,LIMITS,other,original_lease,BOUNDS)),"other legal exact context rejected")
	check(not yes(trace.new_shared_write_journal(Context.new(gen.token,&"trace_shared_original"),LIMITS,other,original_lease,BOUNDS)),"same shape source rejected")
	# Per dimension: after construction, short just one reserve dimension.
	for dimension in Parent.BUDGET_DIMENSIONS:
		var short_parent = parent()
		var t = Trace.new()
		var bound:Dictionary = build(short_parent,t)
		var sj:RefCounted = bound.journal
		var local_before:Dictionary = sj.usage()
		var consume:Dictionary = {}
		consume[dimension] = rem(short_parent)[dimension]
		check(yes(short_parent.reserve_budget(bound.lease,consume,ctx)),"real burn "+dimension)
		var remaining_before:Dictionary = rem(short_parent)
		check(not yes(sj.begin_scope(ctx)),"short "+dimension+" refuses entire reservation")
		check(rem(short_parent)==remaining_before and sj.usage()==local_before and t.calls.is_empty(),"short "+dimension+" single parent failure zero debit live records")
	# Explicit deep bounds fail after paid preparation: parent charged, local zero.
	var deep_parent = parent()
	var low:Dictionary = BOUNDS.duplicate()
	low.leaf_visits = 4
	low.leaf_containers = 2
	var deep:Dictionary = build(deep_parent,Trace.new(),low)
	var dj:RefCounted = deep.journal
	check(yes(dj.begin_scope(ctx)),"deep guard cursor")
	var deep_live:Array = [5]
	var deep_usage:Dictionary = dj.usage()
	var deep_before:Dictionary = rem(deep_parent)
	var deep_fail:Dictionary = dj.apply([{"kind":"append","target":deep_live,"items":[[[[9]]]]}],ctx)
	check(not yes(deep_fail) and deep_live==[5] and dj.usage()==deep_usage,"deep leaf bound no live records half write")
	check(deducted(deep_before,rem(deep_parent),deep_fail.get("parent_reservation",{})) and rem(deep_parent).values < deep_before.values,"failed diagnosis paid parent no refund")
	# Shape refusal is before the first reverse write, even with two recorded targets.
	var shape_parent = parent()
	var shape:Dictionary = build(shape_parent,Trace.new())
	var shape_j:RefCounted = shape.journal
	var shape_h:Variant = op(shape_parent,shape_j,"begin_scope",[ctx],"shape cursor").get("handle")
	var shape_a:Array = [1]
	var shape_d:Dictionary = {"v":2}
	op(shape_parent,shape_j,"apply",[[{"kind":"append","target":shape_a,"items":[3]},{"kind":"patch","target":shape_d,"changes":{"v":4}}],ctx],"shape compound")
	shape_a.append(99)
	var shape_before:Dictionary = shape_j.usage()
	var shape_failed:Dictionary = shape_j.restore(shape_h,ctx)
	check(not yes(shape_failed) and shape_a==[1,3,99] and shape_d.v==4 and shape_j.usage()==shape_before,"reverse prevalidation zero first business write records local ledger")
	for key in ["descriptors","slots","leaf_containers","stack_slots"]:
		var bounds_parent = parent()
		var bounds:Dictionary = BOUNDS.duplicate()
		bounds[key] = 0
		var bounded_trace = Trace.new()
		var bounded:Dictionary = build(bounds_parent,bounded_trace,bounds)
		var bounded_j:RefCounted = bounded.journal
		check(yes(bounded_j.begin_scope(ctx)),key+" bounded scope")
		var bounded_live:Array = [1]
		if key=="stack_slots": bounded_trace.execution_stack.append(77)
		var local_before:Dictionary = bounded_j.usage()
		var result:Dictionary = bounded_j.try_begin_execution(ctx) if key=="stack_slots" else bounded_j.apply([{"kind":"append","target":bounded_live,"items":[2]}],ctx)
		check(not yes(result) and bounded_live==[1] and bounded_j.usage()==local_before,key+" explicit work bound refuses before business batch")
	# Lifecycle: old journals fail after each genuine parent revocation path.
	for mode in ["close","capture","failed_capture"]:
		var life_parent = parent()
		var old:Dictionary = build(life_parent,Trace.new())
		var lj:RefCounted = old.journal
		check(yes(lj.begin_scope(ctx)),mode+" cursor")
		if mode=="close": check(yes(life_parent.close_budget(ctx)),"real close")
		elif mode=="capture": check(life_parent.capture([[2]],{},ctx),"real successful recapture")
		else: check(not life_parent.capture([],{},null),"real failed recapture")
		var local_before:Dictionary = lj.usage()
		var live:Array = [1]
		check(not yes(lj.apply([{"kind":"append","target":live,"items":[2]}],ctx)),mode+" old journal writes revoked")
		check(live==[1] and lj.usage()==local_before,mode+" zero business write")
	var generation_parent = parent()
	var old:Dictionary = build(generation_parent,Trace.new())
	check(yes(old.journal.begin_scope(ctx)),"old generation cursor")
	Source.begin_generation(&"trace_shared_next")
	check(not yes(old.journal.try_push_loop(1,ctx)),"generation old journal write rejected")
	print("SHARED_ACCOUNT ",JSON.stringify({"exhausted_parent":balance,"deep_paid":deep_fail.get("parent_reservation",{}),"mode":"explicit_upper_bound_not_local_units"}))
	print("RESULT ",JSON.stringify({"suite":"trace-shared-budget","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
