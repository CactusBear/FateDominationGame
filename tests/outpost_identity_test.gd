extends Node
# 前哨行动边界 + 控制台身份/牌区交换的回归。
# 覆盖三件事：
#  ① 前哨阶段未部署时不许结束行动，引擎不得替玩家挑席位（旧实现会偷偷部署并推进）
#  ② 更换御主/从者要支持「交换」政策：身份互换、随附状态跟着走、旧牌不整批进游戏外
#  ③ 控制台可单独交换两名玩家的牌库/手牌/弃牌堆，保留卡实例与顺序
var failures:Array=[]
var checks:int=0

func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)

func _ready(): call_deferred("run")

func owner_of(key:String, value:String) -> int:
	for raw_id in GameData.player_data_library:
		var object=GameData.player_data_library[raw_id].get(key)
		if object!=null and object._name==value: return int(raw_id)
	return -1

func id_list() -> Array:
	var ids:Array=GameData.player_data_library.keys()
	ids.sort()
	return ids

## 状态对象的每个效果都要登记在新持有者名下，否则界面上点不出对应能力
func buff_effects_ok(buff:BaseBuff, player_id:int) -> bool:
	if buff._effects.is_empty():
		return false
	for effect in buff._effects:
		if effect._trigger_player_id != player_id or not EffectManager.effect_pool.has(effect):
			return false
	return true

