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
			return parent_var.has(children_var)
		if !parent_var.has(key):
			return false
		if parent_var[key] is Array:
			return (parent_var[key] as Array).has(children_var)
		if parent_var[key] is Dictionary:
			return (parent_var[key] as Dictionary).has(children_var)
		return parent_var[key] == children_var
	return false


#循环
