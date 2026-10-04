class_name SetMapAreaCanMoveTo
extends RefCounted

#改战区的"能否常规进入"开关，并在此区第一次被改时记下印刷基线。
#_can_move_to 的印刷值(_printed_can_move_to)是地图数据声明的事实，
#局势牌(如身处地狱之门/天之杯"无法进入某区")回合结束弃置时由
#RestoreMapAreaMoveFlags 按基线恢复。只记录一次：连续多张局势牌同回合叠加改动时，
#基线始终是改动前的原值，弃置后一次性还原
func exec(map_area:BaseMapArea, value:bool = true):

	if map_area == null:
		return
	if map_area._printed_can_move_to == null:
		map_area._printed_can_move_to = map_area._can_move_to
	map_area._can_move_to = value
