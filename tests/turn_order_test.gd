extends Node
#顺位与实际行动顺序必须一致的回归测试。
#用户现象："言峰位于葛木之前，但葛木动了言峰才动"——顺位表显示的先后
#与真正被派发行动的先后不一致。判据：按 order 排出的名单，
#必须逐个等于 next_player_in_phase() 依次点到的玩家。
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)
func _ready(): call_deferred("run")
func run():
	EffectManager.reset_runtime(); GameLog.reset(); GameLog.set_context(1,"action")
	GameData.player_data_library.clear()
	for i in range(5):
		GameData.player_data_library[i]=GameData.new_player_data()
		GameData.player_data_library[i].is_out=false

	#故意让 order 与 id 顺序相反：id 大的排在前面。
	#这样"按 id 遍历"与"按 order 遍历"会得出不同结果，能暴露用错口径的实现
	var wanted:Array=[4,3,2,1,0]
	for i in range(wanted.size()):
		GameData.player_data_library[wanted[i]].order.set_num(BaseNumber.new(i))

	var ordered:Array = EffectManager.get_player_order_ids()
	check(ordered == wanted, "order ids follow declared order not id order")

	#顺位下标查询与名单一致
	var index_ok:bool = true
	for i in range(wanted.size()):
		if EffectManager.get_player_order_index(wanted[i]) != i:
			index_ok = false
	check(index_ok, "order index matches position in the order list")

	#实际行动顺序：逐个推进，记下每次真正轮到谁
	GameProgress.is_game_over=false
	GameProgress.current_round=1
	GameProgress.current_phase_index=2
	GameProgress.current_phase_player_index=0
	GameProgress.current_player_id=-1
	var acted:Array=[]
	for _step in range(wanted.size()):
		GameProgress.next_player_in_phase()
		if GameProgress.current_player_id == -1:
			break
		acted.append(GameProgress.current_player_id)
		#常规出牌最低要求会拦住 end_current_player_action，
		#这里只验证顺序，直接推进到下一位
	check(acted == wanted, "acting order equals the order list")

	#出局的玩家被跳过，但不改变其余人的相对先后
	GameData.player_data_library[2].is_out = true
	GameProgress.current_phase_player_index=0
	GameProgress.current_player_id=-1
	var acted2:Array=[]
	for _step in range(wanted.size()):
		GameProgress.next_player_in_phase()
		if GameProgress.current_player_id == -1:
			break
		if not acted2.has(GameProgress.current_player_id):
			acted2.append(GameProgress.current_player_id)
	check(not acted2.has(2), "an out player never gets an action")
	check(acted2 == [4,3,1,0], "remaining players keep their relative order")

	print("RESULT checks=",checks," failures=",failures)
	var f=FileAccess.open("res://turn_order_result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures})); f.close()
	get_tree().quit(0 if failures.is_empty() else 1)
