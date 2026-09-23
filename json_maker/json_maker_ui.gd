extends Control

# Fate 卡牌效果积木编辑器（json_maker）。
# 左：积木区（按颜色分类，拖出来用）。中：卡牌信息 + 每条效果一段积木脚本。右：选中积木的说明 / 待修问题 / JSON 原文。
# 编辑的是积木模型，保存时由 JsonCodec 编回加载器认识的 JSON；读写、校验、选图复用 JsonMaker。

const Codec = preload("res://json_maker/json_codec.gd")
const Shape = preload("res://json_maker/json_style.gd")

const VAR_COLOR := Color("#FF8C1A")
const LOOP_ITEM_COLOR := Color("#FFAB19")
const BG := Color("#F9F9F9")
const PANEL := Color("#FFFFFF")
const LINE := Color("#D9D9D9")
const INK := Color("#1F2330")
const HINT := Color("#353A4E")   # 说明文字：中间栏是白底，不用浅灰
const ACCENT := Color("#855CD6")
const DROP_LINE := Color("#1E88E5")

var maker := JsonMaker.new()
var codec
var kind_id := ""      # 顶部下拉选中的种类：只决定文件列表与新建
var card_kind := ""    # 正在编辑的这张卡的种类：打开或新建时定下，之后切换下拉也不变
var path := ""
var style := {}
var data = null
var original = null   # 打开时的原文，用来判断有没有改动
var effects_view:Array = []   # [{effect, where, lists:{funcs:[积木], power_query:[积木]}, options:[{option, nodes, reqs:[[积木]]}]}]
var selected_effect := -1
var dirty := false
var help_title:Label
var help_body:RichTextLabel
var issue_list:VBoxContainer
var json_view:TextEdit
var status:Label
var kind_button:OptionButton
var file_list:ItemList
var palette_box:VBoxContainer
var palette_scroll:ScrollContainer
var category_bar:VBoxContainer
var search:LineEdit
var card_box:VBoxContainer
var script_box:VBoxContainer
var script_scroll:ScrollContainer
var image_dialog:FileDialog
var save_dialog:FileDialog
var zip_dialog:FileDialog
var export_window:AcceptDialog
var export_kind_menu:OptionButton
var export_form:VBoxContainer
var export_preview:Label
var export_kind := ""
var dir_dialog:FileDialog
var dir_target:LineEdit
const PENDING_IMAGES := "res://json_maker/pending_images"   # 选图先放这里，保存时按命名规则搬进卡的文件夹
var image_target := {}
var drag_source := {}
var context_menu:PopupMenu
var context_target := {}
var clipboard = null
var show_advanced := false
var _render_effect = null   # 正在画的那条效果：效果数字存在它的 effect_numbers 里
var focus_path:Array = []     # 正在编辑的子牌在 data 里的路径；空表示本体
var focus_item := ""          # 子牌的类型（types.json 的 item 名）
var sub_list:ItemList
var sub_entries:Array = []
var catalog_sig := ""
var rescan_timer:Timer
var splits:Array = []
var drop_marker:ColorRect      # 拖动时显示「会插在这里」的横线
var hover_target:Control = null
const LAYOUT_PATH := "user://json_maker_layout.cfg"
# 修改记录：每个节点是整张卡的快照，撤回 / 重做 / 回到任一节点都是换回快照
const HISTORY_LIMIT := 200
const HISTORY_MERGE_MSEC := 1000   # 同一处在这段时间内连续改动（打字）合并成一个节点
var history:Array = []
var history_index := -1
var history_restoring := false
var history_view:ItemList
var undo_button:Button
var redo_button:Button
var _key_names := {}


func _ready() -> void:
	maker.load_catalog()
	maker.load_export_settings()
	codec = Codec.new(maker.container_params())
	catalog_sig = maker.catalog_signature()
	_build()
	_load_layout()
	_select_kind(0)
	_show_welcome()
	_use_drag_cursor(true)
	rescan_timer = Timer.new()
	rescan_timer.wait_time = 2.0
	rescan_timer.timeout.connect(_check_catalog)
	add_child(rescan_timer)
	rescan_timer.start()


func _exit_tree() -> void:
	_use_drag_cursor(false)


# 拖动时 Godot 在「放不下」的地方显示禁止光标（项目的 CursorReplace 给它换了禁止图片）。
# 编辑器打开期间把「放不下 / 能放下」都换成手形，关闭时恢复成 CursorReplace 原来的图片。
func _use_drag_cursor(on:bool) -> void:
	var replace = get_node_or_null("/root/CursorReplace")
	var hand = replace.get("pointing") if replace else null
	if on:
		if hand == null:
			var path := "res://assets/images/ui/cursor/cursor_pointing.png"
			hand = load(path) if ResourceLoader.exists(path) else null
		Input.set_custom_mouse_cursor(hand, Input.CURSOR_FORBIDDEN)
		Input.set_custom_mouse_cursor(hand, Input.CURSOR_CAN_DROP)
	else:
		Input.set_custom_mouse_cursor(replace.get("cursor_disabled") if replace else null, Input.CURSOR_FORBIDDEN)
		Input.set_custom_mouse_cursor(null, Input.CURSOR_CAN_DROP)


# 新加、改动、删除了 operation 脚本，或改了登记表 / 声明文件：重新扫描积木。
func _check_catalog() -> void:
	var sig := maker.catalog_signature()
	if sig == catalog_sig:
		return
	rescan_catalog()


func rescan_catalog() -> void:
	var before := maker.operations.size()
	if data != null:
		_commit()
	maker.reload_catalog()
	codec.container_params = maker.container_params()
	catalog_sig = maker.catalog_signature()
	_rebuild_categories()
	_fill_palette()
	if data != null:
		_load_effects()
		_refresh_all()
	_set_status("已重新扫描积木：" + str(maker.operations.size()) + " 块" + ("（多了 " + str(maker.operations.size() - before) + " 块）" if maker.operations.size() > before else ""))


# =============== 界面骨架 ===============

func _build() -> void:
	theme = _light_theme()
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	_build_top(root)
	# 每两块之间都是可以拖的分隔条
	var outer := _split(true, "Outer", 0.20)
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(outer)
	_build_palette(outer)
	var rest := _split(true, "Rest", 0.78)
	outer.add_child(rest)
	_build_center(rest)
	_build_right(rest)
	# 整片背景接住拖放：放在空白处就是取消，不显示禁止光标
	set_drag_forwarding(Callable(), func(_at, d):
		_clear_drop_hint()
		return d is Dictionary and (d.has("new") or d.has("node")), func(_at, _d): pass)
	image_dialog = FileDialog.new()
	image_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	image_dialog.access = FileDialog.ACCESS_FILESYSTEM
	image_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; 图片"])
	image_dialog.file_selected.connect(_image_chosen)
	add_child(image_dialog)
	save_dialog = FileDialog.new()
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_dialog.filters = PackedStringArray(["*.json ; JSON"])
	save_dialog.file_selected.connect(_save_to)
	add_child(save_dialog)
	zip_dialog = FileDialog.new()
	zip_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	zip_dialog.access = FileDialog.ACCESS_FILESYSTEM
	zip_dialog.filters = PackedStringArray(["*.zip ; ZIP"])
	zip_dialog.file_selected.connect(_zip_to)
	add_child(zip_dialog)
	dir_dialog = FileDialog.new()
	dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
	dir_dialog.dir_selected.connect(func(d:String):
		if dir_target != null:
			dir_target.text = LoadHelper.relative_path(d)
			dir_target.text_submitted.emit(dir_target.text))
	add_child(dir_dialog)
	_build_export_window()
	context_menu = PopupMenu.new()
	context_menu.id_pressed.connect(_context_pressed)
	add_child(context_menu)
	drop_marker = ColorRect.new()
	drop_marker.name = "DropMarker"
	drop_marker.color = DROP_LINE
	drop_marker.top_level = true
	drop_marker.z_index = 100
	drop_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_marker.visible = false
	add_child(drop_marker)


func _notification(what:int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_drop_hint()


# Godot 默认是深色主题：输入框、列表、按钮、下拉都是白字或浅灰字，放在白底上看不清。
# 这里给整个编辑器换成浅底深字；积木上的白字由 _block_label 单独指定，不受影响。
func _light_theme() -> Theme:
	var t := Theme.new()
	var field := _theme_box(Color.WHITE, Color("#8A90A6"))
	var field_focus := _theme_box(Color.WHITE, ACCENT)
	for type in ["Label", "CheckBox", "CheckButton", "Button", "OptionButton", "MenuButton", "LinkButton", "LineEdit", "TextEdit", "ItemList", "Tree", "PopupMenu", "TooltipLabel", "RichTextLabel"]:
		for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color", "default_color", "font_uneditable_color"]:
			t.set_color(c, type, INK)
		t.set_color("font_disabled_color", type, HINT)
		t.set_color("font_placeholder_color", type, Color("#5E6480"))
		t.set_color("font_outline_color", type, Color(0, 0, 0, 0))
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, _theme_box(Color("#EEF0F6"), Color("#9BA1B8")))
		t.set_stylebox("hover", type, _theme_box(Color("#E1E5F3"), ACCENT))
		t.set_stylebox("pressed", type, _theme_box(Color("#D3D9EE"), ACCENT))
		t.set_stylebox("hover_pressed", type, _theme_box(Color("#D3D9EE"), ACCENT))
		t.set_stylebox("disabled", type, _theme_box(Color("#F4F5F8"), Color("#C3C7D4")))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, field)
		t.set_stylebox("focus", type, field_focus)
		t.set_stylebox("read_only", type, _theme_box(Color("#F6F7FA"), Color("#9BA1B8")))
		t.set_color("caret_color", type, INK)
		t.set_color("selection_color", type, Color(0.52, 0.36, 0.84, 0.3))
	t.set_color("font_readonly_color", "LineEdit", INK)
	t.set_color("font_readonly_color", "TextEdit", INK)
	for type in ["ItemList", "Tree"]:
		t.set_stylebox("panel", type, _theme_box(Color.WHITE, Color("#8A90A6")))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_stylebox("selected", type, _flat(Color("#DCD2F5"), 3, 2))
		t.set_stylebox("selected_focus", type, _flat(Color("#CFC2F2"), 3, 2))
		t.set_stylebox("hovered", type, _flat(Color("#EFEAFB"), 3, 2))
		t.set_color("font_selected_color", type, INK)
		t.set_color("font_hovered_color", type, INK)
		t.set_color("font_hovered_selected_color", type, INK)
		t.set_color("guide_color", type, Color(0, 0, 0, 0.08))
	for c in ["up_icon_modulate", "up_hover_icon_modulate", "up_pressed_icon_modulate", "down_icon_modulate", "down_hover_icon_modulate", "down_pressed_icon_modulate"]:
		t.set_color(c, "SpinBox", INK)
	t.set_stylebox("panel", "PopupMenu", _theme_box(Color.WHITE, Color("#8A90A6")))
	t.set_stylebox("hover", "PopupMenu", _flat(Color("#E7E0FA"), 3, 2))
	t.set_stylebox("panel", "TooltipPanel", _theme_box(Color("#FFFDF2"), Color("#8A90A6")))
	for type in ["AcceptDialog", "FileDialog", "ConfirmationDialog"]:
		t.set_stylebox("panel", type, _flat(Color("#F9F9FB"), 0, 8))
	return t


func _theme_box(bg:Color, border:Color) -> StyleBoxFlat:
	var sb := _flat(bg, 4, 4, border)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	return sb


func _build_top(parent:Node) -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _flat(Color("#855CD6"), 0, 8))
	parent.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	var title := _label("卡牌效果积木", 20, Color.WHITE)
	row.add_child(title)
	row.add_child(_spacer(16))
	row.add_child(_label("卡牌种类", 14, Color.WHITE))
	kind_button = OptionButton.new()
	kind_button.name = "KindButton"
	for item in maker.file_kinds():
		kind_button.add_item(item.shown)
		kind_button.set_item_metadata(kind_button.item_count - 1, item.id)
	kind_button.item_selected.connect(_select_kind)
	row.add_child(kind_button)
	_top_button(row, "新建一张", _new_card, "按当前种类新建一张空白卡。")
	_top_button(row, "保存", _save, "检查通过才会写文件。Ctrl+S")
	_top_button(row, "另存为", _save_as, "")
	_top_button(row, "导出设置", open_export_settings, "每种卡保存到哪个目录、文件夹和图片怎么命名、zip 里的目录层级。只存在你自己的设置里，不改源码。")
	_top_button(row, "打包 zip", _zip_card, "把这张卡的 json 和它用到的图片打成一个 zip，里面按 data/… 的目录放好，解压到项目根目录就能用。")
	undo_button = _top_button(row, "撤回", undo, "撤回上一步。Ctrl+Z")
	redo_button = _top_button(row, "重做", redo, "重做撤回的一步。Ctrl+Y")
	undo_button.disabled = true
	redo_button.disabled = true
	_top_button(row, "重新扫描积木", rescan_catalog, "新加了 operation 会自动出现；想马上刷新就点这里。")
	var adv := CheckButton.new()
	adv.text = "显示高级积木"
	adv.tooltip_text = "打开后积木区会出现直接读写对象内部字段的积木。一般用不到。"
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		adv.add_theme_color_override(c, Color.WHITE)
	adv.toggled.connect(func(on): show_advanced = on; _fill_palette())
	row.add_child(adv)
	status = _label("", 14, Color.WHITE)
	status.add_theme_font_size_override("font_size", 15)
	status.custom_minimum_size = Vector2(190, 28)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.clip_text = false
	row.add_child(status)


func _build_palette(parent:Node) -> void:
	var side := _split(true, "Palette", 0.19)
	parent.add_child(side)
	# 最左一列：分类色点，点一下跳到那一类
	var cat_panel := PanelContainer.new()
	cat_panel.add_theme_stylebox_override("panel", _flat(PANEL, 0, 4, LINE))
	side.add_child(cat_panel)
	var cat_scroll := ScrollContainer.new()
	cat_scroll.custom_minimum_size = Vector2(40, 0)
	cat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	cat_panel.add_child(cat_scroll)
	category_bar = VBoxContainer.new()
	category_bar.add_theme_constant_override("separation", 2)
	cat_scroll.add_child(category_bar)
	# 积木列表
	var pal := PanelContainer.new()
	pal.add_theme_stylebox_override("panel", _flat(Color("#F5F5FA"), 0, 6, LINE))
	pal.custom_minimum_size = Vector2(160, 0)
	side.add_child(pal)
	var col := VBoxContainer.new()
	pal.add_child(col)
	search = LineEdit.new()
	search.placeholder_text = "搜积木：魔力、抽牌、战果、如果……"
	search.clear_button_enabled = true
	search.text_changed.connect(func(_t): _fill_palette())
	col.add_child(search)
	palette_scroll = ScrollContainer.new()
	palette_scroll.name = "PaletteScroll"
	palette_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	col.add_child(palette_scroll)
	palette_box = VBoxContainer.new()
	palette_box.add_theme_constant_override("separation", 6)
	palette_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette_scroll.add_child(palette_box)
	# 把积木拖回积木区 = 删除
	pal.set_drag_forwarding(Callable(), _palette_can_drop, _palette_drop)
	_rebuild_categories()
	_fill_palette()


