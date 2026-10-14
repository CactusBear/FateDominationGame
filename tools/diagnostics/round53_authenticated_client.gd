extends SceneTree

var session
var started:int = 0
var output_path:String = ""
var done:bool = false
var rejected_reason:String = ""
var authenticated_seen:bool = false

func _initialize() -> void:
	call_deferred("begin")

func begin() -> void:
	var args:PackedStringArray = OS.get_cmdline_user_args()
	output_path = args[1]
	session = load("res://scripts/net/session/lobby_session.gd").new()
	session.rejected.connect(func(reason:String): rejected_reason = reason)
	if not session.configure_identity("user://round53_identity/private.pem","round53probe","Round53"):
		finish(false,"identity_configuration: " + session.error)
		return
	var result:Error = session.join_server("127.0.0.1",int(args[0]),"Round53","","Round53 lobby",{})
	if result != OK: finish(false,"join_server: " + session.error); return
	started = Time.get_ticks_msec()

func _process(delta:float) -> bool:
	if done or session == null: return false
	session.poll(delta)
	if session.identity_authenticated: authenticated_seen = true
	if not rejected_reason.is_empty():
		finish(false,rejected_reason)
		return false
	if session.view.get("settings") is Dictionary and not session.server_room_id.is_empty():
		var settings:Dictionary = session.view.settings
		finish(settings.get("random_sim_enabled") == true and settings.get("random_sim_budget_sec") == 15.0,"settings_readback",settings)
		return false
	if Time.get_ticks_msec() - started > 40000:
		finish(false,"no_room_settings_within_existing_30s_startup_plus_transport_margin")
	return false

func finish(ok:bool,reason:String,settings:Dictionary = {}) -> void:
	done = true
	var receipt:Dictionary = {"ok":ok,"reason":reason,"pid":OS.get_process_id(),"user_root":OS.get_user_data_dir(),"authenticated":authenticated_seen,"room_id":session.server_room_id if session != null else "","settings":settings,"pool":ProjectSettings.get_setting("threading/worker_pool/max_threads")}
	var output:FileAccess = FileAccess.open(output_path,FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify(receipt)); output.close()
	print("ROUND53_AUTHENTICATED_ROOM ",JSON.stringify(receipt))
	if session != null: session.close()
	session = null
	quit(0 if ok else 5)
