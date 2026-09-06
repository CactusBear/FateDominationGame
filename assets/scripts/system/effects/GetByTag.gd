class_name GetByTag
extends RefCounted

func exec(tag:Dictionary):

	var objects:Array
	for object in GameData.objects:
		for t:Dictionary in object.tags:
			if t == tag:
				objects.append(object)
	return objects
