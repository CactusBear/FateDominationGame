extends Node
class_name BaseNumber


var number
var is_float:bool
var can_change:bool



func _init(_number, _can_change:bool = true):
	if _number is int:
		number = _number
		is_float = false
	elif _number is float:
		number = _number
		is_float = true
	can_change = _can_change



func add(num:BaseNumber) -> BaseNumber:
	if !can_change:
		#show("此数字不可被更改")
		return
	number += num.number
	return self
	
func minus(num:BaseNumber) -> BaseNumber:
	if !can_change:
		#show("此数字不可被更改")
		return
	number -= num.number
	return self

func multiply(num:BaseNumber) -> BaseNumber:
	if !can_change:
		#show("此数字不可被更改")
		return
	number *= num.number
	return self

func divide(num:BaseNumber) -> BaseNumber:
	if !can_change:
		#show("此数字不可被更改")
		return
	number /= num.number
	return self

func set_num(num:BaseNumber) -> BaseNumber:
	if !can_change:
		#show("此数字不可被更改")
		return
	number = num.number
	return self
