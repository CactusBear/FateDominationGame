extends Node
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)
func _ready(): call_deferred("run")
func run():
	var scene=load("res://assets/scenes/game_scene/tactical_board_ui.tscn").instantiate()
	get_tree().root.add_child(scene); scene.set_process(false)
	EventResolver.new().clear_all()
	SituationResolver.new().clear_all()
	EffectManager.reset_runtime(); GameLog.reset(); GameLog.set_context(1,"outpost")
	GameProgress.current_round=1; GameProgress.current_phase_index=1; GameProgress.current_player_id=0
	#额外席位：容量不限，但不参与常规部署（常规移动本来也进不去，它没有 _will_move_to）
	check(MapData.magic_workshop4._pl_num_limit == -1,"workshop extra seat capacity unlimited")
	check(MapData.scout1._pl_num_limit == -1,"scout extra seat capacity unlimited")
	check(not scene._open_deploy_locations(MapData.magic_workshop).has(MapData.magic_workshop4),"workshop extra seat is not a deploy seat")
	check(not scene._open_deploy_locations(MapData.scout).has(MapData.scout1),"scout extra seat is not a deploy seat")
	check(scene._open_deploy_locations(MapData.scout).is_empty(),"scout rejects regular deploy")
	check(GetMoveTargetLocation.new().exec(MapData.magic_workshop) != MapData.magic_workshop4,"extra seat is not a move target")
	#常规部署按席位数依次占：+2 先占，再依次占三个 +1
	check(scene._pick_open_deploy_location(MapData.magic_workshop) == MapData.magic_workshop0,"best seat taken first")
	Deploy.new().exec(MapData.magic_workshop0, 0)
	check(scene._pick_open_deploy_location(MapData.magic_workshop) == MapData.magic_workshop1,"next seat in order")
	Deploy.new().exec(MapData.magic_workshop1, 1)
	Deploy.new().exec(MapData.magic_workshop2, 2)
	Deploy.new().exec(MapData.magic_workshop3, 3)
	check(scene._open_deploy_locations(MapData.magic_workshop).is_empty(),"workshop full at four players")
	check(scene._pick_open_deploy_location(MapData.magic_workshop) == null,"fifth player has no workshop seat")
	#部署收益：席位的魔力由调用方组合 edit_magic 结算，数字读席位数据
	var d0 = GameData.player_data_library[0]
	d0.magic.number=0
	scene._apply_deploy_benefit(MapData.magic_workshop0, 0)
	check(d0.magic.number == 2,"deploy to plus two seat gains two magic")
	var d1 = GameData.player_data_library[1]
	d1.magic.number=0
	scene._apply_deploy_benefit(MapData.magic_workshop1, 1)
	check(d1.magic.number == 1,"deploy to plus one seat gains one magic")
	var d5 = GameData.player_data_library[5]
	d5.magic.number=0
	scene._apply_deploy_benefit(MapData.magic_workshop1, 5)
	check(d5.magic.number == 0,"no magic when not settled")
	#地利只在“部署到该位置”时成立。
	#清空全盘（席位 + 所有人 location）再显式摆位：只清席位会留下
	#"人不在席位上、location 仍指着它"的脏占位，随后的 SetLocation 会被它挡住，
	#断言就随 GameStart 的随机部署偶发失败
	GameLog.reset(); GameLog.set_context(1,"battle")
	for area in MapData.areas:
		for loc in area._locations:
			(loc._players as Array).clear()
	for pid in GameData.player_data_library.keys():
		GameData.player_data_library[pid].location = null
	Deploy.new().exec(MapData.miyama0, 5)
	check(GetLocation.new().exec(5) == MapData.miyama0,"deploy places the player onto the seat")
	check(GetEffectiveLocationBenefit.new().exec(5) == 3,"deploy to plus three seat grants benefit")
	check(SetLocation.new().exec(MapData.miyama1, 5, true), "benefit fixture really moves to another seat")
	check(GetEffectiveLocationBenefit.new().exec(5) == 0,"arriving by move gives no benefit")
	#额外席位与侦察：容量不限但常规部署进不去
	check(SetLocation.new().exec(MapData.magic_workshop4, 5, false),"effect can place into extra seat")
	check(MapData.magic_workshop4._players.has(5),"extra seat holds the placed player")
	check(not scene._open_deploy_locations(MapData.magic_workshop).has(MapData.magic_workshop4),"extra seat is not a deploy seat")
	#部署魔力的来源名由数据声明（限制类效果按它查询，不在代码里写死"workshop"）
	check(MapData.magic_workshop._magic_source == "workshop","workshop seat declares magic source")
	print("RESULT checks=",checks," failures=",failures)
	var f=FileAccess.open("res://deploy_test_result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures})); f.close()
	get_tree().quit(0 if failures.is_empty() else 1)
