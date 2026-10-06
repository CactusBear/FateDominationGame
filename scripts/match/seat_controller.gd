class_name SeatController
extends RefCounted

## 单机默认由 AI 控制未登记座位；网络会话须显式登记远程与空座位。
const LOCAL := "local"
const AI := "ai"
const REMOTE := "remote"
const VACANT := "vacant"

var default_kind: String = AI
var _kinds: Dictionary = {}

func set_kind(player_id: int, kind: String) -> void:
	_kinds[player_id] = kind

func kind_of(player_id: int) -> String:
	return str(_kinds.get(player_id, default_kind)) if player_id >= 0 else VACANT

func is_ai(player_id: int) -> bool:
	return player_id >= 0 and kind_of(player_id) == AI

func is_local(player_id: int) -> bool:
	return player_id >= 0 and kind_of(player_id) == LOCAL

func set_single_local(player_id: int) -> void:
	for id in _kinds.keys():
		if _kinds[id] == LOCAL:
			_kinds.erase(id)
	if player_id >= 0:
		set_kind(player_id, LOCAL)
