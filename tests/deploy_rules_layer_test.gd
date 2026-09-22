extends Node
#部署规则必须住在规则层（DeployRules），不能只存在于界面控制器里。
#历史缺陷：_open_deploy_locations / _pick_open_deploy_location / _apply_deploy_benefit
#只写在 tactical_board_ui.gd 里，于是任何不经界面的推进（AI 推演、无界面运行）
#全员都不部署 → 没人在版图上 → 战斗阶段跳过所有人 → 无人获得战果 →
#七人同分 → 高潮日按"并列都不淘汰"一个人都淘汰不掉。
#本测试完全不实例化界面，只用引擎推进。
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)
func setup() -> void:
	EffectManager.reset_runtime(); GameLog.reset(); GameLog.set_context(1,"outpost")
	GameProgress.is_game_over=false
	GameProgress.current_round=1; GameProgress.current_phase_index=1; GameProgress.current_player_id=0
	GameData.player_data_library.clear()
	for i in range(4):
		GameData.player_data_library[i]=GameData.new_player_data()
		var d=GameData.player_data_library[i]
		d.is_out=false
		d.order.set_num(BaseNumber.new(i))
		d.magic.number=0
		d.location=null
	for area in MapData.areas:
		for loc in area._locations:
			(loc._players as Array).clear()
func _ready(): call_deferred("run")
func run():
	setup()
	#规则判定本体在 DeployRules 上，界面只是调用方之一
	check(not DeployRules.open_locations(MapData.magic_workshop).is_empty(),"workshop offers deploy seats")
	check(DeployRules.open_locations(MapData.scout).is_empty(),"scout rejects regular deploy")
	check(not DeployRules.open_locations(MapData.magic_workshop).has(MapData.magic_workshop4),"extra seat is not a deploy seat")
	check(DeployRules.pick_location(MapData.magic_workshop) == MapData.magic_workshop0,"best seat picked first")
	check(not DeployRules.deployable_areas().is_empty(),"some areas are deployable")

	#deploy_to_area 把"挑席位 → 落位 → 结算收益"串起来，供界面/AI/推演共用
	var loc = DeployRules.deploy_to_area(MapData.magic_workshop, 0)
	check(loc == MapData.magic_workshop0,"deploy_to_area lands on the best seat")
	check(GameDataManager.get_player_data(0).location == loc,"player is on the board")
	check(GameDataManager.get_player_data(0).magic.number == 2,"deploy benefit settled by the same entry")
	check(not GameLog.query({"type":"deploy","actor":0}, null).is_empty(),"deploy recorded as a fact")

	#第二个人拿到下一档席位，不会抢同一个
	var loc2 = DeployRules.deploy_to_area(MapData.magic_workshop, 1)
	check(loc2 == MapData.magic_workshop1,"next player takes the next seat")
	check(loc2 != loc,"two players never share one seat")

	#Deploy 要把"有没有真的落位"返回给调用方，否则收益无法按结果结算
	(MapData.miyama0._players as Array).clear()
	check(Deploy.new().exec(MapData.miyama0, 2) == true,"Deploy reports success")
	SetLocationPlNumLimit.new().exec(MapData.miyama0, 0)
	check(Deploy.new().exec(MapData.miyama0, 3) == false,"Deploy reports failure when the seat is full")
	RestoreLocationPlNumLimits.new().exec()

	#前哨行动必须由玩家/AI 显式部署：引擎不得替玩家挑席位推进。
	#旧实现会在结束行动时自动遍历战区替玩家落位，表现为"莫名结束前哨"，
	#还会白送一个玩家没选过的席位收益。
	setup()
	var before:int = GameLog.query({"type":"deploy"}, null).size()
	GameProgress.current_player_id = 0
	check(GameDataManager.get_player_data(0).location == null,"player starts off the board")
	check(not GameProgress.end_current_player_action(),"outpost action is refused before deployment")
	check(GameDataManager.get_player_data(0).location == null,"engine never deploys on the player's behalf")
	check(GameLog.query({"type":"deploy"}, null).size() == before,"a refused action records no deploy")
	#显式部署之后才允许结束，并留下部署事实
	check(DeployRules.deploy_to_area(MapData.magic_workshop, 0) != null,"explicit deployment succeeds")
	check(GameProgress.end_current_player_action(),"outpost action ends after deployment")
	check(GameLog.query({"type":"deploy"}, null).size() > before,"deploy is recorded once it really happened")

	#已经在版图上的不重复部署（界面已替玩家部署过的情况）
	var placed = GameDataManager.get_player_data(0).location
	var count_before:int = GameLog.query({"type":"deploy","actor":0}, null).size()
	GameProgress.current_player_id = 0
	GameProgress.current_phase_index = 1
	GameProgress.end_current_player_action()
	check(GameDataManager.get_player_data(0).location == placed,"already deployed player stays put")
	check(GameLog.query({"type":"deploy","actor":0}, null).size() == count_before,"no duplicate deploy")

	print("RESULT checks=",checks," failures=",failures)
	var f=FileAccess.open("res://deploy_rules_layer_result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures})); f.close()
	get_tree().quit(0 if failures.is_empty() else 1)
