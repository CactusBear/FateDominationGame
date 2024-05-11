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

@onready var time_point_nd = preload("res://assets/scenes/editor/time_point.tscn").instantiate().duplicate()
@onready var tp_countainer = $EffectEditor/AddEffect/EffectBaseInfo/BackGround/HBoxContainer

@onready var tp_game_opbutton = $EffectEditor/AddEffect/EffectBaseInfo/BackGround/HBoxContainer/Button/TimePointPanel/BackGround/Game/OptionButton as OptionButton
@onready var tp_day_opbutton = $EffectEditor/AddEffect/EffectBaseInfo/BackGround/HBoxContainer/Button/TimePointPanel/BackGround/Day/OptionButton as OptionButton
@onready var tp_phase_opbutton = $EffectEditor/AddEffect/EffectBaseInfo/BackGround/HBoxContainer/Button/TimePointPanel/BackGround/Phase/OptionButton as OptionButton
@onready var tp_prepare_phase_opbutton = $EffectEditor/AddEffect/EffectBaseInfo/BackGround/HBoxContainer/Button/TimePointPanel/BackGround/PreparePhase/OptionButton as OptionButton
@onready var tp_outpost_phase_opbutton = $EffectEditor/AddEffect/EffectBaseInfo/BackGround/HBoxContainer/Button/TimePointPanel/BackGround/OutpostPhase/OptionButton as OptionButton
@onready var tp_action_phase_opbutton = $EffectEditor/AddEffect/EffectBaseInfo/BackGround/HBoxContainer/Button/TimePointPanel/BackGround/ActionPhase/OptionButton as OptionButton
@onready var tp_battle_phase_opbutton = $EffectEditor/AddEffect/EffectBaseInfo/BackGround/HBoxContainer/Button/TimePointPanel/BackGround/BattlePhase/OptionButton as OptionButton
@onready var tp_events1_opbutton = $EffectEditor/AddEffect/EffectBaseInfo/BackGround/HBoxContainer/Button/TimePointPanel/BackGround/Events1/OptionButton as OptionButton
@onready var tp_events2_opbutton = $EffectEditor/AddEffect/EffectBaseInfo/BackGround/HBoxContainer/Button/TimePointPanel/BackGround/Events2/OptionButton as OptionButton



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

var time_points:Array#[String]

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
	
func add_time_point(time_point:String, text:String):
	var tpnd = time_point_nd.duplicate() as LineEdit
	tpnd.text = text
	time_points.append(time_point)
	tp_countainer.add_child(tpnd)
	tp_countainer.move_child(tpnd, -2)
	time_point_panel_nd.hide()
	pass

func _on_add_time_point_game():
	var id = tp_game_opbutton.get_selected_id()
	var time_point:String
	match  id:
		0:
			time_point = TimePoints.GAME_START
		1:
			time_point = TimePoints.GAME
		2:
			time_point = TimePoints.GAME_END
	
	add_time_point(time_point, tp_game_opbutton.get_item_text(id))
	

func _on_add_time_point_day():
	var id = tp_day_opbutton.get_selected_id()
	var time_point:String
	match  id:
		0:
			time_point = TimePoints.DAY_START
		1:
			time_point = TimePoints.DAY
		2:
			time_point = TimePoints.DAY_END
			
	add_time_point(time_point, tp_day_opbutton.get_item_text(id))
			
func _on_add_time_point_phase():
	var id = tp_phase_opbutton.get_selected_id()
	var time_point:String
	match  id:
		0:
			time_point = TimePoints.PHASE_START
		1:
			time_point = TimePoints.PHASE
		2:
			time_point = TimePoints.PHASE_END
	
	add_time_point(time_point, tp_phase_opbutton.get_item_text(id))
	
			
