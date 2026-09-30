extends Control

## 展开牌避开御主时保留原握持位置的命中区域；事件仍交给牌位原有 gui_input。
func _has_point(point: Vector2) -> bool:
	if Rect2(Vector2.ZERO, size).has_point(point):
		return true
	if not bool(get_meta("held_hovered", false)) or not has_meta("rest_position"):
		return false
	var parent_point := get_transform() * point
	var rest: Vector2 = get_meta("rest_position")
	var angle: float = get_meta("rest_rotation", 0.0)
	var rest_transform := Transform2D(angle, rest + pivot_offset)
	var local_point := rest_transform.affine_inverse() * parent_point + pivot_offset
	return Rect2(Vector2.ZERO, size).has_point(local_point)
