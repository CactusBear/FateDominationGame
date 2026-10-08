class_name ServerRoomManager
extends RefCounted

var rooms: Dictionary = {}
var error: String = ""
var max_rooms: int = 16
var internal_port_base: int = 52000
var internal_port_count:int = 128
var startup_seconds: float = 30.0
var storage_root: String = "user://server_rooms"
## 本机部署职责，不接受公开 settings 覆盖；LAN/P2P 由房主机器创建此管理器。
var authority_host_mode:String = "dedicated"
const AUTHORITY_HOST_MODES = ["lan", "p2p", "dedicated"]
var record_matches:bool = false
var transaction_log:bool = true
var recovery_key_mismatch:String = "reject"
var recovery_inheritance:String = "host_select"
var identity_binding_required:bool = false
const RecoveryPaths = preload("res://scripts/net/server/recovery_path_safety.gd")
const AtomicReplace = preload("res://scripts/io/atomic_file_replace.gd")
const ValidatedContent = preload("res://scripts/io/validated_file_content.gd")
## 只由本机主管设置；绝不从恢复配置接受新的批准根。
var approved_data_root:String = ""

func _approved_root() -> String:
	return approved_data_root if not approved_data_root.is_empty() else LoadHelper.resolve_path(LoadHelper.DATA_DIR_NAME)

func _safe_recovery_config(id:String, directory:String, config:Dictionary, maintenance:Callable = Callable()) -> bool:
	return valid_instance_id(id) and RecoveryPaths.same(directory, storage_root.path_join(id)) and RecoveryPaths.checked(storage_root, directory) and config.get("directory") is String and RecoveryPaths.same(config.directory, directory) and config.get("data_root") is String and RecoveryPaths.checked(_approved_root(), config.data_root) and RecoveryPaths.tree(_approved_root(), config.data_root, [20000], 0, maintenance) and RecoveryPaths.checked(directory, directory.path_join("config.json")) and RecoveryPaths.checked(directory, directory.path_join("recovery.json"), true) and RecoveryPaths.checked(directory, directory.path_join("matches"), true)

func configure_server_policy(policy:Dictionary) -> bool:
	error = ""
	# 管理器再次逐字段校验，避免非 CLI 入口绕过约束。
	if not policy.get("authority_host_mode") is String or policy.authority_host_mode not in AUTHORITY_HOST_MODES:
		error = "权威位置策略无效"
		return false
	if not policy.get("transaction_log") is bool or not policy.get("recovery_key_mismatch") is String or policy.recovery_key_mismatch != "reject" or not policy.get("recovery_inheritance") is String or policy.recovery_inheritance != "host_select":
		error = "服务端策略字段无效"
		return false
	authority_host_mode = policy.authority_host_mode
	transaction_log = policy.transaction_log
	recovery_key_mismatch = policy.recovery_key_mismatch
	recovery_inheritance = policy.recovery_inheritance
	return true

static func valid_instance_id(value:Variant) -> bool:
	if not value is String or value.length() != 32: return false
	for character in value:
		if character not in "0123456789abcdef": return false
	return true

static func matches_instance(room:Dictionary, pid:int, instance_id:String) -> bool:
	return room.get("pid") == pid and room.get("instance_id") == instance_id and valid_instance_id(instance_id)

## 主管私有原生所有者；令牌只存于本机内存，不从恢复文件认领 PID。
var _process_owner:RefCounted
var _retired_close_bindings:Dictionary = {}
const PROCESS_OWNERSHIP_UNAVAILABLE:String = "原生工作进程所有权验证不可用；禁止启动、恢复或操作未验证的进程，原目录保留"

func process_ownership_available() -> bool:
	if not is_instance_valid(_process_owner):
		_process_owner = null
	if _process_owner == null:
		if not ClassDB.class_exists("FateProcessOwner"): return false
		_process_owner = ClassDB.instantiate("FateProcessOwner")
	return _process_owner != null and _process_owner.call("available") == true

func _process_state(room:Dictionary) -> int:
	if _process_owner == null or not room.get("process_token") is String: return -1
	return int(_process_owner.call("state", room.process_token, int(room.pid)))

func _terminate_process(room:Dictionary) -> bool:
	if _process_owner == null or not room.get("process_token") is String: return false
	return _process_owner.call("terminate", room.process_token, int(room.pid)) == true

