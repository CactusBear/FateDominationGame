extends RefCounted

## 仅主管内部持有；认证适配器提供完整快照，不接收网络 args。
const Channel = preload("res://scripts/net/server/server_console_channel.gd")
const Bindings = preload("res://scripts/net/identity/member_identity_bindings.gd")
const Paths = preload("res://scripts/net/server/recovery_path_safety.gd")
var _pending:Dictionary = {}

## authenticated_snapshot(binding) 必须读取主管已认证连接注册表；空快照用于撤销。
## 序号由主管持久化的管理序列分配；本函数不把 OS process_token 暴露给 worker。
func submit(manager, room_id:String, sequence:int, authenticated_snapshot:Callable) -> Dictionary:
	var target:Dictionary = manager.instance_binding(room_id)
	if target.get("authority_host_mode") not in ["lan","p2p"] or not manager.binding_matches(target,true): return _reject("unverified_supervisor_instance")
	if not Bindings.valid_counter(sequence) or sequence <= 0 or not authenticated_snapshot.is_valid(): return _reject("invalid_identity_delivery")
	var snapshot = authenticated_snapshot.call(target.duplicate(true))
	if not snapshot is Dictionary or snapshot.size() != 2 or not snapshot.get("connections") is Dictionary or not snapshot.get("profiles") is Dictionary: return _reject("missing_authenticated_snapshot")
	var request:Dictionary = {"room":target.room,"pid":target.pid,"instance":target.instance_id,"authority_host_mode":target.authority_host_mode,"action":"identity_context","request_seq":sequence,"connections":snapshot.connections.duplicate(true),"profiles":snapshot.profiles.duplicate(true)}
	if JSON.stringify(request).to_utf8_buffer().size() > 4096: return _reject("identity_request_budget_exceeded")
	# 快照构建期间主管登记可能变化；写入前再次验证原实例能力。
	if not manager.binding_matches(target,true): return _reject("stale_supervisor_instance")
	var room:Dictionary = manager.rooms.get(room_id,{})
	var directory:String = str(room.get("directory","")).path_join("control")
	if not Paths.checked(manager.storage_root,directory) or not DirAccess.dir_exists_absolute(directory): return _reject("unsafe_identity_control_path")
	var id:String = Crypto.new().generate_random_bytes(16).hex_encode()
	if not Channel.valid_id(id): return _reject("request_id_unavailable")
	var path:String = directory.path_join(id+".request.json")
	var response_path:String = directory.path_join(id+".response.json")
	for candidate in [path,path+".tmp",response_path,response_path+".tmp"]:
		if not Paths.checked(directory,candidate,true) or FileAccess.file_exists(candidate): return _reject("unsafe_identity_request_path")
	if Channel.write_json(path,request) != OK: return _reject("identity_request_persistence_failed")
	_pending[id] = {"binding":target.duplicate(true),"request_seq":sequence,"response_path":response_path}
	return {"ok":true,"queued":true,"confirmed":false,"request_id":id}

## 只认可当前实例的精确回执；队列成功不等于身份安装成功。
func confirmation(manager, id:String) -> Dictionary:
	if not _pending.has(id): return _reject("unknown_identity_request")
	var pending:Dictionary = _pending[id]
	if not manager.binding_matches(pending.binding,true): return _reject("stale_identity_confirmation")
	if not FileAccess.file_exists(pending.response_path): return {"ok":false,"pending":true,"confirmed":false}
	var file = FileAccess.open(pending.response_path,FileAccess.READ)
	if file == null: return _reject("unreadable_identity_confirmation")
	if file.get_length() > 4096:
		file.close()
		return _reject("oversized_identity_confirmation")
	var response = JSON.parse_string(file.get_as_text())
	file.close()
	if not response is Dictionary: return _reject("invalid_identity_confirmation")
	var binding:Dictionary = pending.binding
	if response.get("request_id") != id or response.get("room") != binding.room or response.get("pid") != binding.pid or response.get("instance") != binding.instance_id or response.get("authority_host_mode") != binding.authority_host_mode: return _reject("mismatched_identity_confirmation")
	if response.get("ok") != true: return _reject(str(response.get("code","identity_delivery_rejected")))
	var result = response.get("result")
	if not result is Dictionary or result.get("request_seq") != pending.request_seq or result.get("identity_context_installed") != true or response.get("executed") != false: return _reject("invalid_identity_confirmation")
	_pending.erase(id)
	return {"ok":true,"confirmed":true,"request_id":id,"request_seq":pending.request_seq,"executed":false}

func abandon(id:String) -> void:
	_pending.erase(id)

static func _reject(code:String) -> Dictionary:
	return {"ok":false,"confirmed":false,"code":code}
