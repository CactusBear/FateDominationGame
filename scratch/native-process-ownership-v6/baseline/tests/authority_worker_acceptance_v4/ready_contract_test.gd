extends Node

const Manager = preload("res://scripts/net/server/server_room_manager.gd")
var failures:Array[String] = []
var checks:int = 0

func _ready() -> void:
	call_deferred("run")
	watchdog()

func watchdog() -> void:
	await get_tree().create_timer(45.0).timeout
	print("RESULT authority_worker_ready_contract timeout=true")
	get_tree().quit(1)

func check(value:bool, label:String) -> void:
	checks += 1
	if not value: failures.append(label)

func run() -> void:
	# 调用生产校验器；不创建进程，不以该结果代替 LAN/P2P 实机验收。
	for mode in ["lan", "p2p"]:
		var instance:String = "0123456789abcdef0123456789abcdef"
		var room:Dictionary = {"id":instance,"pid":123,"port":52000,"instance_id":instance,"authority_host_mode":mode,"ready":true}
		var capabilities:Dictionary = {"root_transaction_rollback":false,"can_rollback_now":false,"execution_trace":true,"root_transaction_audit":true,"transaction_audit_persistence_enabled":true,"match_recording_enabled":false,"process_restart_is_rollback":false}
		var report:Dictionary = {"ok":true,"id":instance,"room_id":instance,"pid":123,"port":52000,"instance":instance,"instance_id":instance,"authority_host_mode":mode,"capabilities":capabilities}
		check(Manager.valid_ready_report(room,report), mode + ": valid ready")
		for field in ["room_id", "id", "pid", "port", "instance_id", "instance", "authority_host_mode", "ok", "capabilities"]:
			var missing:Dictionary = report.duplicate(true)
			missing.erase(field)
			check(not Manager.valid_ready_report(room,missing), mode + ": missing " + field)
			var changed:Dictionary = report.duplicate(true)
			changed[field] = 124 if field in ["pid", "port"] else "invalid"
			check(not Manager.valid_ready_report(room,changed), mode + ": mismatch " + field)
		for field in capabilities:
			var changed:Dictionary = report.duplicate(true)
			changed.capabilities[field] = 1
			check(not Manager.valid_ready_report(room,changed), mode + ": capability requires bool " + field)
		var restart:Dictionary = report.duplicate(true)
		restart.capabilities.process_restart_is_rollback = true
		check(not Manager.valid_ready_report(room,restart), mode + ": restart is not rollback")
		var manager = Manager.new()
		manager.rooms[instance] = room.duplicate(true)
		# 管理器登记永远使用负 PID；即使断言中途异常，析构也不会杀真实进程。
		manager.rooms[instance].pid = -1
		var binding:Dictionary = manager.instance_binding(instance)
		check(manager.binding_matches(binding), mode + ": binding matches")
		check(not manager.process_identity_verifier.is_valid(), mode + ": OS verifier not configured by default")
		check(not manager.binding_matches(binding,true), mode + ": negative PID cannot be ready")
		for field in ["room", "pid", "instance_id", "authority_host_mode"]:
			var stale:Dictionary = binding.duplicate(true)
			stale[field] = 124 if field == "pid" else "invalid"
			check(not manager.binding_matches(stale,true), mode + ": stale binding " + field)
		manager.rooms.clear() # 析构时不得对合成 PID 调用 OS.kill。
	print("RESULT ", JSON.stringify({"suite":"authority_worker_ready_contract","checks":checks,"failures":failures,"scope":"production_validator_unit_only"}))
	get_tree().quit(0 if failures.is_empty() else 1)
