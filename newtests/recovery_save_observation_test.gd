extends Node

const Lobby = preload("res://scripts/net/session/lobby_session.gd")
const RoomControl = preload("res://scripts/net/server/server_room_control.gd")
var checks:int = 0
var failures:Array = []
var root:String

func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)

func save_case(session, label:String, expected:bool) -> void:
	print("SAVE_CASE_BEGIN ", label)
	var view_before:Dictionary = session.view.duplicate(true)
	var bindings_before:Dictionary = session._recovery_bindings.duplicate()
	var kinds_before:Dictionary = session._recovery_seat_kinds.duplicate()
	var control = RoomControl.new()
	control.session = session
	var response:Dictionary = control.prepare_close()
	check(response.get("ok") == expected, label + " public close bool")
	if expected:
		check(response.get("result") == {"saved":false,"room_state_saved":true,"closing":true}, label + " unchanged close proof")
	else:
		check(not response.has("result"), label + " no saved proof")
		check(session._recovery_bindings == bindings_before and session._recovery_seat_kinds == kinds_before, label + " failure does not adopt memory")
	var shared:Dictionary = {"response_valid":true,"ok":expected}
	if expected: shared["pending"] = false
	check(preload("res://scripts/net/server/server_console_shared_output.gd").project(response) == shared, label + " unchanged shared output")
	check(session.view == view_before, label + " no diagnostic in client view")
	print("SAVE_CASE_END ", label)

func _ready() -> void:
	root = OS.get_environment("ROUND66_FIXTURES")
	check(root.begins_with("E:/") and OS.get_user_data_dir().replace("\\", "/").begins_with("E:/"), "physical E fixture and user dir")
	var session = Lobby.new()
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip("127.0.0.1")
	check(peer.create_server(0, 2, 3) == OK, "actual loopback ENet ephemeral listen")
	check(session.host_peer(peer, "fixture", {"capacity":2,"minimum":2,"ai_count":0,"selection_mode":"fixture"}) == OK, "actual public lobby host")
	save_case(session, "empty_path", false)
	var nonhost = Lobby.new()
	nonhost.recovery_state_path = root.path_join("nonhost.json")
	save_case(nonhost, "nonhost", false)
	nonhost.close()
	session.recovery_state_path = root.path_join("bad/../path.json")
	save_case(session, "path", false)
	session.recovery_state_path = root.path_join("seat.json")
	session._recovery_bindings = {0:0}
	session._recovery_seat_kinds = {}
	save_case(session, "seat", false)
	check(not FileAccess.file_exists(session.recovery_state_path), "seat refuses before file creation")
	session._recovery_bindings = {}
	session.data_revision = -1
	session.recovery_state_path = root.path_join("snapshot.json")
	save_case(session, "snapshot", false)
	check(not FileAccess.file_exists(session.recovery_state_path), "snapshot refuses before file creation")
	session.data_revision = 0
	# 合法 JSON 字符串键须仅在成功后采用为解码出的整数键。
	session._recovery_bindings = {"0":0}
	session._recovery_seat_kinds = {"0":"ai"}
	session.recovery_state_path = root.path_join("initial.json")
	save_case(session, "initial_success", true)
	check(FileAccess.file_exists(session.recovery_state_path), "initial target created without reading payload")
	save_case(session, "replace_success", true)
	session._recovery_bindings = {"0":0}
	session._recovery_seat_kinds = {"0":"ai"}
	session.recovery_state_path = root.path_join("locked.old")
	save_case(session, "native_locked", false)
	check(FileAccess.get_file_as_bytes(session.recovery_state_path) == "old locked ordinary bytes".to_utf8_buffer(), "native failure preserves ordinary old target")
	check(not FileAccess.file_exists(session.recovery_state_path + ".%d.tmp" % OS.get_process_id()), "native failure original temp cleanup")
	session.recovery_state_path = root.path_join("initial_locked.json")
	save_case(session, "initial_locked", false)
	check(not FileAccess.file_exists(session.recovery_state_path), "failed first rename leaves target absent")
	session.recovery_state_path = root.path_join("directory.old")
	save_case(session, "initial_directory", false)
	check(DirAccess.dir_exists_absolute(session.recovery_state_path), "initial directory preserved")
	check(not FileAccess.file_exists(session.recovery_state_path + ".%d.tmp" % OS.get_process_id()), "initial directory temp cleanup")
	session.recovery_state_path = root.path_join("open_failure.json")
	save_case(session, "write_open", false)
	session.recovery_state_path = root.path_join("initial.json")
	save_case(session, "success_after_failure", true)
	check(session._recovery_bindings == {0:0} and session._recovery_seat_kinds == {0:"ai"}, "original success memory adoption")
	session.close()
	print("RESULT checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