func _rebuild_categories() -> void:
	_clear(category_bar)
	for cat in maker.categories():
		var b := Button.new()
		b.flat = true
		b.custom_minimum_size = Vector2(36, 46)
		b.text = "●\n" + str(cat.shown)
		b.add_theme_color_override("font_color", Color(str(cat.color)))
		b.add_theme_font_size_override("font_size", 11)
		b.tooltip_text = str(cat.shown)
		b.pressed.connect(_jump_category.bind(str(cat.id)))
		category_bar.add_child(b)


func _build_center(parent:Node) -> void:
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 0)
	parent.add_child(center)
	var split := _split(true, "Center", 0.32)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(split)
	# 左半：文件列表 / 子牌列表 / 卡牌信息，上下都能拖
	var left := _split(false, "Left", 0.42)
	left.custom_minimum_size = Vector2(160, 0)
	split.add_child(left)
	var lists := _split(false, "Lists", 0.5)
	left.add_child(lists)
	var files_box := VBoxContainer.new()
	lists.add_child(files_box)
	files_box.add_child(_section_title("① 选一张卡", "双击打开。也可以点上面的「新建一张」。"))
	file_list = ItemList.new()
	file_list.name = "FileList"
	file_list.custom_minimum_size = Vector2(0, 40)
	file_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	file_list.item_activated.connect(_open_index)
	files_box.add_child(file_list)
	var subs_box := VBoxContainer.new()
	lists.add_child(subs_box)
	subs_box.add_child(_section_title("子牌", "御主、从者带的技能牌、攻击牌、状态、附带物。点一张就编辑它。"))
	sub_list = ItemList.new()
	sub_list.name = "SubList"
	sub_list.custom_minimum_size = Vector2(0, 40)
	sub_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sub_list.item_selected.connect(func(i): call_deferred("_focus_entry", i))
	subs_box.add_child(sub_list)
	var card_col := VBoxContainer.new()
	left.add_child(card_col)
	card_col.add_child(_section_title("② 卡面信息", "卡面上印的东西。带 * 的必须填。"))
	var card_scroll := ScrollContainer.new()
	card_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	card_col.add_child(card_scroll)
	card_box = VBoxContainer.new()
	card_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_scroll.add_child(card_box)
	# 右半：效果脚本区
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	right.add_child(_section_title("③ 效果积木", "每条效果以一块「当……时」开头，下面接要做的事。从左边把积木拖进来：拖到一块积木的上半截就插在它前面，下半截就插在它后面，拖到空位里就填进去。点积木右边的 ✕ 删除。右键积木可以复制、存为变量。"))
	script_scroll = ScrollContainer.new()
	script_scroll.name = "ScriptScroll"
	script_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sbg := StyleBoxFlat.new()
	sbg.bg_color = Color("#FFFFFF")
	sbg.border_color = LINE
	sbg.set_border_width_all(1)
	script_scroll.add_theme_stylebox_override("panel", sbg)
	right.add_child(script_scroll)
	script_box = VBoxContainer.new()
	script_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	script_box.add_theme_constant_override("separation", 18)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	pad.add_child(script_box)
	script_scroll.add_child(pad)


func _build_right(parent:Node) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(180, 0)
	panel.add_theme_stylebox_override("panel", _flat(PANEL, 0, 8, LINE))
	parent.add_child(panel)
	# 说明 / 待修问题 / JSON 三格，上下都能拖
	var vsplit := _split(false, "Right", 0.38)
	panel.add_child(vsplit)
	var col := VBoxContainer.new()
	vsplit.add_child(col)
	var lower := _split(false, "RightLower", 0.45)
	vsplit.add_child(lower)
	help_title = _label("说明", 16, INK)
	col.add_child(help_title)
	help_body = RichTextLabel.new()
	help_body.name = "HelpBody"
	help_body.bbcode_enabled = true
	help_body.fit_content = false
	help_body.scroll_active = true
	help_body.custom_minimum_size = Vector2(0, 40)
	help_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	help_body.add_theme_color_override("default_color", INK)
	col.add_child(help_body)
	var issue_col := VBoxContainer.new()
	lower.add_child(issue_col)
	issue_col.add_child(_label("还要修的地方", 16, INK))
	var issue_scroll := ScrollContainer.new()
	issue_scroll.custom_minimum_size = Vector2(0, 30)
	issue_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	issue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	issue_col.add_child(issue_scroll)
	issue_list = VBoxContainer.new()
	issue_list.name = "IssueList"
	issue_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	issue_scroll.add_child(issue_list)
	var bottom := _split(false, "RightBottom", 0.4)
	lower.add_child(bottom)
	var history_col := VBoxContainer.new()
	bottom.add_child(history_col)
	history_col.add_child(_label("修改记录（点一条就回到那一步）", 14, INK))
	history_view = ItemList.new()
	history_view.name = "HistoryList"
	history_view.custom_minimum_size = Vector2(0, 30)
	history_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_view.item_selected.connect(_restore_history)
	history_col.add_child(history_view)
	var json_col := VBoxContainer.new()
	bottom.add_child(json_col)
	json_col.add_child(_label("生成的 JSON（把分隔条拖下去就收起）", 14, INK))
	json_view = TextEdit.new()
	json_view.name = "JsonView"
	json_view.editable = false
	json_view.custom_minimum_size = Vector2(0, 20)
	json_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	json_view.add_theme_font_size_override("font_size", 12)
	json_col.add_child(json_view)


# =============== 积木区 ===============

func _fill_palette() -> void:
	_clear(palette_box)
	var needle := search.text.strip_edges().to_lower() if search else ""
	for cat in maker.categories():
		var cat_id := str(cat.id)
		var items:Array = _palette_items(cat_id, needle)
		if items.is_empty():
			continue
		var head := _label(str(cat.shown), 15, Color(str(cat.color)).darkened(0.2))
		head.name = "Cat_" + cat_id.replace("/", "_")
		palette_box.add_child(head)
		for item in items:
			var holder := HBoxContainer.new()
			palette_box.add_child(holder)
			var view := _palette_block(item)
			holder.add_child(view)


func _palette_items(cat_id:String, needle:String) -> Array:
	var out:Array = []
	if cat_id == "控制流":
		out.append({"kind": "if"})
	if cat_id == "变量":
		out.append({"kind": "var"})
		out.append({"kind": "loop_item"})
		out.append({"kind": "option_qty"})
	for op in maker.operations:
		if str(op.category) != cat_id:
			continue
		var spec := maker.block_spec(op.func_name)
		if bool(spec.get("advanced", false)) and not show_advanced:
			continue
		out.append({"kind": "op", "func": op.func_name})
	if needle == "":
		return out
	var kept:Array = []
	for item in out:
		var text := _palette_text(item).to_lower()
		if needle in text or (item.has("func") and needle in str(item.func)):
			kept.append(item)
	return kept


func _palette_text(item:Dictionary) -> String:
	match str(item.kind):
		"if":
			return "如果 那么 条件 判断"
		"var":
			return "变量 前面算出的结果 存下"
		"loop_item":
			return "当前这一项 循环 每一个"
		"option_qty":
			return "选项数量 玩家选的数量"
	return maker.say_of(item.func).replace("{", "").replace("}", "") + " " + maker.help_of(item.func)


func _palette_block(item:Dictionary) -> Control:
	var node := _node_from_palette(item)
	var view := _render_node(node, {"palette": true})
	_make_passive(view)
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	view.tooltip_text = _palette_help(item)
	view.set_drag_forwarding(func(_p): return _begin_drag({"new": item}, view), Callable(), Callable())
	view.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_help_for(node))
	return view


func _palette_help(item:Dictionary) -> String:
	if item.kind == "op":
		return maker.help_of(item.func)
	return ""


func _jump_category(cat_id:String) -> void:
	var node := palette_box.get_node_or_null("Cat_" + cat_id.replace("/", "_"))
	if node:
		palette_scroll.scroll_vertical = int(node.position.y)


func _node_from_palette(item:Dictionary) -> Dictionary:
	match str(item.kind):
		"if":
			return {"t": "if", "cond": _empty_slot(), "body": []}
		"var":
			return {"t": "slot_only", "slot": {"s": "var", "n": 0}}
		"loop_item":
			return {"t": "slot_only", "slot": {"s": "lit", "v": null, "loop": true}}
		"option_qty":
			return {"t": "slot_only", "slot": {"s": "qty", "i": 0}}
	return _new_op(str(item.func))


func _new_op(func_name:String) -> Dictionary:
	var op := maker.operation_of(func_name)
	var params:Array = []
	var containers:Array = codec.container_params.get(func_name, [])
	for i in op.get("params", []).size():
		var p:Dictionary = op.params[i]
		if containers.has(i):
			params.append({"s": "script", "body": []})
		elif bool(p.required):
			match str(p.type):
				"int", "float":
					params.append({"s": "lit", "v": 0})
				"bool":
					params.append({"s": "lit", "v": false})
				"String":
					params.append({"s": "lit", "v": ""})
				_:
					params.append(_empty_slot())
		else:
			params.append(_omit_for(op, i))
	return {"t": "op", "func": func_name, "params": params, "var": -1, "cond": null, "keys": [], "extra": {}}


func _empty_slot() -> Dictionary:
	return {"s": "lit", "v": null}


# 没填的可选空位：记下默认值。默认值是数字对象的，保存时如果后面有空位填了，就补一个同值的效果数字。
func _omit_for(op:Dictionary, index:int) -> Dictionary:
	var params:Array = op.get("params", [])
	if index >= params.size():
		return {"s": "omit", "d": null}
	var d = params[index].default
	if d is Dictionary and d.has("_base_number"):
		return {"s": "omit", "d": null, "number_default": d.number}
	return {"s": "omit", "d": d}


# 复制出来的积木不带变量编号，免得两块写同一个变量。
func _fresh_copy(node:Dictionary) -> Dictionary:
	var copy:Dictionary = node.duplicate(true)
	if copy.has("var"):
		copy.var = -1
	return copy


func _make_passive(node:Node) -> void:
	for child in node.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_make_passive(child)


# =============== 打开 / 新建 ===============

func _select_kind(index:int) -> void:
	if kind_button.selected != index:
		kind_button.select(index)
	kind_id = str(kind_button.get_item_metadata(index))
	file_list.clear()
	for item in maker.list_files(kind_id):
		file_list.add_item(item.shown)
		file_list.set_item_metadata(file_list.item_count - 1, item.path)
		file_list.set_item_tooltip(file_list.item_count - 1, item.path)
	_set_status("共 " + str(file_list.item_count) + " 张" + str(maker.kind_spec(kind_id).get("shown", "")))


func _open_index(index:int) -> void:
	open_path(str(file_list.get_item_metadata(index)))


func open_path(target:String) -> void:
	var loaded = maker.read_json(target)
	if loaded == null:
		_set_status("这份文件读不了：" + target)
		return
	card_kind = _kind_of_path(target)
	path = target
	style = maker.text_style(target)
	data = loaded
	original = loaded.duplicate(true)
	focus_path = []
	focus_item = ""
	history.clear()
	_load_effects()
	_refresh_all()
	dirty = false
	_reset_history("打开 " + target.get_file(), true)
	_set_status("已打开 " + target.get_file())


# 按文件所在目录认种类（取最长的匹配目录）；认不出就用下拉当前的种类。
func _kind_of_path(target:String) -> String:
	var local := LoadHelper.relative_path(target)
	var best := kind_id
	var best_len := -1
	for item in maker.file_kinds():
		var root := str(item.spec.get("root", ""))
		if str(item.spec.get("file", "")) == "named":
			if local == root.path_join(str(item.spec.get("file_name", ""))):
				return str(item.id)
			continue
		if root != "" and local.begins_with(root + "/") and root.length() > best_len:
			best = str(item.id)
			best_len = root.length()
	return best


func _new_card() -> void:
	card_kind = kind_id
	path = ""
	style = {}
	original = null
	data = maker.blank(kind_id)
	focus_path = []
	focus_item = ""
	history.clear()
	_load_effects()
	_refresh_all()
	dirty = true
	_reset_history("新建一张", false)
	_set_status("新建了一张，还没保存")


# 只把正在编辑的那张牌（本体或某张子牌）自己的效果解码成积木。
func _load_effects() -> void:
	effects_view.clear()
	var obj = _focus_obj()
	if not obj is Dictionary:
		return
	for effect in obj.get("effects", []):
		if effect is Dictionary:
			_add_effect_view(effect, "")
	selected_effect = 0 if not effects_view.is_empty() else -1


# 整张卡里所有效果（含各子牌），检查问题时用。
func _all_effects(node, where:String, out:Array) -> void:
	if node is Dictionary:
		for key in node:
			var value = node[key]
			if key == "effects" and value is Array:
				for effect in value:
					if effect is Dictionary:
						out.append({"effect": effect, "owner": where})
				continue
			if value is Array or value is Dictionary:
				_all_effects(value, where if value is Array else _owner_name(value, where), out)
	elif node is Array:
		for item in node:
			if item is Dictionary:
				_all_effects(item, _owner_name(item, where), out)


# =============== 子牌 ===============

func _focus_obj():
	var node = data
	for part in focus_path:
		if node is Dictionary and node.has(part):
			node = node[part]
		elif node is Array and part is int and part < node.size():
			node = node[part]
		else:
			return null
	return node


func _focus_spec() -> Dictionary:
	return maker.kind_spec(card_kind) if focus_path.is_empty() else maker.item_spec(focus_item)


# 列出本体带的子牌：只列带效果列表的类型（技能牌、攻击牌、状态、附带物、升华技、内嵌事件……），由声明决定。
func _sub_entries() -> Array:
	var out:Array = []
	if not data is Dictionary:
		return out
	out.append({"path": [], "item": "", "shown": "本体：" + _owner_name(data, str(maker.kind_spec(card_kind).get("shown", "卡"))), "depth": 0})
	var spec := maker.kind_spec(card_kind)
	for group in spec.get("groups", []):
		if data.get(group.key) is Dictionary:
			for item in group.get("lists", []):
				_sub_entries_of(data[group.key], item, [str(group.key)], out)
	for item in spec.get("lists", []):
		if str(item.key) != "effects":
			_sub_entries_of(data, item, [], out)
	return out


func _sub_entries_of(owner:Dictionary, item:Dictionary, base:Array, out:Array) -> void:
	if not _has_own_page(str(item.get("item", ""))) or not owner.get(item.key) is Array:
		return
	var list:Array = owner[item.key]
	for i in list.size():
		if list[i] is Dictionary:
			var path := base.duplicate()
			path.append(str(item.key))
			path.append(i)
			var shown := str(maker.item_spec(str(item.item)).get("shown", item.shown))
			out.append({"path": path, "item": str(item.item), "shown": "　" + shown + " · " + _owner_name(list[i], "第 " + str(i + 1) + " 个"), "depth": 1})


func _has_own_page(item_id:String) -> bool:
	for inner in maker.item_spec(item_id).get("lists", []):
		if str(inner.key) == "effects":
			return true
	return false


func _rebuild_sub_list() -> void:
	sub_list.clear()
	sub_entries = _sub_entries()
	for entry in sub_entries:
		sub_list.add_item(entry.shown)
		if entry.path == focus_path:
			sub_list.select(sub_list.item_count - 1)


