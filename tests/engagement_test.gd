extends Node
#交战状态与令咒张数限制的规则测试。
#规则出处：基础规则「若你与至少一名对手（包括玩家和NPC）一起位于一处会发生战斗的战场，
#则你处于"交战状态"，此时你无法进行常规移动」；「你常规移动时可以经过…已发生交战的战场」；
#「每名玩家拥有 3 枚令咒；每枚令咒在每局游戏中都可以使用一次…拥有同一能力的多张相同的牌
#（例如 3 张令咒）时，可以为每张卡使用一次能力」。
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)
## 清空"从 from_loc 出发、按地图链走一步"会落到的那个战区里其他玩家的席位。
## 移动类断言只关心"能不能走"，不该因为落点恰好被别人占满而随机失败
## （实测跟在其他套件之后跑时，新都常已被 GameStart 的随机部署占满）。
## 目标战区按 _linked_map_area 取，不写死战区名
func clear_destination_seats(from_loc, keep_player_id: int) -> void:
	if from_loc == null:
		return
	var from_area := from_loc.get_from() as BaseMapArea
	if from_area == null:
		return
	var dest := from_area._linked_map_area as BaseMapArea
	if dest == null:
		return
	for loc in dest._locations:
		for occupant in (loc._players as Array).duplicate():
			if occupant != keep_player_id:
				(loc._players as Array).erase(occupant)
				if GameData.player_data_library.has(occupant):
					GameData.player_data_library[occupant].location = null

## 清空全盘：所有战区的席位与所有玩家的 location 一起复位。
## 实例化界面时 GameStart 会随机部署 7 名玩家，占用目标席位并留下陈旧的 _players 记录，
## 于是"能不能移动"这类断言会随随机结果偶发失败（实测跟其他套件连跑时必现）。
## 清席位必须同时清 location：只清一边会留下"人不在席位上、但席位仍记着他"的脏状态
func _wipe_board() -> void:
	for area in MapData.areas:
		for loc in area._locations:
			(loc._players as Array).clear()
	for pid in GameData.player_data_library.keys():
		GameData.player_data_library[pid].location = null

func _ready(): call_deferred("run")
func run():
	var scene=load("res://assets/scenes/game_scene/tactical_board_ui.tscn").instantiate()
	get_tree().root.add_child(scene); scene.set_process(false)
	# UI 开局会随机放置事件；移动测试应在启动后隔离锁区等无关效果。
	EventResolver.new().clear_all()
	SituationResolver.new().clear_all()
	EffectManager.reset_runtime(); GameLog.reset(); GameLog.set_context(1,"outpost")
	GameProgress.current_round=1; GameProgress.current_phase_index=1; GameProgress.current_player_id=0

	var ids = [0,1]
	for id in ids:
		var d = GameData.player_data_library[id]
		d.is_out = false
		d.is_battle = false
		d.ignore_engagement_for_move = false
		d.magic.number = 30

	#1. 与对手同处会发生战斗的战场（深山町）＝交战
	#清空全盘再显式摆位：不能只清深山町，那会留下"人不在席位上、席位仍记着他"的脏状态
	_wipe_board()
	Deploy.new().exec(MapData.miyama0, 0)
	Deploy.new().exec(MapData.miyama2, 1)
	check(IsEngaged.new().exec(0) and IsEngaged.new().exec(1),"two players in a battle area are engaged")
	var before = GetLocation.new().exec(0)
	Move.new().exec(BaseNumber.new(1), 0)
	check(GetLocation.new().exec(0) == before,"engaged player cannot make a normal move")

	#2. 出局的玩家不再是"对手"
	GameData.player_data_library[1].is_out = true
	check(not IsEngaged.new().exec(0),"an out player is not an opponent")
	GameData.player_data_library[1].is_out = false

	#3. 效果声明可无视交战时能移动（令咒移动、言峰中立走的是同一条声明）
	_wipe_board()
	Deploy.new().exec(MapData.miyama0, 0)
	Deploy.new().exec(MapData.miyama2, 1)
	GameData.player_data_library[0].ignore_engagement_for_move = true
	check(IsEngaged.new().exec(0),"still engaged while the exemption is declared")
	before = GetLocation.new().exec(0)
	clear_destination_seats(before, 0)
	Move.new().exec(BaseNumber.new(1), 0)
	check(GetLocation.new().exec(0) != before,"declared exemption lets the player move while engaged")
	GameData.player_data_library[0].ignore_engagement_for_move = false

	#4. 不会发生战斗的战场（魔术工房、侦察）同处也不算交战
	MapData.magic_workshop0._players = []
	MapData.magic_workshop1._players = []
	MapData.scout0._players = []
	MapData.scout1._players = []
	Deploy.new().exec(MapData.magic_workshop0, 0)
	Deploy.new().exec(MapData.magic_workshop1, 1)
	check(not IsEngaged.new().exec(0),"sharing the workshop is not engagement")
	SetLocation.new().exec(MapData.scout0, 0, false)
	SetLocation.new().exec(MapData.scout1, 1, false)
	check(not IsEngaged.new().exec(0),"sharing the scout area is not engagement")

	#5. 独自位于会发生战斗的战场不算交战
	MapData.shinto0._players = []
	MapData.shinto1._players = []
	MapData.shinto2._players = []
	SetLocation.new().exec(MapData.shinto0, 0, false)
	check(not IsEngaged.new().exec(0),"alone in a battle area is not engagement")

	#6. 战场内不同席位同样算"一起"（规则里地利那段写明摆放于该位置一旁）
	SetLocation.new().exec(MapData.shinto2, 1, false)
	check(IsEngaged.new().exec(0),"different seats in the same battle area still count as together")

	#7. 令咒按张数限制：同一回合可以用不同张，张数用完即止
	var plc = GameData.player_data_library[0]
	var cards = GetPlCommandSpellOutGame.new().exec(0)
	check((cards as Array).size() > 0,"command spell data loaded")
	if (cards as Array).size() > 0:
		var eff = ((cards as Array)[0]._effects as Array)[0]
		plc.command_spell_count.number = 2
		#同一回合可以用不同张令咒：限制按张数走，不再是"每回合只能一张"
		check(EffectManager.card_state_allows(eff),"card state does not limit command spell to one per turn")
		check(EffectManager.pay_effect_cost(eff),"first command spell spent")
		check(plc.command_spell_count.number == 1,"one command spell left")
		check(EffectManager.card_state_allows(eff),"second command spell still allowed in the same turn")
		check(EffectManager.pay_effect_cost(eff),"second command spell spent in the same turn")
		check(plc.command_spell_count.number == 0,"no command spell left")
		check(not EffectManager.can_pay_effect_cost(eff),"cost unpayable without command spells")

	#8. is_battle（本回合参与过战斗结算）不再是移动判据：它不该拦住移动
	_wipe_board()
	GameData.player_data_library[0].is_battle = true
	SetLocation.new().exec(MapData.miyama2, 0, false)
	SetLocation.new().exec(MapData.shinto0, 1, false)
	check(not IsEngaged.new().exec(0),"is_battle alone does not make engagement")
	before = GetLocation.new().exec(0)
	clear_destination_seats(before, 0)
	Move.new().exec(BaseNumber.new(1), 0)
	check(GetLocation.new().exec(0) != before,"is_battle alone does not block a normal move")

	print("RESULT checks=",checks," failures=",failures)
	var f=FileAccess.open("res://engagement_test_result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures})); f.close()
	get_tree().quit(0 if failures.is_empty() else 1)
