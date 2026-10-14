extends Node

# B21 :27：只经公开入口造数据、放置、查询资源/事实。缺牌仍输出合法 RESULT。
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
	return BaseMapArea.new("b21-place-area")

func make_template() -> BaseEvent:
	return SOURCE.runtime(LoadEvent.build_event({
		"card_name":"b21-place-template", "card_img":"", "score":{"number":0,"can_change":true,"is_pure_number":true},
		"effects":[{"effect_name":"b21-place-reveal", "time_points":[TimePoints.SELF_CARD_REVEALED],
			"priority":0,"is_pure_passive":true,"is_residue":false,"need_activate":false,
			"effect_numbers":[{"number":1,"can_change":true,"is_pure_number":true}],
			"funcs":[{"func_name":"edit_magic","parameters":[null,{"number_index":0},0]}]}]
	}, "res://newtests"), context)

func magic():
	return GameDataManager.get_player_data(0).magic.number

func run() -> void:
	var area := setup()
	var template := make_template()
	MapData.event_deck.assign([template])
	var no_plan_receipt:Dictionary = await GameProgress.wait_progress_state(EventResolver.new().place([],context),context)
	check(no_plan_receipt.ok and no_plan_receipt.completed,"S1 no_plan receipt accepted and complete")
	var no_plan:Array = no_plan_receipt.get("placed",[])
	check(no_plan.is_empty() and GetEvents.new().exec(area).is_empty() and magic() == 0,
		"B21 放置对照：空计划不入场也不获得魔力")
	# 省略 concealed，直接覆盖 :27 缺省 false 的实参形状。
	var placed_receipt:Dictionary = await GameProgress.wait_progress_state(EventResolver.new().place([{"area_name":"b21-place-area"}],context),context)
	check(placed_receipt.ok and placed_receipt.completed,"S1 placed receipt accepted and complete")
	var placed:Array = placed_receipt.get("placed",[])
	var events:Array = GetEvents.new().exec(area)
	check(placed == [true], "B21 放置正例：有效计划返回一次成功")
	check(events.size() == 1, "B21 放置正例：区域公开查询恰有一张事件")
	# 不用首元素越界把业务红变成脚本崩溃；对象身份断言在缺牌时明确为 false。
	var clone_ok:bool = false
	if events.size() == 1:
		clone_ok = events[0] is BaseEvent and events[0] != template and events[0].from == area
	check(clone_ok, "B21 放置正例：入场为模板克隆且归属目标区域")
	check(MapData.event_deck == [template], "B21 放置正例：模板仍留牌堆而非移入场")
	check(magic() == 1, "B21 放置正例：缺省明置亮出效果实际增加一魔力")
	check(GameLog.query({"type":"effect","data":{"effect_name":"b21-place-reveal"}}, null).size() == 1,
		"B21 放置正例：亮出业务事实只发生一次")

	area = setup()
	template = make_template()
	MapData.event_deck.assign([template])
	var concealed_receipt:Dictionary = await GameProgress.wait_progress_state(EventResolver.new().place([{"area_name":"b21-place-area","concealed":true}],context),context)
	check(concealed_receipt.ok and concealed_receipt.completed,"S1 concealed receipt accepted and complete")
	var concealed:Array = concealed_receipt.get("placed",[])
	check(concealed == [true] and GetEvents.new().exec(area).size() == 1,
		"B21 放置暗置对照：同样入场成功")
	check(magic() == 0 and GameLog.query({"type":"effect","data":{"effect_name":"b21-place-reveal"}}, null).is_empty(),
		"B21 放置暗置对照：尚未亮出不得获得魔力")

	area = setup()
	var empty_deck_receipt:Dictionary = await GameProgress.wait_progress_state(EventResolver.new().place([{"area_name":"b21-place-area"}],context),context)
	check(empty_deck_receipt.ok and empty_deck_receipt.completed,"S1 empty_deck receipt accepted and complete")
	var empty_deck:Array = empty_deck_receipt.get("placed",[])
	check(empty_deck.is_empty() and GetEvents.new().exec(area).is_empty(),
		"B21 放置前置：空牌堆无成功返回也无入场")
	MapData.event_deck.assign([make_template()])
	var unknown_area_receipt:Dictionary = await GameProgress.wait_progress_state(EventResolver.new().place([{"area_name":"b21-missing-area"}],context),context)
	check(unknown_area_receipt.ok and unknown_area_receipt.completed,"S1 unknown_area receipt accepted and complete")
	var unknown_area:Array = unknown_area_receipt.get("placed",[])
	check(unknown_area.is_empty() and GetEvents.new().exec(area).is_empty(),
		"B21 放置前置：无效区域不走放置步骤")
	EffectManager.reset_runtime()
	print("RESULT checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
