extends Node

## 独立进程入口：参数与输出位置仅由本机任务管理器提供。
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	args.erase("--room-data-validation-worker")
	if args.size() != 3:
		push_error("数据校验需要数据目录、批准清单、报告路径")
		get_tree().quit(2)
		return
	var validator = preload("res://scripts/net/room_data_validator.gd").new()
	var manifest = validator.parse_manifest(FileAccess.get_file_as_string(args[1]))
	var report := {"ok": false, "errors": [], "masters": 0, "servants": 0}
	if not manifest is Array:
		report.errors.append("批准清单不是数组")
	else:
		if not validator.validate(args[0], manifest):
			report.errors = validator.errors.duplicate()
		else:
			var documents: Array = []
			for item in manifest:
				if item.path.get_extension().to_lower() == "json":
					documents.append({"path": item.path, "provider": "", "data": JSON.parse_string(FileAccess.get_file_as_string(args[0].path_join(item.path)))})
			var analysis = preload("res://scripts/net/rule_loop_analysis.gd").new()
			analysis.max_depth = validator.max_json_depth
			report.loop_analysis = analysis.inspect(documents)
			if report.loop_analysis.truncated:
				report.errors.append_array(report.loop_analysis.errors)
			var cache = preload("res://scripts/net/content_cache.gd").new()
			cache.root = args[2].get_base_dir().path_join("validation-cache")
			for item in manifest:
				if not cache.store(item.hash, FileAccess.get_file_as_bytes(args[0].path_join(item.path))):
					report.errors.append(cache.error)
					break
			var assembler = preload("res://scripts/net/room_data_assembler.gd").new()
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
				report.ok = report.errors.is_empty()
	var output := FileAccess.open(args[2], FileAccess.WRITE)
	if output == null:
		push_error("无法写出数据校验报告")
		get_tree().quit(2)
		return
	output.store_string(JSON.stringify(report))
	output.close()
	print("ROOM_DATA_VALIDATION ", JSON.stringify(report))
	get_tree().quit(0 if report.ok else 1)
