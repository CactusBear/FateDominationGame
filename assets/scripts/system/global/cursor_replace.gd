extends Node


# Load the custom images for the mouse cursor.
var arrow_male = load("res://arrow_male.png")
var pointing = load("res://pointing_male.png")


func _ready():
	# Changes only the arrow shape of the cursor.
	# This is similar to changing it in the project settings.
	Input.set_custom_mouse_cursor(arrow_male)

	# Changes a specific shape of the cursor (here, the I-beam shape).
	Input.set_custom_mouse_cursor(pointing, Input.CURSOR_POINTING_HAND)
