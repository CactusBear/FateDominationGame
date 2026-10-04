extends Control

## 主菜单（与开场动画同风格：天空云图背景 + Fate/domination 衬线标题 + 右侧拱门立绘）。
## 场景文件放图层（背景、粒子、拱门立绘、标题、白幕、toast），
## 菜单列表由本脚本按 ENTRIES 声明生成，改入口、文案只改声明，不碰节点树。
## 从开场 portal 转场（终态全白）进入，_ready 时从白场淡入。

## ---------- 声明 ----------

## 菜单入口。数组顺序即显示顺序。
## scene：选中后要切换到的场景，为空则提示尚未接入。
## planned：true 表示功能预定，中文名后跟「预定」标签且不可进入。
## quit：true 表示该项直接退出游戏。
const ENTRIES: Array = [
	{"en": "START GAME", "cn": "开始游戏",
	 "scene": "res://assets/scenes/main_menu/selection_screen.tscn"},
	{"en": "CARD EDITOR", "cn": "编辑器",
	 "scene": "res://json_maker/json_maker.tscn"},
	{"en": "DATABASE", "cn": "数据库", "planned": true},
	{"en": "SETTINGS", "cn": "设置", "planned": true},
	{"en": "QUIT", "cn": "退出游戏", "quit": true},
]

## 配色（与开场文字同系：米白主文字、金色点缀）
const C_TEXT := Color(1, 0.975, 0.92)
const C_GOLD := Color(0.95, 0.83, 0.56)
const C_DIM := Color(0.88, 0.86, 0.8, 0.75)

## 菜单项英文：Bodoni Moda（SIL OFL），与标题同族；可变字体 wght 轴控制字重
const LATIN_FONT := "res://assets/fonts/BodoniModa-Variable.ttf"
## 菜单项中文：江城尖刃黑（SIL OFL，思源黑体改造，尖锐突刺、纵横粗细分明）
const CN_FONT := "res://assets/fonts/JiangChengJianRenHei.ttf"
const WEIGHT_AXIS := 2003265652

## 尺寸（1920×1080 舞台）
const NAV_RECT := Rect2(128, 460, 560, 0)
const NAV_ITEM_HEIGHT := 100
const NAV_BODY_X := 44
const NAV_BODY_X_SELECTED := 66
## 「退出游戏」与上方功能项之间的间隔
const QUIT_GAP := 44

const FADE_SECONDS := 0.9
const TOAST_SECONDS := 1.6
const RISE_SECONDS := 0.7
const RISE_OFFSET := 26.0

## ---------- 运行期 ----------

@onready var _content: Control = $Content
@onready var _fade: ColorRect = $Fade
@onready var _toast: PanelContainer = $Toast

var _latin: Font
var _cn_regular: Font
var _cn_bold: Font

var _nav_items: Array[Control] = []
var _selected := 0
var _switching := false
var _rise_tweens: Array[Tween] = []


func _ready() -> void:
	_setup_fonts()
	_setup_toast()
	_build_nav(_content)
	_select(0, false)
	_play_enter()


## ---------- 输入 ----------

func _unhandled_input(event: InputEvent) -> void:
	if _switching or not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey:
		match event.keycode:
			KEY_DOWN:
				_select(_selected + 1)
			KEY_UP:
				_select(_selected - 1)
			KEY_ENTER, KEY_KP_ENTER:
				_activate(_selected)
			_:
				return
		get_viewport().set_input_as_handled()


## ---------- 字体 ----------

func _setup_fonts() -> void:
	_latin = _weighted(load(LATIN_FONT), 500)
	_cn_regular = load(CN_FONT)
	_cn_bold = _cn_regular


## 可变字体按 wght 轴取字重
func _weighted(base: Font, weight: int) -> Font:
	var variation := FontVariation.new()
	variation.base_font = base
	variation.variation_opentype = {WEIGHT_AXIS: weight}
	return variation


## 字距不是 Font 的属性，要包一层 FontVariation；spacing 为 0 时直接用原字体
func _spaced(base: Font, spacing: int) -> Font:
	if spacing == 0:
		return base
	var variation := FontVariation.new()
	variation.base_font = base
	variation.spacing_glyph = spacing
	return variation


func _label(text: String, size: int, color: Color, font: Font, spacing := 0) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_override("font", _spaced(font, spacing))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _line(color: Color, rect: Rect2) -> ColorRect:
	var line := ColorRect.new()
	line.color = color
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.position = rect.position
	line.size = rect.size
	return line


## ---------- 菜单 ----------

func _build_nav(root: Control) -> void:
	var nav := Control.new()
	nav.name = "Nav"
	nav.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav.position = NAV_RECT.position
	nav.size = Vector2(NAV_RECT.size.x, NAV_ITEM_HEIGHT * ENTRIES.size() + QUIT_GAP)
	root.add_child(nav)
	var y := 0.0
	for i in ENTRIES.size():
		if ENTRIES[i].get("quit", false):
			y += QUIT_GAP
		var item := _make_nav_item(ENTRIES[i], i)
		item.position = Vector2(0, y)
		nav.add_child(item)
		_nav_items.append(item)
		y += NAV_ITEM_HEIGHT


