extends Control

## 进入画面 + 主菜单。视觉稿见 docs/main_menu_concept_v1/index.html。
## 场景文件只放图层（背景、立绘、暗角、粒子、黑幕），全部文字与列表由本脚本按声明生成，
## 改入口、文案、面板内容只改下面的声明，不碰节点树。
## 名单不复制图片副本：御主头像、从者卡直接读 GameData 已加载的模板（LoadGame 在 autoload 阶段读完 data/）。

## ---------- 声明 ----------

## 菜单入口。数组顺序即显示顺序。
## pane：右侧面板的构建方式（play / editor / stub / settings / quit），缺省为 stub。
## scene：主按钮要切换到的场景，为空则主按钮只提示尚未接入。
## secondary：次按钮文案，为空则不显示；次按钮的行为由 pane 决定（quit 面板是「留下」，其余提示尚未接入）。
## planned：true 表示功能预定，中文名后跟「预定」标签且主按钮不可用。
const ENTRIES: Array = [
	{"idx": "01", "en": "START GAME", "cn": "开始游戏", "hint": "进入战术版图，与六名对手争夺圣杯",
	 "pane": "play", "title": "开始游戏", "desc": "选择对局模式后进入御主与从者的选择。当前收录七名御主与七骑从者。",
	 "primary": "进入对局", "secondary": "选择御主与从者", "scene": "res://assets/scenes/game_scene/battle_board_v2.tscn"},
	{"idx": "02", "en": "CARD EDITOR", "cn": "卡牌效果编辑器", "hint": "用填空句式编写卡牌效果 JSON",
	 "pane": "editor", "title": "卡牌效果编辑器", "desc": "面向非程序员的板块式编辑器。选择时点、条件与动作，逐句拼出效果，导出为游戏可直接读取的 JSON。",
	 "primary": "打开编辑器", "secondary": "新手教程", "scene": "res://json_maker/json_maker.tscn"},
	{"idx": "03", "en": "ARCHIVE", "cn": "卡牌图鉴", "hint": "浏览全部御主、从者、事件与局势牌", "planned": true,
	 "pane": "stub", "title": "卡牌图鉴", "desc": "尚未接入。预定收录全部卡牌的高清卡面、效果说明与 ruling。", "primary": "浏览图鉴"},
	{"idx": "04", "en": "SETTINGS", "cn": "设置", "hint": "画面、音量、操作与语言", "planned": true,
	 "pane": "settings", "title": "设置", "desc": "尚未接入，以下为当前运行时的实际取值。", "primary": "保存设置"},
	{"idx": "05", "en": "QUIT", "cn": "退出游戏", "hint": "返回桌面",
	 "pane": "quit", "title": "退出游戏", "desc": "圣杯战争尚未结束。确定要离开冬木吗。", "primary": "退出", "secondary": "留下"},
]

## 开始游戏面板的模式卡。只是展示与选中态，真正的模式区分尚未接入引擎。
const PLAY_MODES: Array = [
	["本地对局", "与 AI 御主同桌，一至七人"],
	["教程", "跟随远坂凛熟悉魔力、令咒与战果"],
	["快速开始", "随机御主与从者，直接开局"],
]

const TITLE_TEXT := {
	"eyebrow": "HOLY GRAIL WAR · TACTICAL CARD GAME",
	"h1": "FATE", "h1_small": "DOMINATION", "cn": "命运支配",
	"desc": "七名御主，七骑英灵。以魔力为代价，以令咒为底牌，在冬木的夜色中争夺圣杯。",
	"press": "按任意键开始", "press_key": "ANY KEY",
	"legal": "Fate/stay night © TYPE-MOON\n概念稿 · 原作图仅供参考",
}
const BOTTOM_HINTS: Array = [["↑ ↓", "选择"], ["ENTER", "确认"], ["ESC", "返回标题"]]

## 配色（与 HTML 稿的 CSS 变量同名）
const C_INK := Color("06080d")
const C_GOLD := Color("c9a45c")
const C_GOLD2 := Color("e8cd86")
const C_GOLD3 := Color("8a6a32")
const C_TEXT := Color("efe6d2")
const C_DIM := Color("a79e8b")
const C_DIM2 := Color("6d665a")
const C_TITLE := Color("fff6dc")
const C_BUTTON_INK := Color("1a1206")

