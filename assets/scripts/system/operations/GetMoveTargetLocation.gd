class_name GetMoveTargetLocation
extends RefCounted


#取某战区"常规移动"的落点：区域内第一个标了 _will_move_to、且还有空位的点位。
#没有这样的点位（落点已满、或该战区不提供常规移动落点）时返回 null。
#常规移动的落点规则只在这一处实现：真正落位(MoveLocation)与界面"能不能移过去"的提示
#共用它，避免两处各写一套出现"看起来能点、点下去不动"。
#ignore_limit=true 表示忽略落点人数上限，与 SetLocation 的同名开关同义
func exec(target_area:BaseMapArea, ignore_limit:bool = false):
	if target_area == null:
		return null
	for loc:BaseLocation in target_area._locations:
		if !loc._will_move_to:
			continue
		if ignore_limit or loc._pl_num_limit == -1 or loc._players.size() < loc._pl_num_limit:
			return loc
	return null
