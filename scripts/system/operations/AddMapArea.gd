class_name AddMapArea
extends RefCounted

#按数据新增一个战区并接进地图（深空、阿里芒戈岛、宅邸……）。
#area_data 的格式与御主 JSON 里 specials.MAP_AREAS 的单项相同（area_name/score/move_cost/can_deploy/locations/
#linked_map_area_name），建区复用 LoadGame.load_map_areas，字段含义与读文件时一致。
#接线：link_to 为新战区往前指向的战区（空则按数据里的 linked_map_area_name 查找）；
#link_from 为改为指向新战区的那个战区（空则不改任何旧箭头）。改箭头只动 _linked_map_area，
#其它连接关系（费用、能否进入）由调用方再用 edit_map_area_move_cost / set_map_area_can_move_to 组合。
#新战区追加到 MapData.areas 末尾。返回新战区，建不出时返回 null
func exec(area_data:Dictionary, link_from:BaseMapArea = null, link_to:BaseMapArea = null):

	if area_data == null or area_data.is_empty():
		return null
	var data:Dictionary = area_data.duplicate(true)
	var areas:Array = LoadGame.load_map_areas([data], _owner())
	if areas.is_empty():
		return null
	var area:BaseMapArea = areas[0]
	#BaseMapArea 构造时会自己登记进 MapData.areas，这里只补上没登记的情况
	if !MapData.areas.has(area):
		MapData.areas.append(area)
	for loc in area._locations:
		if loc is BaseLocation:
			loc.from = area
	if link_to == null:
		link_to = GetMapAreaByName.new().exec(str(data.get("linked_map_area_name", "")))
	if link_to != null and link_to != area:
		area._linked_map_area = link_to
	if link_from != null and link_from != area:
		link_from._linked_map_area = area
	return area


#新战区归属：发动这条效果的对象
func _owner():
	var eff = EffectManager.activating_eff
	return eff.from if eff != null else null
