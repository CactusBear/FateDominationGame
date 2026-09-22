extends Node
var failures:Array = []
var checks:int = 0
func check(ok:bool, label:String):
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", label, " ", ok)
func _ready(): call_deferred("run")
func template(pool:Array, key:String):
	for card in pool:
		if card._name == key: return card
	return null
func setup():
	EffectManager.reset_runtime()
	GameLog.reset()
	GameProgress.current_round = 1
	GameLog.set_context(1, "action")
	TimePointChecker.phase_time_points.clear()
	GameData.player_data_library.clear()
	for id in range(2):
		GameData.player_data_library[id] = GameData.new_player_data()
		GameData.player_data_library[id].order.number = id
		GameData.player_data_library[id].is_out = false
	for area in MapData.areas:
		area._events.clear()
		for loc in area._locations: loc._players.clear()
	MapData.active_situation = null
func run():
	setup()
	var area = MapData.areas[1]
	var other = MapData.areas[2]
	GameData.player_data_library[0].location = area._locations[0]
	var card = BaseAttack.new("probe", "", ["strength"], BaseNumber.new(0), BaseNumber.new(2))
	GameData.player_data_library[0].played_cards.append(card)
	GameData.player_data_library[0].power.number = 2
	MapData.event_deck.assign([template(LoadEvent.events, "glorious_duel")])
	AddEventFromDeck.new().exec(area, 1, true)
	check(GetPlayerTotalPower.new().exec(0) == 2, "concealed event contributes nothing")
	EventResolver.new().reveal_planned([{"area_name":area._area_name, "concealed":true}])
	check(GetPlayerTotalPower.new().exec(0) == 4, "revealed event contributes during action")
	var log_count = GameLog.query({}, null).size()
	for i in range(20): GetPlayerTotalPower.new().exec(0)
	check(GameData.player_data_library[0].power.number == 2 and card._power.number == 2, "query never changes power or cards")
	check(GameLog.query({}, null).size() == log_count, "query never records activation or facts")
	GameData.player_data_library[0].location = other._locations[0]
	check(GetPlayerTotalPower.new().exec(0) == 2, "moving out removes event contribution")
	GameData.player_data_library[0].location = area._locations[0]
	var result = BattleResolver.new().exec([0])
	check(result.details_by_area[area._area_name].powers[0].total == 4, "battle uses same total without duplicate")
	check(GameData.player_data_library[0].power.number == 2, "battle does not materialize continuous bonus")

	# 出牌区预览：预估增量并入 total 与明细，但不写回任何玩家数据
	# 基线不写死：此刻场上明置事件牌也在提供加成，直接读查询本身
	var plain_total:int = GetPlayerTotalPower.new().exec(0)
	check(GetPlayerTotalPower.new().exec(0, 4) == plain_total + 4, "the preview increment joins the total")
	check(GetPlayerTotalPower.new().exec(0) == plain_total, "without a preview the total stays as it is")
	var preview_lines:Array = GetPlayerTotalPower.breakdown_lines(0, 4)
	check(preview_lines.has("待确认出牌 +4") and preview_lines.has("合计 %d" % (plain_total + 4)),
		"the breakdown names the pending increment")
	check(not GetPlayerTotalPower.breakdown_lines(0).has("待确认出牌 +4"),
		"no pending line is shown when nothing is pending")
	check(GameData.player_data_library[0].power.number == 2 and card._power.number == 2,
		"the preview never writes power back")
	# 同一条"计不计威力"的规则作用在尚未入场的牌上：明置计入、暗置不计、例外效果照样生效
	var counts = CardCountsPower.new()
	var waiting = BaseAttack.new("waiting", "", ["strength"], BaseNumber.new(1), BaseNumber.new(3))
	check(counts.exec(card, 0) == counts.counts_when_played(card, card._is_concealed, 0),
		"an on board card is judged identically by both entries")
	check(not counts.exec(waiting, 0), "a card not yet on board contributes nothing yet")
	check(counts.counts_when_played(waiting, false, 0), "it would count once played face up")
	check(not counts.counts_when_played(waiting, true, 0), "it would not count if played concealed")
	waiting._effects.append(NeverCountsPowerEffect.new())
	check(not counts.counts_when_played(waiting, false, 0),
		"the never counts power exemption also holds before the card is played")
	waiting._effects.clear()
	waiting._effects.append(CountsPowerWhileConcealedEffect.new())
	check(counts.counts_when_played(waiting, true, 0),
		"the counts while concealed exemption also holds before the card is played")
	setup()
	MapData.reset_event_deck()
	MapData.situations.assign([template(LoadSituation.situations, "battle_of_shinto")])
	SituationResolver.new().activate()
	var before:int = 0
	for a in MapData.areas: before += a._events.size()
	AddEventFromDeck.new().exec(area, 1, true)
	EventResolver.new().reveal_planned([{"area_name":area._area_name, "concealed":true}])
	var after:int = 0
	for a in MapData.areas: after += a._events.size()
	check(after == before + 1, "event entry does not replay situation setup")
	#All migrated templates must clone the declaration and query without side effects.
	setup()
	GameData.player_data_library[0].location = area._locations[0]
	GameData.player_data_library[0].played_cards.append(card)
	GameData.player_data_library[0].power.number = 2
	var migrated:int = 0
	for source in LoadEvent.events + LoadSituation.situations + LoadSituation.climax_situations.values():
		var cloned = CloneObject.new().exec(source)
		if cloned is BaseEvent:
			area._events.assign([cloned])
			cloned.from = area
			MapData.active_situation = null
		else:
			area._events.clear()
			MapData.active_situation = cloned
		for eff in cloned._effects:
			if eff.get("_power_query") == null or eff.get("_power_query").is_empty(): continue
			migrated += 1
			var before_logs = GameLog.query({}, null).size()
			var first = GetPlayerTotalPower.new().exec(0)
			var second = GetPlayerTotalPower.new().exec(0)
			check(first == second and card._power.number == 2 and GameData.player_data_library[0].power.number == 2 and GameLog.query({}, null).size() == before_logs, "pure cloned query " + eff._name)
	check(migrated == 19, "all nineteen continuous declarations cloned")
	# “攻击”按有威力且计入场上的手牌对象判定，不能窄化为 BaseAttack。
	setup()
	var skill_area = MapData.areas[1]
	var owner_data:Dictionary = GameData.player_data_library[0]
	owner_data.location = skill_area._locations[0]
	var power_skill := BaseSkill.new("power_skill", "", ["noble_phantasm"], BaseNumber.new(0), BaseNumber.new(5))
	owner_data.played_cards = [power_skill]
	owner_data.power.number = 5
	var contain = CloneObject.new().exec(template(LoadEvent.events, "contain_third_party"))
	contain.from = skill_area
	skill_area._events = [contain]
	check(BoardPowerQuery.total(0) == 1 and GetPlayerTotalPower.new().exec(0) == 6,
		"contain third party adds power to a faceup five-power skill attack")
	check(power_skill._power.number == 5, "continuous event does not rewrite printed skill power")
	power_skill._is_concealed = true
	check(BoardPowerQuery.total(0) == 0, "concealed skill attack receives no event bonus")
	power_skill._is_concealed = false
	power_skill._power.number = 3
	check(BoardPowerQuery.total(0) == 0, "skill attack below the declared printed threshold receives no bonus")
	setup()
	GameData.player_data_library[0].location = area._locations[0]
	GameData.player_data_library[0].played_cards = [card]
	GameData.player_data_library[0].power.number = 2
	area._events.clear()
	MapData.active_situation = CloneObject.new().exec(template(LoadSituation.situations, "outrage"))
	check(GetPlayerTotalPower.new().exec(0) == 4, "situation applies during action")
	card._is_concealed = true
	GameData.player_data_library[0].power.number = 0
	check(GetPlayerTotalPower.new().exec(0) == 0, "concealed attack loses situation bonus")
	card._is_concealed = false
	GameData.player_data_library[0].power.number = 2
	MapData.active_situation = null
	var fate = CloneObject.new().exec(template(LoadEvent.events, "fate_battle"))
	fate.from = area
	area._events.assign([fate, CloneObject.new().exec(fate)])
	check(GetPlayerTotalPower.new().exec(0) == 5, "fate battle matches JSON numeric printed power")
	#Verify set-value composition remains non-mutating even when two copies match the same card.
	for ev in area._events:
		for eff in ev._effects:
			eff._power_query = [{"func_name":"card_power_contribution", "parameters":[card, BaseNumber.new(0), BaseNumber.new(5), 0]}]
	check(GetPlayerTotalPower.new().exec(0) == 5 and card._power.number == 2, "duplicate set-to contributions do not stack or rewrite cards")
	print("RESULT checks=",checks," failures=",failures)
	var f = FileAccess.open("res://reported_board_power_result.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures}))
	f.close()
	get_tree().quit(0 if failures.is_empty() else 1)
