extends Node

# 选图面板回归：能浏览电脑上任意位置、图片以图标列出且带缩略图、点图标就选中，
# 并且不会改动正式卡文件（练习副本与正式数据的保护照旧）。
var checks := 0
var failures:Array = []

const ARTORIA_FOLDER := "res://data/servants/00001_artoria_pendragon"
const ARTORIA := ARTORIA_FOLDER + "/00001_artoria_pendragon.json"


func check(ok:bool, text:String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
	print("CHECK ", text, " ", ok)


func grid_now(ui) -> GridContainer:
	return ui.image_picker.find_child("ImageGrid", true, false)


func picture_tiles(ui) -> Array:
	var grid := grid_now(ui)
	return [] if grid == null else grid.find_children("ImageTileButton", "Button", true, false)


func folder_tiles(ui) -> Array:
	var grid := grid_now(ui)
	return [] if grid == null else grid.find_children("ImageFolderButton", "Button", true, false)


func click_folder(ui, button:Button, double_click:bool) -> void:
	var at:Vector2 = button.get_global_rect().get_center() + Vector2(ui.image_picker.position)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.double_click = double_click and pressed
		if DisplayServer.get_name() == "headless":
			if is_instance_valid(button):
				button.gui_input.emit(event)
				if not pressed:
					button.pressed.emit()
		else:
			Input.parse_input_event(event)
		await get_tree().process_frame


func _ready() -> void:
	var ui = load("res://json_maker/json_maker.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame
	ui.open_path(ARTORIA)
	await get_tree().process_frame
	var before_bytes := FileAccess.get_file_as_bytes(ARTORIA)

	ui._pick_image(ui.data, "servant_card_img", "")
	await get_tree().process_frame
	check(ui.image_picker != null, "选图面板打开")
	if DisplayServer.get_name() != "headless":
		check(ui.image_picker.visible, "选图面板真的显示了")
	check(ui.image_dir == ARTORIA_FOLDER, "面板从这张卡自己的文件夹开始 " + ui.image_dir)
	check(grid_now(ui) != null and grid_now(ui) is GridContainer, "图片按图标格子排，不是列表")
	var tiles:Array = picture_tiles(ui)
	check(tiles.size() >= 2, "卡文件夹里的图片都列成图标 " + str(tiles.size()))
	var with_icon := 0
	for tile in tiles:
		if (tile as Button).icon != null:
			with_icon += 1
	check(tiles.size() > 0 and with_icon == tiles.size(), "每个图标都有缩略图 " + str(with_icon) + "/" + str(tiles.size()))
	var names:Array = grid_now(ui).find_children("ImageTileName", "Label", true, false)
	check(names.size() == tiles.size(), "每个图标下面都带名字 " + str(names.size()) + "/" + str(tiles.size()))
	var named := 0
	for node in names:
		if str((node as Label).text) != "" and ((node as Label).size.y >= 8 or DisplayServer.get_name() == "headless"):
			named += 1
	check(names.size() > 0 and named == names.size(), "名字真的显示得出来 " + str(named))

	# 电脑上别的位置也能看：系统图片目录、项目目录、盘根
	var pictures := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	ui._show_image_dir(pictures)
	await get_tree().process_frame
	check(ui.image_dir == pictures and grid_now(ui).get_child_count() > 0, "能跳到系统图片目录并列出内容 " + pictures)
	check(ui._image_roots().size() >= 1, "列出了能浏览的位置 " + str(ui._image_roots()))
	ui._show_image_dir(ProjectSettings.globalize_path("res://json_maker/pending_images"))
	await get_tree().process_frame
	check(picture_tiles(ui).size() >= 1, "项目里的文件也能以图标列出 " + str(picture_tiles(ui).size()))
	ui._show_image_dir(ProjectSettings.globalize_path("res://json_maker"))
	await get_tree().process_frame
	check(folder_tiles(ui).size() >= 1, "文件夹也是图标格子 " + str(folder_tiles(ui).size()))
	var parent_dir:String = ui.image_dir
	var folder_button:Button = folder_tiles(ui)[0]
	var folder_target:String = folder_button.tooltip_text.split("\n")[0]
	await click_folder(ui, folder_button, false)
	check(ui.image_dir == parent_dir, "单击文件夹不进入")
	await click_folder(ui, folder_button, true)
	check(ui.image_dir == folder_target, "左键双击进入文件夹")
	ui._show_image_dir(parent_dir)
	ui._image_dir_up()
	check(ui.image_dir.trim_suffix("/") == ProjectSettings.globalize_path("res://").trim_suffix("/"), "能跳回上一级 " + ui.image_dir)
	ui._show_image_dir("Z:/没有这个位置")
	check(ui.image_dir.trim_suffix("/") == ProjectSettings.globalize_path("res://").trim_suffix("/"), "打不开的位置不改变当前目录")

	# 从卡文件夹双击一个图标：真实双击应选中它并直接关闭面板
	ui._show_image_dir(ARTORIA_FOLDER)
	await get_tree().process_frame
	var tile_buttons:Array = picture_tiles(ui)
	check(not tile_buttons.is_empty(), "卡文件夹里有点得动的图标")
	if not tile_buttons.is_empty():
		var tile:Button = tile_buttons[0]
		await click_folder(ui, tile, true)
		await get_tree().process_frame
		var chosen := str(ui.data.get("servant_card_img", ""))
		check(chosen.begins_with("res://json_maker/pending_images/"), "点图标就把它选成待整理路径 " + chosen)
		check(ui.dirty, "选图把卡标成还没保存")
		check(ui.image_picker == null, "图片双击后直接关闭选图面板")
	check(FileAccess.get_file_as_bytes(ARTORIA) == before_bytes, "选图不改动正式卡文件")

	# 记忆：没保存过的新卡，下次打开从上次去的位置开始，不再每次退回系统图片目录
	var saved_memory = ui.maker.global_export("last_image_dir", null)
	var stash := ProjectSettings.globalize_path("res://json_maker/pending_images")
	ui.path = ""
	ui._pick_image(ui.data, "servant_card_img", "")
	await get_tree().process_frame
	ui._show_image_dir(stash)
	await get_tree().process_frame
	ui._pick_image(ui.data, "servant_card_img", "")
	await get_tree().process_frame
	check(ui.image_dir == stash, "新卡再打开时从上次去的位置开始 " + ui.image_dir)
	check(ui.image_dir != pictures, "不再每次都退回系统图片目录 " + pictures)
	check(str(ui.maker.global_export("last_image_dir", {}).get("dir", "")) == stash, "记忆写进了设置里")
	check(str(ui.maker.global_export("last_image_dir", {}).get("card", "x")) == "", "记忆跟着当时那张卡一起记")
	ui.maker.load_export_settings()   # 重开编辑器：设置从 user:// 读回来
	check(str(ui.maker.global_export("last_image_dir", {}).get("dir", "")) == stash, "记忆存进了 user://，重开还在")
	# 已保存的卡还是先看自己的文件夹，不会沿用别的卡的位置
	ui.path = ARTORIA
	check(ui._image_start_dir() == ARTORIA_FOLDER, "别的卡仍从自己的文件夹开始 " + ui._image_start_dir())
	# 同这张卡选过图之后，它自己上次去的位置优先
	ui._show_image_dir(stash)
	check(ui._image_start_dir() == stash, "同一张卡沿用自己上次去的位置 " + ui._image_start_dir())
	# 记忆里的位置没了（换盘、拔了 U 盘）就往下退，不会卡在打不开的地方
	ui.maker.set_export("_global", "last_image_dir", {"dir": "Z:/没有这个位置", "card": ARTORIA})
	check(ui._image_start_dir() == ARTORIA_FOLDER, "记忆的位置不存在时退回卡的文件夹 " + ui._image_start_dir())
	ui.maker.set_export("_global", "last_image_dir", {"dir": "Z:/没有这个位置", "card": ""})
	ui.path = ""
	check(ui._image_start_dir() == pictures, "记忆失效的新卡退回系统图片目录 " + ui._image_start_dir())
	ui.path = ARTORIA
	ui.maker.set_export("_global", "last_image_dir", saved_memory)
	ui.maker.save_export_settings()
	if DisplayServer.get_name() != "headless":
		var screen := DisplayServer.screen_get_size()
		check(ui.image_picker.size.x <= screen.x and ui.image_picker.size.y <= screen.y, "面板没有超出屏幕 " + str(ui.image_picker.size))
		var grid_rect:Rect2 = (grid_now(ui) as Control).get_global_rect()
		check(grid_rect.end.y <= ui.image_picker.size.y and grid_rect.end.x <= ui.image_picker.size.x, "图标区落在窗口里 " + str(grid_rect))
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://json_maker_image_picker.png")
		print("SHOT picker=", Rect2(Vector2(ui.image_picker.position), Vector2(ui.image_picker.size)),
			" grid=", (grid_now(ui) as Control).get_global_rect(),
			" name0=", ((grid_now(ui).find_child("ImageTileName", true, false)) as Control).get_global_rect())
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
