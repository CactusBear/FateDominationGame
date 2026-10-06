class_name RoomValidationTask
extends RefCounted

var running: bool = false
var complete: bool = false
var error: String = ""
var report: Dictionary = {}
var process_id: int = -1
var directory: String = ""
var approved_files: Array = []
var _deadline: int = 0

## 路径均由本机调用方给出；网络消息不能指定进程参数或报告位置。
func start(data_directory: String, files: Array, timeout_seconds: float) -> bool:
	cancel()
	if running:
		return false
	complete = false
	report = {}
	approved_files = files.duplicate(true)
	error = ""
	if not is_finite(timeout_seconds) or timeout_seconds <= 0:
		error = "数据校验时间预算无效"
		return false
	var validator = preload("res://scripts/net/room_data_validator.gd").new()
	var assembler = preload("res://scripts/net/room_data_assembler.gd").new()
	if not assembler.validate(files, validator.max_file_bytes):
		error = assembler.error
		return false
	directory = "user://room_validation/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if DirAccess.dir_exists_absolute(directory) or DirAccess.make_dir_recursive_absolute(directory) != OK:
		error = "无法创建独立校验目录"
		return false
	var manifest := FileAccess.open(directory.path_join("manifest.json"), FileAccess.WRITE)
	if manifest == null:
		error = "无法写入校验清单"
		return false
	manifest.store_string(JSON.stringify(files))
	manifest.close()
	var arguments := PackedStringArray(["--headless", "--audio-driver", "Dummy", "--fixed-fps", "60", "--path", ProjectSettings.globalize_path("res://"), "--log-file", ProjectSettings.globalize_path(directory.path_join("engine.log")), "--scene", "res://assets/scenes/main_menu/room_data_validation_worker.tscn", "--", "--room-data-validation-worker", ProjectSettings.globalize_path(data_directory), ProjectSettings.globalize_path(directory.path_join("manifest.json")), ProjectSettings.globalize_path(directory.path_join("report.json"))])
	process_id = OS.create_process(OS.get_executable_path(), arguments)
	if process_id < 0:
		error = "无法启动独立数据校验进程"
		return false
	_deadline = Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	running = true
	return true

func poll() -> void:
	if not running:
		return
	if OS.is_process_running(process_id):
		if Time.get_ticks_msec() >= _deadline:
			cancel()
			error = "独立数据校验超时"
		return
	process_id = -1
	running = false
	var log_path := directory.path_join("engine.log")
	var report_path := directory.path_join("report.json")
	if not FileAccess.file_exists(report_path) or not FileAccess.file_exists(log_path):
		error = "校验进程未完整写出报告与引擎日志"
		return
	var logs := FileAccess.get_file_as_string(log_path)
	for line in logs.split("\n"):
		if "SCRIPT ERROR" in line or "SHADER ERROR" in line or "ERROR:" in line:
			error = "隔离加载失败：" + line.strip_edges()
			return
	var decoded = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	if not decoded is Dictionary or not decoded.get("ok") is bool or not decoded.get("errors") is Array:
		error = "校验报告格式无效"
		return
	report = decoded
	complete = report.ok and report.errors.is_empty()
	if not complete:
		error = "\n".join(report.errors) if not report.errors.is_empty() else "数据校验失败"

func cancel() -> void:
	if process_id >= 0 and OS.is_process_running(process_id):
		if OS.kill(process_id) != OK:
			error = "无法终止本次校验进程"
			return
	process_id = -1
	running = false
	complete = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and process_id >= 0 and OS.is_process_running(process_id):
		OS.kill(process_id)