const LATIN_FONT_REGULAR := "res://assets/fonts/Cinzel-Regular.ttf"
const LATIN_FONT_BOLD := "res://assets/fonts/Cinzel-Bold.ttf"
const CN_FONT_NAMES: PackedStringArray = ["Noto Serif SC", "Source Han Serif SC", "SimSun"]
const MASK_SHADER := "res://assets/shaders/ui_mask.gdshader"

## 尺寸（1920×1080 舞台，取自 HTML 稿）
const NAV_RECT := Rect2(96, 250, 640, 0)
const NAV_ITEM_HEIGHT := 128
const NAV_BODY_X := 56
const NAV_BODY_X_SELECTED := 78
const PANEL_RECT := Rect2(1064, 250, 760, 520)
const CORNER_SIZE := 38
const CORNER_MARGIN := 28

const FADE_SECONDS := 0.55
const TOAST_SECONDS := 1.6
const RISE_SECONDS := 0.7
const RISE_OFFSET := 26.0

## ---------- 运行期 ----------

@onready var _title_screen: Control = $TitleScreen
@onready var _title_content: Control = $TitleScreen/Content
@onready var _glow: Control = $TitleScreen/Glow
@onready var _menu: Control = $Menu
@onready var _menu_content: Control = $Menu/Content
@onready var _menu_background: TextureRect = $Menu/Background
@onready var _fade: ColorRect = $Fade
@onready var _toast: PanelContainer = $Toast

var _latin_regular: Font
var _latin_bold: Font
var _cn_regular: Font
var _cn_bold: Font
var _circle_material: ShaderMaterial

var _nav_items: Array[Control] = []
var _panes: Array[Control] = []
var _crumb: Label
var _press_label: Control
var _selected := 0
var _switching := false
var _rise_tweens: Array[Tween] = []


func _ready() -> void:
	_setup_fonts()
	_build_title()
	_build_menu()
	_select(0, false)
	_start_loops()
	_play_title_enter()


## ---------- 输入 ----------

func _unhandled_input(event: InputEvent) -> void:
	if _switching or not event.is_pressed() or event.is_echo():
		return
	if _title_screen.visible:
		if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
			show_menu()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		match event.keycode:
			KEY_DOWN:
				_select(_selected + 1)
			KEY_UP:
				_select(_selected - 1)
			KEY_ENTER, KEY_KP_ENTER:
				_activate_primary()
			KEY_ESCAPE:
				show_title()
			_:
				return
		get_viewport().set_input_as_handled()


## ---------- 屏幕切换 ----------

func show_menu() -> void:
	_switch_screen(false)


func show_title() -> void:
	_switch_screen(true)


