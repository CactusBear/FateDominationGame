extends Node

var checks := 0
var failures:Array = []
const SOURCE := "res://data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json"

func check(ok:bool, text:String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
	print("CHECK ", text, " ", ok)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var ui = load("res://json_maker/json_maker.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame
	check(ui.maker.has_method("identity_conflicts"), "identity conflict query exists")
	if ui.maker.has_method("identity_conflicts"):
		var card:Dictionary = ui.maker.read_json(SOURCE)
		var name:String = card.servant_name
		check(not ui.maker.identity_conflicts("servant_name", name, "", []).is_empty(), "new card detects existing name")
		check(ui.maker.identity_conflicts("servant_name", name, SOURCE, []).is_empty(), "editing original excludes itself")
		check(ui.maker.identity_conflicts("servant_name", "", "", []).is_empty(), "blank name has no duplicate warning")
		check(not ui.maker.identity_conflicts("master_name", name, "", []).is_empty(), "different identity fields also report duplicates")
		check(not ui.maker.identity_conflicts("servant_name", "tohsaka_rin", "", []).is_empty(), "servant name detects existing master tohsaka_rin")
		var skill:Dictionary = card.specials.SKILLS[0]
		check(not ui.maker.identity_conflicts("skill_name", skill.skill_name, "", []).is_empty(), "nested skill identity indexed")
		check(ui.maker.identity_conflicts("skill_name", skill.skill_name, SOURCE, ["specials", "SKILLS", 0]).is_empty(), "nested original excludes itself")
		ui.open_path(SOURCE)
		await get_tree().process_frame
		var labels:Array = ui.card_box.find_children("IdentityWarning", "Label", true, false)
		check(labels.size() == 1 and not labels[0].visible, "original UI has no false warning")
		ui.path = ""
		ui._paint_card()
		labels = ui.card_box.find_children("IdentityWarning", "Label", true, false)
		check(labels.size() == 1 and labels[0].visible and labels[0].text.contains(SOURCE), "new copy shows duplicate source inline")
		var edit:LineEdit = labels[0].get_parent().get_child(labels[0].get_index() - 1).get_child(1)
		edit.text = "identity_test_unique_name"
		edit.text_changed.emit(edit.text)
		check(not labels[0].visible, "warning disappears immediately after rename")
		edit.text = name
		edit.text_changed.emit(edit.text)
		check(labels[0].visible, "warning returns immediately when duplicate restored")
		edit.text = "tohsaka_rin"
		edit.text_changed.emit(edit.text)
		check(labels[0].visible and labels[0].text.contains("data/masters/00002_tohsaka_rin"), "typing tohsaka_rin shows cross-type source in UI")
		if DisplayServer.get_name() != "headless":
			labels[0].get_parent().get_parent().visible = true
			await get_tree().process_frame
			await get_tree().process_frame
			ui.card_box.get_parent().ensure_control_visible(labels[0])
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("identity-warning.png"))
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
