extends Node

func _ready() -> void:
	var worker: bool = "worker" in OS.get_cmdline_user_args()
	var receipt := {"user_dir":OS.get_user_data_dir(), "pid":OS.get_process_id(), "worker":worker, "token":Crypto.new().generate_random_bytes(12).hex_encode()}
	var path := "user://stable-id-worker.json" if worker else "user://stable-id-parent.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("RESULT ", JSON.stringify({"suite":"stable-id-path", "checks":1, "failures":["user receipt writable"]}))
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(receipt))
	file.close()
	print("USER_PATH ", JSON.stringify(receipt))
	if worker:
		get_tree().quit(0)
		return
	if FileAccess.file_exists("user://stable-id-worker.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://stable-id-worker.json"))
	var child: int = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--quit-after", "600", "--scene", "res://newtests/v2-discard-stable-id_path.tscn", "--", "worker"])
	print("WORKER_PID ", child)
	var deadline: int = Time.get_ticks_msec() + 120000
	while child > 0 and OS.is_process_running(child) and Time.get_ticks_msec() < deadline:
		OS.delay_msec(10)
		await get_tree().process_frame
	var ok: bool = child > 0 and not OS.is_process_running(child) and FileAccess.file_exists("user://stable-id-worker.json")
	print("CHECK real worker naturally exited and user receipt ", ok)
	print("RESULT ", JSON.stringify({"suite":"stable-id-path", "checks":1, "failures":[] if ok else ["real worker naturally exited and user receipt"]}))
	get_tree().quit(0 if ok else 1)