func _focus_entry(index:int) -> void:
	if index < 0 or index >= sub_entries.size():
		return
	focus_to(sub_entries[index].path, sub_entries[index].item)


func focus_to(target_path:Array, item_id:String) -> void:
	if data != null:
		_commit()
	focus_path = target_path.duplicate()
	focus_item = item_id
	_load_effects()
	_refresh_all()
	_set_status("正在编辑：" + (_owner_name(_focus_obj(), "子牌") if not focus_path.is_empty() else "本体"))


func _owner_name(item, fallback:String) -> String:
	if item is Dictionary:
		for key in ["shown_skill_name", "shown_buff_name", "shown_thing_name", "shown_attack_name", "shown_name", "skill_name", "buff_name", "thing_name", "attack_name", "card_name"]:
			if str(item.get(key, "")) != "":
				return str(item[key])
	return fallback


func _add_effect_view(effect:Dictionary, owner:String) -> void:
	var view := {"effect": effect, "owner": owner, "lists": {}, "options": []}
	for key in ["funcs", "power_query"]:
		if effect.get(key) is Array:
			view.lists[key] = codec.decode_list(effect[key])
	for option in effect.get("options", []):
		if not option is Dictionary:
			continue
		var ov := {"option": option, "nodes": codec.decode_list(option.get("funcs", [])) if option.get("funcs") is Array else [], "reqs": []}
		for req in option.get("activation_requirements", []):
			if req is Dictionary and req.get("funcs") is Array:
				ov.reqs.append(codec.decode_list(req.funcs))
			else:
				ov.reqs.append([])
		view.options.append(ov)
	effects_view.append(view)


# 积木 → JSON：把所有效果的积木写回 data。
func _commit() -> void:
	for view in effects_view:
		var effect:Dictionary = view.effect
		_fill_middle_numbers(view, effect)
		for key in view.lists:
			effect[key] = codec.encode_effect_list(view.lists[key])
		var options:Array = effect.get("options", [])
		for oi in view.options.size():
			var ov:Dictionary = view.options[oi]
			if ov.option.has("funcs") or not ov.nodes.is_empty():
				ov.option["funcs"] = codec.encode_effect_list(ov.nodes)
			var reqs:Array = ov.option.get("activation_requirements", [])
			for ri in mini(reqs.size(), ov.reqs.size()):
				if reqs[ri] is Dictionary:
					reqs[ri]["funcs"] = codec.encode_effect_list(ov.reqs[ri])


# =============== 刷新 ===============

# 可选的数字空位没填、但它后面的空位填了：JSON 只能按位置写参数，这一格必须写点什么。
# 写 null 会让「加上」这类参数变成空（操作按数字取值会出错），所以补一个与默认值相同的效果数字。
func _fill_middle_numbers(view:Dictionary, effect:Dictionary) -> void:
	var lists:Array = view.lists.values()
	for ov in view.options:
		lists.append(ov.nodes)
	for list in lists:
		_walk_fill(list, effect)


func _walk_fill(value, effect:Dictionary) -> void:
	if value is Array:
		for item in value:
			_walk_fill(item, effect)
	elif value is Dictionary:
		if value.has("params") and value.params is Array:
			var params:Array = value.params
			var last := params.size() - 1
			while last >= 0 and params[last] is Dictionary and str(params[last].get("s", "")) == "omit":
				last -= 1
			for i in last:
				if params[i] is Dictionary and str(params[i].get("s", "")) == "omit" and params[i].has("number_default"):
					params[i] = _new_number_slot(params[i].number_default, effect)
		for key in value:
			if key != "extra" and key != "keys":
				_walk_fill(value[key], effect)


func _refresh_all() -> void:
	_rebuild_sub_list()
	_paint_card()
	_paint_scripts()
	_update_json()


func _changed() -> void:
	dirty = true
	_set_status("")
	_update_json()


func _refresh_scripts() -> void:
	dirty = true
	_set_status("")
	call_deferred("_paint_scripts_and_json")


func _paint_scripts_and_json() -> void:
	_paint_scripts()
	_update_json()


func _update_json() -> void:
	if data == null:
		json_view.text = ""
		_paint_issues([])
		return
	_commit()
	_record_history()
	if json_view.is_visible_in_tree() and json_view.size.y > 24:
		json_view.text = maker.export_text(data, style)
	_paint_issues(_collect_issues())


# =============== 卡面信息 ===============

func _paint_card() -> void:
	_clear(card_box)
	if not data is Dictionary:
		card_box.add_child(_hint("先在上面选一张卡，或者点「新建一张」。"))
		return
	var obj = _focus_obj()
	if not obj is Dictionary:
		focus_path = []
		obj = data
	var spec := _focus_spec()
	if not focus_path.is_empty():
		var back := Button.new()
		back.text = "← 回到本体"
		back.pressed.connect(func(): call_deferred("focus_to", [], ""))
		card_box.add_child(back)
		card_box.add_child(_label(str(spec.get("shown", "子牌")) + "：" + _owner_name(obj, ""), 15, Color("#4C3D8F")))
	_paint_fields(card_box, obj, spec)
	for group in spec.get("groups", []):
		if not obj.get(group.key) is Dictionary:
			obj[group.key] = {}
		for item in group.get("lists", []):
			_paint_sub_list(card_box, obj[group.key], item, focus_path + [str(group.key)])
	for item in spec.get("lists", []):
		if str(item.key) == "effects":
			continue
		_paint_sub_list(card_box, obj, item, focus_path.duplicate())


func _paint_fields(parent:Node, obj:Dictionary, spec:Dictionary) -> void:
	var inner:Array = []
	for field in spec.get("fields", []):
		if bool(field.get("advanced", false)):
			inner.append(field)
			continue
		_field_row(parent, obj, field)
	if inner.is_empty():
		return
	var fold := _fold_box(parent, "程序用的名字", false)
	for field in inner:
		_field_row(fold, obj, field)


func _field_row(parent:Node, obj:Dictionary, field:Dictionary) -> void:
	var key := str(field.key)
	var known := ["text", "int", "float", "bool", "number", "choice", "image", "attributes", "lines", "time_points", "cost"]
	if not known.has(str(field.get("control", "text"))) and not obj.has(key):
		return
	var row := HBoxContainer.new()
	parent.add_child(row)
	var name_text := str(field.get("shown", key)) + (" *" if bool(field.get("required", false)) else "")
	var name := _label(name_text, 14, INK)
	name.custom_minimum_size = Vector2(118, 0)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(name)
	var help := str(field.get("help", ""))
	if help != "":
		name.tooltip_text = help
		name.mouse_filter = Control.MOUSE_FILTER_STOP
		name.text += " ⓘ"
	var control := str(field.get("control", "text"))
	var present:bool = obj.has(key)
	match control:
		"text":
			var edit := LineEdit.new()
			edit.text = str(obj.get(key, ""))
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			edit.text_changed.connect(func(v): obj[key] = v; _changed())
			row.add_child(edit)
		"int", "float":
			var spin := _spin(float(obj.get(key, field.get("default", 0))) if present or field.has("default") else 0.0, control == "float")
			spin.value_changed.connect(func(v): obj[key] = int(v) if control == "int" else v; _changed())
			row.add_child(spin)
		"bool":
			var box := CheckBox.new()
			var on = obj.get(key, field.get("default", false))
			box.button_pressed = on if on is bool else false
			if not present and str(field.get("default", "")) == "!is_pure_passive":
				box.button_pressed = not bool(obj.get("is_pure_passive", false))
				box.text = "（跟随自动发动）"
			box.toggled.connect(func(v): obj[key] = v; box.text = ""; _changed())
			row.add_child(box)
		"number":
			if not obj.get(key) is Dictionary:
				obj[key] = maker._default_of(field)
			var spin := _spin(float(obj[key].get("number", 0)), false)
			spin.value_changed.connect(func(v): obj[key]["number"] = v; _changed())
			row.add_child(spin)
		"choice":
			var menu := OptionButton.new()
			var choices:Array = field.get("choices", [])
			var shown_map:Dictionary = maker.types.get("kind_choices", {})
			for choice in choices:
				menu.add_item(_choice_shown(str(choice)))
			menu.selected = maxi(0, choices.find(obj.get(key, "")))
			menu.item_selected.connect(func(i): obj[key] = choices[i]; _changed())
			row.add_child(menu)
		"image":
			var shown := str(obj.get(key, ""))
			var lab := _label(shown if shown != "" else "还没选图", 13, INK if shown != "" else HINT)
			lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lab.clip_text = true
			row.add_child(lab)
			var pick := Button.new()
			pick.text = "选图"
			pick.pressed.connect(_pick_image.bind(obj, key, str(field.get("zoom", ""))))
			row.add_child(pick)
		"attributes":
			var flow := HFlowContainer.new()
			flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(flow)
			for attr in maker.attributes:
				var box := CheckBox.new()
				box.text = attr.shown
				box.button_pressed = obj.get(key, []) is Array and obj[key].has(attr.id)
				box.toggled.connect(func(on, id = attr.id):
					if not obj.get(key) is Array:
						obj[key] = []
					if on and not obj[key].has(id):
						obj[key].append(id)
					elif not on:
						obj[key].erase(id)
					_changed())
				flow.add_child(box)
		"lines":
			var edit := TextEdit.new()
			edit.custom_minimum_size = Vector2(0, 56)
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			edit.text = "\n".join(PackedStringArray(obj.get(key, []) if obj.get(key) is Array else []))
			edit.text_changed.connect(func(): obj[key] = Array(edit.text.split("\n", false)); _changed())
			row.add_child(edit)
		"time_points":
			_time_points_editor(row, obj, key)
		"cost":
			_cost_editor(row, obj, key)
		_:
			var lab := _label("这一项请在右边 JSON 里看", 12, HINT)
			row.add_child(lab)


func _choice_shown(value:String) -> String:
	for item in maker.kind_choices("card_category"):
		if str(item.v) == value:
			return str(item.shown) + "  " + value
	return value


func _time_points_editor(parent:Node, obj:Dictionary, key:String) -> void:
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(flow)
	var list:Array = obj.get(key, []) if obj.get(key) is Array else []
	for i in list.size():
		var chip := Button.new()
		chip.text = maker.time_point_shown(str(list[i])) + "  ✕"
		chip.tooltip_text = "点一下去掉"
		chip.pressed.connect(func():
			list.remove_at(i)
			obj[key] = list
			_changed()
			call_deferred("_paint_card"))
		flow.add_child(chip)
	var menu := _time_point_menu("＋ 加一个时机")
	menu.item_selected.connect(func(idx):
		if idx == 0:
			return
		list.append(menu.get_item_metadata(idx))
		obj[key] = list
		_changed()
		call_deferred("_paint_card"))
	flow.add_child(menu)


func _time_point_menu(first:String) -> OptionButton:
	var menu := OptionButton.new()
	menu.add_item(first)
	for point in maker.time_points:
		menu.add_item(point.shown)
		menu.set_item_metadata(menu.item_count - 1, point.id)
	return menu


func _cost_editor(parent:Node, obj:Dictionary, key:String) -> void:
	var cost = obj.get(key, {})
	var menu := OptionButton.new()
	menu.add_item("不花费")
	menu.add_item("魔力")
	for t in maker.types.get("cost_types", []):
		menu.add_item(str(t.shown))
	if not cost is Dictionary or cost.is_empty():
		menu.selected = 0
	elif cost.has("type"):
		var idx := 2
		for t in maker.types.get("cost_types", []):
			if str(t.type) == str(cost.type):
				menu.selected = idx
			idx += 1
	else:
		menu.selected = 1
	menu.item_selected.connect(func(i):
		if i == 0:
			obj.erase(key)
		elif i == 1:
			obj[key] = {"number": 1, "can_change": true, "is_pure_number": true}
		else:
			obj[key] = {"type": str(maker.types.cost_types[i - 2].type), "amount": 1}
		_changed()
		call_deferred("_paint_scripts"))
	parent.add_child(menu)
	if cost is Dictionary and cost.has("number"):
		var spin := _spin(float(cost.number), false)
		spin.value_changed.connect(func(v): cost.number = v; _changed())
		parent.add_child(spin)
	elif cost is Dictionary and cost.has("amount"):
		var spin := _spin(float(cost.amount), false)
		spin.min_value = 0
		spin.value_changed.connect(func(v): cost.amount = int(v); _changed())
		parent.add_child(spin)


# 附带内容（技能牌、状态、附带物……）：列出来，展开后就地编辑卡面字段；它们的效果积木在右边一起显示。
func _paint_sub_list(parent:Node, owner:Dictionary, item:Dictionary, base:Array = []) -> void:
	var key := str(item.key)
	var item_id := str(item.get("item", ""))
	# 原文没有这一项就先不写，等真的加了东西才写进去，打开再保存不会平白多出空列表
	var list:Array = owner[key] if owner.get(key) is Array else []
	if item_id in ["text", "deck_ref"]:
		var fold := _fold_box(parent, str(item.shown) + "（" + str(list.size()) + "）", false)
		var edit := TextEdit.new()
		edit.custom_minimum_size = Vector2(0, 72)
		edit.text = "\n".join(PackedStringArray(list.map(func(x): return str(x))))
		edit.text_changed.connect(func():
			var lines := Array(edit.text.split("\n", false))
			if lines.is_empty() and not owner.has(key):
				return
			owner[key] = lines
			_changed())
		fold.add_child(edit)
		fold.add_child(_hint("一行一条。" + ("写成「属性:威力」，如 strength:3。" if item_id == "deck_ref" else "")))
		return
	var own_page := _has_own_page(item_id)
	var fold := _fold_box(parent, str(item.shown) + "（" + str(list.size()) + "）", own_page and not list.is_empty())
	var spec := maker.item_spec(item_id)
	for i in list.size():
		if not list[i] is Dictionary:
			continue
		if own_page:
			# 带效果的子牌单独开一页编辑：卡面字段和它的效果积木一起换过去
			var row := HBoxContainer.new()
			fold.add_child(row)
			var name := _label(_owner_name(list[i], "第 " + str(i + 1) + " 个"), 14, INK)
			name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name.clip_text = true
			row.add_child(name)
			var edit := Button.new()
			edit.text = "编辑"
			var target := base.duplicate()
			target.append(str(item.key))
			target.append(i)
			edit.pressed.connect(func(): call_deferred("focus_to", target, item_id))
			row.add_child(edit)
			var remove := Button.new()
			remove.text = "删掉"
			remove.pressed.connect(func():
				_commit()
				list.remove_at(i)
				call_deferred("focus_to", focus_path, focus_item))
			row.add_child(remove)
			continue
		var sub := _fold_box(fold, _owner_name(list[i], "第 " + str(i + 1) + " 个"), false)
		_paint_fields(sub, list[i], spec)
		if spec.has("lists"):
			for inner in spec.lists:
				if str(inner.key) == "effects" or str(inner.item) == "location":
					continue
				_paint_sub_list(sub, list[i], inner)
		var del := Button.new()
		del.text = "删掉这一个"
		del.pressed.connect(func():
			list.remove_at(i)
			_load_effects()
			_changed()
			call_deferred("_refresh_all"))
		sub.add_child(del)
	var add := Button.new()
	add.text = "＋ 加一个" + str(spec.get("shown", ""))
	add.pressed.connect(func():
		_commit()
		list.append(maker.blank_required(item_id))
		owner[key] = list
		_changed()
		if own_page:
			var target := base.duplicate()
			target.append(key)
			target.append(list.size() - 1)
			call_deferred("focus_to", target, item_id)
		else:
			call_deferred("_refresh_all"))
	fold.add_child(add)