func _switch_screen(to_title: bool) -> void:
	if _switching or _title_screen.visible == to_title:
		return
	_switching = true
	_fade.show()
	_fade.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 1.0, FADE_SECONDS)
	tween.tween_callback(func() -> void:
		_title_screen.visible = to_title
		_menu.visible = not to_title
		if to_title:
			_play_title_enter()
		else:
			_select(0, false)
			_play_menu_enter()
	)
	tween.tween_property(_fade, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(func() -> void:
		_fade.hide()
		_switching = false
	)


## ---------- 字体 ----------

func _setup_fonts() -> void:
	_latin_regular = load(LATIN_FONT_REGULAR)
	_latin_bold = load(LATIN_FONT_BOLD)
	_cn_regular = SystemFont.new()
	_cn_regular.font_names = CN_FONT_NAMES
	_cn_bold = SystemFont.new()
	_cn_bold.font_names = CN_FONT_NAMES
	_cn_bold.font_weight = 700
	_circle_material = ShaderMaterial.new()
	_circle_material.shader = load(MASK_SHADER)
	_circle_material.set_shader_parameter("shape", 1)
	_circle_material.set_shader_parameter("softness", 0.02)


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


func _rect(parent: Control, rect: Rect2) -> void:
	parent.position = rect.position
	parent.size = rect.size


func _line(color: Color, rect: Rect2) -> ColorRect:
	var line := ColorRect.new()
	line.color = color
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect(line, rect)
	return line


## 边框样式：透明底 + 细边，圆角与倾斜由调用方给
func _stylebox(bg: Color, border: Color, border_width := 1, radius := 0, skew := Vector2.ZERO) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.skew = skew
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


## 四角的 L 形角标
func _add_corners(parent: Control) -> void:
	var w := float(CORNER_SIZE)
	var m := float(CORNER_MARGIN)
	var color := Color(C_GOLD, 0.55)
	var far_x := 1920.0 - m - w
	var far_y := 1080.0 - m - w
	for corner in [[m, m, true, true], [far_x, m, false, true], [m, far_y, true, false], [far_x, far_y, false, false]]:
		var x: float = corner[0]
		var y: float = corner[1]
		var left: bool = corner[2]
		var top: bool = corner[3]
		parent.add_child(_line(color, Rect2(x, y if top else y + w - 1, w, 1)))
		parent.add_child(_line(color, Rect2(x if left else x + w - 1, y, 1, w)))


## ---------- 进入画面 ----------

func _build_title() -> void:
	var root := _title_content
	_add_corners(root)

	var version := _label("BUILD %s · CONCEPT" % ProjectSettings.get_setting("application/config/version", ""), 13, C_DIM2, _latin_regular, 3)
	version.position = Vector2(48, 36)
	root.add_child(version)

	var block := VBoxContainer.new()
	block.name = "Block"
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_theme_constant_override("separation", 0)
	_rect(block, Rect2(140, 300, 820, 460))
	root.add_child(block)

	var eyebrow := HBoxContainer.new()
	eyebrow.add_theme_constant_override("separation", 18)
	eyebrow.add_child(_line(C_GOLD, Rect2(0, 0, 64, 1)))
	eyebrow.get_child(0).custom_minimum_size = Vector2(64, 1)
	eyebrow.get_child(0).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	eyebrow.add_child(_label(TITLE_TEXT["eyebrow"], 18, C_GOLD, _latin_regular, 9))
	block.add_child(eyebrow)

	var h1 := _label(TITLE_TEXT["h1"], 150, C_TITLE, _latin_bold, 2)
	h1.add_theme_color_override("font_shadow_color", Color(C_GOLD2, 0.35))
	h1.add_theme_constant_override("shadow_outline_size", 18)
	var h1_box := MarginContainer.new()
	h1_box.add_theme_constant_override("margin_top", 22)
	h1_box.add_child(h1)
	block.add_child(h1_box)

	block.add_child(_label(TITLE_TEXT["h1_small"], 64, C_GOLD2, _latin_regular, 14))

	var cn_row := HBoxContainer.new()
	cn_row.add_theme_constant_override("separation", 22)
	cn_row.add_child(_label(TITLE_TEXT["cn"], 36, C_TEXT, _cn_bold, 12))
	var rule := _line(C_GOLD3, Rect2(0, 0, 300, 1))
	rule.custom_minimum_size = Vector2(300, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cn_row.add_child(rule)
	var cn_box := MarginContainer.new()
	cn_box.add_theme_constant_override("margin_top", 34)
	cn_box.add_child(cn_row)
	block.add_child(cn_box)

	var desc := _label(TITLE_TEXT["desc"], 19, C_DIM, _cn_regular, 2)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(640, 0)
	var desc_box := MarginContainer.new()
	desc_box.add_theme_constant_override("margin_top", 18)
	desc_box.add_theme_constant_override("margin_right", 180)
	desc_box.add_child(desc)
	block.add_child(desc_box)

	var press := Button.new()
	press.name = "Press"
	press.flat = true
	press.focus_mode = Control.FOCUS_NONE
	_rect(press, Rect2(140, 920, 420, 50))
	press.pressed.connect(show_menu)
	var press_row := HBoxContainer.new()
	press_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	press_row.add_theme_constant_override("separation", 22)
	var key := _label(TITLE_TEXT["press_key"], 14, C_GOLD, _latin_regular, 2)
	key.add_theme_stylebox_override("normal", _stylebox(Color(0, 0, 0, 0.35), C_GOLD3))
	press_row.add_child(key)
	press_row.add_child(_label(TITLE_TEXT["press"], 22, C_GOLD2, _cn_regular, 8))
	press_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	press.add_child(press_row)
	root.add_child(press)
	_press_label = press

	var legal := _label(TITLE_TEXT["legal"], 13, C_DIM2, _cn_regular, 2)
	legal.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	legal.position = Vector2(1620 - 400, 912)
	legal.size = Vector2(400, 60)
	root.add_child(legal)


## ---------- 主菜单 ----------

func _build_menu() -> void:
	var root := _menu_content
	_add_corners(root)
	_build_header(root)
	_build_nav(root)
	_build_panel(root)
	_build_bottom(root)


func _build_header(root: Control) -> void:
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 26)
	_rect(header, Rect2(72, 0, 1776, 92))
	root.add_child(header)

	var logo := HBoxContainer.new()
	logo.add_theme_constant_override("separation", 10)
	logo.add_child(_label(TITLE_TEXT["h1"], 30, C_TITLE, _latin_bold, 2))
	logo.add_child(_label(TITLE_TEXT["h1_small"], 22, C_GOLD2, _latin_regular, 6))
	logo.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(logo)

	var sep := _line(C_GOLD3, Rect2(0, 0, 1, 34))
	sep.custom_minimum_size = Vector2(1, 34)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(sep)

	_crumb = _label("主菜单", 17, C_DIM, _cn_regular, 5)
	header.add_child(_crumb)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(spacer)

	# 御主档案：显示 GameData 声明的本地默认御主，没有声明或没加载到就不显示这一段
	var master = _find_named(GameStart.get_masters_can_use(), GameData.default_master)
	if master != null:
		var profile := HBoxContainer.new()
		profile.add_theme_constant_override("separation", 12)
		profile.alignment = BoxContainer.ALIGNMENT_CENTER
		profile.add_child(_avatar(master._header_img, 40))
		profile.add_child(_label(master.get_shown_name(), 15, C_TEXT, _cn_regular, 3))
		profile.add_child(_label("· 御主档案", 15, C_DIM, _cn_regular, 2))
		header.add_child(profile)
	header.add_child(_label(Time.get_date_string_from_system().replace("-", "."), 15, C_DIM, _latin_regular, 2))


func _build_nav(root: Control) -> void:
	var nav := VBoxContainer.new()
	nav.name = "Nav"
	nav.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav.add_theme_constant_override("separation", 0)
	_rect(nav, Rect2(NAV_RECT.position, Vector2(NAV_RECT.size.x, NAV_ITEM_HEIGHT * ENTRIES.size())))
	root.add_child(nav)
	for i in ENTRIES.size():
		var item := _make_nav_item(ENTRIES[i], i)
		nav.add_child(item)
		_nav_items.append(item)


## 单个菜单项：透明按钮铺满，文字挂在 Body 上（选中时 Body 右移），金线从 x=36 处滑出
func _make_nav_item(entry: Dictionary, index: int) -> Control:
	var item := Control.new()
	item.name = "Item%d" % index
	item.custom_minimum_size = Vector2(NAV_RECT.size.x, NAV_ITEM_HEIGHT)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var button := Button.new()
	button.name = "Button"
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.mouse_entered.connect(_select.bind(index, true))
	button.pressed.connect(_on_nav_pressed.bind(index))
	item.add_child(button)

	var idx := _label(entry["idx"], 14, C_DIM2, _latin_regular, 2)
	idx.name = "Idx"
	idx.position = Vector2(0, 14)
	item.add_child(idx)

	var gold_line := _line(C_GOLD2, Rect2(36, 24, 0, 2))
	gold_line.name = "GoldLine"
	item.add_child(gold_line)

	var body := VBoxContainer.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 0)
	body.position = Vector2(NAV_BODY_X, 12)
	body.size = Vector2(NAV_RECT.size.x - NAV_BODY_X, NAV_ITEM_HEIGHT - 12)
	item.add_child(body)

	var en := _label(entry["en"], 15, C_DIM2, _latin_regular, 5)
	en.name = "En"
	body.add_child(en)

	var cn_row := HBoxContainer.new()
	cn_row.name = "CnRow"
	cn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cn_row.add_theme_constant_override("separation", 14)
	var cn := _label(entry["cn"], 44, C_DIM, _cn_bold, 10)
	cn.name = "Cn"
	cn.add_theme_constant_override("line_spacing", -12)
	cn.custom_minimum_size = Vector2(0, 56)
	cn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cn_row.add_child(cn)
	if entry.get("planned", false):
		var tag := _label("预定", 13, C_DIM2, _cn_regular, 3)
		tag.add_theme_stylebox_override("normal", _stylebox(Color.TRANSPARENT, Color("3a3a3a")))
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cn_row.add_child(tag)
	body.add_child(cn_row)

	var hint := _label(entry["hint"], 15, C_GOLD2, _cn_regular, 2)
	hint.name = "Hint"
	hint.custom_minimum_size = Vector2(0, 24)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.visible = false
	body.add_child(hint)

	item.add_child(_line(Color(C_GOLD, 0.35), Rect2(0, NAV_ITEM_HEIGHT - 1, NAV_RECT.size.x, 1)))
	return item


