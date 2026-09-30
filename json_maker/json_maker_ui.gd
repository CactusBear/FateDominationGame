extends Control

# Fate 卡牌效果积木编辑器（json_maker）。
# 左：积木区（按颜色分类，拖出来用）。中：卡牌信息 + 每条效果一段积木脚本。右：选中积木的说明 / 待修问题 / JSON 原文。
# 编辑的是积木模型，保存时由 JsonCodec 编回加载器认识的 JSON；读写、校验、选图复用 JsonMaker。

const Codec = preload("res://json_maker/json_codec.gd")
const Shape = preload("res://json_maker/json_style.gd")

const VAR_COLOR := Color("#77522C")
const LOOP_ITEM_COLOR := Color("#77602C")

## 配色与主菜单（main_menu.gd）、对局界面（battle_board_v2.gd）同名同值：墨蓝底、金线、米色字
const C_INK := Color("0e131d")
const C_INK2 := Color("161d2b")
const C_INK3 := Color("222b3d")
const C_GOLD := Color("c9a45c")
const C_GOLD2 := Color("e8cd86")
const C_GOLD3 := Color("8a6a32")
const C_TEXT := Color("efe6d2")
const C_DIM := Color("a79e8b")
const C_DIM2 := Color("6d665a")
const C_BUTTON_INK := Color("1a1206")
const C_BLOOD2 := Color("ff4d57")
const C_OK := Color("#2E9E4F")                 # 检查通过 / 教程已完成
const C_WARN := Color("#FFB86B")               # 需要注意但不阻止保存
const HINT := C_DIM                            # 说明文字
## 空位（积木上可填的格子）底色：深底金边，里面的按钮、输入框沿用同一套深色主题
const SLOT_FILL := Color(C_INK, 0.95)
const SLOT_FILL_SOFT := Color(C_INK, 0.75)

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
var tutorial_practice := false
var tutorial_previous:Dictionary = {}
var deck_catalog:Array = []
@onready var help_title:Label = %HelpTitle
@onready var help_body:RichTextLabel = %HelpBody
@onready var issue_list:VBoxContainer = %IssueList
@onready var json_view:TextEdit = %JsonView
@onready var status:Label = %Status
@onready var kind_button:OptionButton = %KindButton
@onready var file_list:ItemList = %FileList
@onready var palette_box:VBoxContainer = %PaletteBox
@onready var palette_scroll:ScrollContainer = %PaletteScroll
@onready var category_bar:VBoxContainer = %CategoryBar
@onready var search:LineEdit = %Search
@onready var action_tab:Button = %ActionTab
@onready var value_tab:Button = %ValueTab
@onready var palette_hint:Label = %PaletteHint
var palette_section := "action"
@onready var card_box:VBoxContainer = %CardBox
@onready var script_box:VBoxContainer = %ScriptBox
@onready var script_scroll:ScrollContainer = %ScriptScroll
@onready var save_dialog:FileDialog = %SaveDialog
@onready var zip_dialog:FileDialog = %ZipDialog
@onready var export_window:AcceptDialog = %ExportWindow
@onready var export_kind_menu:OptionButton = %ExportKindMenu
@onready var export_form:VBoxContainer = %ExportForm
@onready var export_preview:Label = %ExportPreview
var export_kind := ""
@onready var dir_dialog:FileDialog = %DirDialog
var dir_target:LineEdit
const PENDING_IMAGES := "res://json_maker/pending_images"   # 选图先放这里，保存时按命名规则复制进卡的文件夹
const IMAGE_TILE_SIZE := 176                               # 选图面板里一个图标格子的边长
const IMAGE_PICKER_COLUMNS := 4                            # 选图面板一行放几个图标
const IMAGE_PICKER_SIZE := Vector2i(900, 760)              # 选图面板的固定尺寸（内容不许把它撑大）
var image_target := {}
var image_picker:AcceptDialog = null   # 选图面板；打开时重建，关掉就丢
var image_dir := ""                    # 选图面板现在在哪个文件夹
var drag_source := {}
@onready var context_menu:PopupMenu = %ContextMenu
var context_target := {}
var clipboard = null
var _render_effect = null   # 正在画的那条效果：效果数字存在它的 effect_numbers 里
var focus_path:Array = []     # 正在编辑的子牌在 data 里的路径；空表示本体
var focus_item := ""          # 子牌的类型（types.json 的 item 名）
@onready var sub_list:ItemList = %SubList
@onready var tutorial_panel:PanelContainer = %TutorialPanel
@onready var tutorial_title:Label = %TutorialTitle
@onready var tutorial_step_label:Label = %TutorialStep
@onready var tutorial_image:TextureRect = %TutorialImage
@onready var tutorial_body:RichTextLabel = %TutorialBody
@onready var tutorial_checks:VBoxContainer = %TutorialChecks
@onready var tutorial_prev_button:Button = %TutorialPrev
@onready var tutorial_next_button:Button = %TutorialNext
@onready var tutorial_menu:PopupMenu = %TutorialMenu
var tutorials:Array = []        # list_tutorials 的结果，入口菜单按下标取
var tutorial := {}              # 正在跟的那套教程；空表示没开
var tutorial_index := 0         # 当前第几步
var tutorial_drag := false
var tutorial_blink:Tween
var tutorial_blink_targets:Array = []
var sub_entries:Array = []
var catalog_sig := ""
@onready var splits:Array = get_tree().get_nodes_in_group("layout_split").filter(func(n): return is_ancestor_of(n))   # 场景里标在 layout_split 组的分隔容器
@onready var drop_marker:ColorRect = %DropMarker      # 拖动时显示「会插在这里」的横线
var hover_target:Control = null
@onready var tp_popup:PopupPanel = %TimePointPopup        # 选时机：搜索 + 分组，所有选时机的地方共用这一个
@onready var tp_search:LineEdit = %TimePointSearch
@onready var tp_tree:Tree = %TimePointTree
var tp_pick := Callable()
var tp_typed := Callable()     # 打的字交给它（空着就交给 tp_pick）：调用方可以按空位类型转换
var tp_groups:Array = []       # 面板当前列出的分组 [{shown, items:[{id, shown, value?}]}]；value 缺省时用 id
var tp_allow_text := false     # 允许把打的字直接当值
var tp_more := Callable()      # 兜底：点「显示其他所有字段」时取更多分组；空着就不显示这一行
var tp_extra:Array = []        # 已经取到的兜底分组；取到就留着，方便反复折叠展开
var tp_more_open := false      # 列表末尾那一项现在是展开还是收起
@onready var gen_window:AcceptDialog = %GenerateWindow     # 生成牌向导
var gen_view:Dictionary = {}
@onready var gen_type:OptionButton = %GenType
@onready var gen_search:LineEdit = %GenSearch
@onready var gen_list:ItemList = %GenerateList
@onready var gen_name:LineEdit = %GenerateName
@onready var gen_zone:OptionButton = %GenZone
@onready var gen_count:SpinBox = %GenCount
@onready var gen_mode:OptionButton = %GenerateMode       # 现成的牌 / 自定义新牌
@onready var gen_library:VBoxContainer = %GenLibrary   # 现成的牌才用的那几行
@onready var gen_custom:VBoxContainer = %GenCustom    # 自定义新牌才用的那几行
@onready var gen_custom_type:OptionButton = %GenerateCustomType
@onready var gen_register:CheckBox = %GenerateRegister
const LAYOUT_PATH := "user://json_maker_layout.cfg"
# 修改记录：每个节点是整张卡的快照，撤回 / 重做 / 回到任一节点都是换回快照
const HISTORY_LIMIT := 200
const HISTORY_MERGE_MSEC := 1000   # 同一处在这段时间内连续改动（打字）合并成一个节点
var history:Array = []
var history_index := -1
var history_restoring := false
@onready var history_view:ItemList = %HistoryList
@onready var undo_button:Button = %UndoButton
@onready var redo_button:Button = %RedoButton
var _key_names := {}


func _ready() -> void:
	maker.load_catalog()
	maker.load_export_settings()
	codec = Codec.new(maker.container_params(), maker.option_params())
	catalog_sig = maker.catalog_signature()
	_setup_scene()
	_load_layout()
	_select_kind(0)
	_show_welcome()
	_use_drag_cursor(true)


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
	codec.option_params = maker.option_params()
	catalog_sig = maker.catalog_signature()
	_rebuild_categories()
	_fill_palette()
	if data != null:
		_load_effects()
		_refresh_all()
	_set_status("已重新扫描积木：" + str(maker.operations.size()) + " 块" + ("（多了 " + str(maker.operations.size() - before) + " 块）" if maker.operations.size() > before else ""))


# =============== 界面骨架 ===============
# 布局、样式、固定文字和信号连接都在 json_maker.tscn（主题在 json_theme.tres）里改；
# 这里只接场景里做不了的：拖放转发、分隔条比例记忆、以及按数据填的下拉选项。

func _setup_scene() -> void:
	# 弹窗关掉就丢开上一个空位的回调，免得它们捕获的格子和编辑器一直被引用（重开时会重新给）
	tp_popup.popup_hide.connect(func():
		tp_pick = Callable()
		tp_typed = Callable()
		tp_more = Callable()
		tp_extra = []
		tp_more_open = false)
	# 整片背景接住拖放：放在空白处就是取消，不显示禁止光标
	set_drag_forwarding(Callable(), func(_at, d):
		_clear_drop_hint()
		return d is Dictionary and (d.has("new") or d.has("node")), func(_at, _d): pass)
	# 把积木拖回积木区 = 删除
	%PalettePanel.set_drag_forwarding(Callable(), _palette_can_drop, _palette_drop)
	for split in splits:
		split.dragged.connect(func(_o): _remember_ratio(split))
		split.resized.connect(func(): _on_split_resized(split))
	for item in maker.file_kinds():
		kind_button.add_item(item.shown)
		kind_button.set_item_metadata(kind_button.item_count - 1, item.id)
	for item in maker.export_kinds():
		export_kind_menu.add_item(item.shown)
		export_kind_menu.set_item_metadata(export_kind_menu.item_count - 1, item.id)
	%ZipDirEdit.text = str(maker.global_export("zip_dir", ""))
	_fill_generate_menus()
	_set_palette_section(palette_section)


func _on_search_changed(_text:String) -> void:
	_fill_palette()


func _on_action_tab_pressed() -> void:
	_set_palette_section("action")


func _on_value_tab_pressed() -> void:
	_set_palette_section("value")


func _set_palette_section(section_id:String) -> void:
	palette_section = section_id
	palette_hint.text = "执行：放进效果顺序，完成一项操作。" if section_id == "action" else "取值：算出一个值，供其他积木引用。"
	for tab in [action_tab, value_tab]:
		var selected:bool = (tab == action_tab) == (section_id == "action")
		var bg := C_GOLD if selected else C_INK3
		var fg := C_BUTTON_INK if selected else C_TEXT
		tab.add_theme_stylebox_override("normal", _flat(bg, 3, 8, Color.TRANSPARENT if selected else Color(C_GOLD3, 0.85)))
		tab.add_theme_stylebox_override("hover", _flat(C_GOLD2 if selected else Color(C_GOLD, 0.22), 3, 8, Color.TRANSPARENT if selected else C_GOLD2))
		tab.add_theme_stylebox_override("pressed", _flat(bg, 3, 8))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			tab.add_theme_color_override(state, fg)
	_rebuild_categories()
	_fill_palette()
	palette_scroll.scroll_vertical = 0


func _on_sub_selected(index:int) -> void:
	call_deferred("_focus_entry", index)


func _on_dir_selected(dir:String) -> void:
	if dir_target != null:
		dir_target.text = LoadHelper.relative_path(dir)
		dir_target.text_submitted.emit(dir_target.text)


