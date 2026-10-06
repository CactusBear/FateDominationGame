class_name MatchReplay
extends RefCounted

## 显式录制会话。恢复重跑原引擎，不反序列化 Object/Callable，不接收远端存档。
const Journal = preload("res://scripts/match/match_journal.gd")
const Ids = preload("res://scripts/match/net_ids.gd")
const Driver = preload("res://scripts/match/match_driver.gd")
const Commands = preload("res://scripts/match/match_commands.gd")
const RuleRandom = preload("res://scripts/match/rule_random.gd")
const RuleState = preload("res://scripts/match/rule_state.gd")
const COMMANDS: Array = ["submit_group", "request_manual_activation", "set_card_concealed", "deploy", "move", "submit_option_choice", "submit_active_choice", "cancel_pending_choice", "submit_card_selection", "submit_player_selection", "submit_location_selection", "confirm_battle_broadcast", "end_current_player_action"]
var error: String = ""
var error_index: int = -1
var truncated: bool = false
var driver = Driver.new()
var commands = Commands.new()
var ids = Ids.new()
var journal = Journal.new()
var _entropy := RandomNumberGenerator.new()
var _last_hash: String = ""
var _recording: bool = false
var _source_data: String = ""
var _restored_folder: String = ""

func begin(folder: String, players: Array, match_seed: int, assignments: Dictionary = {}, order: Array = []) -> bool:
	error = ""
	if FileAccess.file_exists(folder.path_join("match.log")):
		error = "存档已存在，不覆盖"
		return false
	_source_data = LoadHelper.get_data_dir()
	var archive := folder.path_join("data")
	if not _copy_data(_source_data, archive):
		return false
	var header := {"format": 1, "engine": _engine_hash(), "data": _manifest(archive), "players": players, "assignments": assignments, "order": order, "seed": match_seed, "local_id": GameData.player_id, "default_master": GameData.default_master, "default_servant": GameData.default_servant}
	if not _start(header, archive):
		return false
	header["initial_hash"] = state_hash()
	if not error.is_empty():
		return false
	if not journal.create(folder.path_join("match.log"), header):
		error = journal.error
		return false
	_last_hash = header.initial_hash
	_recording = true
	return true

func _start(header: Dictionary, archive: String) -> bool:
	LoadHelper.session_data_dir = archive
	GameStart.end_session()
	GameData.player_id = int(header.local_id)
	GameData.default_master = str(header.default_master)
	GameData.default_servant = str(header.default_servant)
	DummyBot._phase_attempt_scope = ""
	DummyBot._phase_attempted_effect_ids.clear()
	driver = Driver.new()
	ids = Ids.new()
	ids.data_root = archive
	var assignments: Dictionary = {}
	for id in header.assignments:
		var declared: Dictionary = header.assignments[id]
		var master = _template(GameData.loaded_masters, str(declared.get("master", "")))
		var servant = _template(GameData.loaded_servants, str(declared.get("servant", "")))
		if master == null or servant == null:
			error = "存档阵容模板不存在"
			return false
		assignments[id] = {"master": master, "servant": servant}
	_entropy.seed = int(header.seed)
	RuleRandom.start_seed(int(header.seed))
	if not GameStart.game_start(header.players, assignments, header.order):
		error = "存档开局参数无效"
		return false
	return true

func perform(kind: String, args: Array = []):
	if not _recording or not error.is_empty():
		return null
	if not _allowed(kind):
		error = "未知存档操作: " + kind
		return null
	var before := state_hash()
	if before != _last_hash:
		error = "存在未记录的规则修改，请勿继续写入此存档"
		return null
	var packed = ids.encode(args)
	if not ids.error.is_empty():
		error = ids.error
		return null
	# 每次外部动作独立保存随机入口，避免界面或其他会话消耗全局 RNG 后改变恢复。
	var action_seed: int = _entropy.randi()
	RuleRandom.start_seed(action_seed)
	var result = _execute(kind, args)
	var after := state_hash()
	var record := {"kind": kind, "args": packed, "seed": action_seed, "before": before, "after": after}
	if error.is_empty() and journal.append(record):
		_last_hash = after
	else:
		if error.is_empty():
			error = journal.error
	return result

