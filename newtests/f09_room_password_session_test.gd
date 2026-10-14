extends Node

const Password = preload("res://scripts/net/identity/room_password.gd")
const Transaction = preload("res://scripts/net/session/host_room_password_request.gd")
const DENIED:String = "只有房主能在大厅设置房间密码"
const SAVE_FAILED:String = "房间密码保存失败，原设置未改变"
var checks:int = 0
var failures:Array = []

class ObservedPassword extends "res://scripts/net/identity/room_password.gd":
	var setter_calls:int = 0
	var setter_succeeds:bool = true
	func set_password(value:String) -> bool:
		setter_calls += 1
		if not setter_succeeds: return false
		return super.set_password(value)

class ObservedTransaction extends "res://scripts/net/session/host_room_password_request.gd":
	var calls:int = 0
	func receive(password:Password, value:String, persist:Callable) -> Dictionary:
		calls += 1
		return super.receive(password,value,persist)

class ObservedSession extends "res://scripts/net/session/lobby_session.gd":
	var persist_calls:int = 0
	var persist_succeeds:bool = true
	var real_persistence:bool = false
	var published:int = 0
	var saved_verifier:Dictionary = {}
	var saved_revision:int = -1
	var publications:Array = []
	var rejection_notices:Array = []
	var legacy_notices:Array = []
	func _persist_recovery_state() -> bool:
		persist_calls += 1
		saved_verifier = room_password.verifier.duplicate(true)
		saved_revision = room.revision
		if real_persistence: return super._persist_recovery_state()
		return persist_succeeds
	# 只观察发布边界，不让发布阶段再次落盘掩盖请求事务次数。
	func _publish(_persist_recovery:bool = true) -> void:
		published += 1
		publications.append({"revision":room.revision,"password_required":not room_password.verifier.is_empty()})
	func observe_rejection(sequence:int, reason:String) -> void:
		rejection_notices.append({"sequence":sequence,"reason":reason})
	func observe_legacy(reason:String) -> void:
		legacy_notices.append(reason)

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var session = ObservedSession.new()
	var password = ObservedPassword.new()
	var transaction = ObservedTransaction.new()
	session.room_password = password
	session._host = true
	session.room.owner = 1
	session.room.phase = "lobby"
	session.room.members[1] = {"connected":true,"spectator":false}
	session.room.revision = 10
	session.recovery_state_path = "user://fixture-only-password-state.json"
	session.request_rejected.connect(session.observe_rejection)
	session.rejected.connect(session.observe_legacy)
	var wired:bool = false
	for property in session.get_property_list():
		if property.name == "_host_room_password_request": wired = true
	check(wired,"Session owns reusable password request transaction")
	if wired: session.set("_host_room_password_request",transaction)

	check(session.request("room_password",{"password":"fixture-first-password"}) == OK,"公开请求入口发送成功")
	check(transaction.calls == 1,"合法请求进入现有密码事务模块")
	check(password.setter_calls == 1 and session.persist_calls == 1,"合法请求setter与persist各一次")
	check(password.accepts("fixture-first-password") and not password.accepts("fixture-wrong"),"真实密码原语设置成功")
	check(session.saved_verifier == password.verifier and session.saved_revision == 10,"先保存新verifier再增加revision")
	check(session.room.revision == 11 and session.published == 1 and session.publications.back() == {"revision":11,"password_required":true},"成功仅一次revision并沿原发布边界")
	check(session.rejection_notices.is_empty() and session.legacy_notices.is_empty(),"成功不发拒绝通知")

	var old_verifier:Dictionary = password.verifier.duplicate(true)
	for invalid in ["owner","phase","type"]:
		session.room.owner = 2 if invalid == "owner" else 1
		session.room.phase = "playing" if invalid == "phase" else "lobby"
		var args:Dictionary = {"password":123 if invalid == "type" else "fixture-denied"}
		var old_notices:int = session.rejection_notices.size()
		var old_sequence:int = session._seq
		check(session.request("room_password",args) == OK,invalid+"请求仍沿同步拒绝合同")
		check(password.setter_calls == 1 and session.persist_calls == 1 and transaction.calls == 1,invalid+"前置门不进入setter/persist/事务")
		check(password.verifier == old_verifier and session.room.revision == 11 and session.published == 1,invalid+"拒绝保留状态且不发布")
		check(session.rejection_notices.size() == old_notices+1 and session.rejection_notices.back() == {"sequence":old_sequence+1,"reason":DENIED} and session.error == DENIED and session.legacy_notices.back() == DENIED,invalid+"拒绝保留原error及关联通知")

	session.room.owner = 1
	session.room.phase = "lobby"
	session.persist_succeeds = false
	var notice_count:int = session.rejection_notices.size()
	check(session.request("room_password",{"password":"fixture-unsaved"}) == OK,"保存失败请求返回原发送状态")
	check(password.setter_calls == 2 and session.persist_calls == 2 and transaction.calls == 2,"保存失败实际进入setter/persist事务")
	check(password.verifier == old_verifier and password.accepts("fixture-first-password") and not password.accepts("fixture-unsaved"),"保存失败恢复原verifier")
	check(session.room.revision == 11 and session.published == 1,"保存失败不增revision也不发布")
	check(session.error == SAVE_FAILED and session.rejection_notices.size() == notice_count+1 and session.rejection_notices.back() == {"sequence":session._seq,"reason":SAVE_FAILED} and session.legacy_notices.back() == SAVE_FAILED,"保存失败发原文关联拒绝通知")

	# setter失败必须短路persist；不重复模块完整专项。
	password.setter_succeeds = false
	check(session.request("room_password",{"password":"fixture-setter-failure"}) == OK,"setter失败沿公开请求拒绝")
	check(password.setter_calls == 3 and session.persist_calls == 2 and transaction.calls == 3,"setter失败不调用persist")
	check(password.verifier == old_verifier and session.room.revision == 11 and session.published == 1 and session.error == SAVE_FAILED,"setter失败保持原状态及失败文案")
	password.setter_succeeds = true
	session.persist_succeeds = true
	notice_count = session.rejection_notices.size()
	check(session.request("room_password",{"password":""}) == OK,"取消密码沿公开请求成功")
	check(password.setter_calls == 4 and session.persist_calls == 3 and transaction.calls == 4 and session.saved_verifier.is_empty(),"取消密码仍调用原setter并保存空verifier")
	check(password.verifier.is_empty() and password.accepts("fixture-anything") and session.room.revision == 12 and session.published == 2 and session.publications.back() == {"revision":12,"password_required":false},"取消密码保留原语义及单次revision发布")
	check(session.rejection_notices.size() == notice_count,"取消成功不新增拒绝通知")

	# 无路径必须由Session提供显式成功noop，不能调用真实持久化入口。
	session.recovery_state_path = ""
	session.persist_succeeds = false
	check(session.request("room_password",{"password":"fixture-ephemeral"}) == OK,"无路径请求成功")
	check(password.setter_calls == 5 and session.persist_calls == 3 and transaction.calls == 5,"无路径事务不调用持久化入口")
	check(password.accepts("fixture-ephemeral") and session.room.revision == 13 and session.published == 3 and session.rejection_notices.size() == notice_count,"显式成功noop保持成功revision与发布")
	if wired: check(session.get("_host_room_password_request") == transaction,"多次请求复用同一事务实例")

	# 极小真实落盘闭环；不启动监听、不恢复对局、不依赖替换旧文件的native能力。
	var disk = ObservedSession.new()
	disk._host = true
	disk.real_persistence = true
	disk.room.owner = 1
	disk.room.phase = "lobby"
	disk.room.members[1] = {"connected":true,"spectator":false}
	disk.room.revision = 20
	disk.request_rejected.connect(disk.observe_rejection)
	disk.rejected.connect(disk.observe_legacy)
	var directory:String = "user://password-wiring-%d" % OS.get_process_id()
	check(DirAccess.make_dir_recursive_absolute(directory) == OK,"真实落盘夹具目录创建")
	disk.recovery_state_path = directory.path_join("state.json")
	check(disk.request("room_password",{"password":"fixture-disk-password"}) == OK,"真实持久化经公开请求发送")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(disk.recovery_state_path))
	check(saved is Dictionary and saved.get("room_password") == disk.room_password.verifier and disk.room_password.accepts("fixture-disk-password"),"真实恢复文件读回新verifier但不输出凭据")
	check(disk.persist_calls == 1 and disk.room.revision == 21 and disk.published == 1 and disk.rejection_notices.is_empty(),"真实保存成功单次revision及原发布")
	var original_path:String = disk.recovery_state_path
	var disk_verifier:Dictionary = disk.room_password.verifier.duplicate(true)
	disk.recovery_state_path = directory # 目标是既有目录，原生产路径门必须真实拒绝。
	check(disk.request("room_password",{"password":"fixture-disk-unsaved"}) == OK,"真实失败路径经公开请求发送")
	check(disk.persist_calls == 2 and disk.room_password.verifier == disk_verifier and disk.room.revision == 21 and disk.published == 1,"真实保存失败回滚verifier且不revision/publish")
	check(disk.error == SAVE_FAILED and disk.rejection_notices.back() == {"sequence":disk._seq,"reason":SAVE_FAILED} and disk.legacy_notices.back() == SAVE_FAILED,"真实保存失败关联拒绝正确")
	var still_saved = JSON.parse_string(FileAccess.get_file_as_string(original_path))
	check(still_saved is Dictionary and still_saved.get("room_password") == disk_verifier,"真实保存失败保留已有文件")
	check(DirAccess.remove_absolute(original_path) == OK,"清除专属夹具旧文件以验初次提交取消密码")
	disk.recovery_state_path = original_path
	check(disk.request("room_password",{"password":""}) == OK,"真实取消密码经公开入口")
	var cleared = JSON.parse_string(FileAccess.get_file_as_string(original_path))
	check(cleared is Dictionary and cleared.get("room_password") == {} and disk.room_password.verifier.is_empty() and disk.room.revision == 22 and disk.persist_calls == 3 and disk.published == 2,"真实取消密码落盘空verifier及单次revision发布")
	check(DirAccess.remove_absolute(original_path) == OK and DirAccess.remove_absolute(directory) == OK,"仅清理自有密码落盘夹具")
	print("USER_PATH ",OS.get_user_data_dir())
	print("RESULT ",JSON.stringify({"suite":"f09_room_password_session","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
