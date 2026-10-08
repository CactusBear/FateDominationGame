extends RefCounted
# 固定字段白名单，无消息、身份密钥、票据、昵称或 reason。
var _last_poll_usec:int = 0
var _max_gap_usec:int = 0
var _last_emit_usec:Dictionary = {}
var _last_signature:Dictionary = {}
var _poll_count:int = 0
var _last_native_poll_usec:int = -1

func enabled() -> bool:
	return OS.get_environment("FD_RECOVERY_DIAGNOSTICS") == "1"

func poll_enter() -> void:
	if not enabled(): return
	var now:int = Time.get_ticks_usec()
	if _last_poll_usec > 0: _max_gap_usec = maxi(_max_gap_usec,now-_last_poll_usec)
	_last_poll_usec = now
	_poll_count += 1

func native_poll_elapsed(start_usec:int) -> void:
	if enabled(): _last_native_poll_usec = Time.get_ticks_usec()-start_usec

func sample(transport, stage:String, remote_id:int = 0, context:Dictionary = {}) -> void:
	if not enabled(): return
	var native = transport._peer
	var status:int = -1
	var local_id:int = 0
	var native_instance:int = 0
	var state:int = -1
	var rtt:int = -1
	var packet_loss:int = -1
	if is_instance_valid(native):
		status = int(native.get_connection_status())
		native_instance = native.get_instance_id()
		if status == MultiplayerPeer.CONNECTION_CONNECTED:
			local_id = native.get_unique_id()
			if stage != "peer_disconnected" and native is ENetMultiplayerPeer and remote_id > 0 and transport._connected_peers.has(remote_id):
				var remote = native.get_peer(remote_id)
				if is_instance_valid(remote):
					state = remote.get_state()
					rtt = int(remote.get_statistic(ClassDB.class_get_integer_constant("ENetPacketPeer","PEER_ROUND_TRIP_TIME")))
					packet_loss = int(remote.get_statistic(ClassDB.class_get_integer_constant("ENetPacketPeer","PEER_PACKET_LOSS")))
	var record:Dictionary = {"stage":stage,"pid":OS.get_process_id(),"ticks_usec":Time.get_ticks_usec(),
		"transport_instance":transport.get_instance_id(),"native_instance":native_instance,
		"connection_status":status,"local_peer":local_id,"remote_peer":remote_id,
		"enet_state":state,"enet_rtt_msec":rtt,"enet_packet_loss_raw":packet_loss,
		"timeout_limit":-1,"timeout_min_msec":-1,"timeout_max_msec":-1,
		"timeout_observation":"not_exposed_no_setter_called",
		"poll_calls":_poll_count,"max_poll_gap_usec":_max_gap_usec,"native_poll_usec":_last_native_poll_usec}
	for key in ["external_peer","internal_peer","worker_pid"]:
		if context.get(key) is int: record[key] = context[key]
	for key in ["room","instance_id"]:
		var value:Variant = context.get(key)
		if value is String and value.length() == 32 and value.is_valid_hex_number(false): record[key] = value
	if context.get("attached") is bool: record["attached"] = context.attached
	var signature:String = str([stage,status,local_id,remote_id,state,native_instance,context.get("instance_id",""),context.get("attached",false)])
	var now:int = Time.get_ticks_usec()
	var sample_key:String = stage+":"+str(remote_id)
	if stage in ["poll","poll_after","route_poll"]:
		if signature == _last_signature.get(sample_key,"") and now-int(_last_emit_usec.get(sample_key,0)) < 1000000: return
	_last_signature[sample_key] = signature
	_last_emit_usec[sample_key] = now
	print("RECOVERY_NET ",JSON.stringify(record))
	_max_gap_usec = 0