## 回合末的 await 由真实 SceneTree 续行。把等待帧显式记录，不能用墙钟重放。
func pulse() -> void:
	if not _recording or not error.is_empty():
		return
	var before := state_hash()
	if before != _last_hash:
		error = "等待前存在未记录的规则修改"
		return
	var action_seed: int = _entropy.randi()
	RuleRandom.start_seed(action_seed)
	await GameProgress.get_tree().process_frame
	await GameProgress.get_tree().process_frame
	var after := state_hash()
	if error.is_empty() and journal.append({"kind": "frames", "args": [], "seed": action_seed, "before": before, "after": after}):
		_last_hash = after
	else:
		if error.is_empty():
			error = journal.error

func restore(folder: String) -> bool:
	close()
	error = ""
	error_index = -1
	_restored_folder = ""
	var parsed: Dictionary = journal.read_all(folder.path_join("match.log"))
	if not parsed.ok:
		error = str(parsed.error)
		error_index = int(parsed.error_index)
		return false
	truncated = bool(parsed.truncated)
	var records: Array = parsed.records
	var header: Dictionary = records[0]
	var archive := folder.path_join("data")
	if not _valid_header(header):
		error = "存档文件头字段无效"
		return false
	if header.get("format") != 1 or header.get("engine") != _engine_hash():
		error = "存档引擎版本不一致"
		return false
	if header.get("data") != _manifest(archive):
		error = "存档数据缺失或被修改"
		return false
	if not _start(header, archive):
		return false
	if state_hash() != header.get("initial_hash"):
		error = "开局状态校验失败"
		error_index = 0
		return false
	for i in range(1, records.size()):
		error_index = i
		var record: Dictionary = records[i]
		if not record.get("seed") is int or not record.get("args") is Array or not record.get("before") is String or not record.get("after") is String:
			error = "存档操作字段无效"
			return false
		if not _allowed(str(record.get("kind"))) and record.get("kind") != "frames":
			error = "存档含未知操作"
			return false
		if state_hash() != record.get("before"):
			error = "操作前状态校验失败"
			return false
		if _entropy.randi() != int(record.seed):
			error = "随机入口序列校验失败"
			return false
		RuleRandom.start_seed(int(record.seed))
		if record.kind == "frames":
			await GameProgress.get_tree().process_frame
			await GameProgress.get_tree().process_frame
		else:
			var args = ids.decode(record.args)
			if not ids.error.is_empty() or not args is Array:
				error = ids.error
				return false
			_execute(record.kind, args)
		if state_hash() != record.get("after"):
			error = "操作后状态校验失败"
			return false
		if not error.is_empty():
			return false
	error_index = -1
	_last_hash = state_hash()
	_restored_folder = folder
	return true

## 恢复只读；确认后才允许在同一日志末尾继续追加。
func resume_recording() -> bool:
	if not error.is_empty() or _restored_folder.is_empty() or truncated:
		return false
	if not journal.resume(_restored_folder.path_join("match.log")):
		error = journal.error
		return false
	_recording = true
	return true

func close() -> void:
	journal.close()
	_recording = false

func release() -> void:
	close()
	LoadHelper.session_data_dir = ""
	GameStart.end_session()

func _allowed(kind: String) -> bool:
	return kind in COMMANDS or kind in ["ai_turn", "answer_effect", "answer_card", "answer_player", "answer_location", "set_broadcast_enabled"]

func _execute(kind: String, args: Array):
	if not _valid_args(kind, args):
		error = "存档操作参数无效: " + kind
		return null
	if kind in COMMANDS:
		return commands.callv(kind, args)
	match kind:
		"set_broadcast_enabled":
			if args[0]:
				GameProgress.register_battle_broadcast_consumer(self)
			else:
				GameProgress.unregister_battle_broadcast_consumer(self)
		"ai_turn":
			driver.run_bot_turn(int(args[0]))
		"answer_effect":
			return driver.answer_effect(EffectManager.get_pending_active_effect())
		"answer_card":
			return driver.answer_card(EffectManager.get_pending_card_selection())
		"answer_player":
			return driver.answer_player(EffectManager.get_pending_player_selection())
		"answer_location":
			return driver.answer_location(EffectManager.get_pending_location_selection())
	return null

