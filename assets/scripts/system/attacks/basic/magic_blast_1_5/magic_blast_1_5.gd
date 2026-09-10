extends BaseAttack
class_name MagicBlast15


func _init():
	super("magic_blast_1_5", "res://assets/scripts/system/attacks/basic/magic_blast_1_5/magic_blast_1_5.png", ["magic"], BaseNumber.new(1), BaseNumber.new(5))
	_category = BaseAttack.CATEGORY_BASIC
	_shown_name = "超高位魔术"
