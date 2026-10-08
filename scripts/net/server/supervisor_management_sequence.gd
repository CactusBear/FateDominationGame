extends RefCounted

# 单主管串行分配；先持久化预留，后发送 IPC。失败可跳号，绝不回滚或回绕。
const Channel = preload("res://scripts/net/server/server_console_channel.gd")
const Paths = preload("res://scripts/net/server/recovery_path_safety.gd")
const Bindings = preload("res://scripts/net/identity/member_identity_bindings.gd")

func reserve(manager, room:String) -> int:
	var binding:Dictionary = manager.instance_binding(room)
	if not manager.binding_matches(binding,true): return 0
	var directory:String = str(manager.rooms.get(room,{}).get("directory","")).path_join("control")
	var path:String = directory.path_join("supervisor-sequence.%s.json" % binding.instance_id)
	if not Paths.checked(manager.storage_root,directory) or not Paths.checked(directory,path,true) or not Paths.checked(directory,path+".tmp",true): return 0
	var last:int = 0
	if FileAccess.file_exists(path):
		var saved:Dictionary = read_bounded(path)
		if saved.size() != 2 or not preload("res://scripts/net/server/worker_identity_ipc.gd").same_binding(saved.get("binding"),binding,"instance_id") or not Bindings.valid_counter(saved.get("sequence")): return 0
		last = int(saved.sequence)
	var ledger_path:String = directory.path_join("identity-context.%s.json" % binding.instance_id)
	if not Paths.checked(directory,ledger_path,true): return 0
	if FileAccess.file_exists(ledger_path):
		var ledger:Dictionary = read_bounded(ledger_path)
		var worker_binding:Dictionary = {"room":binding.room,"pid":binding.pid,"instance":binding.instance_id,"authority_host_mode":binding.authority_host_mode}
		if not preload("res://scripts/net/server/worker_identity_ipc.gd").same_binding(ledger.get("binding"),worker_binding) or not Bindings.valid_counter(ledger.get("request_seq")): return 0
		last = maxi(last,int(ledger.request_seq))
	if last >= 2147483647 or not manager.binding_matches(binding,true): return 0
	var next:int = last + 1
	if Channel.write_json(path,{"binding":binding,"sequence":next}) != OK: return 0
	return next if manager.binding_matches(binding,true) else 0

static func read_bounded(path:String) -> Dictionary:
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null: return {}
	if file.get_length() > 4096:
		file.close()
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
