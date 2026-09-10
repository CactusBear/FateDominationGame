extends BaseObject
class_name BaseServant


var _shown_servant_name:String
#职阶(如saber)，只存内部值，显示名交给界面层查表
var _servant_class:String
var _header_img:String
var _servant_card_img:String
var _effects:Array
var _specials:Dictionary


func _init(servant_name:String, shown_servant_name:String, servant_class:String, header_img:String, servant_card_img:String):
	_name = servant_name
	_shown_servant_name = shown_servant_name
	_servant_class = servant_class
	_header_img = header_img
	_servant_card_img = servant_card_img
	_effects = []
	_specials = {}

	super.add_object()
