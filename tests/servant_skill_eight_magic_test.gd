extends Node

var failures:Array=[]
var checks:int=0

func check(ok:bool,label:String):
	checks+=1
	if not ok:
		failures.append(label)
	print("CHECK ",label," ",ok)

func _ready():
	call_deferred("run")

func run():
	var ui=load("res://assets/scenes/game_scene/tactical_board_ui.tscn").instantiate()
	get_tree().root.add_child(ui)
	ui.set_process(false)
	var id:int=GameData.player_id
	ui._local_player_id=id
	var d:Dictionary=GameDataManager.get_player_data(id)
	GameProgress.current_phase_index=2
	GameProgress.current_player_id=id
	d.magic.number=8
	for natural in d.servant_skills:
		print("NATURAL ",natural.get_shown_name()," cost=",natural._cost.number,
			" candidate=",RegularPlay.candidates(id).has(natural)," faceup=",RegularPlay.faceup_allowed(natural,id),
			" modes=",RegularPlay.pending_modes(id,[],[],natural)," hand_costs=",d.hand_cards.map(func(c): return c._cost.number),
			" forbidden_np=",BoardHasEffect.new().exec(ForbidNoblePhantasmEffect.EFFECT_NAME))
	EffectManager.reset_runtime()
	GameLog.reset()
	GameLog.set_context(1,"action")
	GameProgress.is_game_over=false
	GameProgress.current_round=1
	GameProgress.current_phase_index=2
	GameProgress.current_player_id=id
	d.is_out=false
	d.magic.number=8
	d.played_cards.clear()
	d.hand_cards.clear()
	d.discard.clear()
	d.side.skills.clear()
	d.play_limit.number=2
	d.regular_play_min.number=2
	var filler=BaseAttack.new("zero_filler","",[],BaseNumber.new(0),BaseNumber.new(0))
	d.hand_cards.append(filler)
	check(not d.servant_skills.is_empty(),"real servant skills exist")
	var skill:BaseSkill=d.servant_skills[0]
	print("PROBE name=",skill.get_shown_name()," cost=",skill._cost.number," awakened=",skill._is_awakened," activating=",skill._is_activating," concealed=",skill._is_concealed)
	print("PROBE candidate=",RegularPlay.candidates(id).has(skill)," faceup=",RegularPlay.faceup_allowed(skill,id)," modes=",RegularPlay.pending_modes(id,[],[],skill)," group=",RegularPlay.can_submit_group(id,[skill,filler],[false,false]))
	check(RegularPlay.candidates(id).has(skill),"real servant skill is a regular-play candidate at eight magic")
	check(RegularPlay.faceup_allowed(skill,id),"real servant skill passes the eight-magic gate")
	check(RegularPlay.pending_modes(id,[],[],skill).has(false),"real servant skill has a faceup pending mode")
	check(RegularPlay.can_submit_group(id,[skill,filler],[false,false]),"real servant skill completes a legal group with a free hand card")
	var slot:Control=ui.get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_SkillsAndPhantasms/VBox/CardsScroll/H/Sk1")
	ui._regular_play_pending_cards=[]
	ui._regular_play_pending_hidden=[]
	ui._fill_skill_slot(slot,skill,true,true)
	var modes:Array=slot.get_meta("regular_play_modes",[])
	check(modes.has(false),"real skill slot stores the faceup mode")
	var ev=InputEventMouseButton.new()
	ev.button_index=MOUSE_BUTTON_LEFT
	ev.pressed=true
	var art_nodes:Array=ui._card_texture_nodes(slot)
	check(not art_nodes.is_empty(),"real skill slot has a card-art input target")
	if not art_nodes.is_empty():
		art_nodes[0].emit_signal("gui_input",ev)
	check(ui._regular_play_pending_cards.has(skill),"clicking the real servant skill card art stages it for play")
	ui._regular_play_pending_cards.clear()
	ui._regular_play_pending_hidden.clear()
	ui._pending_tactical_action.clear()
	var curse=null
	for situation in LoadSituation.situations:
		if situation._name == "curse_of_angra_mainyu":
			curse=situation
			break
	check(curse!=null,"noble-phantasm prohibition situation is loaded")
	if curse!=null:
		MapData.active_situation=curse
		check(BoardHasEffect.new().exec(ForbidNoblePhantasmEffect.EFFECT_NAME),"curse declares an active noble-phantasm prohibition")
		for index in range(d.servant_skills.size()):
			var current:BaseSkill=d.servant_skills[index]
			var allowed:bool=RegularPlay.pending_modes(id,[],[],current).has(false)
			print("CURSE ",current.get_shown_name()," attributes=",current._attributes," allowed=",allowed)
			check(allowed == not current._attributes.has(Attributes.NOBLE_PHANTASM),
				"curse permits only non-noble servant skill %d" % index)
	# 后续断言的前提是"局面没有宝具禁令"。开局随机抽到的局势牌可能正好是禁令，
	# 若沿用先前局面会让宝具技能不合法、把夹具随机性误报成规则 bug，这里显式清空。
	MapData.active_situation=null
	check(not BoardHasEffect.new().exec(ForbidNoblePhantasmEffect.EFFECT_NAME),
		"the fixture runs without a noble-phantasm prohibition")
	for index in range(d.servant_skills.size()):
		var current:BaseSkill=d.servant_skills[index]
		ui._regular_play_pending_cards.clear()
		ui._regular_play_pending_hidden.clear()
		ui._pending_tactical_action.clear()
		if ui.tactical_confirm_modal != null:
			ui.tactical_confirm_modal.visible=false
		var legal:bool=RegularPlay.pending_modes(id,[],[],current).has(false)
		print("SKILL ",index," ",current.get_shown_name()," cost=",current._cost.number," legal=",legal)
		check(legal,"servant skill %d has a legal faceup group at eight magic" % index)
		ui._refresh_clickable_skills(d)
		var bound:Control=null
		for node in ui.skills_scroll_h.get_children():
			if node is Control and node.get_meta("regular_play_card",null)==current:
				bound=node
				break
		check(bound!=null and bound.visible,"servant skill %d is bound to a visible slot" % index)
		if bound==null:
			continue
		var textures:Array=ui._card_texture_nodes(bound)
		check(not textures.is_empty(),"servant skill %d has an art target" % index)
		if not textures.is_empty():
			textures[0].emit_signal("gui_input",ev)
		check(ui._regular_play_pending_cards.has(current),"servant skill %d card-art click stages its own card" % index)
		if DisplayServer.get_name() != "headless" and not textures.is_empty():
			ui._regular_play_pending_cards.clear()
			ui._regular_play_pending_hidden.clear()
			ui._pending_tactical_action.clear()
			ui.refresh_all_ui()
			await get_tree().process_frame
			await get_tree().process_frame
			var rect:Rect2=textures[0].get_global_rect()
			var pos:Vector2=rect.get_center()
			Input.warp_mouse(pos)
			await get_tree().process_frame
			print("HIT ",index," rect=",rect," hovered=",get_viewport().gui_get_hovered_control())
			for pressed in [true,false]:
				var mouse:=InputEventMouseButton.new()
				mouse.button_index=MOUSE_BUTTON_LEFT
				mouse.pressed=pressed
				mouse.position=pos
				mouse.global_position=pos
				get_tree().root.push_input(mouse,true)
			await get_tree().process_frame
			check(ui._regular_play_pending_cards.has(current),"servant skill %d real window click stages its own card" % index)
	print("RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