func _build_panel(root: Control) -> void:
	var panel := Control.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect(panel, PANEL_RECT)
	root.add_child(panel)
	for i in ENTRIES.size():
		var pane := _make_pane(ENTRIES[i], i)
		pane.visible = false
		panel.add_child(pane)
		_panes.append(pane)


## 面板 = 标题行 + 说明 + 按 pane 类型追加的内容 + 底部按钮
func _make_pane(entry: Dictionary, index: int) -> Control:
	var pane := VBoxContainer.new()
	pane.name = "Pane%d" % index
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_theme_constant_override("separation", 0)
	pane.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 16)
	title_row.add_child(_label(entry["title"], 22, C_GOLD2, _cn_regular, 6))
	var rule := _line(C_GOLD3, Rect2(0, 0, 10, 1))
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(rule)
	pane.add_child(title_row)

	var desc := _label(entry["desc"], 17, C_DIM, _cn_regular, 2)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pane.add_child(_margin(desc, 12))

	match str(entry.get("pane", "stub")):
		"play":
			_fill_play_pane(pane)
		"editor":
			_fill_editor_pane(pane)
		"settings":
			_fill_settings_pane(pane)

	var cta := HBoxContainer.new()
	cta.name = "Actions"
	cta.add_theme_constant_override("separation", 22)
	cta.alignment = BoxContainer.ALIGNMENT_BEGIN
	var primary := _primary_button(entry["primary"])
	primary.name = "Primary"
	primary.disabled = entry.get("planned", false)
	primary.pressed.connect(_activate_primary)
	cta.add_child(primary)
	var secondary_text := str(entry.get("secondary", ""))
	if secondary_text != "":
		var secondary := _ghost_button(secondary_text)
		secondary.name = "Secondary"
		secondary.pressed.connect(_activate_secondary)
		cta.add_child(secondary)
	pane.add_child(_margin(cta, 38))
	return pane


