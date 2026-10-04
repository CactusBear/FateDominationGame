extends RefCounted

## 选人规则接口。实现类不依赖界面或对局状态；阵容以玩家 ID 为键。
var error: String = ""
var player_ids: Array = []
var assignments: Dictionary = {}
var initial_order: Array = []

func setup(ids: Array, _masters: Array, _servants: Array, _config: Dictionary) -> bool:
	player_ids = ids.duplicate()
	assignments.clear()
	error = "选人模式未实现"
	return false

func capacity(_masters: Array, _servants: Array, _config: Dictionary) -> int:
	return 0

func available_masters(_player_id: int) -> Array:
	return []

func choose_master(_player_id: int, _master) -> bool:
	return false

func is_complete() -> bool:
	return false

func get_assignments() -> Dictionary:
	return assignments.duplicate(true) if is_complete() else {}

func get_initial_order() -> Array:
	return initial_order.duplicate() if is_complete() else []
