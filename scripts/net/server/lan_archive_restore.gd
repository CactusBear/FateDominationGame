extends RefCounted

# 仅本机管理员登记路径；网络请求不能调用 register_local。
const Channel = preload("res://scripts/net/server/server_console_channel.gd")
const Paths = preload("res://scripts/net/server/recovery_path_safety.gd")
const Contract = preload("res://scripts/net/server/authority_restore_contract.gd")
const Keys = preload("res://scripts/net/identity/member_identity_bindings.gd")
const Sequence = preload("res://scripts/net/server/supervisor_management_sequence.gd")
var busy:bool = false
var error:String = ""

static func read_metadata(path:String) -> Dictionary:
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null: return {}
	if file.get_length() > 16 * 1024 * 1024:
		file.close()
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

static func register_local(directory:String, binding:Dictionary, archive_id:String, source:String, metadata_source:String = "") -> bool:
	if not Channel.valid_id(archive_id) or not Paths.checked(directory,directory): return false
	if not source.is_absolute_path() or not Paths.tree(source.get_base_dir(),source,[20000]): return false
	var metadata:String = source.path_join("restore-identity.json") if metadata_source.is_empty() else metadata_source
	var log:String = source.path_join("match.log")
	if not metadata.is_absolute_path() or not Paths.checked(metadata.get_base_dir(),metadata) or not Paths.checked(source,log): return false
	var path:String = directory.path_join("archive-"+archive_id+".json")
	if not Paths.checked(directory,path,true) or not Paths.checked(directory,path+".tmp",true) or FileAccess.file_exists(path): return false
	var entry:Dictionary = {"binding":binding,"archive_id":archive_id,"source":source,"metadata_source":metadata,"metadata_hash":FileAccess.get_sha256(metadata),"log_hash":FileAccess.get_sha256(log)}
	return Channel.write_json(path,entry) == OK

func submit(host, session, source:String, selected:Dictionary = {}, metadata_source:String = "") -> bool:
	if busy: return false
	error = ""
	var target:Dictionary = host.gateway.manager.rooms.get(host.room_id,{})
	if target.is_empty() or not host.gateway.manager.is_ready(host.room_id) or not host._owner_bound or not host._closing_target.is_empty(): return reject_local(session,"权威未就绪或正在关闭")
	var binding:Dictionary = {"room":host.room_id,"pid":target.pid,"instance":target.instance_id,"authority_host_mode":target.authority_host_mode}
	var process_binding:Dictionary = host.gateway.manager.instance_binding(host.room_id).duplicate()
	var directory:String = str(target.directory).path_join("control")
	var archive_id:String = Crypto.new().generate_random_bytes(16).hex_encode()
	if not register_local(directory,binding,archive_id,source,metadata_source): return reject_local(session,"本机存档登记失败：要求无链接目录、日志及认证座位元数据")
	var metadata:String = source.path_join("restore-identity.json") if metadata_source.is_empty() else metadata_source
	var saved:Dictionary = read_metadata(metadata)
	if not saved.get("bindings") is Dictionary: return reject_local(session,"恢复元数据缺少有效座位绑定")
	var seats:Dictionary = selected.duplicate(true) if not selected.is_empty() else saved.get("bindings",{}).duplicate(true)
	var sequence:int = Sequence.new().reserve(host.gateway.manager,host.room_id)
	if sequence <= 0: return reject_local(session,"恢复序号保存失败")
	var request:Dictionary = binding.duplicate()
	request.merge({"action":"restore","actor_member":session.peer_id(),"revision":session.view.get("revision",-1),"request_seq":sequence,"archive_id":archive_id,"bindings":seats})
	var id:String = Crypto.new().generate_random_bytes(16).hex_encode()
	var request_path:String = directory.path_join(id+".request.json")
	var response_path:String = directory.path_join(id+".response.json")
	if not Paths.checked(directory,request_path,true) or not Paths.checked(directory,request_path+".tmp",true) or not Paths.checked(directory,response_path,true) or Channel.write_json(request_path,request) != OK: return reject_local(session,"恢复 IPC 提交失败")
	busy = true
	# SceneTree 正常泵送主管心跳和身份通路，不手动递归 poll，不设置短超时冒充取消。
	while true:
		if Paths.checked(directory,response_path,true) and FileAccess.file_exists(response_path):
			var response:Dictionary = Sequence.read_bounded(response_path)
			if preload("res://scripts/net/server/worker_identity_ipc.gd").same_binding({"room":response.get("room"),"pid":response.get("pid"),"instance":response.get("instance"),"authority_host_mode":response.get("authority_host_mode")},binding) and response.get("request_id") == id:
				busy = false
				if response.get("ok") == true and response.get("result",{}).get("restored") == true: return true
				return reject_local(session,str(response.get("error",response.get("code","恢复被拒"))))
		if not host.gateway.manager.binding_matches(process_binding,true): break
		await Engine.get_main_loop().process_frame
	busy = false
	return reject_local(session,"权威实例丢失；未确认恢复成功，原档保留")

