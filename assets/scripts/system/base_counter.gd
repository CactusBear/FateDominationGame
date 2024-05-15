extends BaseObject
class_name BaseCounter


var _is_active:bool
var _num:BaseNumber

func _init(counter_name:String, is_active:bool = false, num:BaseNumber = BaseNumber.new(0)):
	_name = counter_name
	_is_active = is_active
	_num = num

func add(num:BaseNumber = BaseNumber.new(1)):
	_num.add(num)

func minus(num:BaseNumber = BaseNumber.new(1)):
	_num.minus(num)

func set_num(num:BaseNumber = BaseNumber.new(0)):
	_num.set_num(num)
