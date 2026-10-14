extends "res://tests/fd39_operations_test.gd"

# 诊断：只读预检 → 支付（派魔力减少时点）→ 落位，不构成原子提交。
# 未修改生产入口；此 RED 必须保留，不能改成候选行为的通过断言。
func run() -> void:
	setup()
	check(SetLocation.new().exec(MapData.magic_workshop0, 0, false), "fixture starts in workshop")
	pd(0).magic.set_num(BaseNumber.new(4))
	var target:BaseLocation = GetMoveTargetLocation.new().exec(MapData.miyama)
	var old_location:BaseLocation = pd(0).location
	var before:float = pd(0).magic.number
	var original_can_move:bool = MapData.miyama._can_move_to
	var cost := BaseNumber.new(MapData.magic_workshop._move_cost.number)
	check(target == MapData.miyama2 and cost.number == 1, "real route target and fee")
	# 与 SetLocation.exec 的全部拒绝门同口径，只读且不添加生产逻辑。
	var admitted:bool = target != null and (target._pl_num_limit == -1 or target._players.size() < target._pl_num_limit) and MapData.miyama._can_move_to and not SetLocation.area_locked(MapData.miyama) and not SetLocation.area_locked(MapData.magic_workshop)
	check(admitted and PayMagic.can_pay(cost, 0), "target admitted and payment affordable before side effects")
	var host := host_with([effect_data("probe_payment_blocks_target", [
		{"func_name": "get_map_area_by_name", "parameters": ["深山町"], "var_index": 0},
		{"func_name": "set_property", "parameters": [{"self_var": 0}, "_can_move_to", false], "var_index": -1}
	], [], ["self_magic_decrease"])])
	GameLog.reset()
	var paid:bool = PayMagic.new().exec(cost, 0, "move", target)
	var moved:bool = SetLocation.new().exec(target, 0) if paid else false
	check(paid and not MapData.miyama._can_move_to, "real payment time point executes declared rejection effect")
	check(not moved and pd(0).location == old_location and old_location._players.has(0) and not target._players.has(0), "placement refused after accepted preflight")
	check(GameLog.query({"type": "move"}).is_empty(), "refusal writes no position fact")
	check(pd(0).magic.number == before, "REQUIRED refused placement must not consume magic")
	check(GameLog.query({"type": "magic_decrease"}).is_empty(), "REQUIRED refused placement must not retain payment fact")
	check(MapData.miyama._can_move_to == original_can_move, "REQUIRED atomic refusal restores payment-triggered rule state")
	print("PREFLIGHT_ATOMICITY ", JSON.stringify({"admitted": admitted, "paid": paid, "moved": moved, "before": before, "after": pd(0).magic.number, "target_can_move_to": MapData.miyama._can_move_to, "move_facts": GameLog.query({"type": "move"}).size(), "payment_facts": GameLog.query({"type": "magic_decrease"}).size()}))
	MapData.miyama._can_move_to = original_can_move
	EffectManager.reset_runtime()
	print("RESULT checks=%d failures=%s" % [checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
