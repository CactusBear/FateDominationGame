extends Node


# 普通、鼠标按键按下和禁止操作的光标素材。
# 只声明路径，避免首次编辑器导入前解析 autoload 就要求 PNG 已导入。
const CURSOR_NORM_PATH := "res://assets/images/ui/cursor/cursor_norm.png"
const POINTING_PATH := "res://assets/images/ui/cursor/cursor_pointing.png"
const CURSOR_DISABLED_PATH := "res://assets/images/ui/cursor/cursor_disabled.png"
var cursor_norm: Texture2D
var pointing: Texture2D
var cursor_disabled: Texture2D
var _mouse_pressed := false


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 非 tool autoload 的运行初始化才同步加载，随后再注册原有三种光标。
	cursor_norm = ResourceLoader.load(CURSOR_NORM_PATH) as Texture2D
	pointing = ResourceLoader.load(POINTING_PATH) as Texture2D
	cursor_disabled = ResourceLoader.load(CURSOR_DISABLED_PATH) as Texture2D
	_apply_cursor_images()


func _process(_delta: float) -> void:
	var pressed := get_window().has_focus() and Input.get_mouse_button_mask() != 0
	if pressed == _mouse_pressed:
		return
	_mouse_pressed = pressed
	_apply_cursor_images()


func _apply_cursor_images() -> void:
	if cursor_norm == null or pointing == null or cursor_disabled == null:
		push_error("光标纹理加载失败：%s、%s、%s" % [CURSOR_NORM_PATH, POINTING_PATH, CURSOR_DISABLED_PATH])
		return
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
