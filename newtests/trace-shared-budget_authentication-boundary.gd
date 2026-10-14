extends Node
const Parent = preload("res://scripts/match/rule_checkpoint.gd")
const Source = preload("res://scripts/system/session_generation.gd")
var checks:int = 0
var failures:Array = []
func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ",label," ",ok)
	if not ok: failures.append(label)
func _ready() -> void:
	var generation:Dictionary = Source.begin_generation(&"trace_budget_auth_boundary")
	var retained:Array = []
	for i in range(100): retained.append(Source.derive_context(generation.token,StringName("retained_auth_"+str(i))).context)
	var ctx:Variant = retained.back()
	var cp = Parent.new()
	cp.limits.max_capture_comparisons = 2
	var alias:Array = [1]
	check(cp.capture([alias,alias],{},ctx),"real capture for authentication boundary")
	var lease:Variant = cp.issue_budget_lease(ctx).get("lease")
	check(cp.reserve_budget(lease,{"comparisons":1},ctx).status=="COMPLETED","real debit comparison remainder to zero")
	var before:Dictionary = cp.budget_remaining(ctx).remaining
	check(before.comparisons==0,"comparison balance genuinely zero")
	var validation:Dictionary = cp.validate_budget_lease(lease,ctx)
	var zero:Dictionary = cp.reserve_budget(lease,{},ctx)
	check(validation.status=="COMPLETED" and zero.status=="COMPLETED" and cp.budget_remaining(ctx).remaining==before,"parent authentication control scans remain outside charged child work")
	var diagnostic:Dictionary = Source.lifecycle_diagnostics()
	check(diagnostic.contexts>=100 and is_same(Source._contexts.back().handle.get_ref(),ctx),"original exact context last in retained issuance table")
	print("AUTH_BOOTSTRAP_BOUNDARY ",JSON.stringify({"contexts":diagnostic.contexts,"issued_tokens":diagnostic.issued_tokens,"comparisons_remaining":before.comparisons,"original_parent_sha":"a4a580dbca699c1e1128f241efa31c5ad6637efc934988bf94a9a24f82b874ee","closure_status":"UNSUPPORTED","meaning":"parent authenticates through linear source table before its own debit; not a child-work guarantee"}))
	print("RESULT ",JSON.stringify({"suite":"trace-shared-budget-authentication-boundary","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
