extends Node
class_name FuncTable



var funcs:Dictionary


func _init():
	for f in EffectLib.new().get_method_list():
		var key = f["name"]
		var _func = Callable(EffectLib, key)
		funcs[key] = _func
