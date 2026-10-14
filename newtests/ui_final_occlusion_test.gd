extends Node

var checks := 0
var failures: Array = []
func check(ok: bool, label: String) -> void:
	checks += 1
	print("CHECK ",label," ",ok)
	if not ok: failures.append(label)
func _ready() -> void:
	var scene = preload("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	for template in ["HandCard","ZoneCard"]:
		var slot: Control = scene.get_node("Templates/"+template)
		for frame in ["Breath","EffectBreath","Selected"]:
			var outline: Control = slot.get_node(frame)
			check(outline.z_index == slot.get_node("Frame").z_index and outline.z_as_relative and not outline.top_level, template+" "+frame+" stays at its card draw depth")
		check(not slot.clip_contents,"external badge is not clipped to card bounds "+template)
	scene.free()
	print("RESULT ",JSON.stringify({"suite":"ui_final_occlusion","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