func _release_process(room:Dictionary) -> bool:
	if _process_owner == null or not room.get("process_token") is String: return false
	return _process_owner.call("release", room.process_token, int(room.pid)) == true

func instance_binding(id:String) -> Dictionary:
	if not rooms.has(id): return {}
	var room:Dictionary = rooms[id]
	if not valid_instance_id(room.get("instance_id")) or room.get("authority_host_mode") not in AUTHORITY_HOST_MODES: return {}
	return {"room":id,"pid":room.pid,"instance_id":room.instance_id,"authority_host_mode":room.authority_host_mode}

func binding_matches(binding:Dictionary, require_ready:bool = false) -> bool:
	if not binding.get("room") is String or not rooms.has(binding.room): return false
	var room:Dictionary = rooms[binding.room]
	if not binding.get("pid") is int or not binding.get("instance_id") is String or room.get("id") != binding.room or binding.get("authority_host_mode") not in AUTHORITY_HOST_MODES: return false
	if not matches_instance(room,binding.pid,binding.instance_id) or binding.get("authority_host_mode") != room.get("authority_host_mode"): return false
	if not require_ready: return true
	return room.get("ready",false) and binding.pid > 0 and process_identity_verified(binding)

func process_identity_verified(binding:Dictionary) -> bool:
	if not process_ownership_available():
		error = PROCESS_OWNERSHIP_UNAVAILABLE
		return false
	if not binding_matches(binding) or binding.pid <= 0: return false
	var room:Dictionary = rooms[binding.room]
	if not room.get("process_token") is String: return false
	return _process_owner.call("verify", room.process_token, binding.pid) == true

## UNKNOWN 不等于 EXITED；不允许调用方退回裸 PID 判活。
func process_state_for_binding(binding:Dictionary) -> int:
	if not process_ownership_available() or not binding_matches(binding): return -1
	var room:Dictionary = rooms[binding.room]
	if not room.get("process_token") is String or str(room.process_token).is_empty(): return -1
	return _process_state(room)

func hold_process_supervision(id:String, request_id:String) -> bool:
	if not valid_instance_id(request_id) or process_state_for_binding(instance_binding(id)) != 1: return false
	if rooms[id].get("close_supervision",false) and rooms[id].get("close_request_id") != request_id: return false
	rooms[id]["close_request_id"] = request_id
	rooms[id]["close_supervision"] = true
	return true

## 仅撤销当前绑定的关闭监督，不 release、不终止进程、不改变 ready/error。
## 调用方只在发布失败或完整绑定的最终拒绝后调用；超时/UNKNOWN 不属于拒绝。
func cancel_process_supervision(binding:Dictionary, request_id:String) -> bool:
	if not binding_matches(binding) or rooms[binding.room].get("close_request_id") != request_id: return false
	rooms[binding.room]["close_supervision"] = false
	rooms[binding.room].erase("close_request_id")
	return true

## 只保留已由真实句柄确认退出、成功 release 的那一个 close 请求身份。
## 此历史证据仅用于最终回执读取，不参与判活、恢复或 terminate。
## 未确认保存的退出证据只授权回执读取，不授权判活、恢复或停止新实例。
func retired_binding_for_request(id:String, request_id:String) -> Dictionary:
	var binding:Dictionary = _retired_close_bindings.get(request_id,{})
	return binding.duplicate(true) if binding.get("room") == id else {}

func retire_unconfirmed_close(binding:Dictionary, request_id:String) -> bool:
	if not release_process_for_binding(binding,request_id): return false
	_retired_close_bindings[request_id] = binding.merged({"request_id":request_id})
	rooms[binding.room].erase("closed_process_binding")
	return true

func closed_binding_for_request(id:String, request_id:String) -> Dictionary:
	var room:Dictionary = rooms.get(id,{})
	var closed:Dictionary = room.get("closed_process_binding",{})
	if room.get("pid") != -1 or room.get("process_token","") != "": return {}
	if closed.get("request_id") != request_id or closed.get("room") != id: return {}
	if closed.get("instance_id") != room.get("instance_id") or closed.get("authority_host_mode") != room.get("authority_host_mode"): return {}
	return closed.duplicate(true)

