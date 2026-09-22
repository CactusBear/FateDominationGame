class_name DebugConsoleUI
extends CanvasLayer

## 独立调试控制台：只读页签与按钮面板共用 DebugSession 的审计和校验。

const CONSOLE_PAUSE_OWNER := "console"
const REFRESH_INTERVAL := 0.75
const OUTPUT_LIMIT := 200

var session:DebugSession
var _panel_pause_token:String = ""
var _output_lines:Array[String] = []
var _refresh_elapsed:float = 0.0
var _dragging:bool = false
var _drag_offset:Vector2 = Vector2.ZERO

@onready var _blocker:ColorRect = $InputBlocker
@onready var _panel:PanelContainer = $ConsolePanel
@onready var _header:Control = $ConsolePanel/Layout/Header
@onready var _pause_state:Label = $ConsolePanel/Layout/Header/Row/PauseState
@onready var _refresh_button:Button = $ConsolePanel/Layout/Header/Row/RefreshButton
@onready var _close_button:Button = $ConsolePanel/Layout/Header/Row/CloseButton
@onready var _tabs:TabContainer = $ConsolePanel/Layout/Body/Tabs
@onready var _players_text:TextEdit = $ConsolePanel/Layout/Body/Tabs/全体玩家
@onready var _zones_text:TextEdit = $ConsolePanel/Layout/Body/Tabs/牌区
@onready var _map_text:TextEdit = $ConsolePanel/Layout/Body/Tabs/地图
@onready var _board_text:TextEdit = $ConsolePanel/Layout/Body/Tabs/事件与局势
@onready var _wait_text:TextEdit = $ConsolePanel/Layout/Body/Tabs/效果等待
@onready var _log_text:TextEdit = $ConsolePanel/Layout/Body/Tabs/日志
@onready var _actions:DebugActionPanel = $ConsolePanel/Layout/Body/Tabs/操作
@onready var _command_output:TextEdit = $ConsolePanel/Layout/CommandOutput


func _ready() -> void:
	_blocker.visible = false
	_panel.visible = false
	_refresh_button.pressed.connect(_on_refresh_pressed)
	_close_button.pressed.connect(close_panel)
	_header.gui_input.connect(_on_header_gui_input)
	_tabs.tab_changed.connect(_on_tab_changed)
	get_viewport().size_changed.connect(_clamp_panel_to_viewport)
	set_process(true)
	if session != null:
		_actions.initialize(session, Callable(self, "_on_action_result"))
		refresh_views()


func initialize(host) -> void:
	if session != null:
		_release_console_pauses()
		# 换会话前先断开旧 Session/Registry 的互相引用，否则重复初始化会留下引用环对象。
		session.shutdown()
	session = DebugSession.new(host)
	_panel_pause_token = ""
	_refresh_elapsed = 0.0
	if is_node_ready():
		_actions.initialize(session, Callable(self, "_on_action_result"))
		refresh_views()


func toggle_panel() -> void:
	if is_panel_open():
		close_panel()
	else:
		open_panel()


func open_panel() -> void:
	if !is_node_ready():
		call_deferred("open_panel")
		return
	if session == null:
		_append_output("[错误] 控制台尚未 initialize(host)")
		return
	if is_panel_open():
		return
	_panel_pause_token = session.acquire_pause(CONSOLE_PAUSE_OWNER)
	_blocker.visible = true
	_panel.visible = true
	_refresh_elapsed = 0.0
	_clamp_panel_to_viewport()
	refresh_views()


func close_panel() -> void:
	_dragging = false
	_release_console_pauses()
	_panel_pause_token = ""
	if !is_node_ready():
		return
	_blocker.visible = false
	_panel.visible = false
	if session != null and session.host != null and session.host.has_method("discard_debug_console_pending_previews"):
		session.host.call("discard_debug_console_pending_previews")


func is_panel_open() -> bool:
	return _panel != null and _panel.visible


func safe_shutdown() -> void:
	close_panel()
	_release_console_pauses()
	if session != null:
		session.shutdown()
	session = null


