class_name Has
extends RefCounted

func exec(parent_var, children_var, key = null):

	if parent_var is Array:
		if parent_var.find(children_var) != -1:
			return true
		else :
			return false
			
	if parent_var is Dictionary:
		if key == null:
			 #show("请输入字典的键")
			return
		if parent_var[key] is Array:
			var array:Array = parent_var[key]
			array.find(children_var)
		if parent_var[key] is Dictionary:
			var dic:Dictionary = parent_var[key]
			if dic.has(children_var):
				return true
			else :
				return false


#循环