func _fill_play_pane(pane: VBoxContainer) -> void:
	var modes := HBoxContainer.new()
	modes.name = "Modes"
	modes.add_theme_constant_override("separation", 14)
	var mode_group := ButtonGroup.new()
	for i in PLAY_MODES.size():
		var card := Button.new()
		card.toggle_mode = true
		card.button_group = mode_group
		card.button_pressed = i == 0
		card.focus_mode = Control.FOCUS_NONE
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(0, 84)
		card.add_theme_stylebox_override("normal", _stylebox(Color(C_INK, 0.55), Color(C_GOLD, 0.35)))
		card.add_theme_stylebox_override("hover", _stylebox(Color(C_GOLD, 0.1), C_GOLD2))
		card.add_theme_stylebox_override("pressed", _stylebox(Color(C_GOLD, 0.1), C_GOLD2))
		var text := VBoxContainer.new()
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_theme_constant_override("separation", 6)
		text.add_child(_label(PLAY_MODES[i][0], 20, C_TEXT, _cn_regular, 4))
		var sub := _label(PLAY_MODES[i][1], 13, C_DIM, _cn_regular, 0)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(sub)
		text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
		text.offset_left = 18
		text.offset_top = 12
		card.add_child(text)
		modes.add_child(card)
	pane.add_child(_margin(modes, 30))

	# 御主名单：从已加载模板读头像，一张不复制
	var roster := HBoxContainer.new()
	roster.name = "Roster"
	roster.add_theme_constant_override("separation", 14)
	for master in GameStart.get_masters_can_use():
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 10)
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		var avatar := _avatar(master._header_img, 86)
		avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cell.add_child(avatar)
		var name_label := _label(master.get_shown_name(), 13, C_TEXT, _cn_regular)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		cell.add_child(name_label)
		roster.add_child(cell)
	pane.add_child(_margin(roster, 30))

	# 从者名单：卡面 5:7，底部压职阶名（口径与对局界面一致：内部值 capitalize）
	var servants := HBoxContainer.new()
	servants.name = "Servants"
	servants.add_theme_constant_override("separation", 14)
	for servant in GameStart.get_servants_can_use():
		var card := _card(servant._servant_card_img, 96)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var caption := _label(str(servant._servant_class).capitalize().to_upper(), 11, C_GOLD2, _latin_regular, 1)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		caption.offset_top = -24
		caption.add_theme_stylebox_override("normal", _stylebox(Color(0, 0, 0, 0.7), Color.TRANSPARENT, 0))
		card.add_child(caption)
		card.tooltip_text = servant.get_shown_name()
		servants.add_child(card)
	pane.add_child(_margin(servants, 30))


