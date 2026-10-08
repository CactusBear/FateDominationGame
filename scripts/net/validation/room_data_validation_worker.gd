extends Node

## 独立进程入口：参数与输出位置仅由本机任务管理器提供。
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	args.erase("--room-data-validation-worker")
	if args.size() not in [3,4]:
		push_error("数据校验需要数据目录、批准清单、报告路径")
		get_tree().quit(2)
		return
	var validator = preload("res://scripts/net/validation/room_data_validator.gd").new()
	var manifest = validator.parse_manifest(FileAccess.get_file_as_string(args[1]))
	var report := {"ok": false, "errors": [], "masters": 0, "servants": 0}
	if not manifest is Array:
		report.errors.append("批准清单不是数组")
	else:
		if not validator.validate(args[0], manifest):
			report.errors = validator.errors.duplicate()
		else:
			var documents: Array = []
			var cache = preload("res://scripts/net/content/content_cache.gd").new()
			cache.root = args[2].get_base_dir().path_join("validation-cache")
			cache.max_file_bytes = validator.max_file_bytes
			for item in manifest:
				# 初检之后源目录仍可能变化；定长复读同一份字节供分析与组装。
				var input := FileAccess.open(args[0].path_join(item.path), FileAccess.READ)
				if input == null:
					report.errors.append("无法复读批准文件：" + item.path)
					break
				if input.get_length() != item.size or item.size > validator.max_file_bytes:
					input.close()
					report.errors.append("批准文件大小在校验后变化：" + item.path)
					break
				var content:PackedByteArray = input.get_buffer(item.size)
				input.close()
				if content.size() != item.size:
					report.errors.append("批准文件复读长度校验失败：" + item.path)
					break
				if not cache.store(item.hash, content):
					# cache.error 全部是组件内固定原因，不含根目录、文件内容或凭据。
					print("ROOM_VALIDATION_CACHE_REJECT ", cache.error)
					report.errors.append("批准文件复读校验失败：" + item.path + "；" + cache.error)
					break
				if item.path.get_extension().to_lower() == "json":
					var parsed := JSON.new()
					if parsed.parse(content.get_string_from_utf8()) != OK:
						report.errors.append("批准 JSON 复读解析失败：" + item.path)
						break
					documents.append({"path": item.path, "provider": "", "data": parsed.data})
			var analysis = preload("res://scripts/net/validation/rule_loop_analysis.gd").new()
			analysis.max_depth = validator.max_json_depth
			report.loop_analysis = analysis.inspect(documents)
			if report.loop_analysis.truncated:
				report.errors.append_array(report.loop_analysis.errors)
			var assembler = preload("res://scripts/net/content/room_data_assembler.gd").new()
			var isolated_root := args[2].get_base_dir().path_join("validation-data")
			if report.errors.is_empty() and not assembler.assemble(isolated_root, manifest, cache):
				report.errors.append(assembler.error)
			if report.errors.is_empty():
				GameData.release_game_objects()
				LoadHelper.session_data_dir = isolated_root
				LoadGame.stored_jsons_path = args[2].get_base_dir().path_join("stored_jsons.dat")
				LoadGame.reload_game()
				report.masters = GameData.loaded_masters.size()
				report.servants = GameData.loaded_servants.size()
				if GameData.loaded_masters.is_empty() or GameData.loaded_servants.is_empty():
					report.errors.append("所选数据缺少可加载的御主或从者")
				if report.errors.is_empty() and args.size() == 4:
					var simulation_options = JSON.parse_string(FileAccess.get_file_as_string(args[3]))
					report.ok = true
					report.random_simulation = {"ok":false,"status":"running","warnings":[],"errors":[]}
					if not _write_report(args[2],report):
						get_tree().quit(2)
						return
					report.random_simulation = await _simulate(simulation_options, isolated_root)
					for warning in report.random_simulation.get("warnings", []):
						report.loop_analysis.warnings.append({"kind":"random_simulation","message":warning})
					if not report.random_simulation.ok: report.errors.append_array(report.random_simulation.errors)
				else:
					report.random_simulation = {"configured":false, "cases":[], "warnings":["未配置随机模拟，本次仅做静态和加载校验"]}
				report.ok = report.errors.is_empty()
	if not _write_report(args[2],report):
		push_error("无法写出数据校验报告")
		get_tree().quit(2)
		return
	print("ROOM_DATA_VALIDATION ", JSON.stringify(report))
	get_tree().quit(0 if report.ok else 1)

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
