extends Node
#局势牌/事件牌的"进场即生效"回归。
#用户现象："局势牌/事件牌的效果没有结算（也可能是没有立刻结算）"、
#"新都之战没有正常加事件牌"。
#根因：局势牌与事件牌进场时不派发任何时点，布置类效果（增加事件牌、封锁战区、
#改席位上限）只能等到战斗阶段的 battle_resolve 才跑一次，整个行动阶段
#玩家都看不到牌面已经宣告的场地变化。
#修法：新增 TimePoints.CARD_ENTERED，局势牌 activate() / 事件牌 reveal_planned()
#派发它，并把布置类效果的数据时点从 battle_resolve 改成 card_entered。
#持续威力通过纯查询在行动阶段生效，战斗不重复写入。
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

func _ready(): call_deferred("run")

func run():
	#——数据层：布置类效果必须挂在进场时点，不能挂结算时点——
	var setup_funcs := ["add_event_from_deck","set_map_area_can_move_to","set_location_pl_num_limit"]
	var wrong:Array = []
	var right:int = 0
	for tmpl in (LoadSituation.situations + LoadSituation.climax_situations.values()):
		if tmpl == null: continue
		for eff in tmpl._effects:
			var names:Array = []
			for f in eff._funcs:
				names.append(str(f._name))
			var is_setup := false
			for sf in setup_funcs:
				if names.has(sf):
					is_setup = true
					break
			if !is_setup: continue
			if eff._time_points.has(TimePoints.CARD_ENTERED):
				right += 1
			else:
				wrong.append("%s / %s" % [tmpl.get_shown_name(), eff.get_shown_name()])
	check(right > 0, "some setup effects declare card_entered")
	check(wrong.is_empty(), "no setup effect left on a resolve-only time point (%s)" % str(wrong))

	#持续修正通过查询求值，不得再进入战斗时点重复写入。
	var power_queries:int = 0
	var duplicate_writes:Array = []
	for tmpl in (LoadSituation.situations + LoadSituation.climax_situations.values()):
		if tmpl == null: continue
		for eff in tmpl._effects:
			if eff._power_query.is_empty(): continue
			power_queries += 1
			if eff._time_points.has(TimePoints.BATTLE_RESOLVE) and not eff._funcs.is_empty():
				duplicate_writes.append(eff._name)
	check(power_queries > 0 and duplicate_writes.is_empty(), "continuous power uses query without duplicate battle writes")

	# 局势牌借顺位玩家 id 排序，但提示中的发动来源必须仍是局势牌，不能显示成锚点玩家效果。
	var killer_template = null
	for tmpl in LoadSituation.situations:
		if tmpl != null and tmpl._name == "killer_in_miyama":
			killer_template = tmpl
			break
	check(killer_template != null, "killer in miyama situation is loadable")
	if killer_template != null:
		setup(1)
		var killer := CloneObject.new().exec(killer_template) as BaseSituation
		MapData.active_situation = killer
		var killer_resolver := SituationResolver.new()
		killer_resolver._register_situation_effects()
		var killer_effect: BaseEffect = killer._effects[0]
		check(EffectManager._effect_actor_name(killer_effect) == "",
			"situation anchor player is not presented as the effect actor")
		check(EffectManager._effect_source_name(killer_effect) == killer.get_shown_name(),
			"situation effect keeps the situation card as its source")
		TimePointChecker.global_time_point([TimePoints.CARD_ENTERED], killer)
		var situation_logs:Array = GameLog.query({"type":"effect", "data":{"effect_name":killer_effect._name}}, null)
		check(not situation_logs.is_empty() and int(situation_logs[0].actor) == -1,
			"situation effect fact does not expose the ordering anchor as actor")

	#——行为层：局势牌进场就把事件牌摆上，不等战斗阶段——
	#找一张带"增加事件牌"的局势牌，直接激活它并检查事件架
	var target = null
	for tmpl in (MapData.situations + LoadSituation.climax_situations.values()):
		if tmpl == null: continue
		for eff in tmpl._effects:
			for f in eff._funcs:
				if str(f._name) == "add_event_from_deck" and eff._time_points.has(TimePoints.CARD_ENTERED):
					target = tmpl
					break
			if target != null: break
		if target != null: break
	check(target != null, "found a situation card that places events on entry")
	if target != null:
		setup(1)
		var before:int = 0
		for area in MapData.areas:
			before += (area._events as Array).size()
		#走真实入场路径：克隆模板挂到激活区，登记效果，派发进场时点
		MapData.active_situation = CloneObject.new().exec(target) as BaseSituation
		var res := SituationResolver.new()
		res._register_situation_effects()
		TimePointChecker.global_time_point([TimePoints.CARD_ENTERED])
		var after:int = 0
		for area in MapData.areas:
			after += (area._events as Array).size()
		check(after > before, "events are placed the moment the situation card enters (%d -> %d)" % [before, after])
		#这一步没有经过战斗阶段：证明不是靠 battle_resolve 才生效的
		check(GameLog.query({"type":"battle"}, null).is_empty(), "no battle happened, so it was not the resolve step")

	#——进场时点是全局时点：所有玩家都该收到，效果的作用范围由效果自己决定——
	setup(1)
	for id in GameDataManager.get_active_player_ids():
		var listener:=BaseEffect.new("entry_listener_%d" % id,[TimePoints.CARD_ENTERED],0,true,false)
		listener._need_activate=false
		listener._funcs=LoadHelper.load_funcs([{"func_name":"do_nothing","parameters":[],"var_index":-1}],listener)
		EffectManager.register_effect(listener,id)
	TimePointChecker.global_time_point([TimePoints.CARD_ENTERED])
	var got:int = 0
	var consumed:bool = true
	for id in GameDataManager.get_active_player_ids():
		if GameLog.query({"type":"effect","actor":id,"data":{"effect_name":"entry_listener_%d" % id}},0).size()==1:
			got += 1
		var tps:Array = GameDataManager.get_player_data(id)["current_time_points"]
		consumed = consumed and not tps.has(TimePoints.CARD_ENTERED)
	check(got == GameDataManager.get_active_player_ids().size(), "card_entered reaches every active player")
	check(consumed,"entry event is consumed after dispatch rather than replayed later")

	print("RESULT checks=",checks," failures=",failures)
	var f=FileAccess.open("res://card_entered_result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures})); f.close()
	get_tree().quit(0 if failures.is_empty() else 1)
