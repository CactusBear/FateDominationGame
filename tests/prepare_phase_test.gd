extends Node
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)
func make_card(i:int) -> BaseAttack:
	return BaseAttack.new("t%d"%i,"",[],BaseNumber.new(1),BaseNumber.new(2))
func _ready(): call_deferred("run")
func run():
	EffectManager.reset_runtime(); GameLog.reset(); GameLog.set_context(1,"")
	GameData.player_data_library.clear()
	for i in range(3): GameData.player_data_library[i]=GameData.new_player_data()
	#规则：准备阶段把手牌补充到手牌上限
	var d = GameDataManager.get_player_data(0)
	d.hand_cards = []
	d.deck = [make_card(0), make_card(1), make_card(2), make_card(3)]
	d.discard = []
	check(RefillHand.new().exec(0, BaseNumber.new(3)) == 3,"refill draws up to limit")
	check(d.hand_cards.size() == 3 and d.deck.size() == 1,"hand at limit and deck reduced")
	check(RefillHand.new().exec(0, BaseNumber.new(3)) == 0,"no draw when already at limit")
	#上限由调用方传入：换个上限就按新上限补
	check(RefillHand.new().exec(0, BaseNumber.new(1)) == 0,"lower limit draws nothing")
	#规则：牌堆耗尽时把弃牌堆洗混作为新牌堆
	d.hand_cards = []
	d.deck = []
	d.discard = [make_card(4), make_card(5)]
	check(RefillHand.new().exec(0, BaseNumber.new(2)) == 2,"refill reshuffles discard when deck empty")
	check(d.hand_cards.size() == 2 and d.deck.is_empty() and d.discard.is_empty(),"cards moved out of discard")
	#两边都空：不报错也不死循环
	d.hand_cards = []
	d.deck = []
	d.discard = []
	check(RefillHand.new().exec(0, BaseNumber.new(3)) == 0,"empty deck and discard stops safely")
	check(ReshuffleDiscard.new().exec(0) == false,"reshuffle without discard returns false")
	#规则：回合结束时把御主移除版图
	MapData.miyama0._players = []
	var p1 = GameDataManager.get_player_data(1)
	p1.is_out = false
	Deploy.new().exec(MapData.miyama0, 1)
	check(p1.location == MapData.miyama0,"deployed onto the board")
	check(MapData.miyama0._players.has(1),"seat records the player")
	check(RemoveFromBoard.new().exec(1),"remove from board succeeds")
	check(p1.location == null,"location cleared")
	check(not MapData.miyama0._players.has(1),"seat no longer holds the player")
	check(RemoveFromBoard.new().exec(1) == false,"removing again reports nothing to do")
	print("RESULT checks=",checks," failures=",failures)
	var f=FileAccess.open("res://prepare_phase_result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures})); f.close()
	get_tree().quit(0 if failures.is_empty() else 1)
