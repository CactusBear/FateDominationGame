extends SceneTree

# 外置测试驱动只走发行包原场景和原信号，不触碰密钥内容。
var control_root: String
var role: String
var repeated := false

func _initialize() -> void:
	_run.call_deferred()

func _fail(code: int) -> void:
	print("IDENTITY_PROOF FAIL code=", code)
	quit(code)

func _marker(name: String) -> void:
	var file := FileAccess.open(control_root.path_join(name), FileAccess.WRITE)
	if file == null:
		_fail(41)
		return
	file.store_string(name)
	file.close()
	print("IDENTITY_PROOF ", name, " role=", role)

func _key() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventKey.new()
	release.keycode = KEY_ENTER
	release.pressed = false
	Input.parse_input_event(release)

func _press(node: Node, path: String) -> bool:
	var button := node.get_node_or_null(path) as BaseButton
	if button == null or button.disabled or button.get_signal_connection_list("pressed").is_empty():
		_fail(42)
		return false
	button.pressed.emit()
	return true

func _run() -> void:
	role = OS.get_environment("FD_PROOF_ROLE")
	control_root = OS.get_environment("FD_PROOF_CONTROL").replace("\\", "/")
	var appdata := OS.get_environment("APPDATA").replace("\\", "/")
	var localappdata := OS.get_environment("LOCALAPPDATA").replace("\\", "/")
	var actual := OS.get_user_data_dir().replace("\\", "/")
	if role not in ["host", "guest"] or not control_root.begins_with("E:/Caches/Hermes/cache/scratch/round75-dual-identity-formal-") or actual != appdata.path_join("FateDomination") or not appdata.begins_with("E:/") or not localappdata.begins_with("E:/"):
		_fail(43)
		return
	print("IDENTITY_PROOF ENV ", JSON.stringify({"pid": OS.get_process_id(), "role": role, "APPDATA": appdata, "LOCALAPPDATA": localappdata, "user_dir": actual}))
	var main_path: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if main_path.is_empty() or change_scene_to_file(main_path) != OK:
		_fail(44)
		return
	await process_frame
	await process_frame
	print("IDENTITY_PROOF MAIN_SCENE ", current_scene.scene_file_path)
	var navigation_deadline := Time.get_ticks_msec() + 30000
	while current_scene == null or current_scene.scene_file_path != "res://assets/scenes/main_menu/main_menu.tscn":
		if Time.get_ticks_msec() > navigation_deadline:
			_fail(45)
			return
		_key()
		await create_timer(1.0).timeout
	await create_timer(1.5).timeout
	if not _press(current_scene, "Content/Nav/Item0/Button"):
		return
	await create_timer(1.0).timeout
	if not _press(current_scene, "Content/Nav/Item1/Button"):
		return
	await process_frame
	await process_frame
	if current_scene == null or current_scene.scene_file_path != "res://assets/scenes/main_menu/multiplayer_lobby.tscn":
		_fail(46)
		return
	print("IDENTITY_PROOF LOBBY_SCENE ", current_scene.scene_file_path)
	var lobby: Node = current_scene
	if str(lobby.get("identity_key_path")) != "user://net_identity/private.pem":
		_fail(47)
		return
	var username := lobby.get_node_or_null("Margin/Content/Identity/Username") as LineEdit
	var nickname := lobby.get_node_or_null("Margin/Content/Connection/Name") as LineEdit
	if username == null or nickname == null:
		_fail(48)
		return
	username.text = role + "proof75"
	nickname.text = role + "proof75"
	if not str(lobby.call("username_error", username.text)).is_empty():
		_fail(49)
		return
	if not _apply(lobby):
		return
	_marker("ready")
	while not FileAccess.file_exists(control_root.path_join("exit")):
		if not repeated and FileAccess.file_exists(control_root.path_join("repeat")):
			if not _apply(lobby):
				return
			repeated = true
			_marker("repeated")
		await create_timer(0.1).timeout
	print("IDENTITY_PROOF NORMAL_EXIT role=", role)
	quit(0)

func _apply(lobby: Node) -> bool:
	if not _press(lobby, "Margin/Content/Identity/Apply"):
		return false
	var status := lobby.get_node_or_null("Margin/Content/Status") as Label
	if status == null or status.text != "身份资料已准备，连接服务端后登记" or not FileAccess.file_exists("user://net_identity/private.pem"):
		_fail(50)
		return false
	print("IDENTITY_PROOF APPLY_OK role=", role, " path=", ProjectSettings.globalize_path("user://net_identity/private.pem"))
	return true
