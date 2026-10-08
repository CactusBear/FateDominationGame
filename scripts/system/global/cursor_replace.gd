extends Node


# 普通、鼠标按键按下和禁止操作的光标素材。
var cursor_norm = preload("res://assets/images/ui/cursor/cursor_norm.png")
var pointing = preload("res://assets/images/ui/cursor/cursor_pointing.png")
var cursor_disabled = preload("res://assets/images/ui/cursor/cursor_disabled.png")
var _mouse_pressed := false


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_cursor_images()


func _process(_delta: float) -> void:
	var pressed := get_window().has_focus() and Input.get_mouse_button_mask() != 0
	if pressed == _mouse_pressed:
		return
	_mouse_pressed = pressed
	_apply_cursor_images()


func _apply_cursor_images() -> void:
	Input.set_custom_mouse_cursor(pointing if _mouse_pressed else cursor_norm)
	Input.set_custom_mouse_cursor(pointing if _mouse_pressed else cursor_norm, Input.CURSOR_POINTING_HAND)
	Input.set_custom_mouse_cursor(pointing if _mouse_pressed else cursor_disabled, Input.CURSOR_FORBIDDEN)


func _exit_tree():
	# Input 会持有自定义光标直到进程退出；解除注册后再释放本节点引用，
	# 否则窗口关闭时三张光标纹理仍留在渲染服务器。
	Input.set_custom_mouse_cursor(null)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_FORBIDDEN)
	cursor_norm = null
	pointing = null
	cursor_disabled = null
