extends Node

var checks:int = 0
var failures:Array = []
func check(ok:bool,label:String) -> void:
	checks += 1
	print("CHECK ",label," ",ok)
	if not ok: failures.append(label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var reset:Dictionary = GameData.reset_game_session([0,1])
	check(reset.ok,"PRE public session factory baseline")
	var context:SessionContext = reset.context
	preload("res://scripts/match/rule_random.gd").start_seed(618)
	var event:BaseEvent = LoadEvent.build_event({"card_name":"S1 factory oracle","card_img":"","score":{"number":1,"can_change":true,"is_pure_number":true},"effects":[]},"")
	var situation:BaseSituation = LoadSituation.build_situation({"card_name":"S1 factory oracle","card_img":"","magic":{"number":2,"can_change":true,"is_pure_number":true},"effects":[]},"")
	LoadEvent.events = [event]
	LoadSituation.situations = [situation]
	# 原签名按公开 arity 调用；同一业务 oracle，不把新增尾参解析/arity 错误当业务红。
	var result = MapData.callv("reset_event_deck",[context] if MapData.get_method_argument_count("reset_event_deck") > 0 else [])
	check(result is Dictionary and result.get("ok",false),"event factory returns explicit success")
	check(MapData.event_deck.size() == 1 and SetCardConcealed.source_is_current(MapData.event_deck[0],context),"event factory produces actual source-bound runtime")
	result = MapData.callv("reset_situation_deck",[context] if MapData.get_method_argument_count("reset_situation_deck") > 0 else [])
	check(result is Dictionary and result.get("ok",false),"situation factory returns explicit success")
	check(MapData.situations.size() == 1 and SetCardConcealed.source_is_current(MapData.situations[0],context),"situation factory produces actual source-bound runtime")
	check(not is_same(MapData.situations[0],situation),"situation factory does not publish shared template")
	check(not SessionGeneration.origin_of(event).ok and not SessionGeneration.origin_of(situation).ok,"trusted source templates remain unbound")
	GameData.release_game_objects()
	print("RESULT ",JSON.stringify({"suite":"card_s1_factory_baseline","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
