extends Node

# 不读席位私有容量/人数：用真实第二人落位与第三人拒绝证明恢复到 2。
const ROUTER = preload("res://scripts/system/operation_router.gd")
var failures:Array = []
var checks:int = 0

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	EffectManager.reset_runtime()
	GameLog.reset()
	var area:BaseMapArea = BaseMapArea.new("restore_limit_probe")
	var slot:BaseLocation = BaseLocation.new(BaseNumber.new(0), BaseNumber.new(0), 2)
	slot.set_from(area)
	area.set_map_area_locations([slot])
	check(bool(ROUTER.exec_registered("set_location", [slot, 9011, false])), "printed two-person slot accepts first occupant")
	SetLocationPlNumLimit.new().exec(slot, 1)
	var without_restore:bool = bool(ROUTER.exec_registered("set_location", [slot, 9012, false]))
	check(not without_restore, "without restore second occupant is rejected at limit one")
	# 二次改写不能把首次保存的 2 覆盖成 1。
	SetLocationPlNumLimit.new().exec(slot, 0)
	check(not bool(ROUTER.exec_registered("set_location", [slot, 9012, false])), "stacked limit zero still rejects second occupant")
	ROUTER.exec_registered("restore_location_pl_num_limits", [])
	var restored:bool = bool(ROUTER.exec_registered("set_location", [slot, 9012, false]))
	check(restored, "restore accepts real second occupant at original limit two")
	check(GetLocation.new().exec(9012) == slot, "restored second occupant actually enters target slot")
	check(restored != without_restore, "restore differs from no-restore control")
	check(not bool(ROUTER.exec_registered("set_location", [slot, 9013, false])), "restored exact limit two rejects third occupant")
	print("OBS limit original=2 changed=0 without_restore=", without_restore, " restored=", restored)
	print("RESULT restore_location_pl_num_limits_probe checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
