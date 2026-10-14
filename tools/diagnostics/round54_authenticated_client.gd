extends Node

var session
var started:int = 0
var output_path:String = ""
var done:bool = false
var rejected_reason:String = ""
var authenticated_seen:bool = false
var requested_settings:Dictionary = {}

func _ready() -> void:
	call_deferred("begin")

func begin() -> void:
	var args:PackedStringArray = OS.get_cmdline_user_args()
	output_path = args[1]
	session = load("res://scripts/net/session/lobby_session.gd").new()
	session.rejected.connect(func(reason:String): rejected_reason = reason)
	if not session.configure_identity("user://round54_own_identity/private.pem","round54probe","Round54"):
		finish(false,"identity_configuration: " + session.error)
		return
	var modes:Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LoadHelper.get_data_dir().path_join("selection_modes.json")))
	var declared:Dictionary = {}
	for mode in modes.modes:
		if mode.id == modes.default_mode: declared = mode
	if declared.is_empty():
		finish(false,"no_formal_default_selection_mode")
		return
	var rules = load(str(declared.script)).new()
	var capacity:int = rules.capacity(GameStart.get_masters_can_use(),GameStart.get_servants_can_use(),declared)
	if capacity <= 0:
		finish(false,"formal_capacity: " + rules.error)
		return
	requested_settings = {"capacity":capacity,"minimum":1,"selection_mode":str(declared.id),"ai_count":0,"spectator_limit":capacity}
	var result:Error = session.join_server("127.0.0.1",int(args[0]),"Round54","","Round54 isolated lobby",requested_settings)
	if result != OK:
		finish(false,"join_server: " + session.error)
		return
	started = Time.get_ticks_msec()

func _process(delta:float) -> void:
	if done or session == null: return
	session.poll(delta)
	if session.identity_authenticated: authenticated_seen = true
	if not rejected_reason.is_empty():
		finish(false,rejected_reason)
		return
	if session.view.get("settings") is Dictionary and not session.server_room_id.is_empty():
		var settings:Dictionary = session.view.settings
		finish(settings.get("random_sim_enabled") == true and settings.get("random_sim_budget_sec") == 15.0,"settings_readback",settings)
		return
	if Time.get_ticks_msec() - started > 40000:
		finish(false,"no_room_settings_within_existing_30s_startup_plus_transport_margin")

func finish(ok:bool,reason:String,settings:Dictionary = {}) -> void:
	done = true
	var receipt:Dictionary = {"ok":ok,"reason":reason,"pid":OS.get_process_id(),"user_root":OS.get_user_data_dir(),"authenticated":authenticated_seen,"room_id":session.server_room_id if session != null else "","settings":settings,"pool":ProjectSettings.get_setting("threading/worker_pool/max_threads"),"request":{"kind":"server_create","args":{"name":"Round54 isolated lobby","settings":requested_settings}},"client_kind":"source_editor_scene_fixture_not_release_GUI"}
	var output:FileAccess = FileAccess.open(output_path,FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(receipt))
		output.close()
	print("ROUND54_AUTHENTICATED_ROOM ",JSON.stringify(receipt))
	if session != null: session.close()
	session = null
	get_tree().quit(0 if ok else 5)
