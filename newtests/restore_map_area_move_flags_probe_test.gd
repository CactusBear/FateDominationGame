extends Node

# 只经公开构造器、setter、注册路由和真实落位结果观察区域禁入恢复。
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
	var area:BaseMapArea = BaseMapArea.new("restore_move_probe")
	var slot:BaseLocation = BaseLocation.new(BaseNumber.new(0), BaseNumber.new(0), -1, true)
	slot.set_from(area)
	area.set_map_area_locations([slot])
	var origin:BaseLocation = BaseLocation.new(BaseNumber.new(0), BaseNumber.new(0), -1)
	var player_id:int = 9001
	check(bool(ROUTER.exec_registered("set_location", [slot, player_id, true])), "printed baseline permits regular entry")
	check(bool(ROUTER.exec_registered("set_location", [origin, player_id, false])), "reset to separate origin through public placement")
	SetMapAreaCanMoveTo.new().exec(area, false)
	var without_restore:bool = bool(ROUTER.exec_registered("set_location", [slot, player_id, true]))
	check(not without_restore, "without restore regular entry is rejected")
	check(GetLocation.new().exec(player_id) == origin, "denied entry leaves actual location at origin")
	check(bool(ROUTER.exec_registered("set_location", [slot, player_id, false])), "effect placement bypasses regular entry flag")
	check(bool(ROUTER.exec_registered("set_location", [origin, player_id, false])), "reset effect placement to origin before restore")
	# 连续改动仍必须回到第一次改动之前，而不是最近一次的 false。
	SetMapAreaCanMoveTo.new().exec(area, true)
	SetMapAreaCanMoveTo.new().exec(area, false)
	check(not bool(ROUTER.exec_registered("set_location", [slot, player_id, true])), "stacked change remains blocked before restore")
	ROUTER.exec_registered("restore_map_area_move_flags", [])
	var restored:bool = bool(ROUTER.exec_registered("set_location", [slot, player_id, true]))
	check(restored, "restore permits real regular entry again")
	check(GetLocation.new().exec(player_id) == slot, "restored regular entry changes actual location to target")
	check(restored != without_restore, "restore differs from no-restore control")
	print("OBS move without_restore=", without_restore, " restored=", restored)
	print("RESULT restore_map_area_move_flags_probe checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
