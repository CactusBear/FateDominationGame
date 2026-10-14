extends Node

var _progress_path:String = ""
var _progress_sequence:int = 0
var _progress_second:int = -1

## 独立进程入口：参数与输出位置仅由本机任务管理器提供。
func _ready() -> void:
	var ready_usec:int = Time.get_ticks_usec()
	var timing:Dictionary = {"ready_since_engine_usec":ready_usec,"reread_usec":0,"reread_hash_usec":0,"cache_store_usec":0,"source_register_usec":0,"second_json_usec":0}
	# 仅本机隔离验收显式启用；正常报告与诊断不输出用户绝对路径。
	if OS.get_environment("HERMES_VALIDATION_USER_PROBE") == "1":
		var receipt:Dictionary = {"pid":OS.get_process_id(),"path":OS.get_user_data_dir(),"worker_pool_max_threads":ProjectSettings.get_setting("threading/worker_pool/max_threads")}
		var probe := FileAccess.open("user://validation-probe-%d.json" % OS.get_process_id(), FileAccess.WRITE)
		if probe == null:
			get_tree().quit(2)
			return
		probe.store_string(JSON.stringify(receipt))
		probe.close()
		print("ROOM_VALIDATION_USER_PROBE ",JSON.stringify(receipt))
	var args := OS.get_cmdline_user_args()
	args.erase("--room-data-validation-worker")
	if args.size() not in [3,4]:
		push_error("数据校验需要数据目录、批准清单、报告路径")
		get_tree().quit(2)
		return
	var validator = preload("res://scripts/net/validation/room_data_validator.gd").new()
	validator.profile_enabled = true
	var manifest = validator.parse_manifest(FileAccess.get_file_as_string(args[1]))
	var report := {"ok": false, "errors": [], "masters": 0, "servants": 0}
	if not manifest is Array:
		report.errors.append("批准清单不是数组")
	else:
		var initial_usec:int = Time.get_ticks_usec()
		if not validator.validate(args[0], manifest):
			report.errors = validator.errors.duplicate()
		else:
			timing.initial_validation_usec = Time.get_ticks_usec() - initial_usec
			timing.initial_file_profile = validator.performance.duplicate()
			var cache = preload("res://scripts/net/content/content_cache.gd").new()
			cache.root = args[2].get_base_dir().path_join("validation-cache")
			cache.max_file_bytes = validator.max_file_bytes
			var documents:Array = prepare_approved_files(args[0], manifest, cache, report, timing)
			var analysis = preload("res://scripts/net/validation/rule_loop_analysis.gd").new()
			analysis.max_depth = validator.max_json_depth
			var analysis_usec:int = Time.get_ticks_usec()
			report.loop_analysis = analysis.inspect(documents)
			timing.loop_analysis_usec = Time.get_ticks_usec() - analysis_usec
			documents.clear()
			if report.loop_analysis.truncated:
				report.errors.append_array(report.loop_analysis.errors)
			var assembler = preload("res://scripts/net/content/room_data_assembler.gd").new()
			var isolated_root := args[2].get_base_dir().path_join("validation-data")
			if report.errors.is_empty():
				var assemble_usec:int = Time.get_ticks_usec()
				if not assembler.assemble(isolated_root, manifest, cache):
					report.errors.append(assembler.error)
					report.assembly_diagnostic = assembler.diagnostic.duplicate()
				timing.assembly_usec = Time.get_ticks_usec() - assemble_usec
			# 源登记只在本次组装存活；不跨请求缓存可变源的批准。
			assembler = null
			cache = null
			report.performance = timing
			if report.errors.is_empty():
				if not await _inspect_loaded_content(report, args, isolated_root):
					get_tree().quit(2)
					return
	timing.worker_total_usec = Time.get_ticks_usec() - ready_usec
	report.performance = timing
	if not _write_report(args[2],report):
		push_error("无法写出数据校验报告")
		get_tree().quit(2)
		return
	print("ROOM_DATA_VALIDATION ", JSON.stringify(report))
	get_tree().quit(0 if report.ok else 1)

