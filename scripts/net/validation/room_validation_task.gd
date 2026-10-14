class_name RoomValidationTask
extends RefCounted

var running: bool = false
var complete: bool = false
var error: String = ""
var report: Dictionary = {}
var process_id: int = -1
## 仅本机配置；不从网络参数或房间设置读取。默认仍为合法 user 目录。
var workspace_root: String = "user://room_validation"
var directory: String = ""
var approved_files: Array = []
var _deadline: int = 0
var _simulation_seconds:float = 0.0
var _progress_sequence:int = 0
var _progress_remaining:float = -1.0
var _progress_received_msec:int = 0
var _next_progress_poll_msec:int = 0

## 路径均由本机调用方给出；网络消息不能指定进程参数或报告位置。
func start(data_directory: String, files: Array, timeout_seconds: float, simulation:Dictionary = {}) -> bool:
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
	if not simulation.is_empty() and (not simulation.get("enabled") is bool or typeof(simulation.get("seconds")) not in [TYPE_INT,TYPE_FLOAT]):
		error = "随机模拟开关或时间类型无效"
		return false
	var configured_seconds:float = float(simulation.get("seconds", 0.0))
	var simulation_seconds:float = configured_seconds if simulation.get("enabled", false) else 0.0
	_simulation_seconds = simulation_seconds
	var started_msec:int = Time.get_ticks_msec()
	if not is_finite(configured_seconds) or configured_seconds < 0 or timeout_seconds + simulation_seconds >= float((9223372036854775807 - started_msec) / 1000):
		error = "随机模拟时间预算无效"
		return false
	_deadline = started_msec + int((timeout_seconds + simulation_seconds) * 1000.0)
	var validator = preload("res://scripts/net/validation/room_data_validator.gd").new()
	var assembler = preload("res://scripts/net/content/room_data_assembler.gd").new()
	if not assembler.validate(files, validator.max_file_bytes):
		error = assembler.error
		return false
	if not _create_directory():
		return false
	var manifest := FileAccess.open(directory.path_join("manifest.json"), FileAccess.WRITE)
	if manifest == null:
		error = "无法写入校验清单"
		return false
	manifest.store_string(JSON.stringify(files))
	manifest.close()
	var engine_arguments := PackedStringArray(["--headless", "--audio-driver", "Dummy", "--fixed-fps", "60", "--path", ProjectSettings.globalize_path("res://"), "--log-file", ProjectSettings.globalize_path(directory.path_join("engine.log"))])
	var role_arguments := PackedStringArray([ProjectSettings.globalize_path(data_directory), ProjectSettings.globalize_path(directory.path_join("manifest.json")), ProjectSettings.globalize_path(directory.path_join("report.json"))])
	if not simulation.is_empty():
		var options:Dictionary = simulation.duplicate(true)
		if options.has("guard"):
			if not options.guard is Dictionary or not preload("res://scripts/match/rule_budget.gd").new().configure(options.guard):
				error = "模拟保护配置无效"
				return false
			options.guard = preload("res://scripts/match/rule_budget.gd").encode_json_config(options.guard)
		if options.has("seeds"):
			if not options.seeds is Array or not options.seeds.all(func(value): return value is int):
				error = "模拟种子无效"
				return false
			options.seeds = options.seeds.map(func(value): return str(value))
		var options_path:String = directory.path_join("simulation.json")
		var options_file:=FileAccess.open(options_path, FileAccess.WRITE)
		if options_file == null:
			error = "无法写入模拟配置"
			return false
		options_file.store_string(JSON.stringify(options))
		options_file.flush()
		var write_error:Error = options_file.get_error()
		options_file.close()
		if write_error != OK:
			error = "无法完整写入模拟配置"
			return false
		role_arguments.append(ProjectSettings.globalize_path(options_path))
	var arguments:PackedStringArray = preload("res://scripts/net/server/server_bootstrap.gd").role_scene_arguments("--room-data-validation-worker", engine_arguments, role_arguments)
	if arguments.is_empty():
		error = "无法构造独立数据校验进程参数"
		return false
	process_id = OS.create_process(OS.get_executable_path(), arguments)
	if process_id < 0:
		error = "无法启动独立数据校验进程"
		return false
	running = true
	return true