func release_process_for_binding(binding:Dictionary, request_id:String) -> bool:
	if not valid_instance_id(request_id) or process_state_for_binding(binding) != 0: return false
	var room:Dictionary = rooms[binding.room]
	if not room.get("close_supervision",false) or room.get("close_request_id") != request_id or not _release_process(room): return false
	var closed:Dictionary = binding.duplicate(true)
	closed["request_id"] = request_id
	room.closed_process_binding = closed
	room.pid = -1
	room.process_token = ""
	room.close_supervision = false
	room.erase("close_request_id")
	room.ready = false
	return true

static func valid_ready_report(room:Dictionary, report:Variant) -> bool:
	if not report is Dictionary: return false
	if not report.get("capabilities") is Dictionary: return false
	for key in ["root_transaction_rollback", "can_rollback_now", "execution_trace", "root_transaction_audit", "transaction_audit_persistence_enabled", "match_recording_enabled", "process_restart_is_rollback"]:
		if not report.capabilities.get(key) is bool: return false
	if report.capabilities.process_restart_is_rollback: return false
	return report.get("ok") == true and report.get("room_id") == room.id and report.get("id") == room.id and report.get("port") == room.port and report.get("pid") == room.pid and report.get("instance_id") == room.instance_id and valid_instance_id(report.instance_id) and report.get("instance") == room.instance_id and report.get("authority_host_mode") == room.authority_host_mode

static func write_configuration(path:String, config:Dictionary) -> bool:
	var temporary:String = path + ".%d.tmp" % OS.get_process_id()
	if not RecoveryPaths.checked(path.get_base_dir(), path, true) or not RecoveryPaths.checked(path.get_base_dir(), temporary, true): return false
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return false
	var encoded: PackedByteArray = JSON.stringify(config).to_utf8_buffer()
	file.store_buffer(encoded)
	file.flush()
	var result:Error = file.get_error()
	file.close()
	if result == OK and RecoveryPaths.checked(path.get_base_dir(), temporary) and RecoveryPaths.checked(path.get_base_dir(), path, true) and ValidatedContent.matches_bytes(temporary, encoded):
		if FileAccess.file_exists(path):
			if AtomicReplace.replace_validated_file(temporary, path, encoded.size()).get("ok", false) == true: return true
		elif not DirAccess.dir_exists_absolute(path) and DirAccess.rename_absolute(temporary, path) == OK:
			return true
	if RecoveryPaths.checked(path.get_base_dir(), temporary): DirAccess.remove_absolute(temporary)
	return false
var data_settings:Dictionary = {}
var supervisor_timeout_seconds: float = 5.0
var _pulse_msec: int = 0
var _pulse_version: int = 0