## 单个菜单项：透明按钮铺满，文字挂在 Body 上（选中时 Body 右移），金线从左侧滑出
func _make_nav_item(entry: Dictionary, index: int) -> Control:
	var item := Control.new()
	item.name = "Item%d" % index
	item.custom_minimum_size = Vector2(NAV_RECT.size.x, NAV_ITEM_HEIGHT)
	item.size = item.custom_minimum_size
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var button := Button.new()
	button.name = "Button"
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.mouse_entered.connect(_select.bind(index, true))
	button.pressed.connect(_activate.bind(index))
	item.add_child(button)

	var gold_line := _line(C_GOLD, Rect2(0, 34, 0, 2))
	gold_line.name = "GoldLine"
	item.add_child(gold_line)

	var body := Control.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.position = Vector2(NAV_BODY_X, 0)
	body.size = Vector2(NAV_RECT.size.x - NAV_BODY_X, NAV_ITEM_HEIGHT)
	item.add_child(body)

	var cn := _label(entry["cn"], 46, C_DIM, _cn_bold, 8)
	cn.name = "Cn"
	cn.position = Vector2(0, 6)
	cn.size = Vector2(body.size.x, 60)
	cn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.add_child(cn)

	var en := _label(entry["en"], 16, C_DIM, _latin, 6)
	en.name = "En"
	en.position = Vector2(2, 70)
	body.add_child(en)

	if entry.get("planned", false):
		var tag := _label("预定", 13, C_DIM, _cn_regular, 3)
		tag.name = "Planned"
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.25)
		style.border_color = Color(C_DIM, 0.5)
		style.set_border_width_all(1)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		tag.add_theme_stylebox_override("normal", style)
		# 放在中文牌名右侧：按字数估宽（40px 字 + 6 字距）
		tag.position = Vector2(entry["cn"].length() * 54 + 16, 26)
		body.add_child(tag)

	return item


## ---------- 选择与动作 ----------

func _select(index: int, animate := true) -> void:
	_selected = posmod(index, ENTRIES.size())
	for i in _nav_items.size():
		var item := _nav_items[i]
		var selected := i == _selected
		var body := item.get_node("Body") as Control
		var gold_line := item.get_node("GoldLine") as ColorRect
		var en := body.get_node("En") as Label
		var cn := body.get_node("Cn") as Label
		var cn_color := C_TEXT if selected else C_DIM
		if animate:
			var tween := create_tween().set_parallel(true)
			tween.tween_property(body, "position:x", float(NAV_BODY_X_SELECTED if selected else NAV_BODY_X), 0.25)
			tween.tween_property(gold_line, "size:x", 26.0 if selected else 0.0, 0.3)
			tween.tween_property(cn, "theme_override_colors/font_color", cn_color, 0.25)
		else:
			body.position.x = float(NAV_BODY_X_SELECTED if selected else NAV_BODY_X)
			gold_line.size.x = 26.0 if selected else 0.0
			cn.add_theme_color_override("font_color", cn_color)
		en.add_theme_color_override("font_color", C_GOLD if selected else C_DIM)


func _activate(index: int) -> void:
	_select(index)
	var entry: Dictionary = ENTRIES[index]
	if entry.get("quit", false):
		get_tree().quit()
		return
	var scene_path := str(entry.get("scene", ""))
	if scene_path == "" or entry.get("planned", false):
		_show_toast(str(entry["cn"]) + " 尚未接入")
		return
	if _switching:
		return
	_switching = true
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		_switching = false
		_show_toast("无法打开场景：" + scene_path)


func _show_toast(message: String) -> void:
	(_toast.get_node("Label") as Label).text = message
	_toast.show()
	_toast.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_toast, "modulate:a", 1.0, 0.3)
	tween.tween_interval(TOAST_SECONDS)
	tween.tween_property(_toast, "modulate:a", 0.0, 0.3)
	tween.tween_callback(_toast.hide)


func _setup_toast() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.024, 0.031, 0.051, 0.85)
	style.border_color = C_GOLD
	style.set_border_width_all(1)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_toast.add_theme_stylebox_override("panel", style)
	var toast_label := _toast.get_node("Label") as Label
	toast_label.add_theme_font_override("font", _spaced(_cn_regular, 5))
	toast_label.add_theme_font_size_override("font_size", 18)
	toast_label.add_theme_color_override("font_color", C_GOLD)


## ---------- 动效 ----------

## 进场：从白场淡入（衔接开场 portal 的全白终态），菜单项逐行淡入上移
func _play_enter() -> void:
	_fade.show()
	_fade.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(_fade.hide)
	_rise(_nav_items, 0.08)


## 逐行淡入上移，间隔 delay_step。
func _rise(controls: Array, delay_step: float) -> void:
	for tween in _rise_tweens:
		if tween.is_valid():
			tween.kill()
	_rise_tweens.clear()
	for control in controls:
		(control as Control).modulate.a = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	for i in controls.size():
		var control := controls[i] as Control
		if not is_instance_valid(control):
			continue
		var base_y := control.position.y
		control.position.y = base_y + RISE_OFFSET
		var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(control, "modulate:a", 1.0, RISE_SECONDS).set_delay(i * delay_step)
		tween.tween_property(control, "position:y", base_y, RISE_SECONDS).set_delay(i * delay_step)
		_rise_tweens.append(tween)
