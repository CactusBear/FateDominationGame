extends SceneTree

var checks:int = 0
var failures:Array = []

func check(label:String, value:bool) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)

func _initialize() -> void:
	var path:String = "res://scripts/net/server/recovery_save_diagnostic.gd"
	check("pure diagnostic interface exists", ResourceLoader.exists(path))
	if ResourceLoader.exists(path):
		var projector = load(path)
		check("native success creates no error", projector.project("native_commit", {"ok":true,"stage":"published","native_error":0,"durability_guaranteed":false}).is_empty())
		check("policy rejection cannot claim WinAPI error", projector.project("native_commit", {"ok":false,"stage":"invalid_path","native_error":32,"durability_guaranteed":false}).native_error == null)
		contract_checks(projector)
		native_checks(projector)
	print("RESULT checks=",checks," failures=",JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)

func contract_checks(projector) -> void:
	var source:Dictionary = {"ok":false,"stage":"open_target","native_error":32,"durability_guaranteed":false,"unexpected":{"test_marker":1},"pid":999,"request_instance":999,"path":"C:/not-approved"}
	var original:Dictionary = source.duplicate(true)
	var projected:Dictionary = projector.project("native_commit", source)
	check("captured error remains exact integer", projected.native_error is int and projected.native_error == 32)
	check("unknown fields and untrusted binding dropped", projected.size() == 5 and not projected.has("unexpected") and not projected.has("pid") and not projected.has("request_instance") and not projected.has("path"))
	check("input unchanged", source == original)
	projected.native_error = 5
	check("output mutation cannot change input", source == original)
	check("caller PID binding not in native result", not projector.project("native_commit", source).has("pid"))
	check("captured Godot Error separately typed", projector.project("write", null, ERR_FILE_CANT_WRITE).godot_error == ERR_FILE_CANT_WRITE and projector.project("write", null, ERR_FILE_CANT_WRITE).native_error == null)
	for code in [null, 0, -1, 1.0, true, "32", 4294967296]:
		check("bad Godot error type or domain " + str(code), projector.project("write", null, code).godot_error == null)
	for stage in ["path", "seat", "snapshot", "write", "hash", "initial_commit"]:
		var value:Dictionary = projector.project(stage)
		check("non-native failed branch " + stage, value.stage == stage and value.native_error == null and value.native_stage == null)
	for stage in [null, 1, true, "unapproved-free-text"]:
		var value:Dictionary = projector.project(stage, source, 32)
		check("unknown caller stage sanitized " + str(stage), value.stage == "unknown" and value.native_error == null and value.godot_error == null)
	for malformed in [null, [], "bad", {}, {"ok":1,"stage":"open_target","native_error":32,"durability_guaranteed":false}, {"ok":false,"stage":"open_target","native_error":32.0,"durability_guaranteed":false}, {"ok":false,"stage":"open_target","native_error":true,"durability_guaranteed":false}, {"ok":false,"stage":"open_target","native_error":-1,"durability_guaranteed":false}, {"ok":false,"stage":"open_target","native_error":4294967296,"durability_guaranteed":false}, {"ok":false,"stage":"open_target","native_error":32,"durability_guaranteed":true}, {"ok":true,"stage":"open_target","native_error":32,"durability_guaranteed":false}]:
		var value:Dictionary = projector.project("native_commit", malformed)
		check("malformed native result " + str(checks), value.native_stage == "invalid_native_result" and value.native_error == null)
	check("unknown native stage drops error association", projector.project("native_commit", {"ok":false,"stage":"unapproved-free-text","native_error":32,"durability_guaranteed":false}).native_error == null)
	check("wrapper sentinel zero is not observed WinAPI error", projector.project("native_commit", {"ok":false,"stage":"native_extension_unavailable","native_error":0,"durability_guaranteed":false}).native_error == null)
	for ignored in [null, "discarded", source]:
		check("non-native branch ignores raw result " + str(checks), projector.project("hash", ignored).native_error == null)

func native_checks(projector) -> void:
	var extension:String = "res://addons/fate_server_signals/fate_server_signals.gdextension"
	var loaded:int = GDExtensionManager.load_extension(extension)
	check("real extension loads", loaded in [GDExtensionManager.LOAD_STATUS_OK, GDExtensionManager.LOAD_STATUS_ALREADY_LOADED])
	check("real native class registered", ClassDB.class_exists("FateAtomicFileReplace"))
	if not ClassDB.class_exists("FateAtomicFileReplace"): return
	var wrapper = load("res://scripts/io/atomic_file_replace.gd")
	var root:String = OS.get_environment("ROUND64_FIXTURES")
	print("USER_DATA ",OS.get_user_data_dir())
	check("runtime user data stays E", OS.get_user_data_dir().to_lower().begins_with("e:/scratch/round64-save-diagnostic-"))
	var success:Dictionary = wrapper.replace_validated_file(root.path_join("success.tmp"), root.path_join("success.old"), "new ordinary bytes".to_utf8_buffer().size())
	check("real wrapper exact schema", success.size() == 4 and success.ok is bool and success.stage is String and success.native_error is int and success.durability_guaranteed == false)
	check("real native commit success", success.ok and success.stage == "published" and success.native_error == 0)
	check("real success produces no diagnostic error", projector.project("native_commit",success).is_empty())
	check("success target readback", FileAccess.get_file_as_bytes(root.path_join("success.old")) == "new ordinary bytes".to_utf8_buffer())
	check("success consumes only fresh temporary", not FileAccess.file_exists(root.path_join("success.tmp")))
	var locked:Dictionary = wrapper.replace_validated_file(root.path_join("locked.tmp"),root.path_join("locked.old"),"new locked ordinary bytes".to_utf8_buffer().size())
	var lock_diag:Dictionary = projector.project("native_commit",locked)
	print("CONTROLLED_LOCK ",JSON.stringify(lock_diag))
	check("real sharing-delete denial", locked.ok == false and locked.stage == "native_replace" and locked.native_error == 32)
	check("real lock exact captured error projected", lock_diag.stage == "native_commit" and lock_diag.native_stage == locked.stage and lock_diag.native_error == locked.native_error)
	var directory:Dictionary = wrapper.replace_validated_file(root.path_join("directory.tmp"),root.path_join("directory.old"),"directory conflict ordinary bytes".to_utf8_buffer().size())
	var directory_diag:Dictionary = projector.project("native_commit",directory)
	print("CONTROLLED_DIRECTORY ",JSON.stringify(directory_diag))
	check("real directory conflict matches WinAPI open", directory.ok == false and directory.stage == "open_target" and directory.native_error == 5)
	check("directory captured code projected without guessing", directory_diag.native_error == directory.native_error and directory_diag.native_stage == directory.stage)
	check("native failures preserve fresh ordinary targets and temporaries", FileAccess.get_file_as_bytes(root.path_join("locked.old")) == "old locked ordinary bytes".to_utf8_buffer() and FileAccess.get_file_as_bytes(root.path_join("locked.tmp")) == "new locked ordinary bytes".to_utf8_buffer() and FileAccess.get_file_as_bytes(root.path_join("directory.tmp")) == "directory conflict ordinary bytes".to_utf8_buffer() and DirAccess.dir_exists_absolute(root.path_join("directory.old")))
	var before:PackedByteArray = FileAccess.get_file_as_bytes(root.path_join("locked.old"))
	for index in range(20):
		projector.project("native_commit",locked)
		projector.project("path")
	check("repeated pure projection performs zero file side effects", FileAccess.get_file_as_bytes(root.path_join("locked.old")) == before and FileAccess.file_exists(root.path_join("locked.tmp")))