func reject_local(session, reason:String) -> bool:
	error = reason
	session.error = reason
	session.rejected.emit(reason)
	return false

func execute(control, request:Dictionary) -> Dictionary:
	var session = control.session
	if busy or not session.dedicated or session.room.phase not in ["lobby","restoring"] or session.match_authority.started or session._restore_failed_closed: return rejection("restore_busy_or_not_lobby")
	var current:Dictionary = {"room":control.room_id,"pid":OS.get_process_id(),"instance":control.instance_id,"authority_host_mode":control.authority_host_mode}
	if request.size() != 10 or request.get("action") != "restore" or not Keys.valid_counter(request.get("actor_member")) or request.actor_member <= 0: return rejection("invalid_request")
	for field in current:
		if request.get(field) != current[field]: return rejection("stale_instance")
	var actor:int = int(request.actor_member)
	var actor_context:Dictionary = live_context(session,actor)
	if actor_context.is_empty(): return rejection("unauthenticated")
	if session._member_identities.get(actor,"") != actor_context.get("actor_key"): return rejection("key_mismatch")
	if actor != session.room.owner: return rejection("not_authenticated_owner")
	if not request.get("archive_id") is String or not Channel.valid_id(request.archive_id): return rejection("invalid_archive_id")
	var registration:String = control.directory.path_join("archive-"+request.archive_id+".json")
	if not Paths.checked(control.directory,registration): return rejection("unregistered_archive")
	var entry:Dictionary = Sequence.read_bounded(registration)
	if not preload("res://scripts/net/server/worker_identity_ipc.gd").same_binding(entry.get("binding"),current) or entry.get("archive_id") != request.archive_id or not entry.get("source") is String: return rejection("invalid_registration")
	var source:String = entry.source
	if not source.is_absolute_path() or not Paths.tree(source.get_base_dir(),source,[20000]): return rejection("unsafe_archive")
	if not entry.get("metadata_source") is String or not entry.metadata_source.is_absolute_path(): return rejection("invalid_registration")
	var metadata:String = entry.metadata_source
	if not Paths.checked(metadata.get_base_dir(),metadata) or FileAccess.get_sha256(metadata) != entry.get("metadata_hash"): return rejection("archive_metadata_changed")
	var saved:Dictionary = read_metadata(metadata)
	if not Keys.valid_state(saved,true) or not saved.get("bindings") is Dictionary or not saved.get("seat_kinds") is Dictionary: return rejection("missing_member_key_bindings")
	if not Keys.valid_counter(saved.room.get("owner")) or saved.room.owner <= 0: return rejection("invalid_saved_owner")
	# 先校验存档房主密钥；不能用换座位绕过错密钥拒绝。
	if saved.member_identities.get(str(int(saved.room.owner)),"") != actor_context.get("actor_key"): return rejection("key_mismatch")
	var decoded:Dictionary = preload("res://scripts/net/session/recovery_seat_json.gd").decode(saved)
	if not decoded.get("ok",false): return rejection("invalid_saved_seats")
	var state:Dictionary = saved.duplicate(true)
	state.room = JSON.parse_string(JSON.stringify(session.room.snapshot()))
	state.resume_hashes = {}
	state.resume_previous = {}
	state.member_identities = {}
	state.bindings = {}
	if not request.get("bindings") is Dictionary or request.bindings.size() != saved.bindings.size(): return rejection("invalid_bindings")
	for player in saved.bindings:
		var old_member = saved.bindings[player]
		var member = request.bindings.get(player)
		if not Keys.valid_counter(old_member) or not Keys.valid_counter(member): return rejection("invalid_bindings")
		if old_member <= 0:
			if member != old_member: return rejection("binding_mismatch")
		else:
			if member <= 0: return rejection("binding_mismatch")
			var live:Dictionary = live_context(session,int(member))
			var expected:String = saved.member_identities.get(str(int(old_member)),"")
			if live.is_empty(): return rejection("member_not_authenticated")
			if expected.is_empty() or live.get("actor_key") != expected: return rejection("key_mismatch")
			state.member_identities[str(int(member))] = expected
		state.bindings[player] = member
	# valid_state 同时要求大厅中的观战者有认证密钥；使用真实当前账本，不信任请求键。
	for member in session._member_identities:
		if not state.member_identities.has(str(member)): state.member_identities[str(member)] = session._member_identities[member]
	var sequence_path:String = control.directory.path_join("restore-worker-sequence."+control.instance_id+".json")
	if not Paths.checked(control.directory,sequence_path,true) or not Paths.checked(control.directory,sequence_path+".tmp",true): return rejection("unsafe_sequence")
	var sequence_state:Dictionary = Sequence.read_bounded(sequence_path)
	if FileAccess.file_exists(sequence_path) and (sequence_state.size() != 1 or not Keys.valid_counter(sequence_state.get("sequence"))): return rejection("corrupt_restore_sequence")
	var last:int = int(sequence_state.get("sequence",0))
	var prepared:Dictionary = Contract.prepare(request,current,state,actor_context,last)
	if not prepared.get("authorized",false): return prepared.merged({"ok":false})
	# 现有原子恢复仍验证逐文件固定数据快照、初始 seat_kinds、全部在线真人和最终 ACK。
	var approved:Dictionary = session.decode_approved_data_snapshot(saved.get("approved_data_snapshot",{}))
	if not approved.get("ok",false) or approved.snapshot.files.size() != session.room_files.size(): return rejection("approved_data_mismatch")
	for index in range(session.room_files.size()):
		for field in ["path","hash","size","provider"]:
			if approved.snapshot.files[index].get(field) != session.room_files[index].get(field): return rejection("approved_data_mismatch")
	if not Paths.checked(source,source.path_join("match.log")) or FileAccess.get_sha256(source.path_join("match.log")) != entry.get("log_hash"): return rejection("archive_log_changed")
	if not control.restore_snapshot.is_valid() or not control.restore_transaction.is_valid(): return rejection("snapshot_callback_unavailable")
	var receipt_path:String = control.directory.path_join("restore-authorized."+control.instance_id+"."+str(int(request.request_seq))+".json")
	if not Paths.checked(control.directory,receipt_path,true) or not Paths.checked(control.directory,receipt_path+".tmp",true) or FileAccess.file_exists(receipt_path): return rejection("unsafe_or_existing_restore_receipt")
	var receipt:Dictionary = {"binding":current,"archive_id":request.archive_id,"actor_member":actor,"revision":int(request.revision),"request_seq":int(request.request_seq),"bindings":prepared.proposal.bindings,"metadata_hash":entry.metadata_hash,"log_hash":entry.log_hash,"status":"authorized_not_committed"}
	if Channel.write_json(receipt_path,receipt) != OK: return rejection("restore_receipt_persistence_failed")
	if Channel.write_json(sequence_path,{"sequence":int(request.request_seq)}) != OK: return rejection("restore_sequence_persistence_failed")
	busy = true
	var room_before:Dictionary = session.room.snapshot().duplicate(true)
	session._restore_in_progress = true
	var snapshot:String = control.restore_snapshot.call(source,request.archive_id)
	session._restore_in_progress = false
	if snapshot.is_empty():
		busy = false
		return rejection("archive_copy_failed")
	if session.room.snapshot() != room_before or live_context(session,actor).is_empty() or FileAccess.get_sha256(snapshot.path_join("match.log")) != entry.log_hash:
		busy = false
		return rejection("room_or_archive_changed_during_copy")
	var prior:Dictionary = session._recovery_bindings.duplicate()
	var prior_kinds:Dictionary = session._recovery_seat_kinds.duplicate()
	session._recovery_bindings = prepared.proposal.bindings.duplicate()
	session._recovery_seat_kinds = decoded.seat_kinds.duplicate()
	session._lan_restore_authorized = true
	var ok:bool = await control.restore_transaction.call(snapshot)
	session._lan_restore_authorized = false
	busy = false
	if not ok:
		if not session._restore_failed_closed:
			session._recovery_bindings = prior
			session._recovery_seat_kinds = prior_kinds
		return {"ok":false,"error":session.error,"executed":session._restore_failed_closed,"code":"restore_failed"}
	return {"ok":true,"executed":true,"result":{"restored":true,"archive_id":request.archive_id,"request_seq":int(request.request_seq),"phase":"restoring","data_barrier_pending":true}}

static func live_context(session, member:int) -> Dictionary:
	if not session.lan_context.is_valid() or not session._peer_by_member.has(member) or not session.room.members.has(member) or not session.room.members[member].get("connected",false): return {}
	return session.lan_context.call(int(session._peer_by_member[member]),member,false)

static func rejection(code:String) -> Dictionary:
	return {"ok":false,"executed":false,"code":code,"error":"存档恢复被拒："+code}
