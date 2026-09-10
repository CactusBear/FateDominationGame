class_name AddSituatiuons
extends RefCounted

func exec(add_situation:BaseSituation):

	var situation_arr = MapData.situations as Array
	situation_arr.append(add_situation)