# =============== 效果脚本区 ===============

func _paint_scripts() -> void:
	_clear(script_box)
	if not data is Dictionary:
		script_box.add_child(_welcome_card())
		return
	var spec := _focus_spec()
	var has_effects := false
	for item in spec.get("lists", []):
		if str(item.key) == "effects":
			has_effects = true
	var obj = _focus_obj()
	script_box.add_child(_label("正在编辑：" + str(spec.get("shown", "卡")) + " " + _owner_name(obj, ""), 15, Color("#4C3D8F")))
	for i in effects_view.size():
		script_box.add_child(_effect_script(i))
	var add := Button.new()
	add.text = "＋ 给「" + _owner_name(obj, str(spec.get("shown", "卡"))) + "」加一条效果"
	add.custom_minimum_size = Vector2(0, 40)
	add.visible = has_effects
	add.pressed.connect(_add_effect)
	script_box.add_child(add)
	if effects_view.is_empty():
		script_box.add_child(_hint("这张牌还没有效果。点上面的按钮加一条，然后从左边拖积木进来。子牌（技能牌、状态、附带物……）的效果在左边「子牌」里点那张牌再编辑。"))


func _add_effect() -> void:
	var obj = _focus_obj()
	if not obj is Dictionary:
		return
	if not obj.get("effects") is Array:
		obj["effects"] = []
	var effect := maker.blank_required("effect")
	effect["effect_name"] = "effect_" + str(obj.effects.size() + 1)
	effect["priority"] = 0
	effect["is_pure_passive"] = true
	obj.effects.append(effect)
	_add_effect_view(effect, "")
	_refresh_scripts()


func _effect_script(index:int) -> Control:
	var view:Dictionary = effects_view[index]
	var effect:Dictionary = view.effect
	_render_effect = effect
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	# 效果头：说明文字 + 设置
	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", _flat(Color("#F2EEFB"), 6, 8, Color("#D8CCF5")))
	col.add_child(info)
	var info_col := VBoxContainer.new()
	info.add_child(info_col)
	var title_row := HBoxContainer.new()
	info_col.add_child(title_row)
	var owner := str(view.owner).trim_prefix("/")
	var badge := _label(("【" + owner + "】 ") if owner != "" else "", 13, Color("#855CD6"))
	title_row.add_child(badge)
	var text := LineEdit.new()
	text.placeholder_text = "照抄卡面上这条效果的原文"
	text.text = str(effect.get("shown_effect_name", ""))
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.tooltip_text = "卡面文字：发动时显示给玩家。"
	text.text_changed.connect(func(v): effect["shown_effect_name"] = v; _changed())
	title_row.add_child(text)
	var del := Button.new()
	del.text = "删除效果"
	del.pressed.connect(_delete_effect.bind(index))
	title_row.add_child(del)
	var settings := _fold_box(info_col, "发动方式与限制", false)
	_paint_fields(settings, effect, _spec_without(maker.item_spec("effect"), ["shown_effect_name", "time_points"]))
	# 帽子积木：当 [时机] 时。只用来算威力、没有时机也没有要做的事的效果，不画这一段
	var power_only:bool = view.lists.has("power_query") and (effect.get("time_points", []) as Array).is_empty() and (view.lists.get("funcs", []) as Array).is_empty() and not (effect.get("options") is Array and not effect.options.is_empty())
	if not power_only:
		col.add_child(_hat_block(effect))
		if effect.get("options") is Array and not effect.options.is_empty():
			col.add_child(_options_view(view))
		else:
			if not view.lists.has("funcs"):
				view.lists["funcs"] = []
			col.add_child(_stack_view(view.lists.funcs, "funcs"))
	if view.lists.has("power_query"):
		col.add_child(_power_hat())
		col.add_child(_stack_view(view.lists.power_query, "power_query"))
	var tools := HBoxContainer.new()
	col.add_child(tools)
	if not (effect.get("options") is Array and not effect.options.is_empty()):
		var to_opt := Button.new()
		to_opt.text = "改成让玩家选一项"
		to_opt.tooltip_text = "效果变成「多选一」：每个选项下面各接一串积木，玩家发动时选其中一项。"
		to_opt.pressed.connect(func():
			effect["options"] = [{"shown_option_name": "选项一", "funcs": codec.encode_effect_list(view.lists.get("funcs", []))}]
			effect["funcs"] = []
			view.lists["funcs"] = []
			view.options = [{"option": effect.options[0], "nodes": codec.decode_list(effect.options[0].funcs), "reqs": []}]
			_refresh_scripts())
		tools.add_child(to_opt)
	if not view.lists.has("power_query"):
		var add_power := Button.new()
		add_power.text = "加一段威力计算"
		add_power.tooltip_text = "只算威力、不改任何东西的积木，界面和结算随时按它算出当前的威力加成。"
		add_power.pressed.connect(func():
			view.lists["power_query"] = []
			effect["power_query"] = []
			_refresh_scripts())
		tools.add_child(add_power)
	return col


func _spec_without(spec:Dictionary, keys:Array) -> Dictionary:
	var copy := spec.duplicate(true)
	copy.fields = spec.get("fields", []).filter(func(f): return not keys.has(str(f.key)))
	return copy


func _delete_effect(index:int) -> void:
	var effect:Dictionary = effects_view[index].effect
	_remove_effect_from(_focus_obj(), effect)
	effects_view.remove_at(index)
	_refresh_scripts()


func _remove_effect_from(node, effect:Dictionary) -> bool:
	if node is Dictionary:
		for key in node:
			if _remove_effect_from(node[key], effect):
				return true
	elif node is Array:
		for i in node.size():
			if typeof(node[i]) == TYPE_DICTIONARY and is_same(node[i], effect):
				node.remove_at(i)
				return true
			if _remove_effect_from(node[i], effect):
				return true
	return false


func _hat_block(effect:Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Shape.new("hat", Color("#FFBF00")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	row.add_child(_block_label("当"))
	var points:Array = effect.get("time_points", []) if effect.get("time_points") is Array else []
	for i in points.size():
		var chip := Button.new()
		chip.text = maker.time_point_shown(str(points[i])) + " ✕"
		chip.tooltip_text = "点一下去掉这个时机"
		chip.add_theme_stylebox_override("normal", Shape.new("reporter", Color("#FFFFFF")))
		chip.add_theme_color_override("font_color", INK)
		chip.pressed.connect(func():
			points.remove_at(i)
			effect["time_points"] = points
			_refresh_scripts())
		row.add_child(chip)
		if i < points.size() - 1:
			row.add_child(_block_label("并且" if bool(effect.get("require_all_time_points", false)) else "或"))
	var menu := _time_point_menu("＋ 时机")
	menu.item_selected.connect(func(idx):
		if idx == 0:
			return
		points.append(menu.get_item_metadata(idx))
		effect["time_points"] = points
		_refresh_scripts())
	row.add_child(menu)
	row.add_child(_block_label("时"))
	if points.is_empty():
		row.add_child(_block_label("（还没选时机）"))
	panel.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_help("当……时", "效果从这里开始。选一个或多个时机，时机到了就往下做积木。\n\n• 默认满足任意一个时机就触发；在「发动方式与限制」里勾「时机要全部同时成立」就变成都要满足。\n• 「自己……」是轮到自己时，「他人……」是轮到别人时。"))
	return panel


func _power_hat() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Shape.new("hat", Color("#0FBDA0")))
	var row := HBoxContainer.new()
	panel.add_child(row)
	row.add_child(_block_label("计算合计威力时"))
	panel.tooltip_text = "这段积木随时被用来算威力，只能放「威力计算」和查询类积木，不能改动游戏。"
	return panel


func _options_view(view:Dictionary) -> Control:
	var col := VBoxContainer.new()
	var effect:Dictionary = view.effect
	for oi in view.options.size():
		var ov:Dictionary = view.options[oi]
		var option:Dictionary = ov.option
		var head := PanelContainer.new()
		head.add_theme_stylebox_override("panel", Shape.new("stack", Color("#FF8C1A")))
		var row := HBoxContainer.new()
		head.add_child(row)
		row.add_child(_block_label("选项 " + str(oi + 1)))
		var name := LineEdit.new()
		name.text = str(option.get("shown_option_name", ""))
		name.placeholder_text = "玩家看到的选项文字"
		name.custom_minimum_size = Vector2(220, 0)
		name.text_changed.connect(func(v): option["shown_option_name"] = v; _changed())
		row.add_child(name)
		var del := Button.new()
		del.text = "删掉此项"
		del.pressed.connect(func():
			effect.options.remove_at(oi)
			view.options.remove_at(oi)
			_refresh_scripts())
		row.add_child(del)
		col.add_child(head)
		var settings := _fold_box(col, "选项的限制", false)
		_paint_fields(settings, option, _spec_without(maker.item_spec("option"), ["shown_option_name"]))
		var body := HBoxContainer.new()
		body.add_child(_spacer(18))
		body.add_child(_stack_view(ov.nodes, "option"))
		col.add_child(body)
	var add := Button.new()
	add.text = "＋ 再加一个选项"
	add.pressed.connect(func():
		var option := {"shown_option_name": "选项" + str(view.options.size() + 1), "funcs": []}
		effect.options.append(option)
		view.options.append({"option": option, "nodes": [], "reqs": []})
		_refresh_scripts())
	col.add_child(add)
	return col


# 一串竖直堆叠的积木，积木之间与末尾都能接住拖来的积木。
func _stack_view(list:Array, context:String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	for i in list.size():
		col.add_child(_gap(list, i, context))
		col.add_child(_render_node(list[i], {"list": list, "index": i, "context": context}))
	col.add_child(_gap(list, list.size(), context, list.is_empty()))
	return col


func _gap(list:Array, index:int, context:String, is_empty := false) -> Control:
	var zone := Panel.new()
	zone.custom_minimum_size = Vector2(160 if is_empty else 200, 30 if is_empty else 8)
	zone.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.04) if is_empty else Color(0, 0, 0, 0)
	s.set_corner_radius_all(4)
	if is_empty:
		s.border_color = Color("#8A90A6")
		s.set_border_width_all(1)
	zone.add_theme_stylebox_override("panel", s)
	if is_empty:
		var lab := _label("把积木拖到这里", 13, HINT)
		lab.position = Vector2(10, 6)
		zone.add_child(lab)
	zone.set_meta("drop", {"kind": "stack", "list": list, "index": index, "context": context})
	if not is_empty:
		zone.set_meta("drop_fn", func(_at:Vector2) -> Dictionary:
			var r := zone.get_global_rect()
			return {"kind": "stack", "list": list, "index": index, "context": context, "marker": Rect2(Vector2(r.position.x, r.get_center().y - 2), Vector2(r.size.x, 4))})
	zone.set_drag_forwarding(Callable(), _can_drop_on.bind(zone), _drop_on.bind(zone))
	return zone


# =============== 积木渲染 ===============

# where: {list, index, context} 表示它在一串积木里；{slot_parent, slot_key} 表示它嵌在空位里；palette 表示在积木区。
func _render_node(node:Dictionary, where:Dictionary) -> Control:
	match str(node.t):
		"if":
			return _render_if(node, where)
		"raw":
			return _render_raw(node, where)
		"slot_only":
			return _render_slot_value(node.slot, where)
	return _render_op(node, where)


func _render_op(node:Dictionary, where:Dictionary) -> Control:
	var op_name := str(node.get("func", node.get("method", "")))
	var op := maker.operation_of(op_name) if node.t == "op" else {}
	var color := _color_of(node)
	var shape := _shape_of(node, where)
	var spec := maker.block_spec(op_name) if node.t == "op" else {}
	var containers:Array = codec.container_params.get(op_name, []) if node.t == "op" else []
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 0)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Shape.new(shape, color))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	wrap.add_child(panel)
	# 积木一行排开、往右长；太长时脚本区可以横向滚动
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	panel.add_child(row)
	var params:Array = node.params
	var used:Dictionary = {}
	if node.t == "method":
		row.add_child(_block_label("让"))
		row.add_child(_slot_widget(node, "target", "对象", "", "", true))
		row.add_child(_block_label("执行 " + str(node.method)))
	var say := maker.say_of(op_name) if node.t == "op" else ""
	var parts := _split_say(say)
	for part in parts:
		if part.begins_with("{"):
			var pname:String = part.substr(1, part.length() - 2)
			var pi := _param_index(op, pname)
			if pi < 0 or containers.has(pi):
				continue
			while params.size() <= pi:
				params.append(_omit_for(op, params.size()))
			used[pi] = true
			row.add_child(_slot_widget(params, pi, maker.param_shown(pname), str(op.params[pi].type), op_name + ":" + pname, bool(op.params[pi].required)))
		elif part.strip_edges() != "":
			row.add_child(_block_label(part.strip_edges()))
	# 句式里没写到、但操作有的空位（可选参数、数据里多写的参数）收进「更多」
	var extra:Array = []
	var hidden:Array = spec.get("hide", [])
	var op_param_list:Array = op.get("params", [])
	for i in params.size():
		if used.has(i) or containers.has(i):
			continue
		if i < op_param_list.size() and hidden.has(str(op_param_list[i].name)):
			continue
		extra.append(i)
	var op_params:Array = op.get("params", [])
	for i in range(params.size(), op_params.size()):
		if not containers.has(i):
			extra.append(i)
	if not extra.is_empty() and not where.get("palette", false):
		var more_on:bool = node.get("_more", false)
		for i in extra:
			var filled:bool = i < params.size() and params[i] is Dictionary and not (str(params[i].get("s", "")) == "omit" or (str(params[i].get("s", "")) == "lit" and params[i].get("v") == null and not params[i].get("loop", false)))
			if filled:
				more_on = true
		var more := Button.new()
		more.text = "▾" if more_on else "…"
		more.tooltip_text = "更多可选设置"
		more.flat = true
		more.add_theme_color_override("font_color", Color.WHITE)
		more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		more.pressed.connect(func(): node["_more"] = not more_on; _refresh_scripts())
		row.add_child(more)
		if more_on:
			for i in extra:
				while params.size() <= i:
					params.append(_omit_for(op, params.size()))
				var pname := str(op_params[i].name) if i < op_params.size() else "参数" + str(i + 1)
				var ptype := str(op_params[i].type) if i < op_params.size() else ""
				var req:bool = i < op_params.size() and bool(op_params[i].required)
				row.add_child(_block_label(maker.param_shown(pname)))
				row.add_child(_slot_widget(params, i, maker.param_shown(pname), ptype, op_name + ":" + pname, req))
	if node.get("cond") is Dictionary and not where.get("palette", false):
		row.add_child(_block_label("仅当"))
		row.add_child(_slot_widget(node, "cond", "条件", "bool", "", true))
	if int(node.get("var", -1)) >= 0 and not where.has("slot_parent"):
		var tag := _label(" → 存为变量 " + str(node.var), 12, Color.WHITE)
		tag.tooltip_text = "后面的积木可以用橙色的「变量 " + str(node.var) + "」读到这一步的结果。"
		tag.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(tag)
	_add_delete_button(row, node, where)
	# C 形积木的嘴
	for ci in containers:
		while params.size() <= ci:
			params.append({"s": "script", "body": []})
		if not params[ci] is Dictionary or str(params[ci].get("s", "")) != "script":
			continue
		if where.get("palette", false):
			var foot_only := PanelContainer.new()
			foot_only.custom_minimum_size = Vector2(120, 16)
			foot_only.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			foot_only.add_theme_stylebox_override("panel", Shape.new("c_bottom", color))
			wrap.add_child(foot_only)
			continue
		_mark_loop_items(node, op, params[ci].body)
		var mouth := HBoxContainer.new()
		mouth.add_theme_constant_override("separation", 0)
		var arm := Panel.new()
		arm.custom_minimum_size = Vector2(16, 0)
		arm.add_theme_stylebox_override("panel", _flat(color, 0, 0))
		mouth.add_child(arm)
		mouth.add_child(_stack_view(params[ci].body, "script"))
		wrap.add_child(mouth)
		var foot := PanelContainer.new()
		foot.custom_minimum_size = Vector2(120, 18)
		foot.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		foot.add_theme_stylebox_override("panel", Shape.new("c_bottom", color))
		wrap.add_child(foot)
		_wire_insert(foot, wrap, where, null, true)
	_wire_block(panel, node, where, wrap, _first_mouth(node, containers))
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return wrap


