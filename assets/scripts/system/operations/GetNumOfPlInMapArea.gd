class_name GetNumOfPlInMapArea
extends RefCounted

func exec(map_area:BaseMapArea):

	var count:int = 0
	for loc:BaseLocation in map_area._locations:
		for pl in loc._players:
			count += 1
	return count
