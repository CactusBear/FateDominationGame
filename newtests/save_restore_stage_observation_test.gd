extends Node

const Manager = preload("res://scripts/net/server/server_room_manager.gd")
const Gateway = preload("res://scripts/net/server/server_gateway.gd")
const Channel = preload("res://scripts/net/server/server_console_channel.gd")
const Relay = preload("res://scripts/net/p2p/p2p_signal_server.gd")
const STARTUP_STAGES:Array = ["signal_protection", "launch_arguments", "configuration", "settings", "selection_mode", "catalog_scan", "data_plan", "cache_policy", "cache_population", "data_assembly", "data_validation", "fixed_source_registration", "process_content", "content_environment", "rules_reload", "roster", "host", "recovery_binding", "selection_configuration", "blob_publication", "room_asset_installation", "startup_pin_release", "identity_bridge", "data_approval", "transaction_audit", "ready_publication"]
const BOUNDARY_STAGES:Array = ["worker_start", "worker_ready", "save_request", "save_receipt", "worker_release", "log_collection"]
const PREFIX:String = "TEST_CHAIN_STAGE "
const CONTENT_SENTINEL:String = "OBSERVATION_ORDINARY_CONTENT_SENTINEL"
var manager = Manager.new()
var checks:int = 0
var failures:Array = []
var boundary_lines:Array = []
var evidence:Dictionary = {"scope":"observation_only", "restore_executed":false, "save_chain_passed":false, "historical_cause":"UNKNOWN"}
var root:String

func check(value:bool, label:String) -> bool:
	checks += 1
	print("CHECK ", value, " ", label)
	if not value: failures.append(label)
	return value

func event(stage:String, result:int) -> void:
	var line:String = PREFIX + "stage=" + stage + " result=" + str(result)
	boundary_lines.append(line)
	print(line)

# This is a test-side boundary collector, never a claim about internal save stages.
# Exact schema excludes all payload fields. Each fixed stage must enter then terminate.
func parse_boundary(lines:Array) -> Dictionary:
	var regex := RegEx.new()
	regex.compile("^TEST_CHAIN_STAGE stage=([a-z_]+) result=(-1|0|1)$")
	var index:int = 0
	var open:bool = false
	var failed_stage:String = ""
	var events:Array = []
	for line in lines:
		var matched = regex.search(str(line))
		if matched == null or index >= BOUNDARY_STAGES.size(): return {"ok":false}
		var stage:String = matched.get_string(1)
		var result:int = int(matched.get_string(2))
		if stage != BOUNDARY_STAGES[index]: return {"ok":false}
		if not open:
			if result != 1: return {"ok":false}
			open = true
		else:
			if result == 1: return {"ok":false}
			if result == -1:
				if not failed_stage.is_empty(): return {"ok":false}
				failed_stage = stage
			index += 1
			open = false
		events.append([stage,result])
	return {"ok":not open and index == BOUNDARY_STAGES.size(),"failure_stage":failed_stage,"events":events}

