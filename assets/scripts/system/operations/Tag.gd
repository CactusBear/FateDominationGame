class_name Tag
extends RefCounted

func exec(tag_name:String, from_pl_id:int):

	var tag = {
		"tag_name" : tag_name,
		"from" : from_pl_id
	}
	return tag
