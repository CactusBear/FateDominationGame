extends Node
const Trace = preload("res://scripts/system/global/execution_trace.gd")
const Parent = preload("res://scripts/match/rule_checkpoint.gd")
const Source = preload("res://scripts/system/session_generation.gd")
const AUTH = {"collections":32,"comparisons":96,"values":1024,"objects":0}
const LOCAL = {"max_rows":512,"max_units":10000000,"max_scopes":32}
var checks:int = 0
var failures:Array = []
var ctx:Variant
func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ",label," ",ok)
	if not ok: failures.append(label)
func good(out:Dictionary) -> bool: return out.get("status")=="COMPLETED"
func bounds(d:int,t:int) -> Dictionary:
	return {"descriptors":d,"slots":3*d+2,"leaf_visits":5*d+8,"leaf_containers":d+1,"stack_slots":t}
func price(b:Dictionary,r:int,kind:String) -> Dictionary:
	var d:int = b.descriptors
	var s:int = b.slots
	var v:int = b.leaf_visits
	var k:int = b.leaf_containers
	var t:int = b.stack_slots
	if kind=="begin_scope" or kind=="release":
		d=0;s=0;v=0;k=0;t=0
	var w:int=2*s+2*d+4
	var c:Dictionary = {"collections":20+8*d+3*t+2*w+s+v,"comparisons":12+v*k+6*v+d*d+d*(d+r)+s*s+2*t*t+4*t,"values":160+32*d+4*w+16*v+16*s+18*t+12*v*k+s*s+4*t*t+8*d*(d+r),"objects":1 if kind=="begin_scope" else 0}
	if kind!="begin_scope" and kind!="release":
		c.comparisons+=6*d+d*t+48*(d+1)
		c.values+=2*d+4*d*t+192*(d+1)
	for key in AUTH: c[key]+=AUTH[key]
	return c
func remaining(f:Dictionary) -> Dictionary:
	return f.cp.validate_budget_lease_bounded(f.lease,ctx).get("remaining",{})
func fixture(b:Dictionary, local_limits:Dictionary = LOCAL) -> Dictionary:
	var cp=Parent.new()
	check(cp.capture([[3]],{},ctx),"original real parent capture")
	var issued:Dictionary=cp.issue_budget_lease(ctx)
	check(good(issued),"original official lease")
	var tr=Trace.new()
	var made:Dictionary=tr.new_bounded_shared_write_journal(ctx,local_limits,cp,issued.get("lease"),b)
	check(good(made),"bounded factory no new allowance")
	var f:Dictionary={"cp":cp,"lease":issued.get("lease"),"trace":tr,"j":made.get("journal"),"bounds":b}
	var scoped:Dictionary=f.j.begin_scope(ctx)
	check(good(scoped),"real scope")
	f["handle"]=scoped.get("handle")
	return f
func reset_observer(f:Dictionary) -> void:
	if f.trace.has_method("revision_cost_reset"): f.trace.call("revision_cost_reset")
func observed(f:Dictionary,label:String,rows:int,legacy:int=0,reverse:bool=false) -> void:
	var stats:Dictionary={}
	if f.trace.has_method("revision_cost_stats"): stats=f.trace.call("revision_cost_stats")
	var d:int=f.bounds.descriptors
	var t:int=f.bounds.stack_slots
	check(stats.is_empty() or (stats.get("root_identity",0)<=6*d and stats.get("active_identity",0)<=d*t and stats.get("markers",0)<=d+1 and stats.get("metadata",0)<=16*(d+1) and stats.get("fields",0)<=32*(d+1)),label+" observed added-work upper bounds")
	if not stats.is_empty():
		check((stats.get("attribution",0)==0 if reverse else stats.get("attribution",0)<=rows) and stats.get("markers",0)==(rows if reverse or legacy==0 else legacy),label+" actual branch counts")
	print("REVISION_OBS ",JSON.stringify({"label":label,"D":d,"T":t,"rows":rows,"legacy":legacy,"reverse":reverse,"stats":stats,"delta":{"collections":0,"comparisons":6*d+d*t+48*(d+1),"values":2*d+4*d*t+192*(d+1),"objects":0}}))
func invoke(f:Dictionary,method:String,args:Array,label:String,rows:int,legacy:int=0) -> Dictionary:
	var before:Dictionary=remaining(f)
	var expected:Dictionary=price(f.bounds,f.j.usage().rows,method)
	reset_observer(f)
	var out:Dictionary=f.j.callv(method,args)
	var after:Dictionary=remaining(f)
	check(good(out),label+" completed")
	var paid:bool=out.get("parent_reservation",{})==expected
	for key in AUTH: paid=paid and before[key]-after[key]==expected[key]
	check(paid,label+" real four-dimensional debit")
	print("REVISION_DEBIT ",JSON.stringify({"operation":label,"before":before,"after":after,"cost":expected,"receipt":out.get("parent_reservation",{})}))
	observed(f,label,rows,legacy,method=="restore")
	return out
