extends Node
#所有卡牌亮出时点回归：任意卡牌、自身卡牌、其他卡牌。
#真实派发统一走 TimePointChecker.card_revealed(card)，由 source 与 effect.from
#决定 SELF_CARD_REVEALED / OTHERS_CARD_REVEALED 是否命中。
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)

func setup(round:int) -> void:
	EffectManager.reset_runtime(); GameLog.reset(); GameLog.set_context(round,"situation")
	GameProgress.is_game_over=false
	GameProgress.current_round=round
	GameData.player_data_library.clear()
	for i in range(4):
		GameData.player_data_library[i]=GameData.new_player_data()
		var d=GameData.player_data_library[i]
		d.is_out=false
		d.order.set_num(BaseNumber.new(i))
		d.magic.number=0
	MapData.reset_event_deck()
	for area in MapData.areas:
		(area._events as Array).clear()

func make_reveal_listener(effect_name:String, time_point:String, player_id:int, owner = null) -> BaseEffect:
	var listener:=BaseEffect.new(effect_name,[time_point],0,true,false)
	listener._need_activate=false
	listener._funcs=LoadHelper.load_funcs([{"func_name":"do_nothing","parameters":[],"var_index":-1}],listener)
	if owner != null: listener.from=owner
	EffectManager.register_effect(listener,player_id)
	return listener

func has_effect_log(effect_name:String) -> bool:
	return not GameLog.query({"type":"effect", "data":{"effect_name":effect_name}}, null).is_empty()

func _ready(): call_deferred("run")

func run():
	#——数据层：布置类效果属于亮出卡牌自身——
	var setup_funcs := ["add_event_from_deck","set_map_area_can_move_to","set_location_pl_num_limit"]
	var wrong:Array = []
	var right:int = 0
	for tmpl in (LoadSituation.situations + LoadSituation.climax_situations.values()):
		if tmpl == null: continue
		for eff in tmpl._effects:
			var names:Array = []
			for f in eff._funcs: names.append(str(f._name))
			var is_setup := false
			for sf in setup_funcs:
				if names.has(sf): is_setup = true; break
			if !is_setup: continue
			if eff._time_points.has(TimePoints.SELF_CARD_REVEALED): right += 1
			else: wrong.append("%s / %s" % [tmpl.get_shown_name(), eff.get_shown_name()])
	check(right > 0, "setup effects declare self_card_revealed")
	check(wrong.is_empty(), "no setup effect uses an incorrect reveal time point (%s)" % str(wrong))

	#持续修正通过查询求值，不得再进入战斗时点重复写入。
	var power_queries:int = 0
	var duplicate_writes:Array = []
	for tmpl in (LoadSituation.situations + LoadSituation.climax_situations.values()):
		if tmpl == null: continue
		for eff in tmpl._effects:
			if eff._power_query.is_empty(): continue
			power_queries += 1
			if eff._time_points.has(TimePoints.BATTLE_RESOLVE) and not eff._funcs.is_empty(): duplicate_writes.append(eff._name)
	check(power_queries > 0 and duplicate_writes.is_empty(), "continuous power uses query without duplicate battle writes")

	var killer_template = null
	for tmpl in LoadSituation.situations:
		if tmpl != null and tmpl._name == "killer_in_miyama": killer_template = tmpl; break
	check(killer_template != null, "killer in miyama situation is loadable")
	if killer_template != null:
		setup(1)
		var killer := CloneObject.new().exec(killer_template) as BaseSituation
		MapData.active_situation = killer
		SituationResolver.new()._register_situation_effects()
		var killer_effect:BaseEffect = killer._effects[0]
		TimePointChecker.card_revealed(killer)
		var situation_logs:Array = GameLog.query({"type":"effect", "data":{"effect_name":killer_effect._name}}, null)
		check(not situation_logs.is_empty() and int(situation_logs[0].actor) == -1, "situation self reveal effect resolves")

	#——三种语义：同一张卡、其他卡、任意卡分别验证——
	setup(1)
	var source_card := CloneObject.new().exec(killer_template) as BaseSituation
	var other_card := CloneObject.new().exec(killer_template) as BaseSituation
	make_reveal_listener("self_match", TimePoints.SELF_CARD_REVEALED, 0, source_card)
	make_reveal_listener("self_miss", TimePoints.SELF_CARD_REVEALED, 0, other_card)
	make_reveal_listener("other_match", TimePoints.OTHERS_CARD_REVEALED, 0, other_card)
	make_reveal_listener("other_miss", TimePoints.OTHERS_CARD_REVEALED, 0, source_card)
	make_reveal_listener("any_match", TimePoints.CARD_REVEALED, 0, other_card)
	TimePointChecker.card_revealed(source_card)
	check(has_effect_log("self_match"), "self_card_revealed matches the revealing card")
	check(not has_effect_log("self_miss"), "self_card_revealed ignores another card")
	check(has_effect_log("other_match"), "others_card_revealed matches another card")
	check(not has_effect_log("other_miss"), "others_card_revealed ignores its own card")
	check(has_effect_log("any_match"), "card_revealed matches any card regardless of source")

	#——行为层：局势牌亮出就把事件牌摆上，不等战斗阶段——
	var target = null
	for tmpl in (MapData.situations + LoadSituation.climax_situations.values()):
		if tmpl == null: continue
		for eff in tmpl._effects:
			for f in eff._funcs:
				if str(f._name) == "add_event_from_deck" and eff._time_points.has(TimePoints.SELF_CARD_REVEALED): target = tmpl; break
			if target != null: break
		if target != null: break
	check(target != null, "found a situation card that places events on self reveal")
	if target != null:
		setup(1)
		var before:int = 0
		for area in MapData.areas: before += (area._events as Array).size()
		var active := CloneObject.new().exec(target) as BaseSituation
		MapData.active_situation = active
		SituationResolver.new()._register_situation_effects()
		TimePointChecker.card_revealed(active)
		var after:int = 0
		for area in MapData.areas: after += (area._events as Array).size()
		check(after > before, "events are placed when the situation card reveals (%d -> %d)" % [before, after])
		check(GameLog.query({"type":"battle"}, null).is_empty(), "no battle happened before reveal effect")

	#无 source 的普通时点广播仍可用于测试/特殊系统逻辑，并会被一次性消费。
	setup(1)
	for id in GameDataManager.get_active_player_ids(): make_reveal_listener("any_listener_%d" % id, TimePoints.CARD_REVEALED, id)
	TimePointChecker.global_time_point([TimePoints.CARD_REVEALED])
	var got:int = 0
	var consumed:bool = true
	for id in GameDataManager.get_active_player_ids():
		if has_effect_log("any_listener_%d" % id): got += 1
		consumed = consumed and not (GameDataManager.get_player_data(id)["current_time_points"] as Array).has(TimePoints.CARD_REVEALED)
	check(got == GameDataManager.get_active_player_ids().size(), "card_revealed without source reaches every active player")
	check(consumed, "reveal event is consumed after dispatch")

	print("RESULT checks=",checks," failures=",failures)
	var f=FileAccess.open("res://card_revealed_result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures})); f.close()
	get_tree().quit(0 if failures.is_empty() else 1)
