class_name GetEffectNumber
extends RefCounted

#按"效果名+下标"取出某个对象上某个效果自带的数字，用于修改别人卡面上的效果数值。
#下标只在单个效果内部有意义，所以给对象增删效果不会让这里的引用错位。
#object留空时取当前激活效果所属的卡牌
func exec(effect_name:String, index:int = 0, object:BaseObject = null):

	var target = object
	if target == null:
		target = GetEffSourceCard.new().exec()
	if target == null:
		return null
	return target.get_effect_number(effect_name, index)