func matrix() -> void:
	for pair in [[0,0],[1,0],[1,1],[1,64],[64,1],[12,64],[64,12],[32,32]]:
		var d:int=pair[0]
		var t:int=pair[1]
		var f:Dictionary=fixture(bounds(d,t))
		var descriptors:Array=[]
		var targets:Array=[]
		for i in range(d):
			var target:Dictionary={"x":0}
			targets.append(target)
			descriptors.append({"kind":"patch","target":target,"changes":{"x":1}})
		# Unique active targets occupy the LAST stack positions. D>T additionally
		# exercises unclassified dictionaries; no overlaps evade the true D bound.
		for i in range(maxi(t-d,0)): f.trace.call_stack.append({"filler":i})
		for i in range(mini(d,t)): f.trace.call_stack.append(targets[i])
		var version:int=f.trace.get_meta(Trace.MANAGED_WRITER_META)[0]
		var label:String="matrix D"+str(d)+" T"+str(t)
		invoke(f,"apply",[descriptors,ctx],label+" forward",d)
		var written:bool=true
		for target in targets: written=written and target.x==1
		check(written,label+" every real target written")
		check(f.trace.get_meta(Trace.MANAGED_WRITER_META)[0]==version+mini(d,t),label+" only bounded active owners advance")
		check((f.trace.managed_writer_snapshot().status=="UNSUPPORTED")== (d>t),label+" unclassified true writes fault not invented ownership")
		invoke(f,"restore",[f.handle,ctx],label+" reverse",d)
		var restored:bool=true
		for target in targets: restored=restored and target.x==0
		check(restored and f.j.usage().rows==0,label+" all inverse contents restored")
		check(f.trace.get_meta(Trace.MANAGED_WRITER_META)[0]==version+mini(d,t)*(1 if d>t else 2),label+" restore preserves prior latched-fault contract")
func roots_and_noops() -> void:
	var f:Dictionary=fixture(bounds(6,0))
	var roots:Array=[f.trace.calls,f.trace._counters,f.trace.execution_stack,f.trace.call_stack,f.trace.loop_stack,f.trace.loop_depths]
	var descriptors:Array=[]
	for i in range(6): descriptors.append({"kind":"root","slot":Trace.WriteJournal.ROOTS[i],"value":{} if i==1 else []})
	invoke(f,"apply",[descriptors,ctx],"fixed root replacements",6)
	check(f.trace.get_meta(Trace.MANAGED_WRITER_META)[0]==6,"all fixed root swaps marked")
	invoke(f,"restore",[f.handle,ctx],"fixed root reverse",6)
	check(is_same(f.trace.calls,roots[0]) and is_same(f.trace._counters,roots[1]) and is_same(f.trace.call_stack,roots[3]),"root reverse exact identity")
	for descriptor in [{"kind":"append","target":[],"items":[]},{"kind":"trim","target":[],"index":0,"count":0},{"kind":"patch","target":{},"changes":{}},{"kind":"contents","target":[],"value":[]}]:
		f=fixture(bounds(1,0))
		var snap:Dictionary=f.trace.managed_writer_snapshot()
		invoke(f,"apply",[[descriptor],ctx],"noop "+descriptor.kind,1)
		invoke(f,"restore",[f.handle,ctx],"noop reverse "+descriptor.kind,1)
		check(f.trace.managed_writer_matches(snap),"no-op does not fault or change version "+descriptor.kind)
	f=fixture(bounds(1,0))
	var snap:Dictionary=f.trace.managed_writer_snapshot()
	invoke(f,"apply",[[{"kind":"root","slot":"calls","value":f.trace.calls}],ctx],"same root noop",1)
	invoke(f,"restore",[f.handle,ctx],"same root noop reverse",1)
	check(f.trace.managed_writer_matches(snap),"same root noop remains matched")
	# Corrupt metadata never bypasses the budget gate; successful real raw writes
	# still execute and preserve the previous invalid-observation contract.
	f=fixture(bounds(1,0))
	f.trace.set_meta(Trace.MANAGED_WRITER_META,["bad"])
	invoke(f,"apply",[[{"kind":"append","target":f.trace.calls,"items":[7]}],ctx],"damaged metadata forward",1)
	invoke(f,"restore",[f.handle,ctx],"damaged metadata reverse",1)
	check(f.trace.calls.is_empty() and f.trace.managed_writer_snapshot().status=="UNSUPPORTED","damaged backing never silently drops real write")
	f=fixture(bounds(1,64),{"max_rows":512,"max_units":64,"max_scopes":32})
	var last:Dictionary={"x":0}
	for i in range(63): f.trace.call_stack.append({"filler":i})
	f.trace.call_stack.append(last)
	invoke(f,"apply",[[{"kind":"patch","target":last,"changes":{"x":1}}],ctx],"shared original per-scan local ceiling",1)
	check(last.x==1 and f.trace.get_meta(Trace.MANAGED_WRITER_META)[0]==0 and f.trace.managed_writer_snapshot().status=="UNSUPPORTED","shared local ceiling preserves original unclassified fault contract")
