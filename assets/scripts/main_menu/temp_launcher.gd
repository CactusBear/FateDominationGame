extends Control

## 临时启动台：用于分别进入主游戏与卡牌效果编辑器（json_maker）。
## 只做一件事——列出入口并切换场景；不含游戏规则、数据加载和界面美化。
## 增加或调整入口只改下面的 ENTRIES 声明，不要把场景路径写进按钮回调里。

## 入口声明：label 是按钮文字，scene 是要切换到的场景（res:// 路径）。
## 数组顺序即显示顺序；声明为空时界面只剩提示行，不会报错。
const ENTRIES: Array = [
	{"label": "主游戏", "scene": "res://assets/scenes/game_scene/tactical_board_ui.tscn"},
	{"label": "卡牌效果编辑器", "scene": "res://json_maker/json_maker.tscn"},
]

## 按钮统一最小尺寸：只保证点得到，与视觉效果无关
const ENTRY_BUTTON_MIN_SIZE := Vector2(320, 56)

@onready var _entry_box: VBoxContainer = $CenterContainer/VBox/EntryBox
@onready var _status_label: Label = $CenterContainer/VBox/StatusLabel


func _ready() -> void:
	_build_entries()
	_status_label.text = "临时启动台：选择一项进入"


## 按声明逐个建按钮；场景路径无效的入口保留按钮但禁用，避免“点了没反应”这种静默失败
func _build_entries() -> void:
	for entry in ENTRIES:
		_entry_box.add_child(_make_entry_button(entry))


func _make_entry_button(entry:Dictionary) -> Button:
	var scene_path := str(entry.get("scene", ""))
	var button := Button.new()
	button.text = str(entry.get("label", scene_path))
	button.custom_minimum_size = ENTRY_BUTTON_MIN_SIZE
	if !_scene_path_available(scene_path):
		button.disabled = true
		button.tooltip_text = "找不到场景：" + scene_path
		button.text += "（缺少场景）"
	button.pressed.connect(_on_entry_pressed.bind(scene_path))
	return button


func _scene_path_available(scene_path:String) -> bool:
	return scene_path != "" and ResourceLoader.exists(scene_path, "PackedScene")


func _on_entry_pressed(scene_path:String) -> void:
	var err:Error = get_tree().change_scene_to_file(scene_path)
	# 切换在本帧末才落地：成功时脚本已经被换掉、不会再回到这里，因此只有失败才需要报出来
	if err != OK:
		_status_label.text = "切换到 %s 失败（错误码 %d）" % [scene_path, err]
