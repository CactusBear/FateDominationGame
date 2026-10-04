extends Control

## 父节点不是 Control（如 CanvasGroup）时锚点无从参照：让本控件始终铺满当前视口可见区域，
## 子节点照常按锚点布局。
func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	var rect := get_viewport_rect()
	position = rect.position
	size = rect.size