func shortages() -> void:
	for method in ["apply","restore","begin_scope"]:
		for dim in Parent.BUDGET_DIMENSIONS:
			if dim=="objects" and method!="begin_scope": continue # exact zero object work, not a fake negative balance
			var f:Dictionary=fixture(bounds(1,1))
			var target:Array=f.trace.loop_stack
			target.append(4)
			if method=="restore": check(good(f.j.apply([{"kind":"patch","target":target,"index":0,"value":9}],ctx)),"short restore real recorded forward")
			var cost:Dictionary=price(f.bounds,f.j.usage().rows,method)
			var before:Dictionary=remaining(f)
			check(good(f.cp.reserve_budget(f.lease,{dim:before[dim]-cost[dim]+1},ctx)),"short "+method+" "+dim+" exact one-short burn")
			before=remaining(f)
			var usage:Dictionary=f.j.usage()
			var version:Variant=f.trace.get_meta(Trace.MANAGED_WRITER_META).duplicate()
			var fault:Variant=f.trace.get_meta(Trace.MANAGED_WRITER_FAULT)
			var old:Variant=target.duplicate()
			reset_observer(f)
			var out:Dictionary
			if method=="apply": out=f.j.apply([{"kind":"append","target":target,"items":[8]}],ctx)
			elif method=="restore": out=f.j.restore(f.handle,ctx)
			else: out=f.j.begin_scope(ctx)
			print("REVISION_SHORT ",JSON.stringify({"operation":method,"dimension":dim,"expected_cost":cost,"result":out,"live_before":old,"live_after":target,"usage_before":usage,"usage_after":f.j.usage(),"parent_before":before,"parent_after":remaining(f),"version_before":version,"version_after":f.trace.get_meta(Trace.MANAGED_WRITER_META),"fault_before":fault,"fault_after":f.trace.get_meta(Trace.MANAGED_WRITER_FAULT)}))
			check(not good(out) and out.get("reason")=="budget_exhausted_"+dim,"TARGET "+method+" one-short "+dim+" rejects real operation")
			check(target==old and f.j.usage()==usage and remaining(f)==before and f.trace.get_meta(Trace.MANAGED_WRITER_META)==version and f.trace.get_meta(Trace.MANAGED_WRITER_FAULT)==fault,"TARGET "+method+" one-short "+dim+" zero live records local version fault debit")
			if f.trace.has_method("revision_cost_stats"):
				var stats:Dictionary=f.trace.call("revision_cost_stats")
				check(stats.attribution==0 and stats.markers==0 and stats.metadata==0,"TARGET shortage before any added work "+method+dim)
	# An unclassified/nested target must not fault merely because a budget failed.
	var f:Dictionary=fixture(bounds(1,1))
	var nested:Array=[1]
	f.trace.calls.append({"nested":nested})
	var snap:Dictionary=f.trace.managed_writer_snapshot()
	var cost:Dictionary=price(f.bounds,0,"apply")
	var before:Dictionary=remaining(f)
	check(good(f.cp.reserve_budget(f.lease,{"comparisons":before.comparisons-cost.comparisons+1},ctx)),"nested shortage exact burn")
	var usage:Dictionary=f.j.usage()
	check(not good(f.j.apply([{"kind":"append","target":nested,"items":[2]}],ctx)) and nested==[1] and f.j.usage()==usage and f.trace.managed_writer_matches(snap),"nested shortage never prematurely downgrades observation")
	f=fixture(bounds(1,0))
	f.trace.set_meta(Trace.MANAGED_WRITER_META,["bad"])
	cost=price(f.bounds,0,"apply")
	before=remaining(f)
	check(good(f.cp.reserve_budget(f.lease,{"values":before.values-cost.values+1},ctx)),"damaged metadata shortage exact burn")
	usage=f.j.usage()
	reset_observer(f)
	check(not good(f.j.apply([{"kind":"append","target":f.trace.calls,"items":[1]}],ctx)) and f.trace.calls.is_empty() and f.j.usage()==usage and f.trace.get_meta(Trace.MANAGED_WRITER_META)==["bad"] and f.trace.get_meta(Trace.MANAGED_WRITER_FAULT)==false,"damaged metadata shortage cannot latch a new fault before payment")
