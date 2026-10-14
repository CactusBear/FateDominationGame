extends Node

# B21 :91：注销是否生效由后续真实资源变化/效果事实证明，不读私有效果池。
var checks:int = 0
var failures:Array = []
var context:SessionContext
const SOURCE = preload("res://newtests/s1_signature_fixture.gd")

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func setup() -> BaseMapArea:
	var prepared:Dictionary = GameData.reset_game_session([0])
	context = prepared.context
	preload("res://scripts/match/rule_random.gd").start_seed(817)
	EffectManager.configure_runtime_guard({"enabled":false,"steps":0,"seconds":0.0})
	GameLog.reset()
	GameLog.set_context(1, "action")
	GameProgress.is_game_over = false
	GameProgress.current_round = 1
	TimePointChecker.set_phase_time_points([])
	GameData.player_data_library.clear()
	GameData.player_data_library[0] = GameData.new_player_data()
	GameDataManager.get_player_data(0).is_out = false
	GameData.player_data_library[0].magic.number = 0
	MapData.areas.clear()
	MapData.event_discard.clear()
	MapData.event_deck.clear()
	return BaseMapArea.new("b21-unregister-area")

func enter(area:BaseMapArea) -> BaseEvent:
	var event:BaseEvent = SOURCE.runtime(LoadEvent.build_event({
		"card_name":"b21-unregister-event", "card_img":"", "score":{"number":0,"can_change":true,"is_pure_number":true},
		"effects":[{"effect_name":"b21-unregister-listener", "time_points":[TimePoints.DAY_START],
			"priority":0,"is_pure_passive":true,"is_residue":false,"need_activate":false,
			"effect_numbers":[{"number":1,"can_change":true,"is_pure_number":true}],
			"funcs":[{"func_name":"edit_magic","parameters":[null,{"number_index":0},0]}]}]
	}, "res://newtests"),context)
	AddMapAreaEvents.new().exec(area, event)
	check(EventResolver.new().register_entered(event,context),"S1 runtime event registration accepted")
	return event

func magic():
	return GameDataManager.get_player_data(0).magic.number

func facts() -> int:
	return GameLog.query({"type":"effect","data":{"effect_name":"b21-unregister-listener"}}, null).size()

func run() -> void:
	var area := setup()
	var event := enter(area)
	check(GetEvents.new().exec(area) == [event] and magic() == 0 and facts() == 0,
		"B21 注销对照前置：监听牌入场但非亮出时点效果未结算")
	TimePointChecker.global_time_point([TimePoints.DAY_START],null,context)
	check(magic() == 1 and facts() == 1,
		"B21 注销留场对照：后续时点确实增加一魔力并留下事实")

	area = setup()
	event = enter(area)
	check(EventResolver.new().clear_all(context).ok,"S1 event cleanup accepted")
	check(GetEvents.new().exec(area).is_empty(), "B21 注销正例：清理后区域无事件")
	check(MapData.event_discard == [event], "B21 注销正例：同一事件对象移入公开弃牌区")
	TimePointChecker.global_time_point([TimePoints.DAY_START],null,context)
	check(magic() == 0, "B21 注销正例：离场监听不得在后续时点增加魔力")
	check(facts() == 0, "B21 注销正例：离场监听不得产生后续效果事实")
	# 重复清理不能删掉回看对象，也不能让已注销效果重新生效。
	check(EventResolver.new().clear_all(context).ok,"S1 event cleanup accepted")
	TimePointChecker.global_time_point([TimePoints.DAY_START],null,context)
	check(MapData.event_discard == [event] and magic() == 0 and facts() == 0,
		"B21 注销正例：重复清理保持弃牌身份且不复活监听")
	EffectManager.reset_runtime()
	print("RESULT checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
