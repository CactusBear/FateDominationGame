extends RefCounted

## 服务端管理协议投影；不保存 Session/Room/回调，不拥有批准、下载或 blob。
const CatalogTransfer = preload("res://scripts/net/transport/catalog_message_transfer.gd")
const DataCatalog = preload("res://scripts/net/content/data_catalog.gd")
const TERMINAL_STAGES:Array = ["applied", "error", "cancelled"]
var data:Dictionary = {}
var generation:int = 0
var error:String = ""

func handles(message:Dictionary) -> bool:
	return message.get("kind") in ["server_data_catalog", "server_data_catalog_part", "server_data_status"]

func reset(next_generation:int) -> void:
	generation = next_generation
	data.clear()
	error = ""

func mark_requested() -> void:
	data["requested"] = true

## 来源和生命周期门在 Session；资格为当前公开 view 的显式判断。
func receive(connection:int, message:Dictionary, qualified:bool, members:Array, transfer:CatalogTransfer, packet_bytes:int, current_generation:int) -> Dictionary:
	error = ""
	if not handles(message): return {"handled":false,"changed":false}
	if current_generation != generation or not qualified:
		if message.get("kind") == "server_data_catalog_part": transfer.fragments.cancel_peer(connection)
		return {"handled":true,"changed":false}
	if message.get("kind") == "server_data_catalog_part":
		message = transfer.accept(connection,message,packet_bytes,"server_data_catalog")
		if message.is_empty():
			error = transfer.error
			return {"handled":true,"changed":false,"error":error}
	if message.get("kind") == "server_data_catalog":
		if _accept_catalog(message,members,transfer.max_message_bytes):
			return {"handled":true,"changed":true,"clear_error":true}
		if error.is_empty(): error = "服务端候选目录无效"
		return {"handled":true,"changed":false,"error":error}
	return {"handled":true,"changed":_accept_status(message.get("state"))}

func _accept_status(state:Variant) -> bool:
	if not state is Dictionary or state.get("stage") not in ["idle", "preparing", "ready", "error", "applied", "cancelled"] or not state.get("request_id") is int or not state.get("catalog_revision") is int or not state.get("text") is String or not state.get("report") is Dictionary: return false
	var previous:Dictionary = data.get("status",{})
	if state.request_id < int(previous.get("request_id",0)): return false
	if not previous.is_empty() and state.request_id == previous.request_id:
		# 目录可以刷新，已准备事务仍绑定原 revision；ready 不是批准终态。
		if state.catalog_revision != previous.catalog_revision: return false
		if previous.stage in TERMINAL_STAGES: return false
		if previous.stage == "ready" and state.stage == "preparing": return false
	data["status"] = state.duplicate(true)
	return true

func _accept_catalog(message:Dictionary, members:Array, max_message_bytes:int) -> bool:
	if var_to_bytes(message).size() > max_message_bytes:
		error = "候选目录超过累计消息预算"
		return false
	if not message.get("catalog_revision") is int or message.catalog_revision <= 0 or not message.get("entries") is Array or not message.get("selected") is Array: return false
	var grouped:Dictionary = {}
	for entry in message.entries:
		if not entry is Dictionary or not entry.get("provider") is String: return false
		var provider:String = entry.provider
		if provider != "server" and not members.any(func(member): return member is Dictionary and str(member.get("id")) == provider and member.get("connected") == true): return false
		if not grouped.has(provider): grouped[provider] = []
		grouped[provider].append(entry)
	var entries:Array = []
	var catalog = DataCatalog.new()
	for provider in grouped:
		var accepted = catalog.accept(grouped[provider],provider)
		if accepted == null:
			error = "\n".join(catalog.errors)
			return false
		entries.append_array(accepted)
	var identities:Dictionary = {}
	for reference in message.selected:
		if not reference is Dictionary or reference.size() != 2 or not reference.get("provider") is String or not reference.get("key") is String: return false
		var identity:String = reference.provider + ":" + reference.key
		if identities.has(identity): return false
		identities[identity] = true
	if not message.get("modes") is Array: return false
	for mode in message.modes:
		if not mode is Dictionary or not mode.get("id") is String or not mode.get("name") is String: return false
	data["catalog_revision"] = message.catalog_revision
	data["modes"] = message.modes.duplicate(true)
	data["entries"] = entries
	data["selected"] = message.selected.duplicate(true)
	return true