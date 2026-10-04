class_name GetMapAreaByName
extends RefCounted

#按区域名取地图区域。名字由调用方传入，不写死深山町/新都。
func exec(area_name:String):

	for area:BaseMapArea in MapData.areas:
		if area._area_name == area_name:
			return area
	return null