func create_room(name: String, settings: Dictionary, data_root: String) -> String:
	error = ""
	if not process_ownership_available():
		error = PROCESS_OWNERSHIP_UNAVAILABLE
		return ""
	if not RecoveryPaths.checked(data_root, data_root) or not RecoveryPaths.tree(data_root, data_root, [20000]):
		error = "批准数据根必须是无链接的规范本机目录"
		return ""
	if approved_data_root.is_empty(): approved_data_root = data_root
	if not RecoveryPaths.checked(_approved_root(), data_root):
		error = "数据根不在本机批准范围"
		return ""
	if not DirAccess.dir_exists_absolute(storage_root):
		var storage_absolute:String = RecoveryPaths.absolute(storage_root)
		var approved_parent:String = storage_absolute.get_base_dir()
		while not approved_parent.is_empty() and not DirAccess.dir_exists_absolute(approved_parent):
			var next_parent:String = approved_parent.get_base_dir()
			if next_parent == approved_parent: break
			approved_parent = next_parent
		if approved_parent.is_empty() or not RecoveryPaths.checked(approved_parent, storage_absolute, true) or DirAccess.make_dir_recursive_absolute(storage_absolute) != OK or not RecoveryPaths.checked(storage_root, storage_root):
			error = "房间存储根不可安全建立"
			return ""
	if not RecoveryPaths.checked(storage_root, storage_root):
		error = "房间存储根包含链接或非规范路径"
		return ""
	if authority_host_mode not in AUTHORITY_HOST_MODES:
		error = "权威位置必须显式声明为 lan、p2p 或 dedicated"
		return ""
	if name.strip_edges().is_empty() or rooms.size() >= max_rooms or not is_finite(startup_seconds) or startup_seconds <= 0 or not is_finite(supervisor_timeout_seconds) or supervisor_timeout_seconds <= 1 or internal_port_base <= 0 or internal_port_base > 65535 or internal_port_count <= 0 or internal_port_count > 65536 - internal_port_base:
		error = "房间名称或服务端资源预算无效"
		return ""
	var state = preload("res://scripts/net/session/room_state.gd").new()
	settings = settings.duplicate(true)
	for key in data_settings:
		if key not in ["random_sim_enabled", "random_sim_budget_sec"]:
			error = "服务端数据策略字段无效"
			return ""
		if not settings.has(key): settings[key] = data_settings[key]
	if not state.configure(1, settings):
		error = state.error
		return ""
	var port := -1
	for candidate in range(internal_port_base, internal_port_base + internal_port_count):
		if not rooms.values().any(func(room): return room.port == candidate):
			var probe := PacketPeerUDP.new()
			var result:Error = probe.bind(candidate, "127.0.0.1")
			probe.close()
			if result == OK:
				port = candidate
				break
	if port < 0:
		error = "配置的内部端口范围内无可绑定端口"
		return ""
	var id: String = Crypto.new().generate_random_bytes(16).hex_encode()
	var directory := storage_root.path_join(id)
	if DirAccess.dir_exists_absolute(directory) or DirAccess.make_dir_recursive_absolute(directory) != OK:
		error = "无法建立房间专属目录"
		return ""
	var instance_id:String = Crypto.new().generate_random_bytes(16).hex_encode()
	var log_file:String = directory.path_join("engine.%s.log" % instance_id)
	var stored_settings := settings.duplicate(true)
	stored_settings["_gateway_identity_required"] = identity_binding_required
	if stored_settings.has("runtime_guard"):
		stored_settings.runtime_guard = preload("res://scripts/match/rule_budget.gd").encode_json_config(stored_settings.runtime_guard)
	if not write_configuration(directory.path_join("config.json"), {"id": id, "name": name, "settings": stored_settings, "data_root": ProjectSettings.globalize_path(data_root), "directory": ProjectSettings.globalize_path(directory), "port": port, "supervisor_timeout_seconds": supervisor_timeout_seconds, "record_matches":record_matches, "transaction_log":transaction_log, "recovery_key_mismatch":recovery_key_mismatch, "recovery_inheritance":recovery_inheritance, "authority_host_mode":authority_host_mode, "instance_id":instance_id}):
		error = "无法写入房间启动配置"
		return ""
	var arguments := PackedStringArray(["--headless", "--audio-driver", "Dummy", "--path", ProjectSettings.globalize_path("res://"), "--log-file", ProjectSettings.globalize_path(log_file), "--scene", "res://assets/scenes/main_menu/server_room_worker.tscn", "--", "--server-room-worker", ProjectSettings.globalize_path(directory.path_join("config.json")), ProjectSettings.globalize_path(_approved_root()), ProjectSettings.globalize_path(storage_root)])
	if not process_ownership_available():
		error = PROCESS_OWNERSHIP_UNAVAILABLE
		return ""
	var startup_deadline:int = _startup_now_msec() + int(startup_seconds * 1000.0)
	var spawned:Dictionary = _process_owner.call("spawn", OS.get_executable_path(), preload("res://scripts/net/server/server_bootstrap.gd").process_arguments(arguments))
	var pid:int = int(spawned.get("pid", -1))
	if pid < 0 or not spawned.get("token", "") is String or str(spawned.token).is_empty():
		error = "无法启动房间子进程"
		return ""
	rooms[id] = {"id": id, "name": name, "port": port, "pid": pid, "process_token":str(spawned.get("token", "")), "instance_id":instance_id, "authority_host_mode":authority_host_mode, "directory": directory, "log_file": log_file, "ready": false, "error": "", "deadline": startup_deadline}
	return id