# 「对每一个」会把当前这一项填进嘴里每一步的「填入位置」那一格（只填空着的）。
# 把这些空格标成「↻ 当前这一项」，只是显示用的记号，保存时仍写成空。
func _mark_loop_items(node:Dictionary, op:Dictionary, body:Array) -> void:
	var fill_name := str(maker.block_spec(str(node.get("func", ""))).get("fill", ""))
	if fill_name == "":
		return
	var fi := _param_index(op, fill_name)
	var fill := 0
	if fi >= 0 and fi < node.params.size():
		var slot = node.params[fi]
		if slot is Dictionary and str(slot.get("s", "")) == "lit" and (slot.v is int or slot.v is float):
			fill = int(slot.v)
	for child in body:
		if not child is Dictionary or not child.has("params"):
			continue
		for i in child.params.size():
			var slot = child.params[i]
			if slot is Dictionary and str(slot.get("s", "")) == "lit":
				if i == fill and slot.get("v") == null:
					slot["loop"] = true
				elif i != fill:
					slot.erase("loop")


func _render_if(node:Dictionary, where:Dictionary) -> Control:
	var color := Color("#FFAB19")
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 0)
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", Shape.new("stack", color))
	wrap.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	top.add_child(row)
	row.add_child(_block_label("如果"))
	row.add_child(_slot_widget(node, "cond", "条件", "bool", "", true))
	row.add_child(_block_label("那么"))
	_add_delete_button(row, node, where)
	if not where.get("palette", false):
		var mouth := HBoxContainer.new()
		mouth.add_theme_constant_override("separation", 0)
		var arm := Panel.new()
		arm.custom_minimum_size = Vector2(16, 0)
		arm.add_theme_stylebox_override("panel", _flat(color, 0, 0))
		mouth.add_child(arm)
		mouth.add_child(_stack_view(node.body, "script"))
		wrap.add_child(mouth)
	var foot := PanelContainer.new()
	foot.custom_minimum_size = Vector2(120, 18)
	foot.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	foot.add_theme_stylebox_override("panel", Shape.new("c_bottom", color))
	wrap.add_child(foot)
	_wire_insert(foot, wrap, where, null, true)
	_wire_block(top, node, where, wrap, node.body)
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return wrap


func _render_raw(node:Dictionary, where:Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Shape.new("stack", Color("#8C8C8C")))
	var row := HBoxContainer.new()
	panel.add_child(row)
	row.add_child(_block_label("看不懂的一步（原样保留）"))
	_add_delete_button(row, node, where)
	panel.tooltip_text = JSON.stringify(node.v)
	_wire_block(panel, node, where)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return panel


# 积木区里的「变量」「当前这一项」这类只有一个值的小积木。
func _render_slot_value(slot:Dictionary, where:Dictionary) -> Control:
	var panel := PanelContainer.new()
	var color := LOOP_ITEM_COLOR if slot.get("loop", false) else VAR_COLOR
	panel.add_theme_stylebox_override("panel", Shape.new("reporter", color))
	var text := ""
	match str(slot.s):
		"var":
			text = "变量 " + str(slot.n)
		"qty":
			text = "选项 " + str(int(slot.i) + 1) + " 选的数量"
		_:
			text = "↻ 当前这一项"
	panel.add_child(_block_label(text))
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return panel


# block：整块积木（C 形积木含嘴和底脚），用来算插入线的位置。mouth：C 形积木嘴里那一串，拖到顶部下半截时插进嘴里。
func _wire_block(panel:Control, node:Dictionary, where:Dictionary, block:Control = null, mouth = null) -> void:
	if where.get("palette", false):
		return
	panel.set_meta("block", node)
	var drag := func(_p): return _begin_drag({"node": node, "from": where}, panel)
	if not _wire_insert(panel, block if block != null else panel, where, mouth, false, drag):
		panel.set_drag_forwarding(drag, Callable(), Callable())
	panel.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			if ev.button_index == MOUSE_BUTTON_LEFT:
				_show_help_for(node)
			elif ev.button_index == MOUSE_BUTTON_RIGHT:
				_open_context(node, where, panel.get_global_mouse_position()))


func _add_delete_button(row:Container, node:Dictionary, where:Dictionary) -> void:
	if where.get("palette", false) or not (where.has("list") or where.has("slot_parent")):
		return
	var del := Button.new()
	del.name = "DeleteBlock"
	del.text = "✕"
	del.flat = true
	del.tooltip_text = "删除这块积木"
	del.focus_mode = Control.FOCUS_NONE
	del.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		del.add_theme_color_override(c, Color.WHITE)
	del.add_theme_stylebox_override("hover", _flat(Color(0, 0, 0, 0.25), 8, 2))
	del.add_theme_stylebox_override("pressed", _flat(Color(0, 0, 0, 0.35), 8, 2))
	del.pressed.connect(func(): _delete_block(node, where))
	row.add_child(del)


func _delete_block(node:Dictionary, where:Dictionary) -> void:
	_detach(node, where, {})
	_refresh_scripts()
	_set_status("已删掉一块积木")


# 积木本身也能接住拖来的积木：上半截插在它前面，下半截插在它后面（C 形积木的顶部下半截插进嘴里的最前面）。
# 放在空位里的积木，拖到它上面就是替换这一格。
func _wire_insert(target:Control, block:Control, where:Dictionary, mouth, is_foot:bool, drag := Callable()) -> bool:
	if where.has("list"):
		target.set_meta("drop_fn", func(at:Vector2) -> Dictionary:
			var index := int(where.index)
			if is_foot:
				return {"kind": "stack", "list": where.list, "index": index + 1, "marker": _line_below(block)}
			if at.y < target.size.y * 0.5:
				return {"kind": "stack", "list": where.list, "index": index, "marker": _line_above(block)}
			if mouth is Array:
				return {"kind": "stack", "list": mouth, "index": 0, "marker": _line_below(target, 16.0)}
			return {"kind": "stack", "list": where.list, "index": index + 1, "marker": _line_below(block)})
	elif where.has("slot_parent"):
		target.set_meta("drop", {"kind": "slot", "holder": where.slot_parent, "key": where.slot_key, "type": ""})
	else:
		return false
	target.set_drag_forwarding(drag, _can_drop_on.bind(target), _drop_on.bind(target))
	return true


func _first_mouth(node:Dictionary, containers:Array):
	for ci in containers:
		if ci < node.params.size() and node.params[ci] is Dictionary and str(node.params[ci].get("s", "")) == "script":
			return node.params[ci].body
	return null


func _line_above(c:Control) -> Rect2:
	var r := c.get_global_rect()
	return Rect2(r.position + Vector2(0, -2), Vector2(maxf(r.size.x, 160), 4))


func _line_below(c:Control, indent := 0.0) -> Rect2:
	var r := c.get_global_rect()
	return Rect2(Vector2(r.position.x + indent, r.end.y - 2), Vector2(maxf(r.size.x - indent, 160), 4))


# =============== 空位 ===============

# holder[key] 是一个空位；空位里可能是字面值、变量、效果数字、嵌套积木。
func _slot_widget(holder, key, label:String, type_name:String, kind_key:String, required:bool) -> Control:
	var slot = holder[key]
	if not slot is Dictionary or not slot.has("s"):
		slot = {"s": "lit", "v": slot}
		holder[key] = slot
	var box := PanelContainer.new()
	var s := str(slot.s)
	var is_bool := type_name == "bool"
	var kind := _slot_kind(kind_key)
	var content:Control
	match s:
		"block", "desc":
			content = _render_op(slot.b, {"slot_parent": holder, "slot_key": key})
			box.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		"var":
			box.add_theme_stylebox_override("panel", Shape.new("reporter", VAR_COLOR))
			content = _var_picker(slot)
		"qty":
			box.add_theme_stylebox_override("panel", Shape.new("reporter", VAR_COLOR))
			content = _block_label("选项 " + str(int(slot.i) + 1) + " 选的数量")
		"num":
			box.add_theme_stylebox_override("panel", Shape.new("slot", Color.WHITE))
			content = _number_editor(slot)
		"script":
			content = _block_label("（一串积木）")
			box.add_theme_stylebox_override("panel", Shape.new("slot", Color.WHITE))
		"list":
			content = _list_editor(slot)
			box.add_theme_stylebox_override("panel", Shape.new("slot", Color("#FFFFFFCC")))
		"omit":
			var shape := Shape.new("boolean" if is_bool else "empty", Color(1, 1, 1, 0.55))
			box.add_theme_stylebox_override("panel", shape)
			content = _literal_editor(holder, key, slot, type_name, kind, label, true)
		_:
			var empty:bool = slot.get("v") == null and not slot.get("loop", false)
			var shape := Shape.new("boolean" if is_bool and empty else "slot", Color.WHITE if not slot.get("loop", false) else LOOP_ITEM_COLOR)
			shape.highlight = empty and required
			box.add_theme_stylebox_override("panel", shape)
			content = _literal_editor(holder, key, slot, type_name, kind, label, false)
	box.add_child(content)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.tooltip_text = label + (("（" + _type_shown(type_name) + "）") if type_name != "" else "") + "\n可以直接填，也可以把积木拖进来。"
	box.set_meta("drop", {"kind": "slot", "holder": holder, "key": key, "type": type_name})
	box.set_drag_forwarding(Callable(), _can_drop_on.bind(box), _drop_on.bind(box))
	var eff = _render_effect
	box.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT and s in ["var", "num", "lit", "qty", "list", "omit"]:
			_open_slot_menu(holder, key, eff, box.get_global_mouse_position()))
	return box


func _slot_kind(kind_key:String) -> String:
	if kind_key == "":
		return ""
	var parts := kind_key.split(":")
	return maker.param_kind(parts[0], parts[1]) if parts.size() == 2 else ""


# 字面值：按空位声明的控件画（玩家下拉、时机、属性、项目名……），缺声明就是普通输入框。
func _literal_editor(holder, key, slot:Dictionary, type_name:String, kind:String, label:String, omitted:bool) -> Control:
	if slot.get("loop", false):
		return _block_label("↻ 当前这一项")
	var value = slot.get("d") if omitted else slot.get("v")
	var set_value := func(v):
		holder[key] = {"s": "lit", "v": v}
		_changed()
	match kind:
		"player", "message_target":
			return _choice_menu(maker.kind_choices(kind), value, omitted, set_value, "发动效果的玩家" if kind == "player" else "所有人")
		"op", "card_category":
			return _choice_menu(maker.kind_choices(kind), value, omitted, set_value, "")
		"player_key":
			return _player_key_menu(value, omitted, set_value)
		"area_name":
			return _area_menu(value, omitted, set_value)
		"time_points", "attributes":
			return _multi_menu(kind, value, omitted, holder, key)
		"time_point":
			var menu := _time_point_menu("选时机" if value == null else maker.time_point_shown(str(value)))
			menu.item_selected.connect(func(i):
				if i > 0:
					set_value.call(menu.get_item_metadata(i))
					_refresh_scripts())
			return menu
	if type_name == "bool" or value is bool:
		var box := CheckBox.new()
		box.button_pressed = value if value is bool else false
		box.text = "是" if box.button_pressed else ("默认" if omitted else "否")
		box.add_theme_color_override("font_color", INK)
		box.toggled.connect(func(on): box.text = "是" if on else "否"; set_value.call(on))
		return box
	var eff = _render_effect
	if type_name == "BaseNumber" and not omitted and value == null:
		var add := Button.new()
		add.text = "填数字"
		add.flat = true
		add.add_theme_color_override("font_color", INK)
		add.tooltip_text = "这里要的是一个效果数字。点一下填一个，或者把算数字的积木拖进来。"
		add.pressed.connect(func():
			holder[key] = _new_number_slot(0, eff)
			_refresh_scripts())
		return add
	if type_name == "BaseNumber" and omitted:
		var add := Button.new()
		add.text = "默认"
		add.flat = true
		add.add_theme_color_override("font_color", HINT)
		add.tooltip_text = "空着就用默认值。点一下填一个数字。"
		add.pressed.connect(func():
			holder[key] = _new_number_slot(0, eff)
			_refresh_scripts())
		return add
	if type_name in ["int", "float"] or value is int or value is float:
		var is_float:bool = type_name == "float" or (type_name != "int" and value is float and value != floor(value))
		var spin := _spin(float(value) if (value is int or value is float) else 0.0, is_float)
		spin.custom_minimum_size = Vector2(76, 0)
		if omitted:
			spin.modulate = Color(1, 1, 1, 0.6)
		spin.value_changed.connect(func(v): set_value.call(v if is_float else int(v)))
		return spin
	if value is Array or value is Dictionary or type_name in ["Array", "Dictionary"]:
		var edit := LineEdit.new()
		edit.text = JSON.stringify(value) if value != null else ""
		edit.placeholder_text = label
		edit.custom_minimum_size = Vector2(120, 0)
		edit.tooltip_text = "按 JSON 写，例如 [\"magic\"] 或 {\"type\": \"battle\"}"
		edit.text_submitted.connect(func(t): _set_json_text(holder, key, t))
		edit.focus_exited.connect(func(): _set_json_text(holder, key, edit.text))
		return edit
	var edit := LineEdit.new()
	edit.text = str(value) if value != null else ""
	edit.placeholder_text = ("默认 " + str(value) if omitted and value != null else label)
	edit.expand_to_text_length = true
	edit.custom_minimum_size = Vector2(60, 0)
	edit.add_theme_color_override("font_color", INK)
	edit.text_changed.connect(func(t): set_value.call(t))
	return edit


