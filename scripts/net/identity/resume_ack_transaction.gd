extends RefCounted

## 仅确认当前恢复凭据并提交旧状态删除；来源鉴权、保存路径和失败通知归调用方。
## 同步 persist 必须返回 bool，且只保存调用方状态；此组件不保存任何引用或能力。
enum Status { UNMATCHED, CONFIRMED, PERSIST_FAILED }

static func acknowledge(member:int, token:Variant, current_hash:Variant, previous_hashes:Dictionary, persist:Callable) -> Status:
	if not token is String or token.sha256_text() != current_hash or not previous_hashes.has(member):
		return Status.UNMATCHED
	var previous:String = previous_hashes[member]
	previous_hashes.erase(member)
	if not persist.is_valid() or not persist.call():
		previous_hashes[member] = previous
		return Status.PERSIST_FAILED
	return Status.CONFIRMED
