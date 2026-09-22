extends Node
#完整对局回归：从开局推到游戏结束，验证
#① 游戏能正常结束并记下结局事实（含圣杯溢出这种"无人获胜"的合法结局）
#② 第8/9/10天按规则淘汰，多个高潮日都继续淘汰
#③ 被淘汰的人离开版图、不再被派发行动
#④ 战斗结算留下可查询的明细
#
#必须实例化 tactical_board_ui：前哨阶段的部署与 AI 行动目前由界面控制器驱动
#（引擎侧没有独立部署入口）。不挂界面直接推进的话没人部署，
#于是没有战斗、没有战果、全员同分，并列规则下一个人都不会被淘汰——
#那是测试环境缺失，不是规则错误。曾据此误报过"高潮日不淘汰人"。
var failures:Array=[]
var checks:=0
var scene:Node=null
var captured_action:bool=false

func render_window_state(capture_name:String = ""):
	if DisplayServer.get_name() == "headless": return
	scene.refresh_all_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if not capture_name.is_empty():
		DirAccess.make_dir_recursive_absolute("res://tests/runtime_reports")
		var path:String = "res://tests/runtime_reports/" + capture_name + ".png"
		check(get_viewport().get_texture().get_image().save_png(path) == OK, "window screenshot saved " + capture_name)

func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)
func _ready(): call_deferred("run")
func run():
	scene=load("res://assets/scenes/game_scene/tactical_board_ui.tscn").instantiate()
	get_tree().root.add_child(scene)
	# 测试独占行动推进，窗口刷新不再让 _process 同时驱动第二次 AI 行动。
	scene.set_process(false)
	await get_tree().process_frame
	check(GameProgress.current_round == 1,"game started at round 1")
	check(GameDataManager.get_active_player_ids().size() == 7,"seven players in play")

	var acted_after_out:Array=[]
	var guard:int=0
	while not GameProgress.is_game_over and guard<40000:
		guard+=1
		var capture_name:String = ""
		if not captured_action:
			for data in GameData.player_data_library.values():
				if not data.played_cards.is_empty():
					capture_name = "full_game_action"
					captured_action = true
					break
		await render_window_state(capture_name)
		if EffectManager.is_waiting_for_card_selection():
			var p:Dictionary=EffectManager.get_pending_card_selection()
			DummyBot.new().resolve_card_selection(p)
			if EffectManager.is_waiting_for_card_selection():
				EffectManager.submit_card_selection(p.get("effect"),[])
			continue
		if EffectManager.waiting_players != null:
			var p_pl:Dictionary=EffectManager.get_pending_player_selection()
			DummyBot.new().resolve_player_selection(p_pl)
			if EffectManager.waiting_players != null:
				EffectManager.submit_player_selection(p_pl.get("effect"),[])
			continue
		if EffectManager.waiting_location != null:
			var p_loc:Dictionary=EffectManager.get_pending_location_selection()
			DummyBot.new().resolve_location_selection(p_loc,scene)
			if EffectManager.waiting_location != null:
				EffectManager.submit_location_selection(p_loc.get("effect"),null)
			continue
		if EffectManager.is_waiting_for_choice():
			#具体的等待(选牌/选位置/选玩家)必须先处理：is_waiting_for_choice 把它们全都算进来，
			#放在前面会用 null 的 waiting_effect 去提交、永远失败，把对局卡死
			EffectManager.submit_active_choice(EffectManager.waiting_effect,false); continue
		var cur:int=GameProgress.current_player_id
		if cur==-1: break
		#出局的玩家不该再被派发行动
		if bool(GameDataManager.get_player_data(cur).get("is_out",false)) and not acted_after_out.has(cur):
			acted_after_out.append(cur)
		if cur==scene._local_player_id:
			#headless 没有玩家点击，替本地玩家做与界面相同的动作
			var phase:String=str(GameProgress.get_current_phase().get("name",""))
			if phase=="outpost":
				for area in MapData.areas:
					var loc=scene._pick_open_deploy_location(area)
					if loc!=null:
						Deploy.new().exec(loc,cur)
						scene._apply_deploy_benefit(loc,cur)
						break
			elif phase=="action":
				#headless 没有玩家点击：数据声明的"结束行动前必须满足"的条件要代为履行，
				#否则引擎会一直拒绝推进，这一局永远走不完
				DummyBot.new().fulfill_action_requirements(cur)
				while not RegularPlay.completed(cur):
					var a:Dictionary=RegularPlay.find_add(cur)
					if a.is_empty() or not RegularPlay.add(cur,a["card"],a["hidden"]): break
				if not RegularPlay.completed(cur) and RegularPlay.can_end(cur):
					RegularPlay.finalize(cur,true)
			if not GameProgress.end_current_player_action():
				RegularPlay.finalize(cur,true)
				GameProgress.end_current_player_action()
		else:
			scene._run_dummy_bot_turn(cur)

	await render_window_state("full_game_end")
	check(GameProgress.is_game_over,"game reaches an end")
	check(guard<40000,"game ends without hitting the step guard")
	check(acted_after_out.is_empty(),"an out player never gets another action")

	#部署必须真的发生过，否则后面关于战斗与淘汰的断言都没有意义
	check(not GameLog.query({"type":"deploy"},null).is_empty(),"players were deployed onto the board")
	check(not GameLog.query({"type":"battle"},null).is_empty(),"battles were resolved")

	#规则：第8/9/10天回合结束时淘汰，多个高潮日都要继续淘汰
	var elim_logs:Array=GameLog.query({"type":"eliminated"},null)
	check(not elim_logs.is_empty(),"players were eliminated on the climax days")
	var elim_rounds:Array=[]
	for e in elim_logs:
		var r:int=int(e.get("round",0))
		if not elim_rounds.has(r): elim_rounds.append(r)
	print("elimination rounds=",elim_rounds," total=",elim_logs.size())
	check(elim_rounds.size()>=2,"elimination continues on more than one climax day")
	var declared:Array=GameProgress.climax_keep_counts.keys()
	var only_declared:bool=true
	for r in elim_rounds:
		if not declared.has(r): only_declared=false
	check(only_declared,"eliminations only happen on declared climax rounds")

	#被淘汰的人必须已离开版图
	var off_board:bool=true
	for e in elim_logs:
		var pid:int=int(e.get("actor",-1))
		if pid>=0 and GameDataManager.get_player_data(pid).get("location")!=null:
			off_board=false
	check(off_board,"eliminated players are off the board")

	#结算与结局都要留下可查询的事实
	check(GameProgress.last_battle_result.has("details_by_area"),"battle result carries settlement details")
	var ge:Array=GameLog.query({"type":"game_end"},null)
	check(not ge.is_empty(),"game end recorded as a fact")

	print("RESULT checks=",checks," failures=",failures)
	var f=FileAccess.open("res://full_game_result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,
		"elim_rounds":elim_rounds,"elim_total":elim_logs.size(),
		"final_round":GameProgress.current_round,
		"winners":(ge[0].get("data",{}).get("winners",[]) if not ge.is_empty() else [])})); f.close()
	get_tree().quit(0 if failures.is_empty() else 1)
