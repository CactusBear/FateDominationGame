extends Node
#规则：与至少一名对手同处一处会发生战斗的战场（即处于交战状态）时，
#常规出的一组牌里至少要有一张明置。
#非交战（该战场没有对手，敌人离开后就是这样）与工房/侦察这类不会发生战斗的地点，
#两张都暗置都合法——"战场"在这里指交战，不指"站进了某个计分战区"。
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)
## 放一名对手进指定战区，让玩家0真正处于交战状态。
## 交战判定按地图数据的战区归属走，不写死战区名。
func _engage(area:BaseMapArea, opp_id:int=1)->void:
	if not GameData.player_data_library.has(opp_id):
		GameData.player_data_library[opp_id]=GameData.new_player_data()
	var opp=GameData.player_data_library[opp_id]
	opp.is_out=false
	opp.location=area._locations[0]
	(area._locations[0]._players as Array).append(opp_id)
func setup(magic:int=10)->Dictionary:
	EffectManager.reset_runtime(); GameLog.reset(); GameLog.set_context(1,"action")
	GameProgress.is_game_over=false
	GameProgress.current_round=1; GameProgress.current_phase_index=2; GameProgress.current_player_id=0
	GameData.player_data_library.clear()
	GameData.player_data_library[0]=GameData.new_player_data()
	var d=GameData.player_data_library[0]; d.is_out=false; d.magic.number=magic
	d.hand_cards=[]
	for i in range(4):
		d.hand_cards.append(BaseAttack.new("a%d"%i,"",[],BaseNumber.new(2),BaseNumber.new(3)))
	return d
func _ready(): call_deferred("run")
func run():
	#交战战场：第一张暗置可以，但第二张不能再暗置（否则整组没有明置牌）
	var d=setup(); d.location=MapData.miyama0
	_engage(MapData.miyama)
	var c=d.hand_cards.duplicate()
	check(RegularPlay.battlefield(d),"an engaged player counts as being on a battlefield")
	check(RegularPlay.add(0,c[0],true),"first card may be concealed on a battlefield")
	check(not RegularPlay.can_add(0,c[1],true),"second card cannot also be concealed on a battlefield")
	check(RegularPlay.modes(0,c[1]) == [false],"only faceup remains legal for the last card")
	check(RegularPlay.add(0,c[1],false),"faceup second card completes the group")
	check(RegularPlay.completed(0),"group completed with one faceup card")

	#已经有一张明置之后，再暗置是允许的（规则只要求"至少一明"）
	d=setup(); d.location=MapData.miyama0; d.play_limit.number=3
	_engage(MapData.miyama)
	c=d.hand_cards.duplicate()
	check(RegularPlay.add(0,c[0],false),"faceup first card")
	check(RegularPlay.can_add(0,c[1],true),"concealed allowed once a faceup card exists")

	#非战场：两张都暗置是合法的，不能被"至少一明"误伤
	d=setup(); d.location=MapData.magic_workshop0
	c=d.hand_cards.duplicate()
	check(not RegularPlay.battlefield(d),"workshop is not a battlefield")
	check(RegularPlay.add(0,c[0],true),"first concealed card off battlefield")
	check(RegularPlay.can_add(0,c[1],true),"second concealed card allowed off battlefield")
	check(RegularPlay.add(0,c[1],true) and RegularPlay.completed(0),"two concealed cards complete off battlefield")

	#界面层：按钮条必须按最新 modes 实时重算，不能读卡位上缓存的旧值。
	#用户现象"非交战时仍不能暗置两张"就出在这里——规则允许，但第二张的
	#暗置按钮不出现，因为 _update_regular_play_bars 读的是整屏刷新时写死的缓存。
	#先实例化界面再 setup：场景的 _ready 在引擎未启动时会自己 game_start，
	#那会覆盖测试铺好的手牌与玩家数据（顺序反了三条断言全假）
	var scene=load("res://assets/scenes/game_scene/tactical_board_ui.tscn").instantiate()
	get_tree().root.add_child(scene); scene.set_process(false)
	d=setup(); d.location=MapData.magic_workshop0
	c=d.hand_cards.duplicate()
	scene._local_player_id=0
	#出掉第一张（暗置）后，第二张此刻仍应允许暗置
	check(RegularPlay.add(0,c[0],true),"UI case: first concealed card played")
	check(scene._regular_play_modes(c[1]).has(true),"UI reads live modes: second card still concealable")
	#把过期缓存写进卡位，验证每帧重算会覆盖它
	var slot:Control = Control.new()
	slot.set_meta("regular_play_card", c[1])
	slot.set_meta("regular_play_modes", [])
	scene.add_child(slot)
	var bar:HBoxContainer = HBoxContainer.new()
	bar.name = "RegularPlayModes"
	slot.add_child(bar)
	scene._update_regular_play_bars()
	check(not (slot.get_meta("regular_play_modes", []) as Array).is_empty(),
		"stale cached modes are recomputed each frame")
	scene.queue_free()

	#不在版图上（location 为空）同样不算战场
	d=setup(); d.location=null
	c=d.hand_cards.duplicate()
	check(not RegularPlay.battlefield(d),"no location is not a battlefield")

	# 暗置事件的规则声明在翻明前不可被战区查询读取；翻明后无需重新登记即可生效。
	var lock_effect:=BaseEffect.new("test_area_lock",[],0,true,false)
	var hidden_event:=BaseEvent.new("hidden_lock","",BaseNumber.new(0),[lock_effect])
	hidden_event._is_concealed=true
	MapData.miyama._events=[hidden_event]
	check(not MapAreaHasEffect.new().exec(MapData.miyama,"test_area_lock"),"concealed event effect stays inactive")
	hidden_event._is_concealed=false
	check(MapAreaHasEffect.new().exec(MapData.miyama,"test_area_lock"),"revealed event effect becomes active")
	MapData.miyama._events.clear()

	print("RESULT checks=",checks," failures=",failures)
	var f=FileAccess.open("res://battlefield_conceal_result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures})); f.close()
	get_tree().quit(0 if failures.is_empty() else 1)
