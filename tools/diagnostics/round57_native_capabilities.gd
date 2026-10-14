extends SceneTree

var output: String
var helper: String
var failures: Array[String] = []
var checks: Array = []
var sequence: int = 0
var owner
var atomic
var current_mode: String = ""

func check(ok: bool, label: String, detail: Variant = null) -> void:
	checks.append({"label": label, "ok": ok, "detail": detail})
	print("R57_CHECK ", JSON.stringify(checks[-1]))
	if not ok:
		failures.append(label)

func write_json(path: String, value: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(value))
	f.close()

func rpc(action: String, data: Dictionary = {}) -> Dictionary:
	sequence += 1
	data["action"] = action
	data["engine_pid"] = OS.get_process_id()
	var check_label := str(data.get("_check_label", "controller_" + action))
	data.erase("_check_label")
	var prefix := output.path_join("rpc-%03d" % sequence)
	write_json(prefix + ".request.json", data)
	var until := Time.get_ticks_msec() + 12000
	while not FileAccess.file_exists(prefix + ".response.json") and Time.get_ticks_msec() < until:
		await process_frame
	if not FileAccess.file_exists(prefix + ".response.json"):
		check(false, "controller_timeout_" + action)
		return {}
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(prefix + ".response.json"))
	check(result is Dictionary and bool(result.get("ok", false)), check_label, result)
	return result if result is Dictionary else {}

func states_are_waiting(states: Dictionary) -> bool:
	if states.size() != 3:
		return false
	for value in states.values():
		if int(value) != 258:
			return false
	return true

func receipt(token: String, pid: int) -> Dictionary:
	return owner.tree_observe(token, pid)

func wait_root(token: String, pid: int) -> bool:
	var until := Time.get_ticks_msec() + 10000
	while owner.state(token, pid) == 1 and Time.get_ticks_msec() < until:
		await process_frame
	return owner.state(token, pid) == 0

func wait_zero(token: String, pid: int) -> Dictionary:
	var r := receipt(token, pid)
	var until := Time.get_ticks_msec() + 10000
	while (not bool(r.get("active_known", false)) or int(r.get("active_processes", -1)) != 0) and Time.get_ticks_msec() < until:
		await process_frame
		r = receipt(token, pid)
	return r

func tree_case(mode: String, destroy: bool = false) -> void:
	var setup := await rpc("tree_prepare", {"mode": mode})
	var d: String = setup.get("directory", "")
	var child: Dictionary = owner.spawn(helper, PackedStringArray(["--tree", d, "root", mode, setup.get("gate", ""), setup.get("end", ""), helper]))
	var pid: int = int(child.get("pid", -1))
	var token: String = str(child.get("token", ""))
	check(pid > 0 and token.length() == 32, mode + "_spawn", child)
	if pid <= 0:
		return
	await rpc("tree_ready", {"directory": d, "pid": pid})
	var r := receipt(token, pid)
	check(bool(r.get("ok", false)) and r.get("root_state", "") == "running" and int(r.get("active_processes", 0)) == 3, mode + "_three_running", r)
	check(r.get("token", "") == token and int(r.get("root_pid", -1)) == pid and int(r.get("local_owner_pid", -1)) == OS.get_process_id() and owner.state(token, pid) == 1, mode + "_binding_identity", r)
	check(owner.verify(token, pid) and owner.state(token, pid) == 1, mode + "_old_root_running")
	check(not owner.release(token, pid), mode + "_live_release_false")
	check(not bool(receipt("stale-" + token, pid).get("ok", true)) and owner.state("stale-" + token, pid) == -1 and not owner.terminate("stale-" + token, pid), mode + "_stale_token_rejected")
	check(not bool(receipt(token, pid + 1).get("ok", true)) and not owner.release(token, pid + 1) and not owner.terminate(token, pid + 1), mode + "_wrong_pid_rejected")
	check(receipt("", -1).get("stage", "") == "lease_unknown", mode + "_unknown")
	if destroy:
		var before := await rpc("count", {"label": "destructor_before"})
		owner = null
		await process_frame
		var alive := await rpc("tree_alive", {"directory": d, "label": "after_destructor_unsaved"})
		var after := await rpc("count", {"label": "destructor_after"})
		check(not bool(alive.get("saved", false)) and states_are_waiting(alive.get("states", {})), "destructor_unsaved_tree_still_live", alive)
		check(before.has("handle_count") and after.has("handle_count"), "destructor_handle_observed", {"baseline": before.get("handle_count", -1), "after": after.get("handle_count", -1), "interpretation": "cache_or_owner_fluctuation_observed_not_leak_proof"})
		await rpc("tree_finish", {"directory": d, "root": true})
		await rpc("tree_exited", {"directory": d})
		owner = ClassDB.instantiate("FateProcessOwner")
		return
	if mode == "terminate":
		check(owner.terminate(token, pid), "old_terminate_root_only")
	else:
		await rpc("tree_root_exit", {"directory": d})
	check(await wait_root(token, pid), mode + "_root_exit")
	r = receipt(token, pid)
	check(bool(r.get("ok", false)) and r.get("root_state", "") == "exited" and int(r.get("active_processes", 0)) > 0 and int(r.get("total_processes", 0)) == 3, mode + "_root_exit_descendants_alive", r)
	check(not owner.release(token, pid), mode + "_root_exit_release_false")
	await rpc("tree_alive", {"directory": d, "only_descendants": true, "label": "unsaved_descendants"})
	await rpc("tree_finish", {"directory": d})
	var exited := await rpc("tree_exited", {"directory": d})
	var expected_root_exit := 0 if mode == "normal" else 0xE0570001 if mode == "crash" else 1
	check(int(exited.get("results", {}).get("root", {}).get("exit", -1)) == expected_root_exit, mode + "_root_exit_code", exited)
	r = await wait_zero(token, pid)
	check(bool(r.get("ok", false)) and int(r.get("active_processes", -1)) == 0 and r.get("root_state", "") == "exited", mode + "_natural_zero", r)
	check(owner.release(token, pid), mode + "_release_true")
	check(owner.state(token, pid) == -1 and receipt(token, pid).get("stage", "") == "lease_unknown" and not owner.release(token, pid), mode + "_released_unknown")

