extends Node
# 三条回归：
#  ① 技能区的卡位顺序必须与场景树顺序一致——升华技不能再插到从者技能牌旁边
#  ② 【宝石】按数据声明改由玩家主动发动：不进自动询问队列，卡位自带发动入口
#  ③ 远坂凛「绝对服从的命令」：第一回合行动阶段没用令咒就不允许结束行动
var failures:Array=[]
var checks:int=0
var host:Node=null

func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)

func _ready(): call_deferred("run")

func find_card(pool:Array, card_name:String):
	for card in pool:
		if card != null and str(card._name) == card_name:
			return card
	return null

## 卡位承载的对象：展示卡位存 display_object，技能卡位存 regular_play_card。
## 两种都要读——只认一种会把另一类卡位当成空的
func slot_object(child:Node):
	for key in ["display_object", "regular_play_card"]:
		# 缺键的 get_meta 会刷 error 级日志，先 has_meta 再读
		if child.has_meta(key):
			var value = child.get_meta(key)
			if value != null:
				return value
	return null

## 卡位在技能区行里的实际次序（跳过分隔线）
func slot_index_of(row:Control, obj) -> int:
	var index:int = 0
	for child in row.get_children():
		if child is Separator:
			continue
		if slot_object(child) == obj:
			return index
		index += 1
	return -1

func has_slot_for(row:Control, obj) -> bool:
	return slot_index_of(row, obj) >= 0