func _fill_editor_pane(pane: VBoxContainer) -> void:
	# 三张倾斜卡：本地默认御主的御主卡与令咒卡、默认从者的从者卡；找不到就少一张
	var master = _find_named(GameStart.get_masters_can_use(), GameData.default_master)
	var servant = _find_named(GameStart.get_servants_can_use(), GameData.default_servant)
	var images: Array[String] = []
	if servant != null:
		images.append(servant._servant_card_img)
	if master != null:
		images.append(master._master_card_img)
		images.append(master._command_spell_img)
	var cards := Control.new()
	cards.name = "Cards"
	cards.custom_minimum_size = Vector2(0, 230)
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tilts := [-2.0, 1.0, 3.0]
	var lifts := [0.0, -8.0, 0.0]
	for i in images.size():
		var card := _card(images[i], 150)
		card.position = Vector2(i * 166, 10 + lifts[i % lifts.size()])
		card.pivot_offset = card.size * 0.5
		card.rotation_degrees = tilts[i % tilts.size()]
		cards.add_child(card)
	pane.add_child(_margin(cards, 22))

	var info := GridContainer.new()
	info.columns = 2
	info.add_theme_constant_override("h_separation", 24)
	info.add_theme_constant_override("v_separation", 12)
	var data_dir := LoadHelper.get_data_dir()
	for row in [["数据目录", data_dir], ["御主", "%d 名" % GameStart.get_masters_can_use().size()], ["从者", "%d 骑" % GameStart.get_servants_can_use().size()]]:
		var key := _label(row[0], 17, C_DIM, _cn_regular, 2)
		key.custom_minimum_size = Vector2(176, 0)
		info.add_child(key)
		info.add_child(_label(row[1], 17, C_TEXT, _cn_regular, 1))
	pane.add_child(_margin(info, 22))


## 设置面板只显示运行时真实取值，不提供修改（尚未接入）
func _fill_settings_pane(pane: VBoxContainer) -> void:
	var mode_names := {
		DisplayServer.WINDOW_MODE_WINDOWED: "窗口",
		DisplayServer.WINDOW_MODE_FULLSCREEN: "全屏",
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN: "独占全屏",
		DisplayServer.WINDOW_MODE_MAXIMIZED: "最大化",
		DisplayServer.WINDOW_MODE_MINIMIZED: "最小化",
	}
	var window_size := DisplayServer.window_get_size()
	var rows := [
		["显示模式", str(mode_names.get(DisplayServer.window_get_mode(), "未知"))],
		["分辨率", "%d × %d" % [window_size.x, window_size.y]],
		["语言", TranslationServer.get_locale()],
		["渲染", str(ProjectSettings.get_setting("rendering/renderer/rendering_method", ""))],
	]
	var info := GridContainer.new()
	info.columns = 2
	info.add_theme_constant_override("h_separation", 24)
	info.add_theme_constant_override("v_separation", 12)
	for row in rows:
		var key := _label(row[0], 17, C_DIM, _cn_regular, 2)
		key.custom_minimum_size = Vector2(176, 0)
		info.add_child(key)
		info.add_child(_label(row[1], 17, C_TEXT, _cn_regular, 1))
	pane.add_child(_margin(info, 22))


