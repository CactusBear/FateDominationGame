extends Node


var regex:RegEx = RegEx.new()

@onready var master_name_nd = $MasterBaseInfo/MasterName as LineEdit
@onready var shown_master_name_nd = $MasterBaseInfo/ShownMasterName as LineEdit
@onready var header_img_nd = $MasterBaseInfo/HeaderImg as LineEdit
@onready var master_card_img_nd = $MasterBaseInfo/MasterCardImg as LineEdit
@onready var command_spell_img_nd = $MasterBaseInfo/CommandSpellImg as LineEdit

@onready var header_dialog = $MasterBaseInfo/HeaderImg/TextureButton/FileDialog
@onready var master_card_dialog = $MasterBaseInfo/MasterCardImg/TextureButton/FileDialog
@onready var command_spell_dialog = $MasterBaseInfo/CommandSpellImg/TextureButton/FileDialog


@onready var effect_editor_nd =  $EffectEditor
@onready var effect_base_info_nd = $EffectEditor/AddEffect/EffectBaseInfo
@onready var time_point_panel_nd = $EffectEditor/AddEffect/EffectBaseInfo/BackGround/HBoxContainer/Button/TimePointPanel


var master_name:String
var shown_master_name:String
var header_img_path:String
var header_img:Texture2D
var header_img_name:String
var master_card_img_path:String
var master_card_img:Texture2D
var master_card_img_name:String
var command_spell_img_path:String
var command_spell_img:Texture2D
var command_spell_img_name:String


func _show_header_dialog():
	header_dialog.show()
func _header_selected(path):
	header_img_path = path
	header_img = load(path)
	header_img_name = header_dialog.current_file
	header_img_nd.text = header_img_name

func _show_master_card_dialog():
	master_card_dialog.show()
func _master_card_selected(path):
	master_card_img_path = path
	master_card_img = load(path)
	master_card_img_name = master_card_dialog.current_file
	master_card_img_nd.text = master_card_img_name

func _show_command_spell_dialog():
	command_spell_dialog.show()
func _command_spell_selected(path):
	command_spell_img_path = path
	command_spell_img = load(path)
	command_spell_img_name = command_spell_dialog.current_file
	command_spell_img_nd.text = command_spell_img_name

func _write_base_info():
	regex.compile(r'^\w+$')
	master_name = master_name_nd.text
	shown_master_name = shown_master_name_nd.text
	
	if regex.search(master_name) == null or regex.search(master_name).get_string() != master_name:
		OS.alert("御主名格式错误！")
		return
	if shown_master_name == null:
		OS.alert("请输入御主显示名称！")
		return
	if header_img_path == null:
		OS.alert("请选择头像！")
		return
	if header_img.get_height() != header_img.get_width():
		OS.alert("请保持头像图片宽高比为1:1！")
		return
	if master_card_img_path == null:
		OS.alert("请选择御主卡面！")
		return
	if command_spell_img_path == null:
		OS.alert("请选择令咒卡面！")
		return
	
	effect_editor_nd.show()
	

func _show_add_effect():
	effect_base_info_nd.show()

func _show_add_time_point():
	time_point_panel_nd.show()
