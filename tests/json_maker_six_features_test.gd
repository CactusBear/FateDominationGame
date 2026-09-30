extends Node

const SCENE = preload("res://json_maker/json_maker.tscn")
var failed:Array = []

func check(ok:bool, text:String) -> void:
	print("FEATURE ", text, ": ", ok)
	if not ok:
		failed.append(text)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var ui = SCENE.instantiate()
	add_child(ui)
	await get_tree().process_frame
	var catalog:Array = ui._deck_entries()
	check(not catalog.is_empty(), "scan actual attack files")
	var first:Dictionary = catalog[0]
	check(str(first.ref).begins_with("special:") and str(first.card.get("attack_name", "")) != "", "exact-name attack reference")
	var existing := ["strength:2", "unknown:legacy", "strength:2"]
	var owner := {"ATTACKS": existing.duplicate()}
	ui._open_deck_picker(owner, "ATTACKS")
	await get_tree().process_frame
	check(owner.ATTACKS == existing, "opening picker preserves duplicate and unknown legacy refs")
	var popup:AcceptDialog = ui.get_child(ui.get_child_count() - 1)
	check(popup.title.contains("攻击牌") and popup.get_node_or_null("DeckPickerBody") != null, "dedicated deck picker created")
	var rows = popup.get_node("DeckPickerBody").get_child(2).get_child(0)
	var last_row = rows.get_child(rows.get_child_count() - 1)
	last_row.get_child(last_row.get_child_count() - 1).pressed.emit()
	check(owner.ATTACKS.size() == existing.size() + 1, "adding an actual attack updates deck")
	await get_tree().process_frame
	rows.get_child(0).get_child(1).pressed.emit()
	check(owner.ATTACKS.size() == existing.size() and owner.ATTACKS.has("unknown:legacy"), "removing one preserves unknown entries")
	await get_tree().process_frame
	var first_offer:HBoxContainer = null
	for candidate in rows.get_children():
		if candidate is HBoxContainer and candidate.get_child_count() > 0 and candidate.get_child(0).name == "CardThumbnail":
			first_offer = candidate
			break
	check(first_offer != null, "attack list has selectable image row")
	first_offer.get_child(first_offer.get_child_count() - 1).pressed.emit()
	check(owner.ATTACKS.back() == first.ref, "first attack row adds its own attack, not the last row")
	await get_tree().process_frame
	var deck_search:LineEdit = popup.get_node("DeckPickerBody").get_child(0)
	deck_search.text = "__no_such_attack__"
	deck_search.text_changed.emit(deck_search.text)
	check(rows.find_children("CardThumbnail", "TextureRect", true, false).is_empty(), "deck picker search filters existing attack rows")
	popup.hide()
	popup.queue_free()
	await get_tree().process_frame
	ui.kind_id = "servant"
	ui._new_card()
	var class_field:Dictionary = {}
	for field in ui.maker.kind_spec("servant").get("fields", []):
		if str(field.get("key", "")) == "servant_class":
			class_field = field
	var class_host := VBoxContainer.new()
	ui.add_child(class_host)
	ui._field_row(class_host, ui.data, class_field)
	check(class_host.get_child_count() == 1 and class_host.get_child(0).get_child_count() == 3, "class field shows editable text and dropdown")
	var class_edit:LineEdit = class_host.get_child(0).get_child(1)
	class_edit.text = "custom_class"
	class_edit.text_changed.emit("custom_class")
	check(ui.data.get("servant_class") == "custom_class", "custom class text is retained")
	class_host.get_child(0).get_child(2).pressed.emit()
	check(ui.tp_groups.size() > 0, "class dropdown opens declared choices")
	ui.tp_pick.call("saber")
	check(ui.data.get("servant_class") == "saber", "selecting a class updates value")
	ui.tp_popup.hide()
	class_host.queue_free()
	var before = ui.data.duplicate(true)
	ui.search.text = "edit_magic"
	ui._fill_palette()
	var palette_slots:Array = ui.palette_box.find_children("PaletteSlot", "Button", true, false)
	check(not palette_slots.is_empty(), "palette block slots are clickable entries " + str(palette_slots.size()))
	check(palette_slots.is_empty() or (palette_slots[0] as Button).mouse_filter == Control.MOUSE_FILTER_STOP, "palette slot keeps mouse response")
	var before_dirty_six:bool = ui.dirty
	if not palette_slots.is_empty():
		(palette_slots[0] as Button).pressed.emit()
	check(ui.tp_groups.size() > 0, "palette slot opens its candidates")
	check(ui.data == before and ui.dirty == before_dirty_six, "preview does not modify card")
	ui.tp_popup.hide()
	ui.search.text = ""
	ui._fill_palette()
	var slot_data := [{"s": "lit", "v": null}]
	var slot:Control = ui._slot_widget(slot_data, 0, "条件", "bool", "", true)
	ui.script_box.add_child(slot)
	await get_tree().process_frame
	check(slot.size.x >= 96 and slot.size.y >= 36, "parameter slot has usable drop surface")
	var picker:Control = slot.find_child("SlotPicker", true, false)
	if picker != null:
		var payload := {"new": {"kind": "op", "func": "is_true_name_released"}}
		var hit:Dictionary = ui._resolve_drop(picker, Vector2(2, 2), payload)
		check(hit.get("target") == slot and hit.get("drop", {}).get("kind") == "slot", "nested picker edge resolves to parameter slot")
	slot.queue_free()
	var classes:Array = ui.maker.kind_choice_groups("servant_class")
	check(not classes.is_empty(), "servant class declared candidates")
	var tutorial_files:Array = ui.maker.list_tutorials()
	check(not tutorial_files.is_empty(), "tutorial available")
	ui.tutorials = tutorial_files
	ui.data["shown_servant_name"] = "未保存原稿"
	ui.dirty = true
	ui.start_tutorial(0)
	check(ui.tutorial_practice and ui.path == "" and ui.data == null, "isolated exercise starts without a card")
	var servant_pick := -1
	for k in ui.kind_button.item_count:
		if str(ui.kind_button.get_item_metadata(k)) == "servant":
			servant_pick = k
	check(servant_pick >= 0, "servant kind is available in the kind menu")
	ui._select_kind(servant_pick)
	ui._new_card()
	check(ui.tutorial_practice and ui.path == "" and ui.data is Dictionary and ui.card_kind == "servant", "learner builds the servant inside the practice copy")
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		var actual_class_button:Control = ui.card_box.find_child("FieldChoiceButton", true, false)
		var card_scroll:Control = ui.card_box.get_parent()
		check(actual_class_button != null and actual_class_button.get_global_rect().end.x <= card_scroll.get_global_rect().end.x + 1.0, "actual class dropdown remains within visible scroll viewport")
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://json_maker_practice.png")
	var target := "user://must_not_write_tutorial.json"
	var real_card := "res://data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json"
	var real_bytes := FileAccess.get_file_as_bytes(real_card)
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
	ui._save()
	ui._save_as()
	ui._save_to(target)
	ui._save_to(real_card)
	ui._zip_card()
	ui._zip_to("user://must_not_write_tutorial.zip")
	check(not FileAccess.file_exists(target) and not FileAccess.file_exists("user://must_not_write_tutorial.zip"), "all save/export paths blocked")
	check(FileAccess.get_file_as_bytes(real_card) == real_bytes, "practice cannot overwrite original card")
	ui.close_tutorial()
	check(ui.tutorial_practice and not ui.tutorial_state().saved, "closing tutorial keeps practice unsavable")
	ui.restore_tutorial_previous()
	check(not ui.tutorial_practice and ui.data.get("shown_servant_name") == "未保存原稿" and ui.dirty, "restore prior unsaved document")
	if DisplayServer.get_name() != "headless":
		ui.open_path("res://data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json")
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://json_maker_card_thumbnail.png")
		ui._open_deck_picker(owner, "ATTACKS")
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var shot := "user://json_maker_six_features.png"
		image.save_png(shot)
		print("SCREENSHOT ", ProjectSettings.globalize_path(shot))
	ui.queue_free()
	await get_tree().process_frame
	print("FEATURE RESULT ", failed.size(), " failures: ", failed)
	get_tree().quit(0 if failed.is_empty() else 1)