func _set_json_text(holder, key, text:String) -> void:
	if text.strip_edges() == "":
		holder[key] = {"s": "lit", "v": null}
		_changed()
		return
	var parser := JSON.new()
	if parser.parse(text) != OK:
		_set_status("这一格要按 JSON 写：" + parser.get_error_message())
		return
	holder[key] = {"s": "lit", "v": parser.data}
	_changed()


func _choice_menu(choices:Array, value, omitted:bool, set_value:Callable, default_text:String) -> OptionButton:
	var menu := OptionButton.new()
	var selected := -1
	for c in choices:
		menu.add_item(str(c.shown))
		if typeof(c.v) == typeof(value) and c.v == value or (c.v is float and value is int and int(c.v) == value) or ((c.v is int or c.v is float) and (value is int or value is float) and float(c.v) == float(value)):
			selected = menu.item_count - 1
	if selected < 0 and value != null:
		menu.add_item(str(value))
		selected = menu.item_count - 1
	if selected < 0 and omitted and default_text != "":
		menu.add_item("默认：" + default_text)
		selected = menu.item_count - 1
	menu.selected = selected
	menu.item_selected.connect(func(i):
		if i < choices.size():
			set_value.call(choices[i].v))
	return menu


func _player_key_menu(value, omitted:bool, set_value:Callable) -> OptionButton:
	var names:Dictionary = maker.types.get("player_key_names", {})
	var menu := OptionButton.new()
	var selected := -1
	for key in maker.player_keys:
		var base := str(key).split(".")[0]
		var shown := str(names.get(key, "")) if names.has(key) else (str(names.get(base, base)) + " · " + str(key).get_slice(".", 1) if str(key).find(".") != -1 else str(key))
		menu.add_item(shown)
		menu.set_item_metadata(menu.item_count - 1, key)
		if str(value) == str(key):
			selected = menu.item_count - 1
	if selected < 0:
		menu.add_item(str(value) if value != null else "选一项")
		menu.set_item_metadata(menu.item_count - 1, value)
		selected = menu.item_count - 1
	menu.selected = selected
	menu.item_selected.connect(func(i): set_value.call(menu.get_item_metadata(i)))
	return menu


func _area_menu(value, omitted:bool, set_value:Callable) -> OptionButton:
	var menu := OptionButton.new()
	var selected := -1
	for area in MapData.areas:
		menu.add_item(str(area._area_name))
		if str(value) == str(area._area_name):
			selected = menu.item_count - 1
	if selected < 0:
		menu.add_item(str(value) if value != null else "选战区")
		selected = menu.item_count - 1
	menu.selected = selected
	menu.item_selected.connect(func(i):
		if i < MapData.areas.size():
			set_value.call(str(MapData.areas[i]._area_name)))
	return menu


# 时机列表、属性列表：一排小标签，点 ✕ 去掉，下拉加一个。
func _multi_menu(kind:String, value, omitted:bool, holder, key) -> Control:
	var list:Array = value.duplicate() if value is Array else []
	var row := HBoxContainer.new()
	for i in list.size():
		var chip := Button.new()
		chip.text = (maker.time_point_shown(str(list[i])) if kind == "time_points" else Attributes.get_shown_attribute(str(list[i]))) + " ✕"
		chip.pressed.connect(func():
			list.remove_at(i)
			holder[key] = {"s": "lit", "v": list}
			_refresh_scripts())
		row.add_child(chip)
	var menu := OptionButton.new()
	menu.add_item("＋")
	var source:Array = maker.time_points if kind == "time_points" else maker.attributes
	for item in source:
		menu.add_item(str(item.shown))
		menu.set_item_metadata(menu.item_count - 1, item.id)
	menu.item_selected.connect(func(i):
		if i == 0:
			return
		list.append(menu.get_item_metadata(i))
		holder[key] = {"s": "lit", "v": list}
		_refresh_scripts())
	row.add_child(menu)
	if list.is_empty() and omitted:
		row.add_child(_block_label("默认"))
	return row