func run():
	host=load("res://assets/scenes/game_scene/tactical_board_ui.tscn").instantiate()
	get_tree().root.add_child(host)
	host.set_process(false)
	var local:int=GameData.player_id
	var d:Dictionary=GameData.player_data_library[local]

	# —— 行动阶段窗口：宝石的声明时点在这里，主动发动与自动询问的差别也在这里暴露 ——
	GameProgress.current_phase_index=2
	GameProgress.current_player_id=local
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE,
		TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX])
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX], local)
	host.refresh_all_ui()

	var jewel=find_card(d.master._other_things, "jewel_card")
	check(jewel!=null,"Rin owns a real jewel card")
	var jewel_effects:Array=[]
	if jewel!=null and jewel.get("_relate_buff")!=null:
		jewel_effects=jewel.get("_relate_buff")._effects
	var declining:Array=[]
	for effect in jewel_effects:
		if effect._is_manual:
			declining.append(effect)
	check(declining.size()==jewel_effects.size() and not jewel_effects.is_empty(),
		"every jewel ability is declared as player-activated")
	# 主动发动类效果不进自动询问队列：进了队列就等于每个行动阶段自动弹窗。
	# 判据取"本时点命中的效果记录"——它只对通过手动筛选的效果写入
	var auto_queued:Array=[]
	for effect in jewel_effects:
		if EffectManager.decision_queue.has(effect) or EffectManager.activation_pool.has(effect) \
				or EffectManager.matched_time_points.has(effect):
			auto_queued.append(effect._name)
	check(auto_queued.is_empty(),"jewel abilities are not auto-asked")

	# —— ① 技能区位置：升华技排在所有从者技能牌之后 ——
	var row:Control=host.skills_scroll_h
	var servant_skills:Array=d.get("servant_skills", []).duplicate()
	var upgrade:Array=d.master._upgrade_skill.duplicate()
	check(servant_skills.size()>0 and upgrade.size()>0,"fixture has both servant skills and an upgrade skill")
	var upgrade_index:int=slot_index_of(row, upgrade[0])
	check(upgrade_index>=0,"the upgrade skill has its own slot")
	var min_servant_index:int=999
	for skill in servant_skills:
		var at:int=slot_index_of(row, skill)
		if at>=0 and at<min_servant_index:
			min_servant_index=at
	check(upgrade_index>min_servant_index,"the upgrade skill sits after the servant skills, not beside them")
	# 升华技必须是这一行最后一个可见卡位：它是觉醒后才启用的牌，混在中间会被当成现在能用
	var last_index:int=-1
	var last_obj=null
	var index:int=0
	for child in row.get_children():
		if child is Separator:
			continue
		var holder = slot_object(child)
		if holder!=null and (child as Control).visible:
			last_index=index
			last_obj=holder
		index+=1
	check(last_obj==upgrade[0],"the upgrade skill occupies the last slot of the row")
	# 铺卡顺序与子节点顺序必须一致：数组顺序若与树序不符，卡会落到别的分区
	var groups:Array=host._collect_uncataloged_card_groups(d)
	var widths:Array=row.get_meta("group_slot_widths", [])
	check(widths.size()==groups.size(),"one slot segment per card group")

	# —— ② 宝石卡位是发动入口 ——
	if jewel!=null:
		var jewel_slot:Control=null
		for child in row.get_children():
			if child is Control and slot_object(child)==jewel:
				jewel_slot=child
		check(jewel_slot!=null,"the jewel card has a slot")
		if jewel_slot!=null:
			check(jewel_slot.has_meta("manual_effect_click_bound"),"the jewel slot is wired as an activation entry")
			# 提示状态落在卡图那一层：节流刷新与金框都按卡图读，写卡位等于没写
			var jewel_art:Control=host._card_art_of(jewel_slot)
			check(jewel_art!=null and bool(jewel_art.get_meta("playable_hint", false)),
				"the jewel slot shows its activation hint while usable")
			# 光晕是否真的画出来：节点存在且可见才算，只看状态位会漏掉"创建了但没显示"
			var glow:Control=jewel_art.get_node_or_null("ClickableGlow") if jewel_art!=null else null
			check(glow!=null and glow.visible,"the jewel slot draws its breathing frame while usable")
			# 能点着发动：卡图节点默认吃点击(mouse_filter=STOP)，只把回调接在卡位上时
			# 点卡面永远到不了卡位——必须两处都接（与待确认出牌卡位同一做法）。
			# 判据要认准"发动入口那条连接"：卡图上本来就有悬停放大等别的 gui_input 连接，
			# 只数"有没有连接"会在撤掉修复后照样通过（假回归）
			var manual_bound:bool=false
			for conn in jewel_art.get_signal_connection_list("gui_input"):
				var cb:Callable=conn["callable"]
				if cb.get_object()==host and str(cb.get_method())=="_on_manual_effect_slot_clicked":
					manual_bound=true
			check(manual_bound,"the jewel card art forwards clicks to the activation entry")
			check(host._manual_effects_of(jewel).size()>0,"the jewel card exposes a usable manual ability")
			# 轮到别人时不能亮：宝石只在本人的行动阶段可发动
			GameProgress.current_player_id=(local+1)%GameData.player_data_library.size()
			host.refresh_all_ui()
			check(host._manual_effects_of(jewel).is_empty(),"another player's turn offers no jewel ability")
			check(not bool(jewel_art.get_meta("playable_hint", false)),"the jewel frame goes out on another player's turn")
			GameProgress.current_player_id=local
			host.refresh_all_ui()

	# —— ③ 绝对服从的命令：硬约束 ——
	check(d.get("action_requirements", []).has(ActionRules.COMMAND_SPELL_USED),
		"the declared requirement is installed when the game starts")
	check(not ActionRules.can_end_action(local),"the action cannot end before the required command spell is used")
	check(ActionRules.block_reason(local)!="","the block carries a reason for the player")
	var block_before:int=ActionRules.block_reason(local).length()
	check(not GameProgress.end_current_player_action(),"the engine refuses to end the action")
	check(ActionRules.block_reason(local).length()==block_before,"the refused action leaves the requirement untouched")

	# 例外：手上没有能发动的令咒时，这条要求无法履行，不能把玩家永久卡在阶段里
	var spells_before:int=d.command_spell_count.number
	d.command_spell_count.number=0
	check(ActionRules.block_reason(local)=="","the requirement is waived when no command spell can be used")
	d.command_spell_count.number=spells_before

	# 走真实链路用掉一枚令咒：请求 → 选项 → 结算
	var usable:Array=host._usable_command_spell_effects()
	check(not usable.is_empty(),"a command spell can be activated in the action phase")
	var spent_before:int=d.command_spell_count.number
	if usable.is_empty():
		# 前置不成立时也要显式记一条失败：静默跳过会让这一整段断言在回归里消失
		check(false,"the command spell chain could not be exercised")
	else:
		check(EffectManager.request_manual_activation(usable[0], local),"the command spell opens a real pending choice")
		check(EffectManager.submit_option_choice(usable[0], [0]),"the pending command choice resolves")
		check(d.command_spell_count.number==spent_before-1,"using a command spell spends one")
		check(not GameLog.query({"type":ActionRules.COMMAND_SPELL_USED,"actor":local},0).is_empty(),
			"the command spell usage is recorded as a fact")
		check(ActionRules.can_end_action(local),"the requirement is satisfied after using a command spell")

	# 到期解除：第一回合结束时摘掉这条要求，之后不再阻塞
	TimePointChecker.global_time_point([TimePoints.DAY_END])
	check(not d.get("action_requirements", []).has(ActionRules.COMMAND_SPELL_USED),
		"the requirement is lifted at the end of the first round")

	print("RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