func poll() -> void:
	if not process_ownership_available():
		error = PROCESS_OWNERSHIP_UNAVAILABLE
		for room in rooms.values():
			room.ready = false
			# 能力缺失只撤销 ready；不得留下恢复后触发 terminate 的进程错误。
		return
	if Time.get_ticks_msec() - _pulse_msec >= 1000:
		_pulse_msec = Time.get_ticks_msec()
		_pulse_version += 1
		for room in rooms.values():
			if (room.error.is_empty() or room.get("close_supervision",false)) and _process_state(room) == 1: _write_supervisor(room)
	for room in rooms.values():
		var process_state:int = _process_state(room)
		if process_state != 1:
			room.ready = false
			# 关闭消费者先读取最终回执，再确认退出并 release，不能提前改 PID。
			if room.get("close_supervision",false): continue
			if process_state < 0 and int(room.pid) > 0:
				error = PROCESS_OWNERSHIP_UNAVAILABLE
				continue
			if process_state == 0 and int(room.pid) > 0 and room.get("process_token", "") is String and not str(room.process_token).is_empty():
				if _release_process(room):
					room.pid = -1
					room.process_token = ""
					continue
				room.error = "无法释放已退出房间的进程所有权；保留原目录"
			if room.error.is_empty():
				room.error = "房间进程已经退出" if process_state == 0 or room.pid <= 0 else PROCESS_OWNERSHIP_UNAVAILABLE
			continue
		# 未决关闭由回执消费者收尾，不以启动超时或 transient UNKNOWN 强杀。
		if room.get("close_supervision",false): continue
		if not room.error.is_empty():
			room.ready = false
			if not _terminate_process(room): room.error = "无法停止自己的房间进程；保留所有权与原目录"
			continue
		if room.ready:
			continue
		# 先检查墙钟：截止后才看到的报告不能让启动预算失效。
		if _startup_now_msec() >= room.deadline:
			room.error = "房间启动超时"
			if not _terminate_process(room): room.error = "无法停止自己的房间进程；保留所有权与原目录"
			continue
		var path: String = room.directory.path_join("ready.json")
		if FileAccess.file_exists(path):
			var report = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not valid_ready_report(room, report):
				room.error = "房间就绪报告无效"
			else:
				# 日志供审计读取，不同步扫描完整日志阻塞路由；就绪由实例报告确认。
				room.capabilities = report.capabilities.duplicate(true)
				room.ready = _process_state(room) == 1 and _startup_now_msec() < room.deadline
		if not room.ready and _startup_now_msec() >= room.deadline:
			room.error = "房间启动超时"
		if not room.error.is_empty():
			if not _terminate_process(room): room.error = "无法停止自己的房间进程；保留所有权与原目录"

func discover_rooms() -> Dictionary:
	var result:Dictionary = {"registered":[],"errors":{}}
	if not DirAccess.dir_exists_absolute(storage_root): return result
	if not RecoveryPaths.checked(storage_root, storage_root):
		result.errors["storage_root"] = "存储根不安全；原目录保留"
		return result
	var storage := DirAccess.open(storage_root)
	for id in DirAccess.get_directories_at(storage_root):
		if rooms.has(id): continue
		if storage.is_link(id):
			result.errors[id] = "不从链接目录恢复房间"
			continue
		var directory:String = storage_root.path_join(id)
		if not valid_instance_id(id) or not RecoveryPaths.checked(storage_root, directory):
			result.errors[id] = "房间目录名称或路径无效；原目录保留"
			continue
		var recovery:String = directory.path_join("recovery.json")
		if not FileAccess.file_exists(recovery): continue
		if not RecoveryPaths.checked(directory, recovery) or not RecoveryPaths.checked(directory, directory.path_join("config.json")):
			result.errors[id] = "恢复文件或配置为链接；原目录保留"
			continue
		var parser := JSON.new()
		var path:String = directory.path_join("config.json")
		if not FileAccess.file_exists(path) or parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
			result.errors[id] = "房间配置不可读"
			continue
		var config:Dictionary = parser.data
		if not _safe_recovery_config(id, directory, config):
			result.errors[id] = "恢复配置越过批准路径或包含链接；原目录保留"
			continue
		if config.get("authority_host_mode") not in AUTHORITY_HOST_MODES or not valid_instance_id(config.get("instance_id")):
			result.errors[id] = "旧房间缺少显式权威位置或实例标识，需管理员迁移；原目录保留"
			continue
		var port_value = config.get("port")
		if config.get("id") != id or not config.get("name") is String or typeof(port_value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(port_value)) or floor(float(port_value)) != port_value or port_value < 1 or port_value > 65535:
			result.errors[id] = "房间配置身份、路径或端口无效"
			continue
		var validation = preload("res://scripts/net/session/lobby_session.gd").new()
		var valid:bool = validation.load_recovery_state(recovery)
		validation.close()
		if not valid:
			result.errors[id] = "恢复状态无效"
			continue
		if rooms.values().any(func(room): return room.port == int(port_value)):
			result.errors[id] = "内部端口与已有登记冲突"
			continue
		rooms[id] = {"id":id,"name":config.name,"port":int(port_value),"pid":-1,"instance_id":config.instance_id,"authority_host_mode":config.authority_host_mode,"directory":directory,"log_file":directory.path_join("engine.%s.log" % config.instance_id),"ready":false,"error":"等待原成员恢复","deadline":0}
		result.registered.append(id)
	return result

