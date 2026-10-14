extends "res://tests/section5_engine_test.gd"

#复用既有 AddPlayer 全部基础 oracle，不复制/修改任何 check。
#生命周期准备移到真实父根创建处；运行既有用例时，不在函数帧中再次换局。
var begin_basics:bool = false:
	set(value):
		begin_basics = value
		if value:
			test_registry()
			test_add_player_basics()

func setup(count:int = 2) -> void:
	#本场景只运行原基础创建用例；与原 setup(2) 同样的全新成员与地图初值。
	check(count == 2 and GameData.player_data_library.keys() == [0, 1], "PRE original basics receives two fresh members")
	GameProgress.is_game_over = false
	GameProgress.current_phase_index = -1
	GameProgress.current_player_id = -1
	for area in MapData.areas:
		area._battle_override = {}
		area._events.clear()
		for loc in area._locations: loc._players.clear()

func _ready() -> void:
	var lifecycle:Dictionary = GameData.reset_game_session([0, 1])
	check(lifecycle.ok, "PRE explicit fixture lifecycle")
	GameData.player_id = 0
	GameLog.reset()
	for id in [0, 1]:
		var data:Dictionary = GameData.player_data_library[id]
		data.is_out = false
		data.order.set_num(BaseNumber.new(id))
	var produced:Array = LoadHelper.load_effects([{"effect_name":"a1_32_existing_basics", "time_points":[],"priority":0,"is_pure_passive":true,"is_residue":false,"effect_numbers":[],"funcs":[{"func_name":"set_property","parameters":[self,"begin_basics",true]}]}], null, lifecycle.context)
	check(produced.size() == 1, "PRE trusted frame factory")
	if produced.is_empty():
		print("RESULT ", JSON.stringify({"suite":"a1_32_existing_addplayer_basics","checks":checks,"failures":failures}))
		get_tree().quit(1)
		return
	var root:BaseEffect = produced[0]
	check(EffectManager.register_effect(root, 0), "PRE original-source frame root registered")
	var result:Array = EffectManager.run_base_func(root._funcs[0], root, lifecycle.context)
	check(result[0], "PRE original basics actually invoked in verified frame")
	print("RESULT ", JSON.stringify({"suite":"a1_32_existing_addplayer_basics","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
