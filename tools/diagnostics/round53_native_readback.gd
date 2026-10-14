extends SceneTree

func _initialize() -> void:
	var args:PackedStringArray = OS.get_cmdline_user_args()
	var required:Dictionary = {
		"FateServerSignals":["enable","protect_worker","disable","take_request"],
		"FateProcessOwner":["available","spawn","state","verify","terminate","release"],
		"FateAtomicFileReplace":["replace_validated_file"],
		"FateCollectionIdentity":["is_supported","candidate_key"]
	}
	var classes:Dictionary = {}
	var ok:bool = true
	for name in required:
		var exists:bool = ClassDB.class_exists(name)
		var methods:Array = []
		if exists:
			for method in ClassDB.class_get_method_list(name,true): methods.append(str(method.name))
		methods.sort()
		for method in required[name]:
			if method not in methods: ok = false
		if not exists: ok = false
		classes[name] = {"registered":exists,"methods":methods}
	var cfg:ConfigFile = ConfigFile.new()
	var cfg_error:Error = cfg.load("res://assets/config/server.cfg")
	var cfg_readback:Dictionary = {"load_error":cfg_error,"sha256":FileAccess.get_sha256("res://assets/config/server.cfg")}
	if cfg_error == OK:
		cfg_readback.enabled = cfg.get_value("data","random_sim_enabled",null)
		cfg_readback.budget_sec = cfg.get_value("data","random_sim_budget_sec",null)
	var receipt:Dictionary = {"pid":OS.get_process_id(),"executable":OS.get_executable_path(),"user_root":OS.get_user_data_dir(),"manifest_sha256":args[0],"classes":classes,"cfg":cfg_readback,"pool":ProjectSettings.get_setting("threading/worker_pool/max_threads"),"main_scene":ProjectSettings.get_setting("application/run/main_scene"),"ok":ok}
	var output:FileAccess = FileAccess.open("user://round53-native-readback.json",FileAccess.WRITE)
	if output == null: quit(3); return
	output.store_string(JSON.stringify(receipt))
	output.close()
	print("ROUND53_NATIVE ",JSON.stringify(receipt))
	quit(0 if ok else 4)
