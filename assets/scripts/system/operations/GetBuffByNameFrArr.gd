class_name GetBuffByNameFrArr
extends RefCounted

func exec(buff_name:String, buffs:Array) -> Array:

	var got_buffs:Array = []
	if buffs == null:
		return got_buffs
	for buff in buffs:
		if buff is BaseBuff and buff._name == buff_name:
			got_buffs.append(buff)
	return got_buffs
