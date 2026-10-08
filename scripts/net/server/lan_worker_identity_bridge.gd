extends RefCounted

# worker 私有桥：观察真实 transport 世代；等待身份 IPC，不采信网络授权字段。
const Channel = preload("res://scripts/net/server/server_console_channel.gd")
const Paths = preload("res://scripts/net/server/recovery_path_safety.gd")
var ledger
var _control
var session
var binding:Dictionary = {}
var path:String = ""
var observed:Dictionary = {}
var members:Dictionary = {}
var pending:Dictionary = {}
var deadlines:Dictionary = {}
var error:String = ""
var _published:String = ""
var max_pending:int = 32
var max_messages_per_peer:int = 16
var max_pending_bytes:int = 4 * 1024 * 1024
var _pending_bytes:int = 0
var timeout_msec:int = 10000

func configure(control, target) -> bool:
	if not Paths.checked(control.directory.get_base_dir(),control.directory,true): return false
	if DirAccess.make_dir_recursive_absolute(control.directory) != OK or not Paths.checked(control.directory.get_base_dir(),control.directory): return false
	ledger = control.identity_context()
	if ledger == null: return false
	_control = control
	session = target
	binding = {"room":control.room_id,"pid":OS.get_process_id(),"instance":control.instance_id,"authority_host_mode":control.authority_host_mode}
	path = control.directory.path_join("identity-observed.%s.json" % control.instance_id)
	if not Paths.checked(control.directory,path,true) or not Paths.checked(control.directory,path+".tmp",true): return false
	session.transport.peer_connected.connect(connected)
	session.transport.peer_disconnected.connect(disconnected)
	session.lan_context = context
	session.lan_gate = gate
	return publish()

func connected(peer:int) -> void:
	if peer <= 1 or observed.size() >= max_pending:
		if session != null: session.transport.disconnect_peer(peer)
		return
	var nonce:String = Crypto.new().generate_random_bytes(16).hex_encode()
	if not ledger.observe_connection(peer,nonce):
		if session != null: session.transport.disconnect_peer(peer)
		return
	observed[peer] = nonce
	deadlines[peer] = Time.get_ticks_msec() + timeout_msec
	if not publish() and session != null: session.transport.disconnect_peer(peer)

func disconnected(peer:int) -> void:
	ledger.forget_connection(peer) # 即便撤销文件写失败，也立即撤销活连接。
	observed.erase(peer)
	members.erase(peer)
	for message in pending.get(peer,[]): _pending_bytes -= var_to_bytes(message).size()
	pending.erase(peer)
	deadlines.erase(peer)
	publish()

func context(peer:int, member:int, joining:bool = false) -> Dictionary:
	if _control != null and (_control.identity_receipt_sequence <= 0 or _control.identity_receipt_sequence != ledger.last_sequence()): return {}
	if not observed.has(peer): return {}
	if not joining and members.get(peer) != member: return {}
	return ledger.context_for(peer,observed[peer],peer if joining else member)

func gate(peer:int, message:Dictionary) -> bool:
	var joining:bool = message.get("kind") == "join"
	var member:int = int(members.get(peer,peer))
	if not context(peer,member,joining).is_empty(): return false
	if not observed.has(peer):
		session.transport.disconnect_peer(peer)
		return true
	if not pending.has(peer):
		pending[peer] = []
		deadlines[peer] = Time.get_ticks_msec() + timeout_msec
	var bytes:int = var_to_bytes(message).size()
	if pending[peer].size() >= max_messages_per_peer or _pending_bytes + bytes > max_pending_bytes:
		session.transport.disconnect_peer(peer)
		return true
	_pending_bytes += bytes
	pending[peer].append(message.duplicate(true))
	return true

func poll() -> void:
	for peer in observed.keys():
		if session._member_by_peer.has(peer): members[peer] = int(session._member_by_peer[peer])
		else: members.erase(peer)
	if not publish():
		# 私有观察无法交付时不继续以旧认证授权。
		for peer in observed.keys(): session.transport.disconnect_peer(peer)
		return
	for peer in observed.keys():
		if not pending.has(peer) or pending[peer].is_empty():
			if not members.has(peer) and Time.get_ticks_msec() >= int(deadlines.get(peer,0)):
				session.transport.disconnect_peer(peer)
			continue
		var message:Dictionary = pending[peer][0]
		if context(peer,int(members.get(peer,peer)),message.get("kind") == "join").is_empty():
			if Time.get_ticks_msec() >= int(deadlines.get(peer,0)):
				session.transport.disconnect_peer(peer)
			continue
		if session._restore_in_progress: continue
		pending[peer].pop_front()
		_pending_bytes -= var_to_bytes(message).size()
		if pending[peer].is_empty(): pending.erase(peer)
		session._receive(peer,message)

func publish() -> bool:
	var connections:Dictionary = {}
	for peer in observed:
		connections[str(peer)] = {"nonce":observed[peer],"member":int(members.get(peer,peer)),"joined":members.has(peer)}
	var report:Dictionary = {"binding":binding,"connections":connections}
	var text:String = JSON.stringify(report)
	if text == _published: return true
	if text.to_utf8_buffer().size() > 4096 or Channel.write_json(path,report) != OK:
		error = "worker_identity_observation_failed"
		return false
	_published = text
	return true
