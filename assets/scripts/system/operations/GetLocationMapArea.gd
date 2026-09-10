class_name GetLocationMapArea
extends RefCounted

#由地点反查所属地图区域。多处规则都要做location->area，抽成查询以免各写一遍循环。
#location留空时取当前玩家所在地点。
func exec(location:BaseLocation = null, player_id:int = -1):

	var loc = location
	if loc == null:
		loc = GetLocation.new().exec(player_id)
	if loc == null:
		return null
	for area:BaseMapArea in MapData.areas:
		if area._locations.has(loc):
			return area
	return null
