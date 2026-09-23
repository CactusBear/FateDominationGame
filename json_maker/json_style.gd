extends StyleBox

# 积木外形。只画形状，不管内容。
# shape: stack 普通积木（上凹口下凸起）、hat 帽子积木（圆顶，下凸起）、
#        reporter 圆角胶囊、boolean 六边形、c_top / c_bottom C 形积木的上下两截、slot 空位、empty 空着的空位
var shape := "stack"
var fill := Color(0.3, 0.5, 0.9)
var border := Color(0.2, 0.35, 0.7)
var highlight := false   # 空位里必填却没填时画黄框

const NOTCH_X := 14.0
const NOTCH_W := 16.0
const NOTCH_D := 4.0
const R := 5.0


func _init(p_shape := "stack", p_fill := Color(0.3, 0.5, 0.9)) -> void:
	shape = p_shape
	fill = p_fill
	border = p_fill.darkened(0.25)
	match shape:
		"reporter", "slot", "empty":
			content_margin_left = 8
			content_margin_right = 8
			content_margin_top = 3
			content_margin_bottom = 3
		"boolean":
			content_margin_left = 14
			content_margin_right = 14
			content_margin_top = 3
			content_margin_bottom = 3
		"hat":
			content_margin_left = 10
			content_margin_right = 12
			content_margin_top = 18
			content_margin_bottom = 8
		_:
			content_margin_left = 10
			content_margin_right = 12
			content_margin_top = 6
			content_margin_bottom = 8


func _draw(item:RID, rect:Rect2) -> void:
	if rect.size.x < NOTCH_X + NOTCH_W + R * 2 + 4 or rect.size.y < NOTCH_D * 2 + R * 2:
		# 布局还没算好或太小：画个普通圆角块，避免多边形自交
		RenderingServer.canvas_item_add_rect(item, rect, fill)
		return
	var pts := _clean(_outline(rect))
	if Geometry2D.triangulate_polygon(pts).is_empty():
		RenderingServer.canvas_item_add_rect(item, rect, fill)
		return
	RenderingServer.canvas_item_add_polygon(item, pts, PackedColorArray([fill]))
	var closed := pts.duplicate()
	closed.append(pts[0])
	var line := Color(1, 0.85, 0.2) if highlight else border
	RenderingServer.canvas_item_add_polyline(item, closed, PackedColorArray([line]), 2.0 if highlight else 1.0, true)


func _outline(r:Rect2) -> PackedVector2Array:
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	var p := PackedVector2Array()
	match shape:
		"reporter", "slot", "empty":
			var rr := minf(r.size.y * 0.5, 12.0)
			_arc(p, Vector2(x0 + rr, y0 + rr), rr, PI, PI * 1.5)
			_arc(p, Vector2(x1 - rr, y0 + rr), rr, PI * 1.5, TAU)
			_arc(p, Vector2(x1 - rr, y1 - rr), rr, 0, PI * 0.5)
			_arc(p, Vector2(x0 + rr, y1 - rr), rr, PI * 0.5, PI)
		"boolean":
			var h := r.size.y * 0.5
			p.append(Vector2(x0, y0 + h))
			p.append(Vector2(x0 + h, y0))
			p.append(Vector2(x1 - h, y0))
			p.append(Vector2(x1, y0 + h))
			p.append(Vector2(x1 - h, y1))
			p.append(Vector2(x0 + h, y1))
		"hat":
			var top := y0 + 12.0
			var w := minf(80.0, r.size.x - R * 2 - 2)
			p.append(Vector2(x0, top))
			_curve(p, Vector2(x0, top), Vector2(x0 + w * 0.5, y0 - 4), Vector2(x0 + w, top))
			p.append(Vector2(x1 - R, top))
			_arc(p, Vector2(x1 - R, top + R), R, PI * 1.5, TAU)
			_bottom(p, x0, x1, y1 - NOTCH_D, true)
		"c_bottom":
			_top(p, x0, x1, y0, false)
			_bottom(p, x0, x1, y1 - NOTCH_D, true)
		_:
			_top(p, x0, x1, y0, true)
			_bottom(p, x0, x1, y1 - NOTCH_D, true)
	return p


func _top(p:PackedVector2Array, x0:float, x1:float, y:float, notch:bool) -> void:
	_arc(p, Vector2(x0 + R, y + R), R, PI, PI * 1.5)
	if notch:
		p.append(Vector2(x0 + NOTCH_X, y))
		p.append(Vector2(x0 + NOTCH_X + 4, y + NOTCH_D))
		p.append(Vector2(x0 + NOTCH_X + NOTCH_W - 4, y + NOTCH_D))
		p.append(Vector2(x0 + NOTCH_X + NOTCH_W, y))
	_arc(p, Vector2(x1 - R, y + R), R, PI * 1.5, TAU)


func _bottom(p:PackedVector2Array, x0:float, x1:float, y:float, bump:bool) -> void:
	_arc(p, Vector2(x1 - R, y - R), R, 0, PI * 0.5)
	if bump:
		p.append(Vector2(x0 + NOTCH_X + NOTCH_W, y))
		p.append(Vector2(x0 + NOTCH_X + NOTCH_W - 4, y + NOTCH_D))
		p.append(Vector2(x0 + NOTCH_X + 4, y + NOTCH_D))
		p.append(Vector2(x0 + NOTCH_X, y))
	_arc(p, Vector2(x0 + R, y - R), R, PI * 0.5, PI)


func _clean(p:PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in p:
		if out.is_empty() or out[out.size() - 1].distance_to(v) > 0.3:
			out.append(v)
	while out.size() > 3 and out[0].distance_to(out[out.size() - 1]) <= 0.3:
		out.remove_at(out.size() - 1)
	return out


func _arc(p:PackedVector2Array, c:Vector2, radius:float, a0:float, a1:float) -> void:
	var steps := 5
	for i in steps + 1:
		var a := lerpf(a0, a1, float(i) / steps)
		p.append(c + Vector2(cos(a), sin(a)) * radius)


func _curve(p:PackedVector2Array, a:Vector2, c:Vector2, b:Vector2) -> void:
	for i in range(1, 9):
		var t := float(i) / 8.0
		p.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
