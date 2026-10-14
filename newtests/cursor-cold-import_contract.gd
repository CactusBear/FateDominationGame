extends Node

var _checks := 0
var _failures: Array[String] = []

func _check(ok: bool, label: String) -> void:
	_checks += 1
	print("CHECK ", ok, " ", label)
	if not ok:
		_failures.append(label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var cursor = get_node_or_null("/root/CursorReplace")
	_check(cursor != null, "production autoload exists")
	if cursor == null:
		_finish()
		return
	_check(cursor.process_mode == Node.PROCESS_MODE_ALWAYS, "cursor processes while paused")
	_check(cursor.is_processing(), "cursor polling remains enabled")
	var rows := [
		["cursor_norm", "res://assets/images/ui/cursor/cursor_norm.png"],
		["pointing", "res://assets/images/ui/cursor/cursor_pointing.png"],
		["cursor_disabled", "res://assets/images/ui/cursor/cursor_disabled.png"],
	]
	for row in rows:
		var texture = cursor.get(row[0])
		_check(texture is Texture2D, row[0] + " is nonempty Texture2D")
		if texture is Texture2D:
			_check(texture.resource_path == row[1], row[0] + " preserves resource path")
			_check(texture.get_size() == Vector2(36, 52), row[0] + " preserves original dimensions")
			print("TEXTURE ", JSON.stringify({"field":row[0], "path":texture.resource_path, "width":texture.get_width(), "height":texture.get_height()}))
	# Parse-only new() has no PNG loading side effect; initialization belongs to ready.
	var script = load("res://scripts/system/global/cursor_replace.gd")
	var detached = script.new()
	for row in rows:
		_check(detached.get(row[0]) == null, row[0] + " stays unloaded before runtime ready")
	detached.free()
	# Attach the unchanged formal Script to an already-ready empty Control.
	# This exercises its real method/root lookup, without requesting the unrelated
	# full editor _ready workflow or its scene's onready UI bindings.
	var consumer = load("res://json_maker/json_maker_ui.gd")
	_check(consumer is GDScript, "unchanged formal JSON editor script loads")
	if consumer is GDScript:
		var reader := Control.new()
		add_child(reader)
		reader.set_script(consumer)
		_check(reader.has_method("_use_drag_cursor"), "formal consumer method exists")
		_check(reader.get_node("/root/CursorReplace").get("pointing") == cursor.pointing, "formal consumer resolves same public hand texture")
		_check(reader.get_node("/root/CursorReplace").get("cursor_disabled") == cursor.cursor_disabled, "formal consumer resolves same public forbidden texture")
		reader.call("_use_drag_cursor", true)
		reader.call("_use_drag_cursor", false)
		_check(cursor.pointing is Texture2D and cursor.cursor_disabled is Texture2D, "consumer open close retains textures")
		reader.free()
		consumer = null
	# No OS mouse movement or focus manipulation. Check the actual headless state.
	await get_tree().process_frame
	_check(cursor.get("_mouse_pressed") == (get_window().has_focus() and Input.get_mouse_button_mask() != 0), "production focus and button polling matches current state")
	_finish()

func _finish() -> void:
	print("RESULT ", JSON.stringify({"suite":"cursor-cold-import", "checks":_checks, "failures":_failures, "mode":"headless-resource-contract", "consumer":"unchanged formal Script method on already-ready Control; not whole UI"}))
	get_tree().quit(0 if _failures.is_empty() else 1)
