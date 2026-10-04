class_name GetCardsByTagFrArr
extends RefCounted

#从给定数组里按tag_name筛对象。GetByTag扫的是全局objects且整份字典相等，
#这里只比tag_name，并且只看传入数组，供"基础攻击"等标记复用。
func exec(tag_name:String, objects:Array) -> Array:

	var got:Array = []
	if objects == null or tag_name == "":
		return got
	for object in objects:
		if !(object is BaseObject):
			continue
		for tag in object.tags:
			if tag is Dictionary and tag.get("tag_name", "") == tag_name:
				got.append(object)
				break
			if tag is Dictionary and tag.get("tag", "") == tag_name:
				got.append(object)
				break
	return got