## 初检之后仍定长复读并哈希。只登记现有安全来源能力，不物化中间 blob。
## 单文件字节上限沿用 cache.max_file_bytes；register/fetch 自己复读并验路径及摘要。
## 不保留字节数组，最多当前 content 与登记调用栈内的另一份单文件缓冲。
func prepare_approved_files(directory:String, manifest:Array, cache, report:Dictionary, timing:Dictionary) -> Array:
	var documents:Array = []
	for item in manifest:
		var reread_usec:int = Time.get_ticks_usec()
		var source:String = directory.path_join(item.path)
		var input := FileAccess.open(source, FileAccess.READ)
		if input == null:
			report.errors.append("无法复读批准文件：" + item.path)
			break
		if input.get_length() != item.size or item.size > cache.max_file_bytes:
			input.close()
			report.errors.append("批准文件大小在校验后变化：" + item.path)
			break
		var content:PackedByteArray = input.get_buffer(item.size)
		var read_error:Error = input.get_error()
		var same_size:bool = input.get_length() == item.size
		input.close()
		if read_error != OK or not same_size or content.size() != item.size:
			report.errors.append("批准文件复读长度校验失败：" + item.path)
			break
		timing.reread_usec += Time.get_ticks_usec() - reread_usec
		var hash_usec:int = Time.get_ticks_usec()
		var matching:bool = preload("res://scripts/net/content/content_cache.gd").digest(content) == item.hash
		timing.reread_hash_usec += Time.get_ticks_usec() - hash_usec
		if not matching:
			report.errors.append("批准文件复读校验失败：" + item.path)
			break
		var register_usec:int = Time.get_ticks_usec()
		var registered:bool = cache.register_verified_source(item.hash, directory, source, item.size)
		timing.source_register_usec += Time.get_ticks_usec() - register_usec
		if not registered:
			print("ROOM_VALIDATION_CACHE_REJECT ", cache.error)
			report.errors.append("批准文件复读校验失败：" + item.path + "；" + cache.error)
			break
		if item.path.get_extension().to_lower() == "json":
			var json_usec:int = Time.get_ticks_usec()
			var parsed := JSON.new()
			if parsed.parse(content.get_string_from_utf8()) != OK:
				report.errors.append("批准 JSON 复读解析失败：" + item.path)
				break
			documents.append({"path": item.path, "provider": "", "data": parsed.data})
			timing.second_json_usec += Time.get_ticks_usec() - json_usec
	return documents