func _on_add_time_point_prepare_phase():
	var id = tp_prepare_phase_opbutton.get_selected_id()
	var time_point:String
	match  id:
		0:
			time_point = TimePoints.PREPARE_PHASE_START
		1:
			time_point = TimePoints.SELF_PREPARE_PHASE_START
		2:
			time_point = TimePoints.OTHERS_PREPARE_PHASE_START
		3:
			time_point = TimePoints.PREPARE_PHASE
		4:
			time_point = TimePoints.SELF_PREPARE_PHASE
		5:
			time_point = TimePoints.OTHERS_PREPARE_PHASE
		6:
			time_point = TimePoints.PREPARE_PHASE_END
		7:  
			time_point = TimePoints.SELF_PREPARE_PHASE_END
		8:
			time_point = TimePoints.OTHERS_PREPARE_PHASE_END
	
	add_time_point(time_point, tp_prepare_phase_opbutton.get_item_text(id))
	
			
func _on_add_time_point_outpost_phase():
	var id = tp_outpost_phase_opbutton.get_selected_id()
	var time_point:String
	match  id:
		0:
			time_point = TimePoints.OUTPOST_PHASE_START
		1:
			time_point = TimePoints.SELF_OUTPOST_PHASE_START
		2:
			time_point = TimePoints.OTHERS_OUTPOST_PHASE_START
		3:
			time_point = TimePoints.OUTPOST_PHASE
		4:
			time_point = TimePoints.SELF_OUTPOST_PHASE
		5:
			time_point = TimePoints.OTHERS_OUTPOST_PHASE
		6:
			time_point = TimePoints.OUTPOST_PHASE_END
		7:  
			time_point = TimePoints.SELF_OUTPOST_PHASE_END
		8:
			time_point = TimePoints.OTHERS_OUTPOST_PHASE_END
	
	add_time_point(time_point, tp_outpost_phase_opbutton.get_item_text(id))
	
			
func _on_add_time_point_action_phase():
	var id = tp_action_phase_opbutton.get_selected_id()
	var time_point:String
	match  id:
		0:
			time_point = TimePoints.ACTION_PHASE_START
		1:
			time_point = TimePoints.SELF_ACTION_PHASE_START
		2:
			time_point = TimePoints.OTHERS_ACTION_PHASE_START
		3:
			time_point = TimePoints.ACTION_PHASE
		4:
			time_point = TimePoints.SELF_ACTION_PHASE
		5:
			time_point = TimePoints.OTHERS_ACTION_PHASE
		6:
			time_point = TimePoints.ACTION_PHASE_END
		7:  
			time_point = TimePoints.SELF_ACTION_PHASE_END
		8:
			time_point = TimePoints.OTHERS_ACTION_PHASE_END
	
	add_time_point(time_point, tp_action_phase_opbutton.get_item_text(id))
	
			
func _on_add_time_point_battle_phase():
	var id = tp_battle_phase_opbutton.get_selected_id()
	var time_point:String
	match  id:
		0:
			time_point = TimePoints.BATTLE_PHASE_START
		1:
			time_point = TimePoints.SELF_BATTLE_PHASE_START
		2:
			time_point = TimePoints.OTHERS_BATTLE_PHASE_START
		3:
			time_point = TimePoints.BATTLE_PHASE
		4:
			time_point = TimePoints.SELF_BATTLE_PHASE
		5:
			time_point = TimePoints.OTHERS_BATTLE_PHASE
		6:
			time_point = TimePoints.BATTLE_PHASE_END
		7:  
			time_point = TimePoints.SELF_BATTLE_PHASE_END
		8:
			time_point = TimePoints.OTHERS_BATTLE_PHASE_END
	
	add_time_point(time_point, tp_battle_phase_opbutton.get_item_text(id))
	
			