func _build_bottom(root: Control) -> void:
	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 34)
	bottom.alignment = BoxContainer.ALIGNMENT_BEGIN
	_rect(bottom, Rect2(72, 1010, 1776, 70))
	root.add_child(bottom)
	for pair in BOTTOM_HINTS:
		var group := HBoxContainer.new()
		group.add_theme_constant_override("separation", 8)
		group.alignment = BoxContainer.ALIGNMENT_CENTER
		var key := _label(pair[0], 12, C_GOLD, _latin_regular, 1)
		key.add_theme_stylebox_override("normal", _stylebox(Color.TRANSPARENT, C_GOLD3))
		key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		group.add_child(key)
		group.add_child(_label(pair[1], 15, C_DIM, _cn_regular, 3))
		bottom.add_child(group)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(spacer)
	var note := _label(TITLE_TEXT["legal"].split("\n")[0] + " · 概念稿", 13, C_DIM2, _cn_regular, 1)
	bottom.add_child(note)


## ---------- 通用小件 ----------

func _margin(child: Control, top: int) -> MarginContainer:
	var box := MarginContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("margin_top", top)
	box.add_child(child)
	return box


## 圆形头像：金环 Panel 里放圆形遮罩的贴图
func _avatar(image_path: String, diameter: int) -> Control:
	var ring := Panel.new()
	ring.custom_minimum_size = Vector2(diameter + 6, diameter + 6)
	var style := _stylebox(Color.TRANSPARENT, C_GOLD3, 1, (diameter + 6) / 2)
	style.set_content_margin_all(0)
	ring.add_theme_stylebox_override("panel", style)
	var image := TextureRect.new()
	image.texture = LoadHelper.load_texture(image_path)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.material = _circle_material
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 3)
	ring.add_child(image)
	return ring


## 卡面：5:7 比例，细金边
func _card(image_path: String, width: int) -> Control:
	var frame := Panel.new()
	frame.custom_minimum_size = Vector2(width, width * 7 / 5)
	frame.size = frame.custom_minimum_size
	var style := _stylebox(Color.BLACK, C_GOLD3, 1, 4)
	style.set_content_margin_all(0)
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 8)
	frame.add_theme_stylebox_override("panel", style)
	var image := TextureRect.new()
	image.texture = LoadHelper.load_texture(image_path)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 1)
	frame.add_child(image)
	return frame


## 主按钮：金色平行四边形
func _primary_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 56)
	button.add_theme_font_override("font", _spaced(_cn_bold, 8))
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", C_BUTTON_INK)
	button.add_theme_color_override("font_hover_color", C_BUTTON_INK)
	button.add_theme_color_override("font_pressed_color", C_BUTTON_INK)
	button.add_theme_color_override("font_disabled_color", Color(C_BUTTON_INK, 0.6))
	var skew := Vector2(0.25, 0)
	var normal := _stylebox(C_GOLD, Color.TRANSPARENT, 0, 0, skew)
	normal.content_margin_left = 46
	normal.content_margin_right = 46
	var hover := normal.duplicate()
	hover.bg_color = C_GOLD2
	var disabled := normal.duplicate()
	disabled.bg_color = Color(C_GOLD3, 0.6)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("disabled", disabled)
	return button


## 次按钮：细金边透明底
func _ghost_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 54)
	button.add_theme_font_override("font", _spaced(_cn_regular, 5))
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", C_GOLD2)
	button.add_theme_color_override("font_hover_color", C_GOLD2)
	button.add_theme_color_override("font_pressed_color", C_GOLD2)
	var normal := _stylebox(Color(0, 0, 0, 0.3), C_GOLD3)
	normal.content_margin_left = 30
	normal.content_margin_right = 30
	var hover := normal.duplicate()
	hover.border_color = C_GOLD2
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	return button


func _find_named(pool: Array, wanted: String):
	for candidate in pool:
		if candidate != null and str(candidate._name) == wanted:
			return candidate
	return null


## ---------- 选择与动作 ----------

