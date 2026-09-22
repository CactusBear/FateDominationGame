extends Node


# Load the custom images for the mouse cursor.
var cursor_norm = preload("res://assets/images/ui/cursor/cursor_norm.png")
var pointing = preload("res://assets/images/ui/cursor/cursor_pointing.png")
var cursor_disabled = preload("res://assets/images/ui/cursor/cursor_disabled.png")


func _ready():
	Input.set_custom_mouse_cursor(cursor_norm)
	Input.set_custom_mouse_cursor(pointing, Input.CURSOR_POINTING_HAND)
	Input.set_custom_mouse_cursor(cursor_disabled, Input.CURSOR_FORBIDDEN)


func _exit_tree():
	# Input 会持有自定义光标直到进程退出；解除注册后再释放本节点引用，
	# 否则窗口关闭时三张光标纹理仍留在渲染服务器。
	Input.set_custom_mouse_cursor(null)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_FORBIDDEN)
	cursor_norm = null
	pointing = null
	cursor_disabled = null