func run():
	var host=load("res://assets/scenes/game_scene/tactical_board_ui.tscn").instantiate()
	get_tree().root.add_child(host)
	host.set_process(false)

	# —— ① 新对局默认组合由 GameData 声明 ——
	var local:int=GameData.player_id
	var d:Dictionary=GameData.player_data_library[local]
	check(d.master!=null and d.master._name==GameData.default_master,"new local game uses the declared default master")
	check(d.servant!=null and d.servant._name==GameData.default_servant,"new local game uses the declared default servant")

	# —— ② 前哨阶段：未部署就不能结束行动 ——
	GameProgress.current_phase_index=1
	GameProgress.current_player_id=local
	GameProgress._phase_end_pending=false
	GameProgress._phase_end_running=false
	GameLog.set_context(GameProgress.current_round,"outpost")
	RemoveFromBoard.new().exec(local)
	d.magic.number=4
	var before_magic:int=d.magic.number
	check(not GameProgress.end_current_player_action(),"outpost rejects ending before deployment")
	check(d.location==null,"rejected end never secretly deploys")
	check(d.magic.number==before_magic,"rejected end never grants a seat benefit")
	check(GameProgress.current_player_id==local and GameProgress.current_phase_index==1,"rejected end preserves actor and phase")
	var loc=DeployRules.deploy_to_area(DeployRules.deployable_areas()[0],local)
	check(loc!=null,"an explicit chosen deployment still succeeds")
	check(GameProgress.end_current_player_action(),"a deployed player may end the outpost action")

	var adapter:=DebugIdentityAdapter.new()

	# —— ③ 交换御主：身份与随附状态一起对调 ——
	var rin_id:int=owner_of("master","tohsaka_rin")
	check(rin_id!=-1,"a player holds Rin after game start")
	var other:int=2 if rin_id!=2 else 3
	var rin:BaseMaster=GameData.player_data_library[rin_id].master
	var jewels:BaseBuff=rin._specials.BUFFS[0]
	check(GameData.player_data_library[rin_id].buffs.has(jewels),"Rin owner holds the jewel buff")
	# 已消耗掉一部分宝石：交换必须把这个状态原样带走，不能重建成模板层数
	jewels._buff_level.number=7
	var previous_master=GameData.player_data_library[other].master
	var out_before:int=GameData.player_data_library[other].out_of_game.attacks.size()
	var swap_master:Dictionary=adapter.set_master(other,"tohsaka_rin","swap")
	check(swap_master.ok,"master swap is accepted")
	check(GameData.player_data_library[other].master==rin,"swapping player receives Rin")
	check(GameData.player_data_library[rin_id].master==previous_master,"original holder receives the other master")
	check(GameData.player_data_library[other].buffs.has(jewels) and not GameData.player_data_library[rin_id].buffs.has(jewels),"jewel state moves with the master")
	check(jewels._buff_level.number==7,"already spent jewel levels survive the swap")
	check(buff_effects_ok(jewels,other),"jewel ability is registered to the new owner")
	check(GameData.player_data_library[other].out_of_game.attacks.size()==out_before,"master swap retires no cards")

	# —— ④ 独占/夺取也要把新御主自带的随附状态挂上（宝石点不出来就是这里漏了）——
	# 先构造确定起点：远坂凛与宝石都不属于任何人，再独占装上它
	var unload:Dictionary=adapter.unequip_master(other,"clear")
	check(unload.ok,"the other master can be unequipped first")
	check(adapter.unequip_master(rin_id,"clear").ok,"the original holder can be unequipped too")
	check(not GameData.player_data_library[rin_id].buffs.has(jewels),"the jewel starts unowned")
	var transfer:Dictionary=adapter.set_master(rin_id,"tohsaka_rin","exclusive")
	check(transfer.ok,"exclusive transfer of an unowned template is accepted")
	check(GameData.player_data_library[rin_id].buffs.has(jewels),"transfer attaches the incoming master's own buffs")
	check(buff_effects_ok(jewels,rin_id),"transfer registers the incoming master's buff effects")

	# —— ⑤ 交换从者：牌区按同名区对搬，实例与顺序保留 ——
	var saber_id:int=owner_of("servant",GameData.default_servant)
	check(saber_id!=-1,"a player holds Saber after game start")
	var partner:int=4 if saber_id!=4 else 5
	var saber:BaseServant=GameData.player_data_library[saber_id].servant
	var previous_servant=GameData.player_data_library[partner].servant
	var saber_deck:Array=GameData.player_data_library[saber_id].deck.duplicate()
	var saber_hand:Array=GameData.player_data_library[saber_id].hand_cards.duplicate()
	var partner_deck:Array=GameData.player_data_library[partner].deck.duplicate()
	var partner_hand:Array=GameData.player_data_library[partner].hand_cards.duplicate()
	var partner_out:int=GameData.player_data_library[partner].out_of_game.attacks.size()
	var swap_servant:Dictionary=adapter.set_servant(partner,GameData.default_servant,"swap","swap")
	check(swap_servant.ok,"servant swap is accepted")
	check(GameData.player_data_library[partner].servant==saber,"swapping player receives Saber")
	check(GameData.player_data_library[saber_id].servant==previous_servant,"original holder receives the other servant")
	check(GameData.player_data_library[partner].deck==saber_deck,"Saber deck transfers as the same instances in order")
	check(GameData.player_data_library[partner].hand_cards==saber_hand,"Saber hand transfers as the same instances in order")
	check(GameData.player_data_library[saber_id].deck==partner_deck,"the other deck moves back")
	check(GameData.player_data_library[saber_id].hand_cards==partner_hand,"the other hand moves back")
	check(GameData.player_data_library[partner].out_of_game.attacks.size()==partner_out,"servant swap retires no cards")

	# —— ⑥ 控制台单独交换两名玩家的牌区 ——
	var ids:Array=id_list()
	var a:int=int(ids[0])
	var b:int=int(ids[1])
	var a_deck:Array=GameData.player_data_library[a].deck.duplicate()
	var b_hand:Array=GameData.player_data_library[b].hand_cards.duplicate()
	var b_deck_before:int=GameData.player_data_library[b].deck.size()
	var card_adapter:=DebugCardAdapter.new()
	var swap:Dictionary=card_adapter.swap_zones(a,b,"deck","hand_cards")
	check(swap.ok and swap.changed,"console swaps two zones between two players")
	check(GameData.player_data_library[a].deck==b_hand,"zone swap places the other zone's exact instances")
	check(GameData.player_data_library[b].hand_cards==a_deck,"zone swap is symmetric")
	check(GameData.player_data_library[b].deck.size()==b_deck_before,"zone swap leaves other zones alone")
	# 非法参数必须在动手之前整批拒绝：不能出现"换了一半"
	var a_deck_after:Array=GameData.player_data_library[a].deck.duplicate()
	var bad:Dictionary=card_adapter.swap_zones(a,b,"deck","played_cards")
	check(not bad.ok,"unsupported zones are rejected")
	check(GameData.player_data_library[a].deck==a_deck_after,"a rejected zone swap changes nothing")
	var bad_player:Dictionary=card_adapter.swap_zones(a,999999,"deck","deck")
	check(not bad_player.ok,"unknown players are rejected")
	check(DebugValidate.validate_all().ok,"identity and zone exchanges keep debug invariants")
	print("RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
