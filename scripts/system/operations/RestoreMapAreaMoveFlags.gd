class_name RestoreMapAreaMoveFlags
extends RefCounted

#把所有战区的"能否常规进入"恢复到印刷基线。局势牌弃置时调用——
#局势牌效果(如"无法进入新都")只在本回合有效，回合结束必须还原，
#否则一个回合的封区会永久生效。没有基线(从未被改过)的区域不动
func exec():

	for area:BaseMapArea in MapData.areas:
		if area._printed_can_move_to != null:
			area._can_move_to = area._printed_can_move_to
			area._printed_can_move_to = null
