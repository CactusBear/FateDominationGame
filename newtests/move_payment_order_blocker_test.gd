extends "res://tests/fd39_operations_test.gd"

# 只读生产实现的顺序诊断，不作为修复通过证明。
func run() -> void:
	var before_result := probe_existing_order()
	var after_result := probe_payment_first()
	check(before_result.moved and after_result.moved, "both legal success paths reach identical destination")
	check(before_result.balance != after_result.balance, "BLOCKER payment-first changes legal final magic")
	print("ORDER_BLOCKER ", JSON.stringify({"existing": before_result, "candidate": after_result}))
	print("RESULT checks=%d failures=%s" % [checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)

func prepare() -> void:
	setup()
	check(SetLocation.new().exec(MapData.magic_workshop0, 0, false), "fixture starts in workshop")
	_real_effect("masters/00003_matou_shinji/00003_matou_shinji.json", "absorb_magic_command", 0)
	pd(0).magic.set_num(GameData.player_magic_limit(0))
	check(pd(0).magic.number == GameData.player_magic_limit(0).number, "fixture has legal full magic")
	check(MapData.magic_workshop._linked_map_area == MapData.miyama, "real map links workshop to miyama")
	check(MapData.magic_workshop._move_cost.number > 0, "real route has nonzero cost")

func probe_existing_order() -> Dictionary:
	prepare()
	var before:float = pd(0).magic.number
	var cost:float = MapData.magic_workshop._move_cost.number
	Move.new().exec(BaseNumber.new(1), 0)
	check(pd(0).magic.number == before - cost, "existing order clips enter gain before paying")
	return {"balance": pd(0).magic.number, "moved": pd(0).location == MapData.miyama2, "before": before, "cost": cost}

func probe_payment_first() -> Dictionary:
	prepare()
	var before:float = pd(0).magic.number
	var cost:float = MapData.magic_workshop._move_cost.number
	var target:BaseLocation = GetMoveTargetLocation.new().exec(MapData.miyama)
	check(PayMagic.new().exec(BaseNumber.new(cost), 0, "move", target), "candidate pays with real primitive")
	check(SetLocation.new().exec(target, 0), "candidate reaches real enter-location effect")
	check(pd(0).magic.number == minf(before, before - cost + 1), "candidate enter gain fills payment headroom")
	return {"balance": pd(0).magic.number, "moved": pd(0).location == MapData.miyama2, "before": before, "cost": cost}