## 在任何清单/日志写入前逐层检查祖先；配置不是链接检查豁免。
func _create_directory() -> bool:
	var paths = preload("res://scripts/net/server/recovery_path_safety.gd")
	var root:String = paths.absolute(workspace_root)
	if root.is_empty():
		error = "校验工作目录无效"
		return false
	var ancestor:String = root
	while not DirAccess.dir_exists_absolute(ancestor):
		var parent:String = ancestor.get_base_dir()
		if parent.length() == 2 and parent[1] == ":": parent += "/"
		if parent == ancestor or parent.is_empty():
			error = "校验工作目录无效"
			return false
		ancestor = parent
	if not paths.checked(ancestor, root, true):
		error = "校验工作目录不安全"
		return false
	directory = root.path_join("%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	if not paths.checked(ancestor, directory, true) or FileAccess.file_exists(directory) or DirAccess.dir_exists_absolute(directory) or DirAccess.make_dir_recursive_absolute(directory) != OK:
		error = "无法创建独立校验目录"
		return false
	if not paths.checked(root, directory):
		error = "校验工作目录不安全"
		return false
	return true

func poll() -> void:
	if not running:
		return
	if OS.is_process_running(process_id):
		_poll_progress()
		if Time.get_ticks_msec() >= _deadline:
			cancel()
			if running or process_id >= 0: return
			_read_report(true)
		return
	process_id = -1
	running = false
	_clear_progress()
	_read_report(false)

## 只读取本次独占工作目录的观测文件；不改 report、complete 或截止时间。
func _poll_progress() -> void:
	var now:int = Time.get_ticks_msec()
	if _simulation_seconds <= 0 or now < _next_progress_poll_msec: return
	_next_progress_poll_msec = now + 1000
	var path:String = directory.path_join("progress.json")
	if not FileAccess.file_exists(path): return
	var input := FileAccess.open(path, FileAccess.READ)
	if input == null: return
	var text:String = input.get_as_text()
	input.close()
	var parsed := JSON.new()
	if parsed.parse(text) == OK: _accept_progress(parsed.data, now)

func _accept_progress(value:Variant, received_msec:int) -> bool:
	if not running or _simulation_seconds <= 0 or not value is Dictionary or value.get("phase") != "simulation": return false
	for key in ["budget_seconds", "remaining_seconds", "sequence"]:
		if typeof(value.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value[key])): return false
	var budget:float = float(value.budget_seconds)
	var remaining:float = float(value.remaining_seconds)
	var sequence:float = float(value.sequence)
	if budget != _simulation_seconds or remaining < 0 or remaining > budget or sequence <= _progress_sequence or sequence != floor(sequence) or sequence >= 9223372036854775807.0: return false
	if _progress_remaining >= 0 and remaining > _progress_remaining: return false
	_progress_sequence = int(sequence)
	_progress_remaining = remaining
	_progress_received_msec = received_msec
	return true

func _progress_text(now_msec:int) -> String:
	if not running or _progress_remaining < 0: return ""
	var elapsed:float = float(maxi(0, now_msec - _progress_received_msec)) / 1000.0
	var remaining:float = maxf(0.0, _progress_remaining - elapsed)
	return "随机模拟预算剩余%d秒" % ceili(remaining) if remaining > 0 else "随机模拟预算已用尽，正在收尾"

func status_text() -> String:
	var countdown:String = _progress_text(Time.get_ticks_msec())
	return countdown if not countdown.is_empty() else "正在独立进程中校验所选数据"

func _clear_progress() -> void:
	_simulation_seconds = 0.0
	_progress_sequence = 0
	_progress_remaining = -1.0
	_progress_received_msec = 0
	_next_progress_poll_msec = 0

func _read_report(interrupted:bool) -> void:
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
	var simulation = report.get("random_simulation", {})
	if interrupted and simulation is Dictionary and simulation.get("status") == "running":
		if not report.ok:
			error = "独立数据校验超时，未取得完整静态校验检查点"
			return
		var warning:String = "随机模拟达到隔离进程硬时限，已终止；静态校验已完成，但模拟未完成，不能据此判断是否死循环"
		simulation.status = "hard_timeout"
		simulation.warnings.append(warning)
		report.loop_analysis.warnings.append({"kind":"random_simulation","message":warning})
	elif simulation is Dictionary and simulation.get("status") == "running":
		error = "模拟进程提前退出，拒绝批准未完成报告"
		return
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
	_clear_progress()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and process_id >= 0 and OS.is_process_running(process_id):
		OS.kill(process_id)