func _var_picker(slot:Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_child(_block_label("变量"))
	var spin := _spin(float(slot.n), false)
	spin.min_value = 0
	spin.custom_minimum_size = Vector2(56, 0)
	spin.tooltip_text = "读前面「存为变量 N」那一步的结果。"
	spin.value_changed.connect(func(v): slot.n = int(v); _changed())
	row.add_child(spin)
	return row


func _list_editor(slot:Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_child(_block_label("["))
	for i in slot.items.size():
		row.add_child(_slot_widget(slot.items, i, "第 " + str(i + 1) + " 个", "", "", false))
	var add := Button.new()
	add.text = "＋"
	add.flat = true
	add.pressed.connect(func(): slot.items.append({"s": "lit", "v": null}); _refresh_scripts())
	row.add_child(add)
	row.add_child(_block_label("]"))
	return row


# 效果数字：直接在积木上改数值；它存放在效果的数字表里，多处引用同一个时会一起变。
func _number_editor(slot:Dictionary) -> Control:
	var effect = _effect_of_slot(slot)
	var numbers:Array = effect.get("effect_numbers", []) if effect is Dictionary else []
	var i := int(slot.i)
	if i < 0 or i >= numbers.size() or not numbers[i] is Dictionary:
		return _block_label("数字 #" + str(i) + " 不存在")
	var num:Dictionary = numbers[i]
	var spin := _spin(float(num.get("number", 0)), bool(num.get("is_float", false)))
	spin.custom_minimum_size = Vector2(76, 0)
	var shared := _number_ref_count(effect, i) > 1
	spin.tooltip_text = "效果数字" + ("（这个数字有多处在用，改一处会一起变）" if shared else "")
	spin.value_changed.connect(func(v): num["number"] = v; _changed())
	return spin


func _new_number_slot(value, effect = null) -> Dictionary:
	if not effect is Dictionary:
		return {"s": "lit", "v": value}
	if not effect.get("effect_numbers") is Array:
		effect["effect_numbers"] = []
	effect.effect_numbers.append({"number": value, "can_change": true, "is_pure_number": true})
	return {"s": "num", "i": effect.effect_numbers.size() - 1}


func _effect_of_slot(_slot:Dictionary):
	return _render_effect


func _number_ref_count(effect:Dictionary, index:int) -> int:
	var text := JSON.stringify(effect)
	return text.count("\"number_index\":" + str(index)) + text.count("\"number_index\":" + str(index) + ".0")


# =============== 拖放 ===============

func _begin_drag(payload:Dictionary, source:Control) -> Variant:
	var preview := source.duplicate(0) as Control
	preview.modulate = Color(1, 1, 1, 0.8)
	set_drag_preview(preview)
	return payload


# 按鼠标位置算出这次会放到哪里：带 drop_fn 的（积木、缝）按上下半截决定插入位置，其余用固定的 drop。
func _drop_of(target:Control, at:Vector2) -> Dictionary:
	if target.has_meta("drop_fn"):
		return (target.get_meta("drop_fn") as Callable).call(at)
	if target.has_meta("drop"):
		return target.get_meta("drop")
	return {}


func _clear_drop_hint() -> void:
	if drop_marker:
		drop_marker.visible = false
	if is_instance_valid(hover_target):
		hover_target.modulate = Color(1, 1, 1)
	hover_target = null


func _show_drop_hint(target:Control, drop:Dictionary) -> void:
	_clear_drop_hint()
	if drop.has("marker"):
		var r:Rect2 = drop.marker
		drop_marker.position = r.position
		drop_marker.size = r.size
		drop_marker.visible = true
	else:
		target.modulate = Color(1.0, 0.95, 0.6)
		hover_target = target


# 这一格接不住（比如把一整块积木拖到积木里的空位上），就往外找能接住的那块积木或缝，交给它。
# 返回 {target, drop}；都接不住返回空字典。
func _resolve_drop(target:Control, at:Vector2, payload) -> Dictionary:
	if not payload is Dictionary:
		return {}
	var node = _payload_node(payload, false)
	if node == null:
		return {}
	var global := target.get_global_transform() * at
	var c:Node = target
	while c is Control and c != script_box:
		if c.has_meta("drop") or c.has_meta("drop_fn"):
			var local := (c as Control).get_global_transform().affine_inverse() * global
			var drop := _drop_of(c, local)
			if _accepts(drop, node, payload):
				return {"target": c, "drop": drop}
		c = c.get_parent()
	return {}


func _accepts(drop:Dictionary, node:Dictionary, payload:Dictionary) -> bool:
	if drop.is_empty():
		return false
	if drop.kind == "stack":
		return node.t != "slot_only" and not (payload.has("node") and _contains_list(payload.node, drop.list))
	return (node.t == "slot_only" or node.t == "op" or node.t == "method") and not (payload.has("node") and _contains_holder(payload.node, drop.holder))


func _can_drop_on(at:Vector2, payload, target:Control) -> bool:
	var found := _resolve_drop(target, at, payload)
	if found.is_empty():
		_clear_drop_hint()
		return false
	_show_drop_hint(found.target, found.drop)
	return true


func _drop_on(at:Vector2, payload, target:Control) -> void:
	_clear_drop_hint()
	var found := _resolve_drop(target, at, payload)
	if found.is_empty():
		return
	var drop:Dictionary = found.drop
	var node = _payload_node(payload, true)
	# 插入位置按拿走之前的列表算：同一串里往后挪时，拿走自己后要往前补一位
	var index := 0
	if drop.kind == "stack":
		index = mini(int(drop.index), drop.list.size())
		if payload.has("node") and payload.from.has("list") and is_same(payload.from.list, drop.list) and int(payload.from.index) < index:
			index -= 1
	if payload.has("node"):
		_detach(payload.node, payload.from, drop)
	if drop.kind == "stack":
		drop.list.insert(mini(index, drop.list.size()), node)
	else:
		if node.t == "slot_only":
			drop.holder[drop.key] = node.slot.duplicate(true)
		else:
			drop.holder[drop.key] = {"s": "block", "b": node}
	_refresh_scripts()
	_show_help_for(node)


func _payload_node(payload:Dictionary, fresh:bool):
	if payload.has("new"):
		return _node_from_palette(payload.new) if fresh else _node_from_palette(payload.new)
	if payload.has("node"):
		return payload.node
	return null


# 从原来的位置拿走（换位置时）。
func _detach(node:Dictionary, from:Dictionary, _to:Dictionary) -> void:
	if from.has("list"):
		var list:Array = from.list
		for i in list.size():
			if is_same(list[i], node):
				list.remove_at(i)
				return
	elif from.has("slot_parent"):
		from.slot_parent[from.slot_key] = _empty_slot()


func _palette_can_drop(_at:Vector2, payload) -> bool:
	_clear_drop_hint()
	return payload is Dictionary and payload.has("node")


func _palette_drop(_at:Vector2, payload) -> void:
	_detach(payload.node, payload.from, {})
	_refresh_scripts()
	_set_status("已删掉一块积木")


func _contains_list(node, list:Array) -> bool:
	if node is Dictionary:
		for key in node:
			var v = node[key]
			if v is Array and is_same(v, list):
				return true
			if _contains_list(v, list):
				return true
	elif node is Array:
		for item in node:
			if _contains_list(item, list):
				return true
	return false


func _contains_holder(node, holder) -> bool:
	if is_same(node, holder):
		return true
	if node is Dictionary:
		for key in node:
			if typeof(node[key]) in [TYPE_DICTIONARY, TYPE_ARRAY] and _contains_holder(node[key], holder):
				return true
	elif node is Array:
		for item in node:
			if typeof(item) in [TYPE_DICTIONARY, TYPE_ARRAY] and _contains_holder(item, holder):
				return true
	return false


# =============== 右键菜单 ===============

func _open_context(node:Dictionary, where:Dictionary, at:Vector2) -> void:
	context_target = {"node": node, "where": where}
	context_menu.clear()
	context_menu.add_item("复制一块", 1)
	if clipboard != null and where.has("list"):
		context_menu.add_item("在下面粘贴", 2)
	context_menu.add_item("删除", 3)
	if (node.t == "op" or node.t == "method") and where.has("list"):
		context_menu.add_separator()
		if int(node.get("var", -1)) >= 0:
			context_menu.add_item("不再存为变量", 4)
		else:
			context_menu.add_item("把结果存为变量……", 5)
		if node.get("cond") == null:
			context_menu.add_item("加一个「仅当」条件", 6)
		else:
			context_menu.add_item("去掉「仅当」条件", 7)
	context_menu.position = Vector2i(at)
	context_menu.popup()


func _context_pressed(id:int) -> void:
	if id >= 11:
		_slot_menu_pressed(id)
		return
	if not context_target.has("node"):
		return
	var node:Dictionary = context_target.node
	var where:Dictionary = context_target.where
	match id:
		1:
			clipboard = _fresh_copy(node)
			if where.has("list"):
				where.list.insert(int(where.index) + 1, _fresh_copy(clipboard))
		2:
			where.list.insert(int(where.index) + 1, _fresh_copy(clipboard))
		3:
			_detach(node, where, {})
		4:
			node.var = -1
		5:
			node.var = codec.max_var(_all_nodes_of_current()) + 1
			_set_status("这一步的结果存为变量 " + str(node.var) + "。去左边「变量」拖一块出来放到要用的地方。")
		6:
			node.cond = _empty_slot()
		7:
			node.cond = null
	_refresh_scripts()


func _all_nodes_of_current() -> Array:
	var out:Array = []
	for view in effects_view:
		out.append(view.lists)
		for ov in view.options:
			out.append(ov.nodes)
	return out


func _open_slot_menu(holder, key, effect, at:Vector2) -> void:
	context_menu.clear()
	context_target = {"slot_holder": holder, "slot_key": key, "effect": effect}
	context_menu.add_item("清空这一格", 11)
	context_menu.add_item("改成效果数字", 12)
	context_menu.add_item("改成读变量", 13)
	context_menu.add_item("改成「↻ 当前这一项」（循环里用）", 14)
	context_menu.position = Vector2i(at)
	context_menu.popup()


func _slot_menu_pressed(id:int) -> void:
	if not context_target.has("slot_holder"):
		return
	var holder = context_target.slot_holder
	var key = context_target.slot_key
	match id:
		11:
			holder[key] = _empty_slot()
		12:
			holder[key] = _new_number_slot(0, context_target.get("effect"))
		13:
			holder[key] = {"s": "var", "n": 0}
		14:
			holder[key] = {"s": "lit", "v": null, "loop": true}
	_refresh_scripts()


# =============== 说明 / 问题 ===============

func _show_welcome() -> void:
	_show_help("怎么用", "[b]像搭积木一样写卡牌效果[/b]\n\n1. 上面选卡牌种类，在左中「选一张卡」里双击打开，或点「新建一张」。\n2. 在「卡面信息」里填牌名、选图。\n3. 在「效果积木」里，每条效果先选[color=#c08000]当……时[/color]，再从最左边的积木区把积木拖到下面。\n4. 白色的圆角格子是[b]空位[/b]：可以直接填，也可以把圆角积木（算出一个值的积木）拖进去。\n5. 橙色「如果……那么」把要做的事包起来，就只在条件成立时做。\n6. 点任意积木，这里会告诉你它是干什么的。点积木右边的 ✕ 删除它，右键可以复制。\n7. 想插在两块积木中间，就拖到下面那块的上半截或上面那块的下半截，会出现一条蓝线标出位置。\n8. 右下「还要修的地方」清空后就能保存。")


func _show_help_for(node:Dictionary) -> void:
	match str(node.t):
		"if":
			_show_help("如果……那么", "只有当条件成立时，才做嘴里的积木。\n\n条件格里放六边形或圆角积木都行：得到「是」、非 0 的数字、找到了东西，都算成立；「否」、0、什么都没拿到，都算不成立。")
			return
		"slot_only":
			var s:Dictionary = node.slot
			if s.s == "var":
				_show_help("变量", "读前面某一步存下的结果。\n\n先右键那一步 →「把结果存为变量」，它会显示「→ 存为变量 N」；再把这块拖进要用的空位，把编号改成 N。\n\n大多数时候不用变量：直接把圆角积木拖进空位里就行，保存时会自动处理。")
			elif s.s == "qty":
				_show_help("选项选的数量", "效果做成多选一、并且选项设了数量范围时，玩家选的那个数量。")
			else:
				_show_help("↻ 当前这一项", "放在「对……里的每一个」的嘴里。每一轮，它代表正在处理的那一个。\n\n注意：程序是按「填入位置」把当前这一个填进嘴里每一步的某个空位的，只填空着的那一格。")
			return
		"raw":
			_show_help("看不懂的一步", "这一步的写法编辑器还不认识，会原样保留、原样保存，不会丢。\n\n原文：\n" + JSON.stringify(node.v))
			return
	var name := str(node.get("func", node.get("method", "")))
	var spec := maker.block_spec(name)
	var op := maker.operation_of(name)
	var say := maker.say_of(name).replace("{", "【").replace("}", "】")
	var lines:Array = []
	var help := maker.help_of(name)
	if not op.is_empty() and not bool(op.get("registered", true)):
		lines.append("[color=#8c8c8c]这是新加的操作，还没登记到 all_operations.gd；登记后会归到对应分类。[/color]")
	if help != "":
		lines.append(help)
	if not op.is_empty():
		var ps:Array = []
		for p in op.params:
			ps.append("• " + maker.param_shown(str(p.name)) + "：" + _type_shown(str(p.type)) + ("" if p.required else "，可以不填"))
		if not ps.is_empty():
			lines.append("[b]空位[/b]\n" + "\n".join(PackedStringArray(ps)))
	if op.is_empty() and node.t == "op":
		lines.append("[color=#c03030]找不到这个积木对应的程序：" + name + "[/color]")
	lines.append("[color=#a0a0a0]程序名：" + name + "[/color]")
	_show_help(say, "\n\n".join(PackedStringArray(lines)))


func _show_help(title:String, text:String) -> void:
	help_title.text = title
	help_body.text = text


func _type_shown(type_name:String) -> String:
	return str(maker.types.get("type_names", {}).get(type_name, type_name if type_name != "" else "任意"))


func _collect_issues() -> Array:
	var out:Array = []
	var stored = data
	for issue in maker.validate(stored, card_kind):
		out.append(str(issue))
	# 其他子牌的效果：按已写回的 JSON 临时解码检查，保证保存前整张卡都查过
	var all:Array = []
	_all_effects(data, "", all)
	for entry in all:
		var effect:Dictionary = entry.effect
		var in_view := false
		for view in effects_view:
			if is_same(view.effect, effect):
				in_view = true
		if in_view:
			continue
		var label := ("【" + str(entry.owner) + "】" if str(entry.owner) != "" else "") + "效果「" + str(effect.get("shown_effect_name", effect.get("effect_name", ""))) + "」"
		for key in ["funcs", "power_query"]:
			if effect.get(key) is Array:
				_empty_issues(codec.decode_list(effect[key]), label, out)
	for i in effects_view.size():
		var view:Dictionary = effects_view[i]
		var label := "效果「" + str(view.effect.get("shown_effect_name", view.effect.get("effect_name", i + 1))) + "」"
		if (view.effect.get("time_points", []) as Array).is_empty() and not (view.lists.get("funcs", []) as Array).is_empty():
			out.append(label + "还没选时机")
		for key in view.lists:
			_empty_issues(view.lists[key], label, out)
		for ov in view.options:
			_empty_issues(ov.nodes, label, out)
	return out


func _empty_issues(nodes:Array, label:String, out:Array) -> void:
	for node in nodes:
		if not node is Dictionary:
			continue
		if node.t == "if":
			if node.cond is Dictionary and node.cond.s == "lit" and node.cond.get("v") == null:
				out.append(label + "里有一块「如果」还没放条件")
			_empty_issues(node.body, label, out)
			if node.cond is Dictionary and node.cond.s == "block":
				_empty_issues([node.cond.b], label, out)
			continue
		if node.t != "op":
			continue
		var op := maker.operation_of(str(node.func))
		for pi in node.params.size():
			var slot = node.params[pi]
			if not slot is Dictionary:
				continue
			if slot.s == "block" or slot.s == "desc":
				_empty_issues([slot.b], label, out)
			elif slot.s == "script":
				_empty_issues(slot.body, label, out)
			elif slot.s == "lit" and slot.get("v") == null and not slot.get("loop", false) and pi < op.get("params", []).size() and bool(op.params[pi].required):
				out.append(label + "：「" + maker.say_of(str(node.func)).replace("{", "").replace("}", "") + "」的「" + maker.param_shown(str(op.params[pi].name)) + "」还空着")


func _paint_issues(issues:Array) -> void:
	_clear(issue_list)
	if data == null:
		return
	if issues.is_empty():
		issue_list.add_child(_label("✔ 没有问题，可以保存", 14, Color("#2E9E4F")))
		return
	for issue in issues.slice(0, 40):
		var lab := _label("• " + str(issue), 13, Color("#C0392B"))
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		issue_list.add_child(lab)


# =============== 保存 / 选图 ===============

func _save() -> void:
	if data == null:
		return
	if path != "":
		_save_to(path)
		return
	# 新卡：按 data 现有的目录与命名规则放；算不出位置、或那里已有文件，就让人自己选
	_commit()
	var suggested := maker.suggest_path(card_kind, data if data is Dictionary else {})
	if suggested == "":
		_set_status("先填好内部名等决定文件夹的字段，才能按规则存到 data 里")
		return
	if FileAccess.file_exists(suggested):
		_save_as()
		return
	_save_to(suggested)


func _save_as() -> void:
	if data == null:
		return
	_commit()
	var suggested := maker.suggest_path(card_kind, data if data is Dictionary else {})
	save_dialog.current_path = ProjectSettings.globalize_path(suggested) if suggested.begins_with("res://") else suggested
	save_dialog.popup_centered_ratio(0.7)


func _save_to(target:String) -> void:
	_commit()
	var issues := _collect_issues()
	if not issues.is_empty():
		_set_status("还有 " + str(issues.size()) + " 处要修，先没保存。看右边「还要修的地方」。")
		return
	var local := ProjectSettings.localize_path(target)
	if local == path and original != null and Codec.same(data, original):
		dirty = false
		_mark_saved()
		_set_status("✓ 没有改动，不用保存")
		return
	var dest := local if local.begins_with("res://") else target
	# 图片与 json 放在同一个文件夹：暂存区的图按命名规则搬过去，另存到别处时把原文件夹的图一起带过去
	var from_folder := path.get_base_dir() if path != "" and path.get_base_dir() != dest.get_base_dir() else ""
	var placed := maker.place_images(data, card_kind, dest.get_base_dir(), from_folder)
	if not placed.missing.is_empty() or not placed.errors.is_empty():
		_set_status("找不到或复制不了图片：" + ", ".join(PackedStringArray(placed.missing + placed.errors)) + "，先没保存")
		return
	var saved := maker.save_file(dest, data, card_kind, style)
	if not saved.get("ok", false):
		_set_status(str(saved.get("error", "写不进去")))
		return
	path = str(saved.path)
	original = data.duplicate(true)
	dirty = false
	if not history.is_empty():
		history[history_index].data = data.duplicate(true)   # 改了图片名，这一步记成保存后的样子
	_mark_saved()
	if not placed.placed.is_empty():
		_paint_card()
		_update_json()
	_set_status("✓ 已保存 " + path.get_file() + ("，放入图片 " + str(placed.placed.size()) if not placed.placed.is_empty() else ""))
	_select_kind(kind_button.selected)


# 打包 zip：先保存（有改动时），再选 zip 放哪
func _zip_card() -> void:
	if data == null:
		return
	if dirty or path == "":
		_save()
		if dirty or path == "":
			return
	var name := path.get_base_dir().get_file() if maker.kind_spec(card_kind).get("file", "") == "folder" else path.get_file().get_basename()
	var zip_dir := str(maker.global_export("zip_dir", "exports"))
	zip_dialog.current_path = ProjectSettings.globalize_path(maker._res(zip_dir)).path_join(name + ".zip")
	zip_dialog.popup_centered_ratio(0.7)


func _zip_to(target:String) -> void:
	var files := maker.card_files(data, card_kind, path)
	# zip 里从哪一层开始放，按导出设置（默认相对项目根：data/masters/…，解压到项目根就回到原位）
	var zipped := maker.zip_files(files, target, maker.zip_base(card_kind, path))
	if not zipped.get("ok", false):
		_set_status(str(zipped.get("error", "打包失败")))
		return
	_set_status("✓ 已打包 " + target.get_file() + "：" + str(zipped.count) + " 个文件")


func _pick_image(obj:Dictionary, key:String, zoom_key:String) -> void:
	image_target = {"obj": obj, "key": key, "zoom": zoom_key}
	image_dialog.popup_centered_ratio(0.7)


func _image_chosen(source:String) -> void:
	var copied := maker.copy_image(source, PENDING_IMAGES)
	if not copied.get("ok", false):
		_set_status(str(copied.get("error", "选图失败")))
		return
	# 记完整路径：保存时据此认出是新选的图，按命名规则搬进卡的文件夹
	image_target.obj[image_target.key] = str(copied.path)
	var zoom := str(image_target.get("zoom", ""))
	if zoom != "" and str(image_target.obj.get(zoom, "")) == "":
		image_target.obj[zoom] = "card"
	_changed()
	call_deferred("_paint_card")
	_set_status("已选图，放大方式先按卡牌图处理")


# =============== 小工具 ===============

func _color_of(node:Dictionary) -> Color:
	if node.t == "method":
		return Color("#8C8C8C")
	var op := maker.operation_of(str(node.get("func", "")))
	var cat := maker.category_of(str(op.get("category", "")))
	return Color(str(cat.get("color", "#8C8C8C")))


func _shape_of(node:Dictionary, where:Dictionary) -> String:
	var name := str(node.get("func", ""))
	var spec := maker.block_spec(name)
	var op := maker.operation_of(name)
	var inside_slot:bool = where.has("slot_parent")
	var cat := maker.category_of(str(op.get("category", "")))
	var is_reporter:bool = bool(cat.get("reporter", false)) or str(spec.get("shape", "")) in ["reporter", "boolean"]
	if inside_slot or (where.get("palette", false) and is_reporter):
		if str(spec.get("shape", "")) == "boolean" or str(op.get("returns", "")) == "bool":
			return "boolean"
		return "reporter"
	return "stack"


func _split_say(say:String) -> Array:
	var out:Array = []
	var cur := ""
	var i := 0
	while i < say.length():
		var ch := say[i]
		if ch == "{":
			if cur != "":
				out.append(cur)
			var end := say.find("}", i)
			if end == -1:
				cur = say.substr(i)
				break
			out.append(say.substr(i, end - i + 1))
			cur = ""
			i = end + 1
			continue
		cur += ch
		i += 1
	if cur != "":
		out.append(cur)
	return out


func _param_index(op:Dictionary, pname:String) -> int:
	var params:Array = op.get("params", [])
	for i in params.size():
		if str(params[i].name) == pname:
			return i
	return -1


func _block_label(text:String) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_color_override("font_color", Color.WHITE)
	lab.add_theme_font_size_override("font_size", 14)
	lab.mouse_filter = Control.MOUSE_FILTER_PASS
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return lab


func _label(text:String, size := 14, color := INK) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", color)
	return lab


func _hint(text:String) -> Label:
	var lab := _label(text, 13, HINT)
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return lab


func _section_title(text:String, help:String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 8)
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_right", 8)
	pad.add_child(col)
	col.add_child(_label(text, 16, Color("#4C3D8F")))
	col.add_child(_hint(help))
	return pad


func _welcome_card() -> Control:
	var lab := _hint("还没打开卡。左边选一张，或者点上面的「新建一张」。")
	return lab


func _fold_box(parent:Node, title:String, open:bool) -> VBoxContainer:
	var button := Button.new()
	button.text = ("▾ " if open else "▸ ") + title
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.flat = true
	button.add_theme_color_override("font_color", Color("#4C3D8F"))
	parent.add_child(button)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	parent.add_child(pad)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(box)
	pad.visible = open
	button.pressed.connect(func():
		pad.visible = not pad.visible
		button.text = ("▾ " if pad.visible else "▸ ") + title)
	return box


func _spin(value:float, allow_float:bool) -> SpinBox:
	var spin := SpinBox.new()
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.min_value = -9999
	spin.max_value = 9999
	spin.step = 0.01 if allow_float else 1.0
	spin.value = value
	return spin


func _top_button(parent:Node, text:String, pressed:Callable, tip:String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.pressed.connect(pressed)
	parent.add_child(button)
	return button


func _spacer(width:int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 0)
	return c


func _flat(color:Color, radius:int, margin:int, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	if border.a > 0:
		s.border_color = border
		s.set_border_width_all(1)
	return s


# ratio：第一块占这一整块的比例。拖动后按比例记下，窗口大小变了也照比例摆。
func _split(horizontal:bool, name:String, ratio:float) -> SplitContainer:
	var split:SplitContainer = HSplitContainer.new() if horizontal else VSplitContainer.new()
	split.name = "Split" + name
	split.set_meta("ratio", ratio)
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 8)
	split.dragged.connect(func(_o): _remember_ratio(split))
	split.resized.connect(func(): _apply_ratio(split))
	splits.append(split)
	return split


func _split_length(split:SplitContainer) -> float:
	return split.size.x if split is HSplitContainer else split.size.y


func _first_length(split:SplitContainer) -> float:
	for child in split.get_children():
		if child is Control and child.visible:
			return child.size.x if split is HSplitContainer else child.size.y
	return 0.0


# 按比例直接算出绝对值，不按现在的尺寸累加：同一帧里多次调用也不会越加越偏。
func _apply_ratio(split:SplitContainer) -> void:
	var total := _split_length(split)
	var first := _first_child(split)
	if total <= 0 or first == null:
		return
	var horizontal := split is HSplitContainer
	if horizontal:
		first.size_flags_horizontal = Control.SIZE_FILL
	else:
		first.size_flags_vertical = Control.SIZE_FILL
	# 实测本版本 Godot：第一块不扩展时，split_offset 就是第一块的长度（仍不小于它的最小尺寸）
	var offset := int(float(split.get_meta("ratio", 0.5)) * (total - 8))
	if split.split_offset != offset:
		split.split_offset = offset
		# 不手动 clamp：还没排过版时没有拖动条可夹会报越界，排版时 Godot 自己会夹到最小尺寸


func _first_child(split:SplitContainer) -> Control:
	for child in split.get_children():
		if child is Control:
			return child
	return null


func _remember_ratio(split:SplitContainer) -> void:
	var total := _split_length(split)
	if total > 8:
		split.set_meta("ratio", clampf(_first_length(split) / (total - 8), 0.02, 0.98))
	_save_layout()


func _load_layout() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(LAYOUT_PATH) == OK:
		for split in splits:
			if cfg.has_section_key("ratio", split.name):
				split.set_meta("ratio", float(cfg.get_value("ratio", split.name)))
	call_deferred("_apply_all_ratios")


func _apply_all_ratios() -> void:
	# 外层先摆好，里层的大小才对；多摆一轮让嵌套的都稳定下来
	for pass_i in 2:
		for split in splits:
			_apply_ratio(split)
		await get_tree().process_frame


func _save_layout() -> void:
	var cfg := ConfigFile.new()
	for split in splits:
		cfg.set_value("ratio", split.name, float(split.get_meta("ratio", 0.5)))
	cfg.save(LAYOUT_PATH)


func _clear(node:Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.free()


func _set_status(text:String) -> void:
	if dirty and not text.begins_with("⚠"):
		status.text = "⚠ 未保存修改" + (" · " + text if text != "" else "")
		status.add_theme_color_override("font_color", Color("#FFE08A"))
	elif text.begins_with("✓"):
		status.text = text
		status.add_theme_color_override("font_color", Color("#B8F5C8"))
	else:
		status.text = text
		status.add_theme_color_override("font_color", Color.WHITE)


# =============== 快捷键 ===============

func _input(event:InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if not (event.ctrl_pressed or event.meta_pressed) or save_dialog.visible or image_dialog.visible or zip_dialog.visible:
		return
	match event.keycode:
		KEY_S:
			_save()
		KEY_Z:
			if event.shift_pressed:
				redo()
			else:
				undo()
		KEY_Y:
			redo()
		_:
			return
	# 输入框自带的撤回只管自己那一格，统一走整张卡的修改记录
	get_viewport().set_input_as_handled()


# =============== 修改记录 ===============

# 打开或新建时的起点。saved 表示这一步与磁盘上的文件一致。
func _reset_history(label:String, saved:bool) -> void:
	history.clear()
	history_index = -1
	_push_history(label, "", saved)


func _push_history(label:String, where:String, saved:bool) -> void:
	history.resize(history_index + 1)   # 撤回后又改动：丢掉原来的「以后」
	history.append({"data": data.duplicate(true), "label": label, "where": where, "time": Time.get_ticks_msec(), "clock": Time.get_time_string_from_system(), "saved": saved})
	if history.size() > HISTORY_LIMIT:
		history.remove_at(0)
	history_index = history.size() - 1
	_paint_history()


# 每次写回 JSON 后调用：内容跟当前节点不同就记一步；同一处连续改动合并。
func _record_history() -> void:
	if history_restoring or history.is_empty() or data == null:
		return
	var current:Dictionary = history[history_index]
	if Codec.same(current.data, data):
		return
	var where := _first_diff(current.data, data, [])
	var label := _where_shown(where)
	var now := Time.get_ticks_msec()
	var key := "/".join(PackedStringArray(where.map(func(p): return str(p))))
	if history_index > 0 and history_index == history.size() - 1 and not current.saved and current.where == key and now - int(current.time) < HISTORY_MERGE_MSEC:
		current.data = data.duplicate(true)
		current.time = now
		current.clock = Time.get_time_string_from_system()
		_paint_history()
		return
	_push_history(label, key, false)


func undo() -> void:
	if history_index > 0:
		_restore_history(history_index - 1)


func redo() -> void:
	if history_index < history.size() - 1:
		_restore_history(history_index + 1)


# 回到任一节点：换回那一步的整张卡，之后的节点保留，可以再重做回去。
func _restore_history(index:int) -> void:
	if index < 0 or index >= history.size():
		return
	if index == history_index:
		_paint_history()
		return
	history_restoring = true
	history_index = index
	data = history[index].data.duplicate(true)
	if not _focus_obj() is Dictionary:
		focus_path = []
		focus_item = ""
	_load_effects()
	_refresh_all()
	history_restoring = false
	dirty = not bool(history[index].saved)
	_paint_history()
	_set_status("回到：" + str(history[index].label))


func _mark_saved() -> void:
	if history.is_empty():
		return
	for node in history:
		node.saved = false
	history[history_index].saved = true
	_paint_history()


func _paint_history() -> void:
	if history_view == null:
		return
	history_view.clear()
	for i in history.size():
		var node:Dictionary = history[i]
		var text := str(i) + ". " + str(node.clock) + "  " + str(node.label) + ("  ✓ 已保存" if node.saved else "")
		history_view.add_item(text)
		history_view.set_item_tooltip(i, str(node.label) + ("\n" + str(node.where) if str(node.where) != "" else ""))
		if i > history_index:
			history_view.set_item_custom_fg_color(i, Color("#9AA0B4"))   # 撤回掉的节点灰显，仍可点回去
	if history_index >= 0:
		history_view.select(history_index)
		history_view.ensure_current_is_visible()
	undo_button.disabled = history_index <= 0
	redo_button.disabled = history_index >= history.size() - 1


# 两份数据第一处不同的位置（键 / 下标路径）。
func _first_diff(a, b, where:Array) -> Array:
	if a is Dictionary and b is Dictionary:
		for key in b:
			if not a.has(key):
				return where + [key]
			var inner := _first_diff(a[key], b[key], where + [key])
			if not inner.is_empty():
				return inner
		for key in a:
			if not b.has(key):
				return where + [key]
		return []
	if a is Array and b is Array:
		for i in mini(a.size(), b.size()):
			var inner := _first_diff(a[i], b[i], where + [i])
			if not inner.is_empty():
				return inner
		return [] if a.size() == b.size() else where
	return [] if Codec.same(a, b) else where


# 把路径说成人话：牌名 / 子牌名 + 字段的显示名（取自 types.json 的声明，没声明就用原键名）。
func _where_shown(where:Array) -> String:
	if where.is_empty():
		return "修改"
	if _key_names.is_empty():
		_collect_key_names(maker.types)
	var owners:Array = []
	var node = data
	var last_key := ""
	for part in where:
		if node is Dictionary and node.has(part):
			node = node[part]
			last_key = str(part)
		elif node is Array and part is int and part < node.size():
			node = node[part]
		else:
			break
		if node is Dictionary:
			var name := _owner_name(node, "")
			if name != "" and (owners.is_empty() or owners[-1] != name):
				owners.append(name)
	var field := str(_key_names.get(last_key, last_key))
	return ("【" + " / ".join(PackedStringArray(owners)) + "】" if not owners.is_empty() else "") + "改了 " + field


func _collect_key_names(node) -> void:
	if node is Dictionary:
		if node.has("key") and node.has("shown") and not _key_names.has(str(node.key)):
			_key_names[str(node.key)] = str(node.shown)
		for key in node:
			_collect_key_names(node[key])
	elif node is Array:
		for item in node:
			_collect_key_names(item)



# =============== 导出设置 ===============

const ZIP_LAYOUT_SHOWN := {"project": "相对项目根目录（data/masters/00002_x/…）", "root": "相对这种卡的根目录（00002_x/…）", "folder": "只放卡文件夹（00002_x/…，不含上层）", "flat": "所有文件直接放在 zip 根"}


func _build_export_window() -> void:
	export_window = AcceptDialog.new()
	export_window.title = "导出设置"
	export_window.ok_button_text = "关闭"
	export_window.min_size = Vector2i(900, 520)
	add_child(export_window)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(880, 0)   # 说明文字自动换行，给定宽度才算得出正确高度
	export_window.add_child(col)
	var intro := _hint("这里的设置只存在你自己电脑上（" + JsonMaker.EXPORT_CFG + "），不改源码和 types.json。留空就用默认值（灰字）。\n命名里可以写 {identity}（内部名）、{serial}（编号）、{folder}（卡文件夹名），以及卡里任何文字字段，如 {category}。")
	intro.custom_minimum_size = Vector2(880, 0)
	col.add_child(intro)
	var top := HBoxContainer.new()
	col.add_child(top)
	top.add_child(_label("卡牌种类", 14, INK))
	export_kind_menu = OptionButton.new()
	for item in maker.export_kinds():
		export_kind_menu.add_item(item.shown)
		export_kind_menu.set_item_metadata(export_kind_menu.item_count - 1, item.id)
	export_kind_menu.item_selected.connect(func(i): _paint_export_form(str(export_kind_menu.get_item_metadata(i))))
	top.add_child(export_kind_menu)
	var reset := Button.new()
	reset.text = "这种恢复默认"
	reset.pressed.connect(func():
		maker.reset_export(export_kind)
		_export_changed()
		_paint_export_form(export_kind))
	top.add_child(reset)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 430)
	col.add_child(scroll)
	export_form = VBoxContainer.new()
	export_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(export_form)
	export_preview = _label("", 13, Color("#4C3D8F"))
	export_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	export_preview.custom_minimum_size = Vector2(880, 0)
	col.add_child(export_preview)
	var zip_row := HBoxContainer.new()
	col.add_child(zip_row)
	zip_row.add_child(_label("zip 默认放在", 14, INK))
	var zip_dir := _export_line(str(maker.global_export("zip_dir", "")), "exports", func(t): maker.set_export("_global", "zip_dir", t if t != "" else null))
	zip_row.add_child(zip_dir)
	zip_row.add_child(_dir_button(zip_dir))


func open_export_settings() -> void:
	var want := card_kind if card_kind != "" else kind_id
	var index := 0
	for i in export_kind_menu.item_count:
		if str(export_kind_menu.get_item_metadata(i)) == want:
			index = i
	export_kind_menu.select(index)
	_paint_export_form(str(export_kind_menu.get_item_metadata(index)))
	export_window.size = Vector2i(920, 760)
	export_window.popup_centered(Vector2i(920, 760))


func _paint_export_form(item_id:String) -> void:
	export_kind = item_id
	_clear(export_form)
	var fields := maker.export_fields(item_id)
	var base := maker.item_spec(item_id)
	var own:Dictionary = maker.export_overrides.get(item_id, {})
	if fields.root != "":
		var row := _export_row("保存根目录")
		var root_edit := _export_line(str(own.get("root", "")), str(base.get("root", "")), func(t): maker.set_export(item_id, "root", t if t != "" else null))
		row.add_child(root_edit)
		row.add_child(_dir_button(root_edit))
		if fields.file == "folder":
			_export_row("文件夹命名").add_child(_export_line(str(own.get("folder_name", "")), str(base.get("folder_name", "{identity}")), func(t): maker.set_export(item_id, "folder_name", t if t != "" else null)))
			_export_row("编号位数").add_child(_export_line(str(own.get("serial_digits", "")), str(int(base.get("serial_digits", 5))), func(t): maker.set_export(item_id, "serial_digits", int(t) if t.is_valid_int() else null)))
			var defaults := JSON.stringify(own.get("pattern_defaults")) if own.has("pattern_defaults") else ""
			var line := _export_line(defaults, JSON.stringify(base.get("pattern_defaults", {})), func(t):
				var parsed = JSON.parse_string(t) if t != "" else null
				maker.set_export(item_id, "pattern_defaults", parsed if parsed is Dictionary else null))
			line.tooltip_text = "命名里的字段卡上没填时用的值，按 JSON 写，如 {\"pack\": \"origin\"}"
			_export_row("缺值时用").add_child(line)
		var zip_menu := OptionButton.new()
		zip_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		zip_menu.fit_to_longest_item = true
		var current := str(own.get("zip_layout", base.get("zip_layout", "project")))
		for layout in JsonMaker.ZIP_LAYOUTS:
			zip_menu.add_item(str(ZIP_LAYOUT_SHOWN.get(layout, layout)))
			zip_menu.set_item_metadata(zip_menu.item_count - 1, layout)
			if layout == current:
				zip_menu.select(zip_menu.item_count - 1)
		zip_menu.item_selected.connect(func(i):
			maker.set_export(item_id, "zip_layout", zip_menu.get_item_metadata(i))
			_export_changed())
		_export_row("zip 里的目录").add_child(zip_menu)
		_export_row("子牌图片前缀").add_child(_export_line(str(own.get("sub_image_prefix", "")), str(base.get("sub_image_prefix", "")), func(t): maker.set_export(item_id, "sub_image_prefix", t if t != "" else null)))
	if not fields.images.is_empty():
		export_form.add_child(_label("图片命名（不含扩展名）", 15, Color("#4C3D8F")))
		var images:Dictionary = own.get("images", {})
		for img in fields.images:
			var key := str(img.key)
			_export_row(str(img.shown)).add_child(_export_line(str(images.get(key, "")), str(img.default), func(t): maker.set_export_image(item_id, key, t if t != "" else null)))
	_paint_export_preview()


func _export_row(title:String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name := _label(title, 14, INK)
	name.custom_minimum_size = Vector2(130, 0)
	row.add_child(name)
	export_form.add_child(row)
	return row


# 输入框：空着显示默认值（灰字），回车或离开时写进设置并存盘。
func _export_line(value:String, fallback:String, apply:Callable) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = value
	edit.placeholder_text = fallback
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var commit := func(t:String):
		apply.call(t.strip_edges())
		_export_changed()
	edit.text_submitted.connect(commit)
	edit.focus_exited.connect(func(): commit.call(edit.text))
	return edit


func _dir_button(target:LineEdit) -> Button:
	var b := Button.new()
	b.text = "选目录"
	b.pressed.connect(func():
		dir_target = target
		var cur := target.text if target.text != "" else target.placeholder_text
		dir_dialog.current_dir = ProjectSettings.globalize_path(maker._res(cur))
		dir_dialog.popup_centered_ratio(0.6))
	return b


func _export_changed() -> void:
	if not maker.save_export_settings():
		_set_status("导出设置存不进去")
	_paint_export_preview()
	if kind_button != null and kind_button.selected >= 0:
		_select_kind(kind_button.selected)


# 按当前这张卡（同种类时）或一张示例卡，显示会存到哪、图片叫什么。
func _paint_export_preview() -> void:
	if export_preview == null:
		return
	var sample:Dictionary = data if data is Dictionary and card_kind == export_kind else {}
	var spec := maker.export_spec(export_kind)
	if sample.is_empty() and str(spec.get("identity", "")) != "":
		sample = {str(spec.identity): "example"}
	var target := maker.suggest_path(export_kind, sample)
	if target == "":
		export_preview.text = "预览：" + ("子牌不单独存文件，图片名跟随本体的文件夹" if str(spec.get("root", "")) == "" else "填好内部名等命名用到的字段后才能算出位置")
		return
	var lines := ["预览：" + target]
	var folder := target.get_base_dir().get_file()
	for field in spec.get("fields", []):
		if str(field.get("control", "")) == "image":
			var base := maker.fill_pattern(str(field.get("file_name", "{identity}")), {"folder": folder, "identity": str(sample.get(spec.get("identity", ""), ""))})
			lines.append("　" + str(field.get("shown", field.key)) + " → " + (base if base != "" else "（原名）") + ".png")
	export_preview.text = "\n".join(PackedStringArray(lines))