func spawn_sequence_case() -> void:
	var leases: Array = []
	for index in range(4):
		var setup := await rpc("tree_prepare", {"mode": "solo-%d" % index})
		var child: Dictionary = owner.spawn(helper, PackedStringArray(["--tree", setup.get("directory", ""), "root", "solo", setup.get("gate", ""), setup.get("end", ""), helper]))
		var pid := int(child.get("pid", -1))
		var token := str(child.get("token", ""))
		leases.append({"setup": setup, "pid": pid, "token": token})
		check(pid > 0 and token.length() == 32, "sequence_%d_spawn" % index, child)
		await rpc("tree_ready", {"directory": setup.get("directory", ""), "pid": pid})
		var r := receipt(token, pid)
		check(bool(r.get("ok", false)) and r.get("token", "") == token and int(r.get("root_pid", -1)) == pid and owner.state(token, pid) == 1, "sequence_%d_binding" % index, r)
		check(int(r.get("active_processes", -1)) == 1 and int(r.get("total_processes", -1)) == 1, "sequence_%d_tree_count" % index, r)
	for lease in leases:
		check(not owner.release(str(lease.get("token", "")), int(lease.get("pid", -1))), "sequence_live_release_%s" % lease.get("pid", -1))
	for lease in leases:
		var setup: Dictionary = lease.get("setup", {})
		await rpc("tree_finish", {"directory": setup.get("directory", ""), "root": true})
	for lease in leases:
		var setup: Dictionary = lease.get("setup", {})
		var token: String = str(lease.get("token", ""))
		var pid: int = int(lease.get("pid", -1))
		var exited := await rpc("tree_exited", {"directory": setup.get("directory", "")})
		check(owner.state(token, pid) == 0 and owner.release(token, pid), "sequence_release_%s" % pid, exited)

func invalid_spawn_case() -> void:
	var missing: Dictionary = owner.spawn(output.path_join("does-not-exist.exe"), PackedStringArray())
	check(int(missing.get("pid", -1)) == -1 and str(missing.get("token", "")) == "", "invalid_spawn_no_token", missing)
	var empty_executable: Dictionary = owner.spawn("", PackedStringArray())
	check(int(empty_executable.get("pid", -1)) == -1 and str(empty_executable.get("token", "")) == "", "empty_spawn_no_token", empty_executable)

func id(value: Dictionary) -> Dictionary:
	return {"volume": int(value.get("volume", 0)), "file_index": int(value.get("file_index", 0))}