func _valid_args(kind: String, args: Array) -> bool:
	if kind == "ai_turn":
		return args.size() == 1 and args[0] is int and GameData.player_data_library.has(args[0])
	if kind == "set_broadcast_enabled":
		return args.size() == 1 and args[0] is bool
	if kind.begins_with("answer_"):
		return args.is_empty()
	for method in commands.get_method_list():
		if str(method.name) != kind:
			continue
		var declared: Array = method.args
		if args.size() > declared.size() or args.size() < declared.size() - method.default_args.size():
			return false
		for i in range(args.size()):
			var type: int = declared[i].type
			if type == TYPE_NIL:
				continue
			if type == TYPE_OBJECT:
				if args[i] == null:
					continue
				var classes := {"BaseCard": BaseCard, "BaseEffect": BaseEffect, "BaseLocation": BaseLocation}
				if not classes.has(str(declared[i].class_name)) or not is_instance_of(args[i], classes[str(declared[i].class_name)]):
					return false
			elif typeof(args[i]) != type:
				return false
		return true
	return false

func state_hash() -> String:
	var snapshot: Dictionary = RuleState.capture(ids)
	if not ids.error.is_empty():
		error = ids.error
	return Journal._digest(var_to_bytes(snapshot)).hex_encode()

func _valid_header(header: Dictionary) -> bool:
	for key in ["players", "order"]:
		if not header.get(key) is Array:
			return false
		for id in header[key]:
			if not id is int:
				return false
	for key in ["seed", "local_id"]:
		if not header.get(key) is int:
			return false
	for key in ["engine", "initial_hash", "default_master", "default_servant"]:
		if not header.get(key) is String:
			return false
	if not header.get("assignments") is Dictionary or not header.get("data") is Dictionary:
		return false
	for id in header.assignments:
		var declared = header.assignments[id]
		if not id is int or not declared is Dictionary or not declared.get("master") is String or not declared.get("servant") is String:
			return false
	return true

func _template(pool: Array, name: String):
	for object in pool:
		if object._name == name:
			return object
	return null

func _copy_data(source: String, target: String) -> bool:
	for relative in _files(source):
		var destination := target.path_join(relative)
		if DirAccess.make_dir_recursive_absolute(destination.get_base_dir()) != OK:
			error = "无法创建存档数据目录"
			return false
		var file := FileAccess.open(destination, FileAccess.WRITE)
		if file == null:
			error = "无法写入存档数据"
			return false
		file.store_buffer(FileAccess.get_file_as_bytes(source.path_join(relative)))
		file.close()
	return true

func _manifest(root: String) -> Dictionary:
	var manifest: Dictionary = {}
	for relative in _files(root):
		manifest[relative] = FileAccess.get_sha256(root.path_join(relative))
	return manifest

func _files(root: String, relative: String = "") -> Array:
	var result: Array = []
	var dir := DirAccess.open(root.path_join(relative))
	if dir == null:
		return result
	for folder in dir.get_directories():
		if not folder.begins_with("."):
			result.append_array(_files(root, relative.path_join(folder)))
	for file in dir.get_files():
		if not file.ends_with(".import") and file != "tag_list.json":
			result.append(relative.path_join(file))
	result.sort()
	return result

func _engine_hash() -> String:
	var manifest: Dictionary = {"godot": Engine.get_version_info().get("hash", "")}
	for root in ["res://scripts/system", "res://scripts/match"]:
		for relative in _files(root):
			if relative.ends_with(".gd"):
				manifest[root.path_join(relative)] = FileAccess.get_sha256(root.path_join(relative))
	manifest["start"] = FileAccess.get_sha256("res://scripts/main_menu/game_start.gd")
	return Journal._digest(var_to_bytes(manifest)).hex_encode()
