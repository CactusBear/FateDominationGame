extends TextureButton

@export var player_id = 0
@export var player_name = "null_name"
@export var master_name = "emiya_shirou"
@export var header_pic_norm = "res://assets/images/masters/headers/emiya_shirou/emiya_shirou_norm.png"
@export var header_pic_hover = "res://assets/images/masters/headers/emiya_shirou/emiya_shirou_hover.png"
@export var header_pic_pressed = "res://assets/images/masters/headers/emiya_shirou/emiya_shirou_pressed.png"
@export var header_pic_disabled = "res://assets/images/masters/headers/emiya_shirou/emiya_shirou_disabled.png"

# Called when the node enters the scene tree for the first time.
func _ready():
	header_pic_setter(master_name)
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func header_pic_setter(master_name:String):
	header_pic_norm = "res://assets/images/masters/headers/" + master_name + "/" + master_name + "_norm.png"
	header_pic_hover = "res://assets/images/masters/headers/" + master_name + "/" + master_name + "_hover.png"
	header_pic_pressed = "res://assets/images/masters/headers/" + master_name + "/" +  master_name + "_pressed.png"
	header_pic_disabled = "res://assets/images/masters/headers/" + master_name + "/" +  master_name + "_disabled.png"
	self.texture_normal = load(header_pic_norm)
	self.texture_hover = load(header_pic_hover)
	self.texture_pressed = load(header_pic_pressed)
	self.texture_disabled = load(header_pic_disabled)

func header_data_setter(player_id:String):
	pass


func _on_mouse_entered():
	pass # Replace with function body.


func _on_mouse_exited():
	pass # Replace with function body.