func _notification(what:int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_drop_hint()


func _rebuild_categories() -> void:
	_clear(category_bar)
	for section in _palette_sections(""):
		if str(section.id) != palette_section:
			continue
		for entry in section.categories:
			var cat:Dictionary = entry.category
			var b := Button.new()
			b.flat = true
			b.custom_minimum_size = Vector2(36, 46)
			b.text = "●\n" + str(cat.shown)
			# 深底上有些分类色（深蓝、紫）太暗：往米色靠一半，既保留分类色又能看清
			b.add_theme_color_override("font_color", Color(str(cat.color)).lightened(0.55))
			b.add_theme_font_size_override("font_size", 11)
			b.tooltip_text = str(section.shown) + " · " + str(cat.shown)
			b.pressed.connect(_jump_category.bind(str(section.id), str(cat.id)))
			category_bar.add_child(b)


# =============== 积木区 ===============

func _fill_palette() -> void:
	_clear(palette_box)
	var needle := search.text.strip_edges().to_lower() if search else ""
	for section in _palette_sections(needle):
		if str(section.id) != palette_section or section.categories.is_empty():
			continue
		for entry in section.categories:
			var cat:Dictionary = entry.category
			var head := _label(str(cat.shown), 15, Color(str(cat.color)).lightened(0.55))
			head.name = _category_anchor(str(section.id), str(cat.id))
			palette_box.add_child(head)
			for item in entry.items:
				var holder := HBoxContainer.new()
				palette_box.add_child(holder)
				holder.add_child(_palette_block(item))


# 积木区里的空位：点开就是这一格能填什么的候选菜单，选中只在积木上显示出来。
# 选择区没有正在编辑的卡可写，所以它只做预览；要真正填值，把积木拖进效果里再点那一格。
func _palette_slot_widget(label:String, type_name:String, kind_key:String) -> Control:
	var button := Button.new()
	button.name = "PaletteSlot"
	button.set_meta("clickable", true)
	button.text = label + " ▾"
	button.tooltip_text = "点开看这一格能填什么；要真正填，把积木拖到效果里再选。"
	button.custom_minimum_size = Vector2(96, 32)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_stylebox_override("normal", Shape.new("slot", SLOT_FILL))
	button.add_theme_stylebox_override("hover", Shape.new("slot", Color(C_GOLD, 0.35)))
	button.add_theme_stylebox_override("pressed", Shape.new("slot", Color(C_GOLD, 0.5)))
	button.add_theme_color_override("font_color", C_TEXT)
	button.pressed.connect(_open_palette_slot_menu.bind(button, label, type_name, kind_key))
	return button


# 选择区的空位菜单：候选和效果里那一格完全同一套（含列表末尾的「显示其他所有字段」），只是选中不写卡。
func _open_palette_slot_menu(anchor:Button, label:String, type_name:String, kind_key:String) -> void:
	var kind := _slot_kind(kind_key)
	var groups:Array = _slot_groups(type_name, kind, kind_key, null)
	var on_pick := func(v):
		anchor.text = label + "：" + _short(_palette_preview_text(v, groups), 20) + " ▾"
		_set_status("选择区只是看候选；要真正填这一格，把积木拖进效果里再选。")
	_open_search_popup(anchor, groups, on_pick, true, on_pick, func(): return _slot_more_groups(type_name, kind_key, null))


# 选择区里选中之后显示什么字：特殊值给中文名，其余按候选的中文名或原值显示。
func _palette_preview_text(value, groups:Array) -> String:
	if value is Dictionary and value.has("_pick"):
		match str(value._pick):
			"op":
				return _say_text(str(value.func))
			"clear":
				return "清空这一格"
			"number":
				return "效果数字"
			"loop":
				return "↻ 当前这一项"
	return _picked_text(value, groups, false, "")


# 同一小分类可同时有取值和执行积木；沿用积木自身的形状判断，不按名称猜。
func _palette_sections(needle:String) -> Array:
	var sections:Array = [
		{"id": "value", "shown": "取值积木", "categories": []},
		{"id": "action", "shown": "执行积木", "categories": []},
	]
	for cat in maker.categories():
		var groups := [[], []]
		for item in _palette_items(str(cat.id), needle):
			var is_value := str(item.kind) in ["var", "loop_item", "option_qty"]
			if str(item.kind) == "op":
				is_value = _shape_of(_node_from_palette(item), {"palette": true}) != "stack"
			groups[0 if is_value else 1].append(item)
		for index in groups.size():
			if not groups[index].is_empty():
				sections[index].categories.append({"category": cat, "items": groups[index]})
	return sections


func _category_anchor(section_id:String, cat_id:String) -> String:
	return "Cat_" + section_id + "_" + cat_id.replace("/", "_")


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
			return "结果 变量 前面算出的结果 存下"
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
	# 空位要留着能点（点开候选菜单）；在这些空位上按住拖动仍然拖出整块积木
	for slot_button in view.find_children("PaletteSlot", "Button", true, false):
		(slot_button as Button).set_drag_forwarding(func(_p): return _begin_drag({"new": item}, view), Callable(), Callable())
	return view


func _palette_help(item:Dictionary) -> String:
	if item.kind == "op":
		return maker.help_of(item.func)
	return ""


func _jump_category(section_id:String, cat_id:String) -> void:
	var node := palette_box.get_node_or_null(_category_anchor(section_id, cat_id))
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
		"var_ref":
			return {"t": "slot_only", "slot": (item.slot as Dictionary).duplicate()}
		"array_item":
			return {"t": "slot_only", "slot": _array_item_slot(int(item.variable), int(item.index))}
	return _new_op(str(item.func))

# 复用现有操作按索引读数组；嵌进目标参数时仍走普通空位的编解码流程。
func _array_item_slot(variable:int, index:int) -> Dictionary:
	var op := _new_op("get_card_by_index_fr_arr")
	var spec := maker.operation_of("get_card_by_index_fr_arr")
	op.params[_param_index(spec, "card_index")] = {"s": "lit", "v": index}
	op.params[_param_index(spec, "cards")] = {"s": "var", "n": variable}
	return {"s": "block", "b": op}


func _new_op(func_name:String) -> Dictionary:
	var op := maker.operation_of(func_name)
	var params:Array = []
	var containers:Array = codec.container_params.get(func_name, [])
	for i in op.get("params", []).size():
		var p:Dictionary = op.params[i]
		if containers.has(i):
			params.append({"s": "script", "body": []})
		elif codec.option_params.get(func_name, []).has(i):
			params.append({"s": "options", "items": [{"opt": {"shown_option_name": "选项1"}, "keys": ["shown_option_name", "funcs"], "body": []}]})
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
	copy.erase("tag_var")
	return copy


func _make_passive(node:Node) -> void:
	for child in node.get_children():
		if child is Control:
			# 挂了 clickable 的（选择区里能点开候选的空位）保留鼠标响应
			if child.has_meta("clickable"):
				continue
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
	if tutorial_practice and bool(tutorial_previous.get("dirty", false)):
		restore_tutorial_previous()
		_set_status("已先恢复未保存的原稿，避免丢失。若仍要打开文件，请再选一次。")
		return
	var loaded = maker.read_json(target)
	if loaded == null:
		_set_status("这份文件读不了：" + target)
		return
	_leave_practice()
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
	if tutorial_practice:
		# 练习里的「新建一张」由使用者自己点：不结束练习、也不动暂存的原稿，建的还是练习副本
		_build_card(kind_id, "练习副本里的新卡")
		_set_status("练习副本里的新" + str(maker.kind_spec(kind_id).get("shown", "卡")) + "：不会写入 JSON，也不能保存或打包。")
		return
	_leave_practice()
	_build_card(kind_id, "新建一张")
	_set_status("新建了一张，还没保存")


# 按种类铺一张空白卡。练习副本与普通新建都走这里，练习与否由调用方处理。
func _build_card(target_kind:String, label:String) -> void:
	card_kind = target_kind
	path = ""
	style = {}
	original = null
	data = maker.blank(target_kind)
	focus_path = []
	focus_item = ""
	history.clear()
	_load_effects()
	_refresh_all()
	dirty = true
	_reset_history(label, false)


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
	for hit in maker.custom_cards(data):
		var at = _path_to(data, hit.card, [])
		if at != null:
			var kind_shown := str(maker.kind_spec(str(hit.kind)).get("shown", "牌"))
			out.append({"path": at, "item": str(hit.kind), "shown": "　自定义" + kind_shown + " · " + _owner_name(hit.card, "还没起名"), "depth": 1})
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
		lists.append_array(ov.reqs)
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
				if params[i] is Dictionary and str(params[i].get("s", "")) == "omit" and params[i].has("number_default") and not params[i].get("loop", false):
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
	_refresh_tutorial()
	if json_view.is_visible_in_tree() and json_view.size.y > 24:
		json_view.text = maker.export_text(data, style)
	_paint_issues(_collect_issues())


# =============== 卡面信息 ===============

func _paint_card() -> void:
	_clear(card_box)
	if tutorial_practice:
		card_box.add_child(_hint("教程练习副本 · 只在内存中，不能保存 JSON 或打包。"))
		var restore := Button.new()
		restore.text = "恢复教程前原稿（包括未保存修改）"
		restore.pressed.connect(restore_tutorial_previous)
		card_box.add_child(restore)
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
		card_box.add_child(_label(str(spec.get("shown", "子牌")) + "：" + _owner_name(obj, ""), 15, C_GOLD))
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
		_field_row(parent, obj, field, str(spec.get("identity", "")) == str(field.key))
	if inner.is_empty():
		return
	var fold := _fold_box(parent, "程序用的名字", false)
	var guide:Array = maker.types.get("naming_guide", [])
	if not guide.is_empty():
		fold.add_child(_hint(str(guide[0]) + " 完整的命名规范见右边「怎么用」。"))
	for field in inner:
		_field_row(fold, obj, field, str(spec.get("identity", "")) == str(field.key))


func _field_row(parent:Node, obj:Dictionary, field:Dictionary, is_identity := false) -> void:
	var key := str(field.key)
	var known := ["text", "int", "float", "bool", "number", "choice", "search_choice", "image", "attributes", "lines", "time_points", "cost"]
	if not known.has(str(field.get("control", "text"))) and not obj.has(key):
		return
	var row := HBoxContainer.new()
	parent.add_child(row)
	var name_text := str(field.get("shown", key)) + (" *" if bool(field.get("required", false)) else "")
	var name := _label(name_text, 14, C_TEXT)
	name.custom_minimum_size = Vector2(118, 0)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(name)
	var help := str(field.get("help", ""))
	if help != "":
		name.tooltip_text = help
		name.mouse_filter = Control.MOUSE_FILTER_STOP
		name.text += " ⓘ"
	var control := str(field.get("control", "text"))
	if control == "search_choice":
		name.custom_minimum_size = Vector2(76, 0)
		row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var present:bool = obj.has(key)
	match control:
		"text":
			var edit := LineEdit.new()
			edit.text = str(obj.get(key, ""))
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			edit.text_changed.connect(func(v): obj[key] = v; _changed())
			row.add_child(edit)
			if is_identity:
				var warning := _hint("")
				warning.name = "IdentityWarning"
				warning.add_theme_color_override("font_color", C_WARN)
				parent.add_child(warning)
				var refresh := func(_text:String):
					var at = _path_to(data, obj, [])
					var found:Array = maker.identity_conflicts(key, str(obj.get(key, "")), path, at if at is Array else [])
					var sources:PackedStringArray = []
					for hit in found:
						sources.append(str(hit.file) + " → " + JSON.stringify(hit.path))
					warning.text = "内部名与 data 中已有对象重复：\n" + "\n".join(sources)
					warning.visible = not found.is_empty()
				edit.text_changed.connect(refresh)
				refresh.call(edit.text)
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
		"choice", "search_choice":
			var choices:Array = field.get("choices", [])
			if control == "search_choice":
				var edit := LineEdit.new()
				edit.name = "FieldChoiceEdit"
				edit.custom_minimum_size = Vector2(72, 0)
				edit.text = str(obj.get(key, ""))
				edit.size_flags_horizontal = Control.SIZE_FILL
				edit.text_changed.connect(func(v): obj[key] = v; _changed())
				row.add_child(edit)
				var choice_kind := str(field.get("choice_kind", ""))
				var choose := _search_button("▾", func(): return maker.kind_choice_groups(choice_kind),
					func(v): edit.text = str(v); obj[key] = str(v); _changed(), true, "选择常用值，也可以直接输入")
				choose.name = "FieldChoiceButton"
				choose.custom_minimum_size = Vector2(36, 0)
				row.add_child(choose)
			else:
				var menu := OptionButton.new()
				for choice in choices:
					menu.add_item(_choice_shown(str(choice)))
				menu.selected = maxi(0, choices.find(obj.get(key, "")))
				menu.item_selected.connect(func(i): obj[key] = choices[i]; _changed())
				row.add_child(menu)
		"image":
			var shown := str(obj.get(key, ""))
			var preview := _card_thumbnail(shown, path.get_base_dir())
			if preview.texture != null:
				row.add_child(preview)
			var lab := _label(shown if shown != "" else "还没选图", 13, C_TEXT if shown != "" else HINT)
			lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lab.clip_text = true
			row.add_child(lab)
			var pick := Button.new()
			pick.text = "选图"
			pick.pressed.connect(_pick_image.bind(obj, key, str(field.get("zoom", ""))))
			row.add_child(pick)
			if shown != "" and not bool(field.get("required", false)):
				var clear := Button.new()
				clear.text = "清除"
				clear.pressed.connect(func():
					obj.erase(key)
					var zoom_key := str(field.get("zoom", ""))
					if zoom_key != "":
						obj.erase(zoom_key)
					_changed()
					call_deferred("_paint_card"))
				row.add_child(clear)
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

func _card_thumbnail(image:String, folder:String) -> TextureRect:
	var preview := TextureRect.new()
	preview.name = "CardThumbnail"
	preview.custom_minimum_size = Vector2(48, 64)
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if image != "":
		var source := image if image.begins_with("res://") or image.is_absolute_path() else folder.path_join(image)
		if LoadHelper.texture_exists(source):
			preview.texture = LoadHelper.load_texture(source)
		preview.tooltip_text = source
	return preview


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
	flow.add_child(_time_point_button("＋ 加一个时机", func(point_id):
		list.append(point_id)
		obj[key] = list
		_changed()
		call_deferred("_paint_card")))


# 选时机的按钮：点开共用的搜索面板，选中后调用 on_pick(时机 id)。
func _time_point_button(text:String, on_pick:Callable) -> Button:
	return _search_button(text, _time_point_groups, on_pick, true, "点开后可以搜索，时机按分组列出；找不到就直接打字回车。")


func _time_point_groups() -> Array:
	var out:Array = []
	for group in maker.time_point_groups():
		out.append({"shown": group.shown, "items": group.points})
	return out


# 通用的搜索下拉按钮：groups_fn 返回 [{shown, items:[{id, shown}]}]，点开时才取，候选总是最新的。
# allow_text：允许把搜索框里打的字直接当值（候选里没有时的兜底）。more：给了就在列表里显示「显示其他所有字段」。
func _search_button(text:String, groups_fn:Callable, on_pick:Callable, allow_text:bool, tip:String, more := Callable()) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.pressed.connect(func(): _open_search_popup(button, groups_fn.call(), on_pick, allow_text, Callable(), more))
	return button


func _on_tp_search_changed(_text:String) -> void:
	_fill_time_point_tree()


func _on_tp_search_submitted(_text:String) -> void:
	_pick_first_time_point()


func _on_tp_item_selected() -> void:
	var item := tp_tree.get_selected()
	if item != null and item.has_meta("more"):
		# Tree 正在处理鼠标选中时禁止 clear/create_item；等本次输入结束再重建。
		call_deferred("_toggle_more_groups")
	elif item != null and item.is_selectable(0):
		_pick_entry(item.get_metadata(0), item.has_meta("typed"))


# 列表末尾那一项：点一下把全部其他字段列在它下面，再点一下收起。
func _toggle_more_groups() -> void:
	# 点击后若弹窗已关闭或更早的一次展开已完成，不重建已切换的列表。
	if not tp_more.is_valid():
		return
	if not tp_more_open and tp_extra.is_empty():
		tp_extra = _merge_more_groups(tp_more.call())
		if tp_extra.is_empty():
			_set_status("没有其他字段了")
			return
	tp_more_open = not tp_more_open
	_fill_time_point_tree()
	if tp_more_open:
		_scroll_to_more()


# 兜底分组：和已经列出的值去重后统一加「其他 · 」前缀；一个都没剩就不返回这组。
func _merge_more_groups(extra:Array) -> Array:
	var out:Array = []
	for group in extra:
		var items:Array = []
		for it in group.items:
			var value = it.get("value", str(it.id))
			if not _find_item(tp_groups, value).is_empty() or not _find_item(out, value).is_empty():
				continue
			items.append(it)
		if not items.is_empty():
			out.append({"shown": "其他 · " + str(group.shown), "items": items})
	return out


# 展开后滚到末尾那一项的第一组，不用自己往下找。
func _scroll_to_more() -> void:
	var head := tp_tree.get_root().get_first_child() if tp_tree.get_root() else null
	while head != null:
		if head.has_meta("more"):
			var first := head.get_first_child()
			if first != null:
				tp_tree.scroll_to_item(first, true)
			return
		head = head.get_next()


func _open_time_point_popup(anchor:Control, on_pick:Callable) -> void:
	_open_search_popup(anchor, _time_point_groups(), on_pick, false)


# on_typed：打的字交给谁；不给就和选中的候选一样交给 on_pick。
# more：兜底取「其他所有字段」的分组；给了才在列表末尾显示那一行。
func _open_search_popup(anchor:Control, groups:Array, on_pick:Callable, allow_text:bool, on_typed := Callable(), more := Callable()) -> void:
	tp_pick = on_pick
	tp_typed = on_typed
	tp_groups = groups.duplicate()
	tp_allow_text = allow_text
	tp_more = more
	tp_extra = []
	tp_more_open = false
	tp_search.text = ""
	tp_search.placeholder_text = "搜索，中文英文都行" + ("；找不到就直接打字回车" if allow_text else "")
	_fill_time_point_tree()
	var r := anchor.get_global_rect()
	tp_popup.popup(Rect2i(Vector2i(r.position + Vector2(0, r.size.y)), Vector2i(380, 460)))
	tp_search.grab_focus()


# 按分组填；有搜索词时只留匹配的项并展开分组，分组名匹配时整组保留。
# 允许打字兜底时，第一行是「用输入的文字」。
func _fill_time_point_tree() -> void:
	tp_tree.clear()
	var root := tp_tree.create_item()
	var raw := tp_search.text.strip_edges()
	var needle := raw.to_lower()
	if tp_allow_text and raw != "":
		var typed := tp_tree.create_item(root)
		typed.set_text(0, "用输入的文字：" + raw)
		typed.set_metadata(0, raw)
		typed.set_meta("typed", true)
		typed.set_custom_color(0, C_GOLD2)
	var fold_idle:bool = needle == "" and tp_groups.size() > 1
	for group in tp_groups:
		_add_candidate_group(root, group, needle, fold_idle and not bool(group.get("open", false)))
	# 兜底入口放在列表最后：点它就在它下面展开全部其他字段，再点一下收起
	if tp_more.is_valid():
		var more := tp_tree.create_item(root)
		more.set_meta("more", true)
		more.set_custom_color(0, C_GOLD2)
		more.set_text(0, "▾ 收起其他所有字段" if tp_more_open else ("▸ 在其他所有字段里搜索" if needle != "" else "▸ 显示其他所有字段"))
		more.set_tooltip_text(0, "点开列出所有已知字段兜底；再点一下收起")
		if tp_more_open:
			for group in tp_extra:
				_add_candidate_group(more, group, needle, false)


# 往树上挂一组候选：组头不可选，折叠与否由调用方决定；整组没有命中的项就不显示。
func _add_candidate_group(parent_item:TreeItem, group:Dictionary, needle:String, folded:bool) -> void:
	var group_hit := needle != "" and str(group.shown).to_lower().find(needle) != -1
	var points:Array = group.items.filter(func(p): return needle == "" or group_hit or str(p.shown).to_lower().find(needle) != -1 or str(p.id).to_lower().find(needle) != -1)
	if points.is_empty():
		return
	var head := tp_tree.create_item(parent_item)
	head.set_text(0, str(group.shown) + "（" + str(points.size()) + "）")
	head.set_selectable(0, false)
	head.set_custom_color(0, C_GOLD)
	head.collapsed = folded
	for p in points:
		var item := tp_tree.create_item(head)
		var shown := str(p.shown)
		item.set_text(0, (shown + "  " + str(p.id)) if shown != "" and shown != str(p.id) and str(p.id) != "" and tp_allow_text else (shown if shown != "" else str(p.id)))
		item.set_tooltip_text(0, str(p.get("tip", p.id)))
		item.set_metadata(0, p.get("value", str(p.id)))


# 回车：选第一个名字本身匹配的项；只有分组名匹配时退回第一个列出的；允许打字时什么都没匹配到就用打的字。
func _pick_first_time_point() -> void:
	var needle := tp_search.text.strip_edges().to_lower()
	var fallback:TreeItem = null
	var head := tp_tree.get_root().get_first_child() if tp_tree.get_root() else null
	while head != null:
		var item := head.get_first_child()
		while item != null:
			if not item.is_selectable(0):
				item = item.get_next()
				continue
			if fallback == null:
				fallback = item
			if item.get_text(0).to_lower().find(needle) != -1 or str(item.get_tooltip_text(0)).to_lower().find(needle) != -1:
				_pick_entry(item.get_metadata(0), false)
				return
			item = item.get_next()
		head = head.get_next()
	if tp_allow_text and needle != "":
		_pick_entry(tp_search.text.strip_edges(), true)
	elif fallback != null:
		_pick_entry(fallback.get_metadata(0), false)


# 选中一项：候选的值原样交出去；打的字交给 tp_typed（没有就交给 tp_pick）。
func _pick_entry(value, typed:bool) -> void:
	# 先取回调再关：关弹窗会清空回调
	var target := tp_typed if typed and tp_typed.is_valid() else tp_pick
	tp_popup.hide()
	if target.is_valid():
		target.call(value)


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
	if item_id == "deck_ref":
		var fold := _fold_box(parent, str(item.shown) + "（" + str(list.size()) + "）", false)
		var counts := {}
		for ref in list:
			counts[str(ref)] = int(counts.get(str(ref), 0)) + 1
		for ref in counts:
			fold.add_child(_label(_deck_name(str(ref)) + " × " + str(counts[ref]) + "  [" + str(ref) + "]", 13, C_TEXT))
		var pick := Button.new()
		pick.text = "打开攻击牌选牌面板"
		pick.pressed.connect(_open_deck_picker.bind(owner, key))
		fold.add_child(pick)
		return
	if item_id == "text":
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
			var name := _label(_owner_name(list[i], "第 " + str(i + 1) + " 个"), 14, C_TEXT)
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

func _deck_entries() -> Array:
	var entries:Array = []
	for file in maker.list_files("attack"):
		var card = maker.read_json(str(file.path))
		if not card is Dictionary:
			continue
		var ref := "special:" + str(card.get("attack_name", ""))
		if ref == "special:":
			continue
		entries.append({"ref": ref, "card": card, "folder": str(file.path).get_base_dir()})
	return entries

func _deck_name(ref:String) -> String:
	for entry in deck_catalog:
		if str(entry.ref) == ref:
			return str(entry.card.get("shown_attack_name", entry.card.get("attack_name", ref)))
	var parts := ref.split(":")
	if parts.size() == 2 and parts[0] != "special" and parts[1].is_valid_int():
		# 旧牌库的属性:威力引用仍按运行时基础牌优先的顺序解析，只用于展示，不改原始字符串。
		for category in ["basic", "other"]:
			for entry in deck_catalog:
				var card:Dictionary = entry.card
				if (str(card.get("category", "")) == "basic") != (category == "basic"):
					continue
				if parts[0] in card.get("attributes", []) and int(card.get("power", {}).get("number", -1)) == int(parts[1]):
					return str(card.get("shown_attack_name", card.get("attack_name", ref)))
	return "未识别的旧引用"

func _open_deck_picker(owner:Dictionary, key:String) -> void:
	deck_catalog = _deck_entries()
	var dialog := AcceptDialog.new()
	dialog.title = "从现有 data 攻击牌选择牌库"
	dialog.ok_button_text = "关闭"
	dialog.size = Vector2i(720, 650)
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	var body := VBoxContainer.new()
	body.name = "DeckPickerBody"
	dialog.add_child(body)
	var search_box := LineEdit.new()
	search_box.placeholder_text = "搜索牌名、属性或内部名"
	body.add_child(search_box)
	var summary := _label("", 13, C_TEXT)
	body.add_child(summary)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(680, 490)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var redraw := _redraw_deck_picker.bind(owner, key, rows, summary, search_box)
	search_box.text_changed.connect(func(_text): redraw.call())
	dialog.confirmed.connect(func(): _paint_card())
	redraw.call()
	dialog.popup_centered(Vector2i(720, 650))

func _redraw_deck_picker(owner:Dictionary, key:String, rows:VBoxContainer, summary:Label, search_box:LineEdit) -> void:
	var redraw := _redraw_deck_picker.bind(owner, key, rows, summary, search_box)
	if is_instance_valid(rows):
		_clear(rows)
		var list:Array = owner.get(key, []) if owner.get(key) is Array else []
		var counts := {}
		for ref in list:
			counts[str(ref)] = int(counts.get(str(ref), 0)) + 1
		summary.text = "已选 " + str(list.size()) + " 张（可重复）。旧引用保持原样；新选牌按内部名精确引用。"
		for ref in counts:
			var selected := HBoxContainer.new()
			rows.add_child(selected)
			var title := _label("已选 · " + _deck_name(str(ref)) + " [" + str(ref) + "] × " + str(counts[ref]), 13, C_TEXT)
			title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			selected.add_child(title)
			var remove := Button.new()
			remove.text = "－ 移除一张"
			remove.pressed.connect(func(): list.erase(ref); owner[key] = list; _changed(); redraw.call_deferred())
			selected.add_child(remove)
		rows.add_child(HSeparator.new())
		for entry in deck_catalog:
			var card:Dictionary = entry.card
			var attrs := ", ".join(PackedStringArray(card.get("attributes", [])))
			var name := str(card.get("shown_attack_name", card.get("attack_name", "")))
			if search_box.text != "" and not (name + " " + attrs + " " + str(card.get("attack_name", ""))).to_lower().contains(search_box.text.to_lower()):
				continue
			var row := HBoxContainer.new()
			rows.add_child(row)
			row.add_child(_card_thumbnail(str(card.get("attack_card_img", "")), str(entry.folder)))
			var cost = card.get("cost", {})
			var power = card.get("power", {})
			var details := _label(name + "  · " + attrs + "  威力 " + str(power.get("number", "?")) + "  魔力 " + str(cost.get("number", "?")), 13, C_TEXT)
			details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(details)
			var add := Button.new()
			add.text = "＋ 添加（" + str(counts.get(entry.ref, 0)) + "）"
			add.pressed.connect(func(): list.append(entry.ref); owner[key] = list; _changed(); redraw.call_deferred())
			row.add_child(add)


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
	script_box.add_child(_label("正在编辑：" + str(spec.get("shown", "卡")) + " " + _owner_name(obj, ""), 15, C_GOLD))
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
	info.add_theme_stylebox_override("panel", _flat(Color(C_GOLD, 0.08), 3, 8, Color(C_GOLD, 0.35)))
	col.add_child(info)
	var info_col := VBoxContainer.new()
	info.add_child(info_col)
	var title_row := HBoxContainer.new()
	info_col.add_child(title_row)
	var owner := str(view.owner).trim_prefix("/")
	var badge := _label(("【" + owner + "】 ") if owner != "" else "", 13, C_GOLD2)
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
		col.add_child(_power_hat(view))
		col.add_child(_stack_view(view.lists.power_query, "power_query"))
	var tools := HBoxContainer.new()
	col.add_child(tools)
	var gen := Button.new()
	gen.name = "GenerateCard"
	gen.text = "生成牌"
	gen.tooltip_text = "按内部名新建一张牌放进某一区。会搭好「新建一张牌」和「把……放进……」这几块，之后可以照常改。"
	gen.pressed.connect(open_generate.bind(view))
	tools.add_child(gen)
	if not (effect.get("options") is Array and not effect.options.is_empty()):
		var to_opt := Button.new()
		to_opt.text = "在下面加选项" if not view.lists.get("funcs", []).is_empty() else "改成让玩家选一项"
		to_opt.tooltip_text = "在已有积木末尾添加空选项，前面的积木保持原位。"
		to_opt.pressed.connect(func():
			if not view.lists.get("funcs", []).is_empty():
				# 效果级 options 会替代 funcs；顺序执行中的选择使用已有的询问积木。
				view.lists.funcs.append(_new_op("ask_player_option"))
			else:
				effect["options"] = [{"shown_option_name": "选项一", "funcs": []}]
				effect["funcs"] = []
				view.lists["funcs"] = []
				view.options = [{"option": effect.options[0], "nodes": [], "reqs": []}]
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
	panel.add_theme_stylebox_override("panel", Shape.new("hat", Color("#77602C")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	row.add_child(_block_label("当"))
	var points:Array = effect.get("time_points", []) if effect.get("time_points") is Array else []
	for i in points.size():
		var chip := Button.new()
		chip.text = maker.time_point_shown(str(points[i])) + " ✕"
		chip.tooltip_text = "点一下去掉这个时机"
		chip.add_theme_stylebox_override("normal", Shape.new("reporter", SLOT_FILL))
		chip.add_theme_color_override("font_color", C_GOLD2)
		chip.pressed.connect(func():
			points.remove_at(i)
			effect["time_points"] = points
			_refresh_scripts())
		row.add_child(chip)
		if i < points.size() - 1:
			row.add_child(_block_label("并且" if bool(effect.get("require_all_time_points", false)) else "或"))
	row.add_child(_time_point_button("＋ 时机", func(point_id):
		points.append(point_id)
		effect["time_points"] = points
		_refresh_scripts()))
	row.add_child(_block_label("时"))
	if points.is_empty():
		row.add_child(_block_label("（还没选时机）"))
	panel.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_help("当……时", "效果从这里开始。选一个或多个时机，时机到了就往下做积木。\n\n• 默认满足任意一个时机就触发；在「发动方式与限制」里勾「时机要全部同时成立」就变成都要满足。\n• 「自己……」是轮到自己时，「他人……」是轮到别人时。"))
	return panel


func _power_hat(view:Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Shape.new("hat", Color("#2C7752")))
	var row := HBoxContainer.new()
	panel.add_child(row)
	row.add_child(_block_label("计算合计威力时"))
	var del := Button.new()
	del.name = "DeletePowerQuery"
	del.text = "✕"
	del.flat = true
	del.tooltip_text = "删掉这一段威力计算，连同里面的积木"
	del.add_theme_color_override("font_color", C_DIM)
	del.pressed.connect(_delete_power_query.bind(view))
	row.add_child(del)
	panel.tooltip_text = "这段积木随时被用来算威力，只能放「威力计算」和查询类积木，不能改动游戏。"
	return panel


# 威力计算整段删掉：模型和 JSON 两边都去掉，避免下次提交又写回空列表。
func _delete_power_query(view:Dictionary) -> void:
	view.lists.erase("power_query")
	view.effect.erase("power_query")
	_refresh_scripts()


# =============== 生成牌 ===============

# 生成牌向导里按声明填的下拉：自定义牌种类、卡库种类、放进哪一区。
func _fill_generate_menus() -> void:
	for item in maker.types.get("custom_card_types", []):
		gen_custom_type.add_item(str(item.shown))
		gen_custom_type.set_item_metadata(gen_custom_type.item_count - 1, item)
	for src in maker.types.get("card_sources", []):
		gen_type.add_item(str(src.shown))
		gen_type.set_item_metadata(gen_type.item_count - 1, src)
	var names:Dictionary = maker.types.get("player_key_names", {})
	for zone in maker.types.get("card_zones", []):
		gen_zone.add_item(str(names.get(zone, zone)))
		gen_zone.set_item_metadata(gen_zone.item_count - 1, str(zone))


func _on_gen_mode_selected(_index:int) -> void:
	_show_generate_mode()


func _on_gen_type_selected(_index:int) -> void:
	_fill_generate_list()


func _on_gen_search_changed(_text:String) -> void:
	_fill_generate_list()


func _on_gen_list_selected(index:int) -> void:
	gen_name.text = str(gen_list.get_item_metadata(index))


func _show_generate_mode() -> void:
	var custom := gen_mode.selected == 0
	gen_custom.visible = custom
	gen_library.visible = not custom


# 卡库列表：按种类声明的 kind 扫 data 里的卡，显示「牌名  内部名」。
func _fill_generate_list() -> void:
	gen_list.clear()
	if gen_type.selected < 0:
		return
	var src:Dictionary = gen_type.get_item_metadata(gen_type.selected)
	var spec := maker.kind_spec(str(src.kind))
	var needle := gen_search.text.strip_edges().to_lower()
	for file in maker.list_files(str(src.kind)):
		var card = maker.read_json(str(file.path))
		if not card is Dictionary:
			continue
		var identity := str(card.get(spec.get("identity", ""), ""))
		var shown := str(card.get(spec.get("shown_key", ""), ""))
		var text := (shown + "  " if shown != "" else "") + identity
		if identity == "" or (needle != "" and text.to_lower().find(needle) == -1):
			continue
		gen_list.add_item(text)
		gen_list.set_item_metadata(gen_list.item_count - 1, identity)


func open_generate(view:Dictionary) -> void:
	gen_view = view
	gen_search.text = ""
	gen_name.text = ""
	gen_count.value = 1
	gen_register.button_pressed = true
	gen_mode.select(0)
	_show_generate_mode()
	_fill_generate_list()
	gen_window.popup_centered()


# 搭积木：把「新建一张牌」放进「玩家的某一区」；张数大于 1 时包进「重复 N 次」。都是已有操作的组合。
func _apply_generate() -> void:
	if gen_view.is_empty() or gen_zone.selected < 0:
		return
	var zone := str(gen_zone.get_item_metadata(gen_zone.selected))
	if gen_mode.selected == 0:
		if gen_custom_type.selected < 0:
			return
		var item:Dictionary = gen_custom_type.get_item_metadata(gen_custom_type.selected)
		var card := blank_custom_card(str(item.kind))
		_append_generated(generate_custom_blocks(card, item, zone, int(gen_count.value), gen_register.button_pressed, gen_view.effect))
		_set_status("已加入一张自定义" + str(item.shown) + "，在这一页写它的卡面和效果")
		# 立刻打开这张新牌：先把积木写回 JSON，才能在卡里找到它的位置
		_commit()
		call_deferred("focus_custom_card", card, str(item.kind))
		return
	var name := gen_name.text.strip_edges()
	if name == "" or gen_type.selected < 0:
		_set_status("先选一张牌再加")
		return
	var src:Dictionary = gen_type.get_item_metadata(gen_type.selected)
	_append_generated(generate_blocks(name, str(src.type), zone, int(gen_count.value), gen_view.effect, gen_register.button_pressed))
	_set_status("已加入生成牌：" + name)


func _append_generated(nodes:Array) -> void:
	if gen_view.options.is_empty():
		if not gen_view.lists.has("funcs"):
			gen_view.lists["funcs"] = []
		gen_view.lists.funcs.append_array(nodes)
	else:
		gen_view.options.back().nodes.append_array(nodes)
	_refresh_scripts()


# 自定义牌的空白数据：加载器直接取的键先写上默认值（types.json 标了 required 的，加上效果列表与属性）。
func blank_custom_card(kind:String) -> Dictionary:
	var card := maker.blank_required(kind)
	var spec := maker.kind_spec(kind)
	for field in spec.get("fields", []):
		if str(field.get("control", "")) == "attributes" and not card.has(field.key):
			card[field.key] = []
	for item in spec.get("lists", []):
		if str(item.key) == "effects" and not card.has("effects"):
			card["effects"] = []
	return card


# 自定义牌：新建一张 → 放进某一区 →（可选）让它的效果生效。新牌记在变量里给后面两步用，
# 张数大于 1 时整串包进「重复 N 次」，每一轮都是新的一张。都是已有操作的组合。
func generate_custom_blocks(card:Dictionary, item:Dictionary, zone:String, count:int, register:bool, effect) -> Array:
	var build := _new_op("build_card")
	build.params[0] = {"s": "lit", "v": card}
	build.params[1] = {"s": "lit", "v": str(item.type)}
	if str(item.get("back_type", "")) != "":
		build.params[4] = {"s": "lit", "v": str(item.back_type)}
	return _place_blocks(build, zone, count, register, effect)


func generate_blocks(card_name:String, card_type:String, zone:String, count:int, effect, register := false) -> Array:
	var create := _new_op("create_card")
	create.params[0] = {"s": "lit", "v": card_name}
	create.params[1] = {"s": "lit", "v": card_type}
	return _place_blocks(create, zone, count, register, effect)


# 返回一串积木：一张时直接平铺，多张时包进一块「重复 N 次」。
func _place_blocks(maker_node:Dictionary, zone:String, count:int, register:bool, effect) -> Array:
	var area := _new_op("get_player_data_value")
	area.params[0] = {"s": "lit", "v": zone}
	var put := _new_op("add_to_array")
	put.params[1] = {"s": "block", "b": area}
	var steps:Array = []
	if register:
		maker_node.var = codec.max_var(_all_nodes_of_current()) + 1
		put.params[0] = {"s": "var", "n": maker_node.var}
		var reg := _new_op("register_object_effects")
		reg.params[0] = {"s": "var", "n": maker_node.var}
		steps = [maker_node, put, reg]
	else:
		put.params[0] = {"s": "block", "b": maker_node}
		steps = [put]
	if count <= 1:
		return steps
	var loop := _new_op("for_func")
	loop.params[0] = {"s": "script", "body": steps}
	loop.params[1] = _new_number_slot(count, effect)
	return [loop]


# 打开一张写在积木里的自定义牌：按对象在卡里找到路径，像子牌一样单独开一页。
func focus_custom_card(card:Dictionary, kind:String) -> void:
	var at = _path_to(data, card, [])
	if at == null:
		_set_status("没找到这张自定义牌")
		return
	focus_to(at, kind)


func _path_to(node, target, base:Array):
	if is_same(node, target):
		return base
	if node is Dictionary:
		for key in node:
			if node[key] is Dictionary or node[key] is Array:
				var found = _path_to(node[key], target, base + [key])
				if found != null:
					return found
	elif node is Array:
		for i in node.size():
			if node[i] is Dictionary or node[i] is Array:
				var found = _path_to(node[i], target, base + [i])
				if found != null:
					return found
	return null


func _options_view(view:Dictionary) -> Control:
	var col := VBoxContainer.new()
	var effect:Dictionary = view.effect
	for oi in view.options.size():
		var ov:Dictionary = view.options[oi]
		var option:Dictionary = ov.option
		var head := PanelContainer.new()
		head.add_theme_stylebox_override("panel", Shape.new("stack", Color("#77522C")))
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
		# 选项头与执行串共用左边缘，凹口覆盖头部凸起；设置不插在接缝中。
		var connected := VBoxContainer.new()
		connected.add_theme_constant_override("separation", -int(Shape.NOTCH_D))
		connected.add_child(head)
		var body := _stack_view(ov.nodes, "option")
		if not ov.nodes.is_empty():
			body.get_child(0).custom_minimum_size.y = 0
		connected.add_child(body)
		col.add_child(connected)
		var settings := _fold_box(col, "选项的限制", false)
		_paint_fields(settings, option, _spec_without(maker.item_spec("option"), ["shown_option_name"]))
		_requirements_view(col, ov)
	var add := Button.new()
	add.text = "＋ 再加一个选项"
	add.pressed.connect(func():
		var option := {"shown_option_name": "选项" + str(view.options.size() + 1), "funcs": []}
		effect.options.append(option)
		view.options.append({"option": option, "nodes": [], "reqs": []})
		_refresh_scripts())
	col.add_child(add)
	return col


# 选项的「发动前必须满足」：每条是一句做不到时的提示加一串查询积木，最后一块算出真才能选这一项。
# 条件积木存在 ov.reqs 里与 activation_requirements 一一对应，_commit 按下标写回。
func _requirements_view(parent:Node, ov:Dictionary) -> void:
	var option:Dictionary = ov.option
	var reqs:Array = option.get("activation_requirements", []) if option.get("activation_requirements") is Array else []
	var fold := _fold_box(parent, "发动前必须满足（" + str(reqs.size()) + "）", not reqs.is_empty())
	fold.name = "Requirements"
	fold.add_child(_hint("最后一块积木算出「是」才能选这一项；做不到时玩家看到下面填的提示。"))
	var spec := maker.item_spec("requirement")
	for ri in reqs.size():
		if not reqs[ri] is Dictionary:
			continue
		while ov.reqs.size() <= ri:
			ov.reqs.append([])
		var head := HBoxContainer.new()
		head.add_child(_label("条件 " + str(ri + 1), 14, C_TEXT))
		var del := Button.new()
		del.text = "删掉这条"
		del.pressed.connect(func():
			reqs.remove_at(ri)
			ov.reqs.remove_at(ri)
			if reqs.is_empty():
				option.erase("activation_requirements")
			_refresh_scripts())
		head.add_child(del)
		fold.add_child(head)
		_paint_fields(fold, reqs[ri], spec)
		fold.add_child(_stack_view(ov.reqs[ri], "requirement"))
	var add := Button.new()
	add.name = "AddRequirement"
	add.text = "＋ 加一条前置条件"
	add.pressed.connect(func():
		var req := maker.blank_required("requirement")
		req["funcs"] = []
		reqs.append(req)
		option["activation_requirements"] = reqs
		ov.reqs.append([])
		_refresh_scripts())
	fold.add_child(add)


# 一串竖直堆叠的积木，积木之间与末尾都能接住拖来的积木。
func _stack_view(list:Array, context:String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	for i in list.size():
		col.add_child(_gap(list, i, context))
		col.add_child(_render_node(list[i], {"list": list, "index": i, "context": context}))
	col.add_child(_gap(list, list.size(), context, true))
	return col


func _gap(list:Array, index:int, context:String, is_empty := false) -> Control:
	var zone := Panel.new()
	zone.custom_minimum_size = Vector2(160 if is_empty else 200, 30 if is_empty else 8)
	zone.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0.04) if is_empty else Color(0, 0, 0, 0)
	s.set_corner_radius_all(4)
	if is_empty:
		s.border_color = C_GOLD3
		s.set_border_width_all(1)
	zone.add_theme_stylebox_override("panel", s)
	if is_empty:
		var lab := _label("把积木拖到这里", 13, HINT)
		lab.position = Vector2(10, 6)
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		zone.add_child(lab)
		zone.tooltip_text = "右键可粘贴剪贴板中的积木"
		zone.gui_input.connect(func(event:InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				context_target = {"paste_zone": zone}
				context_menu.clear()
				context_menu.add_item("粘贴", 2)
				context_menu.set_item_disabled(0, clipboard == null or not _accepts(zone.get_meta("drop"), clipboard, {}))
				context_menu.position = Vector2i(zone.get_global_mouse_position())
				context_menu.popup())
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
		row.add_child(_slot_widget(node, "target", "对象", "", "", true, where))
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
			row.add_child(_slot_widget(params, pi, maker.param_shown(pname), str(op.params[pi].type), op_name + ":" + pname, bool(op.params[pi].required), where))
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
		if not containers.has(i) and not hidden.has(str(op_params[i].name)):
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
		more.add_theme_color_override("font_color", C_GOLD2)
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
				row.add_child(_slot_widget(params, i, maker.param_shown(pname), ptype, op_name + ":" + pname, req, where))
	if node.get("cond") is Dictionary and not where.get("palette", false):
		row.add_child(_block_label("仅当"))
		row.add_child(_slot_widget(node, "cond", "条件", "bool", "", true, where))
	if not where.has("slot_parent") and not where.get("palette", false):
		var tag := _result_tag(node)
		if tag != null:
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
	if not where.get("palette", false):
		for oi in codec.option_params.get(op_name, []) if node.t == "op" else []:
			while params.size() <= oi:
				params.append({"s": "options", "items": []})
			if params[oi] is Dictionary and str(params[oi].get("s", "")) == "lit" and params[oi].get("v") == null:
				params[oi] = {"s": "options", "items": []}
			if params[oi] is Dictionary and str(params[oi].get("s", "")) == "options":
				_option_mouths(wrap, params[oi], color)
		if not codec.option_params.get(op_name, []).is_empty():
			var foot := PanelContainer.new()
			foot.custom_minimum_size = Vector2(120, 18)
			foot.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			foot.add_theme_stylebox_override("panel", Shape.new("c_bottom", color))
			wrap.add_child(foot)
			_wire_insert(foot, wrap, where, null, true)
	_add_block_help_icon(row, node)
	_wire_block(panel, node, where, wrap, _first_mouth(node, containers))
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return wrap


# 选项列表画成一个个嘴：每项一行「选项 n [文字] 限制… ✕」，下面接这一项的一串积木，最后是「＋ 再加一个选项」。
# 选项的其余字段（次数、挑牌……）用 types.json 的 option 表单画，与效果自带选项同一套。
func _option_mouths(wrap:VBoxContainer, slot:Dictionary, color:Color) -> void:
	for oi in slot.items.size():
		var item:Dictionary = slot.items[oi]
		var head := PanelContainer.new()
		head.add_theme_stylebox_override("panel", _flat(color, 0, 4))
		head.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var row := HBoxContainer.new()
		head.add_child(row)
		row.add_child(_block_label("  选项 " + str(oi + 1)))
		var name := LineEdit.new()
		name.text = str(item.opt.get("shown_option_name", ""))
		name.placeholder_text = "玩家看到的选项文字"
		name.custom_minimum_size = Vector2(200, 0)
		name.text_changed.connect(func(v): item.opt["shown_option_name"] = v; _changed())
		row.add_child(name)
		var del := Button.new()
		del.text = "✕"
		del.flat = true
		del.tooltip_text = "删掉这一项"
		del.add_theme_color_override("font_color", C_DIM)
		del.pressed.connect(func(): slot.items.remove_at(oi); _refresh_scripts())
		row.add_child(del)
		wrap.add_child(head)
		var mouth := HBoxContainer.new()
		mouth.add_theme_constant_override("separation", 0)
		var arm := Panel.new()
		arm.custom_minimum_size = Vector2(16, 0)
		arm.add_theme_stylebox_override("panel", _flat(color, 0, 0))
		mouth.add_child(arm)
		mouth.add_child(_stack_view(item.body, "option"))
		wrap.add_child(mouth)
		var settings := _fold_box(wrap, "这一项的限制", false)
		_paint_fields(settings, item.opt, _spec_without(maker.item_spec("option"), ["shown_option_name"]))
		if not item.has("reqs"):
			item["reqs"] = []
		_requirements_view(wrap, {"option": item.opt, "reqs": item.reqs})
	var add_row := HBoxContainer.new()
	var arm2 := Panel.new()
	arm2.custom_minimum_size = Vector2(16, 0)
	arm2.add_theme_stylebox_override("panel", _flat(color, 0, 0))
	add_row.add_child(arm2)
	var add := Button.new()
	add.name = "AddOption"
	add.text = "＋ 再加一个选项"
	add.pressed.connect(func():
		slot.items.append({"opt": {"shown_option_name": "选项" + str(slot.items.size() + 1)}, "keys": ["shown_option_name", "funcs"], "body": []})
		_refresh_scripts())
	add_row.add_child(add)
	wrap.add_child(add_row)


# 「对每一个」会把当前这一项填进嘴里每一步的「填入位置」那一格（只填空着的）。
# 把这些空格标成「↻ 当前这一项」，只是显示用的记号，保存时仍写成空。
# 没填的可选空位也算空着：否则保存时写成默认值，循环就填不进去了。
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
			if not slot is Dictionary:
				continue
			var s := str(slot.get("s", ""))
			if i == fill and ((s == "lit" and slot.get("v") == null) or s == "omit"):
				slot["loop"] = true
			elif i != fill and (s == "lit" or s == "omit"):
				slot.erase("loop")


func _render_if(node:Dictionary, where:Dictionary) -> Control:
	var color := Color("#77602C")
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 0)
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", Shape.new("stack", color))
	wrap.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	top.add_child(row)
	row.add_child(_block_label("如果"))
	row.add_child(_slot_widget(node, "cond", "条件", "bool", "", true, where))
	row.add_child(_block_label("那么"))
	_add_block_help_icon(row, node)
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
	panel.add_theme_stylebox_override("panel", Shape.new("stack", Color("#454A55")))
	var row := HBoxContainer.new()
	panel.add_child(row)
	row.add_child(_block_label("看不懂的一步（原样保留）"))
	_add_block_help_icon(row, node)
	_add_delete_button(row, node, where)
	panel.tooltip_text = JSON.stringify(node.v)
	_wire_block(panel, node, where)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return panel


# 积木区里的「结果」「当前这一项」这类只有一个值的小积木。
func _render_slot_value(slot:Dictionary, where:Dictionary) -> Control:
	var panel := PanelContainer.new()
	var color := LOOP_ITEM_COLOR if slot.get("loop", false) else VAR_COLOR
	panel.add_theme_stylebox_override("panel", Shape.new("reporter", color))
	var text := ""
	match str(slot.s):
		"var":
			text = "结果 " + str(slot.n)
		"qty":
			text = "选项 " + str(int(slot.i) + 1) + " 选的数量"
		_:
			text = "↻ 当前这一项"
	var node := {"t": "slot_only", "slot": slot}
	var row := HBoxContainer.new()
	row.add_child(_block_label(text))
	_add_block_help_icon(row, node)
	panel.add_child(row)
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


# 积木末尾的「结果 n」小标签：有结果的积木都有，拖到别的积木的空位里就读这一步的结果。
# 编号第一次画出来时从这张卡没用过的号里分，记在 tag_var；保存时只有真被读到才写成 var_index。
# 右键「存为变量」写的是 var，不管有没有人读都写出去。
func _result_tag(node:Dictionary) -> Control:
	var n := int(node.get("var", -1))
	if n < 0:
		if node.t == "op" and not maker.has_result(str(node.get("func", ""))):
			return null
		if int(node.get("tag_var", -1)) < 0:
			node["tag_var"] = codec.max_var(_all_nodes_of_current()) + 1
		n = int(node.tag_var)
	var tag := PanelContainer.new()
	tag.name = "ResultTag"
	tag.add_theme_stylebox_override("panel", Shape.new("reporter", VAR_COLOR))
	var tag_label := _block_label("结果 " + str(n))
	tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_child(tag_label)
	tag.mouse_filter = Control.MOUSE_FILTER_STOP
	tag.mouse_default_cursor_shape = Control.CURSOR_DRAG
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.tooltip_text = "「结果」相当于变量：记住这一步算出的值，供后面的步骤引用。" + ("" if int(node.get("var", -1)) >= 0 else "\n没有地方用它时不会写进 JSON。")
	var slot := {"s": "var", "n": n}
	tag.set_drag_forwarding(func(_p): return _begin_drag({"new": {"kind": "var_ref", "slot": slot}}, tag), Callable(), Callable())
	if node.t != "op" or str(maker.operation_of(str(node.get("func", ""))).get("returns", "")) != "Array":
		return tag
	var expanded := VBoxContainer.new()
	var heading := HBoxContainer.new()
	expanded.add_child(heading)
	heading.add_child(tag)
	var toggle := Button.new()
	var count := int(node.get("array_items", 0))
	toggle.text = "收起" if count > 0 else "展开数组"
	toggle.tooltip_text = "结果数量要到运行时才知道；可按需增加索引。拖结果标签可传整组。"
	toggle.pressed.connect(func(): node["array_items"] = 0 if count > 0 else 1; _refresh_scripts())
	heading.add_child(toggle)
	for index in count:
		var item := PanelContainer.new()
		item.name = "ArrayItemTag_" + str(index)
		item.add_theme_stylebox_override("panel", Shape.new("reporter", VAR_COLOR))
		var item_label := _block_label("第 " + str(index + 1) + " 项")
		item_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(item_label)
		item.mouse_default_cursor_shape = Control.CURSOR_DRAG
		item.tooltip_text = "拖到参数里，运行时按索引读取第 " + str(index + 1) + " 项。超出结果长度时返回空。"
		item.set_drag_forwarding(func(_p): return _begin_drag({"new": {"kind": "array_item", "variable": n, "index": index}}, item), Callable(), Callable())
		expanded.add_child(item)
	if count > 0:
		var add := Button.new()
		add.text = "＋ 下一项"
		add.pressed.connect(func(): node["array_items"] = count + 1; _refresh_scripts())
		expanded.add_child(add)
	return expanded


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
		del.add_theme_color_override(c, C_DIM)
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
# where 带 palette 时这一格在积木区里：那里没有正在编辑的卡可写，只画成能点开候选的预览入口。
func _slot_widget(holder, key, label:String, type_name:String, kind_key:String, required:bool, where:Dictionary = {}) -> Control:
	if where.get("palette", false):
		return _palette_slot_widget(label, type_name, kind_key)
	var slot = holder[key]
	if not slot is Dictionary or not slot.has("s"):
		slot = {"s": "lit", "v": slot}
		holder[key] = slot
	var box := PanelContainer.new()
	var s := str(slot.s)
	# 空参数不能只剩下窄窄的按钮；整个圆角区域都是拖放目标，避免手指或鼠标难以命中。
	if s == "lit" or s == "omit":
		box.custom_minimum_size = Vector2(96, 36)
	var is_bool := type_name == "bool"
	var kind := _slot_kind(kind_key)
	var content:Control
	if kind == "card_data" and (s == "lit" or s == "omit"):
		s = "card_data"
	match s:
		"card_data":
			box.add_theme_stylebox_override("panel", Shape.new("slot", SLOT_FILL))
			content = _card_data_editor(holder, key, kind_key)
		"block", "desc":
			content = _render_op(slot.b, {"slot_parent": holder, "slot_key": key})
			box.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		"var":
			box.add_theme_stylebox_override("panel", Shape.new("reporter", VAR_COLOR))
			var var_button := _slot_picker(holder, key, type_name, kind, kind_key, "结果 " + str(slot.n) + " ▾")
			var_button.flat = true
			var_button.add_theme_color_override("font_color", C_GOLD2)
			var_button.tooltip_text = "「结果」相当于变量：这里引用前面步骤算出的值。"
			content = var_button
		"qty":
			box.add_theme_stylebox_override("panel", Shape.new("reporter", VAR_COLOR))
			content = _with_picker(_block_label("选项 " + str(int(slot.i) + 1) + " 选的数量"), holder, key, type_name, kind, kind_key)
		"num":
			box.add_theme_stylebox_override("panel", Shape.new("slot", SLOT_FILL))
			content = _number_editor(slot, holder, key, type_name)
			if content is HBoxContainer:
				content.add_child(_slot_picker(holder, key, type_name, kind, kind_key, "▾"))
		"script":
			content = _block_label("（一串积木）")
			box.add_theme_stylebox_override("panel", Shape.new("slot", SLOT_FILL))
		"options":
			content = _block_label("（" + str(slot.items.size()) + " 个选项，在下面）")
			box.add_theme_stylebox_override("panel", Shape.new("slot", SLOT_FILL_SOFT))
		"list":
			content = _list_editor(slot)
			box.add_theme_stylebox_override("panel", Shape.new("slot", SLOT_FILL_SOFT))
		"omit":
			var shape := Shape.new("boolean" if is_bool else "empty", LOOP_ITEM_COLOR if slot.get("loop", false) else SLOT_FILL_SOFT)
			box.add_theme_stylebox_override("panel", shape)
			content = _literal_editor(holder, key, slot, type_name, kind, kind_key, label, true)
		_:
			var empty:bool = slot.get("v") == null and not slot.get("loop", false)
			var shape := Shape.new("boolean" if is_bool and empty else "slot", SLOT_FILL if not slot.get("loop", false) else LOOP_ITEM_COLOR)
			shape.highlight = empty and required
			box.add_theme_stylebox_override("panel", shape)
			content = _literal_editor(holder, key, slot, type_name, kind, kind_key, label, false)
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


# 写在积木里的整张牌：点一下像子牌一样打开编辑；还空着就按同一块里「种类」那一格新建一张空白牌。
func _card_data_editor(holder, key, kind_key:String) -> Control:
	var slot:Dictionary = holder[key]
	var card = slot.get("v")
	var type_id := _sibling_value(holder, kind_key, "custom_card_type")
	var kind := maker.custom_card_kind(type_id)
	var button := Button.new()
	button.flat = true
	button.add_theme_color_override("font_color", C_TEXT)
	if card is Dictionary:
		var spec := maker.kind_spec(kind)
		var shown := str(card.get(spec.get("shown_key", ""), ""))
		button.text = "✎ " + (shown if shown != "" else str(card.get(spec.get("identity", ""), "")))
		if button.text == "✎ ":
			button.text = "✎ 还没起名的牌"
	else:
		button.text = "＋ 写一张牌"
	button.tooltip_text = "打开这张牌：卡面、数值、卡图和效果都在那一页写。"
	button.disabled = kind == ""
	button.pressed.connect(func():
		if not holder[key].get("v") is Dictionary:
			holder[key] = {"s": "lit", "v": blank_custom_card(kind)}
		var target:Dictionary = holder[key].v
		_commit()
		call_deferred("focus_custom_card", target, kind))
	return button


# 同一块积木里声明为某种控件的那一格现在的值（例如自定义牌的「种类」）。
func _sibling_value(holder, kind_key:String, want:String) -> String:
	var op_name := kind_key.split(":")[0]
	var op := maker.operation_of(op_name)
	if not holder is Array:
		return ""
	for i in op.get("params", []).size():
		if maker.param_kind(op_name, str(op.params[i].name)) == want and i < holder.size():
			var v = holder[i]
			if v is Dictionary and v.has("s"):
				v = v.get("v", v.get("d"))
			return str(v) if v != null else ""
	return ""


func _slot_kind(kind_key:String) -> String:
	if kind_key == "":
		return ""
	var parts := kind_key.split(":")
	return maker.param_kind(parts[0], parts[1]) if parts.size() == 2 else ""


# 字面值空位：一律是「分类 + 搜索」下拉（共用的搜索面板），找不到就直接打字回车。
# 开关、数字仍可在勾选框 / 数字框里直接改，后面跟一个 ▾ 打开同一套下拉。时机列表、属性列表是一排小标签。
func _literal_editor(holder, key, slot:Dictionary, type_name:String, kind:String, kind_key:String, label:String, omitted:bool) -> Control:
	if slot.get("loop", false):
		return _with_picker(_block_label("↻ 当前这一项"), holder, key, type_name, kind, kind_key)
	var value = slot.get("d") if omitted else slot.get("v")
	if kind == "time_points" or kind == "attributes":
		return _multi_menu(kind, value, omitted, holder, key)
	var eff = _render_effect
	var declared := _kind_groups(kind, kind_key)
	# 列表格声明了候选（区域路径、威力来源、共用的键……）：同样是一排小标签多选
	if not declared.is_empty() and type_name == "Array" and (value == null or value is Array):
		return _with_picker(_multi_menu(kind, value, omitted, holder, key, kind_key), holder, key, type_name, kind, kind_key)
	if declared.is_empty() and (type_name == "bool" or value is bool):
		var box := CheckBox.new()
		box.button_pressed = value if value is bool else false
		box.text = "是" if box.button_pressed else ("默认" if omitted else "否")
		box.add_theme_color_override("font_color", C_TEXT)
		box.toggled.connect(func(on):
			box.text = "是" if on else "否"
			holder[key] = {"s": "lit", "v": on}
			_changed())
		return _with_picker(box, holder, key, type_name, kind, kind_key)
	if declared.is_empty() and type_name == "BaseNumber" and not omitted and value == null:
		# 直接给一个数字框：填了就记成这条效果的一个效果数字（可被更改）
		var spin := _spin(0.0, false)
		spin.name = "NewNumber"
		spin.custom_minimum_size = Vector2(76, 0)
		spin.modulate = Color(1, 1, 1, 0.6)
		spin.tooltip_text = "填一个数字。它会记成这条效果的数字，别的效果可以改它；也可以把算数字的积木拖进来，或点 ▾ 选。"
		spin.value_changed.connect(func(v):
			holder[key] = _new_number_slot(v if spin.step < 1.0 else int(v), eff)
			_refresh_scripts())
		return _with_picker(spin, holder, key, type_name, kind, kind_key)
	if declared.is_empty() and type_name == "BaseNumber" and omitted:
		var add := Button.new()
		add.text = "默认"
		add.flat = true
		add.add_theme_color_override("font_color", HINT)
		add.tooltip_text = "空着就用默认值。点一下填一个数字。"
		add.pressed.connect(func():
			holder[key] = _new_number_slot(0, eff)
			_refresh_scripts())
		return _with_picker(add, holder, key, type_name, kind, kind_key)
	if declared.is_empty() and (type_name in ["int", "float"] or value is int or value is float):
		var is_float:bool = type_name == "float" or (type_name != "int" and value is float and value != floor(value))
		var spin := _spin(float(value) if (value is int or value is float) else 0.0, is_float)
		spin.custom_minimum_size = Vector2(76, 0)
		if omitted:
			spin.modulate = Color(1, 1, 1, 0.6)
		spin.value_changed.connect(func(v):
			holder[key] = {"s": "lit", "v": v if is_float else int(v)}
			_changed())
		var row := _with_picker(spin, holder, key, type_name, kind, kind_key)
		# 形参不限类型时，写死的数字可以改回效果数字（能被别的效果更改）
		if not omitted and not type_name in ["int", "float", "bool", "String"]:
			row.add_child(_number_mode_button([["改成可被更改的效果数字", func(): holder[key] = _new_number_slot(value, eff); _refresh_scripts(), false]]))
		return row
	var full := _picked_text(value, declared + _used_groups(kind_key), omitted, label)
	var button := _slot_picker(holder, key, type_name, kind, kind_key, _short(full, 36) + " ▾")
	if full.length() > 36:
		button.tooltip_text = full + "\n\n" + button.tooltip_text
	button.add_theme_color_override("font_color", C_TEXT)
	return button


# 按钮上最多显示这么多字，多的用 … 代替；完整的值放在提示里。
func _short(text:String, limit:int) -> String:
	return text if text.length() <= limit else text.left(limit - 1) + "…"


# 控件后面接一个 ▾：点开是这个空位的下拉。
func _with_picker(control:Control, holder, key, type_name:String, kind:String, kind_key:String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.add_child(control)
	var more := _slot_picker(holder, key, type_name, kind, kind_key, "▾")
	more.flat = true
	row.add_child(more)
	return row


# 空位的下拉按钮：候选点开时才取，总是最新的；选中或打字都直接写回空位。
func _slot_picker(holder, key, type_name:String, kind:String, kind_key:String, text:String) -> Button:
	var eff = _render_effect
	var button := Button.new()
	button.name = "SlotPicker"
	button.text = text
	button.tooltip_text = "点开可以按分类选，也可以搜索；找不到就直接打字回车。"
	# 按钮常是空位里最深的控件；直接接拖放再由 _resolve_drop 找到所属空位。
	button.set_drag_forwarding(Callable(), _can_drop_on.bind(button), _drop_on.bind(button))
	button.pressed.connect(func():
		_open_search_popup(button, _slot_groups(type_name, kind, kind_key, eff),
			func(v): _apply_pick(holder, key, v, type_name, eff), true,
			func(t): _apply_typed(holder, key, str(t), type_name, eff),
			func(): return _slot_more_groups(type_name, kind_key, eff)))
	return button


# 兜底用的「其他所有字段」：所有已知来源各成一组，不按形参筛。
func _all_field_groups() -> Array:
	var out:Array = []
	for kind in maker.types.get("kind_choices", {}):
		for g in maker.kind_choice_groups(str(kind)):
			out.append({"shown": "可选值 · " + str(kind), "items": g.items})
	out.append_array(maker.player_key_groups())
	out.append_array(maker.object_property_groups())
	for kind in maker.types.get("property_sources", {}):
		out.append_array(maker.property_source_groups(str(kind)))
	for kind in maker.types.get("value_sources", {}):
		for g in maker.value_source_groups(str(kind)):
			out.append({"shown": str(g.shown) + " · " + str(kind), "items": g.items})
	out.append_array(maker.internal_name_groups(data))
	out.append_array(maker.card_back_groups())
	out.append_array(_time_point_groups())
	out.append_array(_area_groups())
	return out


# 每个空位的兜底：主列表因类型不符没列的结果和积木，再加上全部字段来源。
func _slot_more_groups(type_name:String, kind_key:String, eff) -> Array:
	var accept := _slot_accept(type_name, kind_key)
	var out:Array = _var_groups(eff, accept, false)
	out.append_array(_block_groups(accept, false))
	out.append_array(_all_field_groups())
	return out


# 这一格接受哪种结果：types.json 的 blocks[x].accepts / param_accepts 声明，没有就按形参类型。
func _slot_accept(type_name:String, kind_key:String) -> String:
	var parts := kind_key.split(":")
	return maker.param_accept(parts[0], parts[1], type_name) if parts.size() == 2 else type_name


# 这一格的下拉分组，按和这一格的契合程度排：
# 声明的可选值 → 卡库里这个形参用过的同类型值 → 这条效果前面的结果 → 特殊值 → 结果类型相符的积木。
# 结果类型不符的结果和积木不在这里列，收进「显示其他所有字段」。默认只展开第一组。
func _slot_groups(type_name:String, kind:String, kind_key:String, eff) -> Array:
	var accept := _slot_accept(type_name, kind_key)
	var out:Array = []
	var declared := _kind_groups(kind, kind_key)
	if declared.is_empty() and type_name == "bool":
		declared = [{"shown": "可选值", "items": [{"id": "true", "shown": "是", "value": true}, {"id": "false", "shown": "否", "value": false}]}]
	out.append_array(declared)
	# 卡库用值：已在声明里的不重复列
	for group in _used_groups(kind_key):
		var items:Array = group.items.filter(func(it): return _slot_accepts(type_name, it.value) and _find_item(declared, it.value).is_empty())
		if not items.is_empty():
			out.append({"shown": group.shown, "items": items})
	if not out.is_empty():
		out[0] = (out[0] as Dictionary).duplicate()
		out[0]["open"] = true
	out.append_array(_var_groups(eff, accept, true))
	var special:Array = [{"id": "", "shown": "清空这一格", "value": {"_pick": "clear"}}]
	if maker.type_fits(accept, "BaseNumber"):
		special.append({"id": "", "shown": "效果数字", "value": {"_pick": "number"}, "tip": "记成这条效果的一个数字，别的效果可以改它"})
	if not type_name in ["bool", "int", "float"]:
		special.append({"id": "", "shown": "↻ 当前这一项", "value": {"_pick": "loop"}, "tip": "在循环积木里代表正在处理的对象"})
	out.append({"shown": "特殊", "items": special})
	out.append_array(_block_groups(accept, true))
	return out


# 类型已知时只推荐相同值形态；未知类型不臆测返回值类型。
func _slot_accepts(type_name:String, value) -> bool:
	match type_name:
		"String": return value is String
		"bool": return value is bool
		"int": return value is int
		"float", "BaseNumber": return value is int or value is float
		"Array": return value is Array
		"Dictionary": return value is Dictionary
	return true


# 空位声明的控件对应的候选：kind_choices 里声明了的直接用，其余按控件取真实来源。
func _kind_groups(kind:String, kind_key:String = "") -> Array:
	if kind == "":
		return []
	var declared := maker.kind_choice_groups(kind)
	if not declared.is_empty():
		return declared
	# 按用途筛的玩家数据键、对象属性，以及从卡库收集的文字值：都由 types.json 声明控件名
	if maker.types.get("player_key_filters", {}).has(kind):
		return maker.player_key_groups(kind)
	if maker.types.get("object_property_filters", {}).has(kind):
		return maker.object_property_groups(kind)
	if maker.types.get("value_sources", {}).has(kind):
		return maker.value_source_groups(kind)
	match kind:
		"player_key":
			return maker.player_key_groups()
		"area_name":
			return _area_groups()
		"object_property":
			return maker.object_property_groups()
		"internal_name":
			var parts := kind_key.split(":")
			return maker.internal_name_groups(data, parts[1] if parts.size() == 2 else "")
		"time_point":
			return _time_point_groups()
		"card_back_type":
			return maker.card_back_groups()
	return maker.property_source_groups(kind)


func _used_groups(kind_key:String) -> Array:
	var parts := kind_key.split(":")
	return maker.used_value_groups(parts[0], parts[1]) if parts.size() == 2 else []


# 这条效果里有结果的积木（右键存成的变量、末尾的变量小标签），选了就读那一步的结果。
# fit 为 true 只列结果类型能放进 accept 的，为 false 只列放不进的（给兜底用）；不知道类型的算能放。
func _var_groups(eff, accept := "", fit := true) -> Array:
	var found := {}
	for view in effects_view:
		if is_same(view.effect, eff):
			_collect_vars(view.lists, found)
			for ov in view.options:
				_collect_vars(ov.nodes, found)
				_collect_vars(ov.reqs, found)
	var keys := found.keys()
	keys.sort()
	var items:Array = []
	for n in keys:
		var result := maker.result_of(str(found[n].func)) if str(found[n].func) != "" else ""
		var ok := result != "none" and maker.type_fits(accept, result)
		if ok != fit:
			continue
		items.append({"id": "结果 " + str(n), "shown": "结果 " + str(n) + " · " + str(found[n].text), "value": {"_pick": "var", "n": n}})
	return [] if items.is_empty() else [{"shown": "前面的结果" if fit else "类型不符的结果", "items": items}]


func _collect_vars(value, found:Dictionary) -> void:
	if value is Dictionary:
		if str(value.get("t", "")) in ["op", "method"]:
			var n := int(value.get("var", -1))
			if n < 0:
				n = int(value.get("tag_var", -1))
			if n >= 0 and not found.has(n):
				# 方法调用的结果类型不知道，func 记空
				found[n] = {"text": _say_text(str(value.get("func", value.get("method", "")))), "func": str(value.get("func", "")) if value.t == "op" else ""}
		for k in value:
			_collect_vars(value[k], found)
	elif value is Array:
		for item in value:
			_collect_vars(item, found)


# 有结果的积木按分类列出：选了就把它嵌进这一格。
# fit 为 true 只列结果类型能放进 accept 的（没声明结果类型的也列，不猜），为 false 列其余有结果的积木（给兜底用）。
func _block_groups(accept := "", fit := true) -> Array:
	var out:Array = []
	for cat in maker.categories():
		var items:Array = []
		for op in maker.operations:
			var fname := str(op.func_name)
			if str(op.category) != str(cat.id) or not maker.has_result(fname) or maker.result_of(fname) == "none":
				continue
			if maker.type_fits(accept, maker.result_of(fname)) != fit:
				continue
			items.append({"id": fname, "shown": _say_text(fname), "value": {"_pick": "op", "func": fname}, "tip": maker.help_of(fname)})
		if not items.is_empty():
			out.append({"shown": ("积木 · " if fit else "类型不符的积木 · ") + str(cat.shown), "items": items})
	return out


# 句式里的 {形参} 换成中文空位名。
func _say_text(func_name:String) -> String:
	var parts:Array = []
	for part in _split_say(maker.say_of(func_name)):
		parts.append(maker.param_shown(part.substr(1, part.length() - 2)) if part.begins_with("{") else part.strip_edges())
	return " ".join(PackedStringArray(parts.filter(func(x): return x != ""))).strip_edges()


func _find_item(groups:Array, value) -> Dictionary:
	for group in groups:
		for item in group.items:
			if _same_value(item.get("value", str(item.id)), value):
				return item
	return {}


func _same_value(a, b) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	return typeof(a) == typeof(b) and a == b


# 按钮上显示的当前值：候选里有就显示它的中文名，没有就显示原值。
func _picked_text(value, groups:Array, omitted:bool, empty_text:String) -> String:
	if value == null:
		return "默认" if omitted else empty_text
	var text := str(value) if value is String else JSON.stringify(maker._whole_numbers(value))
	var item := _find_item(groups, value)
	var shown := str(item.get("shown", ""))
	if shown != "":
		text = shown if item.has("value") or shown == text else shown + "  " + text
	return ("默认 " if omitted else "") + text


# 选中候选：变量、积木、特殊值换成相应的空位形态；形参是数字对象时，选中的数字记成效果数字。
func _apply_pick(holder, key, value, type_name:String, eff) -> void:
	if value is Dictionary and value.has("_pick"):
		match str(value._pick):
			"var":
				holder[key] = {"s": "var", "n": int(value.n)}
			"op":
				holder[key] = {"s": "block", "b": _new_op(str(value.func))}
			"clear":
				holder[key] = _empty_slot()
			"number":
				holder[key] = _new_number_slot(0, eff)
			"loop":
				holder[key] = {"s": "lit", "v": null, "loop": true}
	elif type_name == "BaseNumber" and (value is int or value is float):
		holder[key] = _new_number_slot(value, eff)
	else:
		holder[key] = {"s": "lit", "v": maker._whole_numbers(value) if value is float else value}
	_refresh_scripts()


# 打的字按形参类型转换：文字原样；数字、开关、列表、字典按 JSON 读；不限类型时能读成 JSON 就用读出的值，否则当文字。
func _apply_typed(holder, key, text:String, type_name:String, eff) -> void:
	var parsed = null
	var ok := false
	var parser := JSON.new()
	if parser.parse(text) == OK:
		parsed = maker._whole_numbers(parser.data)
		ok = true
	match type_name:
		"String":
			_apply_pick(holder, key, text, type_name, eff)
			return
		"int", "float", "BaseNumber":
			if not (ok and (parsed is int or parsed is float)):
				_set_status("这一格要填数字")
				return
		"bool":
			if text in ["是", "否"]:
				parsed = text == "是"
			elif not (ok and parsed is bool):
				_set_status("这一格要填 是 或 否")
				return
		"Array", "Dictionary":
			if not ok or (type_name == "Array" and not parsed is Array) or (type_name == "Dictionary" and not parsed is Dictionary):
				_set_status("这一格要按 JSON 写，例如 [\"magic\"] 或 {\"type\": \"battle\"}")
				return
		_:
			if not ok:
				parsed = text
	_apply_pick(holder, key, parsed, type_name, eff)


func _area_groups() -> Array:
	var items:Array = []
	for area in MapData.areas:
		items.append({"id": str(area._area_name), "shown": ""})
	return [{"shown": "战区", "items": items}]


# 时机列表、属性列表以及声明了候选的其他列表格：一排小标签，点 ✕ 去掉，＋ 是可搜索的下拉，也可以打字加一个。
func _multi_menu(kind:String, value, omitted:bool, holder, key, kind_key := "") -> Control:
	var list:Array = value.duplicate() if value is Array else []
	var row := HBoxContainer.new()
	var groups:Array = [] if kind in ["time_points", "attributes"] else _kind_groups(kind, kind_key)
	for i in list.size():
		var chip := Button.new()
		match kind:
			"time_points": chip.text = maker.time_point_shown(str(list[i]))
			"attributes": chip.text = Attributes.get_shown_attribute(str(list[i]))
			_: chip.text = _picked_text(list[i], groups, false, "")
		chip.text += " ✕"
		chip.pressed.connect(func():
			list.remove_at(i)
			holder[key] = {"s": "lit", "v": list}
			_refresh_scripts())
		row.add_child(chip)
	var add_one := func(v):
		list.append(v)
		holder[key] = {"s": "lit", "v": list}
		_refresh_scripts()
	match kind:
		"time_points":
			row.add_child(_time_point_button("＋", add_one))
		"attributes":
			row.add_child(_search_button("＋", func(): return [{"shown": "属性", "items": maker.attributes, "open": true}], add_one, true, "点开可以搜索；找不到就直接打字回车，写自定义属性。"))
		_:
			row.add_child(_search_button("＋", _opened_first.bind(kind, kind_key), add_one, true, "点开可以搜索；找不到就直接打字回车。", _all_field_groups))
	if list.is_empty() and omitted:
		row.add_child(_block_label("默认"))
	return row


# 声明的候选，第一组默认展开。
func _opened_first(kind:String, kind_key:String) -> Array:
	var gs:Array = _kind_groups(kind, kind_key).duplicate()
	if not gs.is_empty():
		gs[0] = (gs[0] as Dictionary).duplicate()
		gs[0]["open"] = true
	return gs


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
# 旁边的 ▾ 能把它改成不可被更改的固定数字（会先弹警告）：形参要的是数字对象时仍是效果数字、只关掉可更改；
# 形参不限类型时写成纯数字。
func _number_editor(slot:Dictionary, holder = null, key = null, type_name := "") -> Control:
	var effect = _effect_of_slot(slot)
	var numbers:Array = effect.get("effect_numbers", []) if effect is Dictionary else []
	var i := int(slot.i)
	if i < 0 or i >= numbers.size() or not numbers[i] is Dictionary:
		return _block_label("数字 #" + str(i) + " 不存在")
	var num:Dictionary = numbers[i]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var spin := _spin(float(num.get("number", 0)), bool(num.get("is_float", false)))
	spin.custom_minimum_size = Vector2(76, 0)
	var shared := _number_ref_count(effect, i) > 1
	var fixed := not bool(num.get("can_change", true))
	spin.tooltip_text = ("固定数字，不可被更改" if fixed else "效果数字，可以被别的效果更改") + ("\n这个数字有多处在用，改一处会一起变" if shared else "")
	spin.value_changed.connect(func(v): num["number"] = v; _changed())
	row.add_child(spin)
	if fixed:
		row.add_child(_label("🔒", 12, C_TEXT))
	if holder == null:
		return row
	var to_fixed := func():
		if type_name == "BaseNumber":
			num["can_change"] = false
		else:
			holder[key] = {"s": "lit", "v": num.get("number", 0)}
		_refresh_scripts()
	var to_free := func():
		num["can_change"] = true
		_refresh_scripts()
	row.add_child(_number_mode_button([["改回可被更改的效果数字", to_free, false]] if fixed else [["改成固定数字，不可被更改", to_fixed, true]]))
	return row


# 数字旁的 ▾ 折叠菜单：entries 是 [[文字, 要做的事, 是否先弹警告]]。
func _number_mode_button(entries:Array) -> MenuButton:
	var menu := MenuButton.new()
	menu.name = "NumberMode"
	menu.text = "⚙"
	menu.flat = true
	menu.tooltip_text = "数字的写法"
	menu.add_theme_color_override("font_color", C_TEXT)
	var popup := menu.get_popup()
	for i in entries.size():
		popup.add_item(str(entries[i][0]), i)
	popup.id_pressed.connect(func(id):
		var entry:Array = entries[id]
		if bool(entry[2]):
			_confirm_fixed_number(entry[1])
		else:
			(entry[1] as Callable).call())
	return menu


func _confirm_fixed_number(apply:Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.name = "FixNumberConfirm"
	dialog.title = "改成固定数字"
	dialog.dialog_text = "固定数字不能再被任何效果更改（例如「费用减一」「威力加倍」都会对它无效）。\n卡面上的数字一般都应当能被更改，除非这张牌写明了这个数字不变。\n\n确定要改成固定数字吗？"
	dialog.ok_button_text = "改成固定数字"
	dialog.confirmed.connect(func(): apply.call(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


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
	if target.name == "SlotPicker":
		var parent := target.get_parent()
		while parent is Control and parent != script_box:
			if parent.has_meta("drop") and str(parent.get_meta("drop").get("kind", "")) == "slot":
				if (parent as Control).get_global_rect().grow(6).has_point(global) and _accepts(parent.get_meta("drop"), node, payload):
					return {"target": parent, "drop": parent.get_meta("drop")}
				break
			parent = parent.get_parent()
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
	context_menu.add_item("复制", 1)
	context_menu.add_item("删除", 3)
	if (node.t == "op" or node.t == "method") and where.has("list"):
		context_menu.add_separator()
		if int(node.get("var", -1)) >= 0:
			context_menu.add_item("不再保存结果", 4)
		else:
			context_menu.add_item("保存这一步的结果……", 5)
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
	if id == 2:
		var zone = context_target.get("paste_zone")
		if clipboard == null or not is_instance_valid(zone):
			return
		var drop:Dictionary = zone.get_meta("drop")
		if _accepts(drop, clipboard, {}):
			drop.list.insert(mini(int(drop.index), drop.list.size()), _fresh_copy(clipboard))
			_refresh_scripts()
		return
	if not context_target.has("node"):
		return
	var node:Dictionary = context_target.node
	var where:Dictionary = context_target.where
	match id:
		1:
			clipboard = _fresh_copy(node)
			_set_status("已复制积木。右键「把积木拖到这里」可粘贴。")
			return
		3:
			_detach(node, where, {})
		4:
			node.var = -1
		5:
			node.var = int(node.tag_var) if int(node.get("tag_var", -1)) >= 0 else codec.max_var(_all_nodes_of_current()) + 1
			_set_status("已保存为结果 " + str(node.var) + "。从左边「结果」拖出对应积木，放到要用的地方。")
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
			out.append(ov.reqs)
	return out


func _open_slot_menu(holder, key, effect, at:Vector2) -> void:
	context_menu.clear()
	context_target = {"slot_holder": holder, "slot_key": key, "effect": effect}
	context_menu.add_item("清空这一格", 11)
	context_menu.add_item("改成效果数字", 12)
	context_menu.add_item("改成引用结果", 13)
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
	_show_help("怎么用", "[color=#c9a45c]像搭积木一样写卡牌效果[/color]\n\n1. 上面选卡牌种类，在左中「选一张卡」里双击打开，或点「新建一张」。\n2. 在「卡面信息」里填牌名、选图。\n3. 在「效果积木」里，每条效果先选[color=#c9a45c]当……时[/color]，再从最左边的积木区把积木拖到下面。\n4. 深色的圆角格子是[color=#c9a45c]空位[/color]：可以直接填，也可以把圆角积木（算出一个值的积木）拖进去。\n5. 橙色「如果……那么」把要做的事包起来，就只在条件成立时做。\n6. 点任意积木，这里会告诉你它是干什么的。点积木右边的 ✕ 删除它，右键可以复制。\n7. 想插在两块积木中间，就拖到下面那块的上半截或上面那块的下半截，会出现一条蓝线标出位置。\n8. 右下「还要修的地方」清空后就能保存。\n9. 效果下面的「生成牌」按内部名新建一张牌放进某一区。\n\n" + _naming_help())


# 命名规范：通用规则来自 types.json 的 naming_guide，各种卡的文件夹与图片命名来自各自的导出声明（含用户导出设置）。
func _naming_help() -> String:
	var lines:Array = ["[color=#c9a45c]命名规范[/color]"]
	for line in maker.types.get("naming_guide", []):
		lines.append("• " + str(line))
	lines.append("")
	lines.append("[color=#c9a45c]各种卡的内部名、文件夹与图片[/color]")
	lines.append("{identity} 是内部名，{serial} 是编号，{folder} 是卡文件夹名，其他花括号是卡里同名字段。")
	for kind_id in maker.types.get("kinds", {}):
		var spec := maker.export_spec(str(kind_id))
		var parts:Array = []
		var identity := str(spec.get("identity", ""))
		if identity != "":
			parts.append("内部名字段 " + identity)
		if str(spec.get("root", "")) != "":
			var where := str(spec.root) + "/"
			match str(spec.get("file", "")):
				"named":
					where += str(spec.get("file_name", ""))
				"file":
					where += "{identity}.json"
				_:
					var folder := str(spec.get("folder_name", "{identity}"))
					where += folder + "/" + folder.get_file() + ".json"
			parts.append("存到 " + where)
		var images:Array = []
		for field in spec.get("fields", []):
			if str(field.get("control", "")) == "image":
				images.append(str(field.get("shown", field.key)) + " " + str(field.get("file_name", "{identity}")))
		if not images.is_empty():
			parts.append("图片 " + "、".join(PackedStringArray(images)))
		if str(spec.get("sub_image_prefix", "")) != "":
			parts.append("子牌图片前面加 " + str(spec.sub_image_prefix))
		if not parts.is_empty():
			lines.append("• " + str(spec.get("shown", kind_id)) + "：" + "；".join(PackedStringArray(parts)))
	return "\n".join(PackedStringArray(lines))


func _show_help_for(node:Dictionary) -> void:
	match str(node.t):
		"if":
			_show_help("如果……那么", "只有当条件成立时，才做嘴里的积木。\n\n条件格里放六边形或圆角积木都行：得到「是」、非 0 的数字、找到了东西，都算成立；「否」、0、什么都没拿到，都算不成立。")
			return
		"slot_only":
			var s:Dictionary = node.slot
			if s.s == "var":
				_show_help("结果", "「结果」相当于变量：记住前面步骤算出的值，供后面的步骤引用。\n\n可以直接拖动前面步骤末尾的「结果 N」标签，放进要用的空位；也可以右键那一步选择「保存这一步的结果……」，再从左边「结果」拖出积木。\n\n多数时候直接把圆角积木拖进空位就行，保存时会自动处理。")
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
		lines.append("[color=#a79e8b]这是新加的操作，还没登记到 all_operations.gd；登记后会归到对应分类。[/color]")
	if help != "":
		lines.append(help)
	if not op.is_empty():
		var ps:Array = []
		for p in op.params:
			ps.append("• " + maker.param_shown(str(p.name)) + "：" + _type_shown(str(p.type)) + ("" if p.required else "，可以不填"))
		if not ps.is_empty():
			lines.append("[color=#c9a45c]空位[/color]\n" + "\n".join(PackedStringArray(ps)))
	if op.is_empty() and node.t == "op":
		lines.append("[color=#ff4d57]找不到这个积木对应的程序：" + name + "[/color]")
	lines.append("[color=#6d665a]程序名：" + name + "[/color]")
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
			for req_nodes in ov.reqs:
				_empty_issues(req_nodes, label, out)
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
			elif slot.s == "options":
				for item in slot.items:
					_empty_issues(item.body, label, out)
			elif slot.s == "lit" and slot.get("v") == null and not slot.get("loop", false) and pi < op.get("params", []).size() and bool(op.params[pi].required):
				out.append(label + "：「" + maker.say_of(str(node.func)).replace("{", "").replace("}", "") + "」的「" + maker.param_shown(str(op.params[pi].name)) + "」还空着")


func _paint_issues(issues:Array) -> void:
	_clear(issue_list)
	if data == null:
		return
	if issues.is_empty():
		issue_list.add_child(_label("✔ 没有问题，可以保存", 14, C_OK))
		return
	for issue in issues.slice(0, 40):
		var lab := _label("• " + str(issue), 13, C_BLOOD2)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		issue_list.add_child(lab)


# =============== 保存 / 选图 ===============

func _save() -> void:
	if _practice_save_blocked():
		return
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
	if _practice_save_blocked():
		return
	if data == null:
		return
	_commit()
	var suggested := maker.suggest_path(card_kind, data if data is Dictionary else {})
	save_dialog.current_path = ProjectSettings.globalize_path(suggested) if suggested.begins_with("res://") else suggested
	save_dialog.popup_centered_ratio(0.7)


func _save_to(target:String) -> void:
	if _practice_save_blocked():
		return
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
	# 图片与 json 放在同一个文件夹：暂存区的图按命名规则复制过去，另存到别处时把原文件夹的图一起带过去
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
	_refresh_tutorial()


# 打包 zip：先保存（有改动时），再选 zip 放哪
func _zip_card() -> void:
	if _practice_save_blocked():
		return
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
	if _practice_save_blocked():
		return
	var files := maker.card_files(data, card_kind, path)
	# zip 里从哪一层开始放，按导出设置（默认相对项目根：data/masters/…，解压到项目根就回到原位）
	var zipped := maker.zip_files(files, target, maker.zip_base(card_kind, path))
	if not zipped.get("ok", false):
		_set_status(str(zipped.get("error", "打包失败")))
		return
	_set_status("✓ 已打包 " + target.get_file() + "：" + str(zipped.count) + " 个文件")


# =============== 选图 ===============

# 选图面板：能浏览电脑上任意位置，图片都直接显示缩略图，看得见卡图长什么样。
func _pick_image(obj:Dictionary, key:String, zoom_key:String) -> void:
	image_target = {"obj": obj, "key": key, "zoom": zoom_key}
	image_dir = _image_start_dir()
	if is_instance_valid(image_picker):
		image_picker.hide()   # 先让出独占窗口，queue_free 是延后的，不然新面板弹出时会和旧的抢独占
		image_picker.queue_free()
	var dialog := AcceptDialog.new()
	dialog.name = "ImagePicker"
	dialog.title = "选卡图"
	dialog.ok_button_text = "关闭"
	dialog.wrap_controls = false   # 尺寸自己定，别让内容把窗口撑到屏幕外
	add_child(dialog)
	image_picker = dialog
	dialog.confirmed.connect(func(): image_picker = null; dialog.queue_free())
	dialog.close_requested.connect(func(): image_picker = null; dialog.queue_free())
	var body := VBoxContainer.new()
	body.name = "ImagePickerBody"
	dialog.add_child(body)
	var where_row := HBoxContainer.new()
	body.add_child(where_row)
	var drives := OptionButton.new()
	drives.name = "ImageDriveMenu"
	for root in _image_roots():
		drives.add_item(str(root).trim_suffix("/"))
		drives.set_item_metadata(drives.item_count - 1, str(root))
	where_row.add_child(drives)
	drives.item_selected.connect(func(i): _show_image_dir(str(drives.get_item_metadata(i))))
	var up := Button.new()
	up.name = "ImageUpButton"
	up.text = "↑ 上一级"
	up.pressed.connect(_image_dir_up)
	where_row.add_child(up)
	var where := LineEdit.new()
	where.name = "ImagePathEdit"
	where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	where.tooltip_text = "这里写文件夹路径，回车跳过去"
	where_row.add_child(where)
	where.text_submitted.connect(func(text): _show_image_dir(text.strip_edges()))
	var search_box := LineEdit.new()
	search_box.name = "ImageSearch"
	search_box.placeholder_text = "在现在这一层里按名字筛"
	body.add_child(search_box)
	search_box.text_changed.connect(func(_text): _fill_image_picker())
	body.add_child(_hint("文件夹双击进入；图片以图标列出，单击图标选中。保存时按命名规则复制进卡的文件夹。"))
	var scroll := ScrollContainer.new()
	scroll.name = "ImageScroll"
	# 尺寸按面板定死：嵌入式窗口不会帮我们算剩余高度，写死反而稳
	scroll.custom_minimum_size = Vector2(IMAGE_PICKER_SIZE.x - 48, IMAGE_PICKER_SIZE.y - 200)
	body.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "ImageGrid"
	grid.columns = IMAGE_PICKER_COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	dialog.popup_centered(IMAGE_PICKER_SIZE)
	dialog.size = IMAGE_PICKER_SIZE
	_fill_image_picker()


# 打开面板时的起点，按顺序取第一个能用的位置：
# ① 这张卡上次选图去过的位置（同一张卡才认，不会把别的卡的位置带过来）
# ② 这张卡自己保存过的文件夹（图片就在 json 旁边）
# ③ 上次选图去过的位置（总比每次退回系统图片目录强）
# ④ 系统图片目录，再不然第一个能浏览的根
func _image_start_dir() -> String:
	var remembered := _remembered_image_dir()
	var remembered_dir := str(remembered.get("dir", ""))
	var remembered_ok := remembered_dir != "" and DirAccess.dir_exists_absolute(remembered_dir)
	if remembered_ok and str(remembered.get("card", "")) == str(path):
		return remembered_dir
	var folder := str(path).get_base_dir()
	if folder != "" and DirAccess.dir_exists_absolute(folder):
		return folder
	if remembered_ok:
		return remembered_dir
	var pictures := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if pictures != "":
		return pictures
	var roots := _image_roots()
	return str(roots[0]) if not roots.is_empty() else ""


# 选图面板记住的位置：存在导出设置的 _global 里（和 zip 目录同一处），关掉编辑器也还在。
# 记成 {dir, card}：dir 是文件夹，card 是当时在编辑哪张卡，用来判断该不该沿用它。
func _remembered_image_dir() -> Dictionary:
	var saved = maker.global_export("last_image_dir", {})
	return saved if saved is Dictionary else {}


# 记住这次去的位置。只写值变了的情况，免得来回浏览时反复写文件。
func _remember_image_dir(folder:String) -> void:
	if folder == "" or not DirAccess.dir_exists_absolute(folder):
		return
	var saved := _remembered_image_dir()
	if str(saved.get("dir", "")) == folder and str(saved.get("card", "")) == str(path):
		return
	maker.set_export("_global", "last_image_dir", {"dir": folder, "card": str(path)})
	maker.save_export_settings()


# 能浏览的位置：有盘符的系统按字母列出所有存在的根，其它系统用 /。
func _image_roots() -> Array:
	var out:Array = []
	for i in 26:
		var root := char(65 + i) + ":/"
		if DirAccess.dir_exists_absolute(root):
			out.append(root)
	if out.is_empty() and DirAccess.dir_exists_absolute("/"):
		out.append("/")
	return out


# 列当前文件夹：文件夹和图片都用一样大的图标格子，双击进入文件夹，单击选中图片。
func _fill_image_picker() -> void:
	if not is_instance_valid(image_picker):
		return
	var grid:GridContainer = image_picker.find_child("ImageGrid", true, false)
	if grid == null:
		return
	_clear(grid)
	var where:LineEdit = image_picker.find_child("ImagePathEdit", true, false)
	if where != null:
		where.text = image_dir
	var search_box:LineEdit = image_picker.find_child("ImageSearch", true, false)
	var needle := search_box.text.strip_edges().to_lower() if search_box != null else ""
	var dir := DirAccess.open(image_dir)
	if dir == null:
		grid.add_child(_hint("这个位置打不开：" + image_dir + "。换个盘或点「↑ 上一级」。"))
		return
	var folders:Array = []
	var pictures:Array = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with("."):
			if dir.current_is_dir():
				folders.append(name)
			elif maker.IMAGE_EXTS.has(name.get_extension().to_lower()):
				pictures.append(name)
		name = dir.get_next()
	folders.sort()
	pictures.sort()
	for folder_name in folders:
		if needle != "" and needle not in folder_name.to_lower():
			continue
		grid.add_child(_image_tile(image_dir.path_join(folder_name), folder_name, true))
	for file_name in pictures:
		if needle != "" and needle not in file_name.to_lower():
			continue
		grid.add_child(_image_tile(image_dir.path_join(file_name), file_name, false))
	if grid.get_child_count() == 0:
		grid.add_child(_hint("这一层没有图片也没有文件夹。"))


# 一个图标格子：上面是可点的缩略图，下面是名字。
func _image_tile(full:String, shown_name:String, is_folder:bool) -> Control:
	var tile := VBoxContainer.new()
	tile.name = "ImageTile"
	tile.custom_minimum_size = Vector2(IMAGE_TILE_SIZE, 0)
	var button := Button.new()
	button.name = "ImageFolderButton" if is_folder else "ImageTileButton"
	button.custom_minimum_size = Vector2(IMAGE_TILE_SIZE, IMAGE_TILE_SIZE)
	button.expand_icon = true
	button.tooltip_text = full + ("\n双击进入这个文件夹" if is_folder else "\n点一下就用这张图")
	if is_folder:
		button.text = "📁"
		button.add_theme_font_size_override("font_size", 48)
		button.gui_input.connect(func(event:InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
				_show_image_dir.call_deferred(full))
	else:
		button.icon = _thumb_texture(full, Vector2i(IMAGE_TILE_SIZE, IMAGE_TILE_SIZE))
		# 刷新会释放当前按钮，必须等 pressed 信号派发结束再选图。
		button.pressed.connect(_use_picked_image.bind(full), CONNECT_DEFERRED)
	tile.add_child(button)
	var label := _label(shown_name, 14, C_TEXT)
	label.name = "ImageTileName"
	label.custom_minimum_size = Vector2(IMAGE_TILE_SIZE, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.max_lines_visible = 2   # 名字最多两行，再长就在第二行收尾
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tile.add_child(label)
	return tile


func _show_image_dir(target:String) -> void:
	var folder := target.strip_edges()
	if folder == "" or not DirAccess.dir_exists_absolute(folder):
		_set_status("没有这个位置：" + target)
		return
	image_dir = folder
	_remember_image_dir(folder)
	_fill_image_picker()


func _image_dir_up() -> void:
	var folder := image_dir.trim_suffix("/")
	var parent := folder.get_base_dir()
	if parent == "" or parent == folder:
		return
	_show_image_dir(parent)


func _use_picked_image(source:String) -> void:
	_image_chosen(source)
	_fill_image_picker()


# 图标的缩略图：先缩到显示尺寸再做纹理，免得把整张大卡图都留在内存里。
func _thumb_texture(image:String, size:Vector2i) -> Texture2D:
	var img := Image.new()
	if img.load(image) != OK:
		return null
	if img.get_width() > size.x or img.get_height() > size.y:
		var scale := minf(float(size.x) / float(img.get_width()), float(size.y) / float(img.get_height()))
		img.resize(maxi(1, int(img.get_width() * scale)), maxi(1, int(img.get_height() * scale)), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)


func _image_chosen(source:String) -> void:
	var copied := maker.copy_image(source, PENDING_IMAGES)
	if not copied.get("ok", false):
		_set_status(str(copied.get("error", "选图失败")))
		return
	_remember_image_dir(source.get_base_dir())
	# 记完整路径：保存时据此认出是新选的图，按命名规则复制进卡的文件夹
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
		return Color("#454A55")
	var op := maker.operation_of(str(node.get("func", "")))
	var cat := maker.category_of(str(op.get("category", "")))
	return Color(str(cat.get("color", "#454A55")))


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


func _block_help_text(node:Dictionary) -> String:
	match str(node.get("t", "")):
		"if":
			return "如果……那么：只有条件成立时，才执行嘴里的积木。"
		"raw":
			return "编辑器暂时无法识别这一步，但会原样保留并保存。\n原文：" + JSON.stringify(node.get("v", {}))
		"slot_only":
			var slot:Dictionary = node.get("slot", {})
			match str(slot.get("s", "")):
				"var":
					return "结果：相当于变量，可引用前面步骤算出的值。"
				"qty":
					return "选项选的数量：读取玩家为当前选项填写的数量。"
				_:
					return "当前这一项：在循环积木里代表正在处理的对象。"
	var name := str(node.get("func", node.get("method", "")))
	var say := maker.say_of(name)
	var help := maker.help_of(name)
	if say == "":
		return help
	return say + ("\n" + help if help != "" else "")


func _add_block_help_icon(row:Container, node:Dictionary) -> void:
	var tip := _block_help_text(node)
	if tip == "":
		tip = "点击查看这块积木的说明。"
	var icon := Button.new()
	icon.name = "BlockHelp"
	icon.text = "ⓘ"
	icon.tooltip_text = tip
	icon.flat = true
	icon.focus_mode = Control.FOCUS_NONE
	icon.mouse_default_cursor_shape = Control.CURSOR_HELP
	icon.custom_minimum_size = Vector2(22, 22)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.add_theme_color_override("font_color", C_GOLD)
	icon.add_theme_color_override("font_hover_color", C_GOLD2)
	icon.add_theme_color_override("font_pressed_color", C_GOLD2)
	icon.add_theme_stylebox_override("hover", _flat(Color(0, 0, 0, 0.2), 8, 1))
	icon.pressed.connect(_show_help_for.bind(node))
	row.add_child(icon)


func _block_label(text:String) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_color_override("font_color", C_TEXT)
	lab.add_theme_font_size_override("font_size", 14)
	lab.mouse_filter = Control.MOUSE_FILTER_PASS
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return lab


func _label(text:String, size := 14, color := C_TEXT) -> Label:
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


func _welcome_card() -> Control:
	var lab := _hint("还没打开卡。左边选一张，或者点上面的「新建一张」。")
	return lab


func _fold_box(parent:Node, title:String, open:bool) -> VBoxContainer:
	var button := Button.new()
	button.text = ("▾ " if open else "▸ ") + title
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.flat = true
	button.add_theme_color_override("font_color", C_GOLD)
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


func _split_length(split:SplitContainer) -> float:
	return split.size.x if split is HSplitContainer else split.size.y


func _on_split_resized(split:SplitContainer) -> void:
	var total := _split_length(split)
	var previous_total := float(split.get_meta("layout_length", -1.0))
	var ratio := float(split.get_meta("ratio", 0.5))
	# 拖动分隔条时，子控件可能先发 resized，再发 dragged。此时总尺寸没变，
	# 但 split_offset 已经是鼠标拖到的位置；不要用旧比例把它覆盖回去。
	if total > 8 and is_equal_approx(previous_total, total):
		var expected := int(ratio * (total - 8.0))
		if abs(split.split_offset - expected) > 1:
			_remember_ratio(split)
			split.set_meta("layout_length", total)
			return
	_apply_ratio(split)
	split.set_meta("layout_length", total)


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
				var saved_ratio := float(cfg.get_value("ratio", split.name))
				# 旧默认值才跟着新的紧凑布局走；用户手动拖过的宽度仍按原值恢复。
				if split.name == "SplitOuter" and is_equal_approx(saved_ratio, 0.2):
					continue
				if split.name == "SplitPalette" and is_equal_approx(saved_ratio, 0.19):
					continue
				split.set_meta("ratio", saved_ratio)
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
		status.add_theme_color_override("font_color", C_TEXT)


# =============== 快捷键 ===============

func _input(event:InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if not (event.ctrl_pressed or event.meta_pressed) or save_dialog.visible or is_instance_valid(image_picker) or zip_dialog.visible:
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
	history.append({"data": data.duplicate(true) if data is Dictionary else null, "label": label, "where": where, "time": Time.get_ticks_msec(), "clock": Time.get_time_string_from_system(), "saved": saved})
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
	var snapshot = history[index].data
	data = snapshot.duplicate(true) if snapshot is Dictionary else null
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
			history_view.set_item_custom_fg_color(i, C_DIM2)   # 撤回掉的节点灰显，仍可点回去
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


func _on_export_kind_selected(index:int) -> void:
	_paint_export_form(str(export_kind_menu.get_item_metadata(index)))


func _on_export_reset() -> void:
	maker.reset_export(export_kind)
	_export_changed()
	_paint_export_form(export_kind)


# zip 默认目录：回车或离开时写进设置并存盘（与表单里的输入框同一套）。
func _on_zip_dir_submitted(text:String) -> void:
	var t := text.strip_edges()
	maker.set_export("_global", "zip_dir", t if t != "" else null)
	_export_changed()


func _on_zip_dir_focus_exited() -> void:
	_on_zip_dir_submitted(%ZipDirEdit.text)


func _on_zip_dir_pick() -> void:
	_pick_dir(%ZipDirEdit)


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
		export_form.add_child(_label("图片命名（不含扩展名）", 15, C_GOLD))
		var images:Dictionary = own.get("images", {})
		for img in fields.images:
			var key := str(img.key)
			_export_row(str(img.shown)).add_child(_export_line(str(images.get(key, "")), str(img.default), func(t): maker.set_export_image(item_id, key, t if t != "" else null)))
	_paint_export_preview()


func _export_row(title:String) -> HBoxContainer:
	var row := _titled_row(title)
	export_form.add_child(row)
	return row


# 左边一个定宽标题的一行，由调用方决定放在哪。
func _titled_row(title:String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name := _label(title, 14, C_TEXT)
	name.custom_minimum_size = Vector2(130, 0)
	row.add_child(name)
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
	b.pressed.connect(_pick_dir.bind(target))
	return b


func _pick_dir(target:LineEdit) -> void:
	dir_target = target
	var cur := target.text if target.text != "" else target.placeholder_text
	dir_dialog.current_dir = ProjectSettings.globalize_path(maker._res(cur))
	dir_dialog.popup_centered_ratio(0.6)


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


# =============== 新手教程 ===============
func _practice_save_blocked() -> bool:
	if tutorial_practice:
		_set_status("练习副本绝不保存 JSON 或打包。关闭教程后仍不可保存；可先恢复原稿，或普通打开/新建。")
		return true
	return false

func _leave_practice() -> void:
	if tutorial_practice:
		close_tutorial()
		tutorial_practice = false
		tutorial_previous.clear()

func restore_tutorial_previous() -> void:
	if tutorial_previous.is_empty():
		return
	var previous := tutorial_previous.duplicate(true)
	_leave_practice()
	data = previous.data
	path = str(previous.path)
	style = previous.style
	original = previous.original
	card_kind = str(previous.kind)
	dirty = bool(previous.dirty)
	focus_path = []
	focus_item = ""
	_load_effects()
	_refresh_all()
	_reset_history("恢复教程前原稿", not dirty)
	_set_status("已恢复教程前原稿" + ("（仍未保存）" if dirty else ""))

# 教程内容全在 json_maker/tutorials 里：这里只负责入口、显示、判定打勾和高亮控件。

# 入口：只有一套时直接打开，多套时弹菜单选。
func open_tutorial_menu() -> void:
	tutorials = maker.list_tutorials()
	if tutorials.is_empty():
		_set_status("没有找到教程：json_maker/tutorials 里放教程 json")
		return
	if tutorials.size() == 1:
		start_tutorial(0)
		return
	tutorial_menu.clear()
	for i in tutorials.size():
		tutorial_menu.add_item(str(tutorials[i].title), i)
	var button:Control = %TutorialButton
	tutorial_menu.popup(Rect2i(Vector2i(button.get_screen_position() + Vector2(0, button.size.y)), Vector2i.ZERO))


func _on_tutorial_menu_pressed(id:int) -> void:
	start_tutorial(id)


func start_tutorial(index:int) -> void:
	if index < 0 or index >= tutorials.size():
		return
	if not tutorial_practice:
		_commit()
		tutorial_previous = {"data": data.duplicate(true) if data != null else null, "path": path, "style": style.duplicate(true), "original": original.duplicate(true) if original != null else null, "kind": card_kind, "dirty": dirty}
		tutorial_practice = true
		path = ""
		style = {}
		original = null
		# 练习里的第一张卡留给你自己建：在种类里选好，再点「新建一张」，教程不代劳
		card_kind = kind_id
		data = null
		focus_path = []
		focus_item = ""
		history.clear()
		_load_effects()
		_refresh_all()
		dirty = false
		_reset_history("教程练习副本：还没新建", false)
	tutorial = tutorials[index].data
	tutorial_index = 0
	tutorial_panel.visible = true
	_show_help(str(tutorial.get("title", "新手教程")), str(tutorial.get("intro", "")))
	_paint_tutorial()
	_set_status("练习副本：不会写入 JSON，保存和打包均已禁用；教程前原稿已暂存。")


func close_tutorial() -> void:
	tutorial = {}
	tutorial_panel.visible = false
	_stop_tutorial_blink()
	if tutorial_practice:
		_set_status("练习副本仍不可保存。可恢复原稿，或普通打开/新建结束练习。")


func tutorial_prev() -> void:
	_go_tutorial_step(tutorial_index - 1)


func tutorial_next() -> void:
	var steps:Array = tutorial.get("steps", [])
	if tutorial_index >= steps.size() - 1:
		close_tutorial()
		_set_status("✓ 教程结束；练习副本不会写入 JSON，可恢复原稿或普通打开/新建。")
		return
	_go_tutorial_step(tutorial_index + 1)


func _go_tutorial_step(index:int) -> void:
	var steps:Array = tutorial.get("steps", [])
	if index < 0 or index >= steps.size():
		return
	tutorial_index = index
	_paint_tutorial()


# 界面状态：教程条件里 from: state 读这里。
func tutorial_state() -> Dictionary:
	return {
		"kind": card_kind if data != null else "",
		"focus": focus_item,
		"saved": data != null and not tutorial_practice and path != "" and not dirty and _collect_issues().is_empty(),
		"ready": data != null and _collect_issues().is_empty(),
		"path": path,
	}


# 当前这一步每条条件是否达成，按 checks 的顺序。
func tutorial_results() -> Array:
	var steps:Array = tutorial.get("steps", [])
	if tutorial_index < 0 or tutorial_index >= steps.size():
		return []
	var state := tutorial_state()
	var out:Array = []
	for check in steps[tutorial_index].get("checks", []):
		out.append(check is Dictionary and maker.tutorial_check(check, data, state))
	return out


func _paint_tutorial() -> void:
	var steps:Array = tutorial.get("steps", [])
	if steps.is_empty():
		return
	var step:Dictionary = steps[tutorial_index]
	tutorial_title.text = str(tutorial.get("title", "新手教程"))
	tutorial_step_label.text = "第 " + str(tutorial_index + 1) + " / " + str(steps.size()) + " 步：" + str(step.get("title", ""))
	var image := str(step.get("image", ""))
	var texture:Texture2D = LoadHelper.load_texture(image) if image != "" else null
	tutorial_image.texture = texture
	tutorial_image.visible = texture != null
	tutorial_body.text = str(step.get("body", ""))
	tutorial_prev_button.disabled = tutorial_index == 0
	tutorial_next_button.text = "完成" if tutorial_index == steps.size() - 1 else "下一步 ▶"
	_refresh_tutorial()
	_blink_tutorial_targets(step.get("highlight", []))


# 卡片改动或保存后重新打勾；全部达成时下一步按钮高亮。
func _refresh_tutorial() -> void:
	if tutorial.is_empty() or tutorial_checks == null:
		return
	var steps:Array = tutorial.get("steps", [])
	if tutorial_index >= steps.size():
		return
	var checks:Array = steps[tutorial_index].get("checks", [])
	var results := tutorial_results()
	_clear(tutorial_checks)
	for i in checks.size():
		var done:bool = results[i]
		var line := Label.new()
		line.text = ("✔ " if done else "○ ") + str(checks[i].get("text", ""))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_color_override("font_color", C_OK if done else HINT)
		tutorial_checks.add_child(line)
	var all_done := results.all(func(r): return r)
	tutorial_next_button.modulate = Color(0.75, 1.0, 0.75) if all_done and not checks.is_empty() else Color(1, 1, 1)


# 让这一步涉及的控件闪几下；控件用场景里的唯一名（%名字）指定，找不到就跳过。
func _blink_tutorial_targets(names:Array) -> void:
	_stop_tutorial_blink()
	var targets:Array = []
	for name in names:
		var node := get_node_or_null("%" + str(name))
		if node is CanvasItem:
			targets.append(node)
	if targets.is_empty():
		return
	tutorial_blink_targets = targets
	tutorial_blink = create_tween().set_loops(3)
	for target in targets:
		tutorial_blink.parallel().tween_property(target, "modulate", Color(1.0, 0.9, 0.45), 0.35)
	tutorial_blink.chain()
	for target in targets:
		tutorial_blink.parallel().tween_property(target, "modulate", Color(1, 1, 1), 0.35)
	tutorial_blink.finished.connect(_stop_tutorial_blink)


func _stop_tutorial_blink() -> void:
	if tutorial_blink != null and tutorial_blink.is_valid():
		tutorial_blink.kill()
	tutorial_blink = null
	for target in tutorial_blink_targets:
		if is_instance_valid(target):
			target.modulate = Color(1, 1, 1)
	tutorial_blink_targets = []


# 拖标题栏移动教程面板，限制在窗口内。
func _on_tutorial_header_input(event:InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		tutorial_drag = event.pressed
	elif event is InputEventMouseMotion and tutorial_drag:
		# 默认贴在右侧；拖过之后改成固定位置，免得窗口缩放时被锚点拉回去
		if tutorial_panel.anchor_left != 0.0:
			var rect := Rect2(tutorial_panel.position, tutorial_panel.size)
			tutorial_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
			tutorial_panel.position = rect.position
			tutorial_panel.size = rect.size
		var limit := size - tutorial_panel.size
		tutorial_panel.position = (tutorial_panel.position + event.relative).clamp(Vector2.ZERO, limit.max(Vector2.ZERO))
