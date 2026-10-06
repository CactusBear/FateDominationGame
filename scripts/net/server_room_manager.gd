class_name ServerRoomManager
extends RefCounted

var rooms: Dictionary = {}
var error: String = ""
var max_rooms: int = 16
var internal_port_base: int = 52000
var startup_seconds: float = 30.0
var storage_root: String = "user://server_rooms"
var supervisor_timeout_seconds: float = 5.0
var _pulse_msec: int = 0
var _pulse_version: int = 0

func create_room(name: String, settings: Dictionary, data_root: String) -> String:
	error = ""
	if name.strip_edges().is_empty() or rooms.size() >= max_rooms or not is_finite(startup_seconds) or startup_seconds <= 0 or not is_finite(supervisor_timeout_seconds) or supervisor_timeout_seconds <= 1 or internal_port_base <= 0 or internal_port_base + max_rooms > 65536:
		error = "房间名称或服务端资源预算无效"
		return ""
	var state = preload("res://scripts/net/room_state.gd").new()
	if not state.configure(1, settings):
		error = state.error
		return ""
	var port := -1
	for candidate in range(internal_port_base, internal_port_base + max_rooms):
		if not rooms.values().any(func(room): return room.port == candidate):
			port = candidate
			break
	if port < 0:
		error = "内部房间端口预算已用尽"
		return ""
	var id: String = Crypto.new().generate_random_bytes(16).hex_encode()
	var directory := storage_root.path_join(id)
	if DirAccess.dir_exists_absolute(directory) or DirAccess.make_dir_recursive_absolute(directory) != OK:
		error = "无法建立房间专属目录"
		return ""
	var config := FileAccess.open(directory.path_join("config.json"), FileAccess.WRITE)
	if config == null:
		error = "无法写入房间启动配置"
		return ""
	var stored_settings := settings.duplicate(true)
	if stored_settings.has("runtime_guard"):
		stored_settings.runtime_guard = preload("res://scripts/match/rule_budget.gd").encode_json_config(stored_settings.runtime_guard)
	config.store_string(JSON.stringify({"id": id, "name": name, "settings": stored_settings, "data_root": ProjectSettings.globalize_path(data_root), "directory": ProjectSettings.globalize_path(directory), "port": port, "supervisor_timeout_seconds": supervisor_timeout_seconds}))
	config.close()
	var arguments := PackedStringArray(["--headless", "--audio-driver", "Dummy", "--path", ProjectSettings.globalize_path("res://"), "--log-file", ProjectSettings.globalize_path(directory.path_join("engine.log")), "--scene", "res://assets/scenes/main_menu/server_room_worker.tscn", "--", "--server-room-worker", ProjectSettings.globalize_path(directory.path_join("config.json"))])
	var pid := OS.create_process(OS.get_executable_path(), arguments)
	if pid < 0:
		error = "无法启动房间子进程"
		return ""
	rooms[id] = {"id": id, "name": name, "port": port, "pid": pid, "directory": directory, "ready": false, "error": "", "deadline": Time.get_ticks_msec() + int(startup_seconds * 1000.0)}
	return id

func poll() -> void:
	if Time.get_ticks_msec() - _pulse_msec >= 1000:
		_pulse_msec = Time.get_ticks_msec()
		_pulse_version += 1
		for room in rooms.values():
			var heartbeat := FileAccess.open(room.directory.path_join("supervisor.json"), FileAccess.WRITE)
			if heartbeat != null:
				heartbeat.store_string(JSON.stringify({"id": room.id, "version": _pulse_version}))
				heartbeat.close()
	for room in rooms.values():
		if not OS.is_process_running(room.pid):
			room.ready = false
			if room.error.is_empty():
				room.error = "房间进程已经退出"
			continue
		if room.ready or not room.error.is_empty():
			continue
		var path: String = room.directory.path_join("ready.json")
		if FileAccess.file_exists(path):
			var report = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not report is Dictionary or report.get("id") != room.id or report.get("port") != room.port or report.get("pid") != room.pid or report.get("ok") != true:
				room.error = "房间就绪报告无效"
			else:
				var logs := FileAccess.get_file_as_string(room.directory.path_join("engine.log"))
				if "ERROR:" in logs or "SCRIPT ERROR" in logs:
					room.error = "房间启动出现引擎错误"
				else:
					room.ready = true
		if not room.ready and Time.get_ticks_msec() >= room.deadline:
			room.error = "房间启动超时"
		if not room.error.is_empty():
			OS.kill(room.pid)

func is_ready(id: String) -> bool:
	return rooms.has(id) and rooms[id].ready

func stop_room(id: String) -> bool:
	if not rooms.has(id):
		return false
	var pid: int = rooms[id].pid
	if OS.is_process_running(pid) and OS.kill(pid) != OK:
		error = "无法停止自己的房间进程"
		return false
	rooms.erase(id)
	return true

func close() -> void:
	for id in rooms.keys():
		stop_room(id)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for room in rooms.values():
			if OS.is_process_running(room.pid):
				OS.kill(room.pid)
