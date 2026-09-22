extends Node
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)
func setup(count:int=3, magic:int=10)->Dictionary:
	EffectManager.reset_runtime(); GameLog.reset(); GameLog.set_context(1,"action")
	GameProgress.current_round=1; GameProgress.current_phase_index=2; GameProgress.current_player_id=0
	GameData.player_data_library[0]=GameData.new_player_data()
	var d=GameData.player_data_library[0]; d.is_out=false; d.magic.number=magic
	d.hand_cards=[]
	for i in range(count): d.hand_cards.append(BaseAttack.new("a%d"%i,"",[],BaseNumber.new(2),BaseNumber.new(3)))
	return d
func _ready(): call_deferred("run")
func run():
	var d=setup(); var c=d.hand_cards.duplicate()
	GameProgress.current_phase_index=1
	check(RegularPlay.pending_modes(0,[],[],c[0]).is_empty(),"outpost phase has no regular-play modes")
	GameProgress.current_phase_index=2
	check(RegularPlay.add(0,c[0],false),"first immediately added")
	check(d.played_cards==[c[0]] and d.hand_cards.size()==2 and d.magic.number==8 and not RegularPlay.completed(0),"first immediately paid and unresolved")
	check(not GameProgress.end_current_player_action() and GameProgress.current_player_id==0,"below minimum cannot end with path")
	check(RegularPlay.add(0,c[1],false),"second added")
	check(RegularPlay.completed(0) and d.played_cards.size()==2,"limit auto finalize")
	d=setup(); c=d.hand_cards.duplicate(); d.play_limit.number=3
	check(RegularPlay.add(0,c[0],false) and RegularPlay.add(0,c[1],false),"minimum reached below limit")
	check(not RegularPlay.completed(0) and GameProgress.end_current_player_action(),"end finalizes at minimum")
	check(RegularPlay.completed(0),"end recorded completion")
	d=setup(1); c=d.hand_cards.duplicate()
	check(RegularPlay.can_end(0) and GameProgress.end_current_player_action(),"no path may end")
	check(RegularPlay.completed(0) and RegularPlay.played_count(0)==0,"no path forced completion")
	d=setup(2,8); c=d.hand_cards.duplicate(); d.play_limit.number=2
	var skill=BaseSkill.new("skill","",[],BaseNumber.new(6),BaseNumber.new(1)); d.servant_skills=[skill]
	check(RegularPlay.add(0,c[0],false),"snapshot first paid")
	check(RegularPlay.add(0,skill,false),"skill uses flow-start magic snapshot")
	# 待确认模式不能允许走进无法完成整组的死路：唯一合法组合是攻击暗置 + 技能明置。
	d=setup(1,2); c=d.hand_cards.duplicate()
	d.ignore_skill_zone_magic_limit=true
	var completion_skill:=BaseSkill.new("completion_skill","",[],BaseNumber.new(1),BaseNumber.new(1))
	d.servant_skills=[completion_skill]
	var first_modes:Array=RegularPlay.pending_modes(0,[],[],c[0])
	check(not first_modes.has(false),"pending UI rejects a faceup choice that makes the group impossible")
	check(first_modes.has(true),"pending UI keeps the concealed choice that has a valid completion")
	d=setup(2); c=d.hand_cards.duplicate(); d.location=MapData.miyama0
	# 非交战状态（战区只有自己）：允许两张都暗置
	check(RegularPlay.pending_modes(0,[c[0]],[true],c[1]).has(true),"peaceful battlefield allows both cards hidden")
	# 放入对手变为交战状态：强制要求必须至少一张明置
	GameData.player_data_library[1] = GameData.new_player_data()
	var opp_d = GameData.player_data_library[1]
	opp_d.is_out = false
	opp_d.location = MapData.miyama1
	check(RegularPlay.pending_modes(0,[],[],c[0]).has(true),"battle first hidden may remain pending")
	check(not RegularPlay.pending_modes(0,[c[0]],[true],c[1]).has(true),"battle second hidden is blocked without a faceup card")
	check(RegularPlay.pending_modes(0,[c[0]],[false],c[1]).has(true),"battle second hidden remains legal after a faceup card")
	check(RegularPlay.modes(0,c[0]).has(true),"battle hidden mode kept when faceup completion exists")
	check(RegularPlay.add(0,c[0],false),"battle faceup add")
	check(RegularPlay.add(0,c[1],true) and RegularPlay.completed(0),"battle mixed completes")
	var scene=load("res://assets/scenes/game_scene/tactical_board_ui.tscn").instantiate(); get_tree().root.add_child(scene); scene.set_process(false)
	d=setup(); scene._local_player_id=0; c=d.hand_cards.duplicate()
	var magic_before:int=d.magic.number
	scene._choose_regular_play_mode(c[0],false)
	check(d.played_cards.is_empty() and d.magic.number==magic_before,"UI selection has no side effects before confirmation")
	check(scene._regular_play_pending_cards.size()==1,"first card is staged")
	scene._undo_regular_play_selection()
	check(scene._regular_play_pending_cards.is_empty() and d.played_cards.is_empty(),"staged card can be undone")
	scene._choose_regular_play_mode(c[0],false)
	scene._choose_regular_play_mode(c[1],true)
	scene._refresh_played_cards(d)
	var pending_slots:Array=[]
	for slot in scene._ensure_slot_nodes(scene.played_cards_row, 2):
		if slot.has_meta("pending_regular_card") and slot.get_meta("pending_regular_card") != null:
			pending_slots.append(slot)
	check(pending_slots.size()==2,"pending cards use independent slots")
	var second_slot:Control=pending_slots[1]
	var second_tex:Array=scene._card_texture_nodes(second_slot)
	var conceal:Control=second_tex[0].get_node_or_null("ConcealOverlay") if not second_tex.is_empty() else null
	check(conceal!=null and conceal.visible,"concealed pending card shows eye overlay")
	var click:=InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true
	scene._on_pending_played_slot_input(click,second_slot)
	check(scene._regular_play_pending_cards==[c[0]],"clicking second pending card removes only that card")
	check(scene.tactical_confirm_modal==null or not scene.tactical_confirm_modal.visible,
		"withdrawing a card closes its obsolete group confirmation")
	scene._undo_regular_play_selection()
	scene._choose_regular_play_mode(c[0],false)
	scene._choose_regular_play_mode(c[1],false)
	check(scene._pending_tactical_action.get("type","")=="regular_play","complete staged group asks for confirmation")
	var pending_count:int=scene._regular_play_pending_cards.size()
	scene._choose_regular_play_mode(c[2] if c.size()>2 else c[0],false)
	check(scene._regular_play_pending_cards.size()==pending_count,"confirmation blocks further pending cards")
	check(GameLog.query({"type":"regular_play","actor":0},0).is_empty(),"group is not broadcast before confirmation")
	scene._on_tactical_confirm_execute()
	check(d.played_cards.size()==2 and RegularPlay.completed(0),"confirmation submits the whole group")
	check(not GameLog.query({"type":"regular_play","actor":0},0).is_empty(),"confirmed group is broadcast as a completion fact")
	# 待确认牌数量超过出牌区预置卡位数时会克隆卡位；克隆体若继承上一张的绑定标记与信号连接，
	# 会表现为"点第二张撤回了第一张"。这里必须真的走克隆路径才算验到。
	d=setup(5); d.play_limit.number=5
	scene._local_player_id=0; scene._regular_play_pending_cards=[]; scene._regular_play_pending_hidden=[]
	c=d.hand_cards.duplicate()
	for i in range(5): scene._choose_regular_play_mode(c[i],false)
	check(scene._regular_play_pending_cards.size()==5,"five pending cards staged")
	scene._refresh_played_cards(d)
	var last_slot:Control=null
	for slot in scene._ensure_slot_nodes(scene.played_cards_row,5):
		if slot.has_meta("pending_regular_card") and slot.get_meta("pending_regular_card")==c[4]:
			last_slot=slot
	check(last_slot!=null,"cloned slot keeps its own pending card")
	var clone_click:=InputEventMouseButton.new(); clone_click.button_index=MOUSE_BUTTON_LEFT; clone_click.pressed=true
	# 玩家实际点的是卡图子节点，而不是卡位容器。
	var art_nodes:Array=scene._card_texture_nodes(last_slot)
	check(not art_nodes.is_empty(),"cloned pending slot has a card art input target")
	if not art_nodes.is_empty():
		art_nodes[0].emit_signal("gui_input",clone_click)
	check(not scene._regular_play_pending_cards.has(c[4]) and scene._regular_play_pending_cards.size()==4,
		"clicking cloned card art withdraws only that card")
	var fourth_slot:Control=null
	for slot in scene._ensure_slot_nodes(scene.played_cards_row,4):
		if slot.get_meta("pending_regular_card",null)==c[3]:
			fourth_slot=slot
	if fourth_slot!=null:
		fourth_slot.emit_signal("gui_input",clone_click)
	check(not scene._regular_play_pending_cards.has(c[3]) and scene._regular_play_pending_cards.size()==3,"clicking a cloned pending slot removes that card only")
	scene._regular_play_pending_cards=[]; scene._regular_play_pending_hidden=[]
	d=setup()
	scene._set_ai_play_prompt(0,c[0]); check(scene._ai_play_prompt_card==null,"local prompt suppressed")
	scene._local_player_id=6; scene._set_ai_play_prompt(0,c[0]); check(scene._ai_play_prompt_card==c[0],"other player prompt shown")
	d=setup(); scene._run_dummy_bot_turn(0); check(RegularPlay.completed(0) and d.played_cards.size()==2,"AI incremental play completes")
	# AI 必须会打技能牌：手牌之外的可出技能要真的被 AI 选中并打出
	d=setup(2,8); d.play_limit.number=2
	var ai_skill=BaseSkill.new("AI技能","",[],BaseNumber.new(2),BaseNumber.new(1)); d.servant_skills=[ai_skill]
	scene._run_dummy_bot_turn(0)
	check(d.played_cards.has(ai_skill),"AI plays an available skill card")
	# 第一张的效果改变后续出牌上限，不得回头扩充已经选定的本组。
	d=setup(4,10); d.play_limit.number=2
	var limit_skill:=BaseSkill.new("limit_skill","",[],BaseNumber.new(0),BaseNumber.new(0))
	var limit_effect:=BaseEffect.new("limit_effect",["self_played_card"],0,true,true)
	limit_effect._need_activate=false
	limit_effect.from=limit_skill
	limit_effect._funcs=LoadHelper.load_funcs([{"func_name":"edit_data_number","parameters":["play_limit",BaseNumber.new(4)],"var_index":-1}],limit_effect)
	limit_skill._effects=[limit_effect]
	d.servant_skills=[limit_skill]
	EffectManager.register_effect(limit_effect,0)
	scene._run_dummy_bot_turn(0)
	var group_logs:=GameLog.query({"type":"regular_play","actor":0},0)
	check(group_logs.size()==1 and int(group_logs[0].data.get("count",-1))==2 and d.played_cards.size()==2,
		"AI freezes the group count before the first card raises the limit")
	check(d.play_limit.number==4,"raised limit applies after the already chosen group")
	# 来源绑定只拦“此牌打出时”；独立监听同一时点仍能响应别的牌。
	d=setup(0,10)
	var source_skill:=BaseSkill.new("source_skill","",[],BaseNumber.new(0),BaseNumber.new(0))
	var other_skill:=BaseSkill.new("other_skill","",[],BaseNumber.new(0),BaseNumber.new(0))
	var source_effect:=BaseEffect.new("source_effect",[TimePoints.SELF_PLAYED_CARD],0,true,true)
	source_effect._need_activate=false
	source_effect._source_bound=true
	source_effect.from=source_skill
	source_effect._funcs=LoadHelper.load_funcs([{"func_name":"do_nothing","parameters":[],"var_index":-1}],source_effect)
	var listener:=BaseEffect.new("independent_listener",[TimePoints.SELF_PLAYED_CARD],0,true,true)
	listener._need_activate=false
	listener.from=source_skill
	listener._funcs=LoadHelper.load_funcs([{"func_name":"do_nothing","parameters":[],"var_index":-1}],listener)
	d.servant_skills=[source_skill,other_skill]
	EffectManager.register_effect(source_effect,0)
	EffectManager.register_effect(listener,0)
	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD],0,other_skill)
	check(GameLog.query({"type":"effect","data":{"effect_name":"source_effect"}},0).is_empty(),"source-bound effect ignores another card")
	check(GameLog.query({"type":"effect","data":{"effect_name":"independent_listener"}},0).size()==1,"independent listener still observes another card")
	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD],0,source_skill)
	check(GameLog.query({"type":"effect","data":{"effect_name":"source_effect"}},0).size()==1,"source-bound effect observes its own card")
	check(EffectManager.messages.is_empty(),"placeholder effects never produce a success announcement")
	# 回归验证：技能卡位的金框与"能不能出"的状态必须同在卡图层。
	# 状态留在卡位、框画在卡图上时，节流刷新按卡位读不到 playable_hint，会落进
	# "轮到我 = 亮着"的兜底分支——症状就是技能在自己回合的非行动阶段（前哨）莫名闪金框
	d=setup(); scene._local_player_id=0
	var rack_slot:Control=scene.get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_SkillsAndPhantasms/VBox/CardsScroll/H/Sk1")
	check(rack_slot!=null,"the skill rack slot is reachable")
	var rack_skill=BaseSkill.new("前哨技能","",[],BaseNumber.new(1),BaseNumber.new(3)); d.servant_skills=[rack_skill]
	GameProgress.current_phase_index=2
	scene._fill_skill_slot(rack_slot,rack_skill,true,true)
	var rack_art:Control=scene._card_art_of(rack_slot)
	var rack_glow:Control=rack_art.get_node_or_null("ClickableGlow") if rack_art!=null else null
	check(rack_glow!=null,"an actionable skill shows its frame in the action phase")
	GameProgress.current_phase_index=1
	scene._fill_skill_slot(rack_slot,rack_skill,true,true)
	scene._refresh_clickable_strength()
	check(rack_glow!=null and not rack_glow.visible,"the skill frame is not relit in the outpost phase")
	check(not bool(rack_art.get_meta("playable_hint",false)),"the skill hint state follows playability")
	scene._show_card_select_panel({"cards":d.hand_cards,"min":1,"max":1})
	check(scene._card_select_panel!=null and scene._card_select_panel.visible,"effect selector preserved")
	print("RESULT checks=",checks," failures=",failures)
	var f=FileAccess.open("res://regular_test_result.json",FileAccess.WRITE); f.store_string(JSON.stringify({"checks":checks,"failures":failures})); f.close()
	get_tree().quit(0 if failures.is_empty() else 1)
