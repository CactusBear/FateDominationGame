extends PopupPanel

signal applied(directory: String)
var session
var source_root: String = ""
var config: Dictionary = {}
var _entries: Array = []
var _items: Array = []
var _plan: Dictionary = {}
var _preparing: bool = false
var _index: int = 0
var files_per_frame: int = 2
var _assembled: String = ""
var _download_provider: int = -1
var _download_key: String = ""
var _download_deadline: int = 0
var _download_offset: int = -1
var _validation = preload("res://scripts/net/room_validation_task.gd").new()
const LABELS := {"masters": "御主", "servants": "从者", "attacks": "攻击牌", "events": "事件牌", "situations": "局势牌"}
@onready var tree: Tree = $Margin/Content/Entries
@onready var status: RichTextLabel = $Margin/Content/Status

func _ready() -> void:
	$Margin/Content/Actions/Apply.pressed.connect(_apply)
	$Margin/Content/Actions/Close.pressed.connect(hide)
	$Margin/Content/Filter/All.pressed.connect(func(): _select_visible(true))
	$Margin/Content/Filter/None.pressed.connect(func(): _select_visible(false))
	$Margin/Content/Filter/Search.text_changed.connect(_filter)
	$RiskConfirmation.confirmed.connect(_apply_validated)
	$RiskConfirmation.canceled.connect(cancel)

func configure(active_session, directory: String, mode_config: Dictionary) -> void:
	session = active_session
	config = mode_config.duplicate(true)
	var chosen: Dictionary = {}
	for index in range(_items.size()):
		chosen[_entries[index].provider + ":" + _entries[index].key] = _items[index].is_checked(0)
	cancel()
	source_root = directory
	var catalog = preload("res://scripts/net/data_catalog.gd").new()
	_entries = catalog.scan(source_root, "host").filter(func(entry): return entry.category != "command_spells")
	if session._host:
		for id in session.catalogs:
			if id != 1 and session.room.members.has(id) and session.room.members[id].connected:
				_entries.append_array(session.catalogs[id])
	$Margin/Content/Title.text = "房间数据 · 选择玩家与条目" if session._host else "共享本机条目"
	$Margin/Content/Actions/Apply.text = "校验并应用" if session._host else "共享所选条目"
	$Margin/Content/Budget.visible = session._host
	tree.clear()
	_items.clear()
	var root := tree.create_item()
	var groups: Dictionary = {}
	for entry in _entries:
		var group_key: String = entry.provider + ":" + entry.category
		if not groups.has(group_key):
			groups[group_key] = tree.create_item(root)
			var provider_name: String = "本机" if entry.provider == "host" else str(session.room.members[int(entry.provider)].name)
			groups[group_key].set_text(0, provider_name + " · " + LABELS.get(entry.category, entry.category))
		var item := tree.create_item(groups[group_key])
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_editable(0, true)
		item.set_checked(0, chosen.get(entry.provider + ":" + entry.key, entry.provider == "host"))
		item.set_text(0, str(entry.get("label", entry.name)))
		item.set_metadata(0, _items.size())
		_items.append(item)
	status.text = ("按玩家选择条目。同名内容冲突时仅保留所需来源。" if session._host else "只共享勾选条目。共享不代表房主已批准使用。") if catalog.errors.is_empty() else "\n".join(catalog.errors)

func _select_visible(value: bool) -> void:
	if _preparing or _validation.running:
		return
	for item in _items:
		if item.visible:
			item.set_checked(0, value)

func _filter(text: String) -> void:
	for index in range(_items.size()):
		var entry: Dictionary = _entries[index]
		_items[index].visible = text.is_empty() or text.to_lower() in str(entry.get("label", entry.name)).to_lower() or text.to_lower() in entry.name.to_lower()

func _apply() -> void:
	if session == null or session.view.get("phase") != "lobby" or _preparing or _validation.running:
		return
	var selected: Array = []
	for index in range(_items.size()):
		if _items[index].is_checked(0):
			selected.append(_entries[index])
	if not session._host:
		status.text = "所选条目已共享，等待房主选择。" if session.share_catalog(source_root, selected) else session.error
		return
	var catalog = preload("res://scripts/net/data_catalog.gd").new()
	var base: Array = []
	for relative in catalog._files(source_root, "card_backs") + catalog._files(source_root, "command_spells") + ["selection_modes.json"]:
		if relative.get_extension().to_lower() not in catalog.EXTENSIONS:
			continue
		var handle := FileAccess.open(source_root.path_join(relative), FileAccess.READ)
		if handle == null:
			status.text = "基础集合文件不可读：" + relative
			return
		base.append({"provider": "host", "path": relative, "hash": FileAccess.get_sha256(source_root.path_join(relative)), "size": handle.get_length()})
	_plan = preload("res://scripts/net/room_data_plan.gd").new().build(selected, base)
	if not _plan.ok:
		status.text = _plan.error + "\n" + JSON.stringify(_plan.conflicts if not _plan.conflicts.is_empty() else _plan.dependencies)
		return
	if $Margin/Content/Budget/Seconds.value <= 0:
		status.text = "数据校验时间预算必须大于零"
		return
	_preparing = true
	_index = 0
	_assembled = "user://net_session/%d-%d/data" % [OS.get_process_id(), Time.get_ticks_usec()]
	_set_busy(true)

