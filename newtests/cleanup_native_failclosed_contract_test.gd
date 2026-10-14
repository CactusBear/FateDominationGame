extends Node

## Reuse the existing explicitly synthetic registrar/lease; this is NOT a second registry.
const Fixtures = preload("res://newtests/round74_cleanup_handoff_contract_test.gd")
const Collector = preload("res://scripts/net/server/temporary_cleanup_proof_collector.gd")
const Ledger = preload("res://scripts/net/server/temporary_cleanup_ledger.gd")
var checks:Array = []
var outcomes:Array = []

func _check(name:String, ok:bool) -> void:
	checks.append({"name":name,"ok":ok})
	print("CHECK ",name," ",ok)

func _write(path:String, value:Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		_check("fixture_write",false)
		return
	file.store_string(JSON.stringify(value))
	file.close()

func _deny(name:String, result:Dictionary, reason:String) -> void:
	# UNKNOWN is the evidence interpretation, not an invented production result field.
	outcomes.append({"case":name,"expected_evidence":"UNKNOWN","expected_decision":"deny","actual":result})
	_check(name+"_unknown_deny",result.get("ok") == false and result.get("error") == reason and not result.has("candidates") and not result.has("lifecycle_proof") and result.get("removed_files",0) == 0)

func _ready() -> void:
	var root:String = ProjectSettings.globalize_path("res://owned_data")
	DirAccess.make_dir_recursive_absolute(root)
	var binding:Dictionary = {"room":"native-failclosed-contract","pid":OS.get_process_id(),"instance_id":"fixture-instance","authority_host_mode":"dedicated_server"}
	var id:String = "2".repeat(32)
	var artifact:String = root.path_join(id+".request.json")
	_write(artifact,{"contract_test_only":true})
	var file := FileAccess.open(artifact,FileAccess.READ)
	var size:int = file.get_length()
	file.close()
	var digest:String = FileAccess.get_sha256(artifact)
	var released:Dictionary = binding.merged({"request_id":id})
	var record:Dictionary = {"artifact_id":id+":request","source":"server_console_channel.close:request","instance_id":binding.instance_id,"path":artifact,"sha256":digest,"bytes":size,"artifact_kind":"temporary_file","save_status":"confirmed","consumed":true,"recyclable":true,"instance_exited":true,"consumed_at":0,"consumption_receipt_id":id,"exit_receipt_id":id,"save_exit_binding":released}
	var ledger_path:String = root.path_join("fixture-ledger.json")
	_write(ledger_path,{"version":1,"entries":{id:{"source":"server_console_channel.close","binding":binding,"root":root,"request_sha256":digest,"response_sha256":"0".repeat(64),"state":"consumed","consumed_at":0,"save_exit_binding":released,"records":[record]}},"runs":[]})
	var ledger = Ledger.new()
	ledger.path = ledger_path
	var ledger_digest:String = FileAccess.get_sha256(ledger_path)
	var config:Dictionary = {"approved_roots":[root],"protected_paths":[],"retention_seconds":0,"max_files":1,"max_bytes":size}
	var scope:Dictionary = {"deployment_id":"synthetic-contract-only","approved_roots":[root],"protected_paths":[]}
	var lease = Fixtures.TestLease.new()
	lease.scope = scope
	var provider = Fixtures.TestRegistration.new()
	provider.scope = scope
	provider.binding = binding
	var result:Dictionary = ledger.preview_proven(config,1,provider,lease,scope.deployment_id)
	_check("synthetic_complete_source_reaches_existing_eligibility",result.get("ok") == true and result.get("planned_files") == 1)
	_check("even_complete_fixture_is_not_execution_permission",result.get("blocked") == true and result.get("diagnostic_only") == true and result.get("removed_files") == 0 and result.get("execution_blocker") == "cleanup_execution_lease_unwired")

	for field in ["room","pid","instance_id","authority_host_mode"]:
		provider.mode = "mismatch_"+field
		_deny("identity_"+field,ledger.preview_proven(config,1,provider,lease,scope.deployment_id),"member_binding_or_generation_changed")
	for mode in ["identity_unknown","missing_native","state_unknown"]:
		provider.mode = mode
		_deny(mode,ledger.preview_proven(config,1,provider,lease,scope.deployment_id),"unknown_process_identity_or_state")
	provider.mode = "closed"
	_deny("missing_registration_source",ledger.preview_proven(config,1,null,lease,scope.deployment_id),"missing_registration_capability")
	_deny("metadata_object_is_not_registration_source",ledger.preview_proven(config,1,RefCounted.new(),lease,scope.deployment_id),"missing_registration_capability:cleanup_registration_contract")
	_deny("missing_deployment_lease",ledger.preview_proven(config,1,provider,null,scope.deployment_id),"missing_deployment_lease")

	provider.mode = "active"
	_check("active_fixture_pid_is_real_running",OS.is_process_running(binding.pid))
	result = ledger.preview_proven(config,1,provider,lease,scope.deployment_id)
	outcomes.append({"case":"active_process","expected_evidence":"KNOWN_ACTIVE","expected_decision":"deny","actual":result})
	_check("active_process_reaches_policy_as_current_not_safe",result.get("ok") == true and result.get("planned_files") == 0 and result.get("candidates",[]).is_empty() and result.get("rejected",[]).size() == 1 and result.rejected[0].reason == "current_instance" and result.lifecycle_proof.current_instances == [binding.instance_id])
	_check("active_process_execution_denied",result.get("blocked") == true and result.get("removed_files") == 0)
	provider.mode = "job_active"
	_deny("exited_root_but_job_active",ledger.preview_proven(config,1,provider,lease,scope.deployment_id),"exited_handles_not_released")
	provider.mode = "member_epoch"
	_deny("member_epoch_drift",ledger.preview_proven(config,1,provider,lease,scope.deployment_id),"member_binding_or_generation_changed")
	provider.mode = "closed"
	lease.reads = 0
	lease.drift = true
	_deny("lease_epoch_between_selection_and_revalidation",ledger.preview_proven(config,1,provider,lease,scope.deployment_id),"lifecycle_proof_changed_between_steps")
	lease.drift = false
	provider.mode = "generation_drift"
	provider.reads = 0
	_deny("registry_generation_drift",ledger.preview_proven(config,1,provider,lease,scope.deployment_id),"lifecycle_proof_changed_between_steps")
	provider.mode = "closed"
	var proof:Dictionary = Collector.collect(provider,lease,scope)
	var other = Fixtures.TestRegistration.new()
	other.scope = scope
	other.binding = binding
	other.generation = provider.generation
	_deny("same_values_different_source_object",Collector.revalidate(proof,other,lease,scope),"lifecycle_proof_changed_between_steps")
	var other_lease = Fixtures.TestLease.new()
	other_lease.scope = scope
	other_lease.epoch = lease.epoch
	_deny("same_values_different_lease_object",Collector.revalidate(proof,provider,other_lease,scope),"lifecycle_proof_changed_between_steps")

	# Metadata only. No native instantiate/load/call/spawn/terminate/release.
	var exists:bool = ClassDB.class_exists("FateProcessOwner")
	var state_available:bool = exists and ClassDB.class_has_method("FateProcessOwner","state")
	var tree_available:bool = exists and ClassDB.class_has_method("FateProcessOwner","tree_observe")
	var native:Dictionary = {"source":"real_ClassDB_metadata","class_exists":exists,"can_instantiate":exists and ClassDB.can_instantiate("FateProcessOwner"),"state_available":state_available,"tree_observe_available":tree_available,"status":"UNKNOWN","query_performed":false,"release_readback_verified":false,"production_job_zero_verified":false}
	_check("real_native_profile_matches_requested_fixture",exists == not OS.get_cmdline_user_args().has("without-native"))
	_check("native_metadata_cannot_supply_release_proof",native.status == "UNKNOWN" and native.release_readback_verified == false)
	# A missing tree method (or presence alone without a bound query) supplies no proof.
	provider.mode = "missing_native"
	_deny("real_native_observation_never_promoted_to_safe",ledger.preview_proven(config,1,provider,lease,scope.deployment_id),"unknown_process_identity_or_state")
	_check("legacy_execution_entry_still_denied",ledger.cleanup(config,1,func(): return proof).get("error") == "cleanup_execution_lease_unwired")
	_check("ledger_unchanged",FileAccess.get_sha256(ledger_path) == ledger_digest)
	file = FileAccess.open(artifact,FileAccess.READ)
	_check("artifact_reopens_unchanged",file != null and FileAccess.get_sha256(artifact) == digest)
	if file != null: file.close()
	var failures:Array = checks.filter(func(row): return not row.ok)
	var report:Dictionary = {"passed":failures.is_empty(),"checks":checks.size(),"check_rows":checks,"failures":failures,"outcomes":outcomes,"native_observation":native,"contract_test_only":true,"production_registry_verified":false,"production_auto_cleanup_enabled":false,"removed_files":0,"artifact_path":artifact,"artifact_sha256":digest,"ledger_path":ledger_path,"ledger_sha256":ledger_digest,"user_data_dir":OS.get_user_data_dir()}
	_write(ProjectSettings.globalize_path("res://result.json"),report)
	print("RESULT ",JSON.stringify({"checks":checks.size(),"failures":failures,"passed":failures.is_empty()}))
	get_tree().quit(0 if failures.is_empty() else 1)
