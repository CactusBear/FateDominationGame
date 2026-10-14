extends Node
const Checkpoint = preload("res://scripts/match/rule_checkpoint.gd")
const Generation = preload("res://scripts/system/session_generation.gd")
const Context = preload("res://scripts/system/session_context.gd")
var checks:int = 0
var failures:Array = []
var context:Variant
class Holder:
	extends RefCounted
	var ticket:Variant
	var items:Array = [7]
func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)
func completed(result:Dictionary) -> bool:
	return result.status == "COMPLETED"
func small() -> RefCounted:
	var cp = Checkpoint.new()
	cp.limits.max_capture_collections = 100
	cp.limits.max_capture_comparisons = 100
	cp.max_capture_values = 100
	cp.max_capture_objects = 100
	return cp
func remaining(cp:RefCounted) -> Dictionary:
	var result:Dictionary = cp.budget_remaining(context)
	return result.get("remaining", {})
func rejects_unchanged(cp:RefCounted, lease:Variant, costs:Variant, label:String) -> void:
	var before:Dictionary = remaining(cp)
	var caller:Array = []
	var result:Dictionary = cp.reserve_budget(lease, costs, context)
	if completed(result): caller.append("write")
	check(not completed(result), label + " refuses")
	check(remaining(cp) == before and caller.is_empty(), label + " atomic zero caller write")
