extends RefCounted

## 房主选择控件的输入模型。只接收公开候选，不接收指纹或恢复凭据。
const Rules = preload("res://scripts/net/identity/member_identity_bindings.gd")
var revision:int = -1
var candidates:Array = []
var selected_member:int = 0

func accept(model:Dictionary) -> bool:
	if model.size() != 3 or not Rules.valid_counter(model.get("revision")) or not Rules.valid_counter(model.get("request_floor")) or not model.get("candidates") is Array: return false
	var seen:Dictionary = {}
	var next:Array = []
	for row in model.candidates:
		if not row is Dictionary or row.size() != 2 or not row.get("member_id") is int or row.member_id <= 0 or not row.get("label") is String or row.label.is_empty() or seen.has(row.member_id): return false
		seen[row.member_id] = true
		next.append({"member_id":row.member_id,"label":row.label})
	if revision > int(model.revision): return false
	if revision != int(model.revision) or not seen.has(selected_member): selected_member = 0
	revision = int(model.revision)
	candidates = next
	return true

func select_member(member_id:int) -> bool:
	for row in candidates:
		if row.member_id == member_id:
			selected_member = member_id
			return true
	return false

func request_args(target_member:int) -> Dictionary:
	if revision < 0 or selected_member <= 0 or target_member <= 0 or target_member == selected_member: return {}
	return {"target_member":target_member,"successor_member":selected_member,"revision":revision}

func clear() -> void:
	revision = -1
	selected_member = 0
	candidates.clear()