func _release_console_pauses() -> void:
	if session == null:
		return
	session.release_owner_pauses(CONSOLE_PAUSE_OWNER)
	# registry 只缓存它自己签发的控制台令牌；统一释放后同步清掉失效句柄。
	session.registry._console_pause_tokens.clear()


func _on_action_result(action_label:String, result:Dictionary) -> void:
	_append_output("%s\n%s" % [action_label, _format_value(result)])
	refresh_views()


## 手动刷新：只读页签与操作页的候选项一起按当前局面重建。
## 周期刷新不会调这里——那会把玩家在操作页里做到一半的选择清掉。
func _on_refresh_pressed() -> void:
	refresh_views()
	if _actions != null:
		_actions.refresh_choices()


func refresh_views() -> void:
	if session == null:
		_set_all_views("控制台尚未初始化。")
		return
	_refresh_players()
	_refresh_zones()
	var board_result:Dictionary = session.registry.execute_action("inspect.board")
	_refresh_map(board_result)
	_refresh_board(board_result)
	_wait_text.text = _format_command_value(session.registry.execute_action("inspect.wait"))
	_refresh_logs()
	_pause_state.text = "已暂停自动推进" if session.is_paused() else "未暂停"


func _process(delta:float) -> void:
	if !is_panel_open() or session == null:
		return
	_refresh_elapsed += delta
	if _refresh_elapsed >= REFRESH_INTERVAL:
		_refresh_elapsed = 0.0
		refresh_views()


