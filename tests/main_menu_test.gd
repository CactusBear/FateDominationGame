extends Node
#主菜单回归（开场风格统一版）：单屏结构、键控与入口。
#① 菜单项数量 = ENTRIES 声明数；每项只有中文/英文，无序号
#② 「数据库」「设置」标预定；预定项激活只弹 toast 不切场景
#③ ↑↓ 循环选择、金线跟随；Enter 激活
#④ 标题 Fate/DOMINATION 与拱门立绘存在且有贴图；白幕淡入完成
#⑤ 非 headless 时保存截图到 tests/runtime_reports
var failures:Array=[]
var checks:=0
var menu:Control=null

func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)

func key(keycode:int):
	var ev:=InputEventKey.new()
	ev.keycode=keycode
	ev.pressed=true
	get_tree().root.push_input(ev,true)

func settle(frames:int=3):
	for i in frames: await get_tree().process_frame

func shot(name:String):
	if DisplayServer.get_name()=="headless": return
	await settle(2)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tests/runtime_reports")
	check(get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/"+name+".png")==OK,"screenshot "+name)

func _ready(): call_deferred("run")

func run():
	menu=load("res://assets/scenes/main_menu/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await settle()

	#结构：标题、立绘、菜单
	var title:TextureRect=menu.get_node("Title")
	check(title.texture!=null and title.texture.resource_path=="res://assets/images/main_menu/title_fate.svg","title uses continuous Fate vector outlines")
	# SVG 按源坐标放大四倍。逐像素检查 t 新横画右端以外，不能残留原字体细横画。
	var title_pixels:Image=title.texture.get_image()
	var residual_alpha:=0.0
	for y in range((102-40)*4,(107-40)*4):
		for x in range((354-50)*4,(359-50)*4):
			residual_alpha=maxf(residual_alpha,title_pixels.get_pixel(x,y).a)
	check(residual_alpha<0.05,"t crossbar has no protruding old hairline pixels")
	var bar_span:=Vector2i(-1,-1)
	var stem_span:=Vector2i(-1,-1)
	for x in range((288-50)*4,(359-50)*4):
		if title_pixels.get_pixel(x,(104-40)*4).a>0.5:
			if bar_span.x<0: bar_span.x=x
			bar_span.y=x
		if title_pixels.get_pixel(x,(115-40)*4).a>0.5:
			if stem_span.x<0: stem_span.x=x
			stem_span.y=x
	check(bar_span.x>=0 and stem_span.x>=0 and abs(bar_span.x+bar_span.y-stem_span.x-stem_span.y)<=2,"t crossbar centered on upright pixels")
	var subtitle:TextureRect=menu.get_node("Domination")
	check(subtitle.texture!=null and subtitle.texture.resource_path=="res://assets/images/main_menu/title_domination.svg","subtitle uses continuous DOMINATION vector outlines")
	var background:VideoStreamPlayer=menu.get_node("Background")
	check(background.stream!=null and background.autoplay and background.loop,"background video autoplays and loops")
	var background_rect:=background.get_rect()
	check(not menu.has_node("Drift"),"background drift removed")
	check(not menu.has_node("KVArch"),"no framed key visual")
	var nav:Control=menu.get_node("Content/Nav")
	var entries:int=menu.ENTRIES.size()
	check(nav.get_child_count()==entries,"nav items == ENTRIES (%d)"%entries)
	for i in entries:
		var item:Control=nav.get_child(i)
		var body:Control=item.get_node("Body")
		check(not item.has_node("Idx"),"item %d has no index number"%i)
		check((body.get_node("Cn") as Label).text==menu.ENTRIES[i]["cn"],"item %d cn"%i)
		check(body.has_node("Planned")==menu.ENTRIES[i].get("planned",false),"item %d planned tag"%i)
	#声明口径：第三项是数据库且预定
	check(str(menu.ENTRIES[2]["cn"])=="数据库" and menu.ENTRIES[2].get("planned",false),"entry 3 is 数据库 (planned)")
	#退出项与上方有间隔
	var quit_item:Control=nav.get_child(entries-1)
	var prev_item:Control=nav.get_child(entries-2)
	check(quit_item.position.y-prev_item.position.y>menu.NAV_ITEM_HEIGHT,"quit gap present")

	#白幕淡入完成后隐藏
	await get_tree().create_timer(menu.FADE_SECONDS+1.2).timeout
	check(not menu.get_node("Fade").visible,"fade hidden after enter")
	check(background.is_playing() and background.stream_position>0.0,"background video advances")
	check(background.get_rect()==background_rect,"background stays stationary over time")
	await shot("main_menu")

	#↑↓ 循环与金线跟随
	check(menu._selected==0,"first selected")
	key(KEY_DOWN)
	await settle()
	check(menu._selected==1,"down selects next")
	key(KEY_UP); key(KEY_UP)
	await settle()
	check(menu._selected==entries-1,"up wraps to last")
	var gold:ColorRect=nav.get_child(entries-1).get_node("GoldLine")
	await get_tree().create_timer(0.4).timeout
	check(gold.size.x>0,"gold line follows selection")
	var selected_body:Control=nav.get_child(entries-1).get_node("Body")
	check(selected_body.position.x>gold.position.x+gold.size.x,"selection line keeps a gap before text")
	(nav.get_child(1).get_node("Button") as Button).mouse_entered.emit()
	await get_tree().create_timer(0.4).timeout
	var hovered_body:Control=nav.get_child(1).get_node("Body")
	var hovered_line:ColorRect=nav.get_child(1).get_node("GoldLine")
	check(menu._selected==1 and hovered_body.position.x>hovered_line.position.x+hovered_line.size.x,"hover line keeps a gap before text")

	#预定项激活只弹 toast
	menu._activate(2)
	await settle()
	check(menu._selected==2,"activate selects")
	check(menu.get_node("Toast").visible,"planned item shows toast")
	check(get_tree().current_scene==null or not str(get_tree().current_scene.scene_file_path).contains("selection"),"planned item does not switch scene")
	await shot("main_menu_toast")

	var previous_position:=background.stream_position
	var looped:=false
	for frame in 480:
		await get_tree().process_frame
		var current_position:=background.stream_position
		if current_position<previous_position:
			looped=true
			break
		previous_position=current_position
	check(looped and background.is_playing(),"background video wraps and keeps playing")
	print("RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