func _process(_delta: float) -> void:
	if not _preparing and not _validation.running and not $RiskConfirmation.visible:
		return
	if session == null or not session._host or session.room.phase != "lobby":
		cancel()
		return
	if $RiskConfirmation.visible:
		return
	if _preparing:
		for _step in range(files_per_frame):
			if _index >= _plan.files.size():
				break
			var file: Dictionary = _plan.files[_index]
			var source: Dictionary = _plan.sources[_index]
			var content: PackedByteArray
			if source.provider == "host":
				content = FileAccess.get_file_as_bytes(source_root.path_join(source.path))
			else:
				content = session.blobs.cache.fetch(file.hash)
				if content.size() != file.size or content.is_empty():
					if _download_key != file.hash:
						_download_provider = int(source.provider)
						_download_key = file.hash
						_download_offset = -1
						_download_deadline = Time.get_ticks_msec() + int($Margin/Content/Budget/Seconds.value * 1000.0)
						if not session.download_provider_blob(_download_provider, file.hash, file.size):
							_fail("无法从所选提供者获取文件：" + source.path)
							return
					var offset: int = session.blobs.offset_for(_download_provider, file.hash)
					if offset > _download_offset:
						_download_offset = offset
						_download_deadline = Time.get_ticks_msec() + int($Margin/Content/Budget/Seconds.value * 1000.0)
					if offset < 0 or Time.get_ticks_msec() >= _download_deadline:
						_fail("提供者下载失败或超时：" + source.path)
						return
					break
			_download_key = ""
			_download_provider = -1
			if not session.blobs.cache.store(file.hash, content) or session.publish_blob(content) != file.hash:
				_fail("所选文件已变化或无法发布：" + _plan.sources[_index].path)
				return
			_index += 1
		status.text = "正在准备批准数据：%d / %d" % [_index, _plan.files.size()]
		if _index == _plan.files.size():
			var catalog = preload("res://scripts/net/data_catalog.gd").new()
			for entry in _plan.entries:
				if not catalog.verify_content(entry, session.blobs.cache):
					_fail("\n".join(catalog.errors))
					return
			var assembler = preload("res://scripts/net/room_data_assembler.gd").new()
			_preparing = false
			if not assembler.assemble(_assembled, _plan.files, session.blobs.cache):
				_fail(assembler.error)
			elif not _validation.start(_assembled, _plan.files, $Margin/Content/Budget/Seconds.value):
				_fail(_validation.error)
		return
	_validation.poll()
	status.text = "正在独立进程中校验所选数据"
	if not _validation.running:
		if not _validation.complete:
			_fail(_validation.error)
		else:
			var report: Dictionary = _validation.report.get("loop_analysis", {})
			if report.get("cycles", []).any(func(group): return group.risk == "high") or not report.get("warnings", []).is_empty():
				$RiskConfirmation/Report.text = _risk_text(report)
				$RiskConfirmation.popup_centered()
				status.text = "静态预检发现风险，等待房主确认。风险报告不等于确定死循环。"
			else:
				_apply_validated()

func _risk_text(report: Dictionary) -> String:
	var origins: Dictionary = {}
	for index in range(_plan.files.size()):
		var source: Dictionary = _plan.sources[index]
		var provider: String = source.provider
		var label := "本机" if provider == "host" else str(session.room.members.get(int(provider), {}).get("name", provider))
		origins[_plan.files[index].path] = label + " · " + source.path
	var lines: Array[String] = ["以下是静态风险，不是确定死循环。条件与动态效果需进一步验证。"]
	for group in report.get("cycles", []):
		lines.append("\n高风险环" if group.risk == "high" else "\n有限制的风险环")
		for id in group.nodes:
			var node: Dictionary = report.nodes[id]
			lines.append(node.name + " · " + origins.get(node.path, "来源未声明 · " + node.path) + "\n" + node.pointer)
	for item in report.get("warnings", []):
		var node: Dictionary = report.nodes[item.node]
		lines.append("\n循环步骤风险 · " + node.name + " · " + origins.get(node.path, node.path))
	for item in report.get("unknowns", []):
		lines.append("\n无法静态确认 · " + item.reason + " · " + origins.get(item.path, item.path) + "\n" + item.pointer)
	return "\n".join(lines)

func _apply_validated() -> void:
	if session == null or not session._host or session.room.phase != "lobby" or not _validation.complete:
		_fail("当前房间无法应用这次校验结果")
		return
	if not session.set_room_files(_plan.files) or not session.adopt_room_data(_validation, config):
		_fail(session.error)
		return
	status.text = "房间数据已应用。等待成员同步。"
	_set_busy(false)
	applied.emit(_validation.directory.path_join("validation-data"))

func _set_busy(value: bool) -> void:
	$Margin/Content/Actions/Apply.disabled = value
	$Margin/Content/Filter/All.disabled = value
	$Margin/Content/Filter/None.disabled = value
	$Margin/Content/Budget/Seconds.editable = not value
	for item in _items:
		item.set_editable(0, not value)

func _fail(reason: String) -> void:
	cancel()
	status.text = reason

func cancel() -> void:
	_preparing = false
	if session != null and _download_provider >= 0 and not _download_key.is_empty():
		session.blobs.cancel_blob(_download_provider, _download_key)
	_download_provider = -1
	_download_key = ""
	_validation.cancel()
	if is_node_ready():
		$RiskConfirmation.hide()
		_set_busy(false)

func _exit_tree() -> void:
	_validation.cancel()

func reset_selection() -> void:
	cancel()
	_entries.clear()
	_items.clear()
	if is_node_ready():
		tree.clear()
