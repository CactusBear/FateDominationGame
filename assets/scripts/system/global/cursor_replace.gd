extends Node


# Load the custom images for the mouse cursor.
var cursor_norm = preload("res://assets/images/ui/cursor/cursor_norm.png")
var pointing = preload("res://assets/images/ui/cursor/cursor_pointing.png")
var cursor_disabled = preload("res://assets/images/ui/cursor/cursor_disabled.png")


func _ready():
	Input.set_custom_mouse_cursor(cursor_norm)
	Input.set_custom_mouse_cursor(pointing, Input.CURSOR_POINTING_HAND)
	Input.set_custom_mouse_cursor(cursor_disabled, Input.CURSOR_FORBIDDEN)