func _select(index: int, animate := true) -> void:
	_selected = posmod(index, ENTRIES.size())
	for i in _nav_items.size():
		var item := _nav_items[i]
		var selected := i == _selected
		var body := item.get_node("Body") as Control
		var gold_line := item.get_node("GoldLine") as ColorRect
		var idx := item.get_node("Idx") as Label
		var en := body.get_node("En") as Label
		var cn := body.get_node("CnRow/Cn") as Label
		var hint := body.get_node("Hint") as Label
		var planned: bool = ENTRIES[i].get("planned", false)
		var cn_color := C_TITLE if selected else (C_DIM2 if planned else C_DIM)
		hint.visible = selected
		if animate:
			var tween := create_tween().set_parallel(true)
			tween.tween_property(body, "position:x", float(NAV_BODY_X_SELECTED if selected else NAV_BODY_X), 0.25)
			tween.tween_property(gold_line, "size:x", 26.0 if selected else 0.0, 0.3)
			tween.tween_property(cn, "theme_override_colors/font_color", cn_color, 0.25)
		else:
			body.position.x = NAV_BODY_X_SELECTED if selected else NAV_BODY_X
			gold_line.size.x = 26.0 if selected else 0.0
			cn.add_theme_color_override("font_color", cn_color)
		idx.add_theme_color_override("font_color", C_GOLD if selected else C_DIM2)
		en.add_theme_color_override("font_color", C_GOLD if selected else C_DIM2)
	for i in _panes.size():
		_panes[i].visible = i == _selected
	_crumb.text = "主菜单 · " + str(ENTRIES[_selected]["cn"])
	_menu_background.modulate = Color(0.55, 0.55, 0.55) if str(ENTRIES[_selected].get("pane", "")) == "quit" else Color.WHITE
	if animate:
		var pane := _panes[_selected]
		pane.modulate.a = 0.0
		pane.position.y = 14.0
		var tween := create_tween().set_parallel(true)
		tween.tween_property(pane, "modulate:a", 1.0, 0.35)
		tween.tween_property(pane, "position:y", 0.0, 0.35)


func _on_nav_pressed(index: int) -> void:
	_select(index)
	_activate_primary()


func _activate_primary() -> void:
	var entry: Dictionary = ENTRIES[_selected]
	if str(entry.get("pane", "")) == "quit":
		get_tree().quit()
		return
	var scene_path := str(entry.get("scene", ""))
	if scene_path == "" or entry.get("planned", false):
		_show_toast(str(entry["cn"]) + " 尚未接入")
		return
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		_show_toast("无法打开场景：" + scene_path)


func _activate_secondary() -> void:
	var entry: Dictionary = ENTRIES[_selected]
	if str(entry.get("pane", "")) == "quit":
		_select(0)
		return
	_show_toast(str(entry.get("secondary", "")) + " 尚未接入")


func _show_toast(message: String) -> void:
	(_toast.get_node("Label") as Label).text = message
	_toast.show()
	_toast.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_toast, "modulate:a", 1.0, 0.3)
	tween.tween_interval(TOAST_SECONDS)
	tween.tween_property(_toast, "modulate:a", 0.0, 0.3)
	tween.tween_callback(_toast.hide)


## ---------- 动效 ----------

func _start_loops() -> void:
	var style := _stylebox(Color(C_INK, 0.85), C_GOLD3)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_toast.add_theme_stylebox_override("panel", style)
	var toast_label := _toast.get_node("Label") as Label
	toast_label.add_theme_font_override("font", _spaced(_cn_regular, 5))
	toast_label.add_theme_font_size_override("font_size", 18)
	toast_label.add_theme_color_override("font_color", C_GOLD2)

	var glow := create_tween().set_loops()
	glow.tween_property(_glow, "modulate:a", 1.0, 2.25).from(0.7)
	glow.parallel().tween_property(_glow, "scale", Vector2(1.06, 1.06), 2.25).from(Vector2.ONE)
	glow.tween_property(_glow, "modulate:a", 0.7, 2.25)
	glow.parallel().tween_property(_glow, "scale", Vector2.ONE, 2.25)

	var press := create_tween().set_loops()
	press.tween_property(_press_label, "modulate:a", 1.0, 1.1).from(0.45)
	press.tween_property(_press_label, "modulate:a", 0.45, 1.1)


## 逐行淡入上移，间隔 delay_step。
## 子项由 Container 排版时，位置要等一帧布局落地后再读，否则全部从 0 起算叠在一起
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


func _play_title_enter() -> void:
	var block := _title_content.get_node("Block") as Control
	_rise(block.get_children(), 0.15)
	var kv := $TitleScreen/KeyVisual as Control
	kv.modulate.a = 0.0
	var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(kv, "modulate:a", 1.0, 1.6)
	tween.tween_property(kv, "position:x", 910.0, 1.6).from(950.0)


func _play_menu_enter() -> void:
	_rise(_nav_items, 0.08)
