class_name GetBuffByNameFrArr
extends RefCounted

func exec(buff_name:String, buffs:Array):

	var got_buffs:Array#[BaseBuff]
	for buff:BaseBuff in buffs:
		if buff._buff_name == buff_name:
			got_buffs.append(buff)
	if got_buffs.size() > 1:
		#show_check()
		pass
	else :
		for b in got_buffs:
			return b
