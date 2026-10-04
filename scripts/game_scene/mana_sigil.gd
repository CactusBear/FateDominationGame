extends Control

## 区间和素材由场景显式声明；只展示资源，不参与游戏规则。
@export var thresholds: PackedInt32Array
@export var textures: Array[Texture2D]
@export var colors: PackedColorArray
@export var color_values: PackedFloat32Array
@export var glow_bands: PackedInt32Array
@export var transition_seconds := 0.35
@export var number_font: Font
@export var number_width_ratio := 0.42
@export var minimum_number_size := 8
@export var negative_number_color := Color(0.65, 0.16, 0.20)

var value := 0
var band := -1
var _tween: Tween
var _hue := 0.0
var _saturation := 0.0
var _brightness := 1.0

func _ready() -> void:
	resized.connect(_resize_number)
	get_node("Number").add_theme_font_override("font", number_font)
	_resize_number()

func _resize_number() -> void:
	var label := get_node("Number") as Label
	if number_font == null:
		return
	var width := maxf(1.0, minf(size.x, size.y) * number_width_ratio)
	var font_size := maxi(minimum_number_size, int(minf(size.x, size.y) * 0.29))
	var exact := str(value)
	while font_size > minimum_number_size and number_font.get_string_size(exact, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		font_size -= 1
	var shown := exact
	if number_font.get_string_size(exact, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		var negative := value < 0
		var prefix := "-" if negative else ""
		var suffix := "-" if negative else "+"
		shown = prefix + "0" + suffix
		# 从十进制字符串求安全边界，避免 abs(INT64_MIN) 和数值乘法溢出。
		for digits in range(1, exact.trim_prefix("-").length()):
			var candidate := prefix + "9".repeat(digits) + suffix
			if number_font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
				break
			shown = candidate
		while font_size > 1 and number_font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)
	label.text = shown
	label.add_theme_color_override("font_color", negative_number_color if value < 0 else Color.from_hsv(wrapf(_hue, 0.0, 1.0), _saturation, _brightness).lightened(0.65))

func set_value(amount: int, limit: int) -> void:
	var unchanged := band >= 0 and value == amount
	value = amount
	_resize_number()
	tooltip_text = str(amount)
	var next_band := -1
	for i in thresholds.size():
		if amount >= thresholds[i]:
			next_band = i
	if next_band < 0 and not thresholds.is_empty():
		next_band = 0
	if next_band < 0 or next_band >= textures.size() or next_band >= colors.size():
		return
	if unchanged:
		return
	var image := get_node("Image") as TextureRect
	var previous := get_node("Previous") as TextureRect
	if _tween != null:
		_tween.kill()
	var shape_changed := next_band != band
	if shape_changed:
		previous.texture = image.texture
		previous.modulate.a = image.modulate.a
		(previous.material as ShaderMaterial).set_shader_parameter("breathing", glow_bands.has(band))
		image.texture = textures[next_band]
		(image.material as ShaderMaterial).set_shader_parameter("breathing", glow_bands.has(next_band))
	var target := color_for_value(amount)
	var first := band < 0
	band = next_band
	if first:
		_hue = target.h
		_saturation = target.s
		_brightness = target.v
		image.modulate.a = 1.0
		previous.modulate.a = 0.0
		_apply_color(0.0)
		return
	if shape_changed:
		image.modulate.a = 0.0
	# 色相沿最近的方向经过红、黄、绿、青，而不是 RGB 混出灰色。
	var start := Vector3(_hue, _saturation, _brightness)
	var end := Vector3(_hue + wrapf(target.h - _hue, -0.5, 0.5), target.s, target.v)
	_tween = create_tween().set_parallel(true)
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(func(t: float):
		var color := start.lerp(end, t)
		_hue = color.x
		_saturation = color.y
		_brightness = color.z
		_apply_color(t), 0.0, 1.0, transition_seconds)
	_tween.tween_property(image, "modulate:a", 1.0, transition_seconds)
	_tween.tween_property(previous, "modulate:a", 0.0, transition_seconds)

## 配色锚点独立于素材档位，正魔力在彩色锚点之间连续插值。
func color_for_value(amount: float) -> Color:
	if color_values.size() != colors.size() or colors.size() < 2:
		return colors[band] if band >= 0 and band < colors.size() else Color.WHITE
	if amount <= color_values[0]:
		return colors[0]
	if amount <= color_values[1]:
		return colors[1]
	for i in range(2, color_values.size()):
		if amount <= color_values[i]:
			var t := inverse_lerp(color_values[i - 1], color_values[i], amount)
			var a := colors[i - 1]
			var b := colors[i]
			var hue := a.h + wrapf(b.h - a.h, -0.5, 0.5) * t
			return Color.from_hsv(wrapf(hue, 0.0, 1.0), lerpf(a.s, b.s, t), lerpf(a.v, b.v, t))
	return colors[-1]

func _apply_color(_progress: float) -> void:
	var tint := Color.from_hsv(wrapf(_hue, 0.0, 1.0), _saturation, _brightness)
	for node_name in ["Image", "Previous"]:
		(get_node(node_name).material as ShaderMaterial).set_shader_parameter("tint", tint)
	(get_node("Number") as Label).add_theme_color_override("font_color", negative_number_color if value < 0 else tint.lightened(0.65))