func legacy_and_local() -> void:
	var b:Dictionary={"descriptors":24,"slots":48,"leaf_visits":128,"leaf_containers":16,"stack_slots":8}
	var f:Dictionary=fixture(b)
	invoke(f,"try_begin_execution",[ctx],"legacy begin execution",3,1)
	invoke(f,"try_begin_call",[{},"one",[],[],ctx],"legacy begin call",3,1)
	invoke(f,"try_begin_call",[{},"two",[],[],ctx],"legacy second call",3,1)
	invoke(f,"try_end_call",[1,7,"completed",ctx],"legacy active dangling",3,1)
	invoke(f,"try_end_execution",[1,ctx],"legacy end execution",4,1)
	invoke(f,"try_reset",[ctx],"legacy reset",6,1)
	var rows:int=f.j.usage().rows
	invoke(f,"restore",[f.handle,ctx],"legacy all reverse",rows)
	check(f.trace.calls.is_empty() and f.trace.next_call_id==0,"legacy real six-root reverse")
	# Local units remain the original cumulative integer ABI, not native CPU gas.
	# Calibrate old preparation using a root target (no active scan), then prove
	# two successful active scans debit 2*T, not a single reused remaining T.
	var tr=Trace.new()
	var active:Array=[]
	for i in range(8): active.append({"x":0})
	tr.call_stack.assign(active)
	var made:Dictionary=tr.new_write_journal(ctx,LOCAL)
	check(good(made),"local original explicit ABI")
	var j:Variant=made.journal
	var h:Variant=j.begin_scope(ctx).handle
	var out:Dictionary=j.apply([{"kind":"patch","target":active[6],"changes":{"x":1}},{"kind":"patch","target":active[7],"changes":{"x":1}}],ctx)
	check(good(out),"local real two-row active write")
	var empty_trace=Trace.new()
	var empty_j:Variant=empty_trace.new_write_journal(ctx,LOCAL).journal
	empty_j.begin_scope(ctx)
	var control_targets:Array=[{"x":0},{"x":0}]
	var baseline:Dictionary=empty_j.apply([{"kind":"patch","target":control_targets[0],"changes":{"x":1}},{"kind":"patch","target":control_targets[1],"changes":{"x":1}}],ctx)
	check(good(baseline) and out.cost-baseline.cost==16,"local two candidate scans debit exactly two T in cumulative ABI")
	var tight_trace=Trace.new()
	var tight_targets:Array=[]
	for i in range(8): tight_targets.append({"x":0})
	tight_trace.call_stack.assign(tight_targets)
	var tight:Variant=tight_trace.new_write_journal(ctx,{"max_rows":512,"max_units":3+baseline.cost+15,"max_scopes":32}).journal
	tight.begin_scope(ctx)
	var tight_out:Dictionary=tight.apply([{"kind":"patch","target":tight_targets[6],"changes":{"x":1}},{"kind":"patch","target":tight_targets[7],"changes":{"x":1}}],ctx)
	check(good(tight_out) and tight_out.cost==baseline.cost+8 and tight_targets[6].x==1 and tight_targets[7].x==1,"local one-short aggregate skips second unpaid scan without suppressing business writes")
	check(tight_trace.get_meta(Trace.MANAGED_WRITER_META)[0]==1 and tight_trace.managed_writer_snapshot().status=="UNSUPPORTED","local outside remaining bound retains unclassified fault contract")
	print("LOCAL_CLASSIFICATION ",JSON.stringify({"T":8,"rows":2,"cost":out.get("cost"),"base":baseline.cost,"tight_cost":tight_out.get("cost"),"usage":j.usage()}))
	check(good(j.restore(h,ctx)) and active[6].x==0 and active[7].x==0,"local reverse original ABI")
func _ready() -> void:
	ctx=Source.derive_context(Source.begin_generation(&"trace_revision_cost").token,&"original_revision_cost").context
	if "sensitivity" in OS.get_cmdline_user_args(): shortages()
	else:
		matrix()
		roots_and_noops()
		shortages()
		legacy_and_local()
	print("RESULT ",JSON.stringify({"suite":"trace-revision-cost","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