func _ready() -> void:
	root = OS.get_environment("FATE_TEST_SCRATCH_ROOT")
	if not check(root.begins_with("E:/") and OS.get_user_data_dir().replace("\\","/").begins_with(root+"/") and manager.startup_seconds == 30.0,"owned_E_paths_and_unchanged_startup_deadline"):
		finish(); return
	# Explicit diagnostic-only startup observation; never change the production default.
	if OS.get_environment("FATE_TEST_STARTUP_OBSERVATION_SECONDS") == "300": manager.startup_seconds = 300.0
	evidence["startup_observation_seconds"] = manager.startup_seconds
	manager.storage_root = root.path_join("rooms")
	manager.approved_data_root = LoadHelper.get_data_dir()
	var probe := PacketPeerUDP.new()
	if not check(probe.bind(0,"127.0.0.1") == OK,"single_owned_udp_port"):
		finish(); return
	manager.internal_port_base = probe.get_local_port()
	manager.internal_port_count = 1
	probe.close()
	var modes:Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manager.approved_data_root.path_join("selection_modes.json")))
	event("worker_start",1)
	var id:String = manager.create_room(CONTENT_SENTINEL,{"capacity":4,"minimum":1,"ai_count":0,"selection_mode":modes.default_mode,"spectator_limit":2},manager.approved_data_root)
	event("worker_start",0 if not id.is_empty() else -1)
	if not check(not id.is_empty(),"real_manager_native_worker_spawn"):
		finish(); return
	var room:Dictionary = manager.rooms[id]
	var binding:Dictionary = manager.instance_binding(id).duplicate(true)
	event("worker_ready",1)
	var deadline:int = Time.get_ticks_msec()+int(manager.startup_seconds*1000)+10000
	while not manager.is_ready(id) and str(room.error).is_empty() and Time.get_ticks_msec()<deadline:
		manager.poll()
		await get_tree().process_frame
	var ready:bool = manager.is_ready(id)
	event("worker_ready",0 if ready else -1)
	if not check(ready and manager.process_identity_verified(binding),"real_empty_lobby_ready_with_original_binding"):
		finish(); return
	var gateway = Gateway.new()
	gateway.manager = manager
	var channel = Channel.new()
	channel.configure("",gateway,Relay.new())
	event("save_request",1)
	# Exactly one save submission via the existing command adapter/IPC.
	var submitted:Dictionary = channel.execute("room "+id+" save")
	var request_id:String = str(submitted.get("result",{}).get("request_id",""))
	var sent:bool = submitted.get("ok",false) and Channel.valid_id(request_id) and submitted.get("result",{}).get("status") == "pending"
	event("save_request",0 if sent else -1)
	if not check(sent,"one_real_save_request_pending"):
		finish(); return
	event("save_receipt",1)
	var response:Dictionary = submitted
	deadline = Time.get_ticks_msec()+300000
	while response.get("result",{}).get("status") == "pending" and Time.get_ticks_msec()<deadline:
		manager.poll()
		response = channel.execute("room "+id+" result "+request_id)
		await get_tree().process_frame
	var rejected:bool = response.get("ok") == false and response.get("error") == "当前对局未启用录制，不能声明存档成功"
	event("save_receipt",-1 if response.get("ok") == false else 0)
	check(rejected,"empty_lobby_save_rejected_not_saved")
	check(response.get("request_id") == request_id and int(response.get("pid",0)) == int(binding.pid) and response.get("instance") == binding.instance_id and response.get("room") == id and response.get("authority_host_mode") == binding.authority_host_mode,"final_receipt_same_owned_instance")
	check(manager.is_ready(id) and manager.process_state_for_binding(binding) == 1,"rejection_keeps_worker_alive")
	evidence["save_requests"] = 1
	evidence["save_receipt"] = {"ok":response.get("ok"),"saved":response.get("result",{}).get("saved",false),"reason_code":"recording_unavailable" if rejected else "UNKNOWN", "binding_verified":response.get("request_id") == request_id and response.get("instance") == binding.instance_id}
	event("worker_release",1)
	# Release only this empty owned worker; not a normal saved-close acceptance test.
	manager.close()
	event("worker_release",0 if manager.rooms.is_empty() else -1)
	check(manager.rooms.is_empty(),"owned_empty_worker_release_only")
	event("log_collection",1)
	var text:String = FileAccess.get_file_as_string(str(room.log_file))
	var startup:Array = []
	var production_save:Array = []
	var shape_ok:bool = true
	var regex := RegEx.new()
	regex.compile("^SERVER_ROOM_STARTUP stage=([a-z_]+) result=(-1|0|1)$")
	for line in text.split("\n"):
		if line.begins_with("SERVER_ROOM_STARTUP "):
			var matched = regex.search(line.strip_edges())
			if matched == null: shape_ok = false
			else:
				shape_ok = shape_ok and matched.get_string(1) in STARTUP_STAGES
				startup.append([matched.get_string(1),int(matched.get_string(2))])
		elif line.begins_with("RECOVERY_SAVE_DIAGNOSTIC ") or line.begins_with("RECOVERY_STAGE ") or line.begins_with("RESTORE_SEGMENT ") or line.begins_with("SERVER_ROOM_SAVE "):
			# Count only; unknown payloads are not reprinted or copied into the safe report.
			production_save.append(true)
	var expected:Array = []
	for stage in STARTUP_STAGES:
		if stage in ["content_environment","rules_reload"]: continue
		expected.append([stage,1])
		if stage == "process_content":
			for child in ["content_environment","rules_reload"]:
				expected.append([child,1]); expected.append([child,0])
		expected.append([stage,0])
	check(shape_ok and startup == expected,"startup_fixed_schema_and_exact_nested_order")
	var categories:Array = []
	for needle in [root,manager.approved_data_root,"res://","user://"]:
		if text.contains(needle) and not categories.has("path"): categories.append("path")
	for needle in [str(binding.room),str(binding.instance_id)]:
		if not needle.is_empty() and text.contains(needle) and not categories.has("identity"): categories.append("identity")
	if text.contains(CONTENT_SENTINEL): categories.append("data_content")
	var private_fields := RegEx.new()
	private_fields.compile("(?i)(token|ticket|private_key|resume_secret|data_root|storage_root|public_key)\\s*[:=]")
	if private_fields.search(text) != null: categories.append("private_field")
	event("log_collection",0 if not text.is_empty() else -1)
	check(not text.is_empty() and not text.contains("SCRIPT ERROR") and not text.contains("ERROR:"),"worker_log_read_after_release_no_engine_error")
	var boundary:Dictionary = parse_boundary(boundary_lines)
	check(boundary.get("ok",false) and boundary.get("failure_stage") == "save_receipt","boundary_collector_complete_monotonic_failure_localized")
	var changed:Array = boundary_lines.duplicate()
	changed[2] = PREFIX+"stage=unexpected result=1"
	check(not parse_boundary(changed).get("ok",false),"collector_rejects_unknown_stage")
	changed = boundary_lines.duplicate(); changed[2] = changed[0]
	check(not parse_boundary(changed).get("ok",false),"collector_rejects_regression_and_duplicate")
	changed = boundary_lines.duplicate(); changed.remove_at(changed.size()-1)
	check(not parse_boundary(changed).get("ok",false),"collector_rejects_missing_completion")
	changed = boundary_lines.duplicate(); changed[0] += " ticket=DO_NOT_LOG"
	check(not parse_boundary(changed).get("ok",false),"collector_rejects_payload_fields")
	check(production_save.size()>0,"production_save_stage_entry_present")
	check(categories.is_empty(),"whole_worker_log_no_configuration_path_identity_ticket_content")
	evidence.merge({"boundary":boundary,"startup":startup,"production_save_marker_count":production_save.size(),"raw_worker_log_disclosure_categories":categories,"minimal_cause":"save_has_no_stage_emission_before_recording_gate" if production_save.is_empty() else "UNKNOWN", "worker_log_relative":"worker-engine.log"},true)
	finish()

func finish() -> void:
	manager.close()
	evidence["checks"] = checks
	evidence["failures"] = failures
	Channel.write_json(root.path_join("observation-evidence.json"),evidence)
	print("RESULT save_restore_stage_observation checks=",checks," failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