## 只观察指定实例；调用方每帧继续 poll，不重置 deadline、不认领新实例。
## 已成功启动的 ready 不因历史启动 deadline 到期而撤销。
func _startup_now_msec() -> int:
	return Time.get_ticks_msec()

func startup_status(binding:Dictionary) -> String:
	if not binding_matches(binding): return "failed"
	var room:Dictionary = rooms[binding.room]
	if not room.error.is_empty() or room.get("close_supervision",false): return "failed"
	if not process_ownership_available(): return "failed"
	if binding_matches(binding,true): return "ready"
	if room.get("ready",false) or process_state_for_binding(binding) != 1: return "failed"
	return "pending" if _startup_now_msec() < room.deadline else "failed"

func is_ready(id: String) -> bool:
	return binding_matches(instance_binding(id),true)

## Guard original registration after native network callbacks; never authorize replacement.
func _recovery_binding_current(binding:Dictionary, room:Dictionary) -> bool:
	return binding_matches(binding) and is_same(rooms.get(binding.get("room")),room) and not room.get("close_supervision",false)

## 仅重启已经落盘的房间子进程；不删除房间目录、配置或既有存档。
## 对局状态恢复由房间工作进程的恢复入口负责，本方法不伪造恢复成功。
func recover_room(id:String, expected_pid:int = -2, expected_instance_id:String = "", maintenance:Callable = Callable()) -> bool:
	error = ""
	if not process_ownership_available():
		error = PROCESS_OWNERSHIP_UNAVAILABLE
		return false
	if not rooms.has(id):
		error = "房间不存在"
		return false
	var room:Dictionary = rooms[id]
	if room.get("close_supervision",false):
		error = "房间安全关闭仍受监督，禁止替换进程实例"
		return false
	if expected_pid != -2 and not matches_instance(room, expected_pid, expected_instance_id):
		error = "房间进程实例已更换，拒绝过期恢复请求"
		return false
	if int(room.pid) > 0:
		var previous_state:int = _process_state(room)
		if previous_state != 0:
			error = "房间仍在运行" if previous_state == 1 else PROCESS_OWNERSHIP_UNAVAILABLE
			return false
	# Callback false is sticky: tree's void maintenance seam cannot clear cancellation.
	var recovery_binding:Dictionary = instance_binding(id)
	var cancelled:Array[bool] = [false]
	var service:Callable = func():
		if maintenance.is_valid() and maintenance.call() != true: cancelled[0] = true
	service.call()
	if cancelled[0] or not _recovery_binding_current(recovery_binding,room):
		error = "恢复请求已取消或实例已更换；原存档保留"
		return false
	var config_path:String = str(room.directory).path_join("config.json")
	if not RecoveryPaths.checked(storage_root, config_path):
		error = "恢复配置路径不安全；原存档保留"
		return false
	if not FileAccess.file_exists(config_path):
		error = "房间启动配置不存在"
		return false
	var config = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if not config is Dictionary or not _safe_recovery_config(id, str(room.directory), config, service):
		error = "恢复配置越过批准路径或包含链接；原存档保留"
		return false
	if not config is Dictionary or config.get("id") != id or config.get("port") != room.port or config.get("instance_id") != room.instance_id or config.get("authority_host_mode") != room.authority_host_mode:
		error = "房间启动配置与登记信息不一致"
		return false
	service.call()
	if cancelled[0] or not _recovery_binding_current(recovery_binding,room):
		error = "恢复请求已取消或实例已更换；原存档保留"
		return false
	var probe:=PacketPeerUDP.new()
	if probe.bind(int(room.port), "127.0.0.1") != OK:
		probe.close()
		error = "房间原内部端口仍被占用"
		return false
	probe.close()
	var instance_id:String = Crypto.new().generate_random_bytes(16).hex_encode()
	config.instance_id = instance_id
	if not _safe_recovery_config(id, str(room.directory), config, service):
		error = "恢复路径在发布配置前失效；原存档保留"
		return false
	service.call()
	if cancelled[0] or not _recovery_binding_current(recovery_binding,room):
		error = "恢复请求已取消或实例已更换；原存档保留"
		return false
	if not write_configuration(config_path, config):
		error = "恢复启动配置发布失败；原存档保留"
		return false
	# 必须在创建进程之前删除旧报告，避免删掉新进程已发布的 ready。
	var ready_path:String = str(room.directory).path_join("ready.json")
	if FileAccess.file_exists(ready_path) and DirAccess.remove_absolute(ready_path) != OK:
		config.instance_id = room.instance_id
		write_configuration(config_path, config)
		error = "无法清除过期就绪报告"
		return false
	var log_file:String = str(room.directory).path_join("engine.%s.log" % instance_id)
	var arguments:=PackedStringArray(["--headless", "--audio-driver", "Dummy", "--path", ProjectSettings.globalize_path("res://"), "--log-file", ProjectSettings.globalize_path(log_file), "--scene", "res://assets/scenes/main_menu/server_room_worker.tscn", "--", "--server-room-worker", ProjectSettings.globalize_path(config_path), ProjectSettings.globalize_path(_approved_root()), ProjectSettings.globalize_path(storage_root)])
	var startup_deadline:int = _startup_now_msec() + int(startup_seconds * 1000.0)
	var spawned:Dictionary = _process_owner.call("spawn", OS.get_executable_path(), preload("res://scripts/net/server/server_bootstrap.gd").process_arguments(arguments))
	var pid:int = int(spawned.get("pid", -1))
	if pid < 0 or not spawned.get("token", "") is String or str(spawned.token).is_empty():
		config.instance_id = room.instance_id
		write_configuration(config_path, config)
		error = "无法重启房间子进程"
		return false
	if int(room.pid) > 0 and room.get("process_token", "") is String and not str(room.process_token).is_empty() and not _release_process(room):
		_process_owner.call("terminate", spawned.token, pid)
		_process_owner.call("release", spawned.token, pid)
		config.instance_id = room.instance_id
		write_configuration(config_path, config)
		error = "旧进程所有权释放失败；恢复失败关闭"
		return false
	room.pid = pid
	room.process_token = str(spawned.get("token", ""))
	room.instance_id = instance_id
	room.log_file = log_file
	room.ready = false
	room.error = ""
	room.deadline = startup_deadline
	rooms[id] = room
	return true

