extends Node
#主菜单回归：进入画面与主菜单的结构、键控与切换。
#① 菜单项数量 = ENTRIES 声明数；每项都有序号/英文/中文/提示
#② 开始游戏面板的头像数 = 已加载御主数，从者卡数 = 已加载从者数（名单直接读 GameData，不复制图片）
#③ ↑↓ 循环选择、面板跟随；Esc 回到标题、任意键回到菜单
#④ 非 headless 时保存四张截图到 tests/runtime_reports
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
	check(menu.get_node("TitleScreen").visible and not menu.get_node("Menu").visible,"title screen first")
	var block:Control=menu.get_node("TitleScreen/Content/Block")
	check(block.get_child_count()==5,"title block has 5 rows")
	#入场动画 1.6 秒，截完整状态要等它结束
	await get_tree().create_timer(1.8).timeout
	await shot("main_menu_title")

	key(KEY_SPACE)
	await get_tree().create_timer(menu.FADE_SECONDS*2+0.2).timeout
	check(menu.get_node("Menu").visible and not menu.get_node("TitleScreen").visible,"any key enters menu")

	var nav:Control=menu.get_node("Menu/Content/Nav")
	var entries:int=menu.ENTRIES.size()
	check(nav.get_child_count()==entries,"nav items == ENTRIES (%d)"%entries)
	for i in entries:
		var item:Control=nav.get_child(i)
		var body:Control=item.get_node("Body")
		check((item.get_node("Idx") as Label).text==menu.ENTRIES[i]["idx"],"item %d idx"%i)
		check((body.get_node("CnRow/Cn") as Label).text==menu.ENTRIES[i]["cn"],"item %d cn"%i)
		check((body.get_node("Hint") as Label).visible==(i==0),"item %d hint visibility"%i)
	var panel:Control=menu.get_node("Menu/Content/Panel")
	check(panel.get_child_count()==entries,"panes == ENTRIES")
	check(panel.get_child(0).visible,"first pane visible")

	var masters:int=GameStart.get_masters_can_use().size()
	var servants:int=GameStart.get_servants_can_use().size()
	check(masters>0 and servants>0,"masters/servants loaded (%d/%d)"%[masters,servants])
	var roster:Control=panel.get_child(0).find_child("Roster",true,false)
	var servant_row:Control=panel.get_child(0).find_child("Servants",true,false)
	check(roster!=null and roster.get_child_count()==masters,"roster avatars == loaded masters")
	check(servant_row!=null and servant_row.get_child_count()==servants,"servant cards == loaded servants")
	var textured:=0
	if roster!=null:
		for cell in roster.get_children():
			var tex:TextureRect=cell.find_child("*",true,false) as TextureRect
			if tex==null:
				for c in cell.get_child(0).get_children():
					if c is TextureRect: tex=c
			if tex!=null and tex.texture!=null: textured+=1
	check(textured==masters,"every avatar has a texture (%d/%d)"%[textured,masters])
	await get_tree().create_timer(0.8).timeout
	await shot("main_menu_play")

	key(KEY_DOWN)
	await settle()
	check(menu._selected==1 and panel.get_child(1).visible and not panel.get_child(0).visible,"down selects editor pane")
	await get_tree().create_timer(0.5).timeout
	await shot("main_menu_editor")
	key(KEY_UP); key(KEY_UP)
	await settle()
	check(menu._selected==entries-1,"up wraps to last")
	check(panel.get_child(entries-1).visible,"quit pane visible")
	check(menu.get_node("Menu/Background").modulate!=Color.WHITE,"quit dims background")
	await get_tree().create_timer(0.5).timeout
	await shot("main_menu_quit")

	#planned 项主按钮禁用
	for i in entries:
		if menu.ENTRIES[i].get("planned",false):
			var primary:Button=panel.get_child(i).find_child("Primary",true,false)
			check(primary!=null and primary.disabled,"planned item %d primary disabled"%i)

	key(KEY_ESCAPE)
	await get_tree().create_timer(menu.FADE_SECONDS*2+0.2).timeout
	check(menu.get_node("TitleScreen").visible,"esc returns to title")

	print("RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