func cleanup_case(kind: String) -> void:
	var setup := await rpc("cleanup_prepare", {"kind": kind})
	if bool(setup.get("skip", false)):
		checks.append({"label": kind, "skip": true, "reason": setup.get("reason", "")})
		return
	var result: Dictionary = atomic.remove_verified(str(setup.get("root", "")), str(setup.get("file", "")), id(setup.get("root_id", {})), id(setup.get("parent_id", {})), id(setup.get("file_id", {})), int(setup.get("size", 0)), str(setup.get("sha256", "")))
	check(bool(result.get("ok", false)) == (kind == "correct"), "remove_" + kind, result)
	var expected: String = setup.get("expected_stage", "")
	check(result.get("stage", "") == expected and not bool(result.get("recovery_required", true)), "remove_" + kind + "_stage", result)
	await rpc("cleanup_readback", {"case": setup.get("case", ""), "result": result})

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	output = args[0]
	helper = args[1]
	var mode: String = args[2]
	current_mode = mode
	var load_status := GDExtensionManager.load_extension("res://addons/fate_server_signals/fate_server_signals.gdextension")
	check(load_status == GDExtensionManager.LOAD_STATUS_OK or load_status == GDExtensionManager.LOAD_STATUS_ALREADY_LOADED, "explicit_loader", load_status)
	var contracts := {
		"FateServerSignals": ["enable", "protect_worker", "disable", "take_request"],
		"FateProcessOwner": ["available", "spawn", "state", "verify", "terminate", "release", "tree_observe"],
		"FateAtomicFileReplace": ["replace_validated_file", "remove_verified"],
		"FateCollectionIdentity": ["is_supported", "candidate_key"]}
	for name in contracts:
		check(ClassDB.class_exists(name) and ClassDB.can_instantiate(name), "registered_" + name)
		if not ClassDB.class_exists(name):
			_finish()
			return
		var instance = ClassDB.instantiate(name)
		check(instance != null, "instantiated_" + name)
		for method in contracts[name]:
			check(instance.has_method(method), "method_" + name + "." + method)
		instance = null
	owner = ClassDB.instantiate("FateProcessOwner")
	atomic = ClassDB.instantiate("FateAtomicFileReplace")
	if mode == "signals":
		var signals = ClassDB.instantiate("FateServerSignals")
		var competing = ClassDB.instantiate("FateServerSignals")
		check(signals.enable(), "signal_enable")
		check(not competing.enable(), "signal_single_owner")
		var start := await rpc("break_start", {"label": "collect", "_check_label": "controller_break"})
		var until := Time.get_ticks_msec() + 5000
		var request: int = 0
		while request == 0 and Time.get_ticks_msec() < until:
			request = signals.take_request()
			await process_frame
		check(request == 2 and signals.take_request() == 0, "ctrl_break_once")
		await rpc("break_ack", {"label": "collect", "_check_label": "signal_handler_event_ack"})
		var collect := await rpc("break_finish", {"label": "collect", "_check_label": "controller_break"})
		check(bool(start.get("registered", {}).get("sender", []).size() == 2) and bool(collect.get("real_event_ack_before_detach", false)), "sender_full_identity_and_safe_detach", {"start": start, "finish": collect})
		signals.disable()
		check(signals.protect_worker(), "protect_worker")
		var protected_start := await rpc("break_start", {"label": "protect", "_check_label": "controller_break_protect_start"})
		for frame in range(15):
			await process_frame
		check(signals.take_request() == 0, "protected_worker_no_request")
		await rpc("break_ack", {"label": "protect", "_check_label": "protected_handler_event_ack"})
		var protected := await rpc("break_finish", {"label": "protect", "_check_label": "controller_break_protect_finish"})
		check(bool(protected_start.get("registered", {}).get("sender", []).size() == 2) and bool(protected.get("real_event_ack_before_detach", false)), "protected_sender_safe_detach", {"start": protected_start, "finish": protected})
		signals.disable()
		signals = null
		competing = null
	else:
		check(owner.available(), "owner_available")
		await invalid_spawn_case()
		await spawn_sequence_case()
		await rpc("count", {"label": "baseline"})
		await tree_case("normal")
		await rpc("count", {"label": "after_normal_release"})
		await tree_case("crash")
		await rpc("count", {"label": "after_crash_release"})
		await tree_case("terminate")
		await rpc("count", {"label": "after_terminate_release"})
		await tree_case("destructor", true)
		await rpc("count", {"label": "after_destructor"})
		for kind in ["wrong_root", "wrong_parent", "wrong_file", "size", "hash", "locked", "directory", "hardlink", "leaf_junction", "ancestor_junction", "ancestor_changed", "root_changed", "symlink", "outside", "dotdot", "correct"]:
			await cleanup_case(kind)
		var setup := await rpc("atomic_prepare")
		var replaced: Dictionary = atomic.replace_validated_file(str(setup.get("source", "")), str(setup.get("target", "")), int(setup.get("size", 0)))
		check(bool(replaced.get("ok", false)) and not bool(replaced.get("durability_guaranteed", true)), "atomic_replace", replaced)
		await rpc("atomic_readback")
		var identity = ClassDB.instantiate("FateCollectionIdentity")
		check(identity.is_supported(str(Engine.get_version_info().get("hash", ""))) and not identity.is_supported("unsupported"), "identity_abi_gate")
		var a: Array = []
		var aa: Array = a
		var b: Array = []
		var d: Dictionary = {}
		var dd: Dictionary = d
		var e: Dictionary = {}
		var ak: int = identity.candidate_key(a)
		var dk: int = identity.candidate_key(d)
		check(ak != 0 and ak == identity.candidate_key(aa) and ak != identity.candidate_key(b), "array_identity")
		check(dk != 0 and dk == identity.candidate_key(dd) and dk != identity.candidate_key(e), "dictionary_identity")
		a.append(1)
		d["x"] = 1
		check(ak == identity.candidate_key(a) and dk == identity.candidate_key(d) and identity.candidate_key(123) == 0, "identity_stable")
		identity = null
	_finish()

func _finish() -> void:
	owner = null
	atomic = null
	var report := {"ok": failures.is_empty(), "failure_must_be_false": true, "failures": failures, "checks": checks, "legacy_check_target": 31 if current_mode == "signals" else 158, "legacy_checks_retained": true, "engine": Engine.get_version_info(), "engine_pid": OS.get_process_id()}
	write_json(output.path_join("functional.json"), report)
	print("R57_RESULT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)