func _on_add_time_point_events1():
	var id = tp_events1_opbutton.get_selected_id()
	var time_point:String
	match  id:
		0:
			time_point = TimePoints.PLAYED_CRAD
		1:
			time_point = TimePoints.SELF_PLAYED_CRAD
		2:
			time_point = TimePoints.OTHERS_PLAYED_CRAD
		3:
			time_point = TimePoints.MAGIC_ADD
		4:
			time_point = TimePoints.SELF_MAGIC_ADD
		5:
			time_point = TimePoints.OTHERS_MAGIC_ADD
		6:
			time_point = TimePoints.MAGIC_DECREASE
		7:  
			time_point = TimePoints.SELF_MAGIC_DECREASE
		8:
			time_point = TimePoints.OTHERS_MAGIC_DECREASE
		9:
			time_point = TimePoints.SCORE_ADD
		10:
			time_point = TimePoints.SELF_SCORE_ADD
		11:
			time_point = TimePoints.OTHERS_SCORE_ADD
		12:
			time_point = TimePoints.SCORE_DECREASE
		13:  
			time_point = TimePoints.SELF_SCORE_DECREASE
		14:
			time_point = TimePoints.OTHERS_SCORE_DECREASE
		15:
			time_point = TimePoints.MOVE_START
		16:
			time_point = TimePoints.SELF_MOVE_START
		17:
			time_point = TimePoints.OTHERS_MOVE_START
		18:
			time_point = TimePoints.MOVE
		19:
			time_point = TimePoints.SELF_MOVE
		20:
			time_point = TimePoints.OTHERS_MOVE
		21:
			time_point = TimePoints.MOVE_END
		22:
			time_point = TimePoints.SELF_MOVE_END
		23:
			time_point = TimePoints.OTHERS_MOVE_END
	
	add_time_point(time_point, tp_events1_opbutton.get_item_text(id))
	
			
func _on_add_time_point_events2():
	var id = tp_events2_opbutton.get_selected_id()
	var time_point:String
	match  id:
		0:
			time_point = TimePoints.BATTLE_WIN
		1:
			time_point = TimePoints.SELF_BATTLE_WIN
		2:
			time_point = TimePoints.OTHERS_BATTLE_WIN
		3:
			time_point = TimePoints.BATTLE
		4:
			time_point = TimePoints.SELF_BATTLE
		5:
			time_point = TimePoints.OTHERS_BATTLE
		6:
			time_point = TimePoints.BATTLE_LOSE
		7:  
			time_point = TimePoints.SELF_BATTLE_LOSE
		8:
			time_point = TimePoints.OTHERS_BATTLE_LOSE
		9:
			time_point = TimePoints.DEPLOY_START
		10:
			time_point = TimePoints.SELF_DEPLOY_START
		11:
			time_point = TimePoints.OTHERS_DEPLOY_START
		12:
			time_point = TimePoints.DEPLOY
		13:  
			time_point = TimePoints.SELF_DEPLOY
		14:
			time_point = TimePoints.OTHERS_DEPLOY
		15:
			time_point = TimePoints.DEPLOY_END
		16:
			time_point = TimePoints.SELF_DEPLOY_END
		17:
			time_point = TimePoints.OTHERS_DEPLOY_END
		18:
			time_point = TimePoints.EFFECT_START
		19:
			time_point = TimePoints.SELF_EFFECT_START
		20:
			time_point = TimePoints.OTHERS_EFFECT_START
		21:
			time_point = TimePoints.EFFECT_END
		22:
			time_point = TimePoints.SELF_EFFECT_END
		23:
			time_point = TimePoints.OTHERS_EFFECT_END
		24:
			time_point = TimePoints.BUFF_START
		25:
			time_point = TimePoints.SELF_BUFF_START
		26:
			time_point = TimePoints.OTHERS_BUFF_START
		27:
			time_point = TimePoints.BUFF
		28:
			time_point = TimePoints.SELF_BUFF
		29:
			time_point = TimePoints.OTHERS_BUFF
		30:
			time_point = TimePoints.BUFF_END
		31:
			time_point = TimePoints.SELF_BUFF_END
		32:
			time_point = TimePoints.OTHERS_BUFF_END
	
	add_time_point(time_point, tp_events2_opbutton.get_item_text(id))
	
