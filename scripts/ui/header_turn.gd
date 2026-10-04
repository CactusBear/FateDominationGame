extends Node2D


@onready var header = $Header
@onready var header_cover = $HeaderCover
@onready var header_button = $HeaderButton

var norm_tex = preload("res://assets/images/ui/header/header_overlap_norm.png")
var hover_tex = preload("res://assets/images/ui/header/header_overlap_hover.png")
var pressed_tex = preload("res://assets/images/ui/header/header_overlap_pressed.png")
var disabled_tex = preload("res://assets/images/ui/header/header_overlap_disabled.png")

var _pic_path:String = "res://assets/images/masters/headers/emiya_shirou/emiya_shirou_norm.png"
var on_hover:bool = false

#func _init(pic_path):
	#_pic_path = pic_path


func _ready():
	header.texture = load(_pic_path)
	header_cover.position = Vector2(-17, 6)
	header_cover.size = Vector2(323, 278)
	header_cover.texture = norm_tex
	


func _on_header_button_mouse_entered():
	header_cover.texture = hover_tex
	header_cover.position = Vector2(-36, -12)
	header_cover.size = Vector2(436, 331)
	on_hover = true


func _on_header_button_mouse_exited():
	header_cover.texture = norm_tex
	header_cover.position = Vector2(-17, 6)
	header_cover.size = Vector2(323, 278)
	on_hover = false



func _on_header_button_button_down():
	header_cover.texture = pressed_tex
	header_cover.position = Vector2(-49, 2)
	header_cover.size = Vector2(436, 295)


func _on_header_button_button_up():
	if on_hover == true:
		header_cover.texture = hover_tex
		header_cover.position = Vector2(-35, -11)
		header_cover.size = Vector2(436, 331)
	else :
		header_cover.texture = norm_tex
		header_cover.position = Vector2(-17, 6)
		header_cover.size = Vector2(323, 278)