func _on_header_gui_input(event:InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_drag_offset = event.global_position - _panel.position
		else:
			_clamp_panel_to_viewport()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		_panel.position = event.global_position - _drag_offset
		_clamp_panel_to_viewport()
		get_viewport().set_input_as_handled()


func _clamp_panel_to_viewport() -> void:
	if _panel == null:
		return
	var viewport_size:Vector2 = get_viewport().get_visible_rect().size
	var maximum := Vector2(maxf(0.0, viewport_size.x - _panel.size.x), maxf(0.0, viewport_size.y - _panel.size.y))
	_panel.position = Vector2(clampf(_panel.position.x, 0.0, maximum.x), clampf(_panel.position.y, 0.0, maximum.y))


func _on_tab_changed(_tab:int) -> void:
	if is_panel_open():
		refresh_views()


func _refresh_players() -> void:
	var lines:Array[String] = []
	for id in _player_ids():
		var result:Dictionary = session.registry.execute_action("inspect.player", {"player":id})
		lines.append("玩家 %s%s" % [id, "  [本地]" if id == GameData.player_id else ""])
		lines.append(_format_command_value(result, "  "))
		lines.append("")
	_players_text.text = "\n".join(lines) if !lines.is_empty() else "没有玩家数据。"


func _refresh_zones() -> void:
	var lines:Array[String] = []
	for id in _player_ids():
		lines.append("玩家 %s%s" % [id, "  [本地]" if id == GameData.player_id else ""])
		var zones:Dictionary = DebugValidate.player_zones(id)
		var paths:Array = zones.keys()
		paths.sort()
		for raw_path in paths:
			var path:String = str(raw_path)
			var zone:Array = zones[raw_path]
			lines.append("  %s (%s)" % [path, zone.size()])
			for object in zone:
				lines.append("    %s" % _card_line(object))
		lines.append("")
	_zones_text.text = "\n".join(lines) if !lines.is_empty() else "没有牌区数据。"


func _refresh_map(board_result:Dictionary) -> void:
	if !bool(board_result.get("ok", false)):
		_map_text.text = _format_value(board_result)
		return
	var value:Dictionary = board_result.get("value", {})
	var lines:Array[String] = []
	for area in value.get("areas", []):
		lines.append("战区 %s  #%s" % [area.get("name", ""), area.get("id", "")])
		for location in area.get("locations", []):
			lines.append("  席位 #%s  玩家=%s  地利=%s  上限=%s" % [
				location.get("id", ""), location.get("players", []),
				location.get("benefit", ""), location.get("limit", "")])
		lines.append("")
	_map_text.text = "\n".join(lines) if !lines.is_empty() else "没有地图数据。"


func _refresh_board(board_result:Dictionary) -> void:
	if !bool(board_result.get("ok", false)):
		_board_text.text = _format_value(board_result)
		return
	var value:Dictionary = board_result.get("value", {})
	var lines:Array[String] = ["当前局势：%s" % _format_value(value.get("active_situation"))]
	lines.append("局势弃牌：%s" % _format_value(value.get("situation_discard", [])))
	lines.append("事件弃牌：%s" % _format_value(value.get("event_discard", [])))
	lines.append("")
	for area in value.get("areas", []):
		lines.append("%s：%s" % [area.get("name", ""), _format_value(area.get("events", []))])
	lines.append("")
	lines.append("事件模板数：%s" % LoadEvent.events.size())
	lines.append("普通局势模板数：%s" % LoadSituation.situations.size())
	lines.append("高潮局势模板数：%s" % LoadSituation.climax_situations.size())
	_board_text.text = "\n".join(lines)


func _refresh_logs() -> void:
	var rule_log:Dictionary = session.registry.execute_action("inspect.log", {"limit":100})
	var lines:Array[String] = ["规则事实", _format_command_value(rule_log), "", "调试审计", _format_value(session.audit_entries())]
	_log_text.text = "\n".join(lines)


func _player_ids() -> Array[int]:
	var result:Array[int] = []
	for raw_id in GameData.player_data_library.keys():
		result.append(int(raw_id))
	result.sort()
	return result


func _card_line(object) -> String:
	if object == null:
		return "<null>"
	var name:String = str(object.get("_name")) if "_name" in object else object.get_class()
	var shown_name:String = str(object.get_shown_name()) if object.has_method("get_shown_name") else name
	var concealed:bool = bool(object.get("_is_concealed")) if "_is_concealed" in object else false
	var template:bool = session.registry.card.is_template(object) if object is BaseCard else false
	return "%s / %s  #%s  class=%s  concealed=%s  template=%s" % [
		name, shown_name, object.get_instance_id(), object.get_class(), concealed, template]


func _format_command_value(result:Dictionary, indent:String = "") -> String:
	if !bool(result.get("ok", false)):
		return "%s[错误] %s" % [indent, result.get("error", "未知错误")]
	return _indent_text(_format_value(result.get("value", result)), indent)


func _format_value(value, depth:int = 0) -> String:
	if depth > 8:
		return "…"
	if value == null:
		return "null"
	if value is Dictionary:
		if value.is_empty():
			return "{}"
		var lines:Array[String] = []
		var keys:Array = value.keys()
		keys.sort_custom(func(a, b): return str(a) < str(b))
		for key in keys:
			var formatted:String = _format_value(value[key], depth + 1)
			lines.append("%s: %s" % [key, _indent_text(formatted, "  ").strip_edges(false, true)])
		return "\n".join(lines)
	if value is Array:
		if value.is_empty():
			return "[]"
		var lines:Array[String] = []
		for index in range(value.size()):
			var formatted:String = _format_value(value[index], depth + 1)
			lines.append("[%s] %s" % [index, _indent_text(formatted, "  ").strip_edges(false, true)])
		return "\n".join(lines)
	if value is Object:
		return "%s#%s" % [value.get_class(), value.get_instance_id()]
	return str(value)


func _indent_text(text:String, indent:String) -> String:
	if indent == "":
		return text
	return indent + text.replace("\n", "\n" + indent)


func _append_output(text:String) -> void:
	_output_lines.append(text)
	if _output_lines.size() > OUTPUT_LIMIT:
		_output_lines = _output_lines.slice(_output_lines.size() - OUTPUT_LIMIT)
	_command_output.text = "\n\n".join(_output_lines)
	_command_output.set_caret_line(maxi(0, _command_output.get_line_count() - 1))


func _set_all_views(text:String) -> void:
	_players_text.text = text
	_zones_text.text = text
	_map_text.text = text
	_board_text.text = text
	_wait_text.text = text
	_log_text.text = text