func _write_supervisor(room:Dictionary) -> void:
	var path:String = room.directory.path_join("supervisor.json")
	if not write_configuration(path, {"id":room.id, "pid":room.pid, "instance_id":room.instance_id, "version":_pulse_version}):
		error = "无法完整发布房间主管心跳"

func stop_room(id: String, expected_pid:int = -2, expected_instance_id:String = "") -> bool:
	if not rooms.has(id):
		return false
	if expected_pid != -2 and not matches_instance(rooms[id], expected_pid, expected_instance_id):
		error = "房间进程实例已更换，拒绝过期停止请求"
		return false
	var pid: int = rooms[id].pid
	if pid > 0 and not process_ownership_available():
		error = PROCESS_OWNERSHIP_UNAVAILABLE
		return false
	if pid > 0 and (not _terminate_process(rooms[id]) or not _release_process(rooms[id])):
		error = "无法停止或释放自己的房间进程；保留登记与原目录"
		return false
	rooms.erase(id)
	return true

func close() -> void:
	for id in rooms.keys():
		stop_room(id)

func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE: return
	# PREDELETE 中不能再分派 self 的脚本方法；保留原生所有者的强引用。
	# 原生 terminate 校验 token + PID 并操作创建时持有的 OS 句柄，绝不按裸 PID 认领。
	var owner:RefCounted = _process_owner
	if not is_instance_valid(owner): return
	for room in rooms.values():
		var pid:Variant = room.get("pid")
		var token:Variant = room.get("process_token")
		if not pid is int or pid <= 0 or not token is String or token.is_empty(): continue
		# 只有确认自己的进程退出后才 release；失败留给原生所有者 RAII 收尾。
		if owner.call("terminate", token, pid) == true:
			owner.call("release", token, pid)
