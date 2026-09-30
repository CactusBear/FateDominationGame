extends Node

# 从者头像可缺省：表单、校验与正式加载器都应接受缺字段和空值。
var checks := 0
var failures:Array = []

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var maker := JsonMaker.new()
	maker.load_catalog()
	var fields:Array = maker.kind_spec("servant").get("fields", [])
	var avatar:Dictionary = {}
	for field in fields:
		if field.key == "header_img":
			avatar = field
	check(not avatar.is_empty() and not bool(avatar.get("required", false)), "servant avatar optional in catalog")
	check(not maker.blank_required("servant").has("header_img"), "blank servant does not add avatar")
	var data := maker.blank_required("servant")
	data["servant_name"] = "probe_servant"
	data["shown_servant_name"] = "测试从者"
	data["servant_class"] = "saber"
	data["servant_card_img"] = "card.png"
	check(maker.validate(data, "servant").is_empty(), "missing avatar passes validation " + str(maker.issues))
	data["header_img"] = ""
	check(maker.validate(data, "servant").is_empty(), "empty avatar passes validation " + str(maker.issues))
	var dir := "user://servant_optional_avatar_probe"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var file := dir.path_join("probe.json")
	for header in ["missing", "empty", "null"]:
		match header:
			"missing": data.erase("header_img")
			"empty": data["header_img"] = ""
			"null": data["header_img"] = null
		var stream := FileAccess.open(file, FileAccess.WRITE)
		stream.store_string(JSON.stringify(data))
		stream.close()
		var servant = LoadGame.load_servant_file(dir, "probe.json")
		check(servant is BaseServant and servant._header_img == "" and servant._servant_card_img.ends_with("card.png"), "loader handles " + header + " avatar")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
	var ui = load("res://json_maker/json_maker.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame
	var parent := VBoxContainer.new()
	ui.add_child(parent)
	var sample := {"header_img": "existing.png", "header_img_zoom_kind": "portrait"}
	ui._field_row(parent, sample, avatar)
	var clear := parent.find_children("*", "Button", true, false).filter(func(b): return b.text == "清除")
	check(clear.size() == 1, "optional image has clear button")
	if not clear.is_empty():
		clear[0].pressed.emit()
		check(not sample.has("header_img") and not sample.has("header_img_zoom_kind"), "clear removes image and zoom kind")
	await get_tree().process_frame
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