func _inspect_loaded_content(report: Dictionary, args: PackedStringArray, isolated_root: String) -> bool:
	var release_usec:int = Time.get_ticks_usec()
	GameData.release_game_objects()
	report.performance.release_usec = Time.get_ticks_usec() - release_usec
	var environment = preload("res://scripts/system/global/content_environment.gd")
	var token: Dictionary = environment.install(isolated_root, args[2].get_base_dir().path_join("stored_jsons.dat"))
	var load_usec:int = Time.get_ticks_usec()
	LoadGame.reload_game(func(message:String): report.errors.append(message))
	report.performance.load_usec = Time.get_ticks_usec() - load_usec
	report.masters = GameData.loaded_masters.size()
	report.servants = GameData.loaded_servants.size()
	if GameData.loaded_masters.is_empty() or GameData.loaded_servants.is_empty():
		report.errors.append("所选数据缺少可加载的御主或从者")
	if report.errors.is_empty() and args.size() == 4:
		var simulation_options = JSON.parse_string(FileAccess.get_file_as_string(args[3]))
		report.ok = true
		report.random_simulation = {"ok":false,"status":"running","warnings":[],"errors":[]}
		if not _write_report(args[2],report):
			environment.restore(token)
			assert(LoadHelper.session_data_dir == token.session_data_dir and LoadGame.stored_jsons_path == token.stored_jsons_path, "中途失败后全局值已恢复")
			return false
		# 模拟仍依赖加载环境；必须等 await 返回之后再恢复。
		var simulation_usec:int = Time.get_ticks_usec()
		_progress_path = args[2].get_base_dir().path_join("progress.json")
		report.random_simulation = await _simulate(simulation_options, isolated_root)
		report.performance.simulation_usec = Time.get_ticks_usec() - simulation_usec
		for warning in report.random_simulation.get("warnings", []):
			report.loop_analysis.warnings.append({"kind":"random_simulation","message":warning})
		if not report.random_simulation.ok: report.errors.append_array(report.random_simulation.errors)
	else:
		report.random_simulation = {"configured":false, "cases":[], "warnings":["未配置随机模拟，本次仅做静态和加载校验"]}
	report.ok = report.errors.is_empty()
	var restore_usec:int = Time.get_ticks_usec()
	environment.restore(token)
	assert(LoadHelper.session_data_dir == token.session_data_dir and LoadGame.stored_jsons_path == token.stored_jsons_path, "中途失败后全局值已恢复")
	report.performance.environment_restore_usec = Time.get_ticks_usec() - restore_usec
	return true

func _write_report(path:String, report:Dictionary) -> bool:
	var temporary:String = path + ".tmp"
	var output := FileAccess.open(temporary, FileAccess.WRITE)
	if output == null: return false
	output.store_string(JSON.stringify(report))
	output.flush()
	var result:Error = output.get_error()
	output.close()
	return result == OK and DirAccess.rename_absolute(temporary,path) == OK

func _simulate(options:Variant, root:String) -> Dictionary:
	var invalid:Dictionary = {"ok":false,"errors":["随机模拟配置无效"],"cases":[]}
	if not options is Dictionary or not options.get("enabled") is bool or not (options.get("seconds") is int or options.get("seconds") is float): return invalid
	var simulation = preload("res://scripts/net/validation/rule_random_simulation.gd").new()
	simulation.progress.connect(_publish_progress)
	if not options.enabled or options.seconds == 0:
		return await simulation.run(get_tree(), {}, [], options.enabled, float(options.seconds), {})
	if not options.get("selection_mode") is String or not options.get("player_ids") is Array or not options.get("guard") is Dictionary: return invalid
	var player_ids:Array = []
	for number in options.player_ids:
		if not (number is int or number is float) or not is_finite(float(number)) or number < 0 or number > 2147483647 or floor(float(number)) != number: return invalid
		player_ids.append(int(number))
	var guard:Dictionary = preload("res://scripts/match/rule_budget.gd").decode_json_config(options.guard)
	var seeds:Array = []
	if not options.get("seeds", []) is Array: return invalid
	for value in options.get("seeds", []):
		if not value is String or not value.is_valid_int() or str(value.to_int()) != value: return invalid
		seeds.append(value.to_int())
	var modes = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("selection_modes.json")))
	if not modes is Dictionary or not modes.get("modes") is Array: return invalid
	var matches:Array = modes.modes.filter(func(mode): return mode is Dictionary and mode.get("id") == options.selection_mode)
	if matches.size() != 1: return invalid
	return await simulation.run(get_tree(), matches[0], player_ids, options.enabled, float(options.seconds), guard, seeds)

## 进度单独原子发布，不覆盖完整静态检查点；写失败不能冒充校验成功。
func _publish_progress(budget_seconds:float, remaining_seconds:float) -> void:
	var second:int = ceili(remaining_seconds)
	if _progress_path.is_empty() or second == _progress_second: return
	_progress_second = second
	_progress_sequence += 1
	_write_report(_progress_path, {"phase":"simulation", "budget_seconds":budget_seconds, "remaining_seconds":remaining_seconds, "sequence":_progress_sequence})