func _ready() -> void:
	var gen:Dictionary = Generation.begin_generation(&"budget_lease_probe")
	context = Generation.derive_context(gen.token, &"budget_lease_original").context
	var cp = small()
	check(not completed(cp.issue_budget_lease(context)), "uncaptured cannot issue")
	var alias:Array = [5]
	var rng = RandomNumberGenerator.new()
	check(cp.capture([alias, alias, rng], {}, context), "real capture success")
	check(cp._collections.size() == 1 and cp._comparisons == 1 and cp._values == 4 and cp._objects.size() == 1, "real four capture counters")
	check(remaining(cp) == {"collections":99,"comparisons":99,"values":96,"objects":99}, "exact remaining after real capture")
	var leak:Dictionary = remaining(cp)
	leak.values = 999999
	check(remaining(cp).values == 96, "query cannot mutate account")
	var issued:Dictionary = cp.issue_budget_lease(context)
	check(completed(issued), "legal original source issue")
	var lease:Variant = issued.get("lease")
	check(completed(cp.validate_budget_lease(lease, context)), "legal original source validates")
	check(remaining(cp) == {"collections":99,"comparisons":99,"values":95,"objects":98}, "lease own bookkeeping charged")
	var nested:Dictionary = cp.issue_budget_lease(context)
	var inner:Variant = nested.get("lease")
	check(completed(nested) and not is_same(inner, lease), "nested separate opaque handle same account")
	check(completed(cp.reserve_budget(lease, {"collections":2,"comparisons":3,"values":4,"objects":5}, context)), "outer compound reserve")
	check(remaining(cp) == {"collections":97,"comparisons":96,"values":90,"objects":92}, "shared debit exact")
	check(cp.validate_budget_lease(inner, context).get("remaining", {}) == remaining(cp), "multiple leases share one account")
	check(completed(cp.reserve_budget(inner, {"collections":7,"values":8}, context)), "nested reserve original remaining")
	check(remaining(cp) == {"collections":90,"comparisons":96,"values":82,"objects":92}, "nested conservation no full meter")
	for dim in Checkpoint.BUDGET_DIMENSIONS:
		var bad:Dictionary = {"collections":1,"comparisons":1,"values":1,"objects":1}
		bad[dim] = remaining(cp)[dim] + 1
		rejects_unchanged(cp, lease, bad, "short one " + dim)
	for bad in [{"unknown":1},{"collections":1,"unknown":1},{"collections":1,"values":-1},{"collections":1,"objects":true},{"values":-1},{"values":-9223372036854775807 - 1},{"objects":true},{"values":1.0},{"values":"1"},{"values":null},{"values":9223372036854775807},{"values":9223372036854775808.0},{1:0},{&"values":1},[],null]:
		rejects_unchanged(cp, lease, bad, "malformed " + str(bad))
	var zero_before:Dictionary = remaining(cp)
	check(completed(cp.reserve_budget(lease, {}, context)) and remaining(cp) == zero_before, "empty costs legal zero debit")
	check(completed(cp.reserve_budget(lease, {"objects":0}, context)) and remaining(cp) == zero_before, "explicit zero cost")
	var other = small()
	check(other.capture([], {}, context), "other owner real capture")
	check(not completed(other.reserve_budget(lease, {}, context)), "cross owner rejected")
	var fake_context = Context.new(gen.token, &"budget_lease_original")
	check(not completed(cp.reserve_budget(lease, {}, fake_context)), "same shaped context rejected")
	var other_context:Variant = Generation.derive_context(gen.token, &"other_valid").context
	check(not completed(cp.reserve_budget(lease, {}, other_context)), "different valid source identity rejected")
	for fake in [Checkpoint.BudgetLease.new(), RefCounted.new(), {"lease":lease}, weakref(lease), null, 1]:
		check(not completed(cp.reserve_budget(fake, {}, context)), "forged handle rejected " + str(fake))
	# 不透明票穿过普通规则图；恢复只恢复规则，不退款静态账。
	var holder = Holder.new()
	holder.ticket = lease
	var observer = small()
	check(observer.capture([holder], {}, context), "lease explicit graph leaf")
	check(not observer._objects.has(lease), "lease not captured as rule object")
	check(not Checkpoint.Ids.script_fields(cp).has("_budget_sessions"), "account outside instance field graph")
	check(completed(cp.reserve_budget(lease, {"values":3}, context)), "debit after observer capture")
	var spent:Dictionary = remaining(cp)
	holder.items.append(8)
	check(observer.restore() and holder.items == [7], "real observer restore")
	check(remaining(cp) == spent, "observer restore cannot refund original account")
	alias.append(9)
	check(cp.restore() and alias == [5], "original checkpoint restore")
	check(remaining(cp) == spent and completed(cp.validate_budget_lease(inner, context)), "restore retains spent shared account")
	cp.limits.max_capture_collections = 1000000
	cp.max_capture_values = 1000000
	check(remaining(cp) == spent, "limit edits do not refill active session")
	check(cp.capture([], {}, context), "successful recapture")
	check(not completed(cp.validate_budget_lease(lease, context)), "old lease invalid on successful recapture")
	var next:Variant = cp.issue_budget_lease(context).get("lease")
	check(not cp.capture([], {}, null), "new capture source failure")
	check(not completed(cp.validate_budget_lease(next, context)) and not completed(cp.issue_budget_lease(context)), "failed capture retires old account")
	check(cp.capture([], {}, context), "reopen only real capture")
	var fresh:Variant = cp.issue_budget_lease(context).get("lease")
	check(not completed(cp.validate_budget_lease(next, context)), "failed capture old lease never revives")
	check(completed(cp.close_budget(context)), "explicit close")
	check(not completed(cp.reserve_budget(fresh, {}, context)) and not completed(cp.issue_budget_lease(context)), "close no reissue bypass")
	check(cp.restore(), "close does not revoke original rule restore")
	# 四维精确边界及多租约共享耗尽。
	for dim in Checkpoint.BUDGET_DIMENSIONS:
		var edge = small()
		check(edge.capture([], {}, context), "edge capture " + dim)
		var a:Variant = edge.issue_budget_lease(context).get("lease")
		var b:Variant = edge.issue_budget_lease(context).get("lease")
		var exact:Dictionary = {}
		exact[dim] = remaining(edge)[dim]
		check(completed(edge.reserve_budget(a, exact, context)) and remaining(edge)[dim] == 0, "exact boundary " + dim)
		var one:Dictionary = {}; one[dim] = 1
		rejects_unchanged(edge, b, one, "shared exhausted " + dim)
		check(completed(edge.reserve_budget(b, {}, context)), "empty at zero " + dim)
		edge.close_budget(context)
	var no_ticket = small()
	no_ticket.max_capture_objects = 0
	check(no_ticket.capture([], {}, context), "zero objects legal empty capture")
	check(not completed(no_ticket.issue_budget_lease(context)) and remaining(no_ticket).objects == 0 and remaining(no_ticket).values == 100, "issuance failure atomic")
	# 原capture门必须真实触发，错误文案不改；无放宽、无后扫放行。
	var gate = small(); gate.limits.max_capture_collections = 1
	check(not gate.capture([[],[]], {}, context) and gate.error == "回滚检查点超出集合预算", "original collection error")
	gate = small(); gate.limits.max_capture_comparisons = 0
	check(not gate.capture([alias,alias], {}, context) and gate.error == "回滚检查点超出集合身份比较预算", "original comparison error")
	gate = small(); gate.max_capture_values = 1
	check(not gate.capture([[1]], {}, context) and gate.error == "回滚检查点超出待采集值预算", "original pending values error")
	gate = small(); gate.max_capture_values = 0
	check(not gate.capture([1], {}, context) and gate.error == "回滚检查点超出值访问预算", "original visited values error")
	gate = small(); gate.max_capture_objects = 0
	check(not gate.capture([rng], {}, context) and gate.error == "回滚检查点超出对象预算", "original object error")
	check(not completed(gate.issue_budget_lease(context)), "overbudget failed capture no ticket")
	var failed_recapture = small()
	check(failed_recapture.capture([], {}, context), "capture failure lifecycle baseline")
	var before_failure:Variant = failed_recapture.issue_budget_lease(context).get("lease")
	failed_recapture.max_capture_values = 0
	check(not failed_recapture.capture([1], {}, context), "same source recapture overbudget fails")
	check(not completed(failed_recapture.validate_budget_lease(before_failure, context)), "overbudget recapture retires old lease")
	failed_recapture.max_capture_values = 100
	check(failed_recapture.capture([], {}, context) and not completed(failed_recapture.validate_budget_lease(before_failure, context)), "overbudget old lease never revives after recapture")
	var defaults = Checkpoint.new()
	check(defaults.limits.max_capture_collections == 100000 and defaults.limits.max_capture_comparisons == 1000000 and defaults.max_capture_values == 1000000 and defaults.max_capture_objects == 100000, "four original defaults unchanged")
	var full = small()
	check(full.capture([], {}, context), "full combination capture")
	var full_ticket:Variant = full.issue_budget_lease(context).get("lease")
	check(completed(full.reserve_budget(full_ticket, remaining(full), context)) and remaining(full) == {"collections":0,"comparisons":0,"values":0,"objects":0}, "full four dimensional boundary")
	var old:Variant = other.issue_budget_lease(context).get("lease")
	Generation.begin_generation(&"budget_lease_next_generation")
	check(not completed(other.reserve_budget(old, {}, context)) and not completed(other.budget_remaining(context)), "generation transition invalidates budget")
	print("RESULT ", JSON.stringify({"suite":"checkpoint-budget-lease","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
