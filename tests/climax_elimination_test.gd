extends Node
#高潮淘汰的规则测试。规则原文：
#第8天回合结束时，除战果前4名外全部淘汰；第9天前3名；第10天前2名。
#战果并列（或因效果免于淘汰）的玩家都不淘汰。
#用户现象："高潮第二天没有继续淘汰人"——只淘汰一次或完全不淘汰。
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)
func setup(count:int) -> void:
	EffectManager.reset_runtime(); GameLog.reset(); GameLog.set_context(1,"")
	GameData.player_data_library.clear()
	for i in range(count):
		GameData.player_data_library[i]=GameData.new_player_data()
		var d=GameData.player_data_library[i]
		d.is_out=false
		d.order.set_num(BaseNumber.new(i))
		#战果各不相同，排名明确：i 越大战果越高
		d.score.set_num(BaseNumber.new(i))
func _ready(): call_deferred("run")
func run():
	#保留人数的声明必须存在，且键要能被 end_round 的回合号命中
	check(not GameProgress.climax_keep_counts.is_empty(),"climax keep counts declared")
	var keep_rounds:Array = GameProgress.climax_keep_counts.keys()
	print("declared climax keep rounds=",keep_rounds)

	#逐个声明的回合验证：淘汰后剩下的人数应等于声明的保留数
	for r in keep_rounds:
		setup(7)
		var keep:BaseNumber = GameProgress.climax_keep_counts[r]
		var kept:Array = ClimaxResolver.new().exec(keep)
		var active:Array = GameDataManager.get_active_player_ids()
		check(active.size() == keep.number,
			"round %d keeps %d players" % [int(r), keep.number])
		check(kept.size() == keep.number, "round %d returns the kept list" % int(r))

	#连续两个高潮日都要继续淘汰：先淘到4人，再淘到3人
	setup(7)
	var r1:Array = ClimaxResolver.new().exec(BaseNumber.new(4))
	check(GameDataManager.get_active_player_ids().size() == 4,"first climax day cuts to four")
	var r2:Array = ClimaxResolver.new().exec(BaseNumber.new(3))
	check(GameDataManager.get_active_player_ids().size() == 3,"second climax day keeps cutting")
	var r3:Array = ClimaxResolver.new().exec(BaseNumber.new(2))
	check(GameDataManager.get_active_player_ids().size() == 2,"third climax day keeps cutting")

	#规则：战果并列的玩家都不淘汰（保留线上的同分全部保留）
	setup(5)
	for i in range(5):
		GameData.player_data_library[i].score.set_num(BaseNumber.new(3))
	ClimaxResolver.new().exec(BaseNumber.new(2))
	check(GameDataManager.get_active_player_ids().size() == 5,"all tied players survive the cut")

	#淘汰要留下事实日志，并把人移出版图
	setup(3)
	MapData.miyama0._players = []
	Deploy.new().exec(MapData.miyama0, 0)
	check(GameDataManager.get_player_data(0).location == MapData.miyama0,"player deployed before the cut")
	ClimaxResolver.new().exec(BaseNumber.new(2))
	check(GameDataManager.get_player_data(0).is_out,"lowest score player is out")
	check(GameDataManager.get_player_data(0).location == null,"eliminated player left the board")
	check(not MapData.miyama0._players.has(0),"seat no longer holds the eliminated player")
	check(not GameLog.query({"type":"eliminated","actor":0}, null).is_empty(),"elimination recorded as a fact")

	print("RESULT checks=",checks," failures=",failures)
	var f=FileAccess.open("res://climax_elimination_result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"keep_rounds":keep_rounds})); f.close()
	get_tree().quit(0 if failures.is_empty() else 1)
