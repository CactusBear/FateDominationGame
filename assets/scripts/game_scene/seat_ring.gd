extends Control

## 席位底环：双环 + 刻度。mana=true 为魔力席（青色、菱形标记），否则金色四刻度。
## 只负责画，数值/头像由父节点放置。

const MANA_COLOR := Color("3fd6f0")
const GOLD_COLOR := Color("c9a45c")
const GOLD2_COLOR := Color("e8cd86")
const INK_COLOR := Color(0.024, 0.031, 0.051, 0.6)

@export var mana: bool = false:
	set(v):
		mana = v
		queue_redraw()


func _draw() -> void:
	var c := size / 2
	var r := size.x / 2
	var main := MANA_COLOR if mana else GOLD_COLOR
	draw_circle(c, r * 0.92, INK_COLOR)
	draw_arc(c, r * 0.92, 0, TAU, 64, Color(main, 0.38), 1.0, true)
	var dashes := 12 if mana else 8
	for i in range(dashes):
		var a0 := TAU * i / dashes
		var a1 := a0 + TAU / dashes * (0.5 if mana else 0.7)
		draw_arc(c, r * 0.8, a0, a1, 12, main, 1.5, true)
	if mana:
		var top := c + Vector2(0, -r * 0.92)
		draw_colored_polygon(PackedVector2Array([top, top + Vector2(r * 0.12, r * 0.2), top + Vector2(0, r * 0.4), top + Vector2(-r * 0.12, r * 0.2)]), main)
	else:
		for d in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
			draw_line(c + d * r * 0.96, c + d * r * 0.8, GOLD2_COLOR, 2.0, true)